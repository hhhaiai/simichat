import 'dart:io';

import 'package:ai_chat_app/core/media/audio_file_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioFileArchive', () {
    late Directory tempDir;
    late Directory rootDir;
    late Directory sourceDir;
    late AudioFileArchive archive;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('simichat_audio_file_');
      rootDir = Directory('${tempDir.path}/app-documents');
      sourceDir = Directory('${tempDir.path}/external-source');
      await sourceDir.create(recursive: true);
      archive = AudioFileArchive(rootDirectory: rootDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'copies audio into private archive path without source path',
      () async {
        final source = File('${sourceDir.path}/voice-original.m4a');
        await source.writeAsBytes([1, 2, 3, 4, 5]);

        final archived = await archive.archive(
          sourcePath: source.path,
          messageId: 'message:1',
          attachmentId: 'attachment:1',
          fileName: 'Voice Original.M4A',
        );

        final archivedFile = File(archived.localPath);
        expect(await archivedFile.exists(), true);
        expect(await archivedFile.readAsBytes(), [1, 2, 3, 4, 5]);
        expect(archived.fileSize, 5);
        expect(archived.localPath, contains('audio_files'));
        expect(archived.localPath, contains('message_1'));
        expect(archived.localPath, contains('attachment_1.m4a'));
        expect(archived.localPath, isNot(contains(sourceDir.path)));

        await source.delete();
        expect(await archivedFile.exists(), true);
      },
    );

    test('throws when source audio is missing', () async {
      expect(
        () => archive.archive(
          sourcePath: '${sourceDir.path}/missing.wav',
          messageId: 'message',
          attachmentId: 'attachment',
          fileName: 'missing.wav',
        ),
        throwsA(isA<FileSystemException>()),
      );
      try {
        await archive.archive(
          sourcePath: '${sourceDir.path}/missing.wav',
          messageId: 'message',
          attachmentId: 'attachment',
          fileName: 'missing.wav',
        );
      } on FileSystemException catch (e) {
        expect(e.path, isNot(contains(sourceDir.path)));
      }
    });
  });
}
