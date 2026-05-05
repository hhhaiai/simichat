import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/context/token_estimator.dart';

/// 待发送附件
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

/// 输入栏组件：附件按钮 + 文本框 + 发送/停止按钮
class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final GlobalKey inputKey;
  final bool isStreaming;
  final ValueNotifier<bool> hasTextNotifier;
  final void Function(String text, List<PendingAttachment> attachments) onSend;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.inputKey,
    required this.isStreaming,
    required this.hasTextNotifier,
    required this.onSend,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _imagePicker = ImagePicker();
  final List<PendingAttachment> _pendingAttachments = [];

  @override
  void dispose() {
    super.dispose();
  }

  void _handleSend() {
    final content = widget.controller.text.trim();
    if (content.isEmpty && _pendingAttachments.isEmpty) return;
    widget.controller.clear();
    final attachments = List<PendingAttachment>.from(_pendingAttachments);
    widget.onSend(content, attachments);
    setState(() => _pendingAttachments.clear());
  }

  void _showAttachmentMenu() {
    final isDesktop = kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isDesktop)
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('相机拍照'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
            if (!isDesktop)
              ListTile(
                leading: const Icon(Icons.photo_library),
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
        _pendingAttachments.add(PendingAttachment(
          path: xFile.path, name: xFile.name, type: 'image',
        ));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
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
        _pendingAttachments.add(PendingAttachment(
          path: path, name: file.name, type: _getFileType(file.extension),
        ));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择文件失败: $e')),
        );
      }
    }
  }

  String _getFileType(String? extension) {
    if (extension == null) return 'document';
    final ext = extension.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) return 'image';
    if (ext == 'pdf') return 'pdf';
    return 'document';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 附件预览
          if (_pendingAttachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pendingAttachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final att = _pendingAttachments[index];
                    return Chip(
                      avatar: Icon(
                        att.type == 'image'
                            ? Icons.image
                            : att.type == 'pdf'
                                ? Icons.picture_as_pdf
                                : Icons.insert_drive_file,
                        size: 18,
                      ),
                      label: Text(att.name,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() => _pendingAttachments.removeAt(index));
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ),
            ),

          // 输入框
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 附件按钮
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: IconButton(
                    onPressed: _showAttachmentMenu,
                    icon: const Icon(Icons.add_circle_outline, size: 22),
                    tooltip: '添加附件',
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                ),

                // 输入框
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: TextField(
                      key: widget.inputKey,
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: '输入消息...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 15),
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                ),

                // 发送/停止按钮
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, right: 4),
                  child: widget.isStreaming
                      ? IconButton(
                          onPressed: () => _handleSend(), // 由父级拦截停止
                          icon: const Icon(Icons.stop_circle, color: Colors.red, size: 28),
                          tooltip: '停止',
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        )
                      : ValueListenableBuilder<bool>(
                          valueListenable: widget.hasTextNotifier,
                          builder: (_, hasText, child) {
                            return IconButton(
                              onPressed: _handleSend,
                              icon: Icon(
                                Icons.arrow_upward,
                                color: hasText ? Colors.white : Colors.grey[500],
                                size: 22,
                              ),
                              tooltip: '发送',
                              style: IconButton.styleFrom(
                                backgroundColor: hasText
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey[300],
                                padding: const EdgeInsets.all(8),
                                minimumSize: const Size(36, 36),
                                shape: const CircleBorder(),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // Token 计数
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (context, value, child) {
              final text = value.text.trim();
              if (text.isEmpty) return const SizedBox.shrink();
              final tokens = TokenEstimator.estimate(text);
              return Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(
                  '~$tokens tokens',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

