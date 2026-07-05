import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModeKey = 'theme_mode';
const _kCompressThresholdKey = 'compress_threshold';
const _kFontScaleKey = 'font_scale';
const _kSemanticSearchEnabledKey = 'semantic_search_enabled';
const _kDefaultCompressThreshold = 2000;
const double kDefaultFontScale = 1.0;
const double kMinFontScale = 0.90;
const double kMaxFontScale = 1.20;
const _kSystemPromptsKey = 'system_prompts';

/// 主题模式 Provider（持久化）
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
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

double normalizeFontScale(double value) {
  if (value.isNaN || value.isInfinite) return kDefaultFontScale;
  return value.clamp(kMinFontScale, kMaxFontScale).toDouble();
}

String formatFontScale(double value) {
  return '${(normalizeFontScale(value) * 100).round()}%';
}

/// 全局字体缩放 Provider（持久化）
final fontScaleProvider = StateNotifierProvider<FontScaleNotifier, double>((
  ref,
) {
  return FontScaleNotifier();
});

class FontScaleNotifier extends StateNotifier<double> {
  FontScaleNotifier() : super(kDefaultFontScale) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = normalizeFontScale(
      prefs.getDouble(_kFontScaleKey) ?? kDefaultFontScale,
    );
  }

  Future<void> setFontScale(double value) async {
    state = normalizeFontScale(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFontScaleKey, state);
  }

  Future<void> reset() => setFontScale(kDefaultFontScale);
}

/// 本地语义搜索开关 Provider（持久化）
final semanticSearchEnabledProvider =
    StateNotifierProvider<SemanticSearchEnabledNotifier, bool>((ref) {
      return SemanticSearchEnabledNotifier();
    });

class SemanticSearchEnabledNotifier extends StateNotifier<bool> {
  SemanticSearchEnabledNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kSemanticSearchEnabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSemanticSearchEnabledKey, value);
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
