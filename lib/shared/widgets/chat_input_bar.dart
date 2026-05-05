import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/context/token_estimator.dart';

class PendingAttachment {
  final String path;
  final String name;
  final String type; // image | pdf | document

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
  final void Function(String text, List<PendingAttachment> attachments) onSend;
  final Widget? modelSelector;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isStreaming,
    required this.hasTextNotifier,
    required this.onSend,
    this.modelSelector,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _imagePicker = ImagePicker();
  final List<PendingAttachment> _pendingAttachments = [];

  void _handleSend() {
    if (widget.isStreaming) {
      widget.onSend('', const []);
      return;
    }
    final content = widget.controller.text.trim();
    if (content.isEmpty && _pendingAttachments.isEmpty) return;
    widget.controller.clear();
    final attachments = List<PendingAttachment>.from(_pendingAttachments);
    widget.onSend(content, attachments);
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
      if (xFile == null) return;
      setState(() {
        _pendingAttachments.add(
          PendingAttachment(path: xFile.path, name: xFile.name, type: 'image'),
        );
      });
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
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final path = file.path;
      if (path == null) return;
      setState(() {
        _pendingAttachments.add(
          PendingAttachment(
            path: path,
            name: file.name,
            type: _getFileType(file.extension),
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择文件失败: $e')));
      }
    }
  }

  String _getFileType(String? extension) {
    if (extension == null) return 'document';
    final ext = extension.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      return 'image';
    }
    if (ext == 'pdf') return 'pdf';
    return 'document';
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
                                    hasText || _pendingAttachments.isNotEmpty;
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
          child: Text(
            tokenText ?? 'AI 可能会出错，请核查重要信息。',
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
