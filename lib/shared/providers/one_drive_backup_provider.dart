import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';

const kOneDriveBackupStorageKey = 'one_drive_backup_v1';

/// OneDrive 云盘备份配置。口令（passphrase）为 E2E 密钥，不持久化。
class OneDriveBackupSettings {
  final String accessToken;
  final String folder;
  const OneDriveBackupSettings({
    this.accessToken = '',
    this.folder = 'backups',
  });

  bool get isConfigured => accessToken.trim().isNotEmpty;
}

class OneDriveBackupSettingsNotifier
    extends StateNotifier<OneDriveBackupSettings> {
  OneDriveBackupSettingsNotifier() : super(const OneDriveBackupSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kOneDriveBackupStorageKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final tokenEncrypted = json['accessTokenEncrypted'] as String? ?? '';
      state = OneDriveBackupSettings(
        accessToken: tokenEncrypted.isEmpty
            ? ''
            : KeyEncryptor.decrypt(tokenEncrypted),
        folder: json['folder'] as String? ?? 'backups',
      );
    } catch (_) {
      state = const OneDriveBackupSettings();
    }
  }

  Future<void> save(OneDriveBackupSettings next) async {
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kOneDriveBackupStorageKey,
        jsonEncode({
          'accessTokenEncrypted': next.accessToken.isEmpty
              ? ''
              : KeyEncryptor.encrypt(next.accessToken),
          'folder': next.folder.trim().isEmpty ? 'backups' : next.folder.trim(),
        }),
      );
    } catch (_) {}
  }

  Future<void> clear() async {
    state = const OneDriveBackupSettings();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kOneDriveBackupStorageKey);
    } catch (_) {}
  }
}

final oneDriveBackupSettingsProvider =
    StateNotifierProvider<
      OneDriveBackupSettingsNotifier,
      OneDriveBackupSettings
    >((ref) => OneDriveBackupSettingsNotifier());
