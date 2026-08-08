import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';

/// WebDAV 云备份配置持久化 key。
const kWebDavBackupStorageKey = 'webdav_backup_v1';

/// WebDAV 云备份配置。
///
/// 口令（passphrase）是端到端加密密钥，**故意不持久化**：
/// 每次备份 / 恢复都需要用户输入，即使 App 被攻破也不会泄露备份解密口令。
class WebDavBackupSettings {
  final String baseUrl;
  final String username;
  final String password;

  const WebDavBackupSettings({
    this.baseUrl = '',
    this.username = '',
    this.password = '',
  });

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  WebDavBackupSettings copyWith({
    String? baseUrl,
    String? username,
    String? password,
  }) {
    return WebDavBackupSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}

class WebDavBackupSettingsNotifier extends StateNotifier<WebDavBackupSettings> {
  WebDavBackupSettingsNotifier() : super(const WebDavBackupSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kWebDavBackupStorageKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final passwordEncrypted = json['passwordEncrypted'] as String? ?? '';
      state = WebDavBackupSettings(
        baseUrl: json['baseUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: passwordEncrypted.isEmpty
            ? ''
            : KeyEncryptor.decrypt(passwordEncrypted),
      );
    } catch (_) {
      state = const WebDavBackupSettings();
    }
  }

  Future<void> save(WebDavBackupSettings next) async {
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kWebDavBackupStorageKey,
        jsonEncode({
          'baseUrl': next.baseUrl.trim(),
          'username': next.username.trim(),
          'passwordEncrypted': next.password.isEmpty
              ? ''
              : KeyEncryptor.encrypt(next.password),
        }),
      );
    } catch (_) {
      // 持久化失败不阻断本次使用。
    }
  }

  Future<void> clear() async {
    state = const WebDavBackupSettings();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kWebDavBackupStorageKey);
    } catch (_) {}
  }
}

final webDavBackupSettingsProvider =
    StateNotifierProvider<WebDavBackupSettingsNotifier, WebDavBackupSettings>(
      (ref) => WebDavBackupSettingsNotifier(),
    );
