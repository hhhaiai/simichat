import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 全屏图片查看器，支持缩放/平移 + 保存到相册
class ImageViewer extends StatefulWidget {
  final ImageProvider imageProvider;
  final String? imageUrl;

  const ImageViewer({
    super.key,
    required this.imageProvider,
    this.imageUrl,
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  bool _saving = false;
  bool get _canSaveToGallery =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows);

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      late Uint8List bytes;

      if (widget.imageProvider is NetworkImage) {
        final url = (widget.imageProvider as NetworkImage).url;
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        bytes = response.bodyBytes;
      } else if (widget.imageProvider is MemoryImage) {
        bytes = (widget.imageProvider as MemoryImage).bytes;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('不支持保存此类型的图片')),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'ai_chat_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      await Gal.putImage(file.path);

      // 清理临时文件
      try {
        await file.delete();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
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
          if (_canSaveToGallery)
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
              tooltip: '保存到相册',
              onPressed: _saving ? null : _saveToGallery,
            ),
        ],
      ),
      body: PhotoView(
        imageProvider: widget.imageProvider,
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (_, _) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
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
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      pageBuilder: (_, _, _) => ImageViewer(
        imageProvider: imageProvider,
        imageUrl: imageUrl,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}
