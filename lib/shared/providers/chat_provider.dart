import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/ai/ai_protocol.dart' as ai;
import '../../core/ai/ai_service.dart';
import '../../core/context/context_builder.dart';
import '../../core/context/context_compressor.dart';
import '../../core/context/token_estimator.dart';
import '../../core/crypto/key_encryptor.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/channel_dao.dart';
import '../../core/notification/notification_service.dart';
import '../widgets/chat_input_bar.dart' show PendingAttachment;
import 'database_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart';

const _uuid = Uuid();

/// 每个会话的流式订阅，用于取消
final _streamSubscriptions = <String, StreamSubscription<ai.AiChunk>>{};

/// 取消当前会话的流式输出
void cancelStreaming(WidgetRef ref, String sessionId) {
  _streamSubscriptions[sessionId]?.cancel();
  _streamSubscriptions.remove(sessionId);
  ref.read(streamStateProvider(sessionId).notifier).state =
      const StreamState(isStreaming: false);
}

/// 当前会话的消息列表
final messagesProvider =
    FutureProvider.family<List<Message>, String>((ref, sessionId) {
  return ref.watch(messageDaoProvider).getMessagesBySession(sessionId);
});

/// 流式输出状态
class StreamState {
  final bool isStreaming;
  final String currentContent;
  final String currentThinking;
  final String? error;
  final bool isWaitingForFirstToken; // 发送后等待第一个 token 的状态

  const StreamState({
    this.isStreaming = false,
    this.currentContent = '',
    this.currentThinking = '',
    this.error,
    this.isWaitingForFirstToken = false,
  });

  StreamState copyWith({
    bool? isStreaming,
    String? currentContent,
    String? currentThinking,
    String? error,
    bool? isWaitingForFirstToken,
  }) {
    return StreamState(
      isStreaming: isStreaming ?? this.isStreaming,
      currentContent: currentContent ?? this.currentContent,
      currentThinking: currentThinking ?? this.currentThinking,
      error: error,
      isWaitingForFirstToken: isWaitingForFirstToken ?? this.isWaitingForFirstToken,
    );
  }
}

/// 流式输出状态 Provider
final streamStateProvider =
    StateProvider.family<StreamState, String>((ref, sessionId) {
  return const StreamState();
});

/// 发送消息
Future<void> sendMessage({
  required WidgetRef ref,
  required String sessionId,
  required String content,
  List<PendingAttachment> attachments = const [],
}) async {
  final messageDao = ref.read(messageDaoProvider);
  final sessionDao = ref.read(sessionDaoProvider);
  final channelDao = ref.read(channelDaoProvider);
  final attachmentDao = ref.read(attachmentDaoProvider);

  // 获取会话信息
  final session = await sessionDao.getSession(sessionId);
  if (session == null) return;

  // 获取模型信息
  final modelId = session.defaultChannelModelId;
  ChannelModelWithChannel? modelInfo;
  if (modelId != null) {
    modelInfo = await channelDao.getModelWithChannel(modelId);
  }
  if (modelInfo == null) {
    ref.read(streamStateProvider(sessionId).notifier).state =
        const StreamState(error: '请先选择一个模型');
    return;
  }

  // 插入用户消息
  final userMsgId = _uuid.v4();
  final userTokens = TokenEstimator.estimate(content);
  await messageDao.insertMessage(
    id: userMsgId,
    sessionId: sessionId,
    role: 'user',
    content: content,
    tokens: userTokens,
  );

  // 保存附件到数据库
  for (final att in attachments) {
    final fileSize = await File(att.path).length();
    await attachmentDao.insertAttachment(
      id: _uuid.v4(),
      messageId: userMsgId,
      fileType: att.type,
      localPath: att.path,
      fileName: att.name,
      fileSize: fileSize,
    );
  }

  await sessionDao.updateLastMessageAt(sessionId);

  // 刷新消息列表
  ref.invalidate(messagesProvider(sessionId));
  ref.invalidate(sessionsProvider);

  // 更新流式状态：等待第一个 token
  ref.read(streamStateProvider(sessionId).notifier).state =
      const StreamState(isStreaming: true, isWaitingForFirstToken: true);

  // 解密 API Key
  final apiKey = KeyEncryptor.decrypt(modelInfo.channel.apiKeyEncrypted);

  // 构建上下文（包含系统提示词）
  final customPrompt = ref.read(systemPromptsProvider.notifier).getPrompt(sessionId);
  final contextBuilder = ContextBuilder(messageDao);
  var (systemPrompt, contextMessages) = await contextBuilder.buildContext(
    sessionId,
    customSystemPrompt: customPrompt,
  );

  // 如果有附件，给最后一条 user 消息附加文件
  if (attachments.isNotEmpty) {
    final aiAttachments = <ai.Attachment>[];
    for (final att in attachments) {
      aiAttachments.add(ai.Attachment(type: att.type, path: att.path));
    }
    if (contextMessages.isNotEmpty && contextMessages.last.role == 'user') {
      final last = contextMessages.last;
      contextMessages = [
        ...contextMessages.sublist(0, contextMessages.length - 1),
        ai.AiMessage(role: last.role, content: last.content, attachments: aiAttachments),
      ];
    }
  }

  // 发送请求
  final assistantMsgId = _uuid.v4();
  final buffer = StringBuffer();
  final thinkingBuffer = StringBuffer();
  final stopwatch = Stopwatch()..start();
  final completer = Completer<void>();
  bool firstTokenReceived = false;

  final stream = AiService.sendMessage(
    protocol: modelInfo.channel.protocol,
    baseUrl: modelInfo.channel.baseUrl,
    apiKey: apiKey,
    model: modelInfo.channelModel.modelName,
    messages: contextMessages,
    systemPrompt: systemPrompt,
  );

  final subscription = stream.listen(
    (chunk) {
      if (!firstTokenReceived) {
        firstTokenReceived = true;
        ref.read(streamStateProvider(sessionId).notifier).state =
            const StreamState(isStreaming: true, isWaitingForFirstToken: false);
      }
      if (chunk.content != null) buffer.write(chunk.content);
      if (chunk.thinking != null) thinkingBuffer.write(chunk.thinking);
      ref.read(streamStateProvider(sessionId).notifier).state =
          StreamState(
            isStreaming: true,
            currentContent: buffer.toString(),
            currentThinking: thinkingBuffer.toString(),
            isWaitingForFirstToken: false,
          );
    },
    onError: (Object e) {
      if (!completer.isCompleted) {
        ref.read(streamStateProvider(sessionId).notifier).state =
            StreamState(isStreaming: false, error: e.toString());
        completer.complete();
      }
    },
    onDone: () {
      if (!completer.isCompleted) completer.complete();
    },
    cancelOnError: false,
  );

  _streamSubscriptions[sessionId] = subscription;
  await completer.future;
  _streamSubscriptions.remove(sessionId);

  stopwatch.stop();

  // 如果被取消且没有内容，直接返回
  final responseContent = buffer.toString();
  final responseThinking = thinkingBuffer.toString();
  if (responseContent.isEmpty && responseThinking.isEmpty) {
    ref.read(streamStateProvider(sessionId).notifier).state =
        const StreamState(isStreaming: false);
    return;
  }

  // 插入 AI 回复
  final responseTokens = TokenEstimator.estimate(responseContent);
  await messageDao.insertMessage(
    id: assistantMsgId,
    sessionId: sessionId,
    role: 'assistant',
    content: responseContent,
    thinkingContent: responseThinking.isNotEmpty ? responseThinking : null,
    channelModelId: modelId,
    tokens: responseTokens,
    responseMs: stopwatch.elapsedMilliseconds,
  );

  // 更新会话 token 总数
  final totalTokens = (session.totalTokens) + userTokens + responseTokens;
  await sessionDao.updateTotalTokens(sessionId, totalTokens);

  // 刷新消息列表（显示完整 AI 回复，覆盖流式内容）
  ref.read(streamStateProvider(sessionId).notifier).state =
      const StreamState(isStreaming: false);
  ref.invalidate(messagesProvider(sessionId));
  ref.invalidate(sessionsProvider);

  // 本地通知：回复完成
  unawaited(
    NotificationService().showResponseComplete(
      sessionTitle: session.title ?? '新会话',
      preview: responseContent,
    ),
  );

  // 后台任务：自动生成标题
  if (session.title == null) {
    unawaited(_generateTitle(ref, sessionId, responseContent, modelInfo));
  }

  // 后台任务：检查是否需要压缩
  final threshold = ref.read(compressThresholdProvider);
  final compressor = ContextCompressor(messageDao);
  unawaited(compressor.compressIfNeeded(
    sessionId: sessionId,
    threshold: threshold,
    protocol: modelInfo.channel.protocol,
    baseUrl: modelInfo.channel.baseUrl,
    apiKey: apiKey,
    model: modelInfo.channelModel.modelName,
  ).then((_) {
    // 压缩后刷新消息列表
    ref.invalidate(messagesProvider(sessionId));
    ref.invalidate(sessionsProvider);
  }));
}

/// 生成会话标题（后台异步，不阻塞消息流）
Future<void> _generateTitle(
  WidgetRef ref,
  String sessionId,
  String firstReply,
  ChannelModelWithChannel modelInfo,
) async {
  try {
    final apiKey = KeyEncryptor.decrypt(modelInfo.channel.apiKeyEncrypted);
    final buffer = StringBuffer();
    await for (final chunk in AiService.sendMessage(
      protocol: modelInfo.channel.protocol,
      baseUrl: modelInfo.channel.baseUrl,
      apiKey: apiKey,
      model: modelInfo.channelModel.modelName,
      messages: [
        ai.AiMessage(
          role: 'user',
          content: '请用 10 字以内概括这段对话的核心议题，只输出标题本身：\n$firstReply',
        ),
      ],
    )) {
      if (chunk.content != null) buffer.write(chunk.content);
    }
    final title = buffer.toString().trim();
    if (title.isNotEmpty) {
      await ref.read(sessionDaoProvider).updateTitle(sessionId, title);
      ref.invalidate(sessionsProvider);
      ref.invalidate(activeSessionProvider);
    }
  } catch (_) {
    // 标题生成失败不影响主流程
  }
}
