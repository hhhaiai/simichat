import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai/universal_media_service.dart';
import '../../core/ai/model_capability.dart';
import '../../core/ai/model_switch_record.dart';
import '../../core/media/audio_player.dart';
import '../../core/media/audio_transcription_service.dart';
import '../../core/media/audio_transcript_archive.dart';
import '../../core/media/attachment_export_service.dart';
import '../../core/media/media_provider_profile.dart';
import '../../core/media/media_request_options.dart';
import '../../core/media/baidu_cdn_image_uploader.dart';
import '../../core/media/openai_text_to_speech_engine.dart'
    show TextToSpeechVoiceOption;
import '../../core/media/speech_provider_preset.dart';
import '../../core/database/dao/channel_dao.dart';
import '../../core/database/app_database.dart' show ChunkedContentTask;
import '../../core/context/chunked_content_task.dart';
import '../../shared/providers/audio_transcription_provider.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/providers/image_generation_provider.dart';
import '../../shared/providers/image_generation_tasks_provider.dart';
import '../../shared/providers/channel_provider.dart';
import '../../shared/providers/chat_composer_draft_store.dart';
import '../../shared/providers/connectivity_provider.dart';
import '../../shared/providers/creation_mode_provider.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/prompt_provider.dart';
import '../../shared/providers/session_provider.dart';
import '../../shared/providers/text_to_speech_provider.dart';
import '../../shared/providers/universal_media_provider.dart';
import '../../shared/widgets/message_bubble.dart';
import '../../shared/widgets/image_viewer.dart';
import '../../shared/widgets/streaming_bubble.dart';
import '../../shared/widgets/realtime_voice_panel.dart';
import 'image_edit_dialog.dart';
import '../../shared/widgets/chat_input_bar.dart'
    show
        ChatComposerDraft,
        ChatInputBar,
        ComposerSendOutcome,
        PendingAttachment,
        VideoGenerationConfig;

class _MediaRetryDraft {
  const _MediaRetryDraft({
    required this.kind,
    required this.prompt,
    required this.attachments,
    this.videoConfig,
  });

  final UniversalMediaKind kind;
  final String prompt;
  final List<PendingAttachment> attachments;
  final VideoGenerationConfig? videoConfig;
}

/// 图片生成面板的本次任务快照。它不写入设置页，只有用户点击“开始生成”
/// 后才转换为 [ImageGenerationOptions]，这样切换模型或取消面板不会污染
/// 下一次请求。
class _ImageGenerationTaskDraft {
  const _ImageGenerationTaskDraft({
    required this.model,
    required this.prompt,
    required this.referenceImages,
    required this.count,
    required this.aspectRatio,
    required this.resolution,
    required this.size,
    required this.quality,
  });

  final ChannelModelWithChannel model;
  final String prompt;
  final List<PendingAttachment> referenceImages;
  final int count;
  final String? aspectRatio;
  final String? resolution;
  final String? size;
  final String? quality;
}

class _SpeechSynthesisTaskDraft {
  const _SpeechSynthesisTaskDraft({
    required this.text,
    required this.voice,
    required this.speed,
    required this.responseFormat,
  });

  final String text;
  final String voice;
  final double speed;
  final String responseFormat;
}

class _VoiceDesignTaskDraft {
  const _VoiceDesignTaskDraft({
    required this.text,
    required this.style,
    required this.speed,
    required this.responseFormat,
  });

  final String text;
  final String style;
  final double speed;
  final String responseFormat;
}

class _VoiceCloneTaskDraft {
  const _VoiceCloneTaskDraft({
    required this.text,
    required this.referenceAudio,
    required this.speed,
    required this.responseFormat,
  });

  final String text;
  final PendingAttachment? referenceAudio;
  final double speed;
  final String responseFormat;
}

class _SpeechRecognitionTaskDraft {
  const _SpeechRecognitionTaskDraft({
    required this.referenceAudio,
    required this.language,
  });

  final PendingAttachment referenceAudio;
  final SpeechRecognitionLanguage language;
}

/// 长内容的持久化工作卡。它不渲染中间 chunk 文本，只显示状态和可恢复
/// 操作；最终回答仍以普通 assistant 气泡交付，避免把内部工作过程混入聊天
/// 时间线。
class _ChunkedContentTaskCard extends StatelessWidget {
  const _ChunkedContentTaskCard({
    required this.task,
    this.onContinue,
    this.onRestart,
    this.onStop,
  });

  final ChunkedContentTask task;
  final VoidCallback? onContinue;
  final VoidCallback? onRestart;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final status = ChunkedContentTaskStatusX.parse(task.status);
    final strategy = ChunkedContentStrategyX.parse(task.strategy);
    final active = !status.isTerminal;
    final progress = task.totalChunks <= 0
        ? null
        : (task.completedChunks / task.totalChunks).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '长内容任务，${status.label}',
      child: Container(
        key: ValueKey('chunked-content-task-${task.id}'),
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.58,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.58),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.auto_awesome : Icons.work_outline_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '长内容 · ${strategy.label}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: active
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (task.totalChunks > 0) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 6),
              Text(
                status == ChunkedContentTaskStatus.reducing
                    ? '所有分段已完成，正在生成最终回答'
                    : '已处理 ${task.completedChunks}/${task.totalChunks} 段',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else
              Text(
                '正在读取并切分已归档的文本附件',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (status == ChunkedContentTaskStatus.failed &&
                (task.error?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 6),
              Text(
                task.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
              ),
            ],
            if (active || onContinue != null || onRestart != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (active && onStop != null)
                    TextButton.icon(
                      key: ValueKey('chunked-content-stop-${task.id}'),
                      onPressed: onStop,
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('停止'),
                    ),
                  if (!active && onContinue != null)
                    TextButton.icon(
                      key: ValueKey('chunked-content-continue-${task.id}'),
                      onPressed: onContinue,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('继续'),
                    ),
                  if (!active && onRestart != null)
                    TextButton.icon(
                      key: ValueKey('chunked-content-restart-${task.id}'),
                      onPressed: onRestart,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('从头重试'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _hasTextNotifier = ValueNotifier<bool>(false);

  /// 深度思考开关（会话内草稿状态）：开启后发送走 reasoner 模型。
  final _deepThinkEnabled = ValueNotifier<bool>(false);

  // 输入草稿缓存：按 sessionId 保存文本、附件和深度思考状态。
  static final Map<String, ChatComposerDraft> _draftCache = {};
  static const _maxDraftCacheSize = 50;
  // Before the first session exists, ChatInputBar still owns real files. Keep
  // that draft in page state so creating the session cannot dispose the empty
  // composer and lose its attachments while a request is in flight or fails.
  ChatComposerDraft _emptyComposerDraft = const ChatComposerDraft();
  String? _draftSessionId;
  late final ChatComposerDraftStore _composerDraftStore;
  int _composerDraftRestoreGeneration = 0;
  int _composerDraftMutationGeneration = 0;
  int _composerDraftRevision = 0;
  bool _isApplyingComposerDraft = false;

  // 滚动监听：距底部超过一屏时显示 FAB
  bool _showScrollFab = false;
  bool _shouldAutoScroll = true;
  bool _isProgrammaticScroll = false;

  // 会话内临时模型覆盖
  String? _pendingModelId;
  bool _isSubmitting = false;
  bool _isUploadingImageCdn = false;
  // Composer 动作可能在会话切换后才返回。generation 用来区分“仍在运行”
  // 和用户已经 Stop 的旧动作；sessionId 则用来阻止旧动作清理当前会话的
  // composer。持久化层仍然使用动作开始时捕获的 sessionId。
  int _composerOperationGeneration = 0;
  int? _activeComposerOperationGeneration;
  String? _activeComposerOperationSessionId;
  // 失败 / 取消的媒体任务按 session 保存原始提示词和实际参考附件。
  // 不把凭据或媒体 bytes 放入这里；重试只复用用户仍持有的 draft 路径。
  final Map<String, _MediaRetryDraft> _mediaRetryDrafts = {};
  String? _speakingMessageId;
  String? _speakingAudioPath;
  String? _playingAttachmentPath;
  String? _lastTerminalSpeechAudioPath;
  String? _lastTerminalPlaybackPath;
  bool _isPreparingSpeech = false;
  int _speechRequestId = 0;
  int _attachmentPlaybackRequestId = 0;
  String? _blockedSendWhileOfflineSessionId;
  StreamSubscription<AudioPlaybackEvent>? _audioPlaybackSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composerDraftStore = ref.read(chatComposerDraftStoreProvider);
    _inputController.addListener(_onTextChanged);
    _scrollController.addListener(_onScrollChanged);
    // ref.listen 不会回放已存在的初始值；首次 build 可能已经有活动会话，
    // 此时也必须恢复该会话的附件 / 文本 / 深度思考草稿，而不是只在 A→B
    // 切换时恢复。
    _restoreComposerDraft(ref.read(activeSessionIdProvider));
    _audioPlaybackSubscription = ref
        .read(audioPlayerProvider)
        .events
        .listen(_handleAudioPlaybackEvent);
  }

  @override
  void dispose() {
    _persistCurrentComposerDraft();
    WidgetsBinding.instance.removeObserver(this);
    _inputController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScrollChanged);
    _hasTextNotifier.dispose();
    _deepThinkEnabled.dispose();
    _audioPlaybackSubscription?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistCurrentComposerDraft();
    }
  }

  void _handleAudioPlaybackEvent(AudioPlaybackEvent event) {
    if (!mounted) return;
    final path = event.path;
    switch (event.type) {
      case AudioPlaybackEventType.completed:
      case AudioPlaybackEventType.stopped:
      case AudioPlaybackEventType.error:
        // Native error callbacks can omit path. The audio channel is shared
        // by TTS and message attachments, so a pathless terminal event must
        // still invalidate both UI states and any pending preparation.
        if (path == null) {
          _speechRequestId++;
          _attachmentPlaybackRequestId++;
          setState(() {
            _speakingMessageId = null;
            _speakingAudioPath = null;
            _isPreparingSpeech = false;
            _playingAttachmentPath = null;
          });
          return;
        }
        final activePlaybackPath = _playingAttachmentPath;
        final activeSpeechPath = _speakingAudioPath;
        final matchesAttachment = _audioPlaybackPathsMatch(
          activePlaybackPath,
          path,
        );
        final matchesSpeech = _audioPlaybackPathsMatch(activeSpeechPath, path);
        _lastTerminalSpeechAudioPath = matchesSpeech ? activeSpeechPath : path;
        _lastTerminalPlaybackPath = matchesAttachment
            ? activePlaybackPath
            : path;
        var changed = false;
        if (matchesAttachment) {
          changed = true;
        }
        if (matchesSpeech) changed = true;
        if (!changed) return;
        setState(() {
          if (matchesAttachment) _playingAttachmentPath = null;
          if (matchesSpeech) {
            _speakingMessageId = null;
            _speakingAudioPath = null;
            _isPreparingSpeech = false;
          }
        });
    }
  }

  /// Android's native player validates and canonicalizes an app-private path
  /// before playback. On devices where the same private file is exposed via
  /// equivalent mount aliases (for example `/data/user/0/...` and
  /// `/data/data/...`), the completion callback can therefore return a path
  /// string different from the SQLite attachment path. The native channel has
  /// only one active MediaPlayer, so compare canonical files and retain a
  /// basename/size fallback for bind-mount aliases that `realpath` cannot
  /// collapse. A different generated UUID basename never clears the current
  /// playback state.
  bool _audioPlaybackPathsMatch(String? activePath, String eventPath) {
    final active = activePath?.trim();
    final event = eventPath.trim();
    if (active == null || active.isEmpty || event.isEmpty) return false;
    if (p.normalize(active) == p.normalize(event)) return true;
    try {
      final activeFile = File(active);
      final eventFile = File(event);
      if (activeFile.resolveSymbolicLinksSync() ==
          eventFile.resolveSymbolicLinksSync()) {
        return true;
      }
      if (p.basename(active) != p.basename(event) ||
          !activeFile.existsSync() ||
          !eventFile.existsSync()) {
        return false;
      }
      return activeFile.lengthSync() == eventFile.lengthSync();
    } on FileSystemException {
      return false;
    }
  }

  void _onTextChanged() {
    final hasText = _inputController.text.trim().isNotEmpty;
    if (_hasTextNotifier.value != hasText) {
      _hasTextNotifier.value = hasText;
    }
    // 缓存当前 session 的文本；切换会话时由 listener 先更新
    // [_draftSessionId]，避免把恢复动作写回旧会话。
    if (_isApplyingComposerDraft) return;
    final currentId = ref.read(activeSessionIdProvider);
    if (currentId != null && currentId == _draftSessionId) {
      _composerDraftMutationGeneration++;
      _saveDraft(currentId, text: _inputController.text);
    }
  }

  bool _isCurrentOperationSession(String? operationSessionId) {
    return mounted && ref.read(activeSessionIdProvider) == operationSessionId;
  }

  int _beginComposerOperation(String? operationSessionId) {
    final generation = ++_composerOperationGeneration;
    _activeComposerOperationGeneration = generation;
    _activeComposerOperationSessionId = operationSessionId;
    return generation;
  }

  bool _isComposerOperationLive(int generation) {
    return _activeComposerOperationGeneration == generation;
  }

  void _adoptComposerOperationSession(int generation, String? sessionId) {
    if (_activeComposerOperationGeneration != generation) return;
    _activeComposerOperationSessionId = sessionId;
  }

  void _setSubmitting(bool value) {
    if (!mounted) {
      _isSubmitting = value;
      return;
    }
    if (_isSubmitting == value) return;
    setState(() => _isSubmitting = value);
  }

  void _restoreOperationTextIfUnchanged({
    required String submittedText,
    required String restoredText,
    required String? sessionId,
  }) {
    if (!_isCurrentOperationSession(sessionId) ||
        _inputController.text != submittedText) {
      return;
    }
    _inputController.value = TextEditingValue(
      text: restoredText,
      selection: TextSelection.collapsed(offset: restoredText.length),
    );
    _hasTextNotifier.value = restoredText.trim().isNotEmpty;
    if (sessionId != null) _saveDraft(sessionId, text: restoredText);
  }

  void _finishComposerOperation(int generation) {
    if (_activeComposerOperationGeneration != generation) return;
    _activeComposerOperationGeneration = null;
    _activeComposerOperationSessionId = null;
    _setSubmitting(false);
  }

  /// 使准备、归档、STT 或网络请求阶段的旧动作失效。旧 future 可以继续
  /// 完成并把消息写入它捕获的会话，但它不能再清理当前 composer。
  void _cancelActiveComposerOperation() {
    if (_activeComposerOperationGeneration == null) return;
    ++_composerOperationGeneration;
    _activeComposerOperationGeneration = null;
    _activeComposerOperationSessionId = null;
    _setSubmitting(false);
  }

  void _cancelComposerOperationForSession(String? sessionId) {
    if (_activeComposerOperationGeneration == null) return;
    if (_activeComposerOperationSessionId != sessionId) return;
    _cancelActiveComposerOperation();
  }

  void _saveDraft(
    String sessionId, {
    String? text,
    List<PendingAttachment>? attachments,
    bool? deepThink,
  }) {
    final previous = _draftCache[sessionId] ?? const ChatComposerDraft();
    final snapshot = previous.copyWith(
      text: text,
      attachments: attachments,
      deepThink: deepThink,
    );
    _draftCache[sessionId] = snapshot;
    if (_draftCache.length > _maxDraftCacheSize) {
      final keysToRemove = _draftCache.keys
          .take(_draftCache.length - _maxDraftCacheSize)
          .toList();
      for (final key in keysToRemove) {
        _draftCache.remove(key);
      }
    }
    // 写入失败不影响正在编辑的草稿；Store 会保持写入顺序，并在下一次
    // 有效保存时继续尝试收敛到最新快照。
    unawaited(_composerDraftStore.save(sessionId, snapshot));
  }

  /// 清理已经成功持久化的旧会话草稿，但不触碰当前 controller / notifier。
  /// 这条路径只在操作返回成功且 UI 已经切到另一个会话时使用；当前会话
  /// 的正常清理仍必须经过 activeSessionId 检查并调用 [_saveDraft]。
  void _clearStoredDraftAfterSuccessfulOperation(String? sessionId) {
    if (sessionId == null) return;
    final draft = _draftCache[sessionId];
    if (draft == null) return;
    _saveDraft(sessionId, text: '', attachments: const []);
  }

  void _adoptEmptyComposerDraft(String sessionId) {
    final snapshot = _emptyComposerDraft.copyWith(
      text: _inputController.text,
      deepThink: _deepThinkEnabled.value,
    );
    _saveDraft(
      sessionId,
      text: snapshot.text,
      attachments: List<PendingAttachment>.from(snapshot.attachments),
      deepThink: snapshot.deepThink,
    );
    _emptyComposerDraft = const ChatComposerDraft();
  }

  void _removeDraftAttachmentIds(
    String? sessionId,
    Iterable<String> stableIds,
  ) {
    if (sessionId == null) return;
    final ids = stableIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;
    final current = _draftCache[sessionId];
    if (current == null) return;
    final retained = current.attachments
        .where((attachment) => !ids.contains(attachment.stableId))
        .toList(growable: false);
    if (retained.length == current.attachments.length) return;
    _saveDraft(sessionId, attachments: retained);
  }

  void _handleComposerDraftChanged(ChatComposerDraft draft) {
    final sessionId = _draftSessionId ?? ref.read(activeSessionIdProvider);
    if (sessionId == null) {
      _emptyComposerDraft = ChatComposerDraft(
        text: draft.text,
        attachments: List<PendingAttachment>.from(draft.attachments),
        deepThink: draft.deepThink,
      );
      return;
    }
    if (!_isCurrentOperationSession(sessionId) ||
        _draftSessionId != sessionId) {
      return;
    }
    if (!_isApplyingComposerDraft) _composerDraftMutationGeneration++;
    _saveDraft(
      sessionId,
      text: draft.text,
      attachments: List<PendingAttachment>.from(draft.attachments),
      deepThink: draft.deepThink,
    );
  }

  void _restoreComposerDraft(String? sessionId) {
    final restoreGeneration = ++_composerDraftRestoreGeneration;
    final mutationGeneration = _composerDraftMutationGeneration;
    final draft = sessionId == null
        ? _emptyComposerDraft
        : _draftCache[sessionId];
    _applyComposerDraft(sessionId, draft);

    // 内存草稿来自本次进程的用户修改，始终比磁盘快照更新；只有冷启动或
    // 页面重建时的 cache miss 才读取私有持久化索引。
    if (sessionId == null || draft != null) return;
    unawaited(
      _restorePersistedComposerDraft(
        sessionId: sessionId,
        restoreGeneration: restoreGeneration,
        mutationGeneration: mutationGeneration,
      ),
    );
  }

  void _applyComposerDraft(String? sessionId, ChatComposerDraft? draft) {
    _isApplyingComposerDraft = true;
    try {
      final text = draft?.text ?? '';
      _draftSessionId = sessionId;
      _inputController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _hasTextNotifier.value = text.trim().isNotEmpty;
      _deepThinkEnabled.value = draft?.deepThink ?? false;
      _pendingModelId = null;
    } finally {
      _isApplyingComposerDraft = false;
    }
  }

  Future<void> _restorePersistedComposerDraft({
    required String sessionId,
    required int restoreGeneration,
    required int mutationGeneration,
  }) async {
    final draft = await _composerDraftStore.read(sessionId);
    if (!mounted ||
        restoreGeneration != _composerDraftRestoreGeneration ||
        mutationGeneration != _composerDraftMutationGeneration ||
        _draftSessionId != sessionId ||
        ref.read(activeSessionIdProvider) != sessionId ||
        _draftCache.containsKey(sessionId) ||
        draft == null) {
      return;
    }
    _draftCache[sessionId] = draft;
    _applyComposerDraft(sessionId, draft);
    // ChatInputBar 自持有附件列表；异步恢复到达时只重建这一份 Composer，
    // 令它以 initialAttachments 初始化，避免把旧空列表发送出去。
    if (mounted) {
      setState(() => _composerDraftRevision++);
    }
  }

  void _persistCurrentComposerDraft() {
    final sessionId = _draftSessionId;
    if (sessionId == null) return;
    _saveDraft(
      sessionId,
      text: _inputController.text,
      deepThink: _deepThinkEnabled.value,
    );
  }

  UniversalMediaCapability _resolveComposerMediaCapability({
    required UniversalMediaKind kind,
    required String? activeSessionId,
    required AsyncValue<ChannelModelWithChannel?>? activeModel,
    required AsyncValue<List<ChannelModelWithChannel>> models,
    required AsyncValue<void> configReady,
    required UniversalMediaConfig config,
    required String? selectedModelId,
  }) {
    if (configReady.isLoading) {
      return const UniversalMediaCapability(
        status: UniversalMediaCapabilityStatus.checking,
        message: '正在检测当前模型和媒体配置…',
      );
    }
    if (configReady.hasError) {
      return UniversalMediaCapability(
        status: UniversalMediaCapabilityStatus.unavailable,
        message: '媒体配置读取失败，请到设置 → 图片生成中检查配置',
      );
    }

    ChannelModelWithChannel? modelInfo;
    if (activeSessionId != null) {
      final current = activeModel;
      if (current == null || current.isLoading) {
        return const UniversalMediaCapability(
          status: UniversalMediaCapabilityStatus.checking,
          message: '正在检测当前模型和媒体配置…',
        );
      }
      if (current.hasError) {
        return UniversalMediaCapability(
          status: UniversalMediaCapabilityStatus.unavailable,
          message: '当前模型能力检测失败，请重新选择模型后重试',
        );
      }
      modelInfo = current.valueOrNull;
    } else {
      if (models.isLoading) {
        return const UniversalMediaCapability(
          status: UniversalMediaCapabilityStatus.checking,
          message: '正在检测当前模型和媒体配置…',
        );
      }
      if (models.hasError) {
        return const UniversalMediaCapability(
          status: UniversalMediaCapabilityStatus.unavailable,
          message: '模型列表加载失败，请到设置中检查模型渠道',
        );
      }
      final availableModels = models.valueOrNull ?? const [];
      modelInfo = availableModels
          .where((model) => model.channelModel.id == selectedModelId)
          .firstOrNull;
      modelInfo ??= availableModels.firstOrNull;
    }

    if (modelInfo == null) {
      return UniversalMediaCapability(
        status: UniversalMediaCapabilityStatus.notConfigured,
        message:
            '请先添加并选择模型渠道后再生成${kind == UniversalMediaKind.video ? '视频' : '音乐'}',
      );
    }
    return resolveUniversalMediaCapability(
      kind: kind,
      protocol: modelInfo.channel.protocol,
      baseUrl: modelInfo.channel.baseUrl,
      apiKeyConfigured: modelInfo.channel.apiKeyEncrypted.trim().isNotEmpty,
      modelName: modelInfo.channelModel.modelName,
      modelCapability: modelInfo.channelModel.capability,
      mediaModel: kind == UniversalMediaKind.video
          ? config.videoModel
          : config.musicModel,
      mediaEndpoint: kind == UniversalMediaKind.video
          ? config.videoEndpoint
          : config.musicEndpoint,
    );
  }

  /// Composer 只暴露当前 TTS 配置真正能走到的声音模式；其它入口保留在
  /// 菜单中并展示原因，避免把设置页的 provider / 模式声明误当成云端能力。
  bool _canUseComposerVoiceCloneReference(TextToSpeechConfig config) {
    return config.enabled &&
        config.isSimiRouter &&
        config.requestedMode?.name == 'voiceClone' &&
        config.baseUrl.trim().isNotEmpty &&
        config.model.trim().isNotEmpty &&
        config.voice.trim().isNotEmpty &&
        config.hasApiKey;
  }

  String? _voiceActionDisabledReason(TextToSpeechConfig config, String action) {
    if (!config.isConfigured) {
      if (action == 'voiceClone' &&
          _canUseComposerVoiceCloneReference(config)) {
        // The Composer can supply a one-shot audio reference even when the
        // settings page has no archived reference yet. The menu itself will
        // remain disabled until that audio attachment is present.
        return null;
      }
      return '请先在设置 → 语音与多模态中启用并配置 TTS（${config.statusLabel}）';
    }

    if (action == 'voiceClone' && !config.isSimiRouter) {
      return '当前 TTS provider 未接入参考音频声音克隆';
    }
    if (action == 'voiceDesign' && !config.isSimiRouter) {
      return '当前 TTS provider 未接入声音设计';
    }

    final configuredMode = config.requestedMode?.name ?? 'standard';
    if (configuredMode != action) {
      final modeLabel = switch (configuredMode) {
        'voiceClone' => '声音克隆',
        'voiceDesign' => '声音设计',
        _ => '普通声音合成',
      };
      final actionLabel = switch (action) {
        'voiceClone' => '声音克隆',
        'voiceDesign' => '声音设计',
        _ => '普通声音合成',
      };
      return '当前 TTS 模式为$modeLabel，请先在设置中切换为$actionLabel';
    }
    return null;
  }

  String? _composerVoiceActionDisabledReason(
    List<ChannelModelWithChannel> models,
    TextToSpeechConfig ttsConfig,
    SpeechToTextConfig sttConfig,
    VoiceCreationTool tool,
  ) {
    if (models.any((model) => _voiceToolSupportedByModel(model, tool))) {
      return null;
    }
    if (tool == VoiceCreationTool.recognition) {
      return sttConfig.isConfigured ? null : '请先在设置中配置语音识别模型';
    }
    final action = switch (tool) {
      VoiceCreationTool.synthesis => 'standard',
      VoiceCreationTool.design => 'voiceDesign',
      VoiceCreationTool.clone => 'voiceClone',
      VoiceCreationTool.recognition || VoiceCreationTool.music => 'standard',
    };
    return _voiceActionDisabledReason(ttsConfig, action);
  }

  /// Resolve and apply the route for one voice task immediately before its
  /// sheet/request.  Standard TTS, design, clone and ASR may coexist in the
  /// same model catalog; a single historical TextToSpeechConfig must not make
  /// the other actions unavailable.  The selected task route is committed to
  /// the top model capsule only after the provider config has been applied.
  Future<bool> _prepareVoiceRoute(VoiceCreationTool tool) async {
    try {
      final models = await ref.read(allConfiguredModelsProvider.future);
      final activeId = ref.read(activeCreationModelIdProvider);
      final routePreferences = ref.read(
        voiceCreationRoutePreferencesProvider.notifier,
      );
      await routePreferences.ready;
      final preferredId = ref
          .read(voiceCreationRoutePreferencesProvider)
          .modelIdFor(tool);
      final candidate =
          models
              .where(
                (model) =>
                    model.channelModel.id == activeId &&
                    _voiceToolSupportedByModel(model, tool),
              )
              .firstOrNull ??
          models
              .where(
                (model) =>
                    model.channelModel.id == preferredId &&
                    _voiceToolSupportedByModel(model, tool),
              )
              .firstOrNull ??
          models
              .where((model) => _voiceToolSupportedByModel(model, tool))
              .firstOrNull;
      if (candidate != null) {
        if (tool == VoiceCreationTool.recognition) {
          await ref
              .read(speechToTextConfigProvider.notifier)
              .applyChannelModel(candidate);
        } else if (tool != VoiceCreationTool.music) {
          await ref
              .read(textToSpeechConfigProvider.notifier)
              .applyChannelModel(candidate);
        }
        ref.read(activeCreationModelIdProvider.notifier).state =
            candidate.channelModel.id;
        ref.read(creationModeProvider.notifier).state = CreationMode.voice;
        ref.read(voiceCreationToolProvider.notifier).state = tool;
        await routePreferences.setPreferred(tool, candidate.channelModel.id);
        return true;
      }

      if (tool == VoiceCreationTool.recognition) {
        await ref.read(speechToTextConfigProvider.notifier).ready;
        return ref.read(speechToTextConfigProvider).isConfigured;
      }
      await ref.read(textToSpeechConfigProvider.notifier).ready;
      final config = ref.read(textToSpeechConfigProvider);
      if (tool == VoiceCreationTool.clone &&
          _canUseComposerVoiceCloneReference(config)) {
        return true;
      }
      final action = switch (tool) {
        VoiceCreationTool.synthesis => 'standard',
        VoiceCreationTool.design => 'voiceDesign',
        VoiceCreationTool.clone => 'voiceClone',
        VoiceCreationTool.recognition || VoiceCreationTool.music => 'standard',
      };
      return _voiceActionDisabledReason(config, action) == null;
    } catch (_) {
      return false;
    }
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final max = _scrollController.position.maxScrollExtent;
    final threshold = MediaQuery.of(context).size.height;
    final shouldShow = max > 0 && (max - offset) > threshold;
    if (shouldShow != _showScrollFab) {
      setState(() => _showScrollFab = shouldShow);
    }
  }

  bool _isNearBottom(ScrollMetrics metrics) {
    return metrics.maxScrollExtent <= 0 || metrics.extentAfter < 200;
  }

  bool _handleMessageListScrollNotification(ScrollNotification notification) {
    if (_isProgrammaticScroll || notification.depth != 0) return false;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _shouldAutoScroll = _isNearBottom(notification.metrics);
    } else if (notification is ScrollEndNotification &&
        notification.dragDetails != null) {
      _shouldAutoScroll = _isNearBottom(notification.metrics);
    }
    return false;
  }

  void _scheduleScrollToBottom() {
    _shouldAutoScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom();
    });
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted || !_shouldAutoScroll) return;
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _shouldAutoScroll = true;
      _isProgrammaticScroll = true;
      _scrollController
          .animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          )
          .whenComplete(() {
            if (!mounted) return;
            _isProgrammaticScroll = false;
          });
    }
  }

  Future<String?> _ensureModelBeforeSend(String? activeSessionId) async {
    final operationSessionId = activeSessionId;
    // 读取模型列表可能跨越会话切换；先固定本次动作看到的模型，避免把
    // B 会话后来选中的模型带回 A 的发送请求。
    final requestedModelId =
        _pendingModelId ?? ref.read(selectedModelIdProvider);
    final models = await ref.read(allModelsProvider.future);
    if (!_isCurrentOperationSession(operationSessionId)) return null;

    final preferredModelId = resolvePreferredChatModelId(
      models,
      selectedModelId: requestedModelId,
    );
    if (preferredModelId != null) {
      if (preferredModelId != requestedModelId) {
        ref.read(selectedModelIdProvider.notifier).state = preferredModelId;
        if (activeSessionId != null) {
          await ref
              .read(sessionDaoProvider)
              .updateDefaultModel(activeSessionId, preferredModelId);
          ref.invalidate(activeSessionProvider);
          ref.invalidate(sessionsProvider);
        }
        if (_isCurrentOperationSession(operationSessionId)) {
          if (mounted) {
            setState(() => _pendingModelId = preferredModelId);
          } else {
            _pendingModelId = preferredModelId;
          }
        }
      }
      return preferredModelId;
    }

    if (!mounted) return null;

    if (models.isEmpty) {
      final goSettings = await _showNoModelsDialog();
      if (goSettings == true &&
          mounted &&
          _isCurrentOperationSession(operationSessionId)) {
        await Navigator.pushNamed(context, '/settings');
      }
      return null;
    }

    final selectedModelId = await _showModelSelectionDialog(models);
    if (selectedModelId == null ||
        !_isCurrentOperationSession(operationSessionId)) {
      return null;
    }

    ref.read(selectedModelIdProvider.notifier).state = selectedModelId;
    if (activeSessionId != null) {
      await ref
          .read(sessionDaoProvider)
          .updateDefaultModel(activeSessionId, selectedModelId);
    }
    if (_isCurrentOperationSession(operationSessionId)) {
      if (mounted) {
        setState(() => _pendingModelId = selectedModelId);
      } else {
        _pendingModelId = selectedModelId;
      }
    }
    return selectedModelId;
  }

  /// 媒体任务的 provider route 已由图片 / 视频 / TTS / STT 配置单独校验，
  /// 因此不能再复用只查询 `getChatModels()` 的普通聊天发送门禁。否则用户只
  /// 配置了媒体模型，或当前会话的默认模型本身就是 media-only 时，明明可以
  /// 生成却会弹出“还没有可用模型”。这里仅为会话寻找一个可选的模型锚点：
  /// 优先保留现有默认模型，其次使用普通 Chat 选择，再使用顶部创建模型；
  /// 旧版独立媒体配置没有 channel model 时允许返回 null，由任务自身配置完成
  /// 请求，结果消息仍会保存实际媒体 route 的 channelModelId。
  Future<String?> _resolveMediaSessionModelId(String? activeSessionId) async {
    final models = await ref.read(allConfiguredModelsProvider.future);
    final knownIds = models
        .map((model) => model.channelModel.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet();

    if (activeSessionId != null) {
      final session = await ref
          .read(sessionDaoProvider)
          .getSession(activeSessionId);
      final existing = session?.defaultChannelModelId;
      if (existing != null && knownIds.contains(existing)) return existing;
    }

    final candidates = <String?>[
      _pendingModelId,
      ref.read(selectedModelIdProvider),
      ref.read(activeCreationModelIdProvider),
    ];
    for (final candidate in candidates) {
      if (candidate != null && knownIds.contains(candidate)) return candidate;
    }
    return models.firstOrNull?.channelModel.id;
  }

  Future<bool?> _showNoModelsDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('还没有可用模型'),
        content: const Text('请先去设置里添加模型渠道和模型，然后再发送消息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showModelSelectionDialog(
    List<ChannelModelWithChannel> models,
  ) {
    final grouped = <String, List<ChannelModelWithChannel>>{};
    for (final model in models) {
      grouped.putIfAbsent(model.channel.name, () => []).add(model);
    }

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择基础模型'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('发送前请先选择一个模型。'),
                const SizedBox(height: 12),
                for (final entry in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  ...entry.value.map(
                    (model) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(model.channelModel.modelName),
                      subtitle: Text(model.displayLabel),
                      onTap: () =>
                          Navigator.of(context).pop(model.channelModel.id),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<bool> _handleSend(
    String content,
    List<PendingAttachment> attachments,
  ) async {
    final submittedComposerText = _inputController.text;
    var activeSessionId = ref.read(activeSessionIdProvider);
    final operationSessionId = activeSessionId;

    if (activeSessionId != null) {
      final streamState = ref.read(streamStateProvider(activeSessionId));
      if (streamState.isStreaming) {
        await _handleStopStreaming();
        return true;
      }
    }

    if (_isSubmitting) return false;

    if (content.isEmpty && attachments.isEmpty) return false;

    if (!ref.read(isOnlineProvider)) {
      _blockedSendWhileOfflineSessionId = activeSessionId;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.fixed,
            content: Text('当前网络不可用，已保留输入，联网后可重试'),
          ),
        );
      return false;
    }

    final operationGeneration = _beginComposerOperation(operationSessionId);
    _setSubmitting(true);
    final deepThinkEnabled = _deepThinkEnabled.value;

    try {
      final selectedModelId = await _ensureModelBeforeSend(activeSessionId);
      if (!_isComposerOperationLive(operationGeneration)) return false;
      if (selectedModelId == null) return false;
      var requestModelId = selectedModelId;

      final hasImageAttachment = attachments.any(
        (attachment) => attachment.type == 'image',
      );

      // 图片消息必须走当前渠道的 Vision 模型。优先自动切换，避免把图片
      // 盲发给纯文本模型后才收到难理解的上游错误。
      if (hasImageAttachment) {
        final visionModelId = await _findVisionModelInCurrentChannel(
          selectedModelId,
        );
        if (!_isComposerOperationLive(operationGeneration)) return false;
        if (visionModelId == null) {
          if (_isCurrentOperationSession(operationSessionId)) {
            _showSnackBar('当前渠道没有支持识图的 Vision 模型，已保留图片和输入');
          }
          return false;
        }
        requestModelId = visionModelId;
        if (deepThinkEnabled &&
            _isCurrentOperationSession(operationSessionId)) {
          _showSnackBar('图片消息将使用 Vision 模型，深度思考本次不切换');
        }
      } else if (deepThinkEnabled) {
        // 深度思考开启：纯文本消息优先切换到当前渠道的 reasoner 模型。
        final reasonerModelId = await _findReasonerModelInCurrentChannel(
          selectedModelId,
        );
        if (!_isComposerOperationLive(operationGeneration)) return false;
        if (reasonerModelId == null) {
          if (_isCurrentOperationSession(operationSessionId)) {
            _showSnackBar('当前渠道没有深度思考（reasoner）模型，已保留输入');
          }
          return false;
        }
        requestModelId = reasonerModelId;
      }

      if (activeSessionId == null) {
        // 空 composer 在模型选择期间如果已经被用户切到某个会话，不能
        // 把那个会话覆盖成新会话；当前输入由新会话动作直接放弃并保留。
        if (ref.read(activeSessionIdProvider) != null) return false;
        activeSessionId = await createNewSession(
          ref,
          defaultModelId: selectedModelId,
        );
        if (!_isComposerOperationLive(operationGeneration)) return false;
        _adoptComposerOperationSession(operationGeneration, activeSessionId);
        _adoptEmptyComposerDraft(activeSessionId);
      }
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }

      final sent = await sendMessage(
        ref: ref,
        sessionId: activeSessionId,
        content: content,
        overrideModelId: requestModelId,
        attachments: attachments,
      );
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }
      if (!sent) {
        if (_isCurrentOperationSession(activeSessionId)) {
          if (_inputController.text == submittedComposerText) {
            _saveDraft(activeSessionId, text: submittedComposerText);
          } else {
            _saveDraft(activeSessionId, text: _inputController.text);
          }
        }
        return false;
      }
      _removeDraftAttachmentIds(
        activeSessionId,
        attachments.map((attachment) => attachment.stableId),
      );
      // ChatInputBar 会在 onSend 返回成功后按实际传入的 attachment IDs
      // 移除草稿；页面这里只清空文本，避免误删并发期间产生的其它附件。
      if (_isCurrentOperationSession(activeSessionId)) {
        final unchanged = _inputController.text == submittedComposerText;
        _saveDraft(
          activeSessionId,
          text: unchanged ? '' : _inputController.text,
        );
        _blockedSendWhileOfflineSessionId = null;
        if (unchanged) {
          _inputController.clear();
          _hasTextNotifier.value = false;
        }
        if (mounted) setState(() => _pendingModelId = null);
        _focusNode.requestFocus();
        _scheduleScrollToBottom();
      } else {
        _clearStoredDraftAfterSuccessfulOperation(activeSessionId);
      }
      return true;
    } catch (e) {
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }
      if (_isCurrentOperationSession(activeSessionId)) {
        if (_inputController.text == submittedComposerText) {
          if (activeSessionId != null) {
            _saveDraft(activeSessionId, text: submittedComposerText);
          }
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发送失败: $e')));
      }
      return false;
    } finally {
      _finishComposerOperation(operationGeneration);
    }
  }

  Future<void> _handleRetryChunkedContentTask(
    String taskId, {
    required bool continueIncomplete,
  }) async {
    final started = await retryChunkedContentTask(
      ref: ref,
      taskId: taskId,
      continueIncomplete: continueIncomplete,
    );
    if (!mounted) return;
    if (!started) {
      _showSnackBar('无法继续该长内容任务；请确认原始附件和提交时模型仍可用。');
      return;
    }
    _scheduleScrollToBottom();
  }

  Future<void> _handleStopChunkedContentTask(String sessionId) async {
    await cancelActiveChunkedContentTask(ref, sessionId);
    if (mounted) _showSnackBar('已停止长内容任务；原始附件和已完成分段已保留。');
  }

  Future<void> _handleStop() async {
    final sessionId = ref.read(activeSessionIdProvider);
    if (sessionId != null) {
      final hasRunningImageTask = ref
          .read(imageGenerationTasksProvider)
          .values
          .any((task) => task.sessionId == sessionId && task.isRunning);
      if (hasRunningImageTask) {
        await cancelImageGeneration(ref: ref, sessionId: sessionId);
        return;
      }
    }
    await _handleStopStreaming();
  }

  Future<void> _handleRetryImageGeneration(String messageId) async {
    final sessionId = ref.read(activeSessionIdProvider);
    if (sessionId == null) return;
    final error = await retryImageGeneration(
      ref: ref,
      sessionId: sessionId,
      messageId: messageId,
    );
    if (error != null && mounted) {
      _showSnackBar(error);
    }
  }

  Future<void> _handleStopStreaming() async {
    final visibleSessionId = ref.read(activeSessionIdProvider);
    final visibleMediaTask = visibleSessionId == null
        ? null
        : ref.read(universalMediaTaskProvider(visibleSessionId));
    if (visibleSessionId != null && visibleMediaTask?.isBusy == true) {
      // 媒体任务的 Stop 不经过 _isSubmitting，也不复用聊天 SSE 的
      // cancelStreaming；服务端取消和本地 cancelled 状态都由 operationId
      // 对齐，避免误取消另一会话的流。
      _cancelComposerOperationForSession(visibleSessionId);
      await ref
          .read(universalMediaJobProvider.notifier)
          .cancelActive(visibleMediaTask!.operationId);
      if (visibleMediaTask.phase != UniversalMediaTaskPhase.saving) {
        ref
            .read(universalMediaTaskProvider(visibleSessionId).notifier)
            .markCancelled();
      }
      return;
    }

    final visibleStreamState = visibleSessionId == null
        ? const StreamState()
        : ref.read(streamStateProvider(visibleSessionId));
    if (visibleSessionId != null && visibleStreamState.isStreaming) {
      _cancelComposerOperationForSession(visibleSessionId);
      // cancelStreaming 同时取消当前 SSE subscription、Dio CancelToken 和
      // STT/请求准备阶段的 operation generation。
      cancelStreaming(ref, visibleSessionId);
      return;
    }

    // 准备阶段还没有 stream/media state 时，Stop 仍然要使本地动作失效。
    // 如果动作属于另一个已经切走的会话，则取消那个会话的 generation，
    // 但绝不把当前 B 的 composer 当成 A 的清理目标。
    if (_isSubmitting && _activeComposerOperationGeneration != null) {
      final operationSessionId = _activeComposerOperationSessionId;
      _cancelActiveComposerOperation();
      if (operationSessionId != null) {
        cancelStreaming(ref, operationSessionId);
      }
      return;
    }

    if (visibleSessionId == null) return;
    // cancelStreaming 同时取消当前 SSE subscription、Dio CancelToken 和
    // STT/请求准备阶段的 operation generation；这里不经过 _isSubmitting。
    cancelStreaming(ref, visibleSessionId);
  }

  /// 替身回复：为最近一条用户消息以镜像人格生成回复。
  Future<bool> _handlePersonaReply() async {
    final activeSessionId = ref.read(activeSessionIdProvider);
    if (activeSessionId == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('请先选择或新建一个会话')));
      return false;
    }
    if (_isSubmitting) return false;
    final operationGeneration = _beginComposerOperation(activeSessionId);
    _setSubmitting(true);
    try {
      final error = await generatePersonaReply(
        ref: ref,
        sessionId: activeSessionId,
      );
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }
      if (error != null) {
        if (_isCurrentOperationSession(activeSessionId)) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(error)));
        }
        return false;
      }
      if (_isCurrentOperationSession(activeSessionId)) {
        _scheduleScrollToBottom();
      }
      return true;
    } finally {
      _finishComposerOperation(operationGeneration);
    }
  }

  MediaRequestProviderProfile _imageProfileForModel(
    ChannelModelWithChannel? model,
  ) {
    if (model == null) {
      return MediaRequestProviderProfile.openAiCompatibleImage;
    }
    return resolveImageRequestProfile(
      modelName: model.channelModel.modelName,
      protocol: model.channel.protocol,
      baseUrl: model.channel.baseUrl,
    );
  }

  MediaRequestProviderProfile _videoProfileForModel(
    ChannelModelWithChannel? model,
  ) {
    if (model == null) {
      return MediaRequestProviderProfile.openAiCompatibleVideo;
    }
    return resolveVideoRequestProfile(
      modelName: model.channelModel.modelName,
      protocol: model.channel.protocol,
      baseUrl: model.channel.baseUrl,
    );
  }

  /// Opens the image task and returns exactly the Composer attachment IDs that
  /// the confirmed request consumed.  A nullable set distinguishes cancel /
  /// failure from a successful text-only generation (the empty set).
  Future<Set<String>?> _handleOpenImageGenerationTaskResult(
    String content,
    List<PendingAttachment> referenceAttachments,
  ) async {
    final submittedComposerText = _inputController.text;
    if (_isSubmitting) return null;
    if (!ref.read(isOnlineProvider)) {
      _showSnackBar('当前网络不可用，请联网后重试');
      return null;
    }

    final configuredModels = await ref.read(allConfiguredModelsProvider.future);
    final imageModels = configuredModels
        .where(
          (model) =>
              model.capabilities.contains(ModelCapability.image) ||
              ModelCapability.isImage(model.channelModel.capability),
        )
        .toList(growable: false);
    if (imageModels.isEmpty) {
      final goSettings = await _showNoImageModelsDialog();
      if (goSettings == true && mounted) {
        await Navigator.pushNamed(context, '/settings');
      }
      return null;
    }

    final imageConfig = ref.read(imageGenerationConfigProvider);
    final activeCreationModelId = ref.read(activeCreationModelIdProvider);
    final initialModel = imageModels.firstWhere(
      (model) => model.channelModel.id == activeCreationModelId,
      orElse: () => imageModels.firstWhere(
        (model) => model.channelModel.id == imageConfig.channelModelId,
        orElse: () => imageModels.firstWhere(
          (model) => model.channelModel.modelName == imageConfig.model,
          orElse: () => imageModels.first,
        ),
      ),
    );
    final draft = await _showImageGenerationTaskSheet(
      content: content,
      imageModels: imageModels,
      initialModel: initialModel,
      referenceAttachments: referenceAttachments,
    );
    if (draft == null || !mounted) return null;
    await ref
        .read(imageGenerationConfigProvider.notifier)
        .applyChannelModel(draft.model);
    ref.read(activeCreationModelIdProvider.notifier).state =
        draft.model.channelModel.id;
    ref.read(creationModeProvider.notifier).state = CreationMode.image;

    final referencePaths = draft.referenceImages
        .map((attachment) => attachment.path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    final options = ImageGenerationOptions(
      model: draft.model.channelModel.modelName,
      prompt: draft.prompt,
      count: draft.count,
      referenceImages: referencePaths,
      aspectRatio: draft.aspectRatio,
      resolution: draft.resolution,
      size: draft.size,
      quality: draft.quality,
    );
    final profile = _imageProfileForModel(draft.model);
    final errors = options.validationErrors(capability: profile.capability);
    if (errors.isNotEmpty) {
      _showSnackBar(errors.join('；'));
      return null;
    }

    var activeSessionId = ref.read(activeSessionIdProvider);
    final operationSessionId = activeSessionId;
    final operationGeneration = _beginComposerOperation(operationSessionId);
    _setSubmitting(true);
    try {
      final resolvedChatModelId = await _ensureModelBeforeSend(activeSessionId);
      if (!_isComposerOperationLive(operationGeneration) ||
          resolvedChatModelId == null) {
        return null;
      }
      if (activeSessionId == null) {
        activeSessionId = await createNewSession(
          ref,
          defaultModelId: resolvedChatModelId,
        );
        if (!_isComposerOperationLive(operationGeneration)) return null;
        _adoptComposerOperationSession(operationGeneration, activeSessionId);
        _adoptEmptyComposerDraft(activeSessionId);
      }
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return null;
      }
      await ref
          .read(sessionDaoProvider)
          .updateDefaultModel(activeSessionId, resolvedChatModelId);

      final error = await generateImageWithOptions(
        ref: ref,
        sessionId: activeSessionId,
        options: options,
        routeModelId: draft.model.channelModel.id,
        referenceAttachments: draft.referenceImages,
      );
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return null;
      }
      if (error != null) {
        if (_isCurrentOperationSession(activeSessionId)) {
          _showSnackBar(error);
          _restoreOperationTextIfUnchanged(
            submittedText: submittedComposerText,
            restoredText: draft.prompt,
            sessionId: activeSessionId,
          );
        }
        return null;
      }
      _removeDraftAttachmentIds(
        activeSessionId,
        draft.referenceImages.map((attachment) => attachment.stableId),
      );
      if (_isCurrentOperationSession(activeSessionId)) {
        final unchanged = _inputController.text == submittedComposerText;
        _saveDraft(
          activeSessionId,
          text: unchanged ? '' : _inputController.text,
        );
        if (unchanged) _hasTextNotifier.value = false;
        _focusNode.requestFocus();
        _scheduleScrollToBottom();
      }
      return Set<String>.unmodifiable(
        draft.referenceImages.map((attachment) => attachment.stableId),
      );
    } catch (error) {
      if (mounted && _isCurrentOperationSession(activeSessionId)) {
        _showSnackBar('图片生成失败：$error');
      }
      return null;
    } finally {
      _finishComposerOperation(operationGeneration);
    }
  }

  Future<bool?> _showNoImageModelsDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('尚未配置图片模型'),
        content: const Text('当前尚未配置可用的图片生成模型，请前往设置添加模型服务。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Future<_ImageGenerationTaskDraft?> _showImageGenerationTaskSheet({
    required String content,
    required List<ChannelModelWithChannel> imageModels,
    required ChannelModelWithChannel initialModel,
    required List<PendingAttachment> referenceAttachments,
  }) async {
    var selectedModelId = initialModel.channelModel.id;
    var selectedCount = 1;
    String? selectedAspectRatio;
    String? selectedResolution;
    String? selectedSize;
    String? selectedQuality;
    final promptController = TextEditingController(text: content);
    final imageReferences = referenceAttachments
        .where((attachment) => attachment.type == 'image')
        .toList(growable: false);
    final selectedReferencePaths = imageReferences
        .map((attachment) => attachment.path)
        .toSet();

    try {
      return await showModalBottomSheet<_ImageGenerationTaskDraft>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final selectedModel = imageModels.firstWhere(
              (model) => model.channelModel.id == selectedModelId,
              orElse: () => initialModel,
            );
            final profile = _imageProfileForModel(selectedModel);
            final capability = profile.capability;
            final maxReferences = capability.maxReferenceImages;
            final maxOutputs = capability.maxOutputs;
            final ratios = capability.aspectRatios;
            final resolutions = capability.resolutions;
            final sizes = capability.sizes;
            final qualities = capability.qualities;
            if (selectedCount > maxOutputs) selectedCount = maxOutputs;
            if (selectedReferencePaths.length > maxReferences) {
              selectedReferencePaths.removeWhere(
                (path) => !imageReferences
                    .take(maxReferences)
                    .any((attachment) => attachment.path == path),
              );
            }
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 4,
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '生成图片',
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('image-generation-prompt-field'),
                      controller: promptController,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 5000,
                      decoration: const InputDecoration(
                        labelText: '描述你的想法',
                        hintText: '描述你的想法，生成一幅图片',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('image-generation-model-field'),
                      initialValue: selectedModel.channelModel.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '模型',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final model in imageModels)
                          DropdownMenuItem<String>(
                            value: model.channelModel.id,
                            child: Text(
                              model.channelModel.modelName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        final nextModel = imageModels.firstWhere(
                          (model) => model.channelModel.id == value,
                          orElse: () => initialModel,
                        );
                        final nextCapability = _imageProfileForModel(
                          nextModel,
                        ).capability;
                        setSheetState(() {
                          selectedModelId = value;
                          if (!nextCapability.supportsAspectRatio(
                            selectedAspectRatio,
                          )) {
                            selectedAspectRatio = null;
                          }
                          if (!nextCapability.supportsResolution(
                            selectedResolution,
                          )) {
                            selectedResolution = null;
                          }
                          if (!nextCapability.supportsSize(selectedSize)) {
                            selectedSize = null;
                          }
                          if (!nextCapability.supportsQuality(
                            selectedQuality,
                          )) {
                            selectedQuality = null;
                          }
                          if (selectedCount > nextCapability.maxOutputs) {
                            selectedCount = nextCapability.maxOutputs;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (imageReferences.isNotEmpty) ...[
                      Text(
                        '参考图（可多选，最多 $maxReferences 张）',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 84,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: imageReferences.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, index) {
                            final attachment = imageReferences[index];
                            final selected = selectedReferencePaths.contains(
                              attachment.path,
                            );
                            return InkWell(
                              key: ValueKey(
                                'image-reference-${attachment.stableId}',
                              ),
                              onTap:
                                  !selected &&
                                      selectedReferencePaths.length >=
                                          maxReferences
                                  ? null
                                  : () {
                                      setSheetState(() {
                                        if (selected) {
                                          selectedReferencePaths.remove(
                                            attachment.path,
                                          );
                                        } else {
                                          selectedReferencePaths.add(
                                            attachment.path,
                                          );
                                        }
                                      });
                                    },
                              child: Container(
                                width: 76,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? Theme.of(
                                            sheetContext,
                                          ).colorScheme.primary
                                        : Theme.of(
                                            sheetContext,
                                          ).colorScheme.outlineVariant,
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(attachment.path),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ] else
                      Text(
                        '未选择参考图。请先通过 + → 从相册选择或选择文件添加图片。',
                        style: TextStyle(
                          color: Theme.of(
                            sheetContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (qualities.isNotEmpty)
                          _imageParameterChip(
                            sheetContext,
                            key: const ValueKey('image-quality-summary'),
                            label: _imageOptionLabel(
                              'quality',
                              selectedQuality,
                            ),
                            prefix: '质量',
                            onPressed: () async {
                              final value = await _showImageOptionSheet(
                                sheetContext,
                                fieldKey: 'quality',
                                title: '图片质量',
                                values: qualities,
                                selected: selectedQuality,
                              );
                              if (value == null || !sheetContext.mounted) {
                                return;
                              }
                              setSheetState(
                                () => selectedQuality = value.isEmpty
                                    ? null
                                    : value,
                              );
                            },
                          ),
                        if (ratios.isNotEmpty)
                          _imageParameterChip(
                            sheetContext,
                            key: const ValueKey('image-aspect-ratio-summary'),
                            label: _imageOptionLabel(
                              'aspect_ratio',
                              selectedAspectRatio,
                            ),
                            prefix: '宽高比',
                            onPressed: () async {
                              final value = await _showImageOptionSheet(
                                sheetContext,
                                fieldKey: 'aspect_ratio',
                                title: '图片宽高比',
                                values: ratios,
                                selected: selectedAspectRatio,
                              );
                              if (value == null || !sheetContext.mounted) {
                                return;
                              }
                              setSheetState(
                                () => selectedAspectRatio = value.isEmpty
                                    ? null
                                    : value,
                              );
                            },
                          ),
                        if (resolutions.isNotEmpty)
                          _imageParameterChip(
                            sheetContext,
                            key: const ValueKey('image-resolution-summary'),
                            label: _imageOptionLabel(
                              'resolution',
                              selectedResolution,
                            ),
                            prefix: '清晰度',
                            onPressed: () async {
                              final value = await _showImageOptionSheet(
                                sheetContext,
                                fieldKey: 'resolution',
                                title: '图片清晰度',
                                values: resolutions,
                                selected: selectedResolution,
                              );
                              if (value == null || !sheetContext.mounted) {
                                return;
                              }
                              setSheetState(
                                () => selectedResolution = value.isEmpty
                                    ? null
                                    : value,
                              );
                            },
                          ),
                        if (sizes.isNotEmpty)
                          _imageParameterChip(
                            sheetContext,
                            key: const ValueKey('image-size-summary'),
                            label: _imageOptionLabel('size', selectedSize),
                            prefix: '分辨率',
                            onPressed: () async {
                              final value = await _showImageOptionSheet(
                                sheetContext,
                                fieldKey: 'size',
                                title: '图片像素分辨率',
                                values: sizes,
                                selected: selectedSize,
                              );
                              if (value == null || !sheetContext.mounted) {
                                return;
                              }
                              setSheetState(
                                () =>
                                    selectedSize = value.isEmpty ? null : value,
                              );
                            },
                          ),
                        _imageParameterChip(
                          sheetContext,
                          label: '$selectedCount 张',
                          prefix: '生成数量',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('高级设置'),
                      initiallyExpanded: true,
                      children: [
                        _imageChoiceRow(
                          sheetContext,
                          fieldKey: 'quality',
                          title: '质量',
                          values: qualities,
                          selected: selectedQuality,
                          onChanged: (value) =>
                              setSheetState(() => selectedQuality = value),
                        ),
                        _imageChoiceRow(
                          sheetContext,
                          fieldKey: 'aspect_ratio',
                          title: '宽高比',
                          values: ratios,
                          selected: selectedAspectRatio,
                          onChanged: (value) =>
                              setSheetState(() => selectedAspectRatio = value),
                        ),
                        _imageChoiceRow(
                          sheetContext,
                          fieldKey: 'resolution',
                          title: '清晰度',
                          values: resolutions,
                          selected: selectedResolution,
                          onChanged: (value) =>
                              setSheetState(() => selectedResolution = value),
                        ),
                        _imageChoiceRow(
                          sheetContext,
                          fieldKey: 'size',
                          title: '像素分辨率',
                          values: sizes,
                          selected: selectedSize,
                          onChanged: (value) =>
                              setSheetState(() => selectedSize = value),
                        ),
                        _imageChoiceRow(
                          sheetContext,
                          fieldKey: 'count',
                          title: '生成数量',
                          values: [
                            for (var count = 1; count <= maxOutputs; count++)
                              '$count',
                          ],
                          selected: '$selectedCount',
                          onChanged: (value) => setSheetState(
                            () =>
                                selectedCount = int.tryParse(value ?? '') ?? 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('confirm-image-generation'),
                        onPressed: () {
                          final prompt = promptController.text.trim();
                          if (prompt.isEmpty) return;
                          final selectedReferences = imageReferences
                              .where(
                                (attachment) => selectedReferencePaths.contains(
                                  attachment.path,
                                ),
                              )
                              .toList(growable: false);
                          Navigator.of(sheetContext).pop(
                            _ImageGenerationTaskDraft(
                              model: selectedModel,
                              prompt: prompt,
                              referenceImages: selectedReferences,
                              count: selectedCount,
                              aspectRatio: selectedAspectRatio,
                              resolution: selectedResolution,
                              size: selectedSize,
                              quality: selectedQuality,
                            ),
                          );
                        },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('开始生成'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } finally {
      promptController.dispose();
    }
  }

  Widget _imageParameterChip(
    BuildContext context, {
    Key? key,
    required String prefix,
    required String label,
    VoidCallback? onPressed,
  }) {
    if (onPressed == null) {
      return Chip(key: key, label: Text('$prefix · $label'));
    }
    return ActionChip(
      key: key,
      tooltip: '设置$prefix',
      label: Text('$prefix · $label'),
      avatar: const Icon(Icons.tune_rounded, size: 16),
      onPressed: onPressed,
    );
  }

  Future<String?> _showImageOptionSheet(
    BuildContext context, {
    required String fieldKey,
    required String title,
    required List<String> values,
    required String? selected,
  }) {
    final explicitValues = values
        .where((value) => value.trim().toLowerCase() != 'auto')
        .toList(growable: false);
    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (optionContext) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              title,
              style: Theme.of(
                optionContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ListTile(
              key: ValueKey('image-option-$fieldKey-auto'),
              leading: Icon(
                selected == null ? Icons.check_circle : Icons.circle_outlined,
              ),
              title: const Text('自动'),
              onTap: () => Navigator.of(optionContext).pop(''),
            ),
            for (final value in explicitValues)
              ListTile(
                key: ValueKey('image-option-$fieldKey-$value'),
                leading: Icon(
                  selected == value
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                title: Text(_imageOptionLabel(fieldKey, value)),
                onTap: () => Navigator.of(optionContext).pop(value),
              ),
          ],
        ),
      ),
    );
  }

  String _imageOptionLabel(String fieldKey, String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return '自动';
    if (fieldKey == 'quality') {
      return switch (normalized.toLowerCase()) {
        'auto' => '自动',
        'low' => '低',
        'medium' => '中',
        'high' => '高',
        _ => normalized,
      };
    }
    return normalized;
  }

  Widget _imageChoiceRow(
    BuildContext context, {
    required String fieldKey,
    required String title,
    required List<String> values,
    required String? selected,
    required ValueChanged<String?> onChanged,
  }) {
    if (values.isEmpty) return const SizedBox.shrink();
    final explicitValues = values
        .where((value) => value.trim().toLowerCase() != 'auto')
        .toList(growable: false);
    return DropdownButtonFormField<String>(
      key: ValueKey(
        'image-$fieldKey-choice-${selected ?? 'auto'}-${explicitValues.join('|')}',
      ),
      initialValue: explicitValues.contains(selected) ? selected : '',
      isExpanded: true,
      decoration: InputDecoration(labelText: title),
      items: [
        const DropdownMenuItem<String>(value: '', child: Text('自动')),
        for (final value in explicitValues)
          DropdownMenuItem<String>(
            value: value,
            child: Text(_imageOptionLabel(fieldKey, value)),
          ),
      ],
      onChanged: (value) =>
          onChanged(value == null || value.trim().isEmpty ? null : value),
    );
  }

  /// 图片生成：把输入框文本作为提示词调用图片生成，成功后清空输入。
  Future<bool> _handleGenerateImage(String content) async {
    return _handleGenerateImageWithAttachments(content, const []);
  }

  /// 生成图片前选择尺寸（记住上次选择），取消则中止本次生成。
  Future<String?> _pickImageGenerationSize() async {
    final config = ref.read(imageGenerationConfigProvider);
    String? chosen;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '图片尺寸',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            for (final size in kImageGenerationSizeOptions)
              ListTile(
                dense: true,
                title: Text(size, style: const TextStyle(fontSize: 13)),
                trailing: size == (chosen ?? config.size)
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  chosen = size;
                },
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      await ref.read(imageGenerationConfigProvider.notifier).setSize(chosen!);
    }
    return chosen;
  }

  Future<bool> _handleGenerateImageWithAttachments(
    String content,
    List<PendingAttachment> referenceAttachments,
  ) async {
    final size = await _pickImageGenerationSize();
    if (size == null) return false;
    return _handleGenerateImageWithAttachmentsAndSize(
      content,
      referenceAttachments,
      size,
    );
  }

  Future<bool> _handleGenerateImageWithAttachmentsAndSize(
    String content,
    List<PendingAttachment> referenceAttachments,
    String size,
  ) async {
    final submittedComposerText = _inputController.text;
    if (_isSubmitting) return false;
    if (!ref.read(isOnlineProvider)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.fixed,
            content: Text('当前网络不可用，请联网后重试'),
          ),
        );
      return false;
    }

    var activeSessionId = ref.read(activeSessionIdProvider);
    final operationSessionId = activeSessionId;
    final operationGeneration = _beginComposerOperation(operationSessionId);
    _setSubmitting(true);

    try {
      final resolvedModelId = await _ensureModelBeforeSend(activeSessionId);
      if (!_isComposerOperationLive(operationGeneration)) return false;
      if (resolvedModelId == null) return false;

      if (activeSessionId == null) {
        if (ref.read(activeSessionIdProvider) != null) return false;
        activeSessionId = await createNewSession(
          ref,
          defaultModelId: resolvedModelId,
        );
        if (!_isComposerOperationLive(operationGeneration)) return false;
        _adoptComposerOperationSession(operationGeneration, activeSessionId);
        _adoptEmptyComposerDraft(activeSessionId);
      }
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }

      await ref
          .read(sessionDaoProvider)
          .updateDefaultModel(activeSessionId, resolvedModelId);
      if (!_isComposerOperationLive(operationGeneration)) return false;

      final error = await generateImage(
        ref: ref,
        sessionId: activeSessionId,
        prompt: content,
        referenceAttachments: referenceAttachments,
        size: size,
      );
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }
      if (error != null) {
        if (_isCurrentOperationSession(activeSessionId)) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(error)));
          if (_inputController.text == submittedComposerText) {
            _saveDraft(activeSessionId, text: submittedComposerText);
          }
        }
        return false;
      }
      _removeDraftAttachmentIds(
        activeSessionId,
        referenceAttachments.map((attachment) => attachment.stableId),
      );
      if (_isCurrentOperationSession(activeSessionId)) {
        final unchanged = _inputController.text == submittedComposerText;
        _saveDraft(
          activeSessionId,
          text: unchanged ? '' : _inputController.text,
        );
        if (unchanged) _hasTextNotifier.value = false;
        if (mounted) setState(() => _pendingModelId = null);
        _focusNode.requestFocus();
        _scheduleScrollToBottom();
      } else {
        _clearStoredDraftAfterSuccessfulOperation(activeSessionId);
      }
      return true;
    } catch (e) {
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }
      if (_isCurrentOperationSession(activeSessionId)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('图片生成失败: $e')));
      }
      return false;
    } finally {
      _finishComposerOperation(operationGeneration);
    }
  }

  Future<bool> _runMediaAction(
    String content,
    Future<String?> Function(String sessionId) action, {
    UniversalMediaKind? mediaKind,
    List<PendingAttachment> mediaAttachments = const [],
    List<PendingAttachment> consumedAttachments = const [],
    VideoGenerationConfig? videoConfig,
  }) async {
    final submittedComposerText = _inputController.text;
    if (_isSubmitting) return false;
    if (!ref.read(isOnlineProvider)) {
      _showSnackBar('当前网络不可用，请联网后重试');
      return false;
    }

    var activeSessionId = ref.read(activeSessionIdProvider);
    final operationSessionId = activeSessionId;
    final operationGeneration = _beginComposerOperation(operationSessionId);
    _setSubmitting(true);
    try {
      final resolvedModelId = await _resolveMediaSessionModelId(
        activeSessionId,
      );
      if (!_isComposerOperationLive(operationGeneration)) return false;
      if (activeSessionId == null) {
        if (ref.read(activeSessionIdProvider) != null) return false;
        activeSessionId = await createNewSession(
          ref,
          defaultModelId: resolvedModelId,
        );
        if (!_isComposerOperationLive(operationGeneration)) return false;
        _adoptComposerOperationSession(operationGeneration, activeSessionId);
        _adoptEmptyComposerDraft(activeSessionId);
      }
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }
      if (resolvedModelId != null) {
        await ref
            .read(sessionDaoProvider)
            .updateDefaultModel(activeSessionId, resolvedModelId);
      }
      if (!_isComposerOperationLive(operationGeneration)) return false;

      if (mediaKind != null) {
        _mediaRetryDrafts[activeSessionId] = _MediaRetryDraft(
          kind: mediaKind,
          prompt: content,
          attachments: List<PendingAttachment>.unmodifiable(mediaAttachments),
          videoConfig: videoConfig,
        );
      }

      final error = await action(activeSessionId);
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }
      if (error != null) {
        if (_isCurrentOperationSession(activeSessionId)) {
          _showSnackBar(error);
          _restoreOperationTextIfUnchanged(
            submittedText: submittedComposerText,
            restoredText: content,
            sessionId: activeSessionId,
          );
        }
        return false;
      }
      _removeDraftAttachmentIds(
        activeSessionId,
        consumedAttachments.map((attachment) => attachment.stableId),
      );
      if (mediaKind != null) _mediaRetryDrafts.remove(activeSessionId);
      if (_isCurrentOperationSession(activeSessionId)) {
        final unchanged = _inputController.text == submittedComposerText;
        _saveDraft(
          activeSessionId,
          text: unchanged ? '' : _inputController.text,
        );
        if (mounted) setState(() => _pendingModelId = null);
        _focusNode.requestFocus();
        _scheduleScrollToBottom();
      } else {
        _clearStoredDraftAfterSuccessfulOperation(activeSessionId);
      }
      return true;
    } catch (_) {
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }
      if (_isCurrentOperationSession(activeSessionId)) {
        _showSnackBar('媒体生成失败，请稍后重试');
        _restoreOperationTextIfUnchanged(
          submittedText: submittedComposerText,
          restoredText: content,
          sessionId: activeSessionId,
        );
      }
      return false;
    } finally {
      _finishComposerOperation(operationGeneration);
    }
  }

  Future<bool> _handleGenerateVideo(
    String content,
    List<PendingAttachment> attachments,
    Map<String, dynamic> extra,
  ) {
    return _runMediaAction(
      content,
      (sessionId) => generateVideo(
        ref: ref,
        sessionId: sessionId,
        prompt: content,
        referenceAttachments: attachments,
        extra: extra,
      ),
      mediaKind: UniversalMediaKind.video,
      mediaAttachments: attachments,
      consumedAttachments: attachments,
    );
  }

  Future<bool> _handleOpenVideoGenerationTask(
    String content,
    VideoGenerationConfig config,
  ) async {
    // The explicit `+ -> 生成视频` action can be invoked while the Composer is
    // still showing an image/voice workspace.  Bind the visible capsule to the
    // persisted video route before submitting so the model shown at the top,
    // the capability sheet and the actual HTTP channel cannot diverge.
    await ref.read(universalMediaConfigProvider.notifier).ready;
    final videoConfig = ref.read(universalMediaConfigProvider);
    final configuredVideoModelId = videoConfig.videoChannelModelId;
    if (configuredVideoModelId != null && configuredVideoModelId.isNotEmpty) {
      ref.read(activeCreationModelIdProvider.notifier).state =
          configuredVideoModelId;
      ref.read(creationModeProvider.notifier).state = CreationMode.video;
    }
    return _runMediaAction(
      content,
      (sessionId) => generateVideoWithOptions(
        ref: ref,
        sessionId: sessionId,
        prompt: content,
        config: config,
      ),
      mediaKind: UniversalMediaKind.video,
      mediaAttachments: config.allAttachments,
      consumedAttachments: config.allAttachments,
      videoConfig: config,
    );
  }

  Future<bool> _handleGenerateMusic(String content) {
    return _runMediaAction(
      content,
      (sessionId) =>
          generateMusic(ref: ref, sessionId: sessionId, prompt: content),
      mediaKind: UniversalMediaKind.music,
    );
  }

  Future<Set<String>?> _handleRetryMediaTask() async {
    final sessionId = ref.read(activeSessionIdProvider);
    if (sessionId == null || _isSubmitting) return null;
    final draft = _mediaRetryDrafts[sessionId];
    if (draft == null) return null;
    if (!ref.read(isOnlineProvider)) {
      _showSnackBar('当前网络不可用，请联网后重试');
      return null;
    }

    final succeeded = await _runMediaAction(
      draft.prompt,
      (retrySessionId) => switch (draft.kind) {
        UniversalMediaKind.video =>
          draft.videoConfig != null
              ? generateVideoWithOptions(
                  ref: ref,
                  sessionId: retrySessionId,
                  prompt: draft.prompt,
                  config: draft.videoConfig!,
                )
              : generateVideo(
                  ref: ref,
                  sessionId: retrySessionId,
                  prompt: draft.prompt,
                  referenceAttachments: draft.attachments,
                ),
        UniversalMediaKind.music => generateMusic(
          ref: ref,
          sessionId: retrySessionId,
          prompt: draft.prompt,
        ),
        UniversalMediaKind.image => Future<String?>.value('不支持重试图片媒体任务'),
      },
      mediaKind: draft.kind,
      mediaAttachments: draft.attachments,
      consumedAttachments: draft.attachments,
      videoConfig: draft.videoConfig,
    );
    if (!succeeded || !_isCurrentOperationSession(sessionId)) return null;
    return draft.attachments.map((attachment) => attachment.stableId).toSet();
  }

  Future<bool> _handleSynthesizeSpeech(String content) {
    return _runMediaAction(
      content,
      (sessionId) => synthesizeSpeechMessage(
        ref: ref,
        sessionId: sessionId,
        text: content,
      ),
    );
  }

  Future<bool> _handleOpenSpeechSynthesisTask(String content) async {
    if (!await _prepareVoiceRoute(VoiceCreationTool.synthesis) || !mounted) {
      if (mounted) _showSnackBar('未找到可用的语音合成模型');
      return false;
    }
    final draft = await _showSpeechSynthesisTaskSheet(content);
    if (draft == null || !mounted) return false;
    return _runMediaAction(
      draft.text,
      (sessionId) => synthesizeSpeechMessage(
        ref: ref,
        sessionId: sessionId,
        text: draft.text,
        voice: draft.voice,
        speed: draft.speed.toStringAsFixed(2),
        responseFormat: draft.responseFormat,
      ),
    );
  }

  Future<_SpeechSynthesisTaskDraft?> _showSpeechSynthesisTaskSheet(
    String content,
  ) async {
    final config = ref.read(textToSpeechConfigProvider);
    final textController = TextEditingController(text: content);
    final localVoiceLabels = <String, String>{
      if (config.voice.trim().isNotEmpty)
        config.voice.trim(): config.isSimiRouter
            ? simiRouterTtsVoiceLabel(config.voice)
            : config.voice.trim(),
      ...(config.isSimiRouter
          ? <String, String>{
              for (final presetVoice in kSimiRouterTtsVoices)
                presetVoice.value: presetVoice.label,
            }
          : const <String, String>{
              'alloy': 'alloy',
              'echo': 'echo',
              'fable': 'fable',
              'onyx': 'onyx',
              'nova': 'nova',
              'shimmer': 'shimmer',
            }),
    };
    // 先返回一个已被 FutureBuilder 监听的外层 Future，再在下一轮事件中调用
    // 渠道 loader。部分测试替身或本地 provider 会同步抛错；如果这里直接调用，
    // 错误可能在 BottomSheet/FutureBuilder 挂载前成为未处理异常，而不是进入
    // snapshot.hasError 的本地音色降级分支。
    Future<List<TextToSpeechVoiceOption>> loadRemoteVoices() {
      return Future<void>.delayed(
        Duration.zero,
      ).then((_) => ref.read(textToSpeechVoiceLoaderProvider)(config));
    }

    Future<List<TextToSpeechVoiceOption>>? remoteVoicesFuture =
        config.isConfigured ? loadRemoteVoices() : null;
    final formats = <String>{
      config.responseFormat.trim().toLowerCase(),
      if (config.isXai) 'mp3',
      if (config.isXai) 'wav',
      if (!config.isXai) 'mp3',
      if (!config.isXai) 'wav',
      if (!config.isXai) 'opus',
      if (!config.isXai) 'aac',
      if (!config.isXai) 'flac',
    }..removeWhere((value) => value.isEmpty);
    var selectedVoice = config.voice.trim().isEmpty
        ? localVoiceLabels.keys.first
        : config.voice.trim();
    var selectedSpeed = double.tryParse(config.speed) ?? 1.0;
    final minSpeed = config.isXai ? 0.7 : 0.25;
    final maxSpeed = config.isXai ? 1.5 : 4.0;
    selectedSpeed = selectedSpeed.clamp(minSpeed, maxSpeed).toDouble();
    var selectedFormat = formats.contains(config.responseFormat.toLowerCase())
        ? config.responseFormat.toLowerCase()
        : formats.first;
    try {
      return await showModalBottomSheet<_SpeechSynthesisTaskDraft>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '声音合成',
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('speech-synthesis-input-field'),
                    controller: textController,
                    minLines: 3,
                    maxLines: 7,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: '输入内容',
                      hintText: '输入需要合成语音的文字',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<TextToSpeechVoiceOption>>(
                    future: remoteVoicesFuture,
                    builder: (context, snapshot) {
                      final voiceLabels = <String, String>{
                        ...localVoiceLabels,
                        for (final voice in snapshot.data ?? const [])
                          voice.id: voice.displayLabel,
                      };
                      voiceLabels.putIfAbsent(
                        selectedVoice,
                        () => config.isSimiRouter
                            ? simiRouterTtsVoiceLabel(selectedVoice)
                            : selectedVoice,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            key: const ValueKey('speech-synthesis-voice-field'),
                            initialValue: selectedVoice,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '音色',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final entry in voiceLabels.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setSheetState(() => selectedVoice = value);
                              }
                            },
                          ),
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) ...[
                            const SizedBox(height: 6),
                            const Row(
                              key: ValueKey('speech-voices-loading'),
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text('正在获取渠道音色…'),
                              ],
                            ),
                          ] else if (snapshot.hasError) ...[
                            const SizedBox(height: 4),
                            Row(
                              key: const ValueKey('speech-voices-fallback'),
                              children: [
                                const Expanded(
                                  child: Text(
                                    '渠道音色获取失败，已使用本地预设',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                TextButton(
                                  key: const ValueKey('retry-speech-voices'),
                                  onPressed: () => setSheetState(() {
                                    remoteVoicesFuture = loadRemoteVoices();
                                  }),
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                          ] else if ((snapshot.data?.isNotEmpty ?? false)) ...[
                            const SizedBox(height: 6),
                            Text(
                              '已同步 ${snapshot.data!.length} 个渠道音色',
                              key: const ValueKey('speech-voices-loaded'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  sheetContext,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '语速 ${selectedSpeed.toStringAsFixed(2)}x',
                    key: const ValueKey('speech-synthesis-speed-label'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Slider(
                    key: const ValueKey('speech-synthesis-speed-slider'),
                    min: minSpeed,
                    max: maxSpeed,
                    divisions: ((maxSpeed - minSpeed) * 20).round(),
                    value: selectedSpeed,
                    label: '${selectedSpeed.toStringAsFixed(2)}x',
                    onChanged: (value) =>
                        setSheetState(() => selectedSpeed = value),
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('speech-synthesis-format-field'),
                    initialValue: selectedFormat,
                    decoration: const InputDecoration(
                      labelText: '输出格式',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final format in formats)
                        DropdownMenuItem(
                          value: format,
                          child: Text(format.toUpperCase()),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() => selectedFormat = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('submit-speech-synthesis-task'),
                      onPressed: () {
                        final text = textController.text.trim();
                        if (text.isEmpty) return;
                        Navigator.of(sheetContext).pop(
                          _SpeechSynthesisTaskDraft(
                            text: text,
                            voice: selectedVoice,
                            speed: selectedSpeed,
                            responseFormat: selectedFormat,
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('开始合成'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      textController.dispose();
    }
  }

  Future<bool> _handleOpenVoiceDesignTask(String content) async {
    if (!await _prepareVoiceRoute(VoiceCreationTool.design) || !mounted) {
      if (mounted) _showSnackBar('未找到可用的声音设计模型');
      return false;
    }
    final draft = await _showVoiceDesignTaskSheet(content);
    if (draft == null || !mounted) return false;
    return _runMediaAction(
      draft.text,
      (sessionId) => synthesizeSpeechMessage(
        ref: ref,
        sessionId: sessionId,
        text: draft.text,
        style: draft.style,
        speed: draft.speed.toStringAsFixed(2),
        responseFormat: draft.responseFormat,
      ),
    );
  }

  Future<_VoiceDesignTaskDraft?> _showVoiceDesignTaskSheet(
    String content,
  ) async {
    final config = ref.read(textToSpeechConfigProvider);
    final textController = TextEditingController(text: content);
    final styleController = TextEditingController(text: config.style);
    final formats = <String>{
      config.responseFormat.trim().toLowerCase(),
      'mp3',
      'wav',
      'opus',
      'aac',
      'flac',
    }..removeWhere((value) => value.isEmpty);
    var selectedSpeed = (double.tryParse(config.speed) ?? 1.0)
        .clamp(0.25, 4.0)
        .toDouble();
    var selectedFormat = formats.contains(config.responseFormat.toLowerCase())
        ? config.responseFormat.toLowerCase()
        : formats.first;
    try {
      return await showModalBottomSheet<_VoiceDesignTaskDraft>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '声音设计',
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('voice-design-input-field'),
                    controller: textController,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: '输入内容',
                      hintText: '输入需要朗读的文字',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('voice-design-style-field'),
                    controller: styleController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '声音风格',
                      hintText: '温柔自然的年轻女声，语速平稳，表达亲切',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final tag in const [
                        '温柔',
                        '活泼',
                        '成熟',
                        '磁性',
                        '沉稳',
                        '故事感',
                      ])
                        ActionChip(
                          key: ValueKey('voice-design-style-tag-$tag'),
                          label: Text(tag),
                          onPressed: () {
                            final current = styleController.text.trim();
                            final next = current.isEmpty
                                ? tag
                                : '$current，$tag';
                            styleController.text = next;
                            styleController.selection =
                                TextSelection.fromPosition(
                                  TextPosition(offset: next.length),
                                );
                            setSheetState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '语速 ${selectedSpeed.toStringAsFixed(2)}x',
                    key: const ValueKey('voice-design-speed-label'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Slider(
                    key: const ValueKey('voice-design-speed-slider'),
                    min: 0.25,
                    max: 4,
                    divisions: 75,
                    value: selectedSpeed,
                    onChanged: (value) =>
                        setSheetState(() => selectedSpeed = value),
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('voice-design-format-field'),
                    initialValue: selectedFormat,
                    decoration: const InputDecoration(
                      labelText: '输出格式',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final format in formats)
                        DropdownMenuItem(
                          value: format,
                          child: Text(format.toUpperCase()),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() => selectedFormat = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('submit-voice-design-task'),
                      onPressed: () {
                        final text = textController.text.trim();
                        final style = styleController.text.trim();
                        if (text.isEmpty || style.isEmpty) return;
                        Navigator.of(sheetContext).pop(
                          _VoiceDesignTaskDraft(
                            text: text,
                            style: style,
                            speed: selectedSpeed,
                            responseFormat: selectedFormat,
                          ),
                        );
                      },
                      child: const Text('开始生成设计语音'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      textController.dispose();
      styleController.dispose();
    }
  }

  Future<bool> _handleOpenVoiceCloneTask(
    String content,
    List<PendingAttachment> attachments,
  ) async =>
      await _handleOpenVoiceCloneTaskResult(content, attachments) != null;

  Future<Set<String>?> _handleOpenVoiceCloneTaskResult(
    String content,
    List<PendingAttachment> attachments,
  ) async {
    if (!await _prepareVoiceRoute(VoiceCreationTool.clone) || !mounted) {
      if (mounted) _showSnackBar('未找到可用的声音克隆模型');
      return null;
    }
    final draft = await _showVoiceCloneTaskSheet(content, attachments);
    if (draft == null || !mounted) return null;
    final config = ref.read(textToSpeechConfigProvider);
    final referencePath =
        draft.referenceAudio?.path ?? config.referenceAudioPath;
    final succeeded = await _runMediaAction(
      draft.text,
      (sessionId) => synthesizeSpeechMessage(
        ref: ref,
        sessionId: sessionId,
        text: draft.text,
        referenceAudioPath: referencePath,
        speed: draft.speed.toStringAsFixed(2),
        responseFormat: draft.responseFormat,
      ),
      consumedAttachments: draft.referenceAudio == null
          ? const <PendingAttachment>[]
          : <PendingAttachment>[draft.referenceAudio!],
    );
    if (!succeeded) return null;
    final selected = draft.referenceAudio;
    return selected == null ? const <String>{} : <String>{selected.stableId};
  }

  Future<_VoiceCloneTaskDraft?> _showVoiceCloneTaskSheet(
    String content,
    List<PendingAttachment> attachments,
  ) async {
    final config = ref.read(textToSpeechConfigProvider);
    final audioReferences = attachments
        .where((attachment) => attachment.type == 'audio')
        .toList(growable: false);
    final configuredReference = config.hasUsableReferenceAudio;
    if (audioReferences.isEmpty && !configuredReference) {
      _showSnackBar('请先上传参考音频');
      return null;
    }
    final textController = TextEditingController(text: content);
    final formats = <String>{config.responseFormat.toLowerCase(), 'mp3', 'wav'}
      ..removeWhere((value) => value.isEmpty);
    var selectedReference = audioReferences.firstOrNull;
    var selectedSpeed = (double.tryParse(config.speed) ?? 1.0)
        .clamp(0.25, 4.0)
        .toDouble();
    var selectedFormat = formats.contains(config.responseFormat.toLowerCase())
        ? config.responseFormat.toLowerCase()
        : formats.first;
    try {
      return await showModalBottomSheet<_VoiceCloneTaskDraft>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 4,
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '声音克隆',
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('voice-clone-input-field'),
                    controller: textController,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: '输入内容',
                      hintText: '输入需要使用克隆音色朗读的文字',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '参考音频（仅用于当前任务）',
                    style: Theme.of(sheetContext).textTheme.titleSmall,
                  ),
                  if (audioReferences.isNotEmpty)
                    RadioGroup<PendingAttachment>(
                      groupValue: selectedReference,
                      onChanged: (value) =>
                          setSheetState(() => selectedReference = value),
                      child: Column(
                        children: [
                          for (final attachment in audioReferences)
                            RadioListTile<PendingAttachment>(
                              key: ValueKey(
                                'voice-clone-reference-${attachment.stableId}',
                              ),
                              value: attachment,
                              title: Text(attachment.name),
                              subtitle: Text('${attachment.fileSize} bytes'),
                            ),
                        ],
                      ),
                    )
                  else
                    const Text('使用设置中已配置的参考音频'),
                  const SizedBox(height: 8),
                  Text(
                    '语速 ${selectedSpeed.toStringAsFixed(2)}x',
                    key: const ValueKey('voice-clone-speed-label'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Slider(
                    key: const ValueKey('voice-clone-speed-slider'),
                    min: 0.25,
                    max: 4,
                    divisions: 75,
                    value: selectedSpeed,
                    onChanged: (value) =>
                        setSheetState(() => selectedSpeed = value),
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('voice-clone-format-field'),
                    initialValue: selectedFormat,
                    decoration: const InputDecoration(
                      labelText: '输出格式',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final format in formats)
                        DropdownMenuItem(
                          value: format,
                          child: Text(format.toUpperCase()),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() => selectedFormat = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('submit-voice-clone-task'),
                      onPressed: () {
                        if (textController.text.trim().isEmpty) return;
                        Navigator.of(sheetContext).pop(
                          _VoiceCloneTaskDraft(
                            text: textController.text.trim(),
                            referenceAudio: selectedReference,
                            speed: selectedSpeed,
                            responseFormat: selectedFormat,
                          ),
                        );
                      },
                      child: const Text('开始生成克隆语音'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      textController.dispose();
    }
  }

  String? _firstVoiceCloneReferencePath(List<PendingAttachment> attachments) {
    for (final attachment in attachments) {
      if (attachment.type != 'audio') continue;
      final path = attachment.path.trim();
      if (path.isNotEmpty) return path;
    }
    return null;
  }

  Future<bool> _handleOpenSpeechRecognitionTask(
    List<PendingAttachment> attachments,
  ) async => await _handleOpenSpeechRecognitionTaskResult(attachments) != null;

  /// Returns the one audio draft ID actually selected in the recognition
  /// sheet, so the Composer removes that audio and retains unrelated files.
  Future<Set<String>?> _handleOpenSpeechRecognitionTaskResult(
    List<PendingAttachment> attachments,
  ) async {
    if (!await _prepareVoiceRoute(VoiceCreationTool.recognition) || !mounted) {
      if (mounted) _showSnackBar('未找到可用的语音识别模型');
      return null;
    }
    final audioReferences = attachments
        .where((attachment) => attachment.type == 'audio')
        .toList(growable: false);
    if (audioReferences.isEmpty) {
      _showSnackBar('请先上传音频文件');
      return null;
    }
    final draft = await _showSpeechRecognitionTaskSheet(audioReferences);
    if (draft == null || !mounted) return null;
    var sessionId = ref.read(activeSessionIdProvider);
    final operationGeneration = _beginComposerOperation(sessionId);
    _setSubmitting(true);
    try {
      if (sessionId == null) {
        sessionId = await createNewSession(ref);
        if (!_isComposerOperationLive(operationGeneration)) return null;
        _adoptComposerOperationSession(operationGeneration, sessionId);
        _adoptEmptyComposerDraft(sessionId);
      }
      final error = await recognizeSpeechMessage(
        ref: ref,
        sessionId: sessionId,
        audioPath: draft.referenceAudio.path,
        fileName: draft.referenceAudio.name,
        language: draft.language,
      );
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return null;
      }
      if (error != null) {
        _showSnackBar(error);
        return null;
      }
      _removeDraftAttachmentIds(sessionId, [draft.referenceAudio.stableId]);
      _scheduleScrollToBottom();
      return <String>{draft.referenceAudio.stableId};
    } finally {
      _finishComposerOperation(operationGeneration);
    }
  }

  Future<_SpeechRecognitionTaskDraft?> _showSpeechRecognitionTaskSheet(
    List<PendingAttachment> audioReferences,
  ) async {
    var selectedReference = audioReferences.first;
    var selectedLanguage = SpeechRecognitionLanguage.auto;
    return showModalBottomSheet<_SpeechRecognitionTaskDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '识别语音',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text('语音文件'),
              RadioGroup<PendingAttachment>(
                groupValue: selectedReference,
                onChanged: (value) =>
                    setSheetState(() => selectedReference = value!),
                child: Column(
                  children: [
                    for (final attachment in audioReferences)
                      RadioListTile<PendingAttachment>(
                        key: ValueKey(
                          'speech-recognition-reference-${attachment.stableId}',
                        ),
                        value: attachment,
                        title: Text(attachment.name),
                        subtitle: Text('${attachment.fileSize} bytes'),
                      ),
                  ],
                ),
              ),
              DropdownButtonFormField<SpeechRecognitionLanguage>(
                key: const ValueKey('speech-recognition-language-field'),
                initialValue: selectedLanguage,
                decoration: const InputDecoration(
                  labelText: '识别语言',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: SpeechRecognitionLanguage.auto,
                    child: Text('自动'),
                  ),
                  DropdownMenuItem(
                    value: SpeechRecognitionLanguage.chinese,
                    child: Text('中文'),
                  ),
                  DropdownMenuItem(
                    value: SpeechRecognitionLanguage.english,
                    child: Text('英文'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setSheetState(() => selectedLanguage = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('submit-speech-recognition-task'),
                  onPressed: () => Navigator.of(sheetContext).pop(
                    _SpeechRecognitionTaskDraft(
                      referenceAudio: selectedReference,
                      language: selectedLanguage,
                    ),
                  ),
                  icon: const Icon(Icons.transcribe_outlined),
                  label: const Text('开始识别'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _handleCloneVoice(
    String content,
    List<PendingAttachment> referenceAttachments,
  ) {
    final config = ref.read(textToSpeechConfigProvider);
    // ChatInputBar 在生产页面明确声明复用设置中的归档参考音频，因此
    // 正常菜单动作会传空列表；保留“有附件则优先使用第一条 audio”的
    // callback 边界，供 Composer 直连 / 测试以及未来关闭该声明时复用。
    final referenceAudioPath =
        _firstVoiceCloneReferencePath(referenceAttachments) ??
        config.referenceAudioPath;
    return _runMediaAction(
      content,
      (sessionId) => synthesizeSpeechMessage(
        ref: ref,
        sessionId: sessionId,
        text: content,
        referenceAudioPath: referenceAudioPath,
      ),
      consumedAttachments: referenceAttachments,
    );
  }

  Future<bool> _handleDesignVoice(String content) {
    final config = ref.read(textToSpeechConfigProvider);
    return _runMediaAction(
      content,
      (sessionId) => synthesizeSpeechMessage(
        ref: ref,
        sessionId: sessionId,
        text: content,
        // 声音设计的 style 来自设置中已校验的描述；它是本次请求参数，
        // 不在 Composer 动作中改写或持久化 TTS 配置。
        style: config.style,
      ),
    );
  }

  /// 编辑图片：打开编辑对话框 → 调 /v1/images/edits → 结果插入会话。
  Future<bool> _handleEditImage(String imagePath) async {
    final activeSessionId = ref.read(activeSessionIdProvider);
    if (activeSessionId == null) {
      _showSnackBar('请先创建一个会话');
      return false;
    }
    if (_isSubmitting) return false;

    final operationGeneration = _beginComposerOperation(activeSessionId);
    _setSubmitting(true);
    try {
      final imageConfig = ref.read(imageGenerationConfigProvider);
      final submitted = await showImageEditDialog(
        context,
        imagePath: imagePath,
        initialSize: imageConfig.size,
        sizeOptions: kImageGenerationSizeOptions,
        onEdit: (prompt, size) async {
          final editError = await editImage(
            ref: ref,
            sessionId: activeSessionId,
            imagePath: imagePath,
            prompt: prompt,
            size: size,
          );
          if (editError == null) {
            await ref
                .read(imageGenerationConfigProvider.notifier)
                .setSize(size);
          }
          return editError;
        },
      );
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }
      if (submitted && _isCurrentOperationSession(activeSessionId)) {
        _scheduleScrollToBottom();
      }
      return submitted;
    } catch (_) {
      if (_isComposerOperationLive(operationGeneration) &&
          _isCurrentOperationSession(activeSessionId)) {
        _showSnackBar('图片编辑失败，请稍后重试');
      }
      return false;
    } finally {
      _finishComposerOperation(operationGeneration);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openRealtimeVoicePanel() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const RealtimeVoicePanel(),
    );
  }

  /// 在当前渠道中查找深度思考（reasoner）模型，返回其 channel_model_id。
  Future<String?> _findReasonerModelInCurrentChannel(
    String currentModelId,
  ) async {
    final channelDao = ref.read(channelDaoProvider);
    final current = await channelDao.getModelWithChannel(currentModelId);
    if (current == null) return null;
    if (ModelCapability.supportsReasonerModel(
      capability: current.channelModel.capability,
      modelId: current.channelModel.modelName,
    )) {
      return current.channelModel.id;
    }
    final models = await channelDao.getModelsByChannel(current.channel.id);
    for (final model in models) {
      if (ModelCapability.supportsReasonerModel(
        capability: model.capability,
        modelId: model.modelName,
      )) {
        return model.id;
      }
    }
    return null;
  }

  /// 图片消息只在当前渠道内选择 Vision 模型；当前模型本身支持识图时不切换。
  Future<String?> _findVisionModelInCurrentChannel(
    String currentModelId,
  ) async {
    final channelDao = ref.read(channelDaoProvider);
    final current = await channelDao.getModelWithChannel(currentModelId);
    if (current == null) return null;

    if (ModelCapability.supportsVisionModel(
      capability: current.channelModel.capability,
      modelId: current.channelModel.modelName,
      capabilities: current.capabilities,
      protocol: current.channel.protocol,
    )) {
      return current.channelModel.id;
    }

    final models = await channelDao.getModelsByChannel(current.channel.id);
    for (final model in models) {
      if (ModelCapability.supportsVisionModel(
        capability: model.capability,
        modelId: model.modelName,
        capabilities: decodeModelCapabilities(
          model.capability,
          model.capabilities,
        ),
        protocol: current.channel.protocol,
      )) {
        return model.id;
      }
    }
    return null;
  }

  void _showNetworkRestoredRetryPromptIfCurrentSession() {
    final blockedSessionId = _blockedSendWhileOfflineSessionId;
    if (blockedSessionId == null ||
        ref.read(activeSessionIdProvider) != blockedSessionId) {
      return;
    }
    if (_inputController.text.trim().isEmpty) {
      _blockedSendWhileOfflineSessionId = null;
      return;
    }
    _blockedSendWhileOfflineSessionId = null;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.fixed,
          content: Text('网络已恢复，可发送保留的输入'),
        ),
      );
  }

  /// 从被点击的 assistant 消息定位对应 user turn；没有具体 ID 时保留
  /// error bar / AppBar 的“重试最后一条”兼容路径。
  void _handleRetry([String? assistantMessageId]) {
    final sessionId = ref.read(activeSessionIdProvider);
    if (sessionId == null) return;
    if (assistantMessageId == null) {
      // STT is intentionally completed before the user turn is persisted. If
      // audio transcription fails, the error bar's retry action must retry
      // the still-visible Composer draft rather than looking for a previous
      // database user message (which would silently do nothing).
      final draftText = _inputController.text.trim();
      final draftAttachments = _composerAttachmentsForCurrentSession();
      if (draftText.isNotEmpty || draftAttachments.isNotEmpty) {
        unawaited(_handleSend(draftText, draftAttachments));
        return;
      }
      retryLastUserMessage(ref, sessionId: sessionId);
      return;
    }
    unawaited(_retryMessageForSession(sessionId, assistantMessageId));
  }

  Future<void> _retryMessageForSession(
    String operationSessionId,
    String assistantMessageId,
  ) async {
    // 图片消息的"重新生成"走图片接口：以原提示词 / 参考图重新生成，
    // 而不是把文字重发到聊天接口。
    final messageAttachments = await ref
        .read(attachmentDaoProvider)
        .getAttachmentsByMessage(assistantMessageId);
    final isImageMessage = messageAttachments.any((a) => a.fileType == 'image');

    final bool submitted;
    if (isImageMessage) {
      final error = await retryImageMessage(
        ref: ref,
        sessionId: operationSessionId,
        assistantMessageId: assistantMessageId,
      );
      submitted = error == null;
      if (error != null &&
          mounted &&
          _isCurrentOperationSession(operationSessionId)) {
        _showSnackBar(error);
      }
    } else {
      submitted = await retryMessage(
        ref: ref,
        sessionId: operationSessionId,
        assistantMessageId: assistantMessageId,
      );
    }
    // retry 的消息结果可以继续落在 operationSessionId；这里没有任何
    // composer 清理，只有当前仍是该会话时才滚动当前页面。
    if (!mounted ||
        !submitted ||
        !_isCurrentOperationSession(operationSessionId)) {
      return;
    }
    _scheduleScrollToBottom();
  }

  /// 从指定消息位置复制会话
  void _handleFork(String messageId) async {
    final activeSessionId = ref.read(activeSessionIdProvider);
    if (activeSessionId == null) return;

    try {
      await forkSession(
        ref: ref,
        sourceSessionId: activeSessionId,
        upToMessageId: messageId,
      );
      if (mounted && _isCurrentOperationSession(activeSessionId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制会话'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted && _isCurrentOperationSession(activeSessionId)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('复制失败: $e')));
      }
    }
  }

  Future<void> _handleSpeak(String messageId, String content) async {
    // 同一页面只允许一个 TTS 合成请求进行。原生 stop 只能停止已经开始的
    // 播放，不能取消另一个尚在网络合成中的请求；若并发合成，较旧请求
    // 晚返回时会反向打断用户刚选择的新播报。
    if (_isPreparingSpeech) {
      _showSnackBar('正在生成语音，请稍候');
      return;
    }
    final text = content.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可播报的文本')));
      return;
    }

    final service = ref.read(textToSpeechServiceProvider);
    final config = ref.read(textToSpeechConfigProvider);
    if (service == null || !config.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在设置中启用并配置语音播报 TTS'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: () {
              if (mounted) Navigator.pushNamed(context, '/settings');
            },
          ),
        ),
      );
      return;
    }

    final operationSessionId = ref.read(activeSessionIdProvider);
    final requestId = ++_speechRequestId;
    setState(() {
      _speakingMessageId = messageId;
      _speakingAudioPath = null;
      _isPreparingSpeech = true;
    });

    try {
      await service.stop();
      if (!mounted || !_isCurrentOperationSession(operationSessionId)) return;
      final result = await service.speak(text: text, voice: config.voice);
      if (!mounted ||
          requestId != _speechRequestId ||
          !_isCurrentOperationSession(operationSessionId)) {
        return;
      }
      final sizeKb = (result.fileSize / 1024).clamp(0, double.infinity);
      final audioPath = result.audioFile.path;
      if (_lastTerminalSpeechAudioPath == audioPath) {
        setState(() {
          _speakingMessageId = null;
          _speakingAudioPath = null;
          _isPreparingSpeech = false;
        });
        return;
      }
      setState(() {
        _speakingMessageId = messageId;
        _speakingAudioPath = audioPath;
        _isPreparingSpeech = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已开始语音播报（${sizeKb.toStringAsFixed(1)} KB）'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (requestId == _speechRequestId &&
          _isCurrentOperationSession(operationSessionId)) {
        setState(() {
          _speakingMessageId = null;
          _speakingAudioPath = null;
          _isPreparingSpeech = false;
        });
      }
      if (_isCurrentOperationSession(operationSessionId)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('语音播报失败：$error')));
      }
    }
  }

  Future<void> _handleStopSpeaking() async {
    _speechRequestId++;
    setState(() {
      _speakingMessageId = null;
      _speakingAudioPath = null;
      _isPreparingSpeech = false;
    });
    try {
      await ref.read(audioPlayerProvider).stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已停止语音播报'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('停止播报失败：$error')));
    }
  }

  Future<void> _handlePlayAttachmentAudio(String path) async {
    final operationSessionId = ref.read(activeSessionIdProvider);
    final requestId = ++_attachmentPlaybackRequestId;
    if (_playingAttachmentPath == path) {
      try {
        await ref.read(audioPlayerProvider).stop();
      } catch (_) {}
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        setState(() => _playingAttachmentPath = null);
      }
      return;
    }
    try {
      final player = ref.read(audioPlayerProvider);
      await player.stop();
      if (!mounted ||
          requestId != _attachmentPlaybackRequestId ||
          !_isCurrentOperationSession(operationSessionId)) {
        return;
      }
      // Mark the path before entering the platform call. Very short audio can
      // emit completed/stopped synchronously from playFile().
      _lastTerminalPlaybackPath = null;
      setState(() => _playingAttachmentPath = path);
      await player.playFile(path);
      if (!mounted ||
          requestId != _attachmentPlaybackRequestId ||
          !_isCurrentOperationSession(operationSessionId)) {
        return;
      }
      // If the platform emitted a terminal event before playFile returned,
      // do not reintroduce a stale “playing” state after the await.
      if (_lastTerminalPlaybackPath == path) {
        if (_playingAttachmentPath == path) {
          setState(() => _playingAttachmentPath = null);
        }
        return;
      }
    } catch (error) {
      if (mounted &&
          requestId == _attachmentPlaybackRequestId &&
          _isCurrentOperationSession(operationSessionId)) {
        setState(() => _playingAttachmentPath = null);
        _showSnackBar('音频播放失败：$error');
      }
    }
  }

  Future<void> _handleUploadImageCdn(String path) async {
    if (_isUploadingImageCdn) return;
    _isUploadingImageCdn = true;
    try {
      const uploader = BaiduCdnImageUploader();
      final url = await uploader.uploadFile(path);
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        _showSnackBar('图床地址已复制：$url');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('图床上传失败：$e');
      }
    } finally {
      _isUploadingImageCdn = false;
    }
  }

  void _handleOpenAttachmentImage(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      _showSnackBar('图片文件不存在或已被移动');
      return;
    }
    showImageViewer(
      context,
      imageProvider: FileImage(file),
      onEditImage: () => _handleEditImage(path),
    );
  }

  Future<void> _handleDownloadAttachment({
    required String path,
    required String fileName,
  }) async {
    final operationSessionId = ref.read(activeSessionIdProvider);
    try {
      final saved = await AttachmentExportService().export(
        localPath: path,
        fileName: fileName,
      );
      if (!mounted ||
          saved == null ||
          !_isCurrentOperationSession(operationSessionId)) {
        return;
      }
      // 不展示用户设备的完整路径；文件名足以确认保存结果。
      _showSnackBar('已保存附件：$fileName');
    } catch (_) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        _showSnackBar('保存附件失败，请重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final ttsConfig = ref.watch(textToSpeechConfigProvider);
    final sttConfig = ref.watch(speechToTextConfigProvider);
    final creationMode = ref.watch(creationModeProvider);
    final selectedVoiceTool = ref.watch(voiceCreationToolProvider);

    ref.listen<bool>(isOnlineProvider, (previous, next) {
      if (previous != false || !next) return;
      _showNetworkRestoredRetryPromptIfCurrentSession();
    });

    // 会话切换时恢复草稿（listener 在 build 外执行，不会干扰 IME）
    ref.listen(activeSessionIdProvider, (prev, next) {
      if (prev != next) {
        _restoreComposerDraft(next);
        if (ref.read(isOnlineProvider)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || ref.read(activeSessionIdProvider) != next) return;
            _showNetworkRestoredRetryPromptIfCurrentSession();
          });
        }
        if (next != null) {
          ref.read(sessionDaoProvider).getSession(next).then((session) {
            if (!mounted || ref.read(activeSessionIdProvider) != next) return;
            ref.read(selectedModelIdProvider.notifier).state =
                session?.defaultChannelModelId;
          });
        }
      }
    });

    // Media capability is resolved from the actual session-bound model when a
    // session exists. The fallback list is only used by the empty composer;
    // it must not silently replace another session's model.
    final mediaConfigReady = ref.watch(universalMediaConfigReadyProvider);
    final mediaConfig = ref.watch(universalMediaConfigProvider);
    final modelsAsync = ref.watch(allModelsProvider);
    final configuredModelsAsync = ref.watch(allConfiguredModelsProvider);
    final activeCreationModelId = ref.watch(activeCreationModelIdProvider);
    final selectedModelId = ref.watch(selectedModelIdProvider);
    final configuredModels =
        configuredModelsAsync.valueOrNull ?? const <ChannelModelWithChannel>[];
    var activeCreationModel = configuredModels
        .where((model) => model.channelModel.id == activeCreationModelId)
        .firstOrNull;
    if (activeCreationModel == null && creationMode != CreationMode.chat) {
      // Match ChatModelSelector's fallback exactly: when no explicit
      // workspace selection exists, both the header and the task form use the
      // first configured model that supports the selected mode. Settings
      // defaults are only request fallbacks and must not create a second
      // visible model state.
      activeCreationModel = configuredModels
          .where((model) => _modelSupportsCreationMode(model, creationMode))
          .firstOrNull;
    }
    final activeModel = activeSessionId == null
        ? null
        : ref.watch(chatSessionModelProvider(activeSessionId));
    final configuredVideoModel = configuredModels
        .where(
          (model) =>
              model.channelModel.id == mediaConfig.videoChannelModelId ||
              model.channelModel.modelName == mediaConfig.videoModel,
        )
        .firstOrNull;
    final configuredMusicModel = configuredModels
        .where(
          (model) =>
              model.channelModel.id == mediaConfig.musicChannelModelId ||
              model.channelModel.modelName == mediaConfig.musicModel,
        )
        .firstOrNull;
    final effectiveVideoModel = AsyncValue<ChannelModelWithChannel?>.data(
      creationMode == CreationMode.video
          ? activeCreationModel
          : configuredVideoModel ?? activeModel?.valueOrNull,
    );
    final effectiveMusicModel = AsyncValue<ChannelModelWithChannel?>.data(
      creationMode == CreationMode.voice &&
              selectedVoiceTool == VoiceCreationTool.music
          ? activeCreationModel
          : configuredMusicModel ?? activeModel?.valueOrNull,
    );
    final videoCapability = _resolveComposerMediaCapability(
      kind: UniversalMediaKind.video,
      activeSessionId: activeSessionId,
      activeModel: effectiveVideoModel,
      models: modelsAsync,
      configReady: mediaConfigReady,
      config: mediaConfig,
      selectedModelId: selectedModelId,
    );
    final musicCapability = _resolveComposerMediaCapability(
      kind: UniversalMediaKind.music,
      activeSessionId: activeSessionId,
      activeModel: effectiveMusicModel,
      models: modelsAsync,
      configReady: mediaConfigReady,
      config: mediaConfig,
      selectedModelId: selectedModelId,
    );
    final voiceTool = creationMode == CreationMode.voice
        ? _effectiveVoiceTool(activeCreationModel, selectedVoiceTool)
        : selectedVoiceTool;

    if (activeSessionId == null) {
      return _buildEmptyState(
        videoCapability: videoCapability,
        musicCapability: musicCapability,
        ttsConfig: ttsConfig,
        sttConfig: sttConfig,
        creationMode: creationMode,
        voiceTool: voiceTool,
        configuredModels: configuredModels,
        activeCreationModel: activeCreationModel,
      );
    }

    final messagesAsync = ref.watch(messagesProvider(activeSessionId));
    final streamState = ref.watch(streamStateProvider(activeSessionId));
    final isOnline = ref.watch(isOnlineProvider);
    final mediaTask = ref.watch(universalMediaTaskProvider(activeSessionId));
    final chunkedTasksAsync = ref.watch(
      chunkedContentTasksProvider(activeSessionId),
    );
    final visibleChunkedTasks = (chunkedTasksAsync.valueOrNull ?? const [])
        .where((task) => task.status != 'completed')
        .toList(growable: false);

    return Stack(
      children: [
        Column(
          children: [
            // 多模态继续沿用同一个 ChatGPT 风格 Composer。图片、视频、
            // 音频和文件通过 Composer 的“+”菜单选择，参数在发送前由
            // 对应的 bottom sheet 收集；页面主体不再根据 CreationMode
            // 插入第二个常驻输入框或独立工作区。
            // 消息列表（点击消息区域收起键盘）
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  // 点击消息区域/背景空白处，收起键盘
                  if (_focusNode.hasFocus) {
                    _focusNode.unfocus();
                  }
                },
                child: messagesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('加载失败: $e')),
                  data: (messages) {
                    if (messages.isEmpty &&
                        visibleChunkedTasks.isEmpty &&
                        !streamState.isStreaming) {
                      return _buildEmptyChat();
                    }

                    if (_shouldAutoScroll) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _scrollToBottom(),
                      );
                    }

                    return NotificationListener<ScrollNotification>(
                      onNotification: _handleMessageListScrollNotification,
                      child: ListView.builder(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.manual,
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        itemCount:
                            messages.length +
                            visibleChunkedTasks.length +
                            (streamState.isStreaming ? 1 : 0),
                        itemBuilder: (_, index) {
                          if (index < messages.length) {
                            final msg = messages[index];
                            if (msg.messageType == kModelSwitchMessageType) {
                              return ModelSwitchNotice(
                                key: ValueKey('message-${msg.id}'),
                                content: msg.content,
                              );
                            }
                            final isUser = msg.role == 'user';
                            final attachments = ref
                                .watch(messageAttachmentsProvider(msg.id))
                                .valueOrNull
                                ?.map((attachment) {
                                  final transcriptStatus =
                                      attachment.fileType == 'audio'
                                      ? ref
                                            .watch(
                                              audioTranscriptStatusProvider(
                                                AudioTranscriptStatusRequest(
                                                  messageId: msg.id,
                                                  attachmentId: attachment.id,
                                                ),
                                              ),
                                            )
                                            .valueOrNull
                                      : null;
                                  return MessageAttachmentView(
                                    attachmentId: attachment.id,
                                    fileName: attachment.fileName,
                                    fileType: attachment.fileType,
                                    fileSize: attachment.fileSize,
                                    localPath: attachment.localPath,
                                    audioTranscriptStatus: transcriptStatus,
                                    onOpenAudioTranscript:
                                        attachment.fileType == 'audio'
                                        ? () => _showAudioTranscriptDetails(
                                            context: context,
                                            messageId: msg.id,
                                            attachmentId: attachment.id,
                                            fileName: attachment.fileName,
                                            fileSize: attachment.fileSize,
                                            audioPath: attachment.localPath,
                                          )
                                        : null,
                                    onPlayAudio:
                                        attachment.fileType == 'audio' &&
                                            attachment.localPath.isNotEmpty
                                        ? () => _handlePlayAttachmentAudio(
                                            attachment.localPath,
                                          )
                                        : null,
                                    onOpenImage:
                                        attachment.fileType == 'image' &&
                                            attachment.localPath.isNotEmpty
                                        ? () => _handleOpenAttachmentImage(
                                            attachment.localPath,
                                          )
                                        : null,
                                    onDownload: attachment.localPath.isNotEmpty
                                        ? () => _handleDownloadAttachment(
                                            path: attachment.localPath,
                                            fileName: attachment.fileName,
                                          )
                                        : null,
                                    isPlayingAudio:
                                        attachment.localPath ==
                                        _playingAttachmentPath,
                                    onEditImage: attachment.fileType == 'image'
                                        ? () => _handleEditImage(
                                            attachment.localPath,
                                          )
                                        : null,
                                    onUploadImageCdn:
                                        attachment.fileType == 'image'
                                        ? () => _handleUploadImageCdn(
                                            attachment.localPath,
                                          )
                                        : null,
                                  );
                                })
                                .toList();
                            // 解析模型名
                            final modelsAsync = ref.watch(allModelsProvider);
                            final modelName = modelsAsync.whenOrNull(
                              data: (models) {
                                if (msg.channelModelId != null) {
                                  return models
                                      .where(
                                        (m) =>
                                            m.channelModel.id ==
                                            msg.channelModelId,
                                      )
                                      .firstOrNull
                                      ?.displayLabel;
                                }
                                return null;
                              },
                            );
                            final imageTask = ref.watch(
                              imageGenerationTasksProvider,
                            )[msg.id];
                            return MessageBubble(
                              key: ValueKey('message-${msg.id}'),
                              messageId: msg.id,
                              role: msg.role,
                              content: msg.content,
                              thinkingContent: msg.thinkingContent,
                              tokens: msg.tokens,
                              responseMs: msg.responseMs,
                              isUser: isUser,
                              modelName: modelName,
                              onRetryMessage: isUser ? null : _handleRetry,
                              onSpeak: isUser
                                  ? null
                                  : () => _handleSpeak(msg.id, msg.content),
                              onStopSpeaking: isUser
                                  ? null
                                  : _handleStopSpeaking,
                              isSpeaking:
                                  !isUser && _speakingMessageId == msg.id,
                              isPreparingSpeech:
                                  !isUser &&
                                  _speakingMessageId == msg.id &&
                                  _isPreparingSpeech,
                              onFork: () => _handleFork(msg.id),
                              attachments: attachments ?? const [],
                              imageGenerationTask: isUser ? null : imageTask,
                              onRetryImageGeneration:
                                  imageTask == null || imageTask.isRunning
                                  ? null
                                  : () => _handleRetryImageGeneration(msg.id),
                            );
                          }
                          final taskIndex = index - messages.length;
                          if (taskIndex < visibleChunkedTasks.length) {
                            final task = visibleChunkedTasks[taskIndex];
                            final status = ChunkedContentTaskStatusX.parse(
                              task.status,
                            );
                            return _ChunkedContentTaskCard(
                              task: task,
                              onStop: status.isTerminal
                                  ? null
                                  : () => _handleStopChunkedContentTask(
                                      activeSessionId,
                                    ),
                              onContinue: status.isTerminal
                                  ? () => _handleRetryChunkedContentTask(
                                      task.id,
                                      continueIncomplete: true,
                                    )
                                  : null,
                              onRestart: status.isTerminal
                                  ? () => _handleRetryChunkedContentTask(
                                      task.id,
                                      continueIncomplete: false,
                                    )
                                  : null,
                            );
                          }
                          // 流式输出中的气泡
                          final modelsAsync = ref.watch(allModelsProvider);
                          final streamingModelName = modelsAsync.whenOrNull(
                            data: (models) {
                              final id =
                                  streamState.modelId ??
                                  _pendingModelId ??
                                  ref.read(selectedModelIdProvider);
                              if (id != null) {
                                final match = models
                                    .where((m) => m.channelModel.id == id)
                                    .firstOrNull;
                                if (match != null) return match.displayLabel;
                              }
                              return models.isNotEmpty
                                  ? models.first.displayLabel
                                  : null;
                            },
                          );
                          return RepaintBoundary(
                            key: ValueKey('streaming-message-$activeSessionId'),
                            child: StreamingBubble(
                              content: streamState.currentContent,
                              thinking: streamState.currentThinking,
                              modelName: streamingModelName,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),

            // 离线提示条
            if (!isOnline)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                color: Colors.orange.withValues(alpha: 0.1),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, size: 14, color: Colors.orange),
                    SizedBox(width: 8),
                    Text(
                      '网络已断开',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ],
                ),
              ),

            // 错误提示条
            if (streamState.error != null)
              _buildErrorBar(activeSessionId, streamState.error!),

            // 输入栏
            ChatInputBar(
              key: ValueKey(
                'chat-composer-$activeSessionId-$_composerDraftRevision',
              ),
              sessionId: activeSessionId,
              controller: _inputController,
              focusNode: _focusNode,
              isStreaming: streamState.isStreaming,
              isSubmitting: _isSubmitting,
              hasTextNotifier: _hasTextNotifier,
              // The Composer is shared by chat and every creation route.  Do
              // not send directly to `_handleSend` here: that would silently
              // turn a selected TTS / image / video model back into a normal
              // Chat request.  Route the submit through the provider state
              // that also drives the model capsule in the AppBar.
              onSend: (text, attachments) async =>
                  (await _handleCreationModeSendOutcome(
                    creationMode,
                    text,
                    attachments,
                    musicAvailable: musicCapability.isAvailable,
                    voiceTool: voiceTool,
                  )).succeeded,
              onSendWithOutcome: (text, attachments) =>
                  _handleCreationModeSendOutcome(
                    creationMode,
                    text,
                    attachments,
                    musicAvailable: musicCapability.isAvailable,
                    voiceTool: voiceTool,
                  ),
              onStop: _handleStop,
              onDraftChanged: _handleComposerDraftChanged,
              initialAttachments:
                  _draftCache[activeSessionId]?.attachments ?? const [],
              onGenerateImage: _handleGenerateImage,
              onGenerateImageWithAttachments:
                  _handleGenerateImageWithAttachments,
              onOpenImageGenerationTask: _handleOpenImageGenerationTaskResult,
              onGenerateVideo: _handleGenerateVideo,
              onOpenVideoGenerationTask: _handleOpenVideoGenerationTask,
              onConfigureVideoGenerationTask: _showVideoModeTaskSheet,
              onSpeechLanguageSelected: (language) {
                ref.read(sttLanguageOverrideProvider.notifier).set(language);
              },
              onOpenSpeechRecognitionTask:
                  _handleOpenSpeechRecognitionTaskResult,
              videoActionDisabledReason: videoCapability.isAvailable
                  ? null
                  : videoCapability.message,
              onSynthesizeSpeech: _handleSynthesizeSpeech,
              onOpenSpeechSynthesisTask: _handleOpenSpeechSynthesisTask,
              onCloneVoice: _handleCloneVoice,
              onOpenVoiceCloneTask: _handleOpenVoiceCloneTask,
              onDesignVoice: _handleDesignVoice,
              onOpenVoiceDesignTask: _handleOpenVoiceDesignTask,
              speechActionDisabledReason: _composerVoiceActionDisabledReason(
                configuredModels,
                ttsConfig,
                sttConfig,
                VoiceCreationTool.synthesis,
              ),
              cloneVoiceActionDisabledReason:
                  _composerVoiceActionDisabledReason(
                    configuredModels,
                    ttsConfig,
                    sttConfig,
                    VoiceCreationTool.clone,
                  ),
              designVoiceActionDisabledReason:
                  _composerVoiceActionDisabledReason(
                    configuredModels,
                    ttsConfig,
                    sttConfig,
                    VoiceCreationTool.design,
                  ),
              useConfiguredVoiceCloneReferenceAudio:
                  ttsConfig.hasUsableReferenceAudio,
              onGenerateMusic: _handleGenerateMusic,
              musicActionDisabledReason: musicCapability.isAvailable
                  ? null
                  : musicCapability.message,
              mediaTask: mediaTask,
              onRetryMedia: _handleRetryMediaTask,
              onEditImage: _handleEditImage,
              deepThinkNotifier: _deepThinkEnabled,
              onPersonaReply: _handlePersonaReply,
              onRealtimeVoice: _openRealtimeVoicePanel,
              modelSelector: null,
            ),
          ],
        ),

        // 滚动到底部 FAB
        if (_showScrollFab)
          Positioned(
            right: 16,
            bottom: 120,
            child: FloatingActionButton.small(
              onPressed: _scrollToBottom,
              child: const Icon(Icons.keyboard_arrow_down),
            ),
          ),
      ],
    );
  }

  Future<void> _showAudioTranscriptDetails({
    required BuildContext context,
    required String messageId,
    required String attachmentId,
    required String fileName,
    required int fileSize,
    required String audioPath,
  }) async {
    AudioTranscriptDetails? details;
    try {
      final root = await getApplicationDocumentsDirectory();
      details = await AudioTranscriptArchive(
        rootDirectory: root,
      ).readDetails(messageId: messageId, attachmentId: attachmentId);
    } catch (_) {
      details = null;
    }
    if (!context.mounted) return;

    final status = details?.status ?? AudioTranscriptStatus.pending;
    final displayText = details?.displayText ?? '等待语音转文字完成。';
    final copyableText = details?.hasCopyableTranscript == true
        ? details!.transcriptText!.trim()
        : null;
    final languageLabel = switch (details?.language) {
      'zh' => '中文',
      'en' => '英文',
      'auto' => '自动',
      final value? when value.trim().isNotEmpty => value,
      _ => null,
    };

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('语音转写详情'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('文件：$fileName'),
                const SizedBox(height: 6),
                Text('状态：${status.displayLabel}'),
                if (details?.modelId?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text('模型：${details!.modelId}'),
                ],
                if (languageLabel != null) ...[
                  const SizedBox(height: 6),
                  Text('语言：$languageLabel'),
                ],
                const SizedBox(height: 12),
                SelectableText(displayText),
              ],
            ),
          ),
        ),
        actions: [
          if (copyableText != null)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyableText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制转写正文'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: const Text('复制正文'),
            ),
          if (copyableText != null)
            TextButton(
              key: const ValueKey('edit-audio-transcript'),
              onPressed: () async {
                final edited = await _showTranscriptEditor(
                  ctx,
                  initialText: copyableText,
                );
                if (edited == null || !mounted) return;
                try {
                  final root = await getApplicationDocumentsDirectory();
                  final archive = AudioTranscriptArchive(rootDirectory: root);
                  await archive.writeDraft(
                    messageId: messageId,
                    attachmentId: attachmentId,
                    fileName: fileName,
                    fileSize: fileSize,
                    transcript: edited,
                    modelId: details?.modelId,
                    language: details?.language,
                    resultMessageId: details?.resultMessageId,
                  );
                  final resultMessageId = details?.resultMessageId;
                  if (resultMessageId?.trim().isNotEmpty == true) {
                    await ref
                        .read(messageDaoProvider)
                        .updateMessageContent(resultMessageId!, edited);
                  }
                  ref.invalidate(
                    audioTranscriptStatusProvider(
                      AudioTranscriptStatusRequest(
                        messageId: messageId,
                        attachmentId: attachmentId,
                      ),
                    ),
                  );
                  final sessionId = ref.read(activeSessionIdProvider);
                  if (sessionId != null) {
                    ref.invalidate(messagesProvider(sessionId));
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (mounted) _showSnackBar('转写已更新');
                } catch (_) {
                  if (mounted) _showSnackBar('转写编辑保存失败，请重试');
                }
              },
              child: const Text('编辑'),
            ),
          if (copyableText != null)
            TextButton(
              key: const ValueKey('download-audio-transcript'),
              onPressed: () async {
                await _downloadTranscriptText(
                  transcript: copyableText,
                  sourceFileName: fileName,
                );
              },
              child: const Text('下载 TXT'),
            ),
          if (copyableText != null)
            TextButton(
              key: const ValueKey('use-audio-transcript-in-composer'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _setComposerTextFromTranscript(copyableText);
              },
              child: const Text('填入输入框'),
            ),
          if (copyableText != null)
            TextButton(
              key: const ValueKey('ask-about-audio-transcript'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _setComposerTextFromTranscript(
                  '请基于以下语音转写回答我的问题：\n\n$copyableText\n\n问题：',
                );
              },
              child: const Text('基于结果提问'),
            ),
          if (audioPath.trim().isNotEmpty)
            TextButton(
              key: const ValueKey('retry-audio-transcript'),
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(
                  _retryAudioTranscript(
                    messageId: messageId,
                    attachmentId: attachmentId,
                    fileName: fileName,
                    fileSize: fileSize,
                    audioPath: audioPath,
                    previousDetails: details,
                  ),
                );
              },
              child: const Text('重新识别'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showTranscriptEditor(
    BuildContext context, {
    required String initialText,
  }) async {
    final controller = TextEditingController(text: initialText);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('编辑转写'),
          content: TextField(
            key: const ValueKey('audio-transcript-editor-field'),
            controller: controller,
            minLines: 8,
            maxLines: 16,
            maxLength: 20000,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('save-audio-transcript-edit'),
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _setComposerTextFromTranscript(String text) {
    final value = text.trim();
    if (value.isEmpty) return;
    _inputController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _hasTextNotifier.value = true;
    final sessionId = ref.read(activeSessionIdProvider);
    if (sessionId != null) _saveDraft(sessionId, text: value);
    _focusNode.requestFocus();
  }

  Future<void> _downloadTranscriptText({
    required String transcript,
    required String sourceFileName,
  }) async {
    File? temporary;
    try {
      final directory = await getTemporaryDirectory();
      temporary = File(
        '${directory.path}/simichat-transcript-${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      await temporary.writeAsString(transcript, flush: true);
      final base = sourceFileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final saved = await AttachmentExportService().export(
        localPath: temporary.path,
        fileName: '${base.isEmpty ? 'audio' : base}-transcript.txt',
      );
      if (mounted) _showSnackBar(saved == null ? '已取消下载' : '转写已保存');
    } catch (_) {
      if (mounted) _showSnackBar('转写下载失败，请检查存储权限后重试');
    } finally {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _retryAudioTranscript({
    required String messageId,
    required String attachmentId,
    required String fileName,
    required int fileSize,
    required String audioPath,
    required AudioTranscriptDetails? previousDetails,
  }) async {
    if (!await File(audioPath).exists()) {
      _showSnackBar('原音频文件已失效，无法重新识别');
      return;
    }
    await ref.read(speechToTextConfigProvider.notifier).ready;
    final config = ref.read(speechToTextConfigProvider);
    final engine = ref.read(speechToTextEngineProvider);
    if (engine == null) {
      _showSnackBar('请先在设置 → 语音输入中启用并配置 STT');
      return;
    }
    final language = previousDetails?.language?.trim().isNotEmpty == true
        ? previousDetails!.language!.trim()
        : config.language;
    ref.read(sttLanguageOverrideProvider.notifier).set(language);
    try {
      final root = await getApplicationDocumentsDirectory();
      final archive = AudioTranscriptArchive(rootDirectory: root);
      final result =
          await AudioTranscriptionService(
            archive: archive,
            engine: engine,
          ).transcribeAndArchive(
            AudioTranscriptionJob(
              messageId: messageId,
              attachmentId: attachmentId,
              audioPath: audioPath,
              fileName: fileName,
              fileSize: fileSize,
            ),
          );
      final transcript = result.transcript.trim();
      if (transcript.isEmpty) {
        _showSnackBar('未识别到可用文字，请更换音频后重试');
        return;
      }
      await archive.writeDraft(
        messageId: messageId,
        attachmentId: attachmentId,
        fileName: fileName,
        fileSize: fileSize,
        transcript: transcript,
        modelId: config.model.trim().isEmpty
            ? config.providerLabel
            : config.model,
        language: language,
        resultMessageId: previousDetails?.resultMessageId,
      );
      final resultMessageId = previousDetails?.resultMessageId;
      if (resultMessageId?.trim().isNotEmpty == true) {
        await ref
            .read(messageDaoProvider)
            .updateMessageContent(resultMessageId!, transcript);
      }
      ref.invalidate(
        audioTranscriptStatusProvider(
          AudioTranscriptStatusRequest(
            messageId: messageId,
            attachmentId: attachmentId,
          ),
        ),
      );
      final sessionId = ref.read(activeSessionIdProvider);
      if (sessionId != null) ref.invalidate(messagesProvider(sessionId));
      _showSnackBar('语音已重新识别');
    } catch (error) {
      _showSnackBar(
        '重新识别失败：${AudioTranscriptArchive.sanitizeErrorMessage(error)}',
      );
    } finally {
      ref.read(sttLanguageOverrideProvider.notifier).clear();
    }
  }

  Widget _buildErrorBar(String sessionId, String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.red.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
          TextButton(onPressed: _handleRetry, child: const Text('重试')),
          TextButton(
            onPressed: () {
              ref.read(streamStateProvider(sessionId).notifier).state =
                  const StreamState();
            },
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  List<PendingAttachment> _composerAttachmentsForCurrentSession() {
    final sessionId = ref.read(activeSessionIdProvider);
    return List<PendingAttachment>.unmodifiable(
      sessionId == null
          ? _emptyComposerDraft.attachments
          : _draftCache[sessionId]?.attachments ?? const [],
    );
  }

  // Single route for the unified Composer.  The selected creation mode is
  // provider state shared with the AppBar model capsule, so every send uses
  // the same model/task that the user sees at the top of the page.
  Future<ComposerSendOutcome> _handleCreationModeSendOutcome(
    CreationMode mode,
    String text,
    List<PendingAttachment> attachments, {
    required bool musicAvailable,
    required VoiceCreationTool voiceTool,
  }) async {
    final prompt = text.trim();
    if (prompt.isEmpty &&
        mode != CreationMode.chat &&
        mode != CreationMode.voice) {
      _showSnackBar('请先输入内容');
      return const ComposerSendOutcome.failure();
    }
    switch (mode) {
      case CreationMode.chat:
        final succeeded = await _handleSend(text, attachments);
        return succeeded
            ? ComposerSendOutcome.success(
                consumedAttachmentIds: attachments
                    .map((attachment) => attachment.stableId)
                    .toSet(),
              )
            : const ComposerSendOutcome.failure();
      case CreationMode.image:
        final consumed = await _handleOpenImageGenerationTaskResult(
          prompt,
          attachments,
        );
        return consumed == null
            ? const ComposerSendOutcome.failure()
            : ComposerSendOutcome.success(consumedAttachmentIds: consumed);
      case CreationMode.video:
        final consumed = await _handleVideoModeSendResult(prompt, attachments);
        return consumed == null
            ? const ComposerSendOutcome.failure()
            : ComposerSendOutcome.success(consumedAttachmentIds: consumed);
      case CreationMode.voice:
        if (voiceTool == VoiceCreationTool.recognition &&
            attachments.any((attachment) => attachment.type == 'audio')) {
          final succeeded = await _handleSend(prompt, attachments);
          return succeeded
              ? ComposerSendOutcome.success(
                  consumedAttachmentIds: attachments
                      .map((attachment) => attachment.stableId)
                      .toSet(),
                )
              : const ComposerSendOutcome.failure();
        }
        if (voiceTool == VoiceCreationTool.clone) {
          final consumed = await _handleOpenVoiceCloneTaskResult(
            prompt,
            attachments,
          );
          return consumed == null
              ? const ComposerSendOutcome.failure()
              : ComposerSendOutcome.success(consumedAttachmentIds: consumed);
        }
        final succeeded = await _handleVoiceModeSend(
          prompt,
          attachments: attachments,
          musicAvailable: musicAvailable,
          voiceTool: voiceTool,
        );
        return succeeded
            ? const ComposerSendOutcome.success()
            : const ComposerSendOutcome.failure();
    }
  }

  Future<bool> _handleVoiceModeSend(
    String prompt, {
    required List<PendingAttachment> attachments,
    required bool musicAvailable,
    required VoiceCreationTool voiceTool,
  }) {
    final ttsConfig = ref.read(textToSpeechConfigProvider);
    if (voiceTool == VoiceCreationTool.recognition) {
      // “语音识别”工作区的发送按钮仍然遵循聊天主流程：有音频时先由
      // 当前绑定的 ASR（例如 mimo-v2.5-asr）转写，再把转写和输入框文字
      // 作为一次用户消息交给当前 Chat 模型。这样用户可以说一段话再补充
      // 一段文字，而不是得到一条孤立的识别结果；ChatInputBar 在成功后也
      // 会按本次传入的 stableId 清掉上方的音频草稿。
      if (attachments.any((attachment) => attachment.type == 'audio')) {
        return _handleSend(prompt, attachments);
      }
      unawaited(_openSpeechRecognitionFromWorkspace());
      return Future.value(false);
    }
    if (voiceTool == VoiceCreationTool.design) {
      return _handleOpenVoiceDesignTask(prompt);
    }
    if (voiceTool == VoiceCreationTool.clone) {
      return _handleOpenVoiceCloneTask(prompt, attachments);
    }
    if (voiceTool == VoiceCreationTool.music) {
      return musicAvailable
          ? _handleGenerateMusic(prompt)
          : Future.value(false);
    }
    if (ttsConfig.isConfigured) {
      return _handleOpenSpeechSynthesisTask(prompt);
    }
    if (musicAvailable) {
      return _handleGenerateMusic(prompt);
    }
    _showSnackBar('请先在设置中配置语音合成或音乐模型');
    return Future.value(false);
  }

  Future<Set<String>?> _handleVideoModeSendResult(
    String prompt,
    List<PendingAttachment> attachments,
  ) async {
    if (prompt.isEmpty) return null;
    final draft = await _showVideoModeTaskSheet(prompt, attachments);
    if (!mounted || draft == null) return null;
    final succeeded = await _handleOpenVideoGenerationTask(prompt, draft);
    if (!succeeded) return null;
    return draft.allAttachments
        .map((attachment) => attachment.stableId)
        .toSet();
  }

  Future<void> _openSpeechRecognitionFromWorkspace() async {
    final audioAttachments = _composerAttachmentsForCurrentSession()
        .where((attachment) => attachment.type == 'audio')
        .toList(growable: false);
    if (audioAttachments.isEmpty) {
      _showSnackBar('请先通过 + 添加音频，再开始识别');
      return;
    }
    await _handleOpenSpeechRecognitionTask(audioAttachments);
  }

  Future<VideoGenerationConfig?> _showVideoModeTaskSheet(
    String prompt,
    List<PendingAttachment> attachments,
  ) async {
    ChannelModelWithChannel? activeVideoModel;
    try {
      final models = await ref.read(allConfiguredModelsProvider.future);
      final activeModelId = ref.read(activeCreationModelIdProvider);
      activeVideoModel = models
          .where(
            (model) =>
                model.channelModel.id == activeModelId &&
                _modelSupportsCreationMode(model, CreationMode.video),
          )
          .firstOrNull;
      if (activeVideoModel == null) {
        final configuredVideo = ref.read(universalMediaConfigProvider);
        activeVideoModel = models
            .where(
              (model) =>
                  _modelSupportsCreationMode(model, CreationMode.video) &&
                  (model.channelModel.id ==
                          configuredVideo.videoChannelModelId ||
                      model.channelModel.modelName ==
                          configuredVideo.videoModel),
            )
            .firstOrNull;
      }
    } catch (_) {
      // Keep the verified default profile when the catalog is temporarily
      // loading. The request layer will validate the final options again.
    }
    if (!mounted) return null;
    final profile = _videoProfileForModel(activeVideoModel);
    final capability = profile.capability;
    final imageAttachments = attachments
        .where((attachment) => attachment.type == 'image')
        .toList(growable: false);
    final audioAttachments = attachments
        .where((attachment) => attachment.type == 'audio')
        .toList(growable: false);
    final selectedReferences = <String>{
      for (final attachment in imageAttachments.take(
        capability.maxReferenceImages,
      ))
        attachment.stableId,
    };
    var firstFrameId = '';
    var audioId = '';
    final durationValues = capability.durations.toList(growable: false);
    final aspectRatioValues = capability.aspectRatios.toList(growable: false);
    final resolutionValues = capability.resolutions.toList(growable: false);
    var durationText =
        (durationValues.contains(6) ? 6 : durationValues.firstOrNull ?? 6)
            .toString();
    var aspectRatio = aspectRatioValues.contains('16:9')
        ? '16:9'
        : aspectRatioValues.firstOrNull ?? '16:9';
    var resolution = resolutionValues.contains('1080p')
        ? '1080p'
        : resolutionValues.firstOrNull ?? '1080p';
    final durationController = TextEditingController(text: durationText);
    try {
      return await showModalBottomSheet<VideoGenerationConfig>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final scheme = Theme.of(sheetContext).colorScheme;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                4,
                16,
                MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '生成视频',
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (imageAttachments.isNotEmpty &&
                        capability.maxReferenceImages > 0) ...[
                      const SizedBox(height: 14),
                      const Text('参考图（可多选）'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final attachment in imageAttachments)
                            FilterChip(
                              key: ValueKey(
                                'creation-video-reference-${attachment.stableId}',
                              ),
                              selected: selectedReferences.contains(
                                attachment.stableId,
                              ),
                              label: Text(
                                attachment.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onSelected: (selected) => setSheetState(() {
                                if (selected) {
                                  if (firstFrameId == attachment.stableId) {
                                    firstFrameId = '';
                                  }
                                  selectedReferences.add(attachment.stableId);
                                } else {
                                  selectedReferences.remove(
                                    attachment.stableId,
                                  );
                                }
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (capability.supportsFirstFrame)
                        DropdownButtonFormField<String>(
                          key: const ValueKey(
                            'creation-video-first-frame-field',
                          ),
                          initialValue: firstFrameId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '首帧图（可选）',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('不指定'),
                            ),
                            for (final attachment in imageAttachments)
                              DropdownMenuItem(
                                value: attachment.stableId,
                                child: Text(attachment.name),
                              ),
                          ],
                          onChanged: (value) => setSheetState(() {
                            firstFrameId = value ?? '';
                            if (firstFrameId.isNotEmpty) {
                              selectedReferences.remove(firstFrameId);
                            }
                          }),
                        ),
                    ],
                    if (audioAttachments.isNotEmpty &&
                        capability.supportsReferenceAudio) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        key: const ValueKey(
                          'creation-video-reference-audio-field',
                        ),
                        initialValue: audioId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '参考音频（可选）',
                        ),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('不指定')),
                          for (final attachment in audioAttachments)
                            DropdownMenuItem(
                              value: attachment.stableId,
                              child: Text(attachment.name),
                            ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => audioId = value ?? ''),
                      ),
                    ],
                    if (durationValues.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: durationText,
                        decoration: const InputDecoration(labelText: '时长'),
                        items: [
                          for (final value in durationValues)
                            DropdownMenuItem(
                              value: value.toString(),
                              child: Text('${value}s'),
                            ),
                        ],
                        onChanged: (value) => setSheetState(
                          () => durationText = value ?? durationText,
                        ),
                      ),
                    ],
                    if (aspectRatioValues.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: aspectRatio,
                        decoration: const InputDecoration(labelText: '宽高比'),
                        items: [
                          for (final value in aspectRatioValues)
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) => setSheetState(
                          () => aspectRatio = value ?? aspectRatio,
                        ),
                      ),
                    ],
                    if (resolutionValues.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: resolution,
                        decoration: const InputDecoration(labelText: '分辨率'),
                        items: [
                          for (final value in resolutionValues)
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) => setSheetState(
                          () => resolution = value ?? resolution,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('creation-video-confirm'),
                        onPressed: () {
                          final references = imageAttachments
                              .where(
                                (attachment) => selectedReferences.contains(
                                  attachment.stableId,
                                ),
                              )
                              .toList(growable: false);
                          final seconds = int.tryParse(durationText);
                          final extra = <String, dynamic>{
                            if (aspectRatioValues.isNotEmpty)
                              'aspect_ratio': aspectRatio,
                            if (resolutionValues.isNotEmpty)
                              'resolution': resolution,
                          };
                          if (durationValues.isNotEmpty && seconds != null) {
                            extra['seconds'] = seconds;
                          }
                          Navigator.of(sheetContext).pop(
                            VideoGenerationConfig(
                              referenceAttachments: references,
                              firstFrameAttachment: imageAttachments
                                  .where(
                                    (attachment) =>
                                        attachment.stableId == firstFrameId,
                                  )
                                  .firstOrNull,
                              referenceAudioAttachment: audioAttachments
                                  .where(
                                    (attachment) =>
                                        attachment.stableId == audioId,
                                  )
                                  .firstOrNull,
                              duration: seconds,
                              aspectRatio: aspectRatio,
                              resolution: resolution,
                              extra: extra,
                            ),
                          );
                        },
                        icon: const Icon(Icons.movie_creation_outlined),
                        label: const Text('开始生成'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } finally {
      durationController.dispose();
    }
  }

  Widget _buildEmptyState({
    required UniversalMediaCapability videoCapability,
    required UniversalMediaCapability musicCapability,
    required TextToSpeechConfig ttsConfig,
    required SpeechToTextConfig sttConfig,
    required CreationMode creationMode,
    required VoiceCreationTool voiceTool,
    required List<ChannelModelWithChannel> configuredModels,
    required ChannelModelWithChannel? activeCreationModel,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 空会话也只保留一个输入框；媒体类型、参考文件和任务参数都从
        // Composer 的“+”菜单进入，不再为图片 / 视频 / 语音渲染另一套
        // 常驻表单。
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'SimiAIChat',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '输入文字，或通过“+”添加图片、视频和音频',
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    _buildEmptyChat(),
                  ],
                ),
              ),
            ),
          ),
        ),
        ChatInputBar(
          sessionId: null,
          controller: _inputController,
          focusNode: _focusNode,
          isStreaming: false,
          isSubmitting: _isSubmitting,
          hasTextNotifier: _hasTextNotifier,
          // Keep the empty-session Composer on the same route as the active
          // session Composer.  Otherwise the first send after selecting a
          // media model would still create a normal text-chat request.
          onSend: (text, attachments) async =>
              (await _handleCreationModeSendOutcome(
                creationMode,
                text,
                attachments,
                musicAvailable: musicCapability.isAvailable,
                voiceTool: voiceTool,
              )).succeeded,
          onSendWithOutcome: (text, attachments) =>
              _handleCreationModeSendOutcome(
                creationMode,
                text,
                attachments,
                musicAvailable: musicCapability.isAvailable,
                voiceTool: voiceTool,
              ),
          onStop: _handleStop,
          onDraftChanged: _handleComposerDraftChanged,
          initialAttachments: _emptyComposerDraft.attachments,
          onGenerateImage: _handleGenerateImage,
          onGenerateImageWithAttachments: _handleGenerateImageWithAttachments,
          onOpenImageGenerationTask: _handleOpenImageGenerationTaskResult,
          onGenerateVideo: _handleGenerateVideo,
          onOpenVideoGenerationTask: _handleOpenVideoGenerationTask,
          onConfigureVideoGenerationTask: _showVideoModeTaskSheet,
          onSpeechLanguageSelected: (language) {
            ref.read(sttLanguageOverrideProvider.notifier).set(language);
          },
          onOpenSpeechRecognitionTask: _handleOpenSpeechRecognitionTaskResult,
          videoActionDisabledReason: videoCapability.isAvailable
              ? null
              : videoCapability.message,
          onSynthesizeSpeech: _handleSynthesizeSpeech,
          onOpenSpeechSynthesisTask: _handleOpenSpeechSynthesisTask,
          onCloneVoice: _handleCloneVoice,
          onOpenVoiceCloneTask: _handleOpenVoiceCloneTask,
          onDesignVoice: _handleDesignVoice,
          onOpenVoiceDesignTask: _handleOpenVoiceDesignTask,
          speechActionDisabledReason: _composerVoiceActionDisabledReason(
            configuredModels,
            ttsConfig,
            sttConfig,
            VoiceCreationTool.synthesis,
          ),
          cloneVoiceActionDisabledReason: _composerVoiceActionDisabledReason(
            configuredModels,
            ttsConfig,
            sttConfig,
            VoiceCreationTool.clone,
          ),
          designVoiceActionDisabledReason: _composerVoiceActionDisabledReason(
            configuredModels,
            ttsConfig,
            sttConfig,
            VoiceCreationTool.design,
          ),
          useConfiguredVoiceCloneReferenceAudio:
              ttsConfig.hasUsableReferenceAudio,
          onGenerateMusic: _handleGenerateMusic,
          musicActionDisabledReason: musicCapability.isAvailable
              ? null
              : musicCapability.message,
          onEditImage: _handleEditImage,
          deepThinkNotifier: _deepThinkEnabled,
          onPersonaReply: _handlePersonaReply,
          onRealtimeVoice: _openRealtimeVoicePanel,
          modelSelector: null,
        ),
      ],
    );
  }

  // Legacy workspace builder retained for migration compatibility with older
  // deep links. The production page intentionally renders only the unified
  // Composer and the message timeline.
  // ignore: unused_element
  Widget _buildCreationModeWorkspace({
    required CreationMode mode,
    required VoiceCreationTool voiceTool,
    required List<ChannelModelWithChannel> configuredModels,
    required ChannelModelWithChannel? activeCreationModel,
    required bool compactAfterOutput,
    required UniversalMediaCapability videoCapability,
    required UniversalMediaCapability musicCapability,
    required TextToSpeechConfig ttsConfig,
    required SpeechToTextConfig sttConfig,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final imageAvailable = configuredModels.any(
      (model) =>
          model.capabilities.contains(ModelCapability.image) ||
          ModelCapability.isImage(model.channelModel.capability),
    );
    final voiceModelAvailable = configuredModels.any((model) {
      final capabilities = model.capabilities;
      final primary = model.channelModel.capability;
      return capabilities.contains(ModelCapability.audio) ||
          capabilities.contains(ModelCapability.tts) ||
          capabilities.contains(ModelCapability.asr) ||
          capabilities.contains(ModelCapability.voiceDesign) ||
          capabilities.contains(ModelCapability.voiceClone) ||
          capabilities.contains(ModelCapability.music) ||
          ModelCapability.isAudio(primary) ||
          ModelCapability.isTts(primary) ||
          ModelCapability.isAsr(primary) ||
          ModelCapability.isVoiceDesign(primary) ||
          ModelCapability.isVoiceClone(primary) ||
          ModelCapability.isMusic(primary);
    });
    final voiceAvailable =
        ttsConfig.isConfigured || sttConfig.isConfigured || voiceModelAvailable;
    final available = switch (mode) {
      CreationMode.chat => true,
      CreationMode.image => imageAvailable,
      CreationMode.video => videoCapability.isAvailable,
      CreationMode.voice => voiceAvailable || musicCapability.isAvailable,
    };

    if (!available) {
      final label = switch (mode) {
        CreationMode.image => '图片生成',
        CreationMode.video => '视频生成',
        CreationMode.voice => '语音创作',
        CreationMode.chat => '聊天',
      };
      return _buildModeEmptyState(
        mode: mode,
        title: '当前尚未配置可用的$label模型',
        subtitle: '前往设置添加模型服务后即可开始创作',
      );
    }

    final (title, subtitle, icon) = switch (mode) {
      CreationMode.image => ('图片生成', '描述你的想法，生成一幅图片', Icons.image_outlined),
      CreationMode.video => ('视频生成', '用文字和参考素材生成视频', Icons.movie_outlined),
      CreationMode.voice => (
        '语音创作',
        '合成语音、识别语音或生成音乐',
        Icons.graphic_eq_rounded,
      ),
      CreationMode.chat => ('聊天', '输入消息开始对话', Icons.chat_bubble_outline),
    };

    final form = switch (mode) {
      CreationMode.image => _buildImageModeWorkspace(
        scheme,
        model: activeCreationModel,
      ),
      CreationMode.video => _buildVideoModeWorkspace(
        scheme,
        model: activeCreationModel,
      ),
      CreationMode.voice => _buildVoiceModeWorkspace(
        scheme,
        model: activeCreationModel,
        ttsConfig: ttsConfig,
        sttConfig: sttConfig,
        musicAvailable: musicCapability.isAvailable,
        voiceTool: voiceTool,
      ),
      CreationMode.chat => const SizedBox.shrink(),
    };

    if (compactAfterOutput) {
      return Container(
        key: ValueKey<String>('creation-mode-workspace-${mode.name}'),
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 860),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .7),
          ),
        ),
        child: ExpansionTile(
          key: ValueKey<String>(
            'creation-mode-workspace-collapsed-${mode.name}',
          ),
          initiallyExpanded: false,
          leading: Icon(icon, color: scheme.primary),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('输出记录已保留在当前会话 · 点击展开继续创作'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: form,
            ),
          ],
        ),
      );
    }

    return Container(
      key: ValueKey<String>('creation-mode-workspace-${mode.name}'),
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 860),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          form,
        ],
      ),
    );
  }

  Widget _buildModeEmptyState({
    required CreationMode mode,
    required String title,
    required String subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey<String>('creation-mode-empty-${mode.name}'),
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 860),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 38, color: scheme.primary),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildImageModeWorkspace(
    ColorScheme scheme, {
    required ChannelModelWithChannel? model,
  }) {
    final capability = _imageProfileForModel(model).capability;
    final labels = <String>['参考图'];
    if (capability.qualities.isNotEmpty) {
      labels.add('质量 · ${capability.qualities.first}');
    }
    if (capability.aspectRatios.isNotEmpty) {
      labels.add('宽高比 · ${capability.aspectRatios.first}');
    }
    if (capability.resolutions.isNotEmpty) {
      labels.add('分辨率 · ${capability.resolutions.first}');
    }
    if (capability.maxOutputs > 1 || capability.supportsMultipleOutputs) {
      labels.add('生成数量 · ${capability.minOutputs} 张');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modeComposerHint(scheme, '在底部输入框描述你的想法，生成一幅图片'),
        const SizedBox(height: 12),
        _modeParameterWrap(scheme, labels),
      ],
    );
  }

  Widget _buildVideoModeWorkspace(
    ColorScheme scheme, {
    required ChannelModelWithChannel? model,
  }) {
    final capability = _videoProfileForModel(model).capability;
    final labels = <String>[];
    if (capability.supportsFirstFrame) labels.add('首帧图');
    if (capability.maxReferenceImages > 0) {
      labels.add('参考图 · 最多 ${capability.maxReferenceImages} 张');
    }
    if (capability.supportsReferenceAudio) labels.add('参考音频');
    if (capability.durations.isNotEmpty) {
      labels.add('时长 · ${capability.durations.first}s');
    }
    if (capability.aspectRatios.isNotEmpty) {
      labels.add('宽高比 · ${capability.aspectRatios.first}');
    }
    if (capability.resolutions.isNotEmpty) {
      labels.add('分辨率 · ${capability.resolutions.first}');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modeComposerHint(scheme, '在底部输入框描述你想生成的视频'),
        const SizedBox(height: 12),
        _modeParameterWrap(scheme, labels),
      ],
    );
  }

  VoiceCreationTool _effectiveVoiceTool(
    ChannelModelWithChannel? model,
    VoiceCreationTool selected,
  ) {
    if (model == null) return selected;
    final capabilities = model.capabilities;
    final explicit = switch (selected) {
      VoiceCreationTool.synthesis => ModelCapability.tts,
      VoiceCreationTool.recognition => ModelCapability.asr,
      VoiceCreationTool.music => ModelCapability.music,
      VoiceCreationTool.design => ModelCapability.voiceDesign,
      VoiceCreationTool.clone => ModelCapability.voiceClone,
    };
    if (capabilities.contains(explicit)) return selected;
    if (capabilities.contains(ModelCapability.audio)) {
      return switch (ModelCapability.voiceCapabilityForModel(
        modelId: model.channelModel.modelName,
        capabilities: capabilities,
      )) {
        ModelCapability.asr => VoiceCreationTool.recognition,
        ModelCapability.music => VoiceCreationTool.music,
        ModelCapability.voiceDesign => VoiceCreationTool.design,
        ModelCapability.voiceClone => VoiceCreationTool.clone,
        _ => VoiceCreationTool.synthesis,
      };
    }
    return selected;
  }

  bool _voiceToolSupportedByModel(
    ChannelModelWithChannel? model,
    VoiceCreationTool tool,
  ) {
    // Empty-session workspaces keep provider-level readiness checks. Once a
    // concrete media model is selected, its declared capability controls the
    // visible actions so TTS/ASR tools cannot be mixed accidentally.
    if (model == null) return true;
    final primary = model.channelModel.capability;
    final capabilities = model.capabilities;
    final explicit = switch (tool) {
      VoiceCreationTool.synthesis => ModelCapability.tts,
      VoiceCreationTool.recognition => ModelCapability.asr,
      VoiceCreationTool.music => ModelCapability.music,
      VoiceCreationTool.design => ModelCapability.voiceDesign,
      VoiceCreationTool.clone => ModelCapability.voiceClone,
    };
    final primaryMatches = switch (tool) {
      VoiceCreationTool.synthesis => ModelCapability.isTts(primary),
      VoiceCreationTool.recognition => ModelCapability.isAsr(primary),
      VoiceCreationTool.music => ModelCapability.isMusic(primary),
      VoiceCreationTool.design => ModelCapability.isVoiceDesign(primary),
      VoiceCreationTool.clone => ModelCapability.isVoiceClone(primary),
    };
    if (capabilities.contains(explicit) || primaryMatches) return true;
    // Legacy rows only have the umbrella audio capability. Resolve those
    // names centrally so an ASR model is never presented as TTS.
    return capabilities.contains(ModelCapability.audio) &&
        _effectiveVoiceTool(model, tool) == tool;
  }

  bool _modelSupportsCreationMode(
    ChannelModelWithChannel model,
    CreationMode mode,
  ) {
    final capabilities = model.capabilities;
    final primary = model.channelModel.capability;
    return switch (mode) {
      CreationMode.chat => true,
      CreationMode.image =>
        capabilities.contains(ModelCapability.image) ||
            ModelCapability.isImage(primary),
      CreationMode.video =>
        capabilities.contains(ModelCapability.video) ||
            ModelCapability.isVideo(primary),
      CreationMode.voice =>
        capabilities.contains(ModelCapability.audio) ||
            capabilities.contains(ModelCapability.tts) ||
            capabilities.contains(ModelCapability.asr) ||
            capabilities.contains(ModelCapability.voiceDesign) ||
            capabilities.contains(ModelCapability.voiceClone) ||
            capabilities.contains(ModelCapability.music) ||
            ModelCapability.isAudio(primary) ||
            ModelCapability.isTts(primary) ||
            ModelCapability.isAsr(primary) ||
            ModelCapability.isVoiceDesign(primary) ||
            ModelCapability.isVoiceClone(primary) ||
            ModelCapability.isMusic(primary),
    };
  }

  Widget _buildVoiceModeWorkspace(
    ColorScheme scheme, {
    required ChannelModelWithChannel? model,
    required TextToSpeechConfig ttsConfig,
    required SpeechToTextConfig sttConfig,
    required bool musicAvailable,
    required VoiceCreationTool voiceTool,
  }) {
    final showSynthesis =
        ttsConfig.isConfigured &&
        _voiceToolSupportedByModel(model, VoiceCreationTool.synthesis);
    final showRecognition =
        sttConfig.isConfigured &&
        _voiceToolSupportedByModel(model, VoiceCreationTool.recognition);
    final showMusic =
        musicAvailable &&
        _voiceToolSupportedByModel(model, VoiceCreationTool.music);
    final showDesign =
        ttsConfig.isConfigured &&
        _voiceToolSupportedByModel(model, VoiceCreationTool.design) &&
        _voiceActionDisabledReason(ttsConfig, 'voiceDesign') == null;
    final showClone =
        ttsConfig.hasUsableReferenceAudio &&
        _voiceToolSupportedByModel(model, VoiceCreationTool.clone) &&
        _voiceActionDisabledReason(ttsConfig, 'voiceClone') == null;
    final actions = <Widget>[];
    if (showSynthesis) {
      actions.add(
        SizedBox(
          width: 146,
          child: OutlinedButton.icon(
            key: const ValueKey('creation-mode-tts-action'),
            onPressed: () => unawaited(
              _handleOpenSpeechSynthesisTask(_inputController.text.trim()),
            ),
            icon: const Icon(Icons.record_voice_over_outlined, size: 18),
            label: const Text('合成语音'),
          ),
        ),
      );
    }
    if (showRecognition) {
      actions.add(
        SizedBox(
          width: 146,
          child: OutlinedButton.icon(
            key: const ValueKey('creation-mode-stt-action'),
            onPressed: () => unawaited(_openSpeechRecognitionFromWorkspace()),
            icon: const Icon(Icons.transcribe_outlined, size: 18),
            label: const Text('识别语音'),
          ),
        ),
      );
    }
    if (showMusic) {
      actions.add(
        SizedBox(
          width: 146,
          child: OutlinedButton.icon(
            key: const ValueKey('creation-mode-music-action'),
            onPressed: () =>
                unawaited(_handleGenerateMusic(_inputController.text.trim())),
            icon: const Icon(Icons.music_note_outlined, size: 18),
            label: const Text('音乐'),
          ),
        ),
      );
    }
    if (showDesign) {
      actions.add(
        SizedBox(
          width: 146,
          child: OutlinedButton.icon(
            key: const ValueKey('creation-mode-voice-design-action'),
            onPressed: () => unawaited(
              _handleOpenVoiceDesignTask(_inputController.text.trim()),
            ),
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('声音设计'),
          ),
        ),
      );
    }
    if (showClone) {
      actions.add(
        SizedBox(
          width: 146,
          child: OutlinedButton.icon(
            key: const ValueKey('creation-mode-voice-clone-action'),
            onPressed: () => unawaited(
              _handleOpenVoiceCloneTask(_inputController.text.trim(), const []),
            ),
            icon: const Icon(Icons.record_voice_over_outlined, size: 18),
            label: const Text('声音克隆'),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modeComposerHint(scheme, switch (voiceTool) {
          VoiceCreationTool.recognition => '上传音频后开始识别',
          VoiceCreationTool.music => '描述你想生成的音乐',
          VoiceCreationTool.design => '描述声音风格并输入朗读内容',
          VoiceCreationTool.clone => '输入要用克隆音色朗读的内容',
          VoiceCreationTool.synthesis => '输入要合成或创作的内容',
        }),
        const SizedBox(height: 12),
        _buildVoiceToolTabs(
          scheme,
          voiceTool,
          showSynthesis: showSynthesis,
          showRecognition: showRecognition,
          showMusic: showMusic,
          showDesign: showDesign,
          showClone: showClone,
        ),
        const SizedBox(height: 12),
        _modeParameterWrap(scheme, _voiceParameterLabels(voiceTool)),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '也可以使用下方输入框右侧的发送按钮自动执行当前语音任务',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  List<String> _voiceParameterLabels(VoiceCreationTool tool) {
    // The task-specific fields stay isolated: an ASR model never advertises
    // TTS controls, and music never shows a voice-clone reference.
    final labels = switch (tool) {
      VoiceCreationTool.synthesis => <String>[
        '输入内容',
        '音色',
        '语速 · 1.0x',
        '输出格式 · MP3',
      ],
      VoiceCreationTool.recognition => <String>['语音文件', '识别语言 · 自动'],
      VoiceCreationTool.music => <String>['音乐描述', '风格', '情绪', '时长', '人声模式'],
      VoiceCreationTool.design => <String>[
        '输入内容',
        '声音风格',
        '语速 · 1.0x',
        '输出格式 · MP3',
      ],
      VoiceCreationTool.clone => <String>[
        '输入内容',
        '参考音频',
        '语速 · 1.0x',
        '输出格式 · MP3',
      ],
    };
    return labels;
  }

  Widget _buildVoiceToolTabs(
    ColorScheme scheme,
    VoiceCreationTool selected, {
    required bool showSynthesis,
    required bool showRecognition,
    required bool showMusic,
    required bool showDesign,
    required bool showClone,
  }) {
    final visibleTools = <VoiceCreationTool>[
      if (showSynthesis) VoiceCreationTool.synthesis,
      if (showRecognition) VoiceCreationTool.recognition,
      if (showMusic) VoiceCreationTool.music,
      if (showDesign) VoiceCreationTool.design,
      if (showClone) VoiceCreationTool.clone,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tool in visibleTools)
          ChoiceChip(
            key: ValueKey('creation-mode-voice-tool-${tool.name}'),
            label: Text(tool.label),
            selected: selected == tool,
            onSelected: (_) =>
                ref.read(voiceCreationToolProvider.notifier).state = tool,
            selectedColor: scheme.primaryContainer,
          ),
      ],
    );
  }

  Widget _modeComposerHint(ColorScheme scheme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_outlined, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeParameterWrap(ColorScheme scheme, List<String> labels) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final label in labels)
          Chip(
            label: Text(label),
            side: BorderSide(color: scheme.outlineVariant),
            backgroundColor: scheme.surface,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  void _fillInputAndFocus(String text) {
    _inputController.text = text;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
    _hasTextNotifier.value = true;
    _focusNode.requestFocus();
  }

  Widget _buildEmptyChat() {
    final scheme = Theme.of(context).colorScheme;
    final suggestions = ['解释一个复杂概念', '帮我写一封邮件', '生成跨平台发布清单', '分析一段代码'];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '今天想聊什么？',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final text in suggestions)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _fillInputAndFocus(text),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ),
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 系统提示词页面：分类浏览 + 自定义编辑
class _SystemPromptPage extends StatefulWidget {
  const _SystemPromptPage({required this.initialPrompt, required this.onSave});

  final String initialPrompt;
  final ValueChanged<String> onSave;

  @override
  State<_SystemPromptPage> createState() => _SystemPromptPageState();
}

class _SystemPromptPageState extends State<_SystemPromptPage>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final TabController _tabController;
  bool _hasChanges = false;

  static const _categories = [
    _CategoryDef('全部', Icons.apps_outlined, 'all'),
    _CategoryDef('创作', Icons.brush_outlined, '创作'),
    _CategoryDef('办公', Icons.business_center_outlined, '办公'),
    _CategoryDef('医疗健康', Icons.health_and_safety_outlined, '医疗'),
    _CategoryDef('学习辅导', Icons.school_outlined, '学习'),
    _CategoryDef('使用工具', Icons.build_outlined, '工具'),
    _CategoryDef('教学辅助', Icons.menu_book_outlined, '教学'),
    _CategoryDef('法律服务', Icons.gavel_outlined, '法律'),
    _CategoryDef('生活', Icons.favorite_outline, '生活'),
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPrompt);
    _controller.addListener(_onTextChanged);
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  void _usePrompt(String content) {
    _controller.text = content;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('系统提示词'),
        actions: [
          TextButton(
            onPressed: () {
              widget.onSave(_controller.text);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _categories
              .map((c) => Tab(icon: Icon(c.icon, size: 18), text: c.label))
              .toList(),
        ),
      ),
      body: Column(
        children: [
          // 当前自定义提示词区域
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: scheme.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前提示词', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  '设定 AI 的角色和行为准则，留空则使用模型默认。',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(
                    minHeight: 80,
                    maxHeight: 160,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                    decoration: InputDecoration(
                      hintText: '点击输入自定义系统提示词...',
                      hintStyle: TextStyle(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${_controller.text.length} 字',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    const Spacer(),
                    if (_controller.text.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          _controller.clear();
                          widget.onSave('');
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('清除', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 提示词库 Tab 浏览
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _categories.map((cat) {
                return _PromptListView(category: cat.key, onUse: _usePrompt);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryDef {
  final String label;
  final IconData icon;
  final String key;
  const _CategoryDef(this.label, this.icon, this.key);
}

/// 提示词列表（按分类）
class _PromptListView extends ConsumerWidget {
  const _PromptListView({required this.category, required this.onUse});

  final String category;
  final ValueChanged<String> onUse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promptsAsync = ref.watch(promptNotifierProvider);

    return promptsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (prompts) {
        final filtered = category == 'all'
            ? prompts
            : prompts
                  .where(
                    (p) => p.category == category || p.category == 'general',
                  )
                  .toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.library_books_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  '暂无提示词',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '可在设置 → 提示词库中添加',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
          itemBuilder: (_, i) {
            final p = filtered[i];
            return ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  _categoryIcon(p.category),
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(p.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                p.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: TextButton(
                onPressed: () => onUse(p.content),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('使用'),
              ),
            );
          },
        );
      },
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case '创作':
        return Icons.brush_outlined;
      case '办公':
        return Icons.business_center_outlined;
      case '医疗':
        return Icons.health_and_safety_outlined;
      case '学习':
        return Icons.school_outlined;
      case '工具':
        return Icons.build_outlined;
      case '教学':
        return Icons.menu_book_outlined;
      case '法律':
        return Icons.gavel_outlined;
      case '生活':
        return Icons.favorite_outline;
      default:
        return Icons.text_snippet_outlined;
    }
  }
}
