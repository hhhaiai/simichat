import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chat_app/core/media/attachment_export_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'exports a local attachment through a safe filename and atomic target write',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'simichat-attachment-export-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = File('${directory.path}/source.bin')
        ..writeAsBytesSync(const [0x10, 0x20, 0x30]);
      final target = File('${directory.path}/exports/attachment.png');
      String? selectedFileName;
      Uint8List? bytesPassedToPicker;

      final service = AttachmentExportService(
        saveFile:
            ({
              String? dialogTitle,
              String? fileName,
              String? initialDirectory,
              FileType type = FileType.any,
              List<String>? allowedExtensions,
              Uint8List? bytes,
            }) async {
              selectedFileName = fileName;
              bytesPassedToPicker = bytes;
              return target.path;
            },
      );

      final saved = await service.export(
        localPath: source.path,
        fileName: '../../private token.png',
      );

      expect(saved?.path, target.path);
      expect(selectedFileName, 'private_token.png');
      expect(selectedFileName, isNot(contains('/')));
      if (Platform.isAndroid || Platform.isIOS) {
        // 移动端由 FilePicker 直接接管 bytes 写入；测试替身只返回路径。
        expect(bytesPassedToPicker, isNotNull);
      } else {
        expect(bytesPassedToPicker, isNull);
        expect(await target.readAsBytes(), [0x10, 0x20, 0x30]);
        final partFiles = await target.parent
            .list()
            .where((entity) => entity.path.endsWith('.part'))
            .toList();
        expect(partFiles, isEmpty);
      }
    },
  );

  test(
    'cancelled save does not report a destination or write a file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'simichat-attachment-cancel-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = File('${directory.path}/source.txt')
        ..writeAsBytesSync(const [1]);
      final target = File('${directory.path}/cancelled.txt');

      final service = AttachmentExportService(
        saveFile:
            ({
              String? dialogTitle,
              String? fileName,
              String? initialDirectory,
              FileType type = FileType.any,
              List<String>? allowedExtensions,
              Uint8List? bytes,
            }) async => null,
      );

      expect(
        await service.export(localPath: source.path, fileName: 'source.txt'),
        isNull,
      );
      expect(await target.exists(), isFalse);
    },
  );

  test(
    'missing and empty sources fail before opening the save dialog',
    () async {
      var saveCalls = 0;
      final service = AttachmentExportService(
        saveFile:
            ({
              String? dialogTitle,
              String? fileName,
              String? initialDirectory,
              FileType type = FileType.any,
              List<String>? allowedExtensions,
              Uint8List? bytes,
            }) async {
              saveCalls++;
              return null;
            },
      );
      final directory = await Directory.systemTemp.createTemp(
        'simichat-attachment-invalid-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final empty = File('${directory.path}/empty.txt')..createSync();

      await expectLater(
        service.export(
          localPath: '${directory.path}/missing.txt',
          fileName: 'missing.txt',
        ),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        service.export(localPath: empty.path, fileName: 'empty.txt'),
        throwsA(isA<FileSystemException>()),
      );
      expect(saveCalls, 0);
    },
  );

  test(
    'draft attachments are session-scoped and deletion is explicit',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'simichat-draft-archive-',
      );
      final sourceRoot = await Directory.systemTemp.createTemp(
        'simichat-draft-source-',
      );
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => sourceRoot.delete(recursive: true));
      final sourceA = File('${sourceRoot.path}/photo.png')
        ..writeAsBytesSync(const [1, 2, 3]);
      final sourceB = File('${sourceRoot.path}/voice.m4a')
        ..writeAsBytesSync(const [4, 5, 6]);
      final archive = AttachmentDraftArchive(rootDirectory: root);

      final draftA = await archive.archiveFile(
        sourcePath: sourceA.path,
        fileName: '../photo.png',
        sessionId: 'session-A',
      );
      final draftB = await archive.archiveFile(
        sourcePath: sourceB.path,
        fileName: 'voice.m4a',
        sessionId: 'session-B',
      );

      expect(draftA.path, contains('composer_drafts'));
      expect(draftA.path, contains('session-A'));
      expect(draftA.path, isNot(draftB.path));
      expect(await File(draftA.path).readAsBytes(), [1, 2, 3]);
      expect(await File(draftB.path).readAsBytes(), [4, 5, 6]);

      await archive.deleteFile(draftA.path);
      expect(await File(draftA.path).exists(), isFalse);
      expect(await File(draftB.path).exists(), isTrue);

      final outside = File('${sourceRoot.path}/outside.txt')
        ..writeAsStringSync('keep');
      await archive.deleteFile(outside.path);
      expect(await outside.exists(), isTrue);
    },
  );

  test(
    'message-owned archive is independent from composer draft source',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'simichat-message-archive-',
      );
      final sourceRoot = await Directory.systemTemp.createTemp(
        'simichat-message-source-',
      );
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => sourceRoot.delete(recursive: true));
      final source = File('${sourceRoot.path}/report.pdf')
        ..writeAsBytesSync(const [7, 8, 9]);

      final archived = await MessageAttachmentArchive(rootDirectory: root)
          .archive(
            sourcePath: source.path,
            messageId: 'message-1',
            attachmentId: 'attachment-1',
            fileName: 'report.pdf',
          );

      expect(
        archived.localPath,
        contains('${Platform.pathSeparator}attachments'),
      );
      expect(archived.localPath, isNot(source.path));
      expect(await File(archived.localPath).readAsBytes(), [7, 8, 9]);
      expect(await source.exists(), isTrue);
    },
  );
}
