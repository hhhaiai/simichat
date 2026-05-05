import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModeKey = 'theme_mode';
const _kCompressThresholdKey = 'compress_threshold';
const _kDefaultCompressThreshold = 2000;
const _kSystemPromptsKey = 'system_prompts';

/// 主题模式 Provider（持久化）
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_kThemeModeKey);
    switch (value) {
      case 'light':
        state = ThemeMode.light;
        break;
      case 'dark':
        state = ThemeMode.dark;
        break;
      default:
        state = ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }
}

/// 压缩阈值 Provider（持久化）
final compressThresholdProvider =
    StateNotifierProvider<CompressThresholdNotifier, int>((ref) {
  return CompressThresholdNotifier();
});

class CompressThresholdNotifier extends StateNotifier<int> {
  CompressThresholdNotifier() : super(_kDefaultCompressThreshold) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt(_kCompressThresholdKey) ?? _kDefaultCompressThreshold;
  }

  Future<void> setThreshold(int value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCompressThresholdKey, value);
  }
}

/// 自定义系统提示词 Provider（按会话存储）
/// key: sessionId, value: 自定义系统提示词
final systemPromptsProvider =
    StateNotifierProvider<SystemPromptsNotifier, Map<String, String>>((ref) {
  return SystemPromptsNotifier();
});

class SystemPromptsNotifier extends StateNotifier<Map<String, String>> {
  SystemPromptsNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kSystemPromptsKey);
    if (json != null) {
      final map = Map<String, String>.from(jsonDecode(json));
      state = map;
    }
  }

  /// 获取指定会话的自定义系统提示词
  String? getPrompt(String sessionId) => state[sessionId];

  /// 设置指定会话的自定义系统提示词
  Future<void> setPrompt(String sessionId, String prompt) async {
    final updated = Map<String, String>.from(state);
    if (prompt.isEmpty) {
      updated.remove(sessionId);
    } else {
      updated[sessionId] = prompt;
    }
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSystemPromptsKey, jsonEncode(updated));
  }
}
