import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/attachments/attachment_policy.dart';
import '../../core/context/token_estimator.dart';
import '../../core/media/voice_recorder.dart';

class PendingAttachment {
  final String path;
  final String name;
  final String type; // image | pdf | audio | document

  const PendingAttachment({
    required this.path,
    required this.name,
    required this.type,
  });
}

/// ChatGPT-style bottom composer.
class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isStreaming;
  final bool isSubmitting;
  final ValueNotifier<bool> hasTextNotifier;
  final Future<bool> Function(String text, List<PendingAttachment> attachments)
  onSend;

  /// 图片生成回调：入参为输入框文本，返回是否成功（成功后清空输入框）。
  /// 为 null 时不显示“生成图片”按钮。
  final Future<bool> Function(String text)? onGenerateImage;

  /// 编辑图片回调：选图后由外部打开编辑对话框。为 null 时不显示入口。
  final Future<bool> Function(String imagePath)? onEditImage;

  /// 深度思考开关状态（外部持有 ValueNotifier）。为 null 时不显示开关按钮。
  final ValueNotifier<bool>? deepThinkNotifier;

  /// 替身回复回调：为最近一条用户消息以镜像人格生成回复。为 null 时不显示入口。
  final Future<bool> Function()? onPersonaReply;
  final Widget? modelSelector;
  final VoiceRecorderPlatform? voiceRecorder;
  final bool? showVoiceInput;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isStreaming,
    this.isSubmitting = false,
    required this.hasTextNotifier,
    required this.onSend,
    this.onGenerateImage,
    this.onEditImage,
    this.deepThinkNotifier,
    this.onPersonaReply,
    this.modelSelector,
    this.voiceRecorder,
    this.showVoiceInput,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _imagePicker = ImagePicker();
  final List<PendingAttachment> _pendingAttachments = [];
  bool _isRecordingVoice = false;
  bool _isVoiceBusy = false;

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
    if (widget.isStreaming) {
      await widget.onSend('', const []);
      return;
    }
    if (widget.isSubmitting) return;
    if (_isRecordingVoice) {
      _showAttachmentError('请先结束当前录音');
      return;
    }
    final content = widget.controller.text.trim();
    if (content.isEmpty && _pendingAttachments.isEmpty) return;
    final attachments = List<PendingAttachment>.from(_pendingAttachments);
    final sent = await widget.onSend(content, attachments);
    if (!sent || !mounted) return;
    setState(() => _pendingAttachments.clear());
  }

  Future<void> _handleGenerateImage() async {
    final text = widget.controller.text.trim();
    if (text.isEmpty || widget.onGenerateImage == null || widget.isSubmitting) {
      return;
    }
    if (_isRecordingVoice) {
      _showAttachmentError('请先结束当前录音');
      return;
    }
    final ok = await widget.onGenerateImage!(text);
    if (ok && mounted) {
      widget.controller.clear();
      widget.hasTextNotifier.value = false;
    }
  }

  bool _usesCompactActionLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 380;
  }

  void _showAttachmentMenu() {
    final isDesktop =
        kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final compactActions = _usesCompactActionLayout(context);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        // 小屏下会额外收纳画图 / 深度思考；允许滚动，避免动作增多后
        // BottomSheet 在 568px 等短屏上溢出。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFile();
                },
              ),
              if (widget.onEditImage != null)
                ListTile(
                  leading: const Icon(Icons.photo_filter_outlined),
                  title: const Text('编辑图片'),
                  subtitle: const Text('选择参考图后用提示词重新生成'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImageForEdit();
                  },
                ),
              if (compactActions && widget.onGenerateImage != null)
                ValueListenableBuilder<bool>(
                  valueListenable: widget.hasTextNotifier,
                  builder: (_, hasText, _) => ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('生成图片'),
                    subtitle: Text(hasText ? '使用当前输入生成图片' : '先在输入框填写图片描述'),
                    enabled:
                        hasText &&
                        !widget.isStreaming &&
                        !widget.isSubmitting &&
                        !_isRecordingVoice,
                    onTap:
                        hasText &&
                            !widget.isStreaming &&
                            !widget.isSubmitting &&
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
                    subtitle: Text(deepThink ? '已开启' : '使用当前渠道的 reasoner 模型'),
                    value: deepThink,
                    onChanged:
                        widget.isStreaming ||
                            widget.isSubmitting ||
                            _isRecordingVoice
                        ? null
                        : (value) {
                            widget.deepThinkNotifier!.value = value;
                            Navigator.pop(ctx);
                          },
                  ),
                ),
              if (widget.onPersonaReply != null)
                ListTile(
                  leading: const Icon(Icons.face_retouching_natural),
                  title: const Text('替身回复'),
                  subtitle: const Text('以我的口吻为最近一条消息回复'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onPersonaReply!();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 编辑图片：选图后直接交给外部打开编辑对话框（不加入附件预览）。
  Future<void> _pickImageForEdit() async {
    try {
      final xFile = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (xFile == null || !mounted) return;
      // 取消编辑同样返回 false；具体失败原因由编辑对话框或业务回调展示，
      // 这里不再追加通用错误，避免用户主动取消后被误报“编辑失败”。
      await widget.onEditImage!(xFile.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择图片失败: $e')));
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xFile = await _imagePicker.pickImage(source: source);
      if (xFile == null || !mounted) return;
      final fileSize = await xFile.length();
      _addAttachmentWithValidation(
        PendingAttachment(path: xFile.path, name: xFile.name, type: 'image'),
        fileSize: fileSize,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择图片失败: $e')));
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.first;
      final path = file.path;
      if (path == null) return;
      final fileSize = await _resolveFileSize(path, file.size);
      _addAttachmentWithValidation(
        PendingAttachment(
          path: path,
          name: file.name,
          type: inferAttachmentType(file.extension ?? file.name),
        ),
        fileSize: fileSize,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择文件失败: $e')));
      }
    }
  }

  bool get _shouldShowVoiceInput {
    if (widget.showVoiceInput != null) return widget.showVoiceInput!;
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  VoiceRecorderPlatform get _voiceRecorder =>
      widget.voiceRecorder ?? const MethodChannelVoiceRecorder();

  Future<void> _toggleVoiceRecording() async {
    if (_isVoiceBusy) return;
    if (_isRecordingVoice) {
      await _stopVoiceRecording();
    } else {
      await _startVoiceRecording();
    }
  }

  Future<void> _startVoiceRecording() async {
    setState(() => _isVoiceBusy = true);
    try {
      await _voiceRecorder.startRecording();
      if (!mounted) return;
      setState(() => _isRecordingVoice = true);
      _showAttachmentError('开始录音，再次点击麦克风结束并添加语音附件');
    } catch (e) {
      if (mounted) _showAttachmentError(e.toString());
    } finally {
      if (mounted) setState(() => _isVoiceBusy = false);
    }
  }

  Future<void> _stopVoiceRecording() async {
    setState(() => _isVoiceBusy = true);
    try {
      final recording = await _voiceRecorder.stopRecording();
      if (!mounted) return;
      final fileSize =
          recording.fileSize ?? await _resolveFileSize(recording.path, 0);
      setState(() => _isRecordingVoice = false);
      _addAttachmentWithValidation(
        PendingAttachment(
          path: recording.path,
          name: recording.fileName,
          type: 'audio',
        ),
        fileSize: fileSize,
      );
      if (mounted) _showAttachmentError('语音已添加为附件');
    } catch (e) {
      if (mounted) _showAttachmentError(e.toString());
    } finally {
      if (mounted) setState(() => _isVoiceBusy = false);
    }
  }

  Future<int> _resolveFileSize(String path, int pickerSize) async {
    if (pickerSize > 0) return pickerSize;
    try {
      return File(path).length();
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
    setState(() => _pendingAttachments.add(attachment));
  }

  void _showAttachmentError(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compactActions = _usesCompactActionLayout(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        color: scheme.surface,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_pendingAttachments.isNotEmpty) _buildAttachmentPreview(),
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
                      color: scheme.outlineVariant.withValues(alpha: 0.7),
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
                        onPressed: widget.isSubmitting
                            ? null
                            : _showAttachmentMenu,
                        icon: const Icon(Icons.add),
                        tooltip: '添加附件',
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.surfaceContainerHighest,
                          minimumSize: const Size(38, 38),
                        ),
                      ),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
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
                            style: const TextStyle(fontSize: 15, height: 1.45),
                            textInputAction: TextInputAction.newline,
                            keyboardType: TextInputType.multiline,
                            onSubmitted: (_) => _handleSend(),
                          ),
                        ),
                      ),
                      if (_shouldShowVoiceInput && !widget.isStreaming)
                        IconButton(
                          key: const ValueKey('voice-record-button'),
                          onPressed: _isVoiceBusy || widget.isSubmitting
                              ? null
                              : _toggleVoiceRecording,
                          icon: Icon(
                            _isRecordingVoice
                                ? Icons.stop_circle_outlined
                                : Icons.mic_none_outlined,
                            size: 20,
                          ),
                          tooltip: _isRecordingVoice ? '结束录音' : '语音输入',
                          color: _isRecordingVoice ? scheme.error : null,
                        ),
                      if (!compactActions && widget.onGenerateImage != null)
                        ValueListenableBuilder<bool>(
                          valueListenable: widget.hasTextNotifier,
                          builder: (_, hasText, child) {
                            final canGenerate =
                                hasText &&
                                !widget.isStreaming &&
                                !widget.isSubmitting &&
                                !_isRecordingVoice;
                            return IconButton(
                              key: const ValueKey('generate-image-button'),
                              onPressed: canGenerate
                                  ? _handleGenerateImage
                                  : null,
                              icon: const Icon(Icons.auto_awesome, size: 20),
                              tooltip: widget.isSubmitting ? '正在处理' : '生成图片',
                              color: canGenerate ? scheme.primary : null,
                            );
                          },
                        ),
                      if (!compactActions && widget.deepThinkNotifier != null)
                        ValueListenableBuilder<bool>(
                          valueListenable: widget.deepThinkNotifier!,
                          builder: (_, deepThink, child) {
                            return IconButton(
                              key: const ValueKey('deep-think-button'),
                              onPressed:
                                  widget.isStreaming ||
                                      widget.isSubmitting ||
                                      _isRecordingVoice
                                  ? null
                                  : () {
                                      widget.deepThinkNotifier!.value =
                                          !deepThink;
                                    },
                              icon: Icon(
                                deepThink
                                    ? Icons.psychology_alt
                                    : Icons.psychology_alt_outlined,
                                size: 20,
                              ),
                              tooltip: deepThink ? '深度思考已开启' : '深度思考',
                              color: deepThink ? scheme.primary : null,
                              style: deepThink
                                  ? IconButton.styleFrom(
                                      backgroundColor: scheme.primaryContainer
                                          .withValues(alpha: 0.4),
                                    )
                                  : null,
                            );
                          },
                        ),
                      widget.isStreaming
                          ? IconButton.filledTonal(
                              onPressed: _handleSend,
                              icon: const Icon(Icons.stop, size: 20),
                              tooltip: '停止',
                            )
                          : widget.isSubmitting
                          ? IconButton.filledTonal(
                              key: const ValueKey('submit-progress-button'),
                              onPressed: null,
                              icon: const Icon(Icons.hourglass_top, size: 20),
                              tooltip: '正在处理',
                            )
                          : ValueListenableBuilder<bool>(
                              valueListenable: widget.hasTextNotifier,
                              builder: (_, hasText, child) {
                                final canSend =
                                    !_isRecordingVoice &&
                                    !widget.isSubmitting &&
                                    (hasText || _pendingAttachments.isNotEmpty);
                                return IconButton.filled(
                                  onPressed: canSend ? _handleSend : null,
                                  icon: const Icon(
                                    Icons.arrow_upward,
                                    size: 20,
                                  ),
                                  tooltip: '发送',
                                  style: IconButton.styleFrom(
                                    disabledBackgroundColor:
                                        scheme.surfaceContainerHighest,
                                    disabledForegroundColor:
                                        scheme.onSurfaceVariant,
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
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pendingAttachments.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final att = _pendingAttachments[index];
            return InputChip(
              avatar: Icon(
                att.type == 'image'
                    ? Icons.image_outlined
                    : att.type == 'pdf'
                    ? Icons.picture_as_pdf_outlined
                    : att.type == 'audio'
                    ? Icons.graphic_eq_outlined
                    : Icons.insert_drive_file_outlined,
                size: 18,
              ),
              label: Text(
                att.name,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
              onDeleted: () =>
                  setState(() => _pendingAttachments.removeAt(index)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            );
          },
        ),
      ),
    );
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
