import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/memory/key_point_memory.dart';

const kKeyPointMemoryStorageKey = 'key_point_memory_v1';
const _kMaxKeyPointMemoryItems = 300;

final keyPointExtractorProvider = Provider<KeyPointExtractor>(
  (ref) => const KeyPointExtractor(),
);

final keyPointMemoryProvider =
    StateNotifierProvider<KeyPointMemoryNotifier, List<KeyPointMemoryItem>>(
      (ref) => KeyPointMemoryNotifier(),
    );

class KeyPointMemoryNotifier extends StateNotifier<List<KeyPointMemoryItem>>
    implements KeyPointMemoryStore {
  KeyPointMemoryNotifier({String storageKey = kKeyPointMemoryStorageKey})
    : _storageKey = storageKey,
      super(const []) {
    ready = _load();
  }

  final String _storageKey;
  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = decodeKeyPointMemoryItems(prefs.getString(_storageKey));
  }

  @override
  Future<List<KeyPointMemoryItem>> load() async {
    await ready;
    return state;
  }

  @override
  Future<List<KeyPointMemoryItem>> rememberAll(
    List<KeyPointMemoryItem> items,
  ) async {
    await ready;
    if (items.isEmpty) return state;

    final existing = {for (final item in state) item.id: item};
    for (final item in items) {
      final old = existing[item.id];
      existing[item.id] = old == null
          ? item
          : item.copyWith(
              createdAt: old.createdAt,
              lastUsedAt: old.lastUsedAt,
              confidence: item.confidence > old.confidence
                  ? item.confidence
                  : old.confidence,
            );
    }

    final sorted = existing.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = List.unmodifiable(sorted.take(_kMaxKeyPointMemoryItems));
    await _save();
    return state;
  }

  @override
  Future<List<KeyPointMemoryItem>> searchRelevant(
    String query, {
    String? sessionId,
    int limit = 8,
  }) async {
    await ready;
    final results = rankRelevantKeyPoints(
      state,
      query,
      sessionId: sessionId,
      limit: limit,
    );
    if (results.isNotEmpty) {
      final now = DateTime.now();
      final usedIds = results.map((item) => item.id).toSet();
      state = List.unmodifiable(
        state.map((item) {
          if (!usedIds.contains(item.id)) return item;
          return item.copyWith(lastUsedAt: now);
        }),
      );
      await _save();
    }
    return results;
  }

  Future<void> clearAll() async {
    await ready;
    state = const [];
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, encodeKeyPointMemoryItems(state));
  }
}
