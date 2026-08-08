import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../crypto/key_encryptor.dart';

/// OneDrive 云盘备份配置。
class OneDriveBackupConfig {
  final String accessToken;

  /// 备份目录（Graph 路径，如 `backups`）。
  final String folder;

  /// 端到端加密口令（不落盘）。
  final String passphrase;

  const OneDriveBackupConfig({
    required this.accessToken,
    required this.folder,
    required this.passphrase,
  });
}

class OneDriveBackupException implements Exception {
  final String message;
  const OneDriveBackupException(this.message);

  @override
  String toString() => message;
}

class OneDriveBackupEntry {
  final String name;
  final int size;
  const OneDriveBackupEntry({required this.name, required this.size});
}

/// OneDrive 云盘备份：导出包口令 E2E 加密后通过 Microsoft Graph 上传 / 列出 / 下载。
///
/// 使用用户提供的 Graph access token（需在应用内走 OAuth 或另行获取）。
class OneDriveBackupService {
  const OneDriveBackupService({String? apiBaseUrl}) : _apiBaseUrl = apiBaseUrl;

  static const kDefaultApiBaseUrl = 'https://graph.microsoft.com/v1.0';

  final String? _apiBaseUrl;

  String get _restBase {
    final base = (_apiBaseUrl ?? kDefaultApiBaseUrl).trim();
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  void validate(OneDriveBackupConfig config) {
    if (config.accessToken.trim().isEmpty) {
      throw const OneDriveBackupException('OneDrive Access Token 未配置');
    }
    if (config.passphrase.length < 8) {
      throw const OneDriveBackupException('备份口令至少 8 位');
    }
  }

  String _itemPath(OneDriveBackupConfig config, String name) {
    final folder = config.folder.trim().isEmpty
        ? 'backups'
        : config.folder.trim();
    return '/me/drive/root:/$folder/$name:';
  }

  Future<void> uploadBackup({
    required File exportFile,
    required OneDriveBackupConfig config,
  }) async {
    validate(config);
    final bytes = await exportFile.readAsBytes();
    final encrypted = KeyEncryptor.encryptWithPassword(
      base64Encode(bytes),
      config.passphrase,
    );
    final name = p.basename(exportFile.path);
    final dio = _dioFor(config);
    try {
      await dio.put<List<int>>(
        '$_restBase${_itemPath(config, name)}/content',
        data: utf8.encode(encrypted),
        options: Options(headers: {'Content-Type': 'application/octet-stream'}),
      );
    } on DioException catch (e) {
      throw OneDriveBackupException(_formatError(e, '上传备份失败'));
    }
  }

  Future<List<OneDriveBackupEntry>> listBackups(
    OneDriveBackupConfig config,
  ) async {
    validate(config);
    final folder = config.folder.trim().isEmpty
        ? 'backups'
        : config.folder.trim();
    final dio = _dioFor(config);
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '$_restBase/me/drive/root:/$folder:/children',
        options: Options(responseType: ResponseType.json),
      );
      final values = response.data?['value'];
      if (values is! List) return const [];
      return values
          .whereType<Map>()
          .map(
            (item) => OneDriveBackupEntry(
              name: item['name']?.toString() ?? '',
              size: item['size'] is int ? (item['size'] as int) : 0,
            ),
          )
          .where((e) => e.name.endsWith('.tar.gz'))
          .toList(growable: false);
    } on DioException catch (e) {
      throw OneDriveBackupException(_formatError(e, '列出备份失败'));
    }
  }

  Future<File> downloadBackup({
    required String name,
    required OneDriveBackupConfig config,
    required Directory downloadDirectory,
  }) async {
    validate(config);
    final dio = _dioFor(config);
    final Uint8List encryptedBytes;
    try {
      final response = await dio.get<List<int>>(
        '$_restBase${_itemPath(config, name)}/content',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const OneDriveBackupException('远端备份为空');
      }
      encryptedBytes = Uint8List.fromList(data);
    } on DioException catch (e) {
      throw OneDriveBackupException(_formatError(e, '下载备份失败'));
    }

    final String decryptedBase64;
    try {
      decryptedBase64 = KeyEncryptor.decryptWithPassword(
        utf8.decode(encryptedBytes),
        config.passphrase,
      );
    } on FormatException {
      throw const OneDriveBackupException('备份口令错误或文件已损坏');
    }

    final Uint8List plainBytes;
    try {
      plainBytes = base64Decode(decryptedBase64);
    } catch (_) {
      throw const OneDriveBackupException('备份文件已损坏');
    }

    await downloadDirectory.create(recursive: true);
    final target = File(p.join(downloadDirectory.path, name));
    await target.writeAsBytes(plainBytes, flush: true);
    return target;
  }

  Dio _dioFor(OneDriveBackupConfig config) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 5),
      ),
    );
    dio.options.headers['Authorization'] =
        'Bearer ${config.accessToken.trim()}';
    return dio;
  }

  String _formatError(DioException e, String action) {
    final status = e.response?.statusCode;
    if (status != null && status >= 400) {
      switch (status) {
        case 401:
          return '$action：Access Token 无效或已过期（401）';
        case 403:
          return '$action：无权限访问该目录（403）';
        default:
          return '$action：HTTP $status';
      }
    }
    return '$action：${e.message ?? '网络错误'}';
  }
}
