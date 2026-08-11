import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'openai_text_to_speech_engine.dart';
import 'text_to_speech_service.dart';

typedef ReferenceAudioRootResolver = Future<Directory> Function();

/// 将声音克隆参考 WAV 归档到 App 私有持久目录。
///
/// 文件选择器在部分平台会返回系统缓存路径，不能直接持久化。
/// 这里先做元数据校验，再以 `.part -> rename` 完成原子落盘。
class ReferenceAudioStore {
  const ReferenceAudioStore({
    this.rootResolver = getApplicationSupportDirectory,
    this.now = DateTime.now,
  });

  final ReferenceAudioRootResolver rootResolver;
  final DateTime Function() now;

  Future<String> archiveWav(String sourcePath) async {
    final normalizedSourcePath = sourcePath.trim();
    if (normalizedSourcePath.isEmpty) {
      throw const TextToSpeechException('声音克隆需要选择参考音频');
    }
    if (p.extension(normalizedSourcePath).toLowerCase() != '.wav') {
      throw const TextToSpeechException('声音克隆参考音频仅支持 WAV');
    }

    final source = File(normalizedSourcePath);
    if (!await source.exists()) {
      throw const TextToSpeechException('参考音频文件不存在，请重新选择');
    }
    final sourceLength = await source.length();
    if (sourceLength <= 0) {
      throw const TextToSpeechException('参考音频文件为空');
    }
    if (sourceLength > kTextToSpeechMaxReferenceAudioBytes) {
      throw const TextToSpeechException('参考音频超过 10 MB，请压缩后重试');
    }

    final root = await _managedRoot();
    final sourceAbsolute = p.normalize(source.absolute.path);
    if (p.isWithin(p.normalize(root.absolute.path), sourceAbsolute)) {
      return sourceAbsolute;
    }

    final originalName = p.basename(sourceAbsolute);
    Directory? stageDirectory;
    try {
      stageDirectory = await _createUniqueStageDirectory(root);
      final target = File(p.join(stageDirectory.path, originalName));
      final part = File('${target.path}.part');
      await source.copy(part.path);
      if (await part.length() != sourceLength) {
        throw const TextToSpeechException('参考音频复制不完整，请重试');
      }
      await part.rename(target.path);
      return p.normalize(target.absolute.path);
    } on TextToSpeechException {
      if (stageDirectory != null && await stageDirectory.exists()) {
        await stageDirectory.delete(recursive: true);
      }
      rethrow;
    } catch (_) {
      if (stageDirectory != null && await stageDirectory.exists()) {
        await stageDirectory.delete(recursive: true);
      }
      throw const TextToSpeechException('参考音频保存失败，请重新选择');
    }
  }

  Future<void> deleteManaged(String? filePath) async {
    final normalizedPath = filePath?.trim();
    if (normalizedPath == null || normalizedPath.isEmpty) return;

    final root = await _managedRoot();
    final rootPath = p.normalize(root.absolute.path);
    final targetPath = p.normalize(File(normalizedPath).absolute.path);
    if (!p.isWithin(rootPath, targetPath)) return;

    final target = File(targetPath);
    if (await target.exists()) await target.delete();

    final parent = target.parent;
    final parentPath = p.normalize(parent.absolute.path);
    if (parentPath != rootPath &&
        p.isWithin(rootPath, parentPath) &&
        await parent.exists()) {
      await parent.delete(recursive: true);
    }
  }

  Future<Directory> _managedRoot() async {
    final support = await rootResolver();
    final root = Directory(p.join(support.path, 'tts', 'reference_audio'));
    await root.create(recursive: true);
    return root;
  }

  Future<Directory> _createUniqueStageDirectory(Directory root) async {
    final prefix = 'reference-${now().microsecondsSinceEpoch}';
    // createTemp 由系统原子地选择唯一目录，避免用户快速连续保存时
    // 两个任务同时写入同一 `.part` 文件。
    return root.createTemp('$prefix-');
  }
}
