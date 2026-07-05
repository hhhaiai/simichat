import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chat provider audio helpers', () {
    test(
      'audio-only content starts transcript as pending instead of empty',
      () {
        expect(initialAudioTranscriptText(''), isNull);
        expect(initialAudioTranscriptText('   \n  '), isNull);
        expect(initialAudioTranscriptText('  我已经手动输入转写  '), '我已经手动输入转写');
      },
    );

    test('audio-only message uses STT transcript for normal chat', () {
      final content = audioAwareMessageContent(
        content: '',
        hasAudioAttachment: true,
        audioTranscript: '你好 SimiAIChat',
      );

      expect(content, contains('以下是语音转文字结果'));
      expect(content, contains('你好 SimiAIChat'));
      expect(content, isNot(contains('base64')));
    });

    test('audio message keeps user text before STT transcript', () {
      final content = audioAwareMessageContent(
        content: '帮我总结',
        hasAudioAttachment: true,
        audioTranscript: '今天要开项目会',
      );

      expect(content, startsWith('帮我总结'));
      expect(content, contains('今天要开项目会'));
    });

    test(
      'audio-only message without transcript asks for audio endpoint config',
      () {
        expect(
          audioAwareMessageContent(content: '', hasAudioAttachment: true),
          contains('STT 音频接口配置'),
        );
        expect(
          audioAwareMessageContent(content: '', hasAudioAttachment: false),
          '',
        );
      },
    );

    test(
      'audio prompt without transcript does not silently drop STT failure',
      () {
        final content = audioAwareMessageContent(
          content: '这段语音帮我识别下',
          hasAudioAttachment: true,
        );

        expect(content, startsWith('这段语音帮我识别下'));
        expect(content, contains('STT 音频接口配置'));
      },
    );

    test('OpenAI-compatible chat channels can be reused for STT fallback', () {
      expect(canUseChannelSpeechToTextFallback('openai_chat'), true);
      expect(canUseChannelSpeechToTextFallback('openai_response'), true);
      expect(canUseChannelSpeechToTextFallback('gemini'), false);
      expect(canUseChannelSpeechToTextFallback('claude'), false);
    });
  });
}
