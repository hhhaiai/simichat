import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../crypto/key_encryptor.dart';

/// S3 云备份配置。
class S3BackupConfig {
  final String endpoint;
  final String region;
  final String accessKey;
  final String secretKey;
  final String bucket;

  /// 端到端加密口令（上传前加密、下载后解密），至少 8 位且不落盘。
  final String passphrase;

  const S3BackupConfig({
    required this.endpoint,
    required this.region,
    required this.accessKey,
    required this.secretKey,
    required this.bucket,
    required this.passphrase,
  });
}

class S3BackupException implements Exception {
  final String message;
  const S3BackupException(this.message);

  @override
  String toString() => message;
}

class S3BackupEntry {
  final String key;
  final int size;
  const S3BackupEntry({required this.key, required this.size});
}

/// S3 云备份：把本地导出包用用户口令 E2E 加密后上传 / 列出 / 下载解密恢复。
///
/// 兼容 AWS S3 与 MinIO / R2 / COS 等兼容端点；使用 AWS SigV4 请求签名。
class S3BackupService {
  const S3BackupService();

  static const _aws4 = 'AWS4-HMAC-SHA256';

  void validate(S3BackupConfig config) {
    final uri = Uri.tryParse(config.endpoint);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const S3BackupException('S3 端点仅支持 HTTP(S)');
    }
    if (config.bucket.trim().isEmpty) {
      throw const S3BackupException('S3 存储桶不能为空');
    }
    if (config.passphrase.length < 8) {
      throw const S3BackupException('备份口令至少 8 位');
    }
  }

  Future<void> uploadBackup({
    required File exportFile,
    required S3BackupConfig config,
  }) async {
    validate(config);
    final bytes = await exportFile.readAsBytes();
    final encrypted = KeyEncryptor.encryptWithPassword(
      base64Encode(bytes),
      config.passphrase,
    );
    final fileName = p.basename(exportFile.path);
    final uri = _objectUri(config, fileName);
    final dio = _dio();
    try {
      await dio.put<List<int>>(
        uri.toString(),
        data: utf8.encode(encrypted),
        options: Options(
          headers: {
            'Authorization': _sigV4(
              config: config,
              method: 'PUT',
              uri: uri,
              payload: utf8.encode(encrypted),
              extraHeaders: {'content-type': 'application/octet-stream'},
            ),
            'Content-Type': 'application/octet-stream',
          },
        ),
      );
    } on DioException catch (e) {
      throw S3BackupException(_formatS3Error(e, '上传备份失败'));
    }
  }

  Future<List<S3BackupEntry>> listBackups(S3BackupConfig config) async {
    validate(config);
    // ListObjectsV2：`?list-type=2`。
    final endpointUri = Uri.parse(config.endpoint);
    final uri = Uri(
      scheme: endpointUri.scheme,
      host: endpointUri.host,
      port: endpointUri.hasPort ? endpointUri.port : null,
      pathSegments: [...endpointUri.pathSegments, config.bucket.trim()],
      queryParameters: {'list-type': '2'},
    );
    final dio = _dio();
    try {
      final response = await dio.get<String>(
        uri.toString(),
        options: Options(
          headers: {
            'Authorization': _sigV4(
              config: config,
              method: 'GET',
              uri: uri,
              payload: const [],
            ),
          },
          responseType: ResponseType.plain,
        ),
      );
      return _parseListV2(response.data ?? '');
    } on DioException catch (e) {
      throw S3BackupException(_formatS3Error(e, '列出备份失败'));
    }
  }

  Future<File> downloadBackup({
    required String key,
    required S3BackupConfig config,
    required Directory downloadDirectory,
  }) async {
    validate(config);
    final uri = _objectUri(config, key);
    final dio = _dio();
    final Uint8List encryptedBytes;
    try {
      final response = await dio.get<List<int>>(
        uri.toString(),
        options: Options(
          headers: {
            'Authorization': _sigV4(
              config: config,
              method: 'GET',
              uri: uri,
              payload: const [],
            ),
          },
          responseType: ResponseType.bytes,
        ),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const S3BackupException('远端备份为空');
      }
      encryptedBytes = Uint8List.fromList(data);
    } on DioException catch (e) {
      throw S3BackupException(_formatS3Error(e, '下载备份失败'));
    }

    final String decryptedBase64;
    try {
      decryptedBase64 = KeyEncryptor.decryptWithPassword(
        utf8.decode(encryptedBytes),
        config.passphrase,
      );
    } on FormatException {
      throw const S3BackupException('备份口令错误或文件已损坏');
    }

    final Uint8List plainBytes;
    try {
      plainBytes = base64Decode(decryptedBase64);
    } catch (_) {
      throw const S3BackupException('备份文件已损坏');
    }

    await downloadDirectory.create(recursive: true);
    final target = File(p.join(downloadDirectory.path, p.basename(key)));
    await target.writeAsBytes(plainBytes, flush: true);
    return target;
  }

  Uri _objectUri(S3BackupConfig config, String key) {
    final endpointUri = Uri.parse(config.endpoint);
    return Uri(
      scheme: endpointUri.scheme,
      host: endpointUri.host,
      port: endpointUri.hasPort ? endpointUri.port : null,
      pathSegments: [...endpointUri.pathSegments, config.bucket.trim(), key],
    );
  }

  List<S3BackupEntry> _parseListV2(String body) {
    final entries = <S3BackupEntry>[];
    if (body.trim().isEmpty) return entries;
    try {
      final doc = XmlDocument.parse(body);
      for (final content in doc.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'Contents',
      )) {
        final key = content.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'Key')
            .map((e) => e.innerText.trim())
            .firstOrNull;
        if (key == null || key.endsWith('/')) continue;
        final size =
            int.tryParse(
              content.descendants
                      .whereType<XmlElement>()
                      .where((e) => e.name.local == 'Size')
                      .map((e) => e.innerText.trim())
                      .firstOrNull ??
                  '',
            ) ??
            0;
        entries.add(S3BackupEntry(key: key, size: size));
      }
    } catch (_) {
      throw const S3BackupException('无法解析 S3 对象列表');
    }
    entries.sort((a, b) => b.key.compareTo(a.key));
    return entries;
  }

  Dio _dio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
      sendTimeout: const Duration(minutes: 5),
    ),
  );

  /// AWS SigV4 请求签名。
  String _sigV4({
    required S3BackupConfig config,
    required String method,
    required Uri uri,
    required List<int> payload,
    Map<String, String> extraHeaders = const {},
  }) {
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final dateStamp = _formatDateStamp(now);

    final canonicalUri = uri.path.isEmpty ? '/' : uri.path;
    final canonicalQuery = _canonicalQuery(uri.queryParametersAll);

    final headers = <String, String>{
      'host': _hostHeader(uri),
      'x-amz-date': amzDate,
      ...extraHeaders,
    };
    final sortedNames = headers.keys.toList()..sort();
    final canonicalHeaders = sortedNames
        .map((k) => '$k:${headers[k]!.trim()}\n')
        .join();
    final signedHeaders = sortedNames.join(';');
    final payloadHash = sha256.convert(payload).toString();

    final canonicalRequest =
        '$method\n$canonicalUri\n$canonicalQuery\n$canonicalHeaders\n$signedHeaders\n$payloadHash';

    final credentialScope = '$dateStamp/${config.region}/s3/aws4_request';
    final stringToSign =
        '$_aws4\n$amzDate\n$credentialScope\n'
        '${sha256.convert(utf8.encode(canonicalRequest))}';

    final dateKey = Hmac(
      sha256,
      utf8.encode('AWS4${config.secretKey}'),
    ).convert(utf8.encode(dateStamp)).bytes;
    final regionKey = Hmac(
      sha256,
      dateKey,
    ).convert(utf8.encode(config.region)).bytes;
    final serviceKey = Hmac(sha256, regionKey).convert(utf8.encode('s3')).bytes;
    final signingKey = Hmac(
      sha256,
      serviceKey,
    ).convert(utf8.encode('aws4_request')).bytes;
    final signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    return '$_aws4 Credential=${config.accessKey}/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
  }

  String _canonicalQuery(Map<String, List<String>> params) {
    final entries = <String>[];
    params.forEach((key, values) {
      for (final value in values) {
        entries.add('${_uriEncode(key)}=${_uriEncode(value)}');
      }
    });
    entries.sort();
    return entries.join('&');
  }

  String _hostHeader(Uri uri) =>
      uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

  String _uriEncode(String value) =>
      Uri.encodeQueryComponent(value).replaceAll('+', '%20');

  String _formatAmzDate(DateTime utc) =>
      utc.toIso8601String().replaceAll(RegExp(r'[:-]|\.\d+'), '');

  String _formatDateStamp(DateTime utc) =>
      utc.toIso8601String().substring(0, 10);

  String _formatS3Error(DioException e, String action) {
    final status = e.response?.statusCode;
    if (status != null && status >= 400) {
      switch (status) {
        case 403:
          return '$action：访问被拒绝，请检查 AccessKey / SecretKey / 桶权限（403）';
        case 404:
          return '$action：对象或桶不存在（404）';
        default:
          return '$action：HTTP $status';
      }
    }
    return '$action：${e.message ?? '网络错误'}';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
