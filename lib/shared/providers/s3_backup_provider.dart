import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';

const kS3BackupStorageKey = 's3_backup_v1';

/// S3 云备份配置。口令（passphrase）为 E2E 密钥，故意不持久化。
class S3BackupSettings {
  final String endpoint;
  final String region;
  final String accessKey;
  final String secretKey;
  final String bucket;

  const S3BackupSettings({
    this.endpoint = '',
    this.region = 'us-east-1',
    this.accessKey = '',
    this.secretKey = '',
    this.bucket = '',
  });

  bool get isConfigured =>
      endpoint.trim().isNotEmpty &&
      accessKey.trim().isNotEmpty &&
      secretKey.isNotEmpty &&
      bucket.trim().isNotEmpty;
}

class S3BackupSettingsNotifier extends StateNotifier<S3BackupSettings> {
  S3BackupSettingsNotifier() : super(const S3BackupSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kS3BackupStorageKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final secretEncrypted = json['secretKeyEncrypted'] as String? ?? '';
      state = S3BackupSettings(
        endpoint: json['endpoint'] as String? ?? '',
        region: json['region'] as String? ?? 'us-east-1',
        accessKey: json['accessKey'] as String? ?? '',
        secretKey: secretEncrypted.isEmpty
            ? ''
            : KeyEncryptor.decrypt(secretEncrypted),
        bucket: json['bucket'] as String? ?? '',
      );
    } catch (_) {
      state = const S3BackupSettings();
    }
  }

  Future<void> save(S3BackupSettings next) async {
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kS3BackupStorageKey,
        jsonEncode({
          'endpoint': next.endpoint.trim(),
          'region': next.region.trim(),
          'accessKey': next.accessKey.trim(),
          'secretKeyEncrypted': next.secretKey.isEmpty
              ? ''
              : KeyEncryptor.encrypt(next.secretKey),
          'bucket': next.bucket.trim(),
        }),
      );
    } catch (_) {}
  }

  Future<void> clear() async {
    state = const S3BackupSettings();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kS3BackupStorageKey);
    } catch (_) {}
  }
}

final s3BackupSettingsProvider =
    StateNotifierProvider<S3BackupSettingsNotifier, S3BackupSettings>(
      (ref) => S3BackupSettingsNotifier(),
    );
