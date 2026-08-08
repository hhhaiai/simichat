import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../crypto/key_encryptor.dart';

/// WebDAV 云备份配置。
class WebDavBackupConfig {
  final String baseUrl;
  final String username;
  final String password;

  /// 端到端加密口令（上传前加密、下载后解密），必填且至少 8 位。
  final String passphrase;

  const WebDavBackupConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.passphrase,
  });

  String get normalizedBaseUrl {
    final value = baseUrl.trim();
    return value.endsWith('/') ? value : '$value/';
  }

  bool get isValid =>
      Uri.tryParse(normalizedBaseUrl) != null &&
      username.isNotEmpty &&
      passphrase.length >= 8;
}

class WebDavBackupException implements Exception {
  final String message;
  const WebDavBackupException(this.message);

  @override
  String toString() => message;
}

/// WebDAV 上的备份文件条目。
class WebDavBackupEntry {
  final String name;
  final int size;
  final DateTime? modifiedAt;

  const WebDavBackupEntry({
    required this.name,
    required this.size,
    this.modifiedAt,
  });
}

/// OpenAI 无关的 WebDAV 云备份：把本地导出的 `.tar.gz` 用用户口令加密后上传，
/// 可列出远端备份并下载解密恢复。
///
/// - 上传：`PUT` 单个加密文件到集合目录；
/// - 列表：`PROPFIND Depth:1` 解析 `multistatus` XML；
/// - 恢复：`GET` 下载 → 口令解密 → 落盘为可被 `DataImportService` 导入的 `.tar.gz`。
class WebDavBackupService {
  const WebDavBackupService();

  /// 校验配置。
  void validate(WebDavBackupConfig config) {
    final uri = Uri.tryParse(config.normalizedBaseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const WebDavBackupException('WebDAV 地址无效');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const WebDavBackupException('WebDAV 仅支持 HTTP(S)');
    }
    if (config.username.isEmpty) {
      throw const WebDavBackupException('WebDAV 用户名不能为空');
    }
    if (config.passphrase.length < 8) {
      throw const WebDavBackupException('备份口令至少 8 位');
    }
  }

  /// 列出远端集合目录下的备份文件（仅 `.tar.gz` 加密文件）。
  Future<List<WebDavBackupEntry>> listBackups(WebDavBackupConfig config) async {
    validate(config);
    final dio = _dioFor(config);
    try {
      final response = await dio.request<String>(
        config.normalizedBaseUrl,
        options: Options(
          method: 'PROPFIND',
          headers: {'Depth': '1', 'Content-Type': 'application/xml'},
          responseType: ResponseType.plain,
        ),
        data: _propfindBody,
      );
      return _parsePropfind(response.data);
    } on DioException catch (e) {
      throw WebDavBackupException(_formatWebDavError(e, '列出备份失败'));
    }
  }

  /// 上传一个本地导出包（已生成 `.tar.gz`），加密后 `PUT` 到远端。
  Future<void> uploadBackup({
    required File exportFile,
    required WebDavBackupConfig config,
  }) async {
    validate(config);
    final bytes = await exportFile.readAsBytes();
    final encrypted = KeyEncryptor.encryptWithPassword(
      base64Encode(bytes),
      config.passphrase,
    );
    final fileName = p.basename(exportFile.path);
    final dio = _dioFor(config);
    try {
      await dio.put(
        '${config.normalizedBaseUrl}$fileName',
        data: utf8.encode(encrypted),
        options: Options(
          headers: {'Content-Type': 'application/octet-stream'},
          // 大文件压缩包逐块流式上传，避免整体驻留内存。
        ),
      );
    } on DioException catch (e) {
      throw WebDavBackupException(_formatWebDavError(e, '上传备份失败'));
    }
  }

  /// 下载并解密远端备份，落盘到 [downloadDirectory]，返回可导入的 `.tar.gz` 文件。
  Future<File> downloadBackup({
    required String name,
    required WebDavBackupConfig config,
    required Directory downloadDirectory,
  }) async {
    validate(config);
    final dio = _dioFor(config);
    final Uint8List encryptedBytes;
    try {
      final response = await dio.get<List<int>>(
        '${config.normalizedBaseUrl}$name',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const WebDavBackupException('远端备份为空');
      }
      encryptedBytes = Uint8List.fromList(data);
    } on DioException catch (e) {
      throw WebDavBackupException(_formatWebDavError(e, '下载备份失败'));
    }

    final encryptedText = utf8.decode(encryptedBytes);
    final String decryptedBase64;
    try {
      decryptedBase64 = KeyEncryptor.decryptWithPassword(
        encryptedText,
        config.passphrase,
      );
    } on FormatException {
      throw const WebDavBackupException('备份口令错误或文件已损坏');
    }

    final Uint8List plainBytes;
    try {
      plainBytes = base64Decode(decryptedBase64);
    } catch (_) {
      throw const WebDavBackupException('备份文件已损坏');
    }

    await downloadDirectory.create(recursive: true);
    final target = File(p.join(downloadDirectory.path, name));
    await target.writeAsBytes(plainBytes, flush: true);
    return target;
  }

  static const _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:">'
      '<d:prop><d:getcontentlength/><d:getlastmodified/><d:resourcetype/></d:prop>'
      '</d:propfind>';

  List<WebDavBackupEntry> _parsePropfind(dynamic body) {
    final raw = body is String
        ? body
        : body is List && body.isNotEmpty
        ? (body.first as dynamic)?.toString() ?? ''
        : '';
    final entries = <WebDavBackupEntry>[];
    if (raw.trim().isEmpty) return entries;

    final XmlDocument document;
    try {
      document = XmlDocument.parse(raw);
    } catch (_) {
      throw const WebDavBackupException('无法解析 WebDAV 目录');
    }

    // 兼容带命名空间前缀（如 d:response）与不带前缀两种 WebDAV 响应。
    final elements = document.descendants.whereType<XmlElement>();
    final responses = elements.where((e) => e.name.local == 'response');
    for (final response in responses) {
      final descendants = response.descendants.whereType<XmlElement>();
      final href = descendants
          .where((e) => e.name.local == 'href')
          .map((e) => e.innerText.trim())
          .firstOrNull;
      if (href == null || href.endsWith('/')) continue;
      final name = Uri.decodeComponent(
        href.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => ''),
      );
      if (name.isEmpty) continue;
      final sizeText = descendants
          .where((e) => e.name.local == 'getcontentlength')
          .map((e) => e.innerText.trim())
          .firstOrNull;
      final size = int.tryParse(sizeText ?? '') ?? 0;
      final modifiedText = descendants
          .where((e) => e.name.local == 'getlastmodified')
          .map((e) => e.innerText.trim())
          .firstOrNull;
      DateTime? modifiedAt;
      if (modifiedText != null) {
        try {
          // WebDAV 规范返回 RFC 1123 格式。
          modifiedAt = HttpDate.parse(modifiedText).toLocal();
        } catch (_) {
          modifiedAt = DateTime.tryParse(modifiedText)?.toLocal();
        }
      }
      entries.add(
        WebDavBackupEntry(name: name, size: size, modifiedAt: modifiedAt),
      );
    }
    entries.sort((a, b) => b.name.compareTo(a.name));
    return entries;
  }

  Dio _dioFor(WebDavBackupConfig config) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 5),
      ),
    );
    if (config.username.isNotEmpty) {
      dio.options.headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
    }
    return dio;
  }

  String _formatWebDavError(DioException e, String action) {
    final status = e.response?.statusCode;
    if (status != null && status >= 400) {
      switch (status) {
        case 401:
        case 403:
          return '$action：WebDAV 用户名或密码无效（$status）';
        case 404:
          return '$action：远端目录不存在（$status）';
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
