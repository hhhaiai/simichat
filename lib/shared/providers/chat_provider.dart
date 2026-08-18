import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/attachments/attachment_policy.dart';
import '../../core/archive/archive_attachment_path.dart';
import '../../core/archive/markdown_conversation_archive.dart';
import '../../core/ai/ai_protocol.dart' as ai;
import '../../core/ai/attachment_helper.dart';
import '../../core/ai/file_content_extractor.dart';
import '../../core/ai/image_generation_service.dart';
import '../../core/ai/image_generation_task.dart';
import '../../core/ai/universal_media_service.dart';
import '../../core/ai/model_capability.dart';
import '../../core/ai/model_switch_record.dart';
import '../../core/ai/openai_chat_protocol.dart' as ai_openai_chat;
import '../../core/ai/ai_service.dart';
import '../../core/context/context_budget_trimmer.dart';
import '../../core/context/context_builder.dart';
import '../../core/context/context_compressor.dart';
import '../../core/context/model_context_budget.dart';
import '../../core/context/token_estimator.dart';
import '../../core/crypto/key_encryptor.dart';
import '../../core/media/audio_file_archive.dart';
import '../../core/media/baidu_cdn_image_uploader.dart';
import '../../core/media/attachment_export_service.dart';
import '../../core/media/inline_base64_audio.dart';
import '../../core/media/audio_transcription_service.dart';
import '../../core/media/audio_transcript_archive.dart';
import '../../core/media/native_speech_to_text_engine.dart';
import '../../core/media/openai_speech_to_text_engine.dart';
import '../../core/media/openai_text_to_speech_engine.dart';
import '../../core/media/speech_provider_preset.dart';
import '../../core/media/text_to_speech_service.dart';
import '../../core/storage/atomic_file_writer.dart';
import '../../core/memory/key_point_memory.dart';
import '../../core/memory/reflection_service.dart';
import '../../core/memory/user_profile.dart';
import '../../core/twin/persona_profile.dart';
import '../../core/skills/skill.dart' as skill_model;
import 'mcp_provider.dart';
import 'persona_provider.dart';
import 'user_profile_provider.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/channel_dao.dart';
import '../../core/database/dao/message_dao.dart';
import '../../core/database/dao/media_job_dao.dart' as media_database;
import '../../core/database/dao/persona_audit_log_dao.dart';
import '../../core/database/dao/session_dao.dart';
import '../../core/notification/notification_service.dart';
import '../widgets/chat_input_bar.dart' show PendingAttachment;
import 'audio_transcription_provider.dart';
import 'channel_provider.dart';
import 'database_provider.dart';
import 'conversation_archive_provider.dart';
import 'image_generation_provider.dart';
import 'universal_media_provider.dart';
import 'universal_media_recovery_provider.dart';
import 'key_point_memory_provider.dart';
import 'reflection_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart';
import 'image_generation_tasks_provider.dart';
import 'text_to_speech_provider.dart';

const _uuid = Uuid();
const kAudioOnlyMessagePrompt = '语音转文字未得到可用结果。请提示用户检查 STT 音频接口配置，或重新录制更清晰的语音。';
const _sttNotConfiguredMessage =
    '未配置语音转文字 STT，且当前模型渠道不支持自动复用 OpenAI 兼容音频接口。请在设置里的语音输入中配置 STT。';
const _audioTranscriptInstruction = '以下是语音转文字结果，请根据这个语音内容回答：';
const _contextLimitUserMessage =
    '当前对话上下文超过了模型限制。已自动优先保留最新问题并裁剪较早历史；如果仍失败，请切换更大上下文模型，或降低长文档 / 工具说明 / 历史消息长度后重试。';

@visibleForTesting
String? initialAudioTranscriptText(String content) {
  final trimmed = content.trim();
  return trimmed.isEmpty ? null : trimmed;
}

@visibleForTesting
String audioAwareMessageContent({
  required String content,
  required bool hasAudioAttachment,
  String? audioTranscript,
}) {
  if (!hasAudioAttachment) return content;
  final normalizedContent = content.trim();
  final normalizedTranscript = audioTranscript?.trim();
  if (normalizedTranscript != null && normalizedTranscript.isNotEmpty) {
    final buffer = StringBuffer();
    if (normalizedContent.isNotEmpty) {
      buffer
        ..writeln(normalizedContent)
        ..writeln();
    }
    buffer
      ..writeln(_audioTranscriptInstruction)
      ..write(normalizedTranscript);
    return buffer.toString();
  }
  if (normalizedContent.isNotEmpty) {
    return '$normalizedContent\n\n$kAudioOnlyMessagePrompt';
  }
  return kAudioOnlyMessagePrompt;
}

const _fileContentContextInstruction = '以下是用户附加的文本文件实际内容：';

/// Binds successfully extracted document text to this request only.
///
/// The persisted user message remains the user's original text, so extracted
/// file contents do not enter long-term memory, message search, or the
/// Markdown archive.  Keeping this transformation pure also means retries
/// always start from the original message and cannot append the same document
/// repeatedly.
@visibleForTesting
String fileAwareMessageContent({
  required String content,
  required Iterable<String> extractedContents,
}) {
  final uniqueContents = <String>[];
  final seen = <String>{};
  for (final rawContent in extractedContents) {
    final normalized = rawContent.trim();
    if (normalized.isEmpty || !seen.add(normalized)) continue;
    uniqueContents.add(normalized);
  }
  if (uniqueContents.isEmpty) return content;

  final normalizedMessage = content.trim();
  final buffer = StringBuffer();
  if (normalizedMessage.isNotEmpty) {
    buffer
      ..write(normalizedMessage)
      ..write('\n\n');
  }
  buffer.writeln(_fileContentContextInstruction);
  for (var index = 0; index < uniqueContents.length; index++) {
    if (index > 0) buffer.writeln('\n---');
    buffer
      ..writeln('---')
      ..writeln(uniqueContents[index])
      ..write('---');
  }
  return buffer.toString();
}

@visibleForTesting
bool canUseChannelSpeechToTextFallback(String protocol) {
  return protocol == 'openai_chat' || protocol == 'openai_response';
}

@visibleForTesting
bool canUseChannelImageGeneration(String protocol) {
  return protocol == 'openai_chat' || protocol == 'openai_response';
}

/// 视频 / 音乐等通用媒体接口默认复用 OpenAI-compatible HTTP 渠道。
/// endpoint 本身可在设置中替换，因此不绑定具体厂商品牌或模型名。
@visibleForTesting
bool canUseChannelUniversalMedia(String protocol) {
  return protocol == 'openai_chat' || protocol == 'openai_response';
}

/// Composer 中通用视频 / 音乐动作的能力判定结果。
///
/// 通用媒体接口复用当前聊天渠道的 Base URL / Key，但这不等于所有渠道
/// 或所有模型都声明了媒体能力。UI 只能展示明确可用的动作；检测尚未
/// 完成时使用 [checking]，配置缺失与渠道 / 模型不适配则分别给出可操作
/// 的禁用原因。
enum UniversalMediaCapabilityStatus {
  available,
  checking,
  notConfigured,
  unavailable,
}

class UniversalMediaCapability {
  const UniversalMediaCapability({required this.status, required this.message});

  final UniversalMediaCapabilityStatus status;
  final String message;

  bool get isAvailable => status == UniversalMediaCapabilityStatus.available;
}

String _universalMediaKindLabel(UniversalMediaKind kind) {
  return kind == UniversalMediaKind.video ? '视频' : '音乐';
}

String? _configuredUniversalMediaChannelModelId(
  UniversalMediaConfig config,
  UniversalMediaKind kind,
) {
  final value = kind == UniversalMediaKind.video
      ? config.videoChannelModelId
      : config.musicChannelModelId;
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

/// Resolves the channel that actually owns a media model.
///
/// A media model selected in Settings is independent from the conversation's
/// Chat model.  Older configurations have no channel-model ID and retain the
/// compatibility behavior of reusing the current Chat channel.  Once an ID
/// is present, silently falling back to the Chat channel would send the media
/// request to the wrong provider, so callers must surface the stale-route
/// error instead.
Future<ChannelModelWithChannel?> _resolveUniversalMediaRouteModel({
  required ChannelDao channelDao,
  required ChannelModelWithChannel chatModel,
  required UniversalMediaConfig config,
  required UniversalMediaKind kind,
}) async {
  final channelModelId = _configuredUniversalMediaChannelModelId(config, kind);
  if (channelModelId == null) return chatModel;

  final selected = await channelDao.getModelWithChannel(channelModelId);
  if (selected == null || !selected.channel.isEnabled) return null;
  return selected;
}

@visibleForTesting
Future<ChannelModelWithChannel?> resolveUniversalMediaRouteModelForTesting({
  required ChannelDao channelDao,
  required ChannelModelWithChannel chatModel,
  required UniversalMediaConfig config,
  required UniversalMediaKind kind,
}) => _resolveUniversalMediaRouteModel(
  channelDao: channelDao,
  chatModel: chatModel,
  config: config,
  kind: kind,
);

String _configuredUniversalMediaModelName(
  UniversalMediaConfig config,
  UniversalMediaKind kind,
  ChannelModelWithChannel routeModel,
) {
  final selectedId = _configuredUniversalMediaChannelModelId(config, kind);
  if (selectedId != null) {
    final selectedName = routeModel.channelModel.modelName.trim();
    if (selectedName.isNotEmpty) return selectedName;
  }
  return (kind == UniversalMediaKind.video
          ? config.videoModel
          : config.musicModel)
      .trim();
}

/// 判断当前“聊天模型 + 渠道”是否可以作为通用媒体请求的路由上下文。
///
/// 视频 / 音乐真正使用的模型和 endpoint 来自 [UniversalMediaConfig]，因此
/// 一个明确标记为 Chat / Vision / Reasoner 的当前模型可以复用已配置的
/// 通用媒体 endpoint；Embedding 或未知的非聊天模型不能被假定具备这个
/// 能力。若模型自身已经显式标记为对应的 Video / Music 能力，也允许通过，
/// 但不会根据模型名字中的 `video` / `music` 猜测能力。
UniversalMediaCapability resolveUniversalMediaCapability({
  required UniversalMediaKind kind,
  required String? protocol,
  required String? baseUrl,
  required bool? apiKeyConfigured,
  required String? modelName,
  required String? modelCapability,
  Set<String>? modelCapabilities,
  required String? mediaModel,
  required String? mediaEndpoint,
  bool checking = false,
}) {
  final label = _universalMediaKindLabel(kind);
  if (checking) {
    return const UniversalMediaCapability(
      status: UniversalMediaCapabilityStatus.checking,
      message: '正在检测当前模型和媒体配置…',
    );
  }

  if (modelName == null || modelName.trim().isEmpty) {
    return UniversalMediaCapability(
      status: UniversalMediaCapabilityStatus.notConfigured,
      message: '请先选择模型后再生成$label',
    );
  }
  if (protocol == null || modelCapability == null || apiKeyConfigured == null) {
    return const UniversalMediaCapability(
      status: UniversalMediaCapabilityStatus.checking,
      message: '正在检测当前模型和媒体配置…',
    );
  }
  if (baseUrl == null || baseUrl.trim().isEmpty) {
    return UniversalMediaCapability(
      status: UniversalMediaCapabilityStatus.notConfigured,
      message: '请先在当前渠道配置 Base URL 后再生成$label',
    );
  }
  if (!apiKeyConfigured) {
    return UniversalMediaCapability(
      status: UniversalMediaCapabilityStatus.notConfigured,
      message: '请先在当前渠道配置 API Key 后再生成$label',
    );
  }
  if (mediaModel == null ||
      mediaModel.trim().isEmpty ||
      mediaEndpoint == null ||
      mediaEndpoint.trim().isEmpty) {
    return UniversalMediaCapability(
      status: UniversalMediaCapabilityStatus.notConfigured,
      message: '请先在设置 → 图片生成中配置$label模型和接口路径',
    );
  }
  if (!canUseChannelUniversalMedia(protocol)) {
    return UniversalMediaCapability(
      status: UniversalMediaCapabilityStatus.unavailable,
      message: '当前渠道协议不提供通用$label接口',
    );
  }

  final normalizedCapability = ModelCapability.normalize(modelCapability);
  final explicitlySupportsKind = kind == UniversalMediaKind.video
      ? ModelCapability.supportsVideoModel(
          capability: normalizedCapability,
          modelId: modelName,
          capabilities: modelCapabilities,
        )
      : ModelCapability.supportsMusicModel(
          capability: normalizedCapability,
          modelId: modelName,
          capabilities: modelCapabilities,
        );
  final isChatCompatible = ModelCapability.isChat(normalizedCapability);
  if (!isChatCompatible && !explicitlySupportsKind) {
    return UniversalMediaCapability(
      status: UniversalMediaCapabilityStatus.unavailable,
      message:
          '当前模型能力为 ${ModelCapability.label(normalizedCapability)}，未声明通用$label能力',
    );
  }

  return const UniversalMediaCapability(
    status: UniversalMediaCapabilityStatus.available,
    message: '',
  );
}

/// 等待通用媒体设置从 SharedPreferences 读取完成。配置 provider 本身
/// 保持默认值以兼容旧调用方；Composer 使用这个 Future 将“检测中”和
/// “可用”区分开，避免在启动瞬间假定默认配置已生效。
final universalMediaConfigReadyProvider = FutureProvider<void>((ref) {
  return ref.read(universalMediaConfigProvider.notifier).ready;
});

/// 当前会话默认模型的完整记录。它不使用 [allModelsProvider]，因为后者
/// 为普通聊天筛选了 Embedding / Media-only 模型；媒体 capability 判断必须
/// 读取会话实际绑定的模型，避免切换会话时复用另一会话的模型状态。
final chatSessionModelProvider =
    FutureProvider.family<ChannelModelWithChannel?, String>((
      ref,
      sessionId,
    ) async {
      final session = await ref.read(sessionDaoProvider).getSession(sessionId);
      final modelId = session?.defaultChannelModelId;
      if (modelId == null || modelId.trim().isEmpty) return null;
      return ref.read(channelDaoProvider).getModelWithChannel(modelId);
    });

@visibleForTesting
bool isContextLimitErrorForTesting(String error) => _isContextLimitError(error);

@visibleForTesting
String contextLimitUserMessageForTesting() => _contextLimitUserMessage;

@visibleForTesting
String? buildLocalContextPromptForTesting({
  String? memoryPrompt,
  ReflectionReport? reflectionReport,
  bool reflectionPromptEnabled = true,
}) {
  return _buildLocalContextPrompt(
    memoryPrompt: memoryPrompt,
    reflectionReport: reflectionReport,
    reflectionPromptEnabled: reflectionPromptEnabled,
  );
}

bool _isContextLimitError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('context_length_exceeded') ||
      text.contains('maximum context length') ||
      text.contains('context length') ||
      text.contains('context window') ||
      text.contains('too many tokens') ||
      text.contains('input tokens exceed') ||
      text.contains('exceeds the model') ||
      text.contains('超过') && text.contains('上下文');
}

String? _buildLocalContextPrompt({
  String? memoryPrompt,
  ReflectionReport? reflectionReport,
  bool reflectionPromptEnabled = true,
}) {
  final reflectionPrompt = reflectionPromptEnabled
      ? buildAssistantReflectionSystemPrompt(reflectionReport)
      : null;
  final sections = <String>[
    if (memoryPrompt != null && memoryPrompt.trim().isNotEmpty)
      memoryPrompt.trim(),
    if (reflectionPrompt != null && reflectionPrompt.trim().isNotEmpty)
      reflectionPrompt.trim(),
  ];
  if (sections.isEmpty) return null;
  return sections.join('\n\n');
}

int _strictRetryInputBudget(int maxInputTokens) {
  final strict = (maxInputTokens * 0.65).floor();
  if (maxInputTokens <= 1024) return strict > 0 ? strict : 1;
  return strict < 1024 ? 1024 : strict;
}

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
final _interruptedStreamCancellationErrors = <String, String>{};
// sendMessage 在真正建立 SSE 之前还可能处于 STT / context preparation 阶段，
// 因此单靠 StreamSubscription.cancel() 不足以阻止它继续启动聊天请求。
final _sendOperationGenerations = <String, int>{};
// 后台标题生成的在途集合：标题仍为空时第二条回复到达，避免重复生成。
final _titleGenerationInFlight = <String>{};

String _universalMediaFailureText(
  Object error, {
  required UniversalMediaKind kind,
}) {
  if (error is UniversalMediaException) return error.message;
  final text = error.toString().trim();
  if (text.isEmpty) {
    return '${_universalMediaKindLabel(kind)}任务失败，请稍后重试';
  }
  return text.startsWith('Exception:')
      ? text.substring('Exception:'.length).trim()
      : text;
}

String _universalMediaJobError(
  UniversalMediaJob job, {
  required UniversalMediaKind kind,
}) {
  final fallback = switch (job.status) {
    UniversalMediaJobStatus.failed =>
      '${_universalMediaKindLabel(kind)}任务失败，请稍后重试',
    UniversalMediaJobStatus.expired =>
      '${_universalMediaKindLabel(kind)}任务已过期，请重试',
    UniversalMediaJobStatus.cancelled =>
      '${_universalMediaKindLabel(kind)}任务已取消',
    _ => '${_universalMediaKindLabel(kind)}接口未返回可用媒体',
  };
  return job.error?.trim().isNotEmpty == true ? job.error!.trim() : fallback;
}

/// 统一执行一次视频 / 音乐任务。
///
/// 这里是 Chat Composer 与 [universalMediaTaskProvider] 的唯一接缝：
/// 任务提交、轮询、取消和最终落盘都共享同一个 operationId。服务层的
/// onJobUpdate 会把每次 poll 的 attempts 传给 task provider，因此 UI 能够
/// 区分 pending / polling，而不是把异步任务伪装成同步请求。
Future<String?> _runUniversalMediaTask({
  required WidgetRef ref,
  required String sessionId,
  required UniversalMediaKind kind,
  required UniversalMediaService service,
  required String model,
  required String prompt,
  required String? endpoint,
  UniversalMediaTaskOptions taskOptions = const UniversalMediaTaskOptions(),
  Map<String, dynamic> extra = const <String, dynamic>{},
  String? referenceImagePath,
  required Future<String?> Function(
    UniversalMediaAsset asset,
    UniversalMediaJob job,
    String operationId,
  )
  saveAsset,
  String? channelModelId,
  String? deliveryUserContent,
  String? deliveryAssistantContent,
  String? deliveryFileType,
}) async {
  final operationId = _uuid.v4();
  final taskNotifier = ref.read(universalMediaTaskProvider(sessionId).notifier);
  taskNotifier.begin(operationId: operationId, kind: kind);

  try {
    final result = await ref
        .read(universalMediaJobProvider.notifier)
        .run(
          operationId: operationId,
          service: service,
          kind: kind,
          model: model,
          prompt: prompt,
          endpoint: endpoint,
          extra: extra,
          taskOptions: taskOptions,
          referenceImagePath: referenceImagePath,
          sessionId: sessionId,
          channelModelId: channelModelId,
          deliveryUserContent: deliveryUserContent,
          deliveryAssistantContent: deliveryAssistantContent,
          deliveryFileType: deliveryFileType,
          onJobUpdate: taskNotifier.updateJob,
        );
    final job = result.job;

    switch (job.status) {
      case UniversalMediaJobStatus.failed:
        taskNotifier.updateJob(job);
        return '${_universalMediaKindLabel(kind)}生成失败：${_universalMediaJobError(job, kind: kind)}';
      case UniversalMediaJobStatus.expired:
        taskNotifier.updateJob(job);
        return '${_universalMediaKindLabel(kind)}任务已过期：${_universalMediaJobError(job, kind: kind)}';
      case UniversalMediaJobStatus.cancelled:
        taskNotifier.markCancelled(job: job);
        return '${_universalMediaKindLabel(kind)}生成已取消';
      case UniversalMediaJobStatus.pending:
        taskNotifier.updateJob(job);
        return '${_universalMediaKindLabel(kind)}仍在排队，请稍后重试';
      case UniversalMediaJobStatus.completed:
        break;
    }

    final asset = result.asset ?? job.asset;
    if (asset == null) {
      const error = '接口已完成但未返回可保存的媒体';
      taskNotifier.markFailed(error, job: job);
      return '${_universalMediaKindLabel(kind)}生成失败：$error';
    }

    taskNotifier.markSaving();
    final saveError = await saveAsset(asset, job, operationId);
    if (saveError != null) {
      await ref
          .read(universalMediaJobProvider.notifier)
          .failDelivery(operationId, error: saveError);
      taskNotifier.markFailed(saveError, job: job);
      return saveError;
    }
    // saveAsset 只返回错误，不会修改 job；这里显式恢复 completed，避免
    // “保存中”状态在事务提交后留在 Composer。
    taskNotifier.updateJob(job);
    return null;
  } on UniversalMediaCancelledException {
    taskNotifier.markCancelled(job: taskNotifier.currentJob);
    return '${_universalMediaKindLabel(kind)}生成已取消';
  } catch (error) {
    final message = _universalMediaFailureText(error, kind: kind);
    taskNotifier.markFailed(message, job: taskNotifier.currentJob);
    return '${_universalMediaKindLabel(kind)}生成失败：$message';
  }
}

int _beginSendOperation(String sessionId) {
  final next = (_sendOperationGenerations[sessionId] ?? 0) + 1;
  _sendOperationGenerations[sessionId] = next;
  return next;
}

bool _isCurrentSendOperation(String sessionId, int operation) {
  return _sendOperationGenerations[sessionId] == operation;
}

const backgroundStreamingInterruptedMessage = '应用进入后台，已停止本次生成，回到前台后可重试。';
const networkStreamingInterruptedMessage = '网络连接断开，已停止本次生成，联网后可重试。';
const kBackgroundInterruptedSessionStorageKey =
    'simichat.background_interrupted_session_id';
const kBackgroundInterruptedSessionsStorageKey =
    'simichat.background_interrupted_session_ids';

/// 取消当前会话的流式输出
void cancelStreaming(WidgetRef ref, String sessionId, {String? error}) {
  // 使 STT / 记忆 / 上下文准备阶段的旧 send 失效；没有 subscription 时也
  // 必须递增，否则 Stop 只会把 UI 置空，旧 future 仍会启动聊天流。
  _beginSendOperation(sessionId);
  if (error != null) {
    _interruptedStreamCancellationErrors[sessionId] = error;
  }
  _cancelTokens[sessionId]?.cancel('用户取消');
  _cancelTokens.remove(sessionId);
  final completer = _responseCompletions.remove(sessionId);
  if (completer != null && !completer.isCompleted) {
    completer.complete();
  }
  final subscription = _streamSubscriptions.remove(sessionId);
  if (subscription != null) {
    unawaited(subscription.cancel().catchError((_) {}));
  }
  ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
    isStreaming: false,
    error: error,
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
  if (const bool.fromEnvironment('SIMICHAT_RELEASE_SEND_SMOKE') &&
      sessionId == 'ios-release-smoke-session') {
    return;
  }
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
    try {
      await ref
          .read(archiveRepairQueueProvider.notifier)
          .recordFailure(
            sessionId: sessionId,
            operation: 'append-$role',
            error: e,
          );
    } catch (_) {
      // 页面关闭后 WidgetRef 可能已销毁，档案修复队列记录不能
      // 反向造成未处理异步异常。
    }
  }
}

Future<String?> _writeAudioTranscriptDraftAndMaybeTranscribe({
  required WidgetRef ref,
  required String sessionId,
  required String messageId,
  required String attachmentId,
  required String audioPath,
  required String fileName,
  required int fileSize,
  String? transcript,
  SpeechToTextEngine? engineOverride,
}) async {
  if (kIsWeb) return null;
  final AudioTranscriptArchive archive;
  try {
    final root = await getApplicationDocumentsDirectory();
    archive = AudioTranscriptArchive(rootDirectory: root);
    final initialTranscript = transcript == null
        ? null
        : initialAudioTranscriptText(transcript);
    await archive.writeDraft(
      messageId: messageId,
      attachmentId: attachmentId,
      fileName: fileName,
      fileSize: fileSize,
      transcript: initialTranscript,
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
    return null;
  }

  final engine = engineOverride ?? ref.read(speechToTextEngineProvider);
  if (engine == null) {
    final initialTranscript = initialAudioTranscriptText(transcript ?? '');
    if (initialTranscript == null) {
      try {
        await archive.writeFailure(
          messageId: messageId,
          attachmentId: attachmentId,
          fileName: fileName,
          fileSize: fileSize,
          error: _sttNotConfiguredMessage,
        );
      } catch (e) {
        await ref
            .read(archiveRepairQueueProvider.notifier)
            .recordFailure(
              sessionId: sessionId,
              operation: 'audio-transcription-not-configured',
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
    return initialTranscript;
  }

  try {
    final service = AudioTranscriptionService(archive: archive, engine: engine);
    final result = await service.transcribeAndArchive(
      AudioTranscriptionJob(
        messageId: messageId,
        attachmentId: attachmentId,
        audioPath: audioPath,
        fileName: fileName,
        fileSize: fileSize,
      ),
    );
    return initialAudioTranscriptText(result.transcript);
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
  return null;
}

SpeechToTextEngine? _resolveSpeechToTextEngineForMessage({
  required WidgetRef ref,
  required ChannelModelWithChannel modelInfo,
  required String apiKey,
}) {
  final engines = <SpeechToTextEngine>[];
  final configured = ref.read(speechToTextEngineProvider);
  if (configured != null) engines.add(configured);
  if (canUseChannelSpeechToTextFallback(modelInfo.channel.protocol)) {
    final channelModel = modelInfo.channelModel.modelName;
    final channelModelIsAsr =
        channelModel.contains('asr') ||
        channelModel.contains('whisper') ||
        channelModel.contains('transcribe');
    engines.add(
      OpenAiCompatibleSpeechToTextEngine(
        baseUrl: modelInfo.channel.baseUrl,
        apiKey: apiKey,
        // 通道模型本身是 ASR 模型（如 SimiRouter 的 mimo-v2.5-asr）时
        // 直接透传，否则保持默认 whisper-1（避免把聊天模型名传给转录接口）。
        model: channelModelIsAsr ? channelModel : kDefaultSpeechToTextModel,
        language:
            ref.read(sttLanguageOverrideProvider) ?? 'auto',
      ),
    );
  }
  if (!kIsWeb && Platform.isIOS) {
    engines.add(const NativeSpeechToTextEngine());
  }
  if (engines.isEmpty) return null;
  if (engines.length == 1) return engines.first;
  return FallbackSpeechToTextEngine(engines);
}

Future<String?> _transcribeAudioAttachmentsForAi({
  required WidgetRef ref,
  required String sessionId,
  required String messageId,
  required List<_StoredAttachment> attachments,
  required SpeechToTextEngine? engine,
}) async {
  final transcripts = <String>[];
  for (final attachment in attachments) {
    if (attachment.fileType != 'audio') continue;
    final transcript = await _writeAudioTranscriptDraftAndMaybeTranscribe(
      ref: ref,
      sessionId: sessionId,
      messageId: messageId,
      attachmentId: attachment.id,
      audioPath: attachment.localPath,
      fileName: attachment.fileName,
      fileSize: attachment.fileSize,
      engineOverride: engine,
    );
    // 单次语言覆盖只影响本次发送的转录，全部完成后清除。
    ref.read(sttLanguageOverrideProvider.notifier).clear();
    final normalized = transcript?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      transcripts.add('【${attachment.fileName}】\n$normalized');
    }
  }
  if (transcripts.isEmpty) return null;
  return transcripts.join('\n\n');
}

class _PreparedAttachment {
  final PendingAttachment attachment;
  final int fileSize;

  const _PreparedAttachment({required this.attachment, required this.fileSize});
}

class _DocumentContentSource {
  final String type;
  final String path;
  final String fileName;

  const _DocumentContentSource({
    required this.type,
    required this.path,
    required this.fileName,
  });
}

/// Extracts only document attachments. Native image transport and the existing
/// audio -> STT path stay outside this function. A duplicate path is archived
/// normally but contributes one text block to this request, preventing an
/// accidental duplicate append when a picker returns the same file twice.
Future<List<String>> _extractDocumentContents(
  Iterable<_DocumentContentSource> sources,
) async {
  final extractor = const FileContentExtractor();
  final extracted = <String>[];
  final seenPaths = <String>{};
  for (final source in sources) {
    if (source.type.trim().toLowerCase() != 'document') continue;
    final path = source.path.trim();
    if (!seenPaths.add(path)) continue;
    final result = await extractor.extract(
      path: path,
      fileName: source.fileName,
      attachmentType: 'document',
    );
    extracted.add(result.text);
  }
  return extracted;
}

String _safeAttachmentPreparationError(Object error) {
  if (error is FileContentExtractionException) return error.message;
  // Do not surface FileSystemException.toString(): it can contain an
  // absolute path, provider URI, or other sensitive diagnostic.
  return '附件无法读取或归档，消息未发送；已保留输入和附件，请重新选择文件后重试。';
}

String? _preflightChatAttachments({
  required ChannelModelWithChannel modelInfo,
  required Iterable<String> attachmentTypes,
}) {
  final protocolAdapter = _tryGetAiProtocol(modelInfo.channel.protocol);
  if (protocolAdapter == null) {
    return '当前渠道协议 ${modelInfo.channel.protocol} 不可用，消息未发送；已保留输入和附件。';
  }
  for (final rawType in attachmentTypes) {
    final type = rawType.trim().toLowerCase();
    if (type == 'pdf' &&
        protocolAdapter.nativeAttachmentTypes.contains('pdf') &&
        !ModelCapability.supportsVerifiedNativeFile(
          capability: modelInfo.channelModel.capability,
          modelId: modelInfo.channelModel.modelName,
          protocol: modelInfo.channel.protocol,
          attachmentType: type,
        )) {
      return '当前模型 ${modelInfo.channelModel.modelName} 未验证 PDF 原生 File 契约，消息未发送；已保留输入和附件。';
    }
  }
  final transportError = preflightChatAttachmentTransport(
    protocol: modelInfo.channel.protocol,
    attachmentTypes: attachmentTypes,
    nativeAttachmentTypes: protocolAdapter.nativeAttachmentTypes,
  );
  if (transportError != null) return transportError.message;

  final hasImage = attachmentTypes.any(
    (type) => type.trim().toLowerCase() == 'image',
  );
  if (hasImage &&
      !ModelCapability.supportsVisionModel(
        capability: modelInfo.channelModel.capability,
        modelId: modelInfo.channelModel.modelName,
        capabilities: modelInfo.capabilities,
        protocol: modelInfo.channel.protocol,
      )) {
    return '当前模型不支持图片输入，消息未发送；已保留输入和附件。';
  }
  return null;
}

ai.AiProtocol? _tryGetAiProtocol(String protocol) {
  try {
    return AiService.getProtocol(protocol);
  } on Object {
    return null;
  }
}

void _setSendPreflightError(WidgetRef ref, String sessionId, String error) {
  ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
    error: error,
  );
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

Future<PendingAttachment?> _materializeInlineBase64AudioAttachment(
  InlineBase64AudioPayload payload,
) async {
  if (kIsWeb) return null;
  final directory = await getTemporaryDirectory();
  final file = File(
    '${directory.path}/simichat-inline-audio-${DateTime.now().microsecondsSinceEpoch}.${payload.extension}',
  );
  await writeBytesAtomically(file, payload.bytes);
  return PendingAttachment(
    path: file.path,
    name: payload.fileName,
    type: 'audio',
  );
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

class _GeneratedSourceAttachment {
  final String path;
  final String fileName;
  final String fileType;

  const _GeneratedSourceAttachment({
    required this.path,
    required this.fileName,
    required this.fileType,
  });
}

/// 将生成动作使用的参考图复制到应用私有目录，确保源文件被用户移动后，
/// 会话时间线仍然可以展示、导出和恢复参考上下文。
Future<_StoredAttachment> _archiveGeneratedSourceAttachment(
  _GeneratedSourceAttachment source, {
  String? attachmentId,
  Directory? rootDirectory,
}) async {
  final input = File(source.path);
  if (!await input.exists()) {
    throw const FileSystemException('参考文件不存在或已被移动');
  }
  final sourceSize = await input.length();
  final validationError = validateAttachmentMetadata(
    fileName: source.fileName,
    fileType: source.fileType,
    fileSize: sourceSize,
    currentCount: 0,
  );
  if (validationError != null) throw Exception(validationError);

  final stableAttachmentId = attachmentId ?? _uuid.v4();
  final safeName = safeAttachmentFileName(source.fileName);
  final root = rootDirectory ?? await getApplicationSupportDirectory();
  final target = File(
    p.join(root.path, 'generated_context', '$stableAttachmentId-$safeName'),
  );
  final archived = await copyFileAtomically(
    input,
    target,
    maxBytes: kMaxAttachmentBytes,
  );
  return _StoredAttachment(
    id: stableAttachmentId,
    fileName: safeName,
    fileType: source.fileType,
    localPath: archived.path,
    fileSize: await archived.length(),
  );
}

Future<List<_StoredAttachment>> _storeAttachments({
  required String messageId,
  required List<_PreparedAttachment> attachments,
}) async {
  if (attachments.isEmpty) return const [];

  final stored = <_StoredAttachment>[];
  AudioFileArchive? audioArchive;
  MessageAttachmentArchive? messageArchive;
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
    } else if (!kIsWeb) {
      try {
        messageArchive ??= MessageAttachmentArchive(
          rootDirectory: await getApplicationDocumentsDirectory(),
        );
        final archived = await messageArchive.archive(
          sourcePath: attachment.path,
          messageId: messageId,
          attachmentId: attachmentId,
          fileName: attachment.name,
        );
        localPath = archived.localPath;
        fileSize = archived.fileSize;
      } catch (_) {
        throw Exception('附件文件归档失败：${attachment.name}');
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

  unawaited(_retryLastUserMessage(ref, resolvedSessionId));
}

Future<void> _retryLastUserMessage(WidgetRef ref, String sessionId) async {
  final messages = await ref
      .read(messageDaoProvider)
      .getMessagesBySession(sessionId);
  if (messages.isEmpty) return;
  for (int i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role == 'user') {
      ref.read(streamStateProvider(sessionId).notifier).state =
          const StreamState();
      await sendMessage(
        ref: ref,
        sessionId: sessionId,
        content: messages[i].content,
        overrideModelId: resolveRetryModelIdForUserMessageForTesting(
          messages,
          messages[i].id,
        ),
        reuseUserMessageId: messages[i].id,
      );
      return;
    }
  }
}

/// 重试被点击的 assistant 回复。
///
/// 先在同一会话中找到该 assistant 对应的最近 user turn，再复用原 user
/// message 和数据库附件。这样 regenerate 不会再插入一条重复 user，也不会
/// 回退到“最后一条 user”而误重试另一轮对话。
@visibleForTesting
String? resolveRetryUserMessageIdForTesting(
  List<Message> messages,
  String assistantMessageId,
) {
  final assistantIndex = messages.indexWhere(
    (message) =>
        message.id == assistantMessageId && message.role == 'assistant',
  );
  if (assistantIndex < 0) return null;
  for (var index = assistantIndex - 1; index >= 0; index--) {
    if (messages[index].role == 'user') return messages[index].id;
  }
  return null;
}

/// Resolves the model used by the assistant response being regenerated. A
/// missing/blank persisted value intentionally returns null so sendMessage can
/// fall back to the session default model.
@visibleForTesting
String? resolveRetryModelIdForTesting(
  List<Message> messages,
  String assistantMessageId,
) {
  for (final message in messages) {
    if (message.id != assistantMessageId || message.role != 'assistant') {
      continue;
    }
    final modelId = message.channelModelId?.trim();
    return modelId == null || modelId.isEmpty ? null : modelId;
  }
  return null;
}

/// Resolves the latest assistant model belonging to one user turn. Assistant
/// messages after the turn are considered regenerate variants; the latest
/// non-empty model id is the one the user currently sees. A following user
/// turn stops the search, and no result falls back to the session default.
@visibleForTesting
String? resolveRetryModelIdForUserMessageForTesting(
  List<Message> messages,
  String userMessageId,
) {
  final userIndex = messages.indexWhere(
    (message) => message.id == userMessageId && message.role == 'user',
  );
  if (userIndex < 0) return null;

  String? resolved;
  for (var index = userIndex + 1; index < messages.length; index++) {
    final message = messages[index];
    if (message.role == 'user') break;
    if (message.role != 'assistant') continue;
    final modelId = message.channelModelId?.trim();
    if (modelId != null && modelId.isNotEmpty) resolved = modelId;
  }
  return resolved;
}

Future<bool> retryMessage({
  required WidgetRef ref,
  required String sessionId,
  required String assistantMessageId,
}) async {
  final messages = await ref
      .read(messageDaoProvider)
      .getMessagesBySession(sessionId);
  final userMessageId = resolveRetryUserMessageIdForTesting(
    messages,
    assistantMessageId,
  );
  if (userMessageId == null) return false;
  final userMessage = messages.firstWhere(
    (message) => message.id == userMessageId,
  );

  ref.read(streamStateProvider(sessionId).notifier).state = const StreamState();
  return sendMessage(
    ref: ref,
    sessionId: sessionId,
    content: userMessage.content,
    overrideModelId: resolveRetryModelIdForTesting(
      messages,
      assistantMessageId,
    ),
    reuseUserMessageId: userMessage.id,
  );
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
  final streamInProgress =
      activeSessionId != null &&
      ref.read(streamStateProvider(activeSessionId)).isStreaming;

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

      if (streamInProgress) {
        // 当前 send 已经把 model / context 快照传入协议层；切换模型不
        // 反向改变这次流，只更新会话默认值，明确作为下一条消息生效。
        ref.invalidate(chatSessionModelProvider(activeSessionId));
        ref.invalidate(activeSessionProvider);
        ref.invalidate(sessionsProvider);
        selectedNotifier.state = modelId;
        return ModelSwitchResult(
          changed: true,
          recorded: false,
          message:
              '当前回复进行中，本次回复仍使用原模型；${resolveModelSwitchLabel(modelLabel)}将用于下一条消息',
        );
      }

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
      ref.invalidate(chatSessionModelProvider(activeSessionId));
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
      ref.invalidate(chatSessionModelProvider(activeSessionId));
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
  final String? modelId;
  final String? error;
  final bool isWaitingForFirstToken; // 发送后等待第一个 token 的状态

  const StreamState({
    this.isStreaming = false,
    this.currentContent = '',
    this.currentThinking = '',
    this.modelId,
    this.error,
    this.isWaitingForFirstToken = false,
  });

  StreamState copyWith({
    bool? isStreaming,
    String? currentContent,
    String? currentThinking,
    String? modelId,
    String? error,
    bool? isWaitingForFirstToken,
  }) {
    return StreamState(
      isStreaming: isStreaming ?? this.isStreaming,
      currentContent: currentContent ?? this.currentContent,
      currentThinking: currentThinking ?? this.currentThinking,
      modelId: modelId ?? this.modelId,
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

  /// regenerate 时复用数据库中的 user message，不再次插入 user 或复制附件。
  String? reuseUserMessageId,
}) async {
  final messageDao = ref.read(messageDaoProvider);
  final sessionDao = ref.read(sessionDaoProvider);
  final channelDao = ref.read(channelDaoProvider);
  final attachmentDao = ref.read(attachmentDaoProvider);

  // 防止同一会话并发发送：先取消已有流
  if (_streamSubscriptions.containsKey(sessionId)) {
    cancelStreaming(ref, sessionId);
  }
  final operation = _beginSendOperation(sessionId);

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

  Message? reusedUserMessage;
  if (reuseUserMessageId != null) {
    final sessionMessages = await messageDao.getMessagesBySession(sessionId);
    for (final candidate in sessionMessages) {
      if (candidate.id == reuseUserMessageId) {
        reusedUserMessage = candidate;
        break;
      }
    }
  }
  if (reuseUserMessageId != null &&
      (reusedUserMessage == null ||
          reusedUserMessage.sessionId != sessionId ||
          reusedUserMessage.role != 'user')) {
    return false;
  }

  List<Attachment>? reusedAttachmentRows;
  if (reusedUserMessage != null) {
    reusedAttachmentRows = await attachmentDao.getAttachmentsByMessage(
      reusedUserMessage.id,
    );
    final preflightError = _preflightChatAttachments(
      modelInfo: modelInfo,
      attachmentTypes: reusedAttachmentRows.map(
        (attachment) => attachment.fileType,
      ),
    );
    if (preflightError != null) {
      _setSendPreflightError(ref, sessionId, preflightError);
      return false;
    }
  } else {
    final preflightError = _preflightChatAttachments(
      modelInfo: modelInfo,
      attachmentTypes: attachments.map((attachment) => attachment.type),
    );
    if (preflightError != null) {
      _setSendPreflightError(ref, sessionId, preflightError);
      return false;
    }
  }

  var messageContent = reusedUserMessage?.content ?? content;
  var messageAttachments = reusedUserMessage == null
      ? attachments
      : const <PendingAttachment>[];
  if (reusedUserMessage == null) {
    try {
      final inlineAudio = extractInlineBase64Audio(messageContent);
      messageContent = inlineAudio.cleanedContent.trim();
      final payload = inlineAudio.audio;
      if (payload != null) {
        final inlineAttachment = await _materializeInlineBase64AudioAttachment(
          payload,
        );
        if (inlineAttachment == null) {
          ref.read(streamStateProvider(sessionId).notifier).state =
              const StreamState(error: '当前平台暂不支持直接粘贴 base64 语音，请改用语音文件附件。');
          return false;
        }
        messageAttachments = [...messageAttachments, inlineAttachment];
      }
    } on InlineBase64AudioException catch (error) {
      ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
        error: error.message,
      );
      return false;
    } catch (_) {
      ref.read(streamStateProvider(sessionId).notifier).state =
          const StreamState(error: 'base64 语音解析失败，请确认内容是完整音频 base64 字符串。');
      return false;
    }
  }

  if (messageContent.isEmpty && messageAttachments.isEmpty) return false;

  if (!_isCurrentSendOperation(sessionId, operation)) return false;

  final String userMsgId;
  final List<_StoredAttachment> storedAttachments;
  late final List<String> extractedDocumentContents;
  var userTokens = TokenEstimator.estimate(messageContent);
  if (reusedUserMessage != null) {
    userMsgId = reusedUserMessage.id;
    storedAttachments = reusedAttachmentRows!
        .map(
          (attachment) => _StoredAttachment(
            id: attachment.id,
            fileName: attachment.fileName,
            fileType: attachment.fileType,
            localPath: attachment.localPath,
            fileSize: attachment.fileSize,
          ),
        )
        .toList(growable: false);
    try {
      extractedDocumentContents = await _extractDocumentContents(
        storedAttachments.map(
          (attachment) => _DocumentContentSource(
            type: attachment.fileType,
            path: attachment.localPath,
            fileName: attachment.fileName,
          ),
        ),
      );
    } on Object catch (error) {
      _setSendPreflightError(
        ref,
        sessionId,
        _safeAttachmentPreparationError(error),
      );
      return false;
    }
  } else {
    late final List<_PreparedAttachment> preparedAttachments;
    try {
      preparedAttachments = await _prepareAttachments(messageAttachments);
      extractedDocumentContents = await _extractDocumentContents(
        preparedAttachments.map(
          (prepared) => _DocumentContentSource(
            type: prepared.attachment.type,
            path: prepared.attachment.path,
            fileName: prepared.attachment.name,
          ),
        ),
      );
    } on Object catch (error) {
      _setSendPreflightError(
        ref,
        sessionId,
        _safeAttachmentPreparationError(error),
      );
      return false;
    }
    userMsgId = _uuid.v4();
    try {
      storedAttachments = await _storeAttachments(
        messageId: userMsgId,
        attachments: preparedAttachments,
      );
    } on Object catch (error) {
      _setSendPreflightError(
        ref,
        sessionId,
        _safeAttachmentPreparationError(error),
      );
      return false;
    }
    await messageDao.insertMessage(
      id: userMsgId,
      sessionId: sessionId,
      role: 'user',
      content: messageContent,
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
    }

    unawaited(
      _appendConversationArchiveMessage(
        ref: ref,
        sessionId: sessionId,
        sessionTitle: session.title,
        messageId: userMsgId,
        role: 'user',
        content: messageContent,
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
            content: messageContent,
          );
      if (extractedMemory.isNotEmpty) {
        await memoryNotifier.rememberAll(extractedMemory);
      }
    } catch (_) {
      // 记忆提取失败不能阻断聊天主路径；不要记录用户消息内容。
    }
  }

  // 刷新消息列表
  ref.invalidate(messagesProvider(sessionId));
  ref.invalidate(sessionsProvider);
  final memoryNotifier = ref.read(keyPointMemoryProvider.notifier);

  // 解密 API Key
  final String apiKey;
  try {
    apiKey = KeyEncryptor.decryptOrEmpty(modelInfo.channel.apiKeyEncrypted);
  } catch (e) {
    ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
      isStreaming: false,
      modelId: modelId,
      error: 'API Key 解密失败: $e',
    );
    return false;
  }

  if (!_isCurrentSendOperation(sessionId, operation)) return false;

  final hasAudioAttachment = storedAttachments.any(
    (attachment) => attachment.fileType == 'audio',
  );
  String? audioTranscriptForAi;
  if (hasAudioAttachment) {
    ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
      isStreaming: true,
      modelId: modelId,
      isWaitingForFirstToken: true,
    );
    audioTranscriptForAi = await _transcribeAudioAttachmentsForAi(
      ref: ref,
      sessionId: sessionId,
      messageId: userMsgId,
      attachments: storedAttachments,
      engine: _resolveSpeechToTextEngineForMessage(
        ref: ref,
        modelInfo: modelInfo,
        apiKey: apiKey,
      ),
    );
    if (!_isCurrentSendOperation(sessionId, operation)) return false;
  }
  final fileAwareContent = fileAwareMessageContent(
    content: messageContent,
    extractedContents: extractedDocumentContents,
  );
  final effectiveUserContent = audioAwareMessageContent(
    content: fileAwareContent,
    hasAudioAttachment: hasAudioAttachment,
    audioTranscript: audioTranscriptForAi,
  );
  userTokens = TokenEstimator.estimate(effectiveUserContent);

  // 只把协议确实能表达的原生附件传给 adapter。document 已在上面绑定为
  // 一次性的文本上下文，不能再把“文件名 / 空 base64 / 伪 file part”传给
  // Chat-compatible adapter；audio 继续使用现有 STT 文本路径，即使某个
  // 协议同时声明了原生 audio 也不重复发送同一段音频。
  final aiAttachments = <ai.Attachment>[];
  final nativeAttachmentTypes =
      _tryGetAiProtocol(modelInfo.channel.protocol)?.nativeAttachmentTypes ??
      const <String>{};
  for (final attachment in storedAttachments) {
    final attachmentType = attachment.fileType.trim().toLowerCase();
    if (attachmentType == 'audio' ||
        !nativeAttachmentTypes.contains(attachmentType)) {
      continue;
    }
    aiAttachments.add(
      ai.Attachment(type: attachmentType, path: attachment.localPath),
    );
  }

  // 构建上下文（包含系统提示词 + Skills + MCP Tools）。重试时以目标
  // user message id 截断，并按 id 绑定一次性的正文与原生附件；不能依赖
  // contextMessages.last，因为目标消息后可能已有旧 assistant / 后续轮次。
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
  // MCP rows auto-connect asynchronously during provider initialization. A
  // cold-start send must wait briefly for that handshake, otherwise the first
  // prompt silently omits every MCP tool. Keep the wait bounded so a broken
  // remote SSE server never blocks ordinary chat input.
  try {
    await ref
        .read(mcpManagerProvider.notifier)
        .ready
        .timeout(const Duration(seconds: 3));
  } on Object {
    // Continue with tools connected so far; a later send can include newly
    // connected tools after the manager finishes loading.
  }
  final mcpToolsPrompt = _buildMcpToolsPrompt(ref);
  String? memoryPrompt;
  try {
    memoryPrompt = buildKeyPointMemorySystemPrompt(
      await memoryNotifier.searchRelevant(
        effectiveUserContent,
        sessionId: sessionId,
      ),
    );
  } catch (_) {
    // 记忆检索失败时降级为无记忆上下文，避免影响正常模型请求。
    memoryPrompt = null;
  }
  try {
    final reflectionEnabledNotifier = ref.read(
      assistantReflectionPromptEnabledProvider.notifier,
    );
    await reflectionEnabledNotifier.ready;
    final reflectionEnabled = ref.read(
      assistantReflectionPromptEnabledProvider,
    );
    final reflectionNotifier = ref.read(assistantReflectionProvider.notifier);
    await reflectionNotifier.ready;
    memoryPrompt = _buildLocalContextPrompt(
      memoryPrompt: memoryPrompt,
      reflectionReport: ref.read(assistantReflectionProvider),
      reflectionPromptEnabled: reflectionEnabled,
    );
  } catch (_) {
    // 反思提示失败不能影响主聊天链路；保留已有记忆提示。
  }
  final contextBudget = resolveModelContextBudget(
    protocol: modelInfo.channel.protocol,
    modelName: modelInfo.channelModel.modelName,
  );
  final compressionThreshold = dynamicCompressThresholdForBudget(
    contextBudget,
    ref.read(compressThresholdProvider),
  );
  try {
    final compressed = await ContextCompressor(messageDao).compressIfNeeded(
      sessionId: sessionId,
      threshold: compressionThreshold,
      protocol: modelInfo.channel.protocol,
      baseUrl: modelInfo.channel.baseUrl,
      apiKey: apiKey,
      model: modelInfo.channelModel.modelName,
    );
    if (compressed) {
      ref.invalidate(messagesProvider(sessionId));
      ref.invalidate(sessionsProvider);
    }
  } catch (_) {
    // 请求前压缩失败时继续走预算裁剪，避免把一次摘要失败变成发送失败。
  }
  final contextBuilder = ContextBuilder(messageDao);
  var (systemPrompt, contextMessages) = await contextBuilder.buildContext(
    sessionId,
    maxInputTokens: contextBudget.maxInputTokens,
    customSystemPrompt: customPrompt,
    memoryPrompt: memoryPrompt,
    skillsPrompt: skillsPrompt,
    mcpToolsPrompt: mcpToolsPrompt,
    upToMessageId: userMsgId,
    targetMessageContent: effectiveUserContent,
    targetMessageAttachments: aiAttachments.isEmpty ? null : aiAttachments,
  );
  contextMessages = trimAiMessagesToTokenBudget(
    systemPrompt: systemPrompt,
    messages: contextMessages,
    maxInputTokens: contextBudget.maxInputTokens,
  );

  if (!_isCurrentSendOperation(sessionId, operation)) return false;

  ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
    isStreaming: true,
    modelId: modelId,
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
      maxInputTokens: contextBudget.maxInputTokens,
      operation: operation,
    ),
  );
  return true;
}

/// 生成图片：调用 OpenAI 兼容 `/v1/images/generations`，
/// 把图片保存到应用私有目录，并将结果作为 assistant 消息（含图片附件）插入会话。
///
/// 返回 null 表示成功，否则返回用户可读的错误信息（不向上抛出到 UI 层）。
/// 测试注入点：非 null 时图片任务使用该工厂构造服务（fake service
/// 可以绕过 dio 的网络管线，直接验证占位 / 失败 / 取消的状态流转）。
@visibleForTesting
ImageGenerationService Function({
  required String baseUrl,
  required String apiKey,
  required String model,
})?
debugImageServiceFactory;

Future<String?> generateImage({
  required WidgetRef ref,
  required String sessionId,
  required String prompt,
  List<PendingAttachment> referenceAttachments = const [],
  String? size,
}) async {
  final sessionDao = ref.read(sessionDaoProvider);
  final channelDao = ref.read(channelDaoProvider);

  final trimmedPrompt = prompt.trim();
  if (trimmedPrompt.isEmpty) return '请输入图片描述';

  final session = await sessionDao.getSession(sessionId);
  if (session == null) return '会话不存在';

  final modelId = session.defaultChannelModelId;
  final modelInfo = modelId == null
      ? null
      : await channelDao.getModelWithChannel(modelId);
  if (modelInfo == null) return '请先选择一个模型';
  final channel = modelInfo.channel;
  if (!canUseChannelImageGeneration(channel.protocol)) {
    return '当前渠道不支持 OpenAI 兼容图片生成，请切换到支持 /v1/images/generations 的渠道';
  }

  final referenceImagePath = referenceAttachments
      .where((attachment) => attachment.type == 'image')
      .map((attachment) => attachment.path)
      .firstOrNull;
  final referenceImageName = referenceAttachments
      .where((attachment) => attachment.type == 'image')
      .map((attachment) => attachment.name)
      .firstOrNull;

  return _runImageGenerationTask(
    ref: ref,
    session: session,
    modelId: modelId,
    channel: channel,
    prompt: trimmedPrompt,
    referenceImagePath: referenceImagePath,
    referenceImageName: referenceImageName,
    userContent: referenceImagePath != null
        ? '参考图生成：$trimmedPrompt'
        : trimmedPrompt,
    assistantContent: referenceImagePath != null ? '已根据参考图生成图片' : '已生成图片',
    filePrefix: referenceImagePath != null
        ? 'reference-generated'
        : 'generated',
    size: size ?? ref.read(imageGenerationConfigProvider).size,
  );
}

/// 图片生成 / 编辑任务执行器：先插入占位消息并注册任务（气泡显示进度，
/// stop 可取消），上游成功后删除占位并原子写入最终消息对；失败时把
/// 占位消息改写为失败提示并保留参数供重试。
Future<String?> _runImageGenerationTask({
  required WidgetRef ref,
  required Session session,
  required String? modelId,
  required ModelChannel channel,
  required String prompt,
  String? referenceImagePath,
  String? referenceImageName,
  required String userContent,
  required String assistantContent,
  required String filePrefix,
  bool includeUserMessage = true,
  String? size,
}) async {
  final tasks = ref.read(imageGenerationTasksProvider.notifier);
  final messageDao = ref.read(messageDaoProvider);
  final sessionDao = ref.read(sessionDaoProvider);
  final imageConfig = ref.read(imageGenerationConfigProvider);

  final placeholderId = _uuid.v4();
  final task = ImageGenerationTask(
    messageId: placeholderId,
    sessionId: session.id,
    prompt: prompt,
    referenceImagePath: referenceImagePath,
    referenceImageName: referenceImageName,
    modelName: imageConfig.model,
    channelId: channel.id,
  );
  try {
    await messageDao.insertMessage(
      id: placeholderId,
      sessionId: session.id,
      role: 'assistant',
      content: '正在生成图片…',
      tokens: 0,
      channelModelId: modelId,
    );
    await sessionDao.updateLastMessageAt(session.id);
  } catch (e) {
    return '无法写入生成进度：$e';
  }
  final cancelToken = tasks.start(task);
  ref.invalidate(messagesProvider(session.id));

  final factory = debugImageServiceFactory;
  final service = factory != null
      ? factory(
          baseUrl: channel.baseUrl,
          apiKey: KeyEncryptor.decryptOrEmpty(channel.apiKeyEncrypted),
          model: imageConfig.model,
        )
      : ImageGenerationService(
          baseUrl: channel.baseUrl,
          apiKey: KeyEncryptor.decryptOrEmpty(channel.apiKeyEncrypted),
          model: imageConfig.model,
        );

  final GeneratedImage generated;
  try {
    generated = await service.generate(
      prompt,
      referenceImagePath: referenceImagePath,
      cancelToken: cancelToken,
      size: size ?? kImageGenerationSize,
    );
  } catch (e) {
    if (cancelToken.isCancelled) {
      tasks.finish(placeholderId);
      await _updatePlaceholderMessage(
        ref,
        session.id,
        placeholderId,
        content: '图片生成已取消',
      );
      return '已取消';
    }
    final message = '图片生成失败：$e';
    tasks.markFailed(placeholderId, message);
    await _updatePlaceholderMessage(
      ref,
      session.id,
      placeholderId,
      content: message,
    );
    return message;
  }

  // 成功：移除占位与任务，走原有原子写入。
  try {
    await messageDao.deleteMessage(placeholderId);
  } catch (_) {
    // 占位删除失败不影响结果写入；任务注册表仍然清理，避免悬空 spinner。
  }
  tasks.finish(placeholderId);

  final savedError = await _saveGeneratedImageConversation(
    ref: ref,
    session: session,
    modelId: modelId,
    userContent: userContent,
    assistantContent: assistantContent,
    filePrefix: filePrefix,
    image: generated,
    sourceAttachment: referenceImagePath == null
        ? null
        : _GeneratedSourceAttachment(
            path: referenceImagePath,
            fileName: referenceImageName ?? 'reference-image',
            fileType: 'image',
          ),
    includeUserMessage: includeUserMessage,
  );

  // 自动图床：上传成功后把 CDN 地址附到 assistant 消息正文。
  if (savedError == null &&
      ref.read(imageGenerationConfigProvider).autoUploadToCdn) {
    unawaited(_uploadGeneratedImageToCdn(ref, session, generated));
  }
  return savedError;
}

/// 上传生成图片到百度 CDN 图床，并把地址追加到最新 assistant 消息。
Future<void> _uploadGeneratedImageToCdn(
  WidgetRef ref,
  Session session,
  GeneratedImage image,
) async {
  try {
    const uploader = BaiduCdnImageUploader();
    final url = await uploader.uploadBytes(
      image.bytes,
      mimeType: image.extension == 'png' ? 'image/png' : 'image/jpeg',
    );
    final messages = await ref
        .read(messageDaoProvider)
        .getMessagesBySession(session.id);
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'assistant') {
        final message = messages[i];
        final suffix = '\n\n图床地址：$url';
        await ref.read(messageDaoProvider).updateMessageContent(
          message.id,
          message.content.endsWith(suffix) ? message.content : '${message.content}$suffix',
        );
        ref.invalidate(messagesProvider(session.id));
        break;
      }
    }
  } catch (_) {
    // 图床上传失败不阻断图片生成结果。
  }
}

Future<void> _updatePlaceholderMessage(
  WidgetRef ref,
  String sessionId,
  String messageId, {
  required String content,
}) async {
  try {
    await ref.read(messageDaoProvider).updateMessageContent(
      messageId,
      content,
    );
  } catch (_) {
    // 占位更新失败不阻塞任务结果，占位消息保持原样。
  }
  ref.invalidate(messagesProvider(sessionId));
}

/// 重试失败 / 取消的图片生成任务：删除旧占位，以相同参数重新执行。
Future<String?> retryImageGeneration({
  required WidgetRef ref,
  required String sessionId,
  required String messageId,
}) async {
  final tasks = ref.read(imageGenerationTasksProvider.notifier);
  final task = ref.read(imageGenerationTasksProvider)[messageId];
  if (task == null) return '生成任务已失效，请重新生成';
  if (task.isRunning) return '生成仍在进行中';
  if (task.isCancelled) {
    tasks.finish(messageId);
    return null;
  }

  final sessionDao = ref.read(sessionDaoProvider);
  final channelDao = ref.read(channelDaoProvider);
  final session = await sessionDao.getSession(sessionId);
  if (session == null) return '会话不存在';
  final modelId = session.defaultChannelModelId;
  final modelInfo = modelId == null
      ? null
      : await channelDao.getModelWithChannel(modelId);
  if (modelInfo == null) return '请先选择一个模型';
  final channel = modelInfo.channel;

  final hasReference = task.referenceImagePath != null &&
      task.referenceImagePath!.trim().isNotEmpty;
  tasks.finish(messageId);
  try {
    await ref.read(messageDaoProvider).deleteMessage(messageId);
  } catch (_) {
    // 占位删除失败时继续重试，最终会话可能出现重复占位提示，
    // 但不会产生错误结果消息。
  }
  ref.invalidate(messagesProvider(sessionId));

  return _runImageGenerationTask(
    ref: ref,
    session: session,
    modelId: modelId,
    channel: channel,
    prompt: task.prompt,
    referenceImagePath: task.referenceImagePath,
    referenceImageName: task.referenceImageName,
    userContent: hasReference ? '参考图生成：${task.prompt}' : task.prompt,
    assistantContent: hasReference ? '已根据参考图生成图片' : '已生成图片',
    filePrefix: hasReference ? 'reference-generated' : 'generated',
  );
}

/// 重新生成图片消息：定位 assistant 图片消息与前一条用户消息，删除旧结果
/// 后以相同提示词 / 参考图重新调用图片接口（不重复插入用户消息）。
Future<String?> retryImageMessage({
  required WidgetRef ref,
  required String sessionId,
  required String assistantMessageId,
}) async {
  final messageDao = ref.read(messageDaoProvider);
  final attachmentDao = ref.read(attachmentDaoProvider);
  final messages = await messageDao.getMessagesBySession(sessionId);
  final assistantIndex = messages.indexWhere(
    (m) => m.id == assistantMessageId,
  );
  if (assistantIndex <= 0) return '未找到图片消息';

  final assistantAttachments = await attachmentDao.getAttachmentsByMessage(
    assistantMessageId,
  );
  if (!assistantAttachments.any((a) => a.fileType == 'image')) {
    return '该消息不是图片消息';
  }

  Message? userMessage;
  for (var i = assistantIndex - 1; i >= 0; i--) {
    if (messages[i].role == 'user') {
      userMessage = messages[i];
      break;
    }
  }
  if (userMessage == null) return '未找到对应提示词';

  const referencePrefix = '参考图生成：';
  var prompt = userMessage.content;
  String? referenceImagePath;
  String? referenceImageName;
  if (prompt.startsWith(referencePrefix)) {
    prompt = prompt.substring(referencePrefix.length).trim();
    final userAttachments = await attachmentDao.getAttachmentsByMessage(
      userMessage.id,
    );
    for (final attachment in userAttachments) {
      if (attachment.fileType != 'image') continue;
      final path = attachment.localPath.trim();
      if (path.isNotEmpty) {
        referenceImagePath = path;
        referenceImageName = attachment.fileName;
        break;
      }
    }
  }

  final sessionDao = ref.read(sessionDaoProvider);
  final channelDao = ref.read(channelDaoProvider);
  final session = await sessionDao.getSession(sessionId);
  if (session == null) return '会话不存在';
  final modelId = session.defaultChannelModelId;
  final modelInfo = modelId == null
      ? null
      : await channelDao.getModelWithChannel(modelId);
  if (modelInfo == null) return '请先选择一个模型';
  final channel = modelInfo.channel;

  // 删除旧的 assistant 结果（含附件），随后按相同参数重新生成。
  await messageDao.deleteMessage(assistantMessageId);
  await attachmentDao.deleteByMessage(assistantMessageId);
  ref.invalidate(messagesProvider(sessionId));

  return _runImageGenerationTask(
    ref: ref,
    session: session,
    modelId: modelId,
    channel: channel,
    prompt: prompt,
    referenceImagePath: referenceImagePath,
    referenceImageName: referenceImageName,
    userContent: referenceImagePath != null ? '参考图生成：$prompt' : prompt,
    assistantContent: referenceImagePath != null ? '已根据参考图生成图片' : '已生成图片',
    filePrefix: referenceImagePath != null ? 'reference-generated' : 'generated',
    includeUserMessage: false,
    size: ref.read(imageGenerationConfigProvider).size,
  );
}

/// 取消会话内运行中的图片生成任务（stop 按钮入口）。
Future<void> cancelImageGeneration({
  required WidgetRef ref,
  required String sessionId,
}) async {
  await ref
      .read(imageGenerationTasksProvider.notifier)
      .cancelForSession(sessionId);
  final cancelled = ref
      .read(imageGenerationTasksProvider)
      .values
      .where((task) => task.sessionId == sessionId)
      .toList();
  for (final task in cancelled) {
    await _updatePlaceholderMessage(
      ref,
      sessionId,
      task.messageId,
      content: '图片生成已取消',
    );
  }
}

/// 编辑图片：把参考图（`imagePath`）与编辑提示词发送到
/// OpenAI 兼容 `/v1/images/edits`，结果作为 assistant 消息（含图片附件）插入会话。
///
/// 返回 null 表示成功，否则返回用户可读的错误信息（不向上抛出到 UI 层）。
Future<String?> editImage({
  required WidgetRef ref,
  required String sessionId,
  required String imagePath,
  required String prompt,
  String? size,
}) async {
  final sessionDao = ref.read(sessionDaoProvider);
  final channelDao = ref.read(channelDaoProvider);

  final trimmedPrompt = prompt.trim();
  if (trimmedPrompt.isEmpty) return '请输入编辑提示词';

  final session = await sessionDao.getSession(sessionId);
  if (session == null) return '会话不存在';

  final modelId = session.defaultChannelModelId;
  final modelInfo = modelId == null
      ? null
      : await channelDao.getModelWithChannel(modelId);
  if (modelInfo == null) return '请先选择一个模型';
  final channel = modelInfo.channel;
  final userContent = '编辑图片：$trimmedPrompt';
  if (!canUseChannelImageGeneration(channel.protocol)) {
    return '当前渠道不支持 OpenAI 兼容图片编辑，请切换到支持 /v1/images/edits 的渠道';
  }

  // 上游成功后才以事务写入会话，失败保留对话框内的提示词。
  final imageConfig = ref.read(imageGenerationConfigProvider);
  final service = ImageGenerationService(
    baseUrl: channel.baseUrl,
    apiKey: KeyEncryptor.decryptOrEmpty(channel.apiKeyEncrypted),
    model: imageConfig.model,
  );

  final GeneratedImage edited;
  try {
    edited = await service.edit(
      imagePath: imagePath,
      prompt: trimmedPrompt,
      size: size ?? ref.read(imageGenerationConfigProvider).size,
    );
  } catch (e) {
    return '图片编辑失败：$e';
  }

  return _saveGeneratedImageConversation(
    ref: ref,
    session: session,
    modelId: modelId,
    userContent: userContent,
    assistantContent: '已编辑图片',
    filePrefix: 'edited',
    image: edited,
    sourceAttachment: _GeneratedSourceAttachment(
      path: imagePath,
      fileName: p.basename(imagePath),
      fileType: 'image',
    ),
  );
}

/// 使用当前渠道的通用媒体接口生成视频，并将最终内容作为 assistant
/// `video` 附件落到本地会话。参考图只取已选附件中的第一张图片。
Future<String?> generateVideo({
  required WidgetRef ref,
  required String sessionId,
  required String prompt,
  List<PendingAttachment> referenceAttachments = const [],
  Map<String, dynamic> extra = const <String, dynamic>{},
}) async {
  final sessionDao = ref.read(sessionDaoProvider);
  final channelDao = ref.read(channelDaoProvider);
  final trimmedPrompt = prompt.trim();
  if (trimmedPrompt.isEmpty) return '请输入视频描述';

  final session = await sessionDao.getSession(sessionId);
  if (session == null) return '会话不存在';
  final modelId = session.defaultChannelModelId;
  final modelInfo = modelId == null
      ? null
      : await channelDao.getModelWithChannel(modelId);
  if (modelInfo == null) return '请先选择一个模型';

  await ref.read(universalMediaConfigProvider.notifier).ready;
  final config = ref.read(universalMediaConfigProvider);
  final routeModelInfo = await _resolveUniversalMediaRouteModel(
    channelDao: channelDao,
    chatModel: modelInfo,
    config: config,
    kind: UniversalMediaKind.video,
  );
  if (routeModelInfo == null) {
    return '已选择的视频媒体渠道模型不存在或已被禁用，请到设置 → 视频 / 音乐 / 通用媒体接口重新选择';
  }
  final mediaModel = _configuredUniversalMediaModelName(
    config,
    UniversalMediaKind.video,
    routeModelInfo,
  );
  final mediaChannelModelId =
      _configuredUniversalMediaChannelModelId(
        config,
        UniversalMediaKind.video,
      ) ??
      modelInfo.channelModel.id;
  final capability = resolveUniversalMediaCapability(
    kind: UniversalMediaKind.video,
    protocol: routeModelInfo.channel.protocol,
    baseUrl: routeModelInfo.channel.baseUrl,
    apiKeyConfigured: routeModelInfo.channel.apiKeyEncrypted.trim().isNotEmpty,
    modelName: routeModelInfo.channelModel.modelName,
    modelCapability: routeModelInfo.channelModel.capability,
    modelCapabilities: routeModelInfo.capabilities,
    mediaModel: mediaModel,
    mediaEndpoint: config.videoEndpoint,
  );
  if (!capability.isAvailable) return capability.message;

  final referenceImagePath = referenceAttachments
      .where((attachment) => attachment.type == 'image')
      .map((attachment) => attachment.path)
      .firstOrNull;
  final String apiKey;
  try {
    apiKey = KeyEncryptor.decryptOrEmpty(
      routeModelInfo.channel.apiKeyEncrypted,
    );
  } catch (error) {
    return '当前渠道 API Key 无法读取，请重新配置';
  }
  final service = UniversalMediaService(
    baseUrl: routeModelInfo.channel.baseUrl,
    apiKey: apiKey,
    onJobUpdate: (job) =>
        ref.read(universalMediaTaskProvider(sessionId).notifier).updateJob(job),
  );
  final userContent = referenceImagePath == null
      ? '生成视频：$trimmedPrompt'
      : '参考图生成视频：$trimmedPrompt';
  final assistantContent = referenceImagePath == null ? '已生成视频' : '已根据参考图生成视频';
  return _runUniversalMediaTask(
    ref: ref,
    sessionId: sessionId,
    kind: UniversalMediaKind.video,
    service: service,
    model: mediaModel,
    endpoint: config.videoEndpoint,
    taskOptions: config.videoTaskOptions,
    extra: extra,
    prompt: trimmedPrompt,
    referenceImagePath: referenceImagePath,
    channelModelId: mediaChannelModelId,
    deliveryUserContent: userContent,
    deliveryAssistantContent: assistantContent,
    deliveryFileType: 'video',
    saveAsset: (asset, job, operationId) => _saveGeneratedMediaConversation(
      ref: ref,
      session: session,
      modelId: mediaChannelModelId,
      userContent: userContent,
      assistantContent: assistantContent,
      fileType: 'video',
      directoryName: 'generated_videos',
      filePrefix: 'generated-video',
      extension: asset.extension,
      mimeType: asset.mimeType,
      bytes: asset.bytes,
      sourceAttachment: referenceImagePath == null
          ? null
          : _GeneratedSourceAttachment(
              path: referenceImagePath,
              fileName:
                  referenceAttachments
                      .where((attachment) => attachment.type == 'image')
                      .map((attachment) => attachment.name)
                      .firstOrNull ??
                  p.basename(referenceImagePath),
              fileType: 'image',
            ),
      mediaJob: job,
      operationId: operationId,
    ),
  );
}

/// 通过通用音频接口生成音乐。音乐结果使用 `audio` 附件展示，
/// 与 STT / TTS 的播放器和导出链路保持一致。
Future<String?> generateMusic({
  required WidgetRef ref,
  required String sessionId,
  required String prompt,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) async {
  final sessionDao = ref.read(sessionDaoProvider);
  final channelDao = ref.read(channelDaoProvider);
  final trimmedPrompt = prompt.trim();
  if (trimmedPrompt.isEmpty) return '请输入音乐描述';

  final session = await sessionDao.getSession(sessionId);
  if (session == null) return '会话不存在';
  final modelId = session.defaultChannelModelId;
  final modelInfo = modelId == null
      ? null
      : await channelDao.getModelWithChannel(modelId);
  if (modelInfo == null) return '请先选择一个模型';

  await ref.read(universalMediaConfigProvider.notifier).ready;
  final config = ref.read(universalMediaConfigProvider);
  final routeModelInfo = await _resolveUniversalMediaRouteModel(
    channelDao: channelDao,
    chatModel: modelInfo,
    config: config,
    kind: UniversalMediaKind.music,
  );
  if (routeModelInfo == null) {
    return '已选择的音乐媒体渠道模型不存在或已被禁用，请到设置 → 视频 / 音乐 / 通用媒体接口重新选择';
  }
  final mediaModel = _configuredUniversalMediaModelName(
    config,
    UniversalMediaKind.music,
    routeModelInfo,
  );
  final mediaChannelModelId =
      _configuredUniversalMediaChannelModelId(
        config,
        UniversalMediaKind.music,
      ) ??
      modelInfo.channelModel.id;
  final capability = resolveUniversalMediaCapability(
    kind: UniversalMediaKind.music,
    protocol: routeModelInfo.channel.protocol,
    baseUrl: routeModelInfo.channel.baseUrl,
    apiKeyConfigured: routeModelInfo.channel.apiKeyEncrypted.trim().isNotEmpty,
    modelName: routeModelInfo.channelModel.modelName,
    modelCapability: routeModelInfo.channelModel.capability,
    modelCapabilities: routeModelInfo.capabilities,
    mediaModel: mediaModel,
    mediaEndpoint: config.musicEndpoint,
  );
  if (!capability.isAvailable) return capability.message;

  final String apiKey;
  try {
    apiKey = KeyEncryptor.decryptOrEmpty(
      routeModelInfo.channel.apiKeyEncrypted,
    );
  } catch (error) {
    return '当前渠道 API Key 无法读取，请重新配置';
  }
  final service = UniversalMediaService(
    baseUrl: routeModelInfo.channel.baseUrl,
    apiKey: apiKey,
    onJobUpdate: (job) =>
        ref.read(universalMediaTaskProvider(sessionId).notifier).updateJob(job),
  );
  const userContentPrefix = '生成音乐：';
  final userContent = '$userContentPrefix$trimmedPrompt';
  const assistantContent = '已生成音乐';
  return _runUniversalMediaTask(
    ref: ref,
    sessionId: sessionId,
    kind: UniversalMediaKind.music,
    service: service,
    model: mediaModel,
    endpoint: config.musicEndpoint,
    taskOptions: config.musicTaskOptions,
    extra: extra,
    prompt: trimmedPrompt,
    channelModelId: mediaChannelModelId,
    deliveryUserContent: userContent,
    deliveryAssistantContent: assistantContent,
    deliveryFileType: 'audio',
    saveAsset: (asset, job, operationId) => _saveGeneratedMediaConversation(
      ref: ref,
      session: session,
      modelId: mediaChannelModelId,
      userContent: userContent,
      assistantContent: assistantContent,
      fileType: 'audio',
      directoryName: 'generated_music',
      filePrefix: 'generated-music',
      extension: asset.extension,
      mimeType: asset.mimeType,
      bytes: asset.bytes,
      mediaJob: job,
      operationId: operationId,
    ),
  );
}

/// 将 TTS 从“只播放回复”扩展为可写回会话的声音合成动作。
///
/// [style] 和 [referenceAudioPath] 只覆盖本次请求，不写回
/// [TextToSpeechConfig]。声音克隆的路径会在 provider/engine 层读取并编码为
/// data URI；本机绝对路径不会进入请求 JSON。若未提供临时覆盖，则继续使用
/// 设置中已经归档的参考音频和风格描述。
Future<String?> synthesizeSpeechMessage({
  required WidgetRef ref,
  required String sessionId,
  required String text,
  String? style,
  String? referenceAudioPath,
}) async {
  final trimmedText = text.trim();
  if (trimmedText.isEmpty) return '请输入要合成的文字';
  await ref.read(textToSpeechConfigProvider.notifier).ready;
  final config = ref.read(textToSpeechConfigProvider);
  final service = ref.read(textToSpeechServiceProvider);

  final mode = config.requestedMode;
  final requestedStyle = style?.trim();
  final requestedReferenceAudioPath = referenceAudioPath?.trim();
  final effectiveStyle = requestedStyle?.isNotEmpty == true
      ? requestedStyle!
      : config.style.trim();
  final effectiveReferenceAudioPath =
      requestedReferenceAudioPath?.isNotEmpty == true
      ? requestedReferenceAudioPath
      : config.referenceAudioPath?.trim();

  // 这些字段只属于 SimiRouter 的明确模式。不能因为一个普通
  // OpenAI-compatible endpoint 的模型名碰巧相似，就把第三方能力伪造为
  // 已接入的声音设计 / 克隆。
  if (requestedStyle?.isNotEmpty == true &&
      mode != SimiRouterTtsMode.voiceDesign) {
    return '当前 TTS 模型未声明声音设计模式';
  }
  if (requestedReferenceAudioPath?.isNotEmpty == true &&
      mode != SimiRouterTtsMode.voiceClone) {
    return '当前 TTS 模型未声明声音克隆模式';
  }
  if ((mode == SimiRouterTtsMode.voiceDesign ||
          mode == SimiRouterTtsMode.voiceClone) &&
      !config.isSimiRouter) {
    return mode == SimiRouterTtsMode.voiceDesign
        ? '当前 TTS provider 未接入声音设计'
        : '当前 TTS provider 未接入参考音频声音克隆';
  }
  if (mode == SimiRouterTtsMode.voiceDesign && effectiveStyle.isEmpty) {
    return '声音设计需要填写声音风格描述';
  }
  if (mode == SimiRouterTtsMode.voiceClone &&
      (effectiveReferenceAudioPath == null ||
          effectiveReferenceAudioPath.isEmpty)) {
    return '声音克隆需要选择参考音频';
  }

  // TextToSpeechConfig.isConfigured 会把“缺少设置页归档参考音频”视为未
  // 配置。Composer 可以把本次第一条 audio 作为临时 referenceAudioPath，
  // 因此这里允许这一个明确的、可校验的临时缺口，但仍保留 enabled / Base
  // URL / model / voice / encrypted key / provider 的全部门禁。
  final hasUsableBaseConfig =
      config.enabled &&
      config.baseUrl.trim().isNotEmpty &&
      config.voice.trim().isNotEmpty &&
      config.hasApiKey &&
      (config.isXai ||
          config.isSimiRouter ||
          config.provider == kTextToSpeechProviderOpenAiCompatible) &&
      (config.isXai || config.model.trim().isNotEmpty);
  final hasTemporaryModeInput =
      (mode == SimiRouterTtsMode.voiceDesign &&
          requestedStyle?.isNotEmpty == true) ||
      (mode == SimiRouterTtsMode.voiceClone &&
          requestedReferenceAudioPath?.isNotEmpty == true);
  if (!hasUsableBaseConfig ||
      (!config.isConfigured && !hasTemporaryModeInput)) {
    return '请先在设置 → 语音与多模态中启用并配置 TTS';
  }

  final session = await ref.read(sessionDaoProvider).getSession(sessionId);
  if (session == null) return '会话不存在';
  final modelId = session.defaultChannelModelId;
  try {
    final usesModeSpecificRequest =
        mode == SimiRouterTtsMode.voiceDesign ||
        mode == SimiRouterTtsMode.voiceClone;
    final engine = usesModeSpecificRequest || service == null
        ? _buildSpeechEngineForRequest(
            config: config,
            style: effectiveStyle,
            referenceAudioPath: effectiveReferenceAudioPath,
          )
        : service.engine;
    final bytes = await engine.synthesize(
      TextToSpeechInput(text: trimmedText, voice: config.voice),
    );
    if (bytes.isEmpty) return '声音合成未返回音频';

    final actionLabel = switch (mode) {
      SimiRouterTtsMode.voiceClone => '声音克隆',
      SimiRouterTtsMode.voiceDesign => '声音设计',
      SimiRouterTtsMode.standard || null => '声音合成',
    };
    final assistantContent = switch (mode) {
      SimiRouterTtsMode.voiceClone => '已生成克隆语音',
      SimiRouterTtsMode.voiceDesign => '已生成设计语音',
      SimiRouterTtsMode.standard || null => '已生成语音',
    };
    return _saveGeneratedMediaConversation(
      ref: ref,
      session: session,
      modelId: modelId,
      userContent: '$actionLabel：$trimmedText',
      assistantContent: assistantContent,
      fileType: 'audio',
      directoryName: 'generated_speech',
      filePrefix: 'generated-speech',
      extension: normalizeTextToSpeechAudioFileExtension(config.responseFormat),
      bytes: bytes,
    );
  } catch (error) {
    return '声音合成失败：$error';
  }
}

TextToSpeechEngine _buildSpeechEngineForRequest({
  required TextToSpeechConfig config,
  required String style,
  required String? referenceAudioPath,
}) {
  if (config.isXai) {
    // xAI 的批量 TTS 是独立的 voice_id / /v1/tts 协议，当前函数的临时
    // style/reference 参数只适用于 SimiRouter mimo；不把字段静默丢给 xAI。
    throw const TextToSpeechException('当前 TTS provider 不支持该声音模式');
  }
  final encryptedKey = config.apiKeyEncrypted;
  if (encryptedKey == null || encryptedKey.isEmpty) {
    throw const TextToSpeechException('TTS API Key 未配置');
  }
  final apiKey = KeyEncryptor.decryptOrEmpty(encryptedKey).trim();
  if (apiKey.isEmpty) {
    throw const TextToSpeechException('TTS API Key 未配置');
  }
  return OpenAiCompatibleTextToSpeechEngine(
    baseUrl: config.baseUrl,
    apiKey: apiKey,
    model: config.model,
    speed: config.speed,
    responseFormat: config.responseFormat,
    style: style,
    referenceAudioPath: referenceAudioPath,
  );
}

Future<String?> _saveGeneratedImageConversation({
  required WidgetRef ref,
  required Session session,
  required String? modelId,
  required String userContent,
  required String assistantContent,
  required String filePrefix,
  required GeneratedImage image,
  _GeneratedSourceAttachment? sourceAttachment,
  bool includeUserMessage = true,
}) async {
  File? file;
  _StoredAttachment? archivedSource;
  late final String fileName;
  late final String userMsgId;
  late final String assistantMsgId;
  try {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'generated_images'));
    await directory.create(recursive: true);
    fileName = '$filePrefix-${_uuid.v4()}.${image.extension}';
    file = File(p.join(directory.path, fileName));
    await writeBytesAtomically(file, image.bytes);

    if (sourceAttachment != null) {
      archivedSource = await _archiveGeneratedSourceAttachment(
        sourceAttachment,
      );
    }

    userMsgId = _uuid.v4();
    assistantMsgId = _uuid.v4();
    final userTokens = TokenEstimator.estimate(userContent);
    final attachmentId = _uuid.v4();
    final database = ref.read(databaseProvider);
    final messageDao = ref.read(messageDaoProvider);
    final sessionDao = ref.read(sessionDaoProvider);
    final attachmentDao = ref.read(attachmentDaoProvider);
    await database.transaction(() async {
      if (includeUserMessage) {
        await messageDao.insertMessage(
          id: userMsgId,
          sessionId: session.id,
          role: 'user',
          content: userContent,
          tokens: userTokens,
        );
        if (archivedSource != null) {
          await attachmentDao.insertAttachment(
            id: archivedSource.id,
            messageId: userMsgId,
            fileType: archivedSource.fileType,
            localPath: archivedSource.localPath,
            fileName: archivedSource.fileName,
            fileSize: archivedSource.fileSize,
          );
        }
      }
      await messageDao.insertMessage(
        id: assistantMsgId,
        sessionId: session.id,
        role: 'assistant',
        content: assistantContent,
        tokens: 0,
        channelModelId: modelId,
      );
      await attachmentDao.insertAttachment(
        id: attachmentId,
        messageId: assistantMsgId,
        fileType: 'image',
        localPath: file!.path,
        fileName: fileName,
        fileSize: image.bytes.lengthInBytes,
      );
      await sessionDao.updateLastMessageAt(session.id);
      await sessionDao.updateTotalTokens(
        session.id,
        session.totalTokens + userTokens,
      );
    });
  } catch (_) {
    if (file != null) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (archivedSource != null) {
      try {
        final sourceFile = File(archivedSource.localPath);
        if (await sourceFile.exists()) await sourceFile.delete();
      } catch (_) {}
    }
    return '保存图片失败，请检查本机存储空间后重试';
  }

  // 数据库事务已提交，后续索引刷新/档案为派生动作；即使页面
  // 此时被关闭，也不回滚或删除已被消息附件引用的图片。
  try {
    unawaited(
      _appendConversationArchiveMessage(
        ref: ref,
        sessionId: session.id,
        sessionTitle: session.title,
        messageId: userMsgId,
        role: 'user',
        content: userContent,
        attachmentNames: archivedSource == null
            ? const []
            : [archivedSource.fileName],
      ),
    );
    unawaited(
      _appendConversationArchiveMessage(
        ref: ref,
        sessionId: session.id,
        sessionTitle: session.title,
        messageId: assistantMsgId,
        role: 'assistant',
        content: assistantContent,
        channelModelId: modelId,
        attachmentNames: [fileName],
      ),
    );
    ref.invalidate(messagesProvider(session.id));
    ref.invalidate(sessionsProvider);
  } catch (_) {
    // Widget 已销毁时不再刷新 UI；已提交的图片与消息保持有效。
  }
  return null;
}

Future<String?> _saveGeneratedMediaConversation({
  required WidgetRef ref,
  required Session session,
  required String? modelId,
  required String userContent,
  required String assistantContent,
  required String fileType,
  required String directoryName,
  required String filePrefix,
  required String extension,
  String? mimeType,
  required List<int> bytes,
  _GeneratedSourceAttachment? sourceAttachment,
  UniversalMediaJob? mediaJob,
  String? operationId,
}) async {
  if (mediaJob != null && operationId != null) {
    final error = await _deliverUniversalMediaResult(
      database: ref.read(databaseProvider),
      notifier: ref.read(universalMediaJobProvider.notifier),
      operationId: operationId,
      job: mediaJob,
      asset: UniversalMediaAsset(
        bytes: Uint8List.fromList(bytes),
        mimeType: mimeType ?? _normalizedMediaMime(fileType, extension),
        extension: extension,
      ),
      sessionId: session.id,
      channelModelId: modelId,
      userContent: userContent,
      assistantContent: assistantContent,
      fileType: fileType,
      directoryName: directoryName,
      filePrefix: filePrefix,
      sourceAttachment: sourceAttachment,
    );
    if (error == null) {
      ref.invalidate(messagesProvider(session.id));
      ref.invalidate(sessionsProvider);
    }
    return error;
  }
  File? file;
  _StoredAttachment? archivedSource;
  late final String fileName;
  late final String userMsgId;
  late final String assistantMsgId;
  try {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, directoryName));
    await directory.create(recursive: true);
    fileName = '$filePrefix-${_uuid.v4()}.$extension';
    file = File(p.join(directory.path, fileName));
    await writeBytesAtomically(file, bytes);

    if (sourceAttachment != null) {
      archivedSource = await _archiveGeneratedSourceAttachment(
        sourceAttachment,
      );
    }

    userMsgId = _uuid.v4();
    assistantMsgId = _uuid.v4();
    final userTokens = TokenEstimator.estimate(userContent);
    final attachmentId = _uuid.v4();
    final database = ref.read(databaseProvider);
    final messageDao = ref.read(messageDaoProvider);
    final sessionDao = ref.read(sessionDaoProvider);
    final attachmentDao = ref.read(attachmentDaoProvider);
    await database.transaction(() async {
      await messageDao.insertMessage(
        id: userMsgId,
        sessionId: session.id,
        role: 'user',
        content: userContent,
        tokens: userTokens,
      );
      if (archivedSource != null) {
        await attachmentDao.insertAttachment(
          id: archivedSource.id,
          messageId: userMsgId,
          fileType: archivedSource.fileType,
          localPath: archivedSource.localPath,
          fileName: archivedSource.fileName,
          fileSize: archivedSource.fileSize,
        );
      }
      await messageDao.insertMessage(
        id: assistantMsgId,
        sessionId: session.id,
        role: 'assistant',
        content: assistantContent,
        tokens: 0,
        channelModelId: modelId,
      );
      await attachmentDao.insertAttachment(
        id: attachmentId,
        messageId: assistantMsgId,
        fileType: fileType,
        localPath: file!.path,
        fileName: fileName,
        fileSize: bytes.length,
      );
      await sessionDao.updateLastMessageAt(session.id);
      await sessionDao.updateTotalTokens(
        session.id,
        session.totalTokens + userTokens,
      );
    });
  } catch (_) {
    try {
      final part = file == null ? null : File('${file.path}.part');
      if (part != null && await part.exists()) await part.delete();
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
    if (archivedSource != null) {
      try {
        final sourceFile = File(archivedSource.localPath);
        if (await sourceFile.exists()) await sourceFile.delete();
      } catch (_) {}
    }
    return '保存媒体失败，请检查本机存储空间后重试';
  }

  try {
    unawaited(
      _appendConversationArchiveMessage(
        ref: ref,
        sessionId: session.id,
        sessionTitle: session.title,
        messageId: userMsgId,
        role: 'user',
        content: userContent,
        attachmentNames: archivedSource == null
            ? const []
            : [archivedSource.fileName],
      ),
    );
    unawaited(
      _appendConversationArchiveMessage(
        ref: ref,
        sessionId: session.id,
        sessionTitle: session.title,
        messageId: assistantMsgId,
        role: 'assistant',
        content: assistantContent,
        channelModelId: modelId,
        attachmentNames: [fileName],
      ),
    );
    ref.invalidate(messagesProvider(session.id));
    ref.invalidate(sessionsProvider);
  } catch (_) {}
  return null;
}

/// 首帧之后触发一次持久化媒体恢复。恢复 coordinator 自身有幂等 guard，
/// 因此即使启动层因为生命周期重建再次调用，也不会创建第二个 worker。
Future<void> startUniversalMediaRecovery(WidgetRef ref) {
  final database = ref.read(databaseProvider);
  final notifier = ref.read(universalMediaJobProvider.notifier);
  return ref
      .read(universalMediaRecoveryProvider)
      .start(
        delivery: ({required row, required result, required leaseId}) {
          return deliverRecoveredUniversalMediaJob(
            database: database,
            notifier: notifier,
            row: row,
            result: result,
            leaseId: leaseId,
          );
        },
      );
}

/// 启动恢复使用的本地交付入口。它只依赖数据库和文件系统，便于使用
/// fake adapter 做回归测试；测试仍然只证明本地恢复 / 交付状态机，不是云端
/// E2E 或真实厂商 API 质量测试。
Future<void> deliverRecoveredUniversalMediaJob({
  required AppDatabase database,
  required UniversalMediaJobNotifier notifier,
  required MediaJob row,
  required UniversalMediaJobResult result,
  required String leaseId,
  Directory? rootDirectory,
}) async {
  final asset = result.asset ?? result.job.asset;
  if (asset == null) {
    throw const UniversalMediaException('恢复任务没有可交付的媒体内容');
  }
  final sessionId = row.sessionId?.trim();
  if (sessionId == null || sessionId.isEmpty) {
    throw const UniversalMediaException('恢复任务未绑定会话，无法交付媒体');
  }
  final persistedSource = row.deliverySourcePath == null
      ? null
      : _StoredAttachment(
          id:
              row.deliverySourceAttachmentId ??
              UniversalMediaDeliveryIds.forOperationId(
                row.id,
              ).sourceAttachmentId,
          fileName: row.deliverySourceFileName ?? 'reference-image',
          fileType: row.deliverySourceFileType ?? 'image',
          localPath: row.deliverySourcePath!,
          fileSize: 0,
        );
  final error = await _deliverUniversalMediaResult(
    database: database,
    notifier: notifier,
    operationId: row.id,
    job: result.job,
    asset: asset,
    sessionId: sessionId,
    channelModelId: row.channelModelId,
    userContent: row.deliveryUserContent ?? _defaultUniversalUserContent(row),
    assistantContent:
        row.deliveryAssistantContent ?? _defaultUniversalAssistantContent(row),
    fileType: row.deliveryFileType ?? _universalFileType(row.kind),
    directoryName: _universalDirectoryName(row.kind),
    filePrefix: _universalFilePrefix(row.kind),
    persistedSourceAttachment: persistedSource,
    rootDirectory: rootDirectory,
    leaseId: leaseId,
  );
  if (error != null) throw UniversalMediaException(error);
}

Future<String?> _deliverUniversalMediaResult({
  required AppDatabase database,
  required UniversalMediaJobNotifier notifier,
  required String operationId,
  required UniversalMediaJob job,
  required UniversalMediaAsset asset,
  required String sessionId,
  required String? channelModelId,
  required String userContent,
  required String assistantContent,
  required String fileType,
  required String directoryName,
  required String filePrefix,
  _GeneratedSourceAttachment? sourceAttachment,
  _StoredAttachment? persistedSourceAttachment,
  Directory? rootDirectory,
  String? leaseId,
}) async {
  File? outputFile;
  _StoredAttachment? archivedSource = persistedSourceAttachment;
  try {
    final root = rootDirectory ?? await getApplicationSupportDirectory();
    if (archivedSource != null && !p.isAbsolute(archivedSource.localPath)) {
      archivedSource = _StoredAttachment(
        id: archivedSource.id,
        fileName: archivedSource.fileName,
        fileType: archivedSource.fileType,
        localPath: _resolveMediaPath(root, archivedSource.localPath),
        fileSize: archivedSource.fileSize,
      );
    }
    final current = await database.mediaJobDao.getJob(job.id);
    if (current == null) return '媒体任务记录不存在，无法交付';
    if (current.status == media_database.mediaJobCompletedStatus &&
        current.deliveryPhase ==
            media_database.mediaJobDeliveryCompletedPhase) {
      notifier.releaseDeliveryLease(operationId);
      return null;
    }
    final ids = UniversalMediaDeliveryIds.fromDatabaseRow(current);
    final extension = current.assetExtension ?? asset.extension;
    final storedPath = current.assetPath;
    final outputPath = storedPath == null || storedPath.trim().isEmpty
        ? p.join(
            root.path,
            directoryName,
            '$filePrefix-${ids.fileStem}.$extension',
          )
        : _resolveMediaPath(root, storedPath);
    outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);

    // 先把稳定路径 / ID / 文案写入 saving，再开始任何本地写入。
    final prepared = await notifier.prepareDelivery(
      operationId: operationId,
      job: job,
      asset: asset,
      assetPath: outputFile.path,
      userContent: userContent,
      assistantContent: assistantContent,
      fileType: fileType,
      sourcePath: archivedSource?.localPath,
      sourceFileName: archivedSource?.fileName,
      sourceFileType: archivedSource?.fileType,
    );
    final effectiveLeaseId = leaseId ?? prepared?.leaseId;
    if (effectiveLeaseId == null) {
      return '媒体任务 lease 已失效，无法交付';
    }

    if (archivedSource == null && sourceAttachment != null) {
      archivedSource = await _archiveGeneratedSourceAttachment(
        sourceAttachment,
        attachmentId: ids.sourceAttachmentId,
        rootDirectory: root,
      );
      await notifier.prepareDelivery(
        operationId: operationId,
        job: job,
        asset: asset,
        assetPath: outputFile.path,
        userContent: userContent,
        assistantContent: assistantContent,
        fileType: fileType,
        sourcePath: archivedSource.localPath,
        sourceFileName: archivedSource.fileName,
        sourceFileType: archivedSource.fileType,
      );
    }

    await writeBytesAtomically(outputFile, asset.bytes);
    final written = await notifier.prepareDelivery(
      operationId: operationId,
      job: job,
      asset: asset,
      assetPath: outputFile.path,
      userContent: userContent,
      assistantContent: assistantContent,
      fileType: fileType,
      sourcePath: archivedSource?.localPath,
      sourceFileName: archivedSource?.fileName,
      sourceFileType: archivedSource?.fileType,
      deliveryPhase: media_database.mediaJobDeliveryFileWrittenPhase,
    );
    final finalLeaseId = written?.leaseId ?? effectiveLeaseId;

    final userTokens = TokenEstimator.estimate(userContent);
    final session = await database.sessionDao.getSession(sessionId);
    if (session == null) return '会话不存在，无法交付媒体';
    late final String userMessageId;
    late final String assistantMessageId;
    late final String attachmentId;
    await database.transaction(() async {
      final rowBeforeCommit = await database.mediaJobDao.getJob(job.id);
      if (rowBeforeCommit == null || rowBeforeCommit.leaseId != finalLeaseId) {
        throw const UniversalMediaLeaseLostException('媒体交付');
      }
      final plan = UniversalMediaDeliveryIds.fromDatabaseRow(rowBeforeCommit);
      userMessageId = plan.userMessageId;
      assistantMessageId = plan.assistantMessageId;
      attachmentId = plan.attachmentId;

      var insertedUser = false;
      final existingUser = await (database.select(
        database.messages,
      )..where((t) => t.id.equals(userMessageId))).getSingleOrNull();
      if (existingUser == null) {
        await database.messageDao.insertMessage(
          id: userMessageId,
          sessionId: sessionId,
          role: 'user',
          content: userContent,
          tokens: userTokens,
        );
        insertedUser = true;
      } else if (existingUser.sessionId != sessionId ||
          existingUser.role != 'user' ||
          existingUser.content != userContent) {
        throw const FormatException('媒体交付用户消息 ID 已绑定到其它内容');
      }

      if (archivedSource != null) {
        final existingSource = await (database.select(
          database.attachments,
        )..where((t) => t.id.equals(archivedSource!.id))).getSingleOrNull();
        if (existingSource == null) {
          final sourceFile = File(archivedSource.localPath);
          if (!await sourceFile.exists()) {
            throw const FileSystemException('参考附件不存在');
          }
          await database.attachmentDao.insertAttachment(
            id: archivedSource.id,
            messageId: userMessageId,
            fileType: archivedSource.fileType,
            localPath: archivedSource.localPath,
            fileName: archivedSource.fileName,
            fileSize: await sourceFile.length(),
          );
        } else if (existingSource.messageId != userMessageId) {
          throw const FormatException('媒体交付参考附件 ID 已绑定到其它消息');
        }
      }

      final existingAssistant = await (database.select(
        database.messages,
      )..where((t) => t.id.equals(assistantMessageId))).getSingleOrNull();
      if (existingAssistant == null) {
        await database.messageDao.insertMessage(
          id: assistantMessageId,
          sessionId: sessionId,
          role: 'assistant',
          content: assistantContent,
          tokens: 0,
          channelModelId: channelModelId,
        );
      } else if (existingAssistant.sessionId != sessionId ||
          existingAssistant.role != 'assistant' ||
          existingAssistant.content != assistantContent) {
        throw const FormatException('媒体交付助手消息 ID 已绑定到其它内容');
      }

      final existingAttachment = await (database.select(
        database.attachments,
      )..where((t) => t.id.equals(attachmentId))).getSingleOrNull();
      if (existingAttachment == null) {
        if (!await outputFile!.exists()) {
          throw const FileSystemException('生成媒体文件不存在');
        }
        await database.attachmentDao.insertAttachment(
          id: attachmentId,
          messageId: assistantMessageId,
          fileType: fileType,
          localPath: outputFile.path,
          fileName: p.basename(outputFile.path),
          fileSize: await outputFile.length(),
        );
      } else if (existingAttachment.messageId != assistantMessageId ||
          existingAttachment.localPath != outputFile!.path) {
        throw const FormatException('媒体交付附件 ID 已绑定到其它文件');
      }

      final currentSession = await database.sessionDao.getSession(sessionId);
      if (currentSession != null) {
        await database.sessionDao.updateLastMessageAt(sessionId);
        if (insertedUser) {
          await database.sessionDao.updateTotalTokens(
            sessionId,
            currentSession.totalTokens + userTokens,
          );
        }
      }

      final completed = await database.mediaJobDao.completeJob(
        job.id,
        assetPath: outputFile.path,
        assetMime: asset.mimeType,
        assetExtension: asset.extension,
        leaseId: finalLeaseId,
        deliveryUserMessageId: userMessageId,
        deliveryAssistantMessageId: assistantMessageId,
        deliveryAttachmentId: attachmentId,
        deliverySourceAttachmentId: archivedSource?.id,
        deliveryPhase: media_database.mediaJobDeliveryCompletedPhase,
      );
      if (completed?.status != media_database.mediaJobCompletedStatus ||
          completed?.deliveryPhase !=
              media_database.mediaJobDeliveryCompletedPhase) {
        throw const UniversalMediaLeaseLostException('媒体交付提交');
      }
    });
    notifier.releaseDeliveryLease(operationId);
    return null;
  } catch (error) {
    return '保存媒体失败：${_universalMediaFailureText(error, kind: job.kind)}';
  }
}

String _resolveMediaPath(Directory root, String rawPath) {
  final normalized = rawPath.trim();
  if (p.isAbsolute(normalized)) return normalized;
  return p.join(root.path, normalized);
}

String _normalizedMediaMime(String fileType, String extension) {
  final normalized = extension.toLowerCase().replaceFirst('.', '');
  return switch (fileType) {
    'video' => normalized == 'webm' ? 'video/webm' : 'video/mp4',
    'audio' => normalized == 'wav' ? 'audio/wav' : 'audio/mpeg',
    _ => normalized == 'webp' ? 'image/webp' : 'image/png',
  };
}

String _universalFileType(String kind) {
  return switch (kind) {
    'music' => 'audio',
    'image' => 'image',
    _ => 'video',
  };
}

String _universalDirectoryName(String kind) {
  return switch (kind) {
    'music' => 'generated_music',
    'image' => 'generated_images',
    _ => 'generated_videos',
  };
}

String _universalFilePrefix(String kind) {
  return switch (kind) {
    'music' => 'generated-music',
    'image' => 'generated-image',
    _ => 'generated-video',
  };
}

String _defaultUniversalUserContent(MediaJob row) {
  final prompt = row.prompt?.trim() ?? '';
  return switch (row.kind) {
    'music' => '生成音乐：$prompt',
    'image' => prompt,
    _ => '生成视频：$prompt',
  };
}

String _defaultUniversalAssistantContent(MediaJob row) {
  return switch (row.kind) {
    'music' => '已生成音乐',
    'image' => '已生成图片',
    _ => '已生成视频',
  };
}

/// 替身回复：仅当用户显式授权时，用镜像人格 system prompt 为最近一条用户消息生成回复。
///
/// 返回 null 表示成功，否则返回用户可读的错误信息。
Future<String?> generatePersonaReply({
  required WidgetRef ref,
  required String sessionId,
}) async {
  final auth = ref.read(personaAuthorizationProvider);
  if (!auth.isAuthorized) {
    return '替身回复尚未授权，请先在设置 → 数字孪生中显式启用。';
  }

  final messageDao = ref.read(messageDaoProvider);
  final sessionDao = ref.read(sessionDaoProvider);
  final channelDao = ref.read(channelDaoProvider);

  final session = await sessionDao.getSession(sessionId);
  if (session == null) return '会话不存在';

  final modelId = session.defaultChannelModelId;
  final modelInfo = modelId == null
      ? null
      : await channelDao.getModelWithChannel(modelId);
  if (modelInfo == null) return '请先选择一个模型';

  // 最近一条用户消息。
  final messages = await messageDao.getMessagesBySession(sessionId);
  Message? lastUser;
  for (final message in messages.reversed) {
    if (message.role == 'user') {
      lastUser = message;
      break;
    }
  }
  if (lastUser == null) return '当前没有可替身回复的用户消息';

  // 人格配置（来自本地用户画像）。
  final profile = ref.read(userProfileProvider);
  final persona = const PersonaProfileGenerator().fromUserProfile(
    profile ?? UserProfile.empty(),
  );
  if (persona.isEmpty) return '画像信号不足，暂无可生成的人格配置';

  // 上下文：最近若干条消息。
  final recent = messages.length <= 10
      ? messages
      : messages.sublist(messages.length - 10);
  final contextMessages = recent
      .map((m) => ai.AiMessage(role: m.role, content: m.content))
      .toList(growable: false);

  final apiKey = KeyEncryptor.decryptOrEmpty(modelInfo.channel.apiKeyEncrypted);
  final buffer = StringBuffer();
  try {
    await for (final chunk in AiService.sendMessage(
      protocol: modelInfo.channel.protocol,
      baseUrl: modelInfo.channel.baseUrl,
      apiKey: apiKey,
      model: modelInfo.channelModel.modelName,
      messages: contextMessages,
      systemPrompt: persona.buildPersonaSystemPrompt(),
    )) {
      final content = chunk.content ?? '';
      if (content.isNotEmpty) buffer.write(content);
    }
  } catch (e) {
    return '替身回复失败：$e';
  }

  final reply = buffer.toString().trim();
  if (reply.isEmpty) return '替身回复未生成有效内容';

  final assistantMsgId = _uuid.v4();
  await messageDao.insertMessage(
    id: assistantMsgId,
    sessionId: sessionId,
    role: 'assistant',
    content: reply,
    tokens: TokenEstimator.estimate(reply),
    channelModelId: modelId,
  );
  unawaited(
    _appendConversationArchiveMessage(
      ref: ref,
      sessionId: sessionId,
      sessionTitle: session.title,
      messageId: assistantMsgId,
      role: 'assistant',
      content: reply,
      channelModelId: modelId,
    ),
  );
  await sessionDao.updateLastMessageAt(sessionId);

  // 审计：记录本次替身回复。
  try {
    await ref
        .read(personaAuditLogDaoProvider)
        .insertLog(
          eventType: PersonaAuditEventType.personaReply,
          sessionId: sessionId,
          messageId: assistantMsgId,
          summary: '替身回复 ${reply.length} 字符',
        );
  } catch (_) {}

  ref.invalidate(messagesProvider(sessionId));
  ref.invalidate(sessionsProvider);
  return null;
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
  required int maxInputTokens,
  required int operation,
}) async {
  if (!_isCurrentSendOperation(sessionId, operation)) return;
  try {
    const maxToolRounds = 3;
    var toolRound = 0;
    var totalTokens = session.totalTokens + userTokens;
    var contextLimitRetryCount = 0;

    while (toolRound < maxToolRounds) {
      if (!_isCurrentSendOperation(sessionId, operation)) return;
      final assistantMsgId = _uuid.v4();
      final buffer = StringBuffer();
      final thinkingBuffer = StringBuffer();
      final stopwatch = Stopwatch()..start();
      final completer = Completer<void>();
      _responseCompletions[sessionId] = completer;
      bool firstTokenReceived = false;
      Object? streamError;
      final cancelToken = CancelToken();
      _cancelTokens[sessionId] = cancelToken;

      ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
        isStreaming: true,
        modelId: modelId,
        isWaitingForFirstToken: true,
      );

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
                .state = StreamState(
              isStreaming: true,
              modelId: modelId,
              isWaitingForFirstToken: false,
            );
          }
          if (chunk.content != null) buffer.write(chunk.content);
          if (chunk.thinking != null) thinkingBuffer.write(chunk.thinking);
          ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
            isStreaming: true,
            currentContent: buffer.toString(),
            currentThinking: thinkingBuffer.toString(),
            modelId: modelId,
            isWaitingForFirstToken: false,
          );
        },
        onError: (Object e) {
          if (!completer.isCompleted) {
            streamError = e;
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

      // 用户 Stop 可能在 STT / SSE future 完成之前发生。generation 不同
      // 时直接退出，禁止把部分回答落成 assistant，也禁止启动下一轮工具调用。
      if (!_isCurrentSendOperation(sessionId, operation)) return;

      final interruptedCancellationError = _interruptedStreamCancellationErrors
          .remove(sessionId);
      if (interruptedCancellationError != null) {
        ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
          isStreaming: false,
          modelId: modelId,
          error: interruptedCancellationError,
        );
        return;
      }

      if (streamError != null) {
        if (_isContextLimitError(streamError!) && contextLimitRetryCount < 1) {
          final retryBudget = _strictRetryInputBudget(maxInputTokens);
          final trimmedMessages = trimAiMessagesToTokenBudget(
            systemPrompt: systemPrompt,
            messages: contextMessages,
            maxInputTokens: retryBudget,
          );
          if (trimmedMessages.isNotEmpty) {
            contextLimitRetryCount++;
            contextMessages = trimmedMessages;
            ref
                .read(streamStateProvider(sessionId).notifier)
                .state = StreamState(
              isStreaming: true,
              modelId: modelId,
              isWaitingForFirstToken: true,
            );
            continue;
          }
        }

        ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
          isStreaming: false,
          modelId: modelId,
          error: _isContextLimitError(streamError!)
              ? _contextLimitUserMessage
              : streamError.toString(),
        );
        return;
      }

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
          ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
            isStreaming: false,
            modelId: modelId,
          );
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

      ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
        isStreaming: false,
        modelId: modelId,
      );
      ref.invalidate(messagesProvider(sessionId));
      ref.invalidate(sessionsProvider);

      unawaited(
        NotificationService().showResponseComplete(
          sessionTitle: session.title ?? '新会话',
          preview: responseContent,
        ),
      );

      if (session.title == null || session.title!.trim().isEmpty) {
        unawaited(_generateTitle(ref, sessionId, responseContent, modelInfo));
      }

      final threshold = dynamicCompressThresholdForBudget(
        resolveModelContextBudget(
          protocol: modelInfo.channel.protocol,
          modelName: modelInfo.channelModel.modelName,
        ),
        ref.read(compressThresholdProvider),
      );
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
    if (!_isCurrentSendOperation(sessionId, operation)) return;
    ref.read(streamStateProvider(sessionId).notifier).state = StreamState(
      isStreaming: false,
      modelId: modelId,
      error: e.toString(),
    );
  } finally {
    if (_isCurrentSendOperation(sessionId, operation)) {
      _streamSubscriptions.remove(sessionId);
      _cancelTokens.remove(sessionId);
      _responseCompletions.remove(sessionId);
      _interruptedStreamCancellationErrors.remove(sessionId);
    }
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
  // 同一会话的标题生成在途时直接跳过，防止标题为空期间第二条回复
  // 触发第二次生成。
  if (!_titleGenerationInFlight.add(sessionId)) return;
  try {
    final sessionDao = ref.read(sessionDaoProvider);
    // 写前复查：用户可能已在生成期间手动重命名。
    final current = await sessionDao.getSession(sessionId);
    if (current == null) return;
    final existingTitle = current.title?.trim() ?? '';
    if (existingTitle.isNotEmpty) return;

    // 优先用第一条用户消息概括主题，兜底用助手首条回复。
    final messages = await ref
        .read(messageDaoProvider)
        .getMessagesBySession(sessionId);
    final firstUser = messages
        .where((m) => m.role == 'user' && m.content.trim().isNotEmpty)
        .map((m) => m.content)
        .firstOrNull;
    final subjectSource = firstUser ?? firstReply;
    var subject = subjectSource.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (subject.length > 400) subject = subject.substring(0, 400);

    final apiKey = KeyEncryptor.decryptOrEmpty(
      modelInfo.channel.apiKeyEncrypted,
    );
    final buffer = StringBuffer();
    final stream = AiService.sendMessage(
      protocol: modelInfo.channel.protocol,
      baseUrl: modelInfo.channel.baseUrl,
      apiKey: apiKey,
      model: modelInfo.channelModel.modelName,
      messages: [
        ai.AiMessage(
          role: 'user',
          content: '请用 10 字以内概括下面这段对话的主题，只输出标题本身，不要引号或标点：\n$subject',
        ),
      ],
    );
    // 流式接收默认超时 5 分钟，标题请求挂起时需要尽快放弃。
    await stream.timeout(const Duration(seconds: 30)).forEach((chunk) {
      if (chunk.content != null) buffer.write(chunk.content);
    });

    var title = buffer.toString().trim();
    if (title.isNotEmpty) {
      if (title.length > 30) title = title.substring(0, 30);
      await sessionDao.updateTitle(sessionId, title);
      unawaited(syncConversationArchiveTitle(ref, sessionId));
      ref.invalidate(sessionsProvider);
      ref.invalidate(activeSessionProvider);
    }
  } catch (_) {
    // 标题生成失败不影响主流程
  } finally {
    _titleGenerationInFlight.remove(sessionId);
  }
}
