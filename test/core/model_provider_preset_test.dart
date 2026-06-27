import 'package:ai_chat_app/core/ai/model_provider_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model provider presets', () {
    test('includes major providers for key-only setup guidance', () {
      final ids = kModelProviderPresets.map((preset) => preset.id).toSet();

      expect(ids, containsAll(['openai', 'anthropic', 'gemini']));
      expect(ids, containsAll(['deepseek', 'dashscope', 'openrouter']));
      expect(ids, contains('ollama'));
    });

    test('deepseek preset uses openai-compatible chat protocol', () {
      final preset = findModelProviderPreset('deepseek');

      expect(preset, isNotNull);
      expect(preset!.protocol, 'openai_chat');
      expect(preset.openAiCompatible, true);
      expect(preset.baseUrl, 'https://api.deepseek.com/v1');
      expect(preset.docsUrl, contains('deepseek'));
    });
  });
}
