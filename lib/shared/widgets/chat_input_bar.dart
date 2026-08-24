import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/attachments/attachment_policy.dart';
import '../../core/context/token_estimator.dart';
import '../../core/media/attachment_export_service.dart';
import '../../core/media/large_paste_policy.dart';
import '../../core/media/pasted_text_attachment_service.dart';
import '../../core/media/voice_recorder.dart';
import '../providers/universal_media_provider.dart';

const _composerDraftUuid = Uuid();

class PendingAttachment {
  /// 选择阶段的稳定 ID。发送后数据库会生成 message-owned attachment ID；
  /// draft ID 只用于在 composer 中精确移除 / 清理被消费的附件。
  final String? id;
  final String path;
  final String name;
  final String type; // image | video | pdf | audio | document
  final int fileSize;

  /// 仅由“大粘贴自动归档”创建时携带的私有文本元数据。普通文件附件保持
  /// null，避免把大文本的内容、hash 或本机路径误写入通用请求 JSON。
  final PastedTextAttachment? pastedText;

  const PendingAttachment({
    this.id,
    required this.path,
    required this.name,
    required this.type,
    this.fileSize = 0,
    this.pastedText,
  });

  PendingAttachment copyWith({
    String? id,
    String? path,
    String? name,
    int? fileSize,
    PastedTextAttachment? pastedText,
    bool clearPastedText = false,
  }) {
    return PendingAttachment(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      type: type,
      fileSize: fileSize ?? this.fileSize,
      pastedText: clearPastedText ? null : pastedText ?? this.pastedText,
    );
  }

  String get stableId {
    final explicitId = id?.trim();
    if (explicitId != null && explicitId.isNotEmpty) return explicitId;
    final normalizedPath = path.trim();
    if (normalizedPath.isNotEmpty) return normalizedPath;
    return '$name:$type:$fileSize';
  }
}

/// Chat composer 的 session-scoped 草稿快照。
///
/// 文本由页面的 controller 保存，附件和深度思考状态也必须一并按会话
/// 保存；否则切换 A/B 会话时，原本只恢复文本的实现会把 A 的附件继续发到 B。
class ChatComposerDraft {
  final String text;
  final List<PendingAttachment> attachments;
  final bool deepThink;

  const ChatComposerDraft({
    this.text = '',
    this.attachments = const [],
    this.deepThink = false,
  });

  ChatComposerDraft copyWith({
    String? text,
    List<PendingAttachment>? attachments,
    bool? deepThink,
  }) {
    return ChatComposerDraft(
      text: text ?? this.text,
      attachments: attachments ?? this.attachments,
      deepThink: deepThink ?? this.deepThink,
    );
  }
}

/// Unified Composer submission result.
///
/// A boolean is not enough for a multimodal Composer: TTS consumes only text,
/// image/video tasks may consume a selected subset of the draft files, while
/// a normal chat turn consumes every attachment it sends.  Keeping the exact
/// stable IDs in the result prevents a successful media task from deleting
/// unrelated files that the user prepared for the next request.
class ComposerSendOutcome {
  const ComposerSendOutcome._({
    required this.succeeded,
    this.consumedAttachmentIds = const <String>{},
  });

  const ComposerSendOutcome.success({
    Set<String> consumedAttachmentIds = const <String>{},
  }) : this._(succeeded: true, consumedAttachmentIds: consumedAttachmentIds);

  const ComposerSendOutcome.failure()
    : this._(succeeded: false, consumedAttachmentIds: const <String>{});

  final bool succeeded;
  final Set<String> consumedAttachmentIds;
}

class _InsertedTextRange {
  const _InsertedTextRange(this.start, this.end);

  final int start;
  final int end;
}

enum _PastedTextAttachmentAction { preview, rename, restore, delete }

/// ChatGPT-style bottom composer.
class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? sessionId;
  final bool isStreaming;
  final bool isSubmitting;
  final ValueNotifier<bool> hasTextNotifier;
  final Future<bool> Function(String text, List<PendingAttachment> attachments)
  onSend;

  /// Exact-consumption variant used by the production multimodal page.
  ///
  /// [onSend] remains available for older callers and tests. When both are
  /// supplied, this callback wins so a task can retain unrelated attachments.
  final Future<ComposerSendOutcome> Function(
    String text,
    List<PendingAttachment> attachments,
  )?
  onSendWithOutcome;

  /// 独立于发送 busy guard 的停止动作。流式聊天和音频转写阶段都走这里。
  final Future<void> Function()? onStop;
  final ValueChanged<ChatComposerDraft>? onDraftChanged;

  /// 图片生成回调：入参为输入框文本，返回是否成功（成功后清空输入框）。
  /// 为 null 时不显示“生成图片”按钮。
  final Future<bool> Function(String text)? onGenerateImage;

  /// 带参考附件的图片生成回调。保留 [onGenerateImage] 以兼容只支持文本
  /// 生图的调用方；配置此回调后，输入栏会把已选图片作为参考图传出。
  final Future<bool> Function(String text, List<PendingAttachment> attachments)?
  onGenerateImageWithAttachments;

  /// 完整图片任务面板回调。与旧版图片回调不同，这个入口把 Composer 中
  /// 的全部图片参考附件交给页面，由页面打开本次任务参数面板并创建不可变
  /// 的请求快照；未配置时继续使用旧版单参考图兼容路径。
  final Future<Set<String>?> Function(
    String text,
    List<PendingAttachment> attachments,
  )?
  onOpenImageGenerationTask;

  /// 通用媒体动作。它们都采用 ChatGPT Composer 的“工具菜单”交互：
  /// 输入提示词，必要时附带参考文件，再把结果作为 assistant 媒体消息写回。
  /// 视频生成 extra 携带用户在弹窗中选择的时长 / 分辨率等请求参数。
  final Future<bool> Function(
    String text,
    List<PendingAttachment> attachments,
    Map<String, dynamic> extra,
  )?
  onGenerateVideo;

  /// 完整的视频任务面板回调。相比旧的 [onGenerateVideo]，这个入口保留
  /// 首帧图、多个参考图、参考音频、时长、比例和分辨率的角色语义，避免
  /// 页面层再从自由字段 Map 猜测附件用途。
  final Future<bool> Function(String text, VideoGenerationConfig config)?
  onOpenVideoGenerationTask;

  /// Production configuration sheet shared with the top video-model send
  /// path. Supplying this removes the historical split where the `+` menu and
  /// the main send button exposed different durations, ratios and attachment
  /// roles. Older embedders can omit it and keep the local compatibility
  /// dialog.
  final Future<VideoGenerationConfig?> Function(
    String text,
    List<PendingAttachment> attachments,
  )?
  onConfigureVideoGenerationTask;

  /// 语音识别语言单次选择（麦克风长按）：auto / zh / en。
  final void Function(String language)? onSpeechLanguageSelected;
  final Future<Set<String>?> Function(List<PendingAttachment> attachments)?
  onOpenSpeechRecognitionTask;
  final Future<bool> Function(String text)? onSynthesizeSpeech;

  /// 打开一次性的语音合成任务面板。配置后由页面把音色、语速和输出
  /// 格式作为本次请求参数传递给 provider；为空时兼容旧的直接合成入口。
  final Future<bool> Function(String text)? onOpenSpeechSynthesisTask;

  /// 声音克隆回调。默认要求 Composer 中存在一个 audio 附件，并把第一条
  /// 音频作为参考音频传出；如果上游已经在设置中持久化并校验参考音频，
  /// 可以通过 [useConfiguredVoiceCloneReferenceAudio] 关闭这个本地附件门禁。
  final Future<bool> Function(String text, List<PendingAttachment> attachments)?
  onCloneVoice;

  /// 打开一次性的声音克隆任务面板。面板可以在提交前确认参考音频、语速和
  /// 输出格式；为空时兼容旧的直接克隆入口。
  final Future<bool> Function(String text, List<PendingAttachment> attachments)?
  onOpenVoiceCloneTask;

  /// 声音设计回调：输入框文字作为声音设计描述传出。具体 provider / 云端
  /// 能力由上游回调决定，Composer 不伪造任何远端能力。
  final Future<bool> Function(String text)? onDesignVoice;
  final Future<bool> Function(String text)? onOpenVoiceDesignTask;
  final Future<bool> Function(String text)? onGenerateMusic;

  /// 当前会话的视频 / 音乐能力不可用时仍保留工具菜单入口，但以禁用
  /// 状态展示这个明确原因。null 表示对应动作已通过能力检查。
  final String? videoActionDisabledReason;
  final String? musicActionDisabledReason;
  final String? speechActionDisabledReason;
  final String? cloneVoiceActionDisabledReason;
  final String? designVoiceActionDisabledReason;

  /// 声音克隆回调是否使用上游已经配置好的参考音频，而不是 Composer
  /// 中当前选中的 audio 附件。为 false 时，菜单会要求用户先附加参考音频。
  final bool useConfiguredVoiceCloneReferenceAudio;

  /// 重试最近一次失败 / 取消的通用媒体任务。返回非 null 表示重试成功；
  /// 返回的 stable IDs 是这次重试实际消费的附件，空集合表示只消费文本。
  final Future<Set<String>?> Function()? onRetryMedia;

  /// 当前会话的通用媒体任务状态。它独立于聊天发送的 isSubmitting，便于
  /// Composer 在轮询期间显示排队 / 生成 / 保存和 Stop。
  final UniversalMediaTaskState? mediaTask;

  /// 编辑图片回调：选图后由外部打开编辑对话框。为 null 时不显示入口。
  final Future<bool> Function(String imagePath)? onEditImage;

  /// 深度思考开关状态（外部持有 ValueNotifier）。为 null 时不显示开关按钮。
  final ValueNotifier<bool>? deepThinkNotifier;

  /// 替身回复回调：为最近一条用户消息以镜像人格生成回复。为 null 时不显示入口。
  final Future<bool> Function()? onPersonaReply;

  /// 打开 ChatGPT 风格实时语音对话面板。面板自己管理 Realtime
  /// WebSocket 生命周期；当前原生录音按钮仍然是文件录音 → STT 路径。
  final Future<void> Function()? onRealtimeVoice;
  final Widget? modelSelector;
  final VoiceRecorderPlatform? voiceRecorder;

  /// 可注入的草稿归档器。生产环境使用应用私有 support 目录；测试和
  /// 隔离运行可以提供临时根目录，避免依赖平台 path_provider 通道。
  final AttachmentDraftArchive? draftArchive;
  final bool? showVoiceInput;

  /// 可选的初始附件，用于恢复外部持有的草稿或 Widget 测试；Widget 后续仍由
  /// 自身维护附件增删，不会在每次父级 rebuild 时重置。
  final List<PendingAttachment> initialAttachments;

  /// 是否在附件条中读取本地图片缩略图。默认开启；在低内存场景或外部已经
  /// 提供预览层时可以关闭，但不会影响图片附件发送或参考图编辑。
  final bool showImageAttachmentPreviews;

  /// 大粘贴判定策略。默认采用产品定义的 16000 字符 / 64 KiB / 8000
  /// token 任一阈值；测试或设置页可以注入覆盖，不能在 TextField 内散落阈值。
  final LargePastePolicy largePastePolicy;

  /// 可注入私有文本附件服务。默认和 [draftArchive] 共用同一 Composer
  /// 私有目录，以保证删除、重命名和草稿恢复使用相同的目录边界。
  final PastedTextAttachmentService? pastedTextAttachmentService;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.sessionId,
    required this.isStreaming,
    this.isSubmitting = false,
    required this.hasTextNotifier,
    required this.onSend,
    this.onSendWithOutcome,
    this.onStop,
    this.onDraftChanged,
    this.onGenerateImage,
    this.onGenerateImageWithAttachments,
    this.onOpenImageGenerationTask,
    this.onGenerateVideo,
    this.onOpenVideoGenerationTask,
    this.onConfigureVideoGenerationTask,
    this.onSpeechLanguageSelected,
    this.onOpenSpeechRecognitionTask,
    this.onSynthesizeSpeech,
    this.onOpenSpeechSynthesisTask,
    this.onCloneVoice,
    this.onOpenVoiceCloneTask,
    this.onDesignVoice,
    this.onOpenVoiceDesignTask,
    this.onGenerateMusic,
    this.videoActionDisabledReason,
    this.musicActionDisabledReason,
    this.speechActionDisabledReason,
    this.cloneVoiceActionDisabledReason,
    this.designVoiceActionDisabledReason,
    this.useConfiguredVoiceCloneReferenceAudio = false,
    this.onRetryMedia,
    this.mediaTask,
    this.onEditImage,
    this.deepThinkNotifier,
    this.onPersonaReply,
    this.onRealtimeVoice,
    this.modelSelector,
    this.voiceRecorder,
    this.draftArchive,
    this.showVoiceInput,
    this.initialAttachments = const [],
    this.showImageAttachmentPreviews = true,
    this.largePastePolicy = const LargePastePolicy(),
    this.pastedTextAttachmentService,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with WidgetsBindingObserver {
  final _imagePicker = ImagePicker();
  late final AttachmentDraftArchive _draftArchive;
  late final PastedTextAttachmentService _pastedTextAttachmentService;
  late String _draftId;
  late TextEditingValue _lastEditingValue;
  final List<PendingAttachment> _pendingAttachments = [];
  bool _isReplacingLargePaste = false;
  bool _isRecordingVoice = false;
  bool _isVoiceBusy = false;
  bool _isDraggingFiles = false;
  int _voiceOperation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draftArchive = widget.draftArchive ?? const AttachmentDraftArchive();
    _pastedTextAttachmentService =
        widget.pastedTextAttachmentService ??
        PastedTextAttachmentService(archive: _draftArchive);
    _draftId = _newDraftId(widget.sessionId);
    _lastEditingValue = widget.controller.value;
    widget.controller.addListener(_handleComposerTextChanged);
    _syncHasTextNotifier();
    _pendingAttachments.addAll(widget.initialAttachments);
    unawaited(_recoverLostImagePickerData());
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleComposerTextChanged);
      widget.controller.addListener(_handleComposerTextChanged);
      _lastEditingValue = widget.controller.value;
    }
    _syncHasTextNotifier();
    if (oldWidget.sessionId == widget.sessionId) return;

    _draftId = _newDraftId(widget.sessionId);
    _lastEditingValue = widget.controller.value;
    // 会话替换时先终止录音，再装载新会话的附件草稿；不能把旧会话的
    // recording result 或附件列表带到新会话。
    unawaited(_cancelVoiceRecording());
    if (!mounted) return;
    setState(() {
      _pendingAttachments
        ..clear()
        ..addAll(widget.initialAttachments);
      _isRecordingVoice = false;
      _isVoiceBusy = false;
    });
    // 会话切换时附件由外部的 session-scoped draft 提供。这里的状态同步
    // 不是用户编辑，不能把刚切入会话的持久化草稿误写为空草稿；真正的
    // 附件增删、文本修改和深度思考切换仍会通过 [_notifyDraftChanged] 上报。
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_cancelVoiceRecording());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleComposerTextChanged);
    // dispose 不能等待平台调用，但必须告诉原生录音通道结束当前 session。
    unawaited(_cancelVoiceRecording(updateUi: false));
    super.dispose();
  }

  void _syncHasTextNotifier() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (widget.hasTextNotifier.value != hasText) {
      widget.hasTextNotifier.value = hasText;
    }
  }

  String _newDraftId(String? sessionId) =>
      '${sessionId?.trim().isNotEmpty == true ? sessionId!.trim() : 'new'}-${_composerDraftUuid.v4()}';

  /// 对 TextEditingValue 的相邻状态做最小 diff，只取本次插入片段评估。
  ///
  /// Flutter 没有跨所有 Android 输入法的一致 paste callback；大段剪贴板
  /// 粘贴最终都会形成一次 EditingValue 插入。因此在 controller 边界处理，
  /// 不依赖某个厂商键盘的菜单实现。连续逐字输入不会达到单次 delta 阈值。
  void _handleComposerTextChanged() {
    final current = widget.controller.value;
    final previous = _lastEditingValue;
    _lastEditingValue = current;
    _syncHasTextNotifier();
    if (_isReplacingLargePaste || current.text == previous.text) return;

    final diff = _findInsertedRange(previous.text, current.text);
    if (diff == null) return;
    final inserted = current.text.substring(diff.start, diff.end);
    if (inserted.isEmpty) return;
    final decision = widget.largePastePolicy.evaluate(inserted);
    if (!decision.shouldArchive) return;

    // 先同步移除 delta；异步写文件期间用户仍可继续编辑剩余草稿。若归档失败，
    // _restoreLargePasteAfterFailure 会把原始文本放回当前编辑位置。
    _replaceComposerText(
      removeInsertedText(
        current.text,
        insertionStart: diff.start,
        insertionEnd: diff.end,
      ),
      selectionOffset: diff.start,
    );
    final sessionId = widget.sessionId;
    unawaited(
      _archiveLargePaste(
        sessionId: sessionId,
        insertionOffset: diff.start,
        text: inserted,
        decision: decision,
      ),
    );
  }

  _InsertedTextRange? _findInsertedRange(String previous, String current) {
    // 替换选区的粘贴可能比被替换文本短，因此不能仅比较全文长度。纯删除的
    // diff 会得到空 inserted range 并由调用方跳过，不会误归档现有草稿。
    var prefix = 0;
    final commonLimit = previous.length < current.length
        ? previous.length
        : current.length;
    while (prefix < commonLimit &&
        previous.codeUnitAt(prefix) == current.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < previous.length - prefix &&
        suffix < current.length - prefix &&
        previous.codeUnitAt(previous.length - 1 - suffix) ==
            current.codeUnitAt(current.length - 1 - suffix)) {
      suffix++;
    }
    final end = current.length - suffix;
    if (end <= prefix) return null;
    return _InsertedTextRange(prefix, end);
  }

  void _replaceComposerText(String text, {required int selectionOffset}) {
    final safeOffset = selectionOffset.clamp(0, text.length).toInt();
    _isReplacingLargePaste = true;
    try {
      widget.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: safeOffset),
        composing: TextRange.empty,
      );
    } finally {
      _isReplacingLargePaste = false;
    }
  }

  Future<void> _archiveLargePaste({
    required String? sessionId,
    required int insertionOffset,
    required String text,
    required LargePasteDecision decision,
  }) async {
    PastedTextAttachment? pasted;
    try {
      pasted = await _pastedTextAttachmentService.create(
        conversationId: sessionId?.trim().isNotEmpty == true
            ? sessionId!.trim()
            : 'new-conversation',
        draftId: _draftId,
        text: text,
        decision: decision,
      );
      if (!_isCurrentOperationSession(sessionId)) {
        await _pastedTextAttachmentService.delete(pasted);
        return;
      }
      _addAttachmentWithValidation(
        PendingAttachment(
          id: pasted.id,
          path: pasted.localPath,
          name: pasted.displayName,
          type: 'document',
          fileSize: pasted.utf8ByteCount,
          pastedText: pasted,
        ),
        fileSize: pasted.utf8ByteCount,
      );
      if (mounted && _isCurrentOperationSession(sessionId)) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('粘贴内容较长，已转换为附件')));
      }
    } catch (_) {
      if (pasted != null) {
        try {
          await _pastedTextAttachmentService.delete(pasted);
        } catch (_) {
          // 归档失败时原始文本恢复优先，清理失败交由下一次 draft 清理收敛。
        }
      }
      if (mounted && _isCurrentOperationSession(sessionId)) {
        final current = widget.controller.value;
        final safeOffset = insertionOffset
            .clamp(0, current.text.length)
            .toInt();
        _replaceComposerText(
          current.text.replaceRange(safeOffset, safeOffset, text),
          selectionOffset: safeOffset + text.length,
        );
        _showAttachmentError('粘贴内容归档失败，已保留在输入框中');
      }
    }
  }

  void _notifyDraftChanged() {
    widget.onDraftChanged?.call(
      ChatComposerDraft(
        text: widget.controller.text,
        attachments: List<PendingAttachment>.unmodifiable(_pendingAttachments),
        deepThink: widget.deepThinkNotifier?.value ?? false,
      ),
    );
  }

  /// Clear only the exact text revision submitted by an older async action.
  /// Users may type their next prompt while image/audio/video work is running;
  /// that newer text must survive completion of the previous task.
  void _clearSubmittedTextIfUnchanged(String submittedText) {
    if (!mounted || widget.controller.text != submittedText) return;
    widget.controller.clear();
    widget.hasTextNotifier.value = false;
  }

  bool _isCurrentOperationSession(String? operationSessionId) {
    return mounted && widget.sessionId == operationSessionId;
  }

  /// 部分第三方输入法在应用切回前台或切换输入法后，会保留 Flutter 的输入
  /// 连接但不重新显示自身窗口。TextField 默认会请求焦点；这里在下一帧显式
  /// 重发一次 show 请求，确保输入连接完成建立后再通知系统 IME。
  void _requestComposerFocus() {
    widget.focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focusNode.hasFocus) return;
      unawaited(
        SystemChannels.textInput
            .invokeMethod<void>('TextInput.show')
            .catchError((Object _) {}),
      );
    });
  }

  Future<void> _handleSend() async {
    final operationSessionId = widget.sessionId;
    if (widget.mediaTask?.isBusy == true ||
        widget.isStreaming ||
        widget.isSubmitting) {
      await _handleStop();
      return;
    }
    if (_isRecordingVoice) {
      _showAttachmentError('请先结束当前录音');
      return;
    }
    final submittedText = widget.controller.text;
    final content = submittedText.trim();
    if (content.isEmpty && _pendingAttachments.isEmpty) return;
    final attachments = List<PendingAttachment>.from(_pendingAttachments);
    late final ComposerSendOutcome outcome;
    try {
      final exactCallback = widget.onSendWithOutcome;
      if (exactCallback != null) {
        outcome = await exactCallback(content, attachments);
      } else {
        final sent = await widget.onSend(content, attachments);
        outcome = sent
            ? ComposerSendOutcome.success(
                consumedAttachmentIds: attachments
                    .map((attachment) => attachment.stableId)
                    .toSet(),
              )
            : const ComposerSendOutcome.failure();
      }
    } catch (_) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        _showActionFailure('发送');
      }
      return;
    }
    if (!outcome.succeeded ||
        !mounted ||
        !_isCurrentOperationSession(operationSessionId)) {
      return;
    }
    _clearSubmittedTextIfUnchanged(submittedText);
    _removeConsumedAttachmentIds(outcome.consumedAttachmentIds);
    _notifyDraftChanged();
  }

  Future<void> _handleStop() async {
    // Stop 永远不检查 isSubmitting：STT 预处理和聊天流本来就可能让
    // isSubmitting=true，但用户仍必须能立即取消。
    try {
      if (widget.onStop != null) {
        await widget.onStop!();
        return;
      }
      // 保持旧调用方兼容；新页面始终提供显式 onStop。
      final exactCallback = widget.onSendWithOutcome;
      if (exactCallback != null) {
        await exactCallback('', const []);
      } else {
        await widget.onSend('', const []);
      }
    } catch (_) {
      if (mounted) _showActionFailure('停止');
    }
  }

  void _removeConsumedAttachments(List<PendingAttachment> consumed) {
    // 文本媒体 action 也会经过这里，但它可能没有附件输入。即使没有
    // 可移除的附件，也要把 action 成功后的空文本快照通知给会话草稿持有者；
    // 否则 UI 已清空，session-scoped draft 仍可能保留旧 prompt。
    if (consumed.isEmpty) {
      _notifyDraftChanged();
      return;
    }
    _removeConsumedAttachmentIds(consumed.map((item) => item.stableId));
  }

  void _removeConsumedAttachmentIds(Iterable<String> stableIds) {
    if (!mounted) return;
    final consumedIds = stableIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (consumedIds.isEmpty) return;
    final removed = _pendingAttachments
        .where((item) => consumedIds.contains(item.stableId))
        .toList(growable: false);
    if (removed.isEmpty) return;
    setState(
      () => _pendingAttachments.removeWhere(
        (item) => consumedIds.contains(item.stableId),
      ),
    );
    _notifyDraftChanged();
    // 只清理本次回调实际收到的 attachment ids；其它 session / 其它草稿
    // 不会因为一次发送成功而被无差别删除。
    unawaited(
      Future.wait(
        removed.map((item) => _draftArchive.deleteFile(item.path)),
      ).then<void>((_) {}).catchError((_) {}),
    );
  }

  Future<void> _handleGenerateImage() async {
    final submittedText = widget.controller.text;
    final text = submittedText.trim();
    final operationSessionId = widget.sessionId;
    if (text.isEmpty ||
        (widget.onGenerateImage == null &&
            widget.onGenerateImageWithAttachments == null &&
            widget.onOpenImageGenerationTask == null) ||
        widget.isStreaming ||
        widget.isSubmitting ||
        widget.mediaTask?.isBusy == true) {
      return;
    }
    if (_isRecordingVoice) {
      _showAttachmentError('请先结束当前录音');
      return;
    }
    // /v1/images/edits 当前只使用第一张图片作为参考图；其它附件不是这次
    // 工具动作的输入，成功后必须保留在 Composer 中供用户后续使用。
    final offeredAttachments = widget.onOpenImageGenerationTask != null
        ? _allImageReferenceAttachments()
        : widget.onGenerateImageWithAttachments != null
        ? _firstImageReferenceAttachments()
        : const <PendingAttachment>[];
    bool ok;
    Set<String>? consumedIds;
    try {
      if (widget.onOpenImageGenerationTask != null) {
        consumedIds = await widget.onOpenImageGenerationTask!(
          text,
          offeredAttachments,
        );
        ok = consumedIds != null;
      } else {
        ok = widget.onGenerateImageWithAttachments != null
            ? await widget.onGenerateImageWithAttachments!(
                text,
                offeredAttachments,
              )
            : await widget.onGenerateImage!(text);
      }
    } catch (_) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        _showActionFailure('图片生成');
      }
      return;
    }
    if (ok && _isCurrentOperationSession(operationSessionId)) {
      _clearSubmittedTextIfUnchanged(submittedText);
      if (consumedIds != null) {
        _removeConsumedAttachmentIds(consumedIds);
      } else {
        _removeConsumedAttachments(offeredAttachments);
      }
      _notifyDraftChanged();
    }
  }

  List<PendingAttachment> _firstImageReferenceAttachments() {
    for (final attachment in _pendingAttachments) {
      if (attachment.type == 'image') {
        return [attachment];
      }
    }
    return const <PendingAttachment>[];
  }

  List<PendingAttachment> _allImageReferenceAttachments() {
    return _pendingAttachments
        .where((attachment) => attachment.type == 'image')
        .toList(growable: false);
  }

  List<PendingAttachment> _firstAudioReferenceAttachments() {
    for (final attachment in _pendingAttachments) {
      if (attachment.type == 'audio') {
        return [attachment];
      }
    }
    return const <PendingAttachment>[];
  }

  String _mediaStatusText(UniversalMediaTaskState task) {
    final label = task.kindLabel;
    return switch (task.phase) {
      UniversalMediaTaskPhase.submitting ||
      UniversalMediaTaskPhase.pending => '$label排队中…',
      UniversalMediaTaskPhase.polling => '$label生成中…',
      UniversalMediaTaskPhase.saving => '$label保存中…',
      UniversalMediaTaskPhase.completed => '$label已完成',
      UniversalMediaTaskPhase.failed ||
      UniversalMediaTaskPhase.expired ||
      UniversalMediaTaskPhase.cancelled => task.statusText,
    };
  }

  Future<void> _handleRetryMedia() async {
    final callback = widget.onRetryMedia;
    if (callback == null || widget.mediaTask?.canRetry != true) return;
    final operationSessionId = widget.sessionId;
    try {
      final consumedIds = await callback();
      if (consumedIds == null ||
          !mounted ||
          widget.sessionId != operationSessionId) {
        return;
      }
      widget.controller.clear();
      widget.hasTextNotifier.value = false;
      _removeConsumedAttachmentIds(consumedIds);
      _notifyDraftChanged();
    } catch (_) {
      if (mounted) _showAttachmentError('媒体任务重试失败，已保留输入和附件');
    }
  }

  bool _usesCompactActionLayout(BuildContext context) {
    // 手机主行只保留 +、编辑区、麦克风和发送 / 停止；画图、深度思考等
    // secondary tools 收进 + 菜单。390px 宽度也必须走这条路径。
    return MediaQuery.sizeOf(context).width < 600;
  }

  void _showAttachmentMenu() {
    final isDesktop =
        kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final compactActions = _usesCompactActionLayout(context);
    final hasVoiceOrEditingActions =
        widget.onRealtimeVoice != null || widget.onEditImage != null;
    final hasCreationActions =
        (compactActions &&
            (widget.onGenerateImage != null ||
                widget.onGenerateImageWithAttachments != null ||
                widget.onOpenImageGenerationTask != null ||
                widget.deepThinkNotifier != null)) ||
        (widget.onGenerateVideo != null ||
            widget.onOpenVideoGenerationTask != null) ||
        (widget.onSynthesizeSpeech != null ||
            widget.onOpenSpeechSynthesisTask != null) ||
        (widget.onCloneVoice != null || widget.onOpenVoiceCloneTask != null) ||
        (widget.onDesignVoice != null ||
            widget.onOpenVoiceDesignTask != null) ||
        widget.onOpenSpeechRecognitionTask != null ||
        widget.onGenerateMusic != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.9;
        return SafeArea(
          // 小屏下会额外收纳画图 / 深度思考；允许滚动，避免动作增多后
          // BottomSheet 在 568px 等短屏上溢出。
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              key: const ValueKey('composer-attachment-menu-scroll'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAttachmentMenuSectionHeader(ctx, '添加内容'),
                  if (!isDesktop)
                    ListTile(
                      leading: const Icon(Icons.camera_alt_outlined),
                      title: const Text('相机拍照'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.camera);
                      },
                    ),
                  if (!isDesktop)
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('从相册选择'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.attach_file),
                    title: const Text('选择文件'),
                    subtitle: const Text('可多选图片、视频、音频、PDF 和普通文件'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickFile();
                    },
                  ),
                  if (hasVoiceOrEditingActions) ...[
                    _buildAttachmentMenuSectionHeader(ctx, '语音与编辑'),
                    if (widget.onRealtimeVoice != null)
                      ListTile(
                        key: const ValueKey('realtime-voice-menu-item'),
                        leading: const Icon(Icons.graphic_eq_outlined),
                        title: const Text('实时语音对话'),
                        subtitle: const Text(
                          '连接 OpenAI / xAI Realtime，查看转写与回答',
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          unawaited(_openRealtimeVoice());
                        },
                      ),
                    if (widget.onEditImage != null)
                      ListTile(
                        leading: const Icon(Icons.photo_filter_outlined),
                        title: const Text('编辑图片'),
                        subtitle: const Text('优先使用当前已选图片，否则选择参考图'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickImageForEdit();
                        },
                      ),
                  ],
                  if (hasCreationActions) ...[
                    _buildAttachmentMenuSectionHeader(ctx, '生成与工具'),
                    if (widget.onOpenSpeechRecognitionTask != null)
                      ListTile(
                        key: const ValueKey('recognize-speech-menu-item'),
                        leading: const Icon(Icons.transcribe_outlined),
                        title: const Text('识别语音'),
                        subtitle: Text(
                          _firstAudioReferenceAttachments().isEmpty
                              ? '先通过“选择文件”附加语音文件'
                              : '选择识别语言并生成转写结果',
                        ),
                        enabled:
                            _firstAudioReferenceAttachments().isNotEmpty &&
                            !widget.isStreaming &&
                            !widget.isSubmitting &&
                            widget.mediaTask?.isBusy != true &&
                            !_isRecordingVoice,
                        onTap:
                            _firstAudioReferenceAttachments().isNotEmpty &&
                                !widget.isStreaming &&
                                !widget.isSubmitting &&
                                widget.mediaTask?.isBusy != true &&
                                !_isRecordingVoice
                            ? () async {
                                Navigator.pop(ctx);
                                final callback =
                                    widget.onOpenSpeechRecognitionTask;
                                if (callback == null) return;
                                final consumedIds = await callback(
                                  _firstAudioReferenceAttachments(),
                                );
                                if (consumedIds != null &&
                                    _isCurrentOperationSession(
                                      widget.sessionId,
                                    )) {
                                  _removeConsumedAttachmentIds(consumedIds);
                                }
                              }
                            : null,
                      ),
                    if (compactActions &&
                        (widget.onGenerateImage != null ||
                            widget.onGenerateImageWithAttachments != null ||
                            widget.onOpenImageGenerationTask != null))
                      ValueListenableBuilder<bool>(
                        valueListenable: widget.hasTextNotifier,
                        builder: (_, hasText, _) => ListTile(
                          leading: const Icon(Icons.auto_awesome),
                          title: const Text('生成图片'),
                          subtitle: Text(
                            hasText ? '使用当前输入生成图片' : '先在输入框填写图片描述',
                          ),
                          enabled:
                              hasText &&
                              !widget.isStreaming &&
                              !widget.isSubmitting &&
                              widget.mediaTask?.isBusy != true &&
                              !_isRecordingVoice,
                          onTap:
                              hasText &&
                                  !widget.isStreaming &&
                                  !widget.isSubmitting &&
                                  widget.mediaTask?.isBusy != true &&
                                  !_isRecordingVoice
                              ? () async {
                                  Navigator.pop(ctx);
                                  await _handleGenerateImage();
                                }
                              : null,
                        ),
                      ),
                    if (compactActions && widget.deepThinkNotifier != null)
                      ValueListenableBuilder<bool>(
                        valueListenable: widget.deepThinkNotifier!,
                        builder: (_, deepThink, _) => SwitchListTile(
                          secondary: Icon(
                            deepThink
                                ? Icons.psychology_alt
                                : Icons.psychology_alt_outlined,
                          ),
                          title: const Text('深度思考'),
                          subtitle: Text(
                            deepThink ? '已开启' : '使用当前渠道的 reasoner 模型',
                          ),
                          value: deepThink,
                          onChanged:
                              widget.isStreaming ||
                                  widget.isSubmitting ||
                                  widget.mediaTask?.isBusy == true ||
                                  _isRecordingVoice
                              ? null
                              : (value) {
                                  widget.deepThinkNotifier!.value = value;
                                  _notifyDraftChanged();
                                  Navigator.pop(ctx);
                                },
                        ),
                      ),
                    if (widget.onGenerateVideo != null ||
                        widget.onOpenVideoGenerationTask != null)
                      ValueListenableBuilder<bool>(
                        valueListenable: widget.hasTextNotifier,
                        builder: (_, hasText, _) => ListTile(
                          key: const ValueKey('generate-video-menu-item'),
                          leading: const Icon(Icons.movie_creation_outlined),
                          title: const Text('生成视频'),
                          subtitle: Text(
                            widget.videoActionDisabledReason ??
                                (hasText ? '用提示词生成视频，可附带参考图' : '先填写视频描述'),
                          ),
                          enabled:
                              hasText &&
                              widget.videoActionDisabledReason == null &&
                              !widget.isStreaming &&
                              !widget.isSubmitting &&
                              widget.mediaTask?.isBusy != true &&
                              !_isRecordingVoice,
                          onTap:
                              hasText &&
                                  widget.videoActionDisabledReason == null &&
                                  !widget.isStreaming &&
                                  !widget.isSubmitting &&
                                  widget.mediaTask?.isBusy != true &&
                                  !_isRecordingVoice
                              ? () async {
                                  Navigator.pop(ctx);
                                  await _handleGenerateVideo();
                                }
                              : null,
                        ),
                      ),
                    if (widget.onSynthesizeSpeech != null ||
                        widget.onOpenSpeechSynthesisTask != null)
                      ValueListenableBuilder<bool>(
                        valueListenable: widget.hasTextNotifier,
                        builder: (_, hasText, _) => ListTile(
                          key: const ValueKey('synthesize-speech-menu-item'),
                          leading: const Icon(Icons.record_voice_over_outlined),
                          title: const Text('声音合成'),
                          subtitle: Text(
                            widget.speechActionDisabledReason ??
                                (hasText ? '将当前文字转换为语音' : '先填写要合成的文字'),
                          ),
                          enabled:
                              hasText &&
                              widget.speechActionDisabledReason == null &&
                              !widget.isStreaming &&
                              !widget.isSubmitting &&
                              widget.mediaTask?.isBusy != true &&
                              !_isRecordingVoice,
                          onTap:
                              hasText &&
                                  widget.speechActionDisabledReason == null &&
                                  !widget.isStreaming &&
                                  !widget.isSubmitting &&
                                  widget.mediaTask?.isBusy != true &&
                                  !_isRecordingVoice
                              ? () async {
                                  Navigator.pop(ctx);
                                  await _handleSynthesizeSpeech();
                                }
                              : null,
                        ),
                      ),
                    if (widget.onCloneVoice != null ||
                        widget.onOpenVoiceCloneTask != null)
                      ValueListenableBuilder<bool>(
                        valueListenable: widget.hasTextNotifier,
                        builder: (_, hasText, _) {
                          final attachedReferenceAudio =
                              _firstAudioReferenceAttachments();
                          final referenceAudio =
                              attachedReferenceAudio.isNotEmpty
                              ? attachedReferenceAudio
                              : (widget.useConfiguredVoiceCloneReferenceAudio
                                    ? const <PendingAttachment>[]
                                    : attachedReferenceAudio);
                          final hasReferenceAudio =
                              widget.useConfiguredVoiceCloneReferenceAudio ||
                              referenceAudio.isNotEmpty;
                          final subtitle =
                              widget.cloneVoiceActionDisabledReason ??
                              (!hasText
                                  ? '先填写要合成的文字'
                                  : !hasReferenceAudio
                                  ? '先通过“选择文件”附加参考音频'
                                  : referenceAudio.isNotEmpty
                                  ? '使用当前参考音频生成克隆语音'
                                  : widget.useConfiguredVoiceCloneReferenceAudio
                                  ? '使用设置中已配置的参考音频生成语音'
                                  : '使用当前参考音频生成克隆语音');
                          final enabled =
                              hasText &&
                              hasReferenceAudio &&
                              widget.cloneVoiceActionDisabledReason == null &&
                              !widget.isStreaming &&
                              !widget.isSubmitting &&
                              widget.mediaTask?.isBusy != true &&
                              !_isRecordingVoice;
                          return ListTile(
                            key: const ValueKey('clone-voice-menu-item'),
                            leading: const Icon(
                              Icons.record_voice_over_outlined,
                            ),
                            title: const Text('声音克隆'),
                            subtitle: Text(subtitle),
                            enabled: enabled,
                            onTap: enabled
                                ? () async {
                                    Navigator.pop(ctx);
                                    await _handleCloneVoice();
                                  }
                                : null,
                          );
                        },
                      ),
                    if (widget.onDesignVoice != null ||
                        widget.onOpenVoiceDesignTask != null)
                      ValueListenableBuilder<bool>(
                        valueListenable: widget.hasTextNotifier,
                        builder: (_, hasText, _) => ListTile(
                          key: const ValueKey('design-voice-menu-item'),
                          leading: const Icon(Icons.auto_awesome_outlined),
                          title: const Text('声音设计'),
                          subtitle: Text(
                            widget.designVoiceActionDisabledReason ??
                                (hasText ? '用文字描述生成声音' : '先填写声音描述'),
                          ),
                          enabled:
                              hasText &&
                              widget.designVoiceActionDisabledReason == null &&
                              !widget.isStreaming &&
                              !widget.isSubmitting &&
                              widget.mediaTask?.isBusy != true &&
                              !_isRecordingVoice,
                          onTap:
                              hasText &&
                                  widget.designVoiceActionDisabledReason ==
                                      null &&
                                  !widget.isStreaming &&
                                  !widget.isSubmitting &&
                                  widget.mediaTask?.isBusy != true &&
                                  !_isRecordingVoice
                              ? () async {
                                  Navigator.pop(ctx);
                                  await _handleDesignVoice();
                                }
                              : null,
                        ),
                      ),
                    if (widget.onGenerateMusic != null)
                      ValueListenableBuilder<bool>(
                        valueListenable: widget.hasTextNotifier,
                        builder: (_, hasText, _) => ListTile(
                          key: const ValueKey('generate-music-menu-item'),
                          leading: const Icon(Icons.music_note_outlined),
                          title: const Text('生成音乐'),
                          subtitle: Text(
                            widget.musicActionDisabledReason ??
                                (hasText ? '用提示词生成音乐' : '先填写音乐描述'),
                          ),
                          enabled:
                              hasText &&
                              widget.musicActionDisabledReason == null &&
                              !widget.isStreaming &&
                              !widget.isSubmitting &&
                              widget.mediaTask?.isBusy != true &&
                              !_isRecordingVoice,
                          onTap:
                              hasText &&
                                  widget.musicActionDisabledReason == null &&
                                  !widget.isStreaming &&
                                  !widget.isSubmitting &&
                                  widget.mediaTask?.isBusy != true &&
                                  !_isRecordingVoice
                              ? () async {
                                  Navigator.pop(ctx);
                                  await _handleGenerateMusic();
                                }
                              : null,
                        ),
                      ),
                  ],
                  if (widget.onPersonaReply != null) ...[
                    _buildAttachmentMenuSectionHeader(ctx, '个性化'),
                    ListTile(
                      leading: const Icon(Icons.face_retouching_natural),
                      title: const Text('替身回复'),
                      subtitle: const Text('以我的口吻为最近一条消息回复'),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(_runPersonaReply());
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openRealtimeVoice() async {
    try {
      await widget.onRealtimeVoice?.call();
    } catch (_) {
      if (mounted) _showActionFailure('实时语音');
    }
  }

  Future<void> _runPersonaReply() async {
    try {
      await widget.onPersonaReply?.call();
    } catch (_) {
      if (mounted) _showActionFailure('替身回复');
    }
  }

  Widget _buildAttachmentMenuSectionHeader(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      header: true,
      child: Container(
        alignment: Alignment.centerLeft,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(
          label,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// 编辑图片：选图后直接交给外部打开编辑对话框（不加入附件预览）。
  Future<void> _pickImageForEdit() async {
    final operationSessionId = widget.sessionId;
    String? directDraftPath;
    PendingAttachment? selectedAttachment;
    try {
      String? imagePath;
      for (final attachment in _pendingAttachments) {
        if (attachment.type != 'image' || attachment.path.trim().isEmpty) {
          continue;
        }
        if (kIsWeb || File(attachment.path).existsSync()) {
          imagePath = attachment.path;
          selectedAttachment = attachment;
          break;
        }
      }

      if (imagePath == null) {
        final isDesktop =
            !kIsWeb &&
            (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
        if (isDesktop) {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.image,
            allowMultiple: false,
          );
          if (!_isCurrentOperationSession(operationSessionId)) return;
          final pickedPath = result?.files.singleOrNull?.path;
          final pickedName = result?.files.singleOrNull?.name;
          if (pickedPath != null && pickedName != null) {
            final archived = await _draftArchive.archiveFile(
              sourcePath: pickedPath,
              fileName: pickedName,
              sessionId: operationSessionId,
            );
            if (!_isCurrentOperationSession(operationSessionId)) {
              await _draftArchive.deleteFile(archived.path);
              return;
            }
            imagePath = archived.path;
            directDraftPath = archived.path;
          }
        } else {
          final xFile = await _imagePicker.pickImage(
            source: ImageSource.gallery,
          );
          if (!_isCurrentOperationSession(operationSessionId)) return;
          if (xFile != null) {
            final archived = await _draftArchive.archiveFile(
              sourcePath: xFile.path,
              fileName: xFile.name,
              sessionId: operationSessionId,
            );
            if (!_isCurrentOperationSession(operationSessionId)) {
              await _draftArchive.deleteFile(archived.path);
              return;
            }
            imagePath = archived.path;
            directDraftPath = archived.path;
          }
        }
      }

      if (imagePath == null ||
          imagePath.trim().isEmpty ||
          !_isCurrentOperationSession(operationSessionId)) {
        return;
      }
      // 取消编辑同样返回 false；具体失败原因由编辑对话框或业务回调展示，
      // 这里不再追加通用错误，避免用户主动取消后被误报“编辑失败”。
      final submitted = await widget.onEditImage!(imagePath);
      if (!submitted || !_isCurrentOperationSession(operationSessionId)) return;

      if (selectedAttachment != null) {
        // 当前 Composer 中的参考图是本次编辑的输入；成功后只消费这张
        // 图片，保留其它附件，避免把编辑后的结果和原始参考图重复发送。
        _removeConsumedAttachments([selectedAttachment]);
      } else if (directDraftPath != null) {
        await _draftArchive.deleteFile(directDraftPath);
        directDraftPath = null;
      }
    } catch (e) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择图片失败: $e')));
      }
    } finally {
      // 编辑器临时使用的图片不是 Composer 附件。取消、失败或会话切换
      // 都不能把它遗留在 composer_drafts 中；成功路径已安全幂等删除。
      if (directDraftPath != null) {
        try {
          await _draftArchive.deleteFile(directDraftPath);
        } catch (_) {
          // 编辑临时文件清理失败不能覆盖编辑结果或制造未处理异步异常。
        }
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final operationSessionId = widget.sessionId;
    try {
      final xFile = await _imagePicker.pickImage(source: source);
      if (xFile == null || !_isCurrentOperationSession(operationSessionId)) {
        return;
      }
      final fileSize = await xFile.length();
      if (!_isCurrentOperationSession(operationSessionId)) return;
      await _archiveAndAddPath(
        operationSessionId: operationSessionId,
        sourcePath: xFile.path,
        fileName: xFile.name,
        fileType: 'image',
        fileSize: fileSize,
      );
    } catch (e) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择图片失败: $e')));
      }
    }
  }

  Future<void> _pickFile() async {
    final operationSessionId = widget.sessionId;
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null ||
          result.files.isEmpty ||
          !_isCurrentOperationSession(operationSessionId)) {
        return;
      }
      for (final file in result.files) {
        if (!_isCurrentOperationSession(operationSessionId)) return;
        final path = file.path;
        // 当前 Flutter 移动端 / 桌面端都提供路径；Web 仍允许用户选择，
        // 但在没有 bytes 的情况下不能把半残附件写入消息。
        if (path == null || path.trim().isEmpty) continue;
        final fileSize = await _resolveFileSize(path, file.size);
        if (!_isCurrentOperationSession(operationSessionId)) return;
        await _archiveAndAddPath(
          operationSessionId: operationSessionId,
          sourcePath: path,
          fileName: file.name,
          fileType: inferAttachmentType(file.extension ?? file.name),
          fileSize: fileSize,
        );
      }
    } catch (e) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择文件失败: $e')));
      }
    }
  }

  Future<void> _handleDroppedFiles(List<DropItem> files) async {
    final operationSessionId = widget.sessionId;
    if (widget.isSubmitting || files.isEmpty) return;
    if (mounted) setState(() => _isDraggingFiles = false);

    for (final file in files) {
      if (!_isCurrentOperationSession(operationSessionId)) return;
      // 桌面端拖入目录时不递归读取目录，避免把整个目录树意外加入消息。
      if (file is DropItemDirectory) continue;

      final path = file.path.trim();
      var fileSize = 0;
      try {
        fileSize = await file.length();
      } catch (_) {
        fileSize = 0;
      }
      if (!_isCurrentOperationSession(operationSessionId)) return;

      // macOS file promise / Web drop 可能只有 bytes，没有稳定的源路径。
      // 两条路径都直接进入 app-owned draft archive，不把临时目录作为
      // composer 的长期引用。
      final hasStablePath = path.isNotEmpty && await File(path).exists();
      if (!_isCurrentOperationSession(operationSessionId)) return;
      if (!hasStablePath) {
        if (kIsWeb) {
          _showAttachmentError('当前平台无法把拖入文件保存为本地附件，请改用文件选择器');
          continue;
        }
        try {
          final bytes = await file.readAsBytes();
          if (!_isCurrentOperationSession(operationSessionId)) return;
          if (bytes.isEmpty) {
            _showAttachmentError('拖入文件为空：${file.name}');
            continue;
          }
          fileSize = bytes.length;
          await _archiveAndAddBytes(
            operationSessionId: operationSessionId,
            bytes: bytes,
            fileName: file.name,
            fileType: inferAttachmentType(file.name),
            fileSize: fileSize,
          );
          continue;
        } catch (_) {
          if (_isCurrentOperationSession(operationSessionId)) {
            _showAttachmentError('读取拖入文件失败：${file.name}');
          }
          continue;
        }
      }

      await _archiveAndAddPath(
        operationSessionId: operationSessionId,
        sourcePath: path,
        fileName: file.name,
        fileType: inferAttachmentType(file.name),
        fileSize: fileSize,
      );
    }
  }

  Future<void> _recoverLostImagePickerData() async {
    // image_picker 官方要求 Android 在启动后调用 retrieveLostData；其它
    // 平台没有这个恢复语义，跳过可避免桌面测试 / 平台插件抛 unsupported。
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    final operationSessionId = widget.sessionId;
    try {
      final response = await _imagePicker.retrieveLostData();
      if (response.isEmpty || !_isCurrentOperationSession(operationSessionId)) {
        return;
      }
      if (response.exception != null) {
        if (_isCurrentOperationSession(operationSessionId)) {
          _showAttachmentError('恢复上次图片选择失败，请重新选择');
        }
        return;
      }
      for (final file in response.files ?? const <XFile>[]) {
        if (!_isCurrentOperationSession(operationSessionId)) return;
        final size = await file.length();
        if (!_isCurrentOperationSession(operationSessionId)) return;
        await _archiveAndAddPath(
          operationSessionId: operationSessionId,
          sourcePath: file.path,
          fileName: file.name,
          fileType: 'image',
          fileSize: size,
        );
      }
    } catch (_) {
      // retrieveLostData 是恢复补偿路径，插件不支持或没有恢复数据时不打断
      // 正常 composer；真实选择仍由用户主动触发。
    }
  }

  Future<void> _archiveAndAddPath({
    required String? operationSessionId,
    required String sourcePath,
    required String fileName,
    required String fileType,
    required int fileSize,
  }) async {
    if (!_isCurrentOperationSession(operationSessionId)) return;
    final validationError = validateAttachmentMetadata(
      fileName: fileName,
      fileType: fileType,
      fileSize: fileSize,
      currentCount: _pendingAttachments.length,
    );
    if (validationError != null) {
      _showAttachmentError(validationError);
      return;
    }

    ArchivedDraftAttachment? archived;
    try {
      archived = await _draftArchive.archiveFile(
        sourcePath: sourcePath,
        fileName: fileName,
        sessionId: operationSessionId,
      );
      if (!_isCurrentOperationSession(operationSessionId)) {
        await _draftArchive.deleteFile(archived.path);
        return;
      }
      final finalError = validateAttachmentMetadata(
        fileName: archived.fileName,
        fileType: fileType,
        fileSize: archived.fileSize,
        currentCount: _pendingAttachments.length,
      );
      if (finalError != null) {
        await _draftArchive.deleteFile(archived.path);
        if (_isCurrentOperationSession(operationSessionId)) {
          _showAttachmentError(finalError);
        }
        return;
      }
      if (!_isCurrentOperationSession(operationSessionId)) {
        await _draftArchive.deleteFile(archived.path);
        return;
      }
      _addAttachmentWithValidation(
        PendingAttachment(
          id: archived.id,
          path: archived.path,
          name: archived.fileName,
          type: fileType,
        ),
        fileSize: archived.fileSize,
      );
    } catch (error) {
      if (archived != null) await _draftArchive.deleteFile(archived.path);
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        _showAttachmentError('附件归档失败：$error');
      }
    }
  }

  Future<void> _archiveAndAddBytes({
    required String? operationSessionId,
    required List<int> bytes,
    required String fileName,
    required String fileType,
    required int fileSize,
  }) async {
    if (!_isCurrentOperationSession(operationSessionId)) return;
    final validationError = validateAttachmentMetadata(
      fileName: fileName,
      fileType: fileType,
      fileSize: fileSize,
      currentCount: _pendingAttachments.length,
    );
    if (validationError != null) {
      _showAttachmentError(validationError);
      return;
    }

    ArchivedDraftAttachment? archived;
    try {
      archived = await _draftArchive.archiveBytes(
        bytes: bytes,
        fileName: fileName,
        sessionId: operationSessionId,
      );
      if (!_isCurrentOperationSession(operationSessionId)) {
        await _draftArchive.deleteFile(archived.path);
        return;
      }
      if (!_isCurrentOperationSession(operationSessionId)) {
        await _draftArchive.deleteFile(archived.path);
        return;
      }
      _addAttachmentWithValidation(
        PendingAttachment(
          id: archived.id,
          path: archived.path,
          name: archived.fileName,
          type: fileType,
        ),
        fileSize: archived.fileSize,
      );
    } catch (error) {
      if (archived != null) await _draftArchive.deleteFile(archived.path);
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        _showAttachmentError('附件归档失败：$error');
      }
    }
  }

  Future<void> _handleGenerateVideo() async {
    final submittedText = widget.controller.text;
    final text = submittedText.trim();
    final operationSessionId = widget.sessionId;
    final callback = widget.onGenerateVideo;
    final typedCallback = widget.onOpenVideoGenerationTask;
    if (text.isEmpty ||
        (callback == null && typedCallback == null) ||
        widget.isStreaming ||
        widget.isSubmitting ||
        widget.videoActionDisabledReason != null ||
        widget.mediaTask?.isBusy == true) {
      return;
    }
    if (_isRecordingVoice) {
      _showAttachmentError('请先结束当前录音');
      return;
    }
    final configure = widget.onConfigureVideoGenerationTask;
    final config = configure != null
        ? await configure(
            text,
            List<PendingAttachment>.unmodifiable(_pendingAttachments),
          )
        : await _showVideoConfigDialog(
            text,
            _pendingAttachments
                .where((attachment) => attachment.type == 'image')
                .toList(growable: false),
          );
    if (!_isCurrentOperationSession(operationSessionId)) return;
    if (config == null) return;
    // The typed page callback receives every selected role. Older integrations
    // still get their historical single-reference contract, so a legacy
    // callback never silently changes from one image to N images.
    final consumedAttachments = typedCallback != null
        ? config.allAttachments
        : config.referenceAttachments.isEmpty
        ? const <PendingAttachment>[]
        : <PendingAttachment>[config.referenceAttachments.first];
    bool ok;
    try {
      ok = typedCallback != null
          ? await typedCallback(text, config)
          : await callback!(text, consumedAttachments, config.extra);
    } catch (_) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        _showActionFailure('视频生成');
      }
      return;
    }
    if (ok && _isCurrentOperationSession(operationSessionId)) {
      _clearSubmittedTextIfUnchanged(submittedText);
      _removeConsumedAttachments(consumedAttachments);
    }
  }

  Future<void> _handleSynthesizeSpeech() async {
    final submittedText = widget.controller.text;
    final text = submittedText.trim();
    final operationSessionId = widget.sessionId;
    final callback =
        widget.onOpenSpeechSynthesisTask ?? widget.onSynthesizeSpeech;
    if (text.isEmpty ||
        callback == null ||
        widget.isStreaming ||
        widget.isSubmitting ||
        widget.speechActionDisabledReason != null ||
        widget.mediaTask?.isBusy == true) {
      return;
    }
    if (_isRecordingVoice) {
      _showAttachmentError('请先结束当前录音');
      return;
    }
    bool ok;
    try {
      ok = await callback(text);
    } catch (_) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        _showActionFailure('声音合成');
      }
      return;
    }
    if (ok && _isCurrentOperationSession(operationSessionId)) {
      _clearSubmittedTextIfUnchanged(submittedText);
      // TTS 只消费文本；保留 composer 中未消费的附件草稿。
      _notifyDraftChanged();
    }
  }

  Future<void> _handleCloneVoice() async {
    final submittedText = widget.controller.text;
    final text = submittedText.trim();
    final operationSessionId = widget.sessionId;
    final callback = widget.onOpenVoiceCloneTask ?? widget.onCloneVoice;
    if (text.isEmpty ||
        callback == null ||
        widget.isStreaming ||
        widget.isSubmitting ||
        widget.cloneVoiceActionDisabledReason != null ||
        widget.mediaTask?.isBusy == true) {
      return;
    }
    if (_isRecordingVoice) {
      _showAttachmentError('请先结束当前录音');
      return;
    }
    final attachedReferenceAudio = _firstAudioReferenceAttachments();
    // An explicitly attached audio file wins for this action. An empty list
    // keeps the callback boundary for the persisted reference fallback.
    final referenceAudio = attachedReferenceAudio.isNotEmpty
        ? attachedReferenceAudio
        : (widget.useConfiguredVoiceCloneReferenceAudio
              ? const <PendingAttachment>[]
              : attachedReferenceAudio);
    if (!widget.useConfiguredVoiceCloneReferenceAudio &&
        referenceAudio.isEmpty) {
      return;
    }
    bool ok;
    try {
      ok = await callback(text, referenceAudio);
    } catch (_) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        _showActionFailure('声音克隆');
      }
      return;
    }
    if (!ok || !_isCurrentOperationSession(operationSessionId)) return;
    _clearSubmittedTextIfUnchanged(submittedText);
    if (referenceAudio.isEmpty) {
      // 上游消费的是已配置的参考音频，不是 Composer 草稿附件。
      _notifyDraftChanged();
    } else {
      _removeConsumedAttachments(referenceAudio);
    }
  }

  Future<void> _handleDesignVoice() async {
    final submittedText = widget.controller.text;
    final text = submittedText.trim();
    final operationSessionId = widget.sessionId;
    final callback = widget.onOpenVoiceDesignTask ?? widget.onDesignVoice;
    if (text.isEmpty ||
        callback == null ||
        widget.isStreaming ||
        widget.isSubmitting ||
        widget.designVoiceActionDisabledReason != null ||
        widget.mediaTask?.isBusy == true) {
      return;
    }
    if (_isRecordingVoice) {
      _showAttachmentError('请先结束当前录音');
      return;
    }
    bool ok;
    try {
      ok = await callback(text);
    } catch (_) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        _showActionFailure('声音设计');
      }
      return;
    }
    if (ok && _isCurrentOperationSession(operationSessionId)) {
      _clearSubmittedTextIfUnchanged(submittedText);
      // 声音设计只消费文本；保留 Composer 中其它附件草稿。
      _notifyDraftChanged();
    }
  }

  Future<void> _handleGenerateMusic() async {
    final submittedText = widget.controller.text;
    final text = submittedText.trim();
    final operationSessionId = widget.sessionId;
    final callback = widget.onGenerateMusic;
    if (text.isEmpty ||
        callback == null ||
        widget.isStreaming ||
        widget.isSubmitting ||
        widget.musicActionDisabledReason != null ||
        widget.mediaTask?.isBusy == true) {
      return;
    }
    if (_isRecordingVoice) {
      _showAttachmentError('请先结束当前录音');
      return;
    }
    bool ok;
    try {
      ok = await callback(text);
    } catch (_) {
      if (mounted && widget.sessionId == operationSessionId) {
        _showActionFailure('音乐生成');
      }
      return;
    }
    if (ok && mounted && widget.sessionId == operationSessionId) {
      _clearSubmittedTextIfUnchanged(submittedText);
      // 音乐生成只消费文本；不能借成功状态清空其它附件。
      _notifyDraftChanged();
    }
  }

  bool get _shouldShowVoiceInput {
    if (widget.showVoiceInput != null) return widget.showVoiceInput!;
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  VoiceRecorderPlatform get _voiceRecorder =>
      widget.voiceRecorder ?? const MethodChannelVoiceRecorder();

  /// 麦克风长按：为接下来的录音选择识别语言（单次生效，不改设置）。
  Future<void> _pickSpeechLanguage() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '本次录音识别语言',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              key: const ValueKey('stt-language-auto'),
              dense: true,
              leading: const Icon(Icons.auto_awesome, size: 18),
              title: const Text('自动检测', style: TextStyle(fontSize: 13)),
              onTap: () => Navigator.of(sheetContext).pop('auto'),
            ),
            ListTile(
              key: const ValueKey('stt-language-zh'),
              dense: true,
              leading: const Icon(Icons.language, size: 18),
              title: const Text('中文', style: TextStyle(fontSize: 13)),
              onTap: () => Navigator.of(sheetContext).pop('zh'),
            ),
            ListTile(
              key: const ValueKey('stt-language-en'),
              dense: true,
              leading: const Icon(Icons.translate, size: 18),
              title: const Text('English', style: TextStyle(fontSize: 13)),
              onTap: () => Navigator.of(sheetContext).pop('en'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    widget.onSpeechLanguageSelected!(selected);
    final label = switch (selected) {
      'zh' => '中文',
      'en' => 'English',
      _ => '自动检测',
    };
    _showAttachmentError('本次录音识别语言：$label（仅本次生效）');
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isVoiceBusy) return;
    if (_isRecordingVoice) {
      await _stopVoiceRecording();
    } else {
      await _startVoiceRecording();
    }
  }

  Future<void> _startVoiceRecording() async {
    final operation = ++_voiceOperation;
    final operationSessionId = widget.sessionId;
    setState(() => _isVoiceBusy = true);
    try {
      await _voiceRecorder.startRecording();
      if (!mounted ||
          operation != _voiceOperation ||
          !_isCurrentOperationSession(operationSessionId)) {
        await _voiceRecorder.cancelRecording();
        return;
      }
      setState(() => _isRecordingVoice = true);
      if (_isCurrentOperationSession(operationSessionId)) {
        _showAttachmentError('开始录音，再次点击麦克风结束并添加语音附件');
      }
    } catch (e) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        _showAttachmentError(e.toString());
      }
    } finally {
      if (mounted) setState(() => _isVoiceBusy = false);
    }
  }

  Future<void> _stopVoiceRecording() async {
    final operation = ++_voiceOperation;
    final operationSessionId = widget.sessionId;
    setState(() => _isVoiceBusy = true);
    try {
      final recording = await _voiceRecorder.stopRecording();
      if (!mounted ||
          operation != _voiceOperation ||
          !_isCurrentOperationSession(operationSessionId)) {
        return;
      }
      final fileSize =
          recording.fileSize ?? await _resolveFileSize(recording.path, 0);
      if (!mounted ||
          operation != _voiceOperation ||
          !_isCurrentOperationSession(operationSessionId)) {
        return;
      }
      setState(() => _isRecordingVoice = false);
      await _archiveAndAddPath(
        operationSessionId: operationSessionId,
        sourcePath: recording.path,
        fileName: recording.fileName,
        fileType: 'audio',
        fileSize: fileSize,
      );
      if (mounted &&
          operation == _voiceOperation &&
          _isCurrentOperationSession(operationSessionId)) {
        _showAttachmentError('语音已添加为附件');
      }
    } catch (e) {
      if (mounted && _isCurrentOperationSession(operationSessionId)) {
        _showAttachmentError(e.toString());
      }
    } finally {
      if (mounted) setState(() => _isVoiceBusy = false);
    }
  }

  Future<void> _cancelVoiceRecording({bool updateUi = true}) async {
    final operation = ++_voiceOperation;
    final operationSessionId = widget.sessionId;
    final shouldCancel = _isRecordingVoice || _isVoiceBusy;
    if (updateUi && mounted) {
      setState(() {
        _isRecordingVoice = false;
        _isVoiceBusy = false;
      });
      if (shouldCancel) _notifyDraftChanged();
    }
    if (!shouldCancel) return;
    try {
      await _voiceRecorder.cancelRecording();
    } catch (_) {
      // lifecycle/dispose 取消失败不能产生未处理异步异常，也不能阻塞页面销毁。
    }
    if (updateUi &&
        mounted &&
        operation == _voiceOperation &&
        _isCurrentOperationSession(operationSessionId)) {
      setState(() {
        _isRecordingVoice = false;
        _isVoiceBusy = false;
      });
    }
  }

  Future<int> _resolveFileSize(String path, int pickerSize) async {
    if (pickerSize > 0) return pickerSize;
    try {
      return await File(path).length();
    } catch (_) {
      return pickerSize;
    }
  }

  void _addAttachmentWithValidation(
    PendingAttachment attachment, {
    required int fileSize,
  }) {
    if (!mounted) return;
    final error = validateAttachmentMetadata(
      fileName: attachment.name,
      fileType: attachment.type,
      fileSize: fileSize,
      currentCount: _pendingAttachments.length,
    );
    if (error != null) {
      _showAttachmentError(error);
      return;
    }
    setState(
      () => _pendingAttachments.add(
        attachment.copyWith(
          fileSize: fileSize > 0 ? fileSize : attachment.fileSize,
        ),
      ),
    );
    _notifyDraftChanged();
  }

  void _showAttachmentError(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showActionFailure(String action) {
    _showAttachmentError('$action失败，已保留当前输入和附件');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compactActions = _usesCompactActionLayout(context);
    final mediaTask = widget.mediaTask;
    return DropTarget(
      enable: !widget.isSubmitting && widget.mediaTask?.isBusy != true,
      onDragEntered: (_) {
        if (mounted) setState(() => _isDraggingFiles = true);
      },
      onDragExited: (_) {
        if (mounted) setState(() => _isDraggingFiles = false);
      },
      onDragDone: (details) => unawaited(_handleDroppedFiles(details.files)),
      child: SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          color: _isDraggingFiles
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : scheme.surface,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : _fallbackComposerMaxHeight(context);
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 860,
                    maxHeight: maxHeight,
                  ),
                  child: ListView(
                    reverse: true,
                    shrinkWrap: true,
                    primary: false,
                    padding: EdgeInsets.zero,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_isDraggingFiles)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '松开以添加文件，可一次拖入多个图片、视频、音频或文档',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (mediaTask != null && mediaTask.showInComposer)
                            _buildMediaTaskStatus(mediaTask, scheme),
                          if (_pendingAttachments.isNotEmpty)
                            _buildAttachmentPreview(),
                          if (widget.modelSelector != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: widget.modelSelector!,
                            ),
                          Container(
                            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                IconButton(
                                  onPressed:
                                      widget.isSubmitting ||
                                          widget.mediaTask?.isBusy == true
                                      ? null
                                      : _showAttachmentMenu,
                                  icon: const Icon(Icons.add),
                                  tooltip: '添加附件',
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        scheme.surfaceContainerHighest,
                                    minimumSize: const Size.square(44),
                                    tapTargetSize: MaterialTapTargetSize.padded,
                                    visualDensity: VisualDensity.standard,
                                  ),
                                ),
                                Expanded(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 220,
                                    ),
                                    child: TextField(
                                      controller: widget.controller,
                                      focusNode: widget.focusNode,
                                      onTap: _requestComposerFocus,
                                      maxLines: null,
                                      decoration: const InputDecoration(
                                        hintText: '询问任何问题',
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 12,
                                        ),
                                        isDense: true,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        height: 1.45,
                                      ),
                                      // 手机的换行键只应插入新行；桌面端没有独立的
                                      // 发送键时才把 IME submit 映射为发送。
                                      textInputAction: compactActions
                                          ? TextInputAction.newline
                                          : TextInputAction.send,
                                      keyboardType: TextInputType.multiline,
                                      onSubmitted: compactActions
                                          ? null
                                          : (_) => unawaited(_handleSend()),
                                    ),
                                  ),
                                ),
                                if (_shouldShowVoiceInput &&
                                    !widget.isStreaming)
                                  IconButton(
                                    key: const ValueKey('voice-record-button'),
                                    onPressed:
                                        _isVoiceBusy ||
                                            widget.isSubmitting ||
                                            widget.mediaTask?.isBusy == true
                                        ? null
                                        : _toggleVoiceRecording,
                                    onLongPress:
                                        widget.onSpeechLanguageSelected == null
                                        ? null
                                        : _pickSpeechLanguage,
                                    icon: Icon(
                                      _isRecordingVoice
                                          ? Icons.stop_circle_outlined
                                          : Icons.mic_none_outlined,
                                      size: 20,
                                    ),
                                    tooltip: _isRecordingVoice
                                        ? '结束录音'
                                        : '语音输入',
                                    color: _isRecordingVoice
                                        ? scheme.error
                                        : null,
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size.square(44),
                                      tapTargetSize:
                                          MaterialTapTargetSize.padded,
                                      visualDensity: VisualDensity.standard,
                                    ),
                                  ),
                                if (!compactActions &&
                                    (widget.onGenerateImage != null ||
                                        widget.onGenerateImageWithAttachments !=
                                            null ||
                                        widget.onOpenImageGenerationTask !=
                                            null))
                                  ValueListenableBuilder<bool>(
                                    valueListenable: widget.hasTextNotifier,
                                    builder: (_, hasText, child) {
                                      final canGenerate =
                                          hasText &&
                                          !widget.isStreaming &&
                                          !widget.isSubmitting &&
                                          widget.mediaTask?.isBusy != true &&
                                          !_isRecordingVoice;
                                      return IconButton(
                                        key: const ValueKey(
                                          'generate-image-button',
                                        ),
                                        onPressed: canGenerate
                                            ? _handleGenerateImage
                                            : null,
                                        icon: const Icon(
                                          Icons.auto_awesome,
                                          size: 20,
                                        ),
                                        tooltip: widget.isSubmitting
                                            ? '正在处理'
                                            : '生成图片',
                                        color: canGenerate
                                            ? scheme.primary
                                            : null,
                                        style: IconButton.styleFrom(
                                          minimumSize: const Size.square(44),
                                          tapTargetSize:
                                              MaterialTapTargetSize.padded,
                                          visualDensity: VisualDensity.standard,
                                        ),
                                      );
                                    },
                                  ),
                                if (!compactActions &&
                                    widget.deepThinkNotifier != null)
                                  ValueListenableBuilder<bool>(
                                    valueListenable: widget.deepThinkNotifier!,
                                    builder: (_, deepThink, child) {
                                      return IconButton(
                                        key: const ValueKey(
                                          'deep-think-button',
                                        ),
                                        onPressed:
                                            widget.isStreaming ||
                                                widget.isSubmitting ||
                                                widget.mediaTask?.isBusy ==
                                                    true ||
                                                _isRecordingVoice
                                            ? null
                                            : () {
                                                widget
                                                        .deepThinkNotifier!
                                                        .value =
                                                    !deepThink;
                                                _notifyDraftChanged();
                                              },
                                        icon: Icon(
                                          deepThink
                                              ? Icons.psychology_alt
                                              : Icons.psychology_alt_outlined,
                                          size: 20,
                                        ),
                                        tooltip: deepThink ? '深度思考已开启' : '深度思考',
                                        color: deepThink
                                            ? scheme.primary
                                            : null,
                                        style: deepThink
                                            ? IconButton.styleFrom(
                                                backgroundColor: scheme
                                                    .primaryContainer
                                                    .withValues(alpha: 0.4),
                                                minimumSize: const Size.square(
                                                  44,
                                                ),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .padded,
                                                visualDensity:
                                                    VisualDensity.standard,
                                              )
                                            : IconButton.styleFrom(
                                                minimumSize: const Size.square(
                                                  44,
                                                ),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .padded,
                                                visualDensity:
                                                    VisualDensity.standard,
                                              ),
                                      );
                                    },
                                  ),
                                widget.isStreaming ||
                                        mediaTask?.isBusy == true ||
                                        widget.isSubmitting
                                    ? IconButton.filledTonal(
                                        key:
                                            widget.isSubmitting &&
                                                !widget.isStreaming &&
                                                mediaTask?.isBusy != true
                                            ? const ValueKey(
                                                'submit-stop-button',
                                              )
                                            : null,
                                        onPressed: _handleStop,
                                        icon: const Icon(Icons.stop, size: 20),
                                        tooltip: '停止',
                                        style: IconButton.styleFrom(
                                          minimumSize: const Size.square(44),
                                          tapTargetSize:
                                              MaterialTapTargetSize.padded,
                                          visualDensity: VisualDensity.standard,
                                        ),
                                      )
                                    : ValueListenableBuilder<bool>(
                                        valueListenable: widget.hasTextNotifier,
                                        builder: (_, hasText, child) {
                                          final canSend =
                                              !_isRecordingVoice &&
                                              !widget.isSubmitting &&
                                              (hasText ||
                                                  _pendingAttachments
                                                      .isNotEmpty);
                                          return IconButton.filled(
                                            onPressed: canSend
                                                ? _handleSend
                                                : null,
                                            icon: const Icon(
                                              Icons.arrow_upward,
                                              size: 20,
                                            ),
                                            tooltip: '发送',
                                            style: IconButton.styleFrom(
                                              disabledBackgroundColor: scheme
                                                  .surfaceContainerHighest,
                                              disabledForegroundColor:
                                                  scheme.onSurfaceVariant,
                                              minimumSize: const Size.square(
                                                44,
                                              ),
                                              tapTargetSize:
                                                  MaterialTapTargetSize.padded,
                                              visualDensity:
                                                  VisualDensity.standard,
                                            ),
                                          );
                                        },
                                      ),
                              ],
                            ),
                          ),
                          _buildFooter(context),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  double _fallbackComposerMaxHeight(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    if (!mediaSize.height.isFinite || bottomInset <= 0) {
      return double.infinity;
    }
    // ChatInputBar is a non-flex child of the chat page's message Column, so
    // its incoming height can be unbounded while the keyboard is resizing the
    // page. Keep the composer bounded to the visible window and let the
    // secondary rows scroll above the input instead of overflowing the page.
    return ((mediaSize.height - bottomInset) * 0.65).clamp(
      80.0,
      mediaSize.height,
    );
  }

  Widget _buildMediaTaskStatus(
    UniversalMediaTaskState task,
    ColorScheme scheme,
  ) {
    final isBusy = task.isBusy;
    return Padding(
      key: const ValueKey('universal-media-task-status'),
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isBusy
              ? scheme.primaryContainer.withValues(alpha: 0.45)
              : scheme.errorContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (isBusy)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        task.phase == UniversalMediaTaskPhase.cancelled
                            ? Icons.cancel_outlined
                            : Icons.error_outline,
                        size: 18,
                        color: scheme.error,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      _mediaStatusText(task),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isBusy
                            ? scheme.onPrimaryContainer
                            : scheme.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (task.canRetry && widget.onRetryMedia != null)
                    TextButton(
                      key: const ValueKey('media-task-retry-button'),
                      onPressed: _handleRetryMedia,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      child: const Text('重试'),
                    ),
                ],
              ),
              if (isBusy)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: scheme.primary,
                    backgroundColor: scheme.primary.withValues(alpha: 0.15),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 68,
        child: ListView.separated(
          key: const ValueKey('composer-pending-attachments-scroll'),
          scrollDirection: Axis.horizontal,
          itemCount: _pendingAttachments.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final att = _pendingAttachments[index];
            final icon = switch (att.type) {
              'image' => Icons.image_outlined,
              'video' => Icons.movie_outlined,
              'pdf' => Icons.picture_as_pdf_outlined,
              'audio' => Icons.graphic_eq_outlined,
              _ => Icons.insert_drive_file_outlined,
            };
            final hasImagePreview =
                att.type == 'image' &&
                widget.showImageAttachmentPreviews &&
                att.path.isNotEmpty &&
                !kIsWeb &&
                File(att.path).existsSync();
            return Container(
              key: ValueKey('pending-attachment-${att.stableId}'),
              constraints: const BoxConstraints(minWidth: 168, maxWidth: 230),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: hasImagePreview
                          ? Image.file(
                              File(att.path),
                              fit: BoxFit.cover,
                              cacheWidth: 104,
                              errorBuilder: (_, _, _) => Icon(icon, size: 22),
                            )
                          : Center(child: Icon(icon, size: 22)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          att.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          att.pastedText == null
                              ? formatAttachmentSize(att.fileSize)
                              : '${formatAttachmentSize(att.fileSize)} · ${att.pastedText!.characterCount} 字符 · ~${att.pastedText!.estimatedTokens} tokens',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (att.pastedText != null)
                    PopupMenuButton<_PastedTextAttachmentAction>(
                      tooltip: '大粘贴附件操作',
                      icon: const Icon(Icons.more_horiz, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      onSelected: (action) => unawaited(
                        _handlePastedTextAttachmentAction(index, action),
                      ),
                      itemBuilder: (menuContext) => const [
                        PopupMenuItem(
                          value: _PastedTextAttachmentAction.preview,
                          child: Text('预览'),
                        ),
                        PopupMenuItem(
                          value: _PastedTextAttachmentAction.rename,
                          child: Text('重命名'),
                        ),
                        PopupMenuItem(
                          value: _PastedTextAttachmentAction.restore,
                          child: Text('还原为文本'),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: _PastedTextAttachmentAction.delete,
                          child: Text('删除附件'),
                        ),
                      ],
                    )
                  else
                    IconButton(
                      onPressed: () => _removePendingAttachmentAt(index),
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: '移除附件',
                      visualDensity: VisualDensity.standard,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _removePendingAttachmentAt(int index) {
    if (!mounted || index < 0 || index >= _pendingAttachments.length) return;
    final removed = _pendingAttachments[index];
    setState(() => _pendingAttachments.removeAt(index));
    _notifyDraftChanged();
    // 只尝试删除这个明确被用户移除的 draft 路径；MessageAttachmentArchive
    // 路径不在 composer_drafts 根目录内，deleteFile 会安全地忽略它。
    unawaited(_draftArchive.deleteFile(removed.path).catchError((_) {}));
  }

  Future<void> _handlePastedTextAttachmentAction(
    int index,
    _PastedTextAttachmentAction action,
  ) async {
    if (!mounted || index < 0 || index >= _pendingAttachments.length) return;
    final attachment = _pendingAttachments[index];
    final pasted = attachment.pastedText;
    if (pasted == null) return;
    switch (action) {
      case _PastedTextAttachmentAction.preview:
        await _previewPastedTextAttachment(pasted);
      case _PastedTextAttachmentAction.rename:
        await _renamePastedTextAttachment(index, attachment, pasted);
      case _PastedTextAttachmentAction.restore:
        await _restorePastedTextAttachment(index, pasted);
      case _PastedTextAttachmentAction.delete:
        _removePendingAttachmentAt(index);
    }
  }

  Future<void> _previewPastedTextAttachment(
    PastedTextAttachment attachment,
  ) async {
    try {
      final text = await _pastedTextAttachmentService.readText(attachment);
      if (!mounted) return;
      // 预览只读取首段，避免一个几十万行附件把对话页的 overlay 撑爆；原始
      // 文件没有被截断或改写，用户仍可通过“还原为文本”取得完整内容。
      const previewLimit = 12000;
      final truncated = text.length > previewLimit;
      final preview = truncated ? text.substring(0, previewLimit) : text;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(attachment.displayName),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420, minWidth: 280),
            child: SingleChildScrollView(
              child: SelectableText(
                truncated ? '$preview\n\n（预览仅显示前 $previewLimit 个字符）' : preview,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) _showAttachmentError('无法读取该大粘贴附件，请删除后重新粘贴');
    }
  }

  Future<void> _renamePastedTextAttachment(
    int index,
    PendingAttachment attachment,
    PastedTextAttachment pasted,
  ) async {
    final controller = TextEditingController(text: pasted.displayName);
    String? requestedName;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('重命名附件'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(hintText: '文件名'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                requestedName = controller.text;
                Navigator.of(dialogContext).pop();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
      final normalized = requestedName?.trim();
      if (normalized == null || normalized.isEmpty || !mounted) return;
      final renamed = await _pastedTextAttachmentService.rename(
        pasted,
        normalized,
      );
      if (!mounted || index >= _pendingAttachments.length) return;
      if (_pendingAttachments[index].stableId != attachment.stableId) return;
      setState(
        () => _pendingAttachments[index] = attachment.copyWith(
          path: renamed.localPath,
          name: renamed.displayName,
          pastedText: renamed,
        ),
      );
      _notifyDraftChanged();
    } catch (_) {
      if (mounted) _showAttachmentError('附件重命名失败，已保留原文件名');
    } finally {
      controller.dispose();
    }
  }

  Future<void> _restorePastedTextAttachment(
    int index,
    PastedTextAttachment attachment,
  ) async {
    try {
      final source = await _pastedTextAttachmentService.readText(attachment);
      if (!mounted || index >= _pendingAttachments.length) return;
      final current = widget.controller.value;
      final selection = current.selection.isValid
          ? current.selection
          : TextSelection.collapsed(offset: current.text.length);
      final start = selection.start.clamp(0, current.text.length).toInt();
      final end = selection.end.clamp(start, current.text.length).toInt();
      final nextText = current.text.replaceRange(start, end, source);
      _replaceComposerText(nextText, selectionOffset: start + source.length);
      _removePendingAttachmentAt(index);
    } catch (_) {
      if (mounted) _showAttachmentError('无法还原该大粘贴附件，请先检查文件是否存在');
    }
  }

  Widget _buildFooter(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final text = value.text.trim();
        final tokenText = text.isEmpty
            ? null
            : '~${TokenEstimator.estimate(text)} tokens';
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: tokenText == null
              ? const SizedBox.shrink()
              : Text(
                  tokenText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
        );
      },
    );
  }
}

/// 视频生成弹窗的确认结果。
class VideoGenerationConfig {
  VideoGenerationConfig({
    required List<PendingAttachment> referenceAttachments,
    this.firstFrameAttachment,
    this.referenceAudioAttachment,
    this.duration,
    this.aspectRatio,
    this.resolution,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) : referenceAttachments = List<PendingAttachment>.unmodifiable(
         referenceAttachments.where(
           (attachment) =>
               attachment.stableId != firstFrameAttachment?.stableId,
         ),
       ),
       extra = Map<String, dynamic>.unmodifiable(extra);

  final List<PendingAttachment> referenceAttachments;
  final PendingAttachment? firstFrameAttachment;
  final PendingAttachment? referenceAudioAttachment;
  final int? duration;
  final String? aspectRatio;
  final String? resolution;
  final Map<String, dynamic> extra;

  /// All files consumed by this task, preserving their explicit role while
  /// allowing the legacy composer callback to remove them after success.
  List<PendingAttachment> get allAttachments {
    final result = <PendingAttachment>[];
    final seen = <String>{};
    void add(PendingAttachment? attachment) {
      if (attachment == null || !seen.add(attachment.stableId)) return;
      result.add(attachment);
    }

    for (final attachment in referenceAttachments) {
      add(attachment);
    }
    add(firstFrameAttachment);
    add(referenceAudioAttachment);
    return List<PendingAttachment>.unmodifiable(result);
  }
}

/// 视频生成 per-request 弹窗：首帧图、多参考图、参考音频 + 时长 / 比例 /
/// 分辨率均在本次任务中选择，不写入全局设置。
extension on _ChatInputBarState {
  Future<VideoGenerationConfig?> _showVideoConfigDialog(
    String prompt,
    List<PendingAttachment> imageAttachments,
  ) {
    final audioAttachments = _pendingAttachments
        .where((attachment) => attachment.type == 'audio')
        .toList(growable: false);
    final selectedReferenceIndexes = <int>{
      for (var index = 0; index < imageAttachments.length; index++) index,
    };
    var firstFrameIndex = -1;
    var referenceAudioIndex = -1;
    var durationText = '';
    var aspectRatio = '16:9';
    var resolution = '';
    return showDialog<VideoGenerationConfig>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final scheme = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            title: const Text('生成视频'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (imageAttachments.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        '参考图（可多选）',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 72,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: imageAttachments.length,
                          itemBuilder: (_, index) {
                            final attachment = imageAttachments[index];
                            final selected = selectedReferenceIndexes.contains(
                              index,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                key: ValueKey('video-ref-image-$index'),
                                onTap: () {
                                  setDialogState(() {
                                    if (selected) {
                                      selectedReferenceIndexes.remove(index);
                                    } else {
                                      if (firstFrameIndex == index) {
                                        firstFrameIndex = -1;
                                      }
                                      selectedReferenceIndexes.add(index);
                                    }
                                  });
                                },
                                child: Container(
                                  width: 64,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: selected
                                          ? scheme.primary
                                          : scheme.outlineVariant,
                                      width: selected ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(7),
                                              ),
                                          child: Image.file(
                                            File(attachment.path),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                const Icon(
                                                  Icons.image,
                                                  size: 24,
                                                ),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        selected ? '参考图' : '可选',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: selected
                                              ? scheme.primary
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (imageAttachments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: const ValueKey('video-first-frame-field'),
                        initialValue: firstFrameIndex,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '首帧图（可选）',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<int>(
                            value: -1,
                            child: Text('不指定'),
                          ),
                          for (
                            var index = 0;
                            index < imageAttachments.length;
                            index++
                          )
                            DropdownMenuItem<int>(
                              value: index,
                              child: Text(
                                imageAttachments[index].name.isEmpty
                                    ? '图片 ${index + 1}'
                                    : imageAttachments[index].name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            firstFrameIndex = value ?? -1;
                            if (firstFrameIndex >= 0) {
                              selectedReferenceIndexes.remove(firstFrameIndex);
                            }
                          });
                        },
                      ),
                    ],
                    if (audioAttachments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: const ValueKey('video-reference-audio-field'),
                        initialValue: referenceAudioIndex,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '参考音频（可选）',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<int>(
                            value: -1,
                            child: Text('不指定'),
                          ),
                          for (
                            var index = 0;
                            index < audioAttachments.length;
                            index++
                          )
                            DropdownMenuItem<int>(
                              value: index,
                              child: Text(
                                audioAttachments[index].name.isEmpty
                                    ? '音频 ${index + 1}'
                                    : audioAttachments[index].name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            referenceAudioIndex = value ?? -1;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      key: const ValueKey('video-duration-field'),
                      controller: TextEditingController(text: durationText),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '时长（秒，可选）',
                        hintText: '留空使用上游默认',
                        isDense: true,
                      ),
                      onChanged: (value) {
                        durationText = value.trim();
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('video-aspect-ratio-field'),
                      initialValue: aspectRatio,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '宽高比（可选）',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('不指定')),
                        DropdownMenuItem(value: '1:1', child: Text('1:1')),
                        DropdownMenuItem(value: '16:9', child: Text('16:9')),
                        DropdownMenuItem(value: '9:16', child: Text('9:16')),
                        DropdownMenuItem(value: '4:3', child: Text('4:3')),
                        DropdownMenuItem(value: '3:4', child: Text('3:4')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          aspectRatio = value ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('video-resolution-field'),
                      initialValue: resolution,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '分辨率（可选）',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('不指定')),
                        DropdownMenuItem(value: '480p', child: Text('480p')),
                        DropdownMenuItem(value: '720p', child: Text('720p')),
                        DropdownMenuItem(value: '1080p', child: Text('1080p')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          resolution = value ?? '';
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('confirm-video-generation'),
                onPressed: () {
                  final extra = <String, dynamic>{};
                  final seconds = int.tryParse(durationText);
                  if (seconds != null && seconds > 0) {
                    extra['seconds'] = seconds;
                  }
                  if (resolution.isNotEmpty) {
                    extra['resolution'] = resolution;
                  }
                  if (aspectRatio.isNotEmpty) {
                    extra['aspect_ratio'] = aspectRatio;
                  }
                  final selectedReferences = imageAttachments
                      .asMap()
                      .entries
                      .where(
                        (entry) => selectedReferenceIndexes.contains(entry.key),
                      )
                      .map((entry) => entry.value)
                      .toList(growable: false);
                  Navigator.of(dialogContext).pop(
                    VideoGenerationConfig(
                      referenceAttachments: selectedReferences,
                      firstFrameAttachment:
                          firstFrameIndex >= 0 &&
                              firstFrameIndex < imageAttachments.length
                          ? imageAttachments[firstFrameIndex]
                          : null,
                      referenceAudioAttachment:
                          referenceAudioIndex >= 0 &&
                              referenceAudioIndex < audioAttachments.length
                          ? audioAttachments[referenceAudioIndex]
                          : null,
                      duration: seconds,
                      aspectRatio: aspectRatio.isEmpty ? null : aspectRatio,
                      resolution: resolution.isEmpty ? null : resolution,
                      extra: extra,
                    ),
                  );
                },
                child: const Text('开始生成'),
              ),
            ],
          );
        },
      ),
    );
  }
}
