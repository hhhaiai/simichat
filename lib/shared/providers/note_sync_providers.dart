import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';

const kYuqueSyncStorageKey = 'yuque_sync_v1';
const kSiyuanSyncStorageKey = 'siyuan_sync_v1';

class YuqueSyncSettings {
  final String token;
  final String namespace;
  const YuqueSyncSettings({this.token = '', this.namespace = ''});

  bool get isConfigured =>
      token.trim().isNotEmpty && namespace.trim().isNotEmpty;
}

class SiyuanSyncSettings {
  final String baseUrl;
  final String token;
  final String notebook;
  const SiyuanSyncSettings({
    this.baseUrl = '',
    this.token = '',
    this.notebook = '',
  });

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty &&
      token.trim().isNotEmpty &&
      notebook.trim().isNotEmpty;
}

/// 通用加密配置存储：把敏感字段用 KeyEncryptor 加密后以 JSON 持久化。
class EncryptedSettingsStore<T> {
  const EncryptedSettingsStore(this._key);

  final String _key;
  final List<String> _sensitiveFields = const ['token', 'password'];

  Future<T?> load(
    T Function(Map<String, dynamic> raw) fromRaw,
    T Function() empty,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return empty();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      for (final field in _sensitiveFields) {
        final encrypted = json['${field}Encrypted'] as String?;
        if (encrypted != null && encrypted.isNotEmpty) {
          json[field] = KeyEncryptor.decrypt(encrypted);
        }
      }
      return fromRaw(json);
    } catch (_) {
      return empty();
    }
  }

  Future<void> save(
    Map<String, dynamic> json, {
    required List<String> sensitive,
  }) async {
    final copy = Map<String, dynamic>.from(json);
    for (final field in sensitive) {
      final value = copy[field];
      if (value is String && value.isNotEmpty) {
        copy['${field}Encrypted'] = KeyEncryptor.encrypt(value);
      }
      copy.remove(field);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(copy));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}

class YuqueSyncNotifier extends StateNotifier<YuqueSyncSettings> {
  YuqueSyncNotifier() : super(const YuqueSyncSettings()) {
    _store
        .load(
          (raw) => YuqueSyncSettings(
            token: raw['token'] as String? ?? '',
            namespace: raw['namespace'] as String? ?? '',
          ),
          () => const YuqueSyncSettings(),
        )
        .then((value) {
          if (value != null) state = value;
        });
  }

  final _store = const EncryptedSettingsStore<YuqueSyncSettings>(
    kYuqueSyncStorageKey,
  );

  Future<void> save(YuqueSyncSettings next) async {
    state = next;
    await _store.save(
      {'namespace': next.namespace, 'token': next.token},
      sensitive: ['token'],
    );
  }

  Future<void> clear() async {
    state = const YuqueSyncSettings();
    await _store.clear();
  }
}

class SiyuanSyncNotifier extends StateNotifier<SiyuanSyncSettings> {
  SiyuanSyncNotifier() : super(const SiyuanSyncSettings()) {
    const EncryptedSettingsStore<SiyuanSyncSettings>(kSiyuanSyncStorageKey)
        .load(
          (raw) => SiyuanSyncSettings(
            baseUrl: raw['baseUrl'] as String? ?? '',
            token: raw['token'] as String? ?? '',
            notebook: raw['notebook'] as String? ?? '',
          ),
          () => const SiyuanSyncSettings(),
        )
        .then((value) {
          if (value != null) state = value;
        });
  }

  final _store = const EncryptedSettingsStore<SiyuanSyncSettings>(
    kSiyuanSyncStorageKey,
  );

  Future<void> save(SiyuanSyncSettings next) async {
    state = next;
    await _store.save(
      {'baseUrl': next.baseUrl, 'notebook': next.notebook, 'token': next.token},
      sensitive: ['token'],
    );
  }

  Future<void> clear() async {
    state = const SiyuanSyncSettings();
    await _store.clear();
  }
}

final yuqueSyncProvider =
    StateNotifierProvider<YuqueSyncNotifier, YuqueSyncSettings>(
      (ref) => YuqueSyncNotifier(),
    );

final siyuanSyncProvider =
    StateNotifierProvider<SiyuanSyncNotifier, SiyuanSyncSettings>(
      (ref) => SiyuanSyncNotifier(),
    );
