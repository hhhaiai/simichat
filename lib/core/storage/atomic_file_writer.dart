import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

const _atomicFileUuid = Uuid();

/// 将字节安全写入目标文件：先写同目录临时文件并 flush，再原子改名。
///
/// 临时文件使用唯一后缀，避免两个生成任务共用同一个 `.part` 文件。
/// 调用方只会看到已完成的目标文件；失败时会尽力清理临时文件。
Future<File> writeBytesAtomically(
  File target,
  List<int> bytes, {
  int? maxBytes,
}) async {
  if (maxBytes != null && bytes.length > maxBytes) {
    throw ArgumentError.value(bytes.length, 'bytes', '文件超过允许大小');
  }

  await target.parent.create(recursive: true);
  final part = File(
    p.join(
      target.parent.path,
      '.${p.basename(target.path)}.${_atomicFileUuid.v4()}.part',
    ),
  );
  try {
    await part.writeAsBytes(bytes, flush: true);
    return await part.rename(target.path);
  } catch (_) {
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {
      // 原始写入异常优先返回给调用方，清理失败不覆盖它。
    }
    rethrow;
  }
}

/// 将普通文件复制到目标路径，并沿用 [writeBytesAtomically] 的原子落盘语义。
Future<File> copyFileAtomically(
  File source,
  File target, {
  int? maxBytes,
}) async {
  if (!await source.exists()) {
    throw const FileSystemException('源文件不存在');
  }
  final size = await source.length();
  if (maxBytes != null && size > maxBytes) {
    throw ArgumentError.value(size, 'source', '文件超过允许大小');
  }
  return writeBytesAtomically(
    target,
    await source.readAsBytes(),
    maxBytes: maxBytes,
  );
}
