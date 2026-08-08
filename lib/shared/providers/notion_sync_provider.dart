import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';

/// Notion 同步配置持久化 key。
const kNotionSyncStorageKey = 'notion_sync_v1';

class NotionSyncSettings {
  final String token;
  final String parentPageId;
  const NotionSyncSettings({this.token = '', this.parentPageId = ''});

  bool get isConfigured =>
      token.trim().isNotEmpty && parentPageId.trim().isNotEmpty;
}

class NotionSyncSettingsNotifier extends StateNotifier<NotionSyncSettings> {
  NotionSyncSettingsNotifier() : super(const NotionSyncSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kNotionSyncStorageKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final tokenEncrypted = json['tokenEncrypted'] as String? ?? '';
      state = NotionSyncSettings(
        token: tokenEncrypted.isEmpty
            ? ''
            : KeyEncryptor.decrypt(tokenEncrypted),
        parentPageId: json['parentPageId'] as String? ?? '',
      );
    } catch (_) {
      state = const NotionSyncSettings();
    }
  }

  Future<void> save(NotionSyncSettings next) async {
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kNotionSyncStorageKey,
        jsonEncode({
          'tokenEncrypted': next.token.isEmpty
              ? ''
              : KeyEncryptor.encrypt(next.token),
          'parentPageId': next.parentPageId.trim(),
        }),
      );
    } catch (_) {}
  }

  Future<void> clear() async {
    state = const NotionSyncSettings();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kNotionSyncStorageKey);
    } catch (_) {}
  }
}

final notionSyncSettingsProvider =
    StateNotifierProvider<NotionSyncSettingsNotifier, NotionSyncSettings>(
      (ref) => NotionSyncSettingsNotifier(),
    );
