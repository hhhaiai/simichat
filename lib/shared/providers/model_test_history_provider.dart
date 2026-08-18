import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/model_tester.dart';

const _kModelTestHistoryKey = 'model_test_history_v1';
const _kMaxModelTestHistoryItems = 100;

@immutable
class ModelTestHistoryItem {
  final String modelId;
  final String modelName;
  final String channelId;
  final String channelName;
  final bool success;
  final String summary;
  final String suggestion;
  final int? statusCode;
  final int attempts;
  final DateTime testedAt;

  const ModelTestHistoryItem({
    required this.modelId,
    required this.modelName,
    required this.channelId,
    required this.channelName,
    required this.success,
    required this.summary,
    required this.suggestion,
    required this.statusCode,
    this.attempts = 1,
    required this.testedAt,
  });

  factory ModelTestHistoryItem.fromResult({
    required String modelId,
    required String modelName,
    required String channelId,
    required String channelName,
    required ModelTestResult result,
    DateTime? testedAt,
  }) {
    return ModelTestHistoryItem(
      modelId: modelId,
      modelName: modelName,
      channelId: channelId,
      channelName: channelName,
      success: result.success,
      summary: _safeText(result.summary),
      suggestion: _safeText(result.suggestion),
      statusCode: result.statusCode,
      attempts: result.attempts,
      testedAt: testedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    'modelName': modelName,
    'channelId': channelId,
    'channelName': channelName,
    'success': success,
    'summary': summary,
    'suggestion': suggestion,
    'statusCode': statusCode,
    'attempts': attempts,
    'testedAt': testedAt.toIso8601String(),
  };

  static ModelTestHistoryItem fromJson(Map<String, dynamic> json) {
    return ModelTestHistoryItem(
      modelId: json['modelId'] as String? ?? '',
      modelName: json['modelName'] as String? ?? '',
      channelId: json['channelId'] as String? ?? '',
      channelName: json['channelName'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      summary: _safeText(json['summary'] as String? ?? ''),
      suggestion: _safeText(json['suggestion'] as String? ?? ''),
      statusCode: json['statusCode'] as int?,
      attempts: json['attempts'] as int? ?? 1,
      testedAt:
          DateTime.tryParse(json['testedAt'] as String? ?? '') ?? DateTime(0),
    );
  }

  String get compactStatus {
    final parts = [
      if (success) '成功' else summary.isEmpty ? '失败' : summary,
      if (!success && statusCode != null) 'HTTP $statusCode',
      if (attempts > 1) '已重试 ${attempts - 1} 次',
    ];
    return parts.join(' · ');
  }
}

final modelTestHistoryProvider =
    StateNotifierProvider<
      ModelTestHistoryNotifier,
      Map<String, ModelTestHistoryItem>
    >((ref) {
      return ModelTestHistoryNotifier();
    });

class ModelTestHistoryNotifier
    extends StateNotifier<Map<String, ModelTestHistoryItem>> {
  ModelTestHistoryNotifier() : super(const {}) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kModelTestHistoryKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List;
      final items = decoded
          .whereType<Map>()
          .map(
            (item) =>
                ModelTestHistoryItem.fromJson(item.cast<String, dynamic>()),
          )
          .where((item) => item.modelId.isNotEmpty)
          .take(_kMaxModelTestHistoryItems)
          .toList();
      state = {for (final item in items) item.modelId: item};
    } catch (_) {
      state = const {};
    }
  }

  Future<void> recordResult({
    required String modelId,
    required String modelName,
    required String channelId,
    required String channelName,
    required ModelTestResult result,
    DateTime? testedAt,
  }) async {
    await ready;
    final item = ModelTestHistoryItem.fromResult(
      modelId: modelId,
      modelName: modelName,
      channelId: channelId,
      channelName: channelName,
      result: result,
      testedAt: testedAt,
    );
    final remaining = Map<String, ModelTestHistoryItem>.from(state)
      ..remove(modelId);
    final updated = <String, ModelTestHistoryItem>{modelId: item, ...remaining};
    state = Map.unmodifiable(
      Map.fromEntries(updated.entries.take(_kMaxModelTestHistoryItems)),
    );
    await _save();
  }

  Future<void> clearModel(String modelId) async {
    await ready;
    if (!state.containsKey(modelId)) return;
    final updated = Map<String, ModelTestHistoryItem>.from(state)
      ..remove(modelId);
    state = Map.unmodifiable(updated);
    await _save();
  }

  Future<void> clearChannel(String channelId) async {
    await ready;
    final updated = Map<String, ModelTestHistoryItem>.from(state)
      ..removeWhere((_, item) => item.channelId == channelId);
    if (updated.length == state.length) return;
    state = Map.unmodifiable(updated);
    await _save();
  }

  Future<void> clearAll() async {
    await ready;
    state = const {};
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kModelTestHistoryKey,
      jsonEncode(state.values.map((item) => item.toJson()).toList()),
    );
  }
}

String _safeText(String value) {
  return value
      .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'), 'Bearer ***')
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{6,}'), 'sk-***')
      .replaceAll(RegExp(r'AIza[0-9A-Za-z_-]{10,}'), 'AIza***')
      .trim();
}

/// 正在测试中的模型 id 集合：驱动模型行的 spinner 与禁用状态，
/// 并防止同一模型并发发起多个测试请求。
final testingModelIdsProvider =
    StateNotifierProvider<TestingModelIdsNotifier, Set<String>>((ref) {
      return TestingModelIdsNotifier();
    });

class TestingModelIdsNotifier extends StateNotifier<Set<String>> {
  TestingModelIdsNotifier() : super(const <String>{});

  void start(String modelId) {
    if (state.contains(modelId)) return;
    state = {...state, modelId};
  }

  void finish(String modelId) {
    if (!state.contains(modelId)) return;
    final updated = Set<String>.from(state)..remove(modelId);
    state = updated;
  }
}
