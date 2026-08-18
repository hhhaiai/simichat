import 'dart:io';

import 'package:ai_chat_app/core/storage/atomic_file_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'writes bytes through a temporary part file and leaves no part file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'simichat-atomic-write-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final target = File('${directory.path}/nested/result.bin');

      final written = await writeBytesAtomically(target, const [1, 2, 3, 4]);

      expect(written.path, target.path);
      expect(await target.readAsBytes(), [1, 2, 3, 4]);
      final remaining = await target.parent
          .list()
          .where((entity) => entity.path.endsWith('.part'))
          .toList();
      expect(remaining, isEmpty);
    },
  );

  test('copies a source file atomically and enforces the byte limit', () async {
    final directory = await Directory.systemTemp.createTemp(
      'simichat-atomic-copy-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.txt')
      ..writeAsBytesSync(const [9, 8, 7]);
    final target = File('${directory.path}/copy.txt');

    final copied = await copyFileAtomically(source, target, maxBytes: 3);

    expect(copied.path, target.path);
    expect(await target.readAsBytes(), [9, 8, 7]);
    await expectLater(
      copyFileAtomically(
        source,
        File('${directory.path}/too-large.txt'),
        maxBytes: 2,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await File('${directory.path}/too-large.txt').exists(), isFalse);
  });

  test(
    'copying a missing source fails without creating a destination',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'simichat-atomic-missing-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final target = File('${directory.path}/copy.txt');

      await expectLater(
        copyFileAtomically(File('${directory.path}/missing.txt'), target),
        throwsA(isA<FileSystemException>()),
      );
      expect(await target.exists(), isFalse);
    },
  );
}
