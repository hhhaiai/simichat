import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/atomic_file_writer.dart';

/// 全屏图片查看器，支持缩放/平移 + 导出图片
class ImageViewer extends StatefulWidget {
  final ImageProvider imageProvider;
  final String? imageUrl;

  /// 编辑入口：为 null 时不显示编辑按钮。编辑通常以当前图片为参考图
  /// 进入编辑对话框，结果作为新消息插入会话（ChatGPT 风格）。
  final VoidCallback? onEditImage;

  const ImageViewer({
    super.key,
    required this.imageProvider,
    this.imageUrl,
    this.onEditImage,
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  bool _saving = false;
  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  bool get _canExportImage => !kIsWeb;
  String get _exportTooltip => _isDesktop ? '保存图片' : '保存到相册';
  String get _exportSuccessLabel => _isDesktop ? '已保存图片' : '已保存到相册';

  Future<void> _exportImage() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      late Uint8List bytes;

      // Markdown 网络图片使用 CachedNetworkImageProvider，不能通过
      // `imageProvider is NetworkImage` 判断；优先使用调用方传入的原始
      // imageUrl，确保全屏预览中的“保存到相册”不会误报“不支持此类型”。
      final suppliedUrl = widget.imageUrl?.trim();
      if (suppliedUrl != null && suppliedUrl.isNotEmpty) {
        final uri = Uri.tryParse(suppliedUrl);
        if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
          throw const FormatException('图片地址无效');
        }
        final response = await http.get(uri);
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        bytes = response.bodyBytes;
      } else if (widget.imageProvider is NetworkImage) {
        final url = (widget.imageProvider as NetworkImage).url;
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        bytes = response.bodyBytes;
      } else if (widget.imageProvider is MemoryImage) {
        bytes = (widget.imageProvider as MemoryImage).bytes;
      } else if (widget.imageProvider is FileImage) {
        final source = (widget.imageProvider as FileImage).file;
        bytes = await source.readAsBytes();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('不支持保存此类型的图片')));
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'ai_chat_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await writeBytesAtomically(file, bytes);

      try {
        if (_isDesktop) {
          final downloadsDir = await getDownloadsDirectory();
          final targetPath = await FilePicker.platform.saveFile(
            dialogTitle: '保存图片',
            fileName: fileName,
            initialDirectory: downloadsDir?.path,
            type: FileType.custom,
            allowedExtensions: const ['png'],
          );
          if (targetPath == null) return;
          await writeBytesAtomically(File(targetPath), bytes);
        } else {
          await Gal.putImage(file.path);
        }

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_exportSuccessLabel)));
        }
      } finally {
        // 取消保存对话框时也清理临时文件。
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.5),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (widget.onEditImage != null)
            IconButton(
              key: const ValueKey('viewer-edit-image'),
              icon: const Icon(Icons.auto_fix_high_outlined),
              tooltip: '编辑图片',
              onPressed: () {
                Navigator.of(context).pop();
                widget.onEditImage!();
              },
            ),
          if (_canExportImage)
            IconButton(
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download),
              tooltip: _exportTooltip,
              onPressed: _saving ? null : _exportImage,
            ),
        ],
      ),
      body: PhotoView(
        imageProvider: widget.imageProvider,
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (_, _) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        errorBuilder: (_, _, _) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, color: Colors.grey, size: 48),
              SizedBox(height: 8),
              Text('图片加载失败', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 打开全屏图片查看器
void showImageViewer(
  BuildContext context, {
  required ImageProvider imageProvider,
  String? imageUrl,
  VoidCallback? onEditImage,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      pageBuilder: (_, _, _) => ImageViewer(
        imageProvider: imageProvider,
        imageUrl: imageUrl,
        onEditImage: onEditImage,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}
