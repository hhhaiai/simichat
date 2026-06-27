import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/archive/conversation_archive_service.dart';
import '../../core/archive/markdown_conversation_archive.dart';
import 'database_provider.dart';

const _kArchiveRepairQueueKey = 'archive_repair_queue_v1';

class ArchiveRepairItem {
  final String sessionId;
  final String operation;
  final String error;
  final DateTime createdAt;

  const ArchiveRepairItem({
    required this.sessionId,
    required this.operation,
    required this.error,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'operation': operation,
    'error': error,
    'createdAt': createdAt.toIso8601String(),
  };

  static ArchiveRepairItem fromJson(Map<String, dynamic> json) {
    return ArchiveRepairItem(
      sessionId: json['sessionId'] as String? ?? '',
      operation: json['operation'] as String? ?? 'unknown',
      error: json['error'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime(0),
    );
  }
}

class ArchiveRepairResult {
  final int attempted;
  final int repaired;
  final int failed;
  final bool unsupported;

  const ArchiveRepairResult({
    required this.attempted,
    required this.repaired,
    required this.failed,
    this.unsupported = false,
  });

  bool get hasWork => attempted > 0;

  String get summary {
    if (unsupported) return '当前平台暂不支持 Markdown 档案修复';
    if (!hasWork) return '待修复队列为空';
    return '已尝试 $attempted 个会话，成功 $repaired 个，失败 $failed 个';
  }
}

@visibleForTesting
List<String> uniqueArchiveRepairSessionIds(List<ArchiveRepairItem> queue) {
  final seen = <String>{};
  final sessionIds = <String>[];
  for (final item in queue) {
    if (item.sessionId.isEmpty || seen.contains(item.sessionId)) continue;
    seen.add(item.sessionId);
    sessionIds.add(item.sessionId);
  }
  return sessionIds;
}

final archiveRepairQueueProvider =
    StateNotifierProvider<ArchiveRepairQueueNotifier, List<ArchiveRepairItem>>((
      ref,
    ) {
      return ArchiveRepairQueueNotifier();
    });

class ArchiveRepairQueueNotifier
    extends StateNotifier<List<ArchiveRepairItem>> {
  ArchiveRepairQueueNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kArchiveRepairQueueKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map(
            (item) => ArchiveRepairItem.fromJson(item.cast<String, dynamic>()),
          )
          .where((item) => item.sessionId.isNotEmpty)
          .toList();
      state = list;
    } catch (_) {
      state = const [];
    }
  }

  Future<void> recordFailure({
    required String sessionId,
    required String operation,
    required Object error,
  }) async {
    final item = ArchiveRepairItem(
      sessionId: sessionId,
      operation: operation,
      error: error.toString(),
      createdAt: DateTime.now(),
    );
    state = [
      item,
      ...state.where(
        (existing) =>
            existing.sessionId != sessionId || existing.operation != operation,
      ),
    ].take(100).toList();
    await _save();
  }

  Future<void> clearSession(String sessionId) async {
    state = state.where((item) => item.sessionId != sessionId).toList();
    await _save();
  }

  Future<void> clearAll() async {
    state = const [];
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kArchiveRepairQueueKey,
      jsonEncode(state.map((item) => item.toJson()).toList()),
    );
  }
}

Future<ConversationArchiveService?> _buildArchiveService(WidgetRef ref) async {
  if (kIsWeb) return null;
  final root = await getApplicationDocumentsDirectory();
  return ConversationArchiveService(
    archive: MarkdownConversationArchive(rootDirectory: root),
    sessionDao: ref.read(sessionDaoProvider),
    messageDao: ref.read(messageDaoProvider),
    attachmentDao: ref.read(attachmentDaoProvider),
  );
}

Future<void> syncConversationArchiveTitle(
  WidgetRef ref,
  String sessionId,
) async {
  try {
    final service = await _buildArchiveService(ref);
    await service?.syncTitle(sessionId);
  } catch (e) {
    debugPrint('[Archive] Failed to sync title: $e');
    await ref
        .read(archiveRepairQueueProvider.notifier)
        .recordFailure(sessionId: sessionId, operation: 'sync-title', error: e);
  }
}

Future<bool> rebuildConversationArchive(WidgetRef ref, String sessionId) async {
  try {
    final service = await _buildArchiveService(ref);
    final file = await service?.rebuildSession(sessionId);
    if (file == null) return false;
    await ref.read(archiveRepairQueueProvider.notifier).clearSession(sessionId);
    return true;
  } catch (e) {
    debugPrint('[Archive] Failed to rebuild session: $e');
    await ref
        .read(archiveRepairQueueProvider.notifier)
        .recordFailure(sessionId: sessionId, operation: 'rebuild', error: e);
    return false;
  }
}

Future<ArchiveRepairResult> processConversationArchiveRepairQueue(
  WidgetRef ref,
) async {
  final queue = ref.read(archiveRepairQueueProvider);
  final sessionIds = uniqueArchiveRepairSessionIds(queue);
  if (sessionIds.isEmpty) {
    return const ArchiveRepairResult(attempted: 0, repaired: 0, failed: 0);
  }
  if (kIsWeb) {
    return ArchiveRepairResult(
      attempted: sessionIds.length,
      repaired: 0,
      failed: sessionIds.length,
      unsupported: true,
    );
  }

  final ConversationArchiveService? service;
  try {
    service = await _buildArchiveService(ref);
  } catch (e) {
    final queueNotifier = ref.read(archiveRepairQueueProvider.notifier);
    for (final sessionId in sessionIds) {
      await queueNotifier.recordFailure(
        sessionId: sessionId,
        operation: 'repair',
        error: e,
      );
    }
    debugPrint('[Archive] Failed to build archive service for repair: $e');
    return ArchiveRepairResult(
      attempted: sessionIds.length,
      repaired: 0,
      failed: sessionIds.length,
    );
  }
  if (service == null) {
    return ArchiveRepairResult(
      attempted: sessionIds.length,
      repaired: 0,
      failed: sessionIds.length,
      unsupported: true,
    );
  }

  var repaired = 0;
  var failed = 0;
  final queueNotifier = ref.read(archiveRepairQueueProvider.notifier);

  for (final sessionId in sessionIds) {
    try {
      final file = await service.rebuildSession(sessionId);
      if (file == null) {
        failed++;
        await queueNotifier.recordFailure(
          sessionId: sessionId,
          operation: 'repair',
          error: '会话不存在，无法从 SQLite 重建 Markdown 档案',
        );
        continue;
      }
      repaired++;
      await queueNotifier.clearSession(sessionId);
    } catch (e) {
      failed++;
      debugPrint('[Archive] Failed to repair queued session: $e');
      await queueNotifier.recordFailure(
        sessionId: sessionId,
        operation: 'repair',
        error: e,
      );
    }
  }

  return ArchiveRepairResult(
    attempted: sessionIds.length,
    repaired: repaired,
    failed: failed,
  );
}

Future<ArchiveConsistencyReport?> checkConversationArchiveConsistency(
  WidgetRef ref,
  String sessionId,
) async {
  try {
    final service = await _buildArchiveService(ref);
    return service?.checkConsistency(sessionId);
  } catch (e) {
    debugPrint('[Archive] Failed to check session: $e');
    await ref
        .read(archiveRepairQueueProvider.notifier)
        .recordFailure(sessionId: sessionId, operation: 'check', error: e);
    return null;
  }
}
