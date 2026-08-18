import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai/universal_media_service.dart';
import '../../core/ai/model_capability.dart';
import '../../core/ai/model_switch_record.dart';
import '../../core/media/audio_player.dart';
import '../../core/media/audio_transcript_archive.dart';
import '../../core/media/attachment_export_service.dart';
import '../../core/media/baidu_cdn_image_uploader.dart';
import '../../core/database/dao/channel_dao.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/providers/image_generation_provider.dart';
import '../../shared/providers/image_generation_tasks_provider.dart';
import '../../shared/providers/channel_provider.dart';
import '../../shared/providers/connectivity_provider.dart';
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
    show ChatComposerDraft, ChatInputBar, PendingAttachment;

class _MediaRetryDraft {
  const _MediaRetryDraft({
    required this.kind,
    required this.prompt,
    required this.attachments,
  });

  final UniversalMediaKind kind;
  final String prompt;
  final List<PendingAttachment> attachments;
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _hasTextNotifier = ValueNotifier<bool>(false);

  /// 深度思考开关（会话内草稿状态）：开启后发送走 reasoner 模型。
  final _deepThinkEnabled = ValueNotifier<bool>(false);

  // 输入草稿缓存：按 sessionId 保存文本、附件和深度思考状态。
  static final Map<String, ChatComposerDraft> _draftCache = {};
  static const _maxDraftCacheSize = 50;
  String? _draftSessionId;

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
        _lastTerminalSpeechAudioPath = path;
        _lastTerminalPlaybackPath = path;
        var changed = false;
        if (_playingAttachmentPath == path) {
          changed = true;
        }
        if (_speakingAudioPath == path) changed = true;
        if (!changed) return;
        setState(() {
          if (_playingAttachmentPath == path) _playingAttachmentPath = null;
          if (_speakingAudioPath == path) {
            _speakingMessageId = null;
            _speakingAudioPath = null;
            _isPreparingSpeech = false;
          }
        });
    }
  }

  void _onTextChanged() {
    final hasText = _inputController.text.trim().isNotEmpty;
    if (_hasTextNotifier.value != hasText) {
      _hasTextNotifier.value = hasText;
    }
    // 缓存当前 session 的文本；切换会话时由 listener 先更新
    // [_draftSessionId]，避免把恢复动作写回旧会话。
    final currentId = ref.read(activeSessionIdProvider);
    if (currentId != null && currentId == _draftSessionId) {
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
    _draftCache[sessionId] = previous.copyWith(
      text: text,
      attachments: attachments,
      deepThink: deepThink,
    );
    if (_draftCache.length > _maxDraftCacheSize) {
      final keysToRemove = _draftCache.keys
          .take(_draftCache.length - _maxDraftCacheSize)
          .toList();
      for (final key in keysToRemove) {
        _draftCache.remove(key);
      }
    }
  }

  /// 清理已经成功持久化的旧会话草稿，但不触碰当前 controller / notifier。
  /// 这条路径只在操作返回成功且 UI 已经切到另一个会话时使用；当前会话
  /// 的正常清理仍必须经过 activeSessionId 检查并调用 [_saveDraft]。
  void _clearStoredDraftAfterSuccessfulOperation(String? sessionId) {
    if (sessionId == null) return;
    final draft = _draftCache[sessionId];
    if (draft == null) return;
    _draftCache[sessionId] = draft.copyWith(text: '', attachments: const []);
  }

  void _handleComposerDraftChanged(ChatComposerDraft draft) {
    final sessionId = _draftSessionId ?? ref.read(activeSessionIdProvider);
    if (sessionId == null ||
        !_isCurrentOperationSession(sessionId) ||
        _draftSessionId != sessionId) {
      return;
    }
    _saveDraft(
      sessionId,
      text: draft.text,
      attachments: List<PendingAttachment>.from(draft.attachments),
      deepThink: draft.deepThink,
    );
  }

  void _restoreComposerDraft(String? sessionId) {
    final draft = sessionId == null ? null : _draftCache[sessionId];
    _draftSessionId = sessionId;
    _inputController.text = draft?.text ?? '';
    _hasTextNotifier.value = _inputController.text.trim().isNotEmpty;
    _deepThinkEnabled.value = draft?.deepThink ?? false;
    _pendingModelId = null;
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

    if (requestedModelId != null &&
        models.any((m) => m.channelModel.id == requestedModelId)) {
      return requestedModelId;
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
          _saveDraft(activeSessionId, text: content);
          _inputController.text = content;
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: content.length),
          );
          _hasTextNotifier.value = content.trim().isNotEmpty;
        }
        return false;
      }
      // ChatInputBar 会在 onSend 返回成功后按实际传入的 attachment IDs
      // 移除草稿；页面这里只清空文本，避免误删并发期间产生的其它附件。
      if (_isCurrentOperationSession(activeSessionId)) {
        _saveDraft(activeSessionId, text: '');
        _blockedSendWhileOfflineSessionId = null;
        _inputController.clear();
        _hasTextNotifier.value = false;
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
        _inputController.text = content;
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: content.length),
        );
        _hasTextNotifier.value = content.trim().isNotEmpty;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发送失败: $e')));
      }
      return false;
    } finally {
      _finishComposerOperation(operationGeneration);
    }
  }

  Future<void> _handleStop() async {
    final sessionId = ref.read(activeSessionIdProvider);
    if (sessionId != null) {
      final hasRunningImageTask = ref
          .read(imageGenerationTasksProvider)
          .values
          .any(
            (task) => task.sessionId == sessionId && task.isRunning,
          );
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
      await ref
          .read(imageGenerationConfigProvider.notifier)
          .setSize(chosen!);
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
          _saveDraft(activeSessionId, text: content);
          _inputController.text = content;
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: content.length),
          );
          _hasTextNotifier.value = true;
        }
        return false;
      }
      if (_isCurrentOperationSession(activeSessionId)) {
        _saveDraft(activeSessionId, text: '');
        _hasTextNotifier.value = false;
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
  }) async {
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
      }
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }
      await ref
          .read(sessionDaoProvider)
          .updateDefaultModel(activeSessionId, resolvedModelId);
      if (!_isComposerOperationLive(operationGeneration)) return false;

      if (mediaKind != null) {
        _mediaRetryDrafts[activeSessionId] = _MediaRetryDraft(
          kind: mediaKind,
          prompt: content,
          attachments: List<PendingAttachment>.unmodifiable(mediaAttachments),
        );
      }

      final error = await action(activeSessionId);
      if (!mounted || !_isComposerOperationLive(operationGeneration)) {
        return false;
      }
      if (error != null) {
        if (_isCurrentOperationSession(activeSessionId)) {
          _showSnackBar(error);
          _restoreComposerText(content, activeSessionId);
        }
        return false;
      }
      if (mediaKind != null) _mediaRetryDrafts.remove(activeSessionId);
      if (_isCurrentOperationSession(activeSessionId)) {
        _saveDraft(activeSessionId, text: '');
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
        _restoreComposerText(content, activeSessionId);
      }
      return false;
    } finally {
      _finishComposerOperation(operationGeneration);
    }
  }

  void _restoreComposerText(String content, String? sessionId) {
    if (!_isCurrentOperationSession(sessionId)) return;
    if (sessionId != null) _saveDraft(sessionId, text: content);
    _inputController.text = content;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: content.length),
    );
    _hasTextNotifier.value = content.trim().isNotEmpty;
  }

  Future<bool> _handleGenerateVideo(
    String content,
    List<PendingAttachment> attachments,
  ) {
    return _runMediaAction(
      content,
      (sessionId) => generateVideo(
        ref: ref,
        sessionId: sessionId,
        prompt: content,
        referenceAttachments: attachments,
      ),
      mediaKind: UniversalMediaKind.video,
      mediaAttachments: attachments,
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
        UniversalMediaKind.video => generateVideo(
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

  String? _firstVoiceCloneReferencePath(List<PendingAttachment> attachments) {
    for (final attachment in attachments) {
      if (attachment.type != 'audio') continue;
      final path = attachment.path.trim();
      if (path.isNotEmpty) return path;
    }
    return null;
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
    final isImageMessage = messageAttachments.any(
      (a) => a.fileType == 'image',
    );

    final bool submitted;
    if (isImageMessage) {
      final error = await retryImageMessage(
        ref: ref,
        sessionId: operationSessionId,
        assistantMessageId: assistantMessageId,
      );
      submitted = error == null;
      if (error != null && mounted && _isCurrentOperationSession(operationSessionId)) {
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
    final selectedModelId = ref.watch(selectedModelIdProvider);
    final activeModel = activeSessionId == null
        ? null
        : ref.watch(chatSessionModelProvider(activeSessionId));
    final videoCapability = _resolveComposerMediaCapability(
      kind: UniversalMediaKind.video,
      activeSessionId: activeSessionId,
      activeModel: activeModel,
      models: modelsAsync,
      configReady: mediaConfigReady,
      config: mediaConfig,
      selectedModelId: selectedModelId,
    );
    final musicCapability = _resolveComposerMediaCapability(
      kind: UniversalMediaKind.music,
      activeSessionId: activeSessionId,
      activeModel: activeModel,
      models: modelsAsync,
      configReady: mediaConfigReady,
      config: mediaConfig,
      selectedModelId: selectedModelId,
    );

    if (activeSessionId == null) {
      return _buildEmptyState(
        videoCapability: videoCapability,
        musicCapability: musicCapability,
        ttsConfig: ttsConfig,
      );
    }

    final messagesAsync = ref.watch(messagesProvider(activeSessionId));
    final streamState = ref.watch(streamStateProvider(activeSessionId));
    final isOnline = ref.watch(isOnlineProvider);
    final mediaTask = ref.watch(universalMediaTaskProvider(activeSessionId));

    return Stack(
      children: [
        Column(
          children: [
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
                    if (messages.isEmpty && !streamState.isStreaming) {
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
                            messages.length + (streamState.isStreaming ? 1 : 0),
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
                            final imageTask = ref
                                .watch(imageGenerationTasksProvider)[msg.id];
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
              sessionId: activeSessionId,
              controller: _inputController,
              focusNode: _focusNode,
              isStreaming: streamState.isStreaming,
              isSubmitting: _isSubmitting,
              hasTextNotifier: _hasTextNotifier,
              onSend: _handleSend,
              onStop: _handleStop,
              onDraftChanged: _handleComposerDraftChanged,
              initialAttachments:
                  _draftCache[activeSessionId]?.attachments ?? const [],
              onGenerateImage: _handleGenerateImage,
              onGenerateImageWithAttachments:
                  _handleGenerateImageWithAttachments,
              onGenerateVideo: _handleGenerateVideo,
              videoActionDisabledReason: videoCapability.isAvailable
                  ? null
                  : videoCapability.message,
              onSynthesizeSpeech: _handleSynthesizeSpeech,
              onCloneVoice: _handleCloneVoice,
              onDesignVoice: _handleDesignVoice,
              speechActionDisabledReason: _voiceActionDisabledReason(
                ttsConfig,
                'standard',
              ),
              cloneVoiceActionDisabledReason: _voiceActionDisabledReason(
                ttsConfig,
                'voiceClone',
              ),
              designVoiceActionDisabledReason: _voiceActionDisabledReason(
                ttsConfig,
                'voiceDesign',
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
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

  Widget _buildEmptyState({
    required UniversalMediaCapability videoCapability,
    required UniversalMediaCapability musicCapability,
    required TextToSpeechConfig ttsConfig,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
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
                      '我们从哪里开始呢？',
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
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
          onSend: _handleSend,
          onStop: _handleStop,
          onDraftChanged: _handleComposerDraftChanged,
          onGenerateImage: _handleGenerateImage,
          onGenerateImageWithAttachments: _handleGenerateImageWithAttachments,
          onGenerateVideo: _handleGenerateVideo,
          videoActionDisabledReason: videoCapability.isAvailable
              ? null
              : videoCapability.message,
          onSynthesizeSpeech: _handleSynthesizeSpeech,
          onCloneVoice: _handleCloneVoice,
          onDesignVoice: _handleDesignVoice,
          speechActionDisabledReason: _voiceActionDisabledReason(
            ttsConfig,
            'standard',
          ),
          cloneVoiceActionDisabledReason: _voiceActionDisabledReason(
            ttsConfig,
            'voiceClone',
          ),
          designVoiceActionDisabledReason: _voiceActionDisabledReason(
            ttsConfig,
            'voiceDesign',
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
