import 'dart:io';

import 'package:ai_chat_app/core/media/audio_transcription_service.dart';
import 'package:ai_chat_app/core/media/native_speech_to_text_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeSpeechToTextEngine', () {
    late Directory tempDir;
    late File audioFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('simichat_native_stt_');
      audioFile = File('${tempDir.path}/voice.m4a');
      await audioFile.writeAsBytes([1, 2, 3, 4, 5]);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('simichat/test_native_stt'),
            null,
          );
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('calls native transcribeFile channel and trims transcript', () async {
      const channel = MethodChannel('simichat/test_native_stt');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'transcribeFile');
            expect(call.arguments, isA<Map>());
            final args = call.arguments as Map;
            expect(args['path'], audioFile.path);
            expect(args['localeIdentifier'], 'zh-CN');
            return '  你好 SimiAIChat  ';
          });

      final engine = NativeSpeechToTextEngine(
        channel: channel,
        enforceIosPlatform: false,
      );

      final transcript = await engine.transcribe(
        AudioTranscriptionInput(
          audioPath: audioFile.path,
          fileName: 'voice.m4a',
          fileSize: await audioFile.length(),
        ),
      );

      expect(transcript, '你好 SimiAIChat');
    });

    test('maps native permission denial to safe user message', () async {
      const channel = MethodChannel('simichat/test_native_stt');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'PERMISSION_DENIED',
              message: 'raw native permission denied',
            );
          });

      final engine = NativeSpeechToTextEngine(
        channel: channel,
        enforceIosPlatform: false,
      );

      await expectLater(
        engine.transcribe(
          AudioTranscriptionInput(
            audioPath: audioFile.path,
            fileName: 'voice.m4a',
            fileSize: await audioFile.length(),
          ),
        ),
        throwsA(
          isA<AudioTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('系统语音识别权限被拒绝'),
          ),
        ),
      );
    });
  });
}
