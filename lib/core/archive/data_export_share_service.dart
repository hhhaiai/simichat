import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class DataExportShareService {
  const DataExportShareService({
    MethodChannel channel = const MethodChannel(_channelName),
  }) : _channel = channel;

  static const String _channelName = 'simichat/data_export_share';

  final MethodChannel _channel;

  Future<void> shareExportFile(
    File file, {
    String subject = 'SimiChat 数据导出包',
    String text = 'SimiChat 本地数据导出包。请只分享到可信目标。',
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('当前平台暂不支持系统分享');
    }

    final absoluteFile = file.absolute;
    if (!await absoluteFile.exists()) {
      throw ArgumentError.value(file.path, 'file', '导出文件不存在');
    }
    final fileName = p.basename(absoluteFile.path);
    if (!_isSimiChatExportArchiveName(fileName)) {
      throw ArgumentError.value(fileName, 'file', '只能分享 SimiChat 导出压缩包');
    }

    await _channel.invokeMethod<bool>('shareFile', {
      'path': absoluteFile.path,
      'fileName': fileName,
      'mimeType': 'application/gzip',
      'subject': subject,
      'text': text,
    });
  }
}

bool isSimiChatExportArchiveName(String fileName) =>
    _isSimiChatExportArchiveName(fileName);

bool _isSimiChatExportArchiveName(String fileName) {
  return fileName.startsWith('simichat-export-') &&
      fileName.endsWith('.tar.gz');
}
