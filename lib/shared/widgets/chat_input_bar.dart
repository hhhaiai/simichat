import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  final ValueNotifier<bool> hasTextNotifier;
  final Future<bool> Function(String text, List<PendingAttachment> attachments)
  onSend;
  final Widget? modelSelector;
  final VoiceRecorderPlatform? voiceRecorder;
  final bool? showVoiceInput;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isStreaming,
    required this.hasTextNotifier,
    required this.onSend,
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

  Future<void> _handleSend() async {
    if (widget.isStreaming) {
      await widget.onSend('', const []);
      return;
    }
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

  void _showAttachmentMenu() {
    final isDesktop =
        kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
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
          ],
        ),
      ),
    );
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
                        onPressed: _showAttachmentMenu,
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
                          onPressed: _isVoiceBusy
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
                      widget.isStreaming
                          ? IconButton.filledTonal(
                              onPressed: _handleSend,
                              icon: const Icon(Icons.stop, size: 20),
                              tooltip: '停止',
                            )
                          : ValueListenableBuilder<bool>(
                              valueListenable: widget.hasTextNotifier,
                              builder: (_, hasText, child) {
                                final canSend =
                                    !_isRecordingVoice &&
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
