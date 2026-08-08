import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 替身回复授权持久化 key。
const kPersonaAuthorizationKey = 'persona_reply_authorized_v1';

/// 替身回复授权状态。
///
/// 替身回复代表用户本人对外以镜像人格发言，必须用户**显式授权**。
/// 记录授权时间便于审计；未授权时 [authorized] 为 false。
class PersonaAuthorization {
  final bool authorized;
  final String? authorizedAtIso;

  const PersonaAuthorization({required this.authorized, this.authorizedAtIso});

  bool get isAuthorized => authorized;
}

class PersonaAuthorizationNotifier extends StateNotifier<PersonaAuthorization> {
  PersonaAuthorizationNotifier()
    : super(const PersonaAuthorization(authorized: false)) {
    _load();
  }

  /// 用户是否已手动修改过授权状态（防止异步 _load 覆盖用户操作）。
  bool _userModified = false;

  final _ready = Completer<void>();

  /// 等待初始化读取完成（测试用）。
  Future<void> get ready => _ready.future;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kPersonaAuthorizationKey);
      if (raw != null && raw.isNotEmpty && !_userModified) {
        state = PersonaAuthorization(authorized: true, authorizedAtIso: raw);
      }
    } catch (_) {
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  /// 显式授权（记录当前时间）。
  Future<void> authorize() async {
    _userModified = true;
    final now = DateTime.now().toIso8601String();
    state = PersonaAuthorization(authorized: true, authorizedAtIso: now);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPersonaAuthorizationKey, now);
    } catch (_) {}
  }

  /// 撤销授权。
  Future<void> revoke() async {
    _userModified = true;
    state = const PersonaAuthorization(authorized: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kPersonaAuthorizationKey);
    } catch (_) {}
  }
}

final personaAuthorizationProvider =
    StateNotifierProvider<PersonaAuthorizationNotifier, PersonaAuthorization>(
      (ref) => PersonaAuthorizationNotifier(),
    );
