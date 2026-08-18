import 'dart:io';

import 'package:flutter/material.dart';

/// 图片编辑对话框：预览参考图 + 输入编辑提示词，确认后回调编辑动作。
///
/// 由 [showImageEditDialog] 弹出；返回 true 表示编辑请求已提交（调用方负责
/// 调 `/v1/images/edits`）。[onEdit] 返回 null 表示成功，否则返回
/// 需要展示在对话框内的具体错误，避免与外层 SnackBar 重复提示。
Future<bool> showImageEditDialog(
  BuildContext context, {
  required String imagePath,
  required Future<String?> Function(String prompt, String size) onEdit,
  List<String> sizeOptions = const <String>['1024x1024'],
  String initialSize = '1024x1024',
}) async {
  final submitted = await showDialog<bool>(
    context: context,
    builder: (ctx) => _ImageEditDialog(
      imagePath: imagePath,
      onEdit: onEdit,
      sizeOptions: sizeOptions,
      initialSize: initialSize,
    ),
  );
  return submitted ?? false;
}

class _ImageEditDialog extends StatefulWidget {
  const _ImageEditDialog({
    required this.imagePath,
    required this.onEdit,
    required this.sizeOptions,
    required this.initialSize,
  });

  final String imagePath;
  final Future<String?> Function(String prompt, String size) onEdit;
  final List<String> sizeOptions;
  final String initialSize;

  @override
  State<_ImageEditDialog> createState() => _ImageEditDialogState();
}

class _ImageEditDialogState extends State<_ImageEditDialog> {
  final _promptController = TextEditingController();
  late String _size = widget.initialSize;
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _errorText = '请输入编辑提示词');
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    String? error;
    try {
      error = await widget.onEdit(prompt, _size);
    } catch (_) {
      // 业务回调约定返回可读错误，但 DAO / 配置读取等意外异常仍需在
      // 对话框内收口，恢复按钮并保留提示词，不能让用户卡在“编辑中”。
      error = '图片编辑失败，请稍后重试';
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _errorText = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('编辑图片'),
      // AlertDialog 会先做固有宽度测量；预览图的 double.infinity 必须
      // 有一个有限宽度父级，否则会触发 `input.isFinite` 布局异常。
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(widget.imagePath),
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 180,
                    color: scheme.surfaceContainerHighest,
                    child: const Center(child: Text('图片无法预览')),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _promptController,
                enabled: !_busy,
                maxLines: 2,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '编辑提示词',
                  hintText: '如：改成赛博朋克夜景',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _size,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '输出尺寸'),
                items: [
                  for (final size in widget.sizeOptions)
                    DropdownMenuItem(value: size, child: Text(size)),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _size = value);
                        }
                      },
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(_errorText!, style: TextStyle(color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? '编辑中…' : '确认编辑'),
        ),
      ],
    );
  }
}
