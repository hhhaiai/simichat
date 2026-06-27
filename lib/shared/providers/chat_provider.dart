import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/attachments/attachment_policy.dart';
import '../../core/archive/markdown_conversation_archive.dart';
import '../../core/ai/ai_protocol.dart' as ai;
import '../../core/ai/model_switch_record.dart';
import '../../core/ai/openai_chat_protocol.dart' as ai_openai_chat;
import '../../core/ai/ai_service.dart';
import '../../core/context/context_builder.dart';
import '../../core/context/context_compressor.dart';
import '../../core/context/token_estimator.dart';
import '../../core/crypto/key_encryptor.dart';
import '../../core/media/audio_file_archive.dart';
import '../../core/media/audio_transcription_service.dart';
import '../../core/media/audio_transcript_archive.dart';
import '../../core/memory/key_point_memory.dart';
import '../../core/skills/skill.dart' as skill_model;
import 'mcp_provider.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/channel_dao.dart';
import '../../core/database/dao/message_dao.dart';
import '../../core/database/dao/session_dao.dart';
import '../../core/notification/notification_service.dart';
import '../widgets/chat_input_bar.dart' show PendingAttachment;
import 'audio_transcription_provider.dart';
import 'channel_provider.dart';
import 'database_provider.dart';
import 'conversation_archive_provider.dart';
import 'key_point_memory_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart';

const _uuid = Uuid();

class AudioTranscriptStatusRequest {
  final String messageId;
  final String attachmentId;

  const AudioTranscriptStatusRequest({
    required this.messageId,
    required this.attachmentId,
  });

  @override
  bool operator ==(Object other) {
    return other is AudioTranscriptStatusRequest &&
        other.messageId == messageId &&
        other.attachmentId == attachmentId;
  }

  @override
  int get hashCode => Object.hash(messageId, attachmentId);
}

final audioTranscriptStatusProvider =
    FutureProvider.family<AudioTranscriptStatus?, AudioTranscriptStatusRequest>(
      (ref, request) async {
        if (kIsWeb) return null;
        final root = await getApplicationDocumentsDirectory();
        return AudioTranscriptArchive(rootDirectory: root).readStatus(
          messageId: request.messageId,
          attachmentId: request.attachmentId,
        );
      },
    );

void _invalidateAudioTranscriptStatus(
  WidgetRef ref, {
  required String messageId,
  required String attachmentId,
}) {
  ref.invalidate(
    audioTranscriptStatusProvider(
      AudioTranscriptStatusRequest(
        messageId: messageId,
        attachmentId: attachmentId,
      ),
    ),
  );
}

/// 每个会话的流式订阅，用于取消
final _streamSubscriptions = <String, StreamSubscription<ai.AiChunk>>{};
final _cancelTokens = <String, CancelToken>{};
final _responseCompletions = <String, Completer<void>>{};

/// 取消当前会话的流式输出
void cancelStreaming(WidgetRef ref, String sessionId) {
  _cancelTokens[sessionId]?.cancel('用户取消');
  _cancelTokens.remove(sessionId);
  final completer = _responseCompletions.remove(sessionId);
  if (completer != null && !completer.isCompleted) {
    completer.complete();
  }
  _streamSubscriptions[sessionId]?.cancel();
  _streamSubscriptions.remove(sessionId);
  ref.read(streamStateProvider(sessionId).notifier).state = const StreamState(
    isStreaming: false,
  );
}

Future<void> _appendConversationArchiveMessage({
  required WidgetRef ref,
  required String sessionId,
  required String messageId,
  required String role,
  required String content,
  String? sessionTitle,
  String? thinkingContent,
  String? channelModelId,
  List<String> attachmentNames = const [],
}) async {
  if (kIsWeb) return;
  try {
    final root = await getApplicationDocumentsDirectory();
    final archive = MarkdownConversationArchive(rootDirectory: root);
    await archive.appendMessage(
      sessionId: sessionId,
      sessionTitle: sessionTitle,
      message: ArchivedMessage(
        id: messageId,
        sessionId: sessionId,
        role: role,
        content: content,
        thinkingContent: thinkingContent,
        channelModelId: channelModelId,
        attachmentNames: attachmentNames,
        createdAt: DateTime.now(),
      ),
    );
  } catch (e) {
    await ref
        .read(archiveRepairQueueProvider.notifier)
        .recordFailure(
          sessionId: sessionId,
          operation: 'append-$role',
          error: e,
        );
  }
}

Future<void> _writeAudioTranscriptDraftAndMaybeTranscribe({
  required WidgetRef ref,
  required String sessionId,
  required String messageId,
  required String attachmentId,
  required String audioPath,
  required String fileName,
  required int fileSize,
  String? transcript,
}) async {
  if (kIsWeb) return;
  final AudioTranscriptArchive archive;
  try {
    final root = await getApplicationDocumentsDirectory();
    archive = AudioTranscriptArchive(rootDirectory: root);
    await archive.writeDraft(
      messageId: messageId,
      attachmentId: attachmentId,
      fileName: fileName,
      fileSize: fileSize,
      transcript: transcript,
    );
    _invalidateAudioTranscriptStatus(
      ref,
      messageId: messageId,
      attachmentId: attachmentId,
    );
  } catch (e) {
    await ref
        .read(archiveRepairQueueProvider.notifier)
        .recordFailure(
          sessionId: sessionId,
          operation: 'audio-transcript-draft',
          error: e,
        );
    return;
  }

  final engine = ref.read(speechToTextEngineProvider);
  if (engine == null) return;

  try {
    final service = AudioTranscriptionService(archive: archive, engine: engine);
    await service.transcribeAndArchive(
      AudioTranscriptionJob(
        messageId: messageId,
        attachmentId: attachmentId,
        audioPath: audioPath,
        fileName: fileName,
        fileSize: fileSize,
      ),
    );
  } catch (e) {
    await ref
        .read(archiveRepairQueueProvider.notifier)
        .recordFailure(
          sessionId: sessionId,
          operation: 'audio-transcription',
          error: e,
        );
  } finally {
    _invalidateAudioTranscriptStatus(
      ref,
      messageId: messageId,
      attachmentId: attachmentId,
    );
  }
}

class _PreparedAttachment {
  final PendingAttachment attachment;
  final int fileSize;

  const _PreparedAttachment({required this.attachment, required this.fileSize});
}

Future<List<_PreparedAttachment>> _prepareAttachments(
  List<PendingAttachment> attachments,
) async {
  if (attachments.isEmpty) return const [];
  final prepared = <_PreparedAttachment>[];
  for (final attachment in attachments) {
    final file = File(attachment.path);
    if (!await file.exists()) {
      throw Exception('附件不存在或已移动：${attachment.name}');
    }
    final fileSize = await file.length();
    final error = validateAttachmentMetadata(
      fileName: attachment.name,
      fileType: attachment.type,
      fileSize: fileSize,
      currentCount: prepared.length,
      maxCount: kMaxAttachmentsPerMessage,
    );
    if (error != null) throw Exception(error);
    prepared.add(
      _PreparedAttachment(attachment: attachment, fileSize: fileSize),
    );
  }
  return prepared;
}

class _StoredAttachment {
  final String id;
  final String fileName;
  final String fileType;
  final String localPath;
  final int fileSize;

  const _StoredAttachment({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.localPath,
    required this.fileSize,
  });
}

Future<List<_StoredAttachment>> _storeAttachments({
  required String messageId,
  required List<_PreparedAttachment> attachments,
}) async {
  if (attachments.isEmpty) return const [];

  final stored = <_StoredAttachment>[];
  AudioFileArchive? audioArchive;
  for (final prepared in attachments) {
    final attachment = prepared.attachment;
    final attachmentId = _uuid.v4();
    var localPath = attachment.path;
    var fileSize = prepared.fileSize;

    if (!kIsWeb && attachment.type == 'audio') {
      try {
        audioArchive ??= AudioFileArchive(
          rootDirectory: await getApplicationDocumentsDirectory(),
        );
        final archived = await audioArchive.archive(
          sourcePath: attachment.path,
          messageId: messageId,
          attachmentId: attachmentId,
          fileName: attachment.name,
        );
        localPath = archived.localPath;
        fileSize = archived.fileSize;
      } catch (_) {
        throw Exception('语音文件归档失败：${attachment.name}');
      }
    }

    stored.add(
      _StoredAttachment(
        id: attachmentId,
        fileName: attachment.name,
        fileType: attachment.type,
        localPath: localPath,
        fileSize: fileSize,
      ),
    );
  }
  return stored;
}

/// 重试当前会话最后一条 user 消息
void retryLastUserMessage(WidgetRef ref, {String? sessionId}) {
  final resolvedSessionId = sessionId ?? ref.read(activeSessionIdProvider);
  if (resolvedSessionId == null) return;

  final messagesAsync = ref.read(messagesProvider(resolvedSessionId));
  messagesAsync.whenData((messages) {
    if (messages.isEmpty) return;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'user') {
        ref.read(streamStateProvider(resolvedSessionId).notifier).state =
            const StreamState();
        sendMessage(
          ref: ref,
          sessionId: resolvedSessionId,
          content: messages[i].content,
        );
        return;
      }
    }
  });
}

/// 当前会话的消息列表
final messagesProvider = FutureProvider.family<List<Message>, String>((
  ref,
  sessionId,
) {
  return ref.watch(messageDaoProvider).getMessagesBySession(sessionId);
});

final messageAttachmentsProvider =
    FutureProvider.family<List<Attachment>, String>((ref, messageId) {
      return ref
          .watch(attachmentDaoProvider)
          .getAttachmentsByMessage(messageId);
    });

class ModelSwitchResult {
  final bool changed;
  final bool recorded;
  final String message;

  const ModelSwitchResult({
    required this.changed,
    required this.recorded,
    required this.message,
  });
}

Future<ModelSwitchResult> switchConversationModel({
  required WidgetRef ref,
  required String modelId,
  required String modelLabel,
  String? previousModelId,
  String? previousModelLabel,
}) async {
  final selectedNotifier = ref.read(selectedModelIdProvider.notifier);
  final previousSelectedId = ref.read(selectedModelIdProvider);
  final activeSessionId = ref.read(activeSessionIdProvider);
  final resolvedPreviousModelId = previousModelId ?? previousSelectedId;

  if (resolvedPreviousModelId == modelId) {
    return ModelSwitchResult(
      changed: false,
      recorded: false,
      message: '已在使用 ${resolveModelSwitchLabel(modelLabel)}',
    );
  }

  var defaultModelUpdated = false;
  try {
    if (activeSessionId != null) {
      final sessionDao = ref.read(sessionDaoProvider);
      await sessionDao.updateDefaultModel(activeSessionId, modelId);
      defaultModelUpdated = true;

      final session = await sessionDao.getSession(activeSessionId);
      final content = buildModelSwitchRecordContent(
        fromLabel: previousModelLabel,
        toLabel: modelLabel,
      );
      final messageId = _uuid.v4();
      await ref
          .read(messageDaoProvider)
          .insertMessage(
            id: messageId,
            sessionId: activeSessionId,
            role: 'system',
            content: content,
            messageType: kModelSwitchMessageType,
            channelModelId: modelId,
          );
      await sessionDao.updateLastMessageAt(activeSessionId);

      unawaited(
        _appendConversationArchiveMessage(
          ref: ref,
          sessionId: activeSessionId,
          sessionTitle: session?.title,
          messageId: messageId,
          role: 'system',
          content: content,
          channelModelId: modelId,
        ),
      );

      ref.invalidate(messagesProvider(activeSessionId));
      ref.invalidate(activeSessionProvider);
      ref.invalidate(sessionsProvider);
      selectedNotifier.state = modelId;
      return ModelSwitchResult(changed: true, recorded: true, message: content);
    }

    selectedNotifier.state = modelId;
    return ModelSwitchResult(
      changed: true,
      recorded: false,
      message: '默认模型已切换为 ${resolveModelSwitchLabel(modelLabel)}',
    );
  } catch (_) {
    selectedNotifier.state = previousSelectedId;
    if (activeSessionId != null && defaultModelUpdated) {
      try {
        await ref
            .read(sessionDaoProvider)
            .updateDefaultModel(activeSessionId, resolvedPreviousModelId);
      } catch (_) {
        // 回滚失败时保持原始异常向外抛出，调用方提示用户重试。
      }
      ref.invalidate(activeSessionProvider);
      ref.invalidate(sessionsProvider);
    }
    rethrow;
  }
}

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
      isWaitingForFirstToken:
          isWaitingForFirstToken ?? this.isWaitingForFirstToken,
    );
  }
}

/// 流式输出状态 Provider
final streamStateProvider = StateProvider.family<StreamState, String>((
  ref,
  sessionId,
) {
  return const StreamState();
});

/// 发送消息（支持 MCP 工具调用循环：AI → tool_call → 执行 → AI 回复，最多 3 轮）
Future<bool> sendMessage({
  required WidgetRef ref,
  required String sessionId,
  required String content,
  String? overrideModelId,
  List<PendingAttachment> attachments = const [],
}) async {
  final messageDao = ref.read(messageDaoProvider);
  final sessionDao = ref.read(sessionDaoProvider);
  final channelDao = ref.read(channelDaoProvider);
  final attachmentDao = ref.read(attachmentDaoProvider);

  // 防止同一会话并发发送：先取消已有流
  if (_streamSubscriptions.containsKey(sessionId)) {
    cancelStreaming(ref, sessionId);
  }

  // 获取会话信息
  final session = await sessionDao.getSession(sessionId);
  if (session == null) return false;

  // 获取模型信息（支持单次覆盖）
  final modelId = overrideModelId ?? session.defaultChannelModelId;
  ChannelModelWithChannel? modelInfo;
  if (modelId != null) {
    modelInfo = await channelDao.getModelWithChannel(modelId);
  }
  if (modelInfo == null) {
    ref.read(streamStateProvider(sessionId).notifier).state = const StreamState(
      error: '请先选择一个模型',
    );
    return false;
  }

  final preparedAttachments = await _prepareAttachments(attachments);

  // 插入用户消息
  final userMsgId = _uuid.v4();
  final storedAttachments = await _storeAttachments(
    messageId: userMsgId,
    attachments: preparedAttachments,
  );
  final userTokens = TokenEstimator.estimate(content);
  await messageDao.insertMessage(
    id: userMsgId,
    sessionId: sessionId,
    role: 'user',
    content: content,
    tokens: userTokens,
  );

  // 保存附件到数据库
  for (final attachment in storedAttachments) {
    await attachmentDao.insertAttachment(
      id: attachment.id,
      messageId: userMsgId,
      fileType: attachment.fileType,
      localPath: attachment.localPath,
      fileName: attachment.fileName,
      fileSize: attachment.fileSize,
    );
    if (attachment.fileType == 'audio') {
      unawaited(
        _writeAudioTranscriptDraftAndMaybeTranscribe(
          ref: ref,
          sessionId: sessionId,
          messageId: userMsgId,
          attachmentId: attachment.id,
          audioPath: attachment.localPath,
          fileName: attachment.fileName,
          fileSize: attachment.fileSize,
          transcript: content,
        ),
      );
    }
  }

  unawaited(
    _appendConversationArchiveMessage(
      ref: ref,
      sessionId: sessionId,
      sessionTitle: session.title,
      messageId: userMsgId,
      role: 'user',
      content: content,
      attachmentNames: storedAttachments
          .map((attachment) => attachment.fileName)
          .toList(),
    ),
  );

  await sessionDao.updateLastMessageAt(sessionId);

  // 本地核心记忆点提取：只处理用户明示偏好 / 画像 / 目标等文本，
  // 结果持久化在本机，后续构建上下文时按相关性注入系统提示词。
  final memoryNotifier = ref.read(keyPointMemoryProvider.notifier);
  try {
    final extractedMemory = ref
        .read(keyPointExtractorProvider)
        .extractFromUserMessage(
          sessionId: sessionId,
          sourceMessageId: userMsgId,
          content: content,
        );
    if (extractedMemory.isNotEmpty) {
      await memoryNotifier.rememberAll(extractedMemory);
    }
  } catch (_) {
    // 记忆提取失败不能阻断聊天主路径；不要记录用户消息内容。
  }

  // 刷新消息列表
  ref.invalidate(messagesProvider(sessionId));
  ref.invalidate(sessionsProvider);

  // 解密 API Key
  final String apiKey;
  try {
    apiKey = KeyEncryptor.decrypt(modelInfo.channel.apiKeyEncrypted);
  } catch (e) {
    ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
      isStreaming: false,
      error: 'API Key 解密失败: $e',
    );
    return false;
  }

  // 构建上下文（包含系统提示词 + Skills + MCP Tools）
  final customPrompt = ref
      .read(systemPromptsProvider.notifier)
      .getPrompt(sessionId);
  final dbSkills = await ref.read(skillDaoProvider).getEnabledSkills();
  final skills = dbSkills
      .map(
        (s) => skill_model.Skill(
          id: s.id,
          name: s.name,
          description: s.description,
          instructions: s.instructions,
          sourceUrl: s.sourceUrl,
          sourceSha256: s.sourceSha256,
          sha256Verified: s.sha256Verified,
          online: s.online,
          isEnabled: s.isEnabled,
          createdAt: s.createdAt,
        ),
      )
      .toList();
  final skillsPrompt = skill_model.buildSkillsSystemPrompt(skills);
  final mcpToolsPrompt = _buildMcpToolsPrompt(ref);
  String? memoryPrompt;
  try {
    memoryPrompt = buildKeyPointMemorySystemPrompt(
      await memoryNotifier.searchRelevant(content, sessionId: sessionId),
    );
  } catch (_) {
    // 记忆检索失败时降级为无记忆上下文，避免影响正常模型请求。
    memoryPrompt = null;
  }
  final contextBuilder = ContextBuilder(messageDao);
  var (systemPrompt, contextMessages) = await contextBuilder.buildContext(
    sessionId,
    customSystemPrompt: customPrompt,
    memoryPrompt: memoryPrompt,
    skillsPrompt: skillsPrompt,
    mcpToolsPrompt: mcpToolsPrompt,
  );

  // 如果有附件，给最后一条 user 消息附加文件
  if (storedAttachments.isNotEmpty) {
    final aiAttachments = <ai.Attachment>[];
    for (final attachment in storedAttachments) {
      aiAttachments.add(
        ai.Attachment(type: attachment.fileType, path: attachment.localPath),
      );
    }
    if (contextMessages.isNotEmpty && contextMessages.last.role == 'user') {
      final last = contextMessages.last;
      contextMessages = [
        ...contextMessages.sublist(0, contextMessages.length - 1),
        ai.AiMessage(
          role: last.role,
          content: last.content,
          attachments: aiAttachments,
        ),
      ];
    }
  }

  ref.read(streamStateProvider(sessionId).notifier).state = const StreamState(
    isStreaming: true,
    isWaitingForFirstToken: true,
  );

  unawaited(
    _runAssistantResponse(
      ref: ref,
      sessionId: sessionId,
      session: session,
      messageDao: messageDao,
      sessionDao: sessionDao,
      modelId: modelId,
      modelInfo: modelInfo,
      apiKey: apiKey,
      userTokens: userTokens,
      systemPrompt: systemPrompt,
      contextMessages: contextMessages,
    ),
  );
  return true;
}

Future<void> _runAssistantResponse({
  required WidgetRef ref,
  required String sessionId,
  required Session session,
  required MessageDao messageDao,
  required SessionDao sessionDao,
  required String? modelId,
  required ChannelModelWithChannel modelInfo,
  required String apiKey,
  required int userTokens,
  required String? systemPrompt,
  required List<ai.AiMessage> contextMessages,
}) async {
  try {
    const maxToolRounds = 3;
    var toolRound = 0;
    var totalTokens = session.totalTokens + userTokens;

    while (toolRound < maxToolRounds) {
      final assistantMsgId = _uuid.v4();
      final buffer = StringBuffer();
      final thinkingBuffer = StringBuffer();
      final stopwatch = Stopwatch()..start();
      final completer = Completer<void>();
      _responseCompletions[sessionId] = completer;
      bool firstTokenReceived = false;
      final cancelToken = CancelToken();
      _cancelTokens[sessionId] = cancelToken;

      ref.read(streamStateProvider(sessionId).notifier).state =
          const StreamState(isStreaming: true, isWaitingForFirstToken: true);

      final stream = AiService.sendMessage(
        protocol: modelInfo.channel.protocol,
        baseUrl: modelInfo.channel.baseUrl,
        apiKey: apiKey,
        model: modelInfo.channelModel.modelName,
        messages: contextMessages,
        systemPrompt: systemPrompt,
        cancelToken: cancelToken,
      );

      final subscription = stream.listen(
        (chunk) {
          if (!firstTokenReceived) {
            firstTokenReceived = true;
            ref
                .read(streamStateProvider(sessionId).notifier)
                .state = const StreamState(
              isStreaming: true,
              isWaitingForFirstToken: false,
            );
          }
          if (chunk.content != null) buffer.write(chunk.content);
          if (chunk.thinking != null) thinkingBuffer.write(chunk.thinking);
          ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
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
      _cancelTokens.remove(sessionId);
      _responseCompletions.remove(sessionId);

      stopwatch.stop();

      final rawResponseContent = buffer.toString();
      final toolCalls = _parseToolCalls(rawResponseContent, ref);
      var responseContent = _stripToolCallMarkup(rawResponseContent);
      var responseThinking = thinkingBuffer.toString();

      if (responseContent.isEmpty &&
          responseThinking.isNotEmpty &&
          modelInfo.channel.protocol == 'openai_chat') {
        try {
          final fallback =
              await ai_openai_chat.OpenAiChatProtocol.fetchMessageOnce(
                baseUrl: modelInfo.channel.baseUrl,
                apiKey: apiKey,
                model: modelInfo.channelModel.modelName,
                messages: contextMessages,
                systemPrompt: systemPrompt,
                cancelToken: cancelToken,
              );
          if (fallback.content.isNotEmpty) {
            responseContent = fallback.content;
          }
          if ((responseThinking.isEmpty || responseThinking.trim().isEmpty) &&
              fallback.thinking != null &&
              fallback.thinking!.isNotEmpty) {
            responseThinking = fallback.thinking!;
          }
        } catch (_) {
          // 保持静默：这里是兜底补取，失败不应把上游异常或请求上下文写入日志。
        }
      }

      if (responseContent.isEmpty && responseThinking.isEmpty) {
        if (toolCalls.isEmpty) {
          ref.read(streamStateProvider(sessionId).notifier).state =
              const StreamState(isStreaming: false);
          return;
        }
      }

      if (toolCalls.isNotEmpty && toolRound < maxToolRounds - 1) {
        toolRound++;
        final responseTokens = TokenEstimator.estimate(responseContent);
        if (responseContent.isNotEmpty || responseThinking.isNotEmpty) {
          await messageDao.insertMessage(
            id: assistantMsgId,
            sessionId: sessionId,
            role: 'assistant',
            content: responseContent,
            thinkingContent: responseThinking.isNotEmpty
                ? responseThinking
                : null,
            channelModelId: modelId,
            tokens: responseTokens,
            responseMs: stopwatch.elapsedMilliseconds,
          );
          unawaited(
            _appendConversationArchiveMessage(
              ref: ref,
              sessionId: sessionId,
              sessionTitle: session.title,
              messageId: assistantMsgId,
              role: 'assistant',
              content: responseContent,
              thinkingContent: responseThinking.isNotEmpty
                  ? responseThinking
                  : null,
              channelModelId: modelId,
            ),
          );
        }

        final toolMessages = <ai.AiMessage>[];
        if (rawResponseContent.isNotEmpty) {
          toolMessages.add(
            ai.AiMessage(role: 'assistant', content: rawResponseContent),
          );
        }

        for (final tc in toolCalls) {
          try {
            final result = await ref
                .read(mcpManagerProvider.notifier)
                .callTool(tc.serverId, tc.toolName, tc.arguments);
            final resultText = result.content
                .where((c) => c.text != null)
                .map((c) => c.text!)
                .join('\n');
            final toolResultContent =
                '[工具结果: ${tc.toolName}]\n${resultText.isNotEmpty ? resultText : "(空结果)"}';
            final toolResultMsgId = _uuid.v4();
            await messageDao.insertMessage(
              id: toolResultMsgId,
              sessionId: sessionId,
              role: 'user',
              content: toolResultContent,
            );
            unawaited(
              _appendConversationArchiveMessage(
                ref: ref,
                sessionId: sessionId,
                sessionTitle: session.title,
                messageId: toolResultMsgId,
                role: 'user',
                content: toolResultContent,
              ),
            );
            toolMessages.add(
              ai.AiMessage(role: 'user', content: toolResultContent),
            );
          } catch (e) {
            final toolErrorContent = '[工具调用失败: ${tc.toolName}] $e';
            final toolErrorMsgId = _uuid.v4();
            await messageDao.insertMessage(
              id: toolErrorMsgId,
              sessionId: sessionId,
              role: 'user',
              content: toolErrorContent,
            );
            unawaited(
              _appendConversationArchiveMessage(
                ref: ref,
                sessionId: sessionId,
                sessionTitle: session.title,
                messageId: toolErrorMsgId,
                role: 'user',
                content: toolErrorContent,
              ),
            );
            toolMessages.add(
              ai.AiMessage(role: 'user', content: toolErrorContent),
            );
          }
        }

        contextMessages = [...contextMessages, ...toolMessages];
        totalTokens += responseTokens;
        await sessionDao.updateTotalTokens(sessionId, totalTokens);
        ref.invalidate(messagesProvider(sessionId));
        ref.invalidate(sessionsProvider);
        continue;
      }

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
      unawaited(
        _appendConversationArchiveMessage(
          ref: ref,
          sessionId: sessionId,
          sessionTitle: session.title,
          messageId: assistantMsgId,
          role: 'assistant',
          content: responseContent,
          thinkingContent: responseThinking.isNotEmpty
              ? responseThinking
              : null,
          channelModelId: modelId,
        ),
      );

      totalTokens += responseTokens;
      await sessionDao.updateTotalTokens(sessionId, totalTokens);

      ref.read(streamStateProvider(sessionId).notifier).state =
          const StreamState(isStreaming: false);
      ref.invalidate(messagesProvider(sessionId));
      ref.invalidate(sessionsProvider);

      unawaited(
        NotificationService().showResponseComplete(
          sessionTitle: session.title ?? '新会话',
          preview: responseContent,
        ),
      );

      if (session.title == null) {
        unawaited(_generateTitle(ref, sessionId, responseContent, modelInfo));
      }

      final threshold = ref.read(compressThresholdProvider);
      final compressor = ContextCompressor(messageDao);
      unawaited(
        compressor
            .compressIfNeeded(
              sessionId: sessionId,
              threshold: threshold,
              protocol: modelInfo.channel.protocol,
              baseUrl: modelInfo.channel.baseUrl,
              apiKey: apiKey,
              model: modelInfo.channelModel.modelName,
            )
            .then((_) {
              ref.invalidate(messagesProvider(sessionId));
              ref.invalidate(sessionsProvider);
            })
            .catchError((_) {}),
      );

      return;
    }
  } catch (e) {
    ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
      isStreaming: false,
      error: e.toString(),
    );
  } finally {
    _streamSubscriptions.remove(sessionId);
    _cancelTokens.remove(sessionId);
    _responseCompletions.remove(sessionId);
  }
}

/// 构建 MCP 工具描述，注入到 system prompt
String? _buildMcpToolsPrompt(WidgetRef ref) {
  final mcpManager = ref.read(mcpManagerProvider.notifier);
  final tools = mcpManager.getAllTools();
  if (tools.isEmpty) return null;

  final buf = StringBuffer();
  buf.writeln('## Available Tools (MCP)');
  buf.writeln('');
  buf.writeln(
    'You have access to the following tools provided by MCP servers. '
    'To use a tool, respond with a JSON code block in this exact format:',
  );
  buf.writeln(
    'Only use one of the exact tool names listed below. '
    'Do not invent tool names that are not in the list.',
  );
  buf.writeln('');
  buf.writeln('```tool_call');
  buf.writeln('{"tool": "<server_name>/<tool_name>", "arguments": {...}}');
  buf.writeln('```');
  buf.writeln('');
  buf.writeln('XML-style tool calls are also accepted:');
  buf.writeln(
    '<tool_call><function=tool_name><parameter=name>value</parameter></function></tool_call>',
  );
  buf.writeln('');
  buf.writeln('Available tools:');
  buf.writeln('');

  for (final entry in tools) {
    buf.writeln('### ${entry.serverName}/${entry.tool.name}');
    if (entry.tool.description != null) {
      buf.writeln(entry.tool.description);
    }
    if (entry.tool.inputSchema != null) {
      buf.writeln('Parameters: ```json\n${entry.tool.inputSchema}\n```');
    }
    buf.writeln('');
  }

  return buf.toString();
}

/// 解析 AI 回复中的 MCP 工具调用
List<_ToolCall> _parseToolCalls(String response, WidgetRef ref) {
  final mcpManager = ref.read(mcpManagerProvider.notifier);
  final allTools = mcpManager.getAllTools();
  return _parseToolCallsFromResponse(response, allTools);
}

@visibleForTesting
List<({String serverId, String toolName, Map<String, dynamic> arguments})>
parseToolCallsForTesting(String response, List<McpToolWithServer> allTools) {
  return _parseToolCallsFromResponse(response, allTools)
      .map(
        (call) => (
          serverId: call.serverId,
          toolName: call.toolName,
          arguments: call.arguments,
        ),
      )
      .toList();
}

@visibleForTesting
String stripToolCallMarkupForTesting(String response) {
  return _stripToolCallMarkup(response);
}

List<_ToolCall> _parseToolCallsFromResponse(
  String response,
  List<McpToolWithServer> allTools,
) {
  final results = <_ToolCall>[];
  final toolMap = <String, String>{};
  final toolNameMap = <String, List<McpToolWithServer>>{};
  for (final t in allTools) {
    toolMap['${t.serverName}/${t.tool.name}'] = t.serverId;
    toolNameMap.putIfAbsent(t.tool.name, () => []).add(t);
  }

  // 1) 兼容 JSON fenced code block
  final pattern = RegExp(r'```tool_call\s*\n(.*?)\n\s*```', dotAll: true);
  final matches = pattern.allMatches(response);
  for (final match in matches) {
    try {
      final jsonStr = match.group(1)!.trim();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final toolFullName = json['tool'] as String?;
      final arguments = json['arguments'] as Map<String, dynamic>? ?? {};
      if (toolFullName == null) continue;

      final parts = toolFullName.split('/');
      if (parts.length < 2) continue;
      final serverId = toolMap[toolFullName];
      if (serverId == null) continue;

      results.add(
        _ToolCall(
          serverId: serverId,
          toolName: parts.sublist(1).join('/'),
          arguments: arguments,
        ),
      );
    } catch (_) {}
  }

  // 2) 兼容 XML/标签式 tool_call
  final xmlPattern = RegExp(
    r'<tool_call>\s*(.*?)\s*</tool_call>',
    caseSensitive: false,
    dotAll: true,
  );
  final functionPattern = RegExp(
    r'<function(?:=| name=| name=")([^>"\s]+)"?>\s*(.*?)\s*</function>',
    caseSensitive: false,
    dotAll: true,
  );
  final parameterPattern = RegExp(
    r'<parameter(?:=| name=| name=")([^>"\s]+)"?>(.*?)</parameter>',
    caseSensitive: false,
    dotAll: true,
  );

  for (final callMatch in xmlPattern.allMatches(response)) {
    final callBody = callMatch.group(1)?.trim();
    if (callBody == null || callBody.isEmpty) continue;

    for (final functionMatch in functionPattern.allMatches(callBody)) {
      final rawFunctionName = functionMatch.group(1)?.trim();
      final functionBody = functionMatch.group(2) ?? '';
      if (rawFunctionName == null || rawFunctionName.isEmpty) continue;

      final arguments = <String, dynamic>{};
      for (final parameterMatch in parameterPattern.allMatches(functionBody)) {
        final key = parameterMatch.group(1)?.trim();
        final value = parameterMatch.group(2)?.trim() ?? '';
        if (key == null || key.isEmpty) continue;
        arguments[key] = value;
      }

      final normalizedFunctionName = rawFunctionName.replaceAll('"', '');
      if (normalizedFunctionName.contains('/')) {
        final serverId = toolMap[normalizedFunctionName];
        if (serverId == null) continue;
        final parts = normalizedFunctionName.split('/');
        results.add(
          _ToolCall(
            serverId: serverId,
            toolName: parts.sublist(1).join('/'),
            arguments: arguments,
          ),
        );
        continue;
      }

      final candidates = toolNameMap[normalizedFunctionName];
      if (candidates == null || candidates.isEmpty) continue;
      if (candidates.length > 1) {
        continue;
      }
      final match = candidates.single;
      results.add(
        _ToolCall(
          serverId: match.serverId,
          toolName: match.tool.name,
          arguments: arguments,
        ),
      );
    }
  }

  return results;
}

String _stripToolCallMarkup(String response) {
  var cleaned = response;
  cleaned = cleaned.replaceAll(
    RegExp(r'```tool_call\s*\n.*?\n\s*```', dotAll: true),
    '',
  );
  cleaned = cleaned.replaceAll(
    RegExp(
      r'<tool_call>\s*.*?\s*</tool_call>',
      dotAll: true,
      caseSensitive: false,
    ),
    '',
  );
  cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return cleaned.trim();
}

class _ToolCall {
  final String serverId;
  final String toolName;
  final Map<String, dynamic> arguments;

  const _ToolCall({
    required this.serverId,
    required this.toolName,
    required this.arguments,
  });
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
      unawaited(syncConversationArchiveTitle(ref, sessionId));
      ref.invalidate(sessionsProvider);
      ref.invalidate(activeSessionProvider);
    }
  } catch (_) {
    // 标题生成失败不影响主流程
  }
}
