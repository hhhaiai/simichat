import 'dart:io';

import 'package:ai_chat_app/core/archive/data_export_share_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DataExportShareService', () {
    late Directory tempDir;
    late MethodChannel channel;
    final calls = <MethodCall>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('simichat_share_');
      channel = const MethodChannel('simichat/test_data_export_share');
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('invokes native share with archive metadata only', () async {
      final file = File(
        '${tempDir.path}/simichat-export-20260627-010203.tar.gz',
      );
      await file.writeAsBytes([1, 2, 3], flush: true);

      await DataExportShareService(
        channel: channel,
      ).shareExportFile(file, subject: '备份', text: '只分享到可信目标');

      expect(calls, hasLength(1));
      expect(calls.single.method, 'shareFile');
      final args = Map<String, Object?>.from(calls.single.arguments as Map);
      expect(args['fileName'], 'simichat-export-20260627-010203.tar.gz');
      expect(args['mimeType'], 'application/gzip');
      expect(args['subject'], '备份');
      expect(args['text'], '只分享到可信目标');
      expect(args['path'], file.absolute.path);
    });

    test('rejects missing files before calling native share', () async {
      final missing = File(
        '${tempDir.path}/simichat-export-20260627-010203.tar.gz',
      );

      expect(
        () => DataExportShareService(channel: channel).shareExportFile(missing),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test('rejects non SimiChat export file names', () async {
      final file = File('${tempDir.path}/notes.tar.gz');
      await file.writeAsBytes([1], flush: true);

      expect(
        () => DataExportShareService(channel: channel).shareExportFile(file),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test('recognizes SimiChat export archive names', () {
      expect(
        isSimiChatExportArchiveName('simichat-export-20260627-010203.tar.gz'),
        isTrue,
      );
      expect(isSimiChatExportArchiveName('simichat-export.zip'), isFalse);
      expect(isSimiChatExportArchiveName('other-20260627.tar.gz'), isFalse);
    });
  });
}
