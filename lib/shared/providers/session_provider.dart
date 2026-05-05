import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/app_database.dart';
import 'database_provider.dart';
import 'channel_provider.dart';

const _uuid = Uuid();

/// 所有会话列表
final sessionsProvider = FutureProvider<List<Session>>((ref) {
  return ref.watch(sessionDaoProvider).getAllSessions();
});

/// 按文件夹筛选的会话
final sessionsByFolderProvider =
    FutureProvider.family<List<Session>, String>((ref, folderId) {
  return ref.watch(sessionDaoProvider).getSessionsByFolder(folderId);
});

/// 搜索会话
final sessionSearchProvider =
    FutureProvider.family<List<Session>, String>((ref, query) {
  if (query.isEmpty) return Future.value([]);
  return ref.watch(sessionDaoProvider).searchSessions(query);
});

/// 当前活跃会话 ID
final activeSessionIdProvider = StateProvider<String?>((ref) => null);

/// 当前活跃会话详情
final activeSessionProvider = FutureProvider<Session?>((ref) {
  final id = ref.watch(activeSessionIdProvider);
  if (id == null) return Future.value(null);
  return ref.watch(sessionDaoProvider).getSession(id);
});

/// 刷新会话列表
void refreshSessions(WidgetRef ref) {
  ref.invalidate(sessionsProvider);
  ref.invalidate(activeSessionProvider);
}

/// 创建新会话并设为活跃
Future<String> createNewSession(WidgetRef ref) async {
  final sessionDao = ref.read(sessionDaoProvider);
  final selectedModelId = ref.read(selectedModelIdProvider);
  final id = _uuid.v4();
  await sessionDao.createSession(id: id, defaultChannelModelId: selectedModelId);
  ref.read(activeSessionIdProvider.notifier).state = id;
  refreshSessions(ref);
  return id;
}

/// 复制会话（Fork）：创建新会话，复制指定消息 ID 之前的所有消息
Future<String> forkSession({
  required WidgetRef ref,
  required String sourceSessionId,
  required String upToMessageId,
}) async {
  final sessionDao = ref.read(sessionDaoProvider);
  final messageDao = ref.read(messageDaoProvider);

  // 读取源会话
  final sourceSession = await sessionDao.getSession(sourceSessionId);
  if (sourceSession == null) throw Exception('源会话不存在');

  // 读取源会话的所有消息
  final allMessages = await messageDao.getMessagesBySession(sourceSessionId);

  // 找到 upToMessageId 的位置（包含该消息）
  int endIndex = allMessages.indexWhere((m) => m.id == upToMessageId);
  if (endIndex == -1) endIndex = allMessages.length - 1;
  final messagesToCopy = allMessages.sublist(0, endIndex + 1);

  // 创建新会话
  final newSessionId = _uuid.v4();
  await sessionDao.createSession(
    id: newSessionId,
    defaultChannelModelId: sourceSession.defaultChannelModelId,
  );

  // 复制消息
  for (final msg in messagesToCopy) {
    await messageDao.insertMessage(
      id: _uuid.v4(),
      sessionId: newSessionId,
      role: msg.role,
      content: msg.content,
      thinkingContent: msg.thinkingContent,
      messageType: msg.messageType,
      channelModelId: msg.channelModelId,
      tokens: msg.tokens,
    );
  }

  // 更新标题
  final forkTitle = sourceSession.title != null
      ? '${sourceSession.title} (副本)'
      : '副本';
  await sessionDao.updateTitle(newSessionId, forkTitle);

  // 切换到新会话
  ref.read(activeSessionIdProvider.notifier).state = newSessionId;
  refreshSessions(ref);

  return newSessionId;
}
