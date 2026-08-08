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

    test('domestic openai-compatible presets include qianfan and xfyun', () {
      final qianfan = findModelProviderPreset('qianfan');
      final xfyun = findModelProviderPreset('xfyun-spark');

      expect(qianfan, isNotNull);
      expect(qianfan!.protocol, 'openai_chat');
      expect(qianfan.openAiCompatible, true);
      expect(qianfan.baseUrl, 'https://qianfan.baidubce.com/v2');
      expect(qianfan.docsUrl, contains('baidu'));

      expect(xfyun, isNotNull);
      expect(xfyun!.protocol, 'openai_chat');
      expect(xfyun.openAiCompatible, true);
      expect(xfyun.baseUrl, 'https://spark-api-open.xf-yun.com/v1');
      expect(xfyun.docsUrl, contains('xfyun'));
    });

    test(
      'free and low-cost openai-compatible presets include moonshot and siliconflow',
      () {
        final moonshot = findModelProviderPreset('moonshot');
        final siliconFlow = findModelProviderPreset('siliconflow');

        expect(moonshot, isNotNull);
        expect(moonshot!.protocol, 'openai_chat');
        expect(moonshot.openAiCompatible, true);
        expect(moonshot.baseUrl, 'https://api.moonshot.ai/v1');
        expect(moonshot.docsUrl, 'https://platform.kimi.ai/docs/api/overview');

        expect(siliconFlow, isNotNull);
        expect(siliconFlow!.protocol, 'openai_chat');
        expect(siliconFlow.openAiCompatible, true);
        expect(siliconFlow.baseUrl, 'https://api.siliconflow.cn/v1');
        expect(siliconFlow.docsUrl, contains('siliconflow'));
      },
    );

    test(
      'domestic openai-compatible presets include volcengine ark and hunyuan',
      () {
        final volcengineArk = findModelProviderPreset('volcengine-ark');
        final hunyuan = findModelProviderPreset('tencent-hunyuan');

        expect(volcengineArk, isNotNull);
        expect(volcengineArk!.protocol, 'openai_chat');
        expect(volcengineArk.openAiCompatible, true);
        expect(
          volcengineArk.baseUrl,
          'https://ark.cn-beijing.volces.com/api/v3',
        );
        expect(volcengineArk.docsUrl, contains('volcengine'));

        expect(hunyuan, isNotNull);
        expect(hunyuan!.protocol, 'openai_chat');
        expect(hunyuan.openAiCompatible, true);
        expect(hunyuan.baseUrl, 'https://api.hunyuan.cloud.tencent.com/v1');
        expect(hunyuan.docsUrl, contains('tencent'));
      },
    );

    test(
      'openai-compatible presets expose recommended starter model names',
      () {
        final openAi = findModelProviderPreset('openai');
        final moonshot = findModelProviderPreset('moonshot');
        final siliconFlow = findModelProviderPreset('siliconflow');

        expect(openAi!.recommendedModels, contains('gpt-4o-mini'));
        expect(moonshot!.recommendedModels, contains('kimi-k2-0711-preview'));
        expect(siliconFlow!.recommendedModels, contains('Qwen/Qwen3-8B'));
      },
    );

    test(
      'global openai-compatible presets include groq mistral together and fireworks',
      () {
        final groq = findModelProviderPreset('groq');
        final mistral = findModelProviderPreset('mistral');
        final together = findModelProviderPreset('together');
        final fireworks = findModelProviderPreset('fireworks');

        expect(groq, isNotNull);
        expect(groq!.protocol, 'openai_chat');
        expect(groq.openAiCompatible, true);
        expect(groq.baseUrl, 'https://api.groq.com/openai/v1');
        expect(groq.recommendedModels, contains('llama-3.1-8b-instant'));

        expect(mistral, isNotNull);
        expect(mistral!.protocol, 'openai_chat');
        expect(mistral.openAiCompatible, true);
        expect(mistral.baseUrl, 'https://api.mistral.ai/v1');
        expect(mistral.recommendedModels, contains('mistral-small-latest'));

        expect(together, isNotNull);
        expect(together!.protocol, 'openai_chat');
        expect(together.openAiCompatible, true);
        expect(together.baseUrl, 'https://api.together.ai/v1');
        expect(together.recommendedModels, contains('MiniMaxAI/MiniMax-M3'));

        expect(fireworks, isNotNull);
        expect(fireworks!.protocol, 'openai_chat');
        expect(fireworks.openAiCompatible, true);
        expect(fireworks.baseUrl, 'https://api.fireworks.ai/inference/v1');
        expect(
          fireworks.recommendedModels,
          contains('accounts/fireworks/models/llama-v3p1-8b-instruct'),
        );
      },
    );

    test(
      'global openai-compatible presets include xai perplexity and deepinfra',
      () {
        final xai = findModelProviderPreset('xai');
        final perplexity = findModelProviderPreset('perplexity');
        final deepInfra = findModelProviderPreset('deepinfra');

        expect(xai, isNotNull);
        expect(xai!.protocol, 'openai_chat');
        expect(xai.openAiCompatible, true);
        expect(xai.baseUrl, 'https://api.x.ai/v1');
        expect(xai.recommendedModels, contains('grok-4.3'));

        expect(perplexity, isNotNull);
        expect(perplexity!.protocol, 'openai_chat');
        expect(perplexity.openAiCompatible, true);
        expect(perplexity.baseUrl, 'https://api.perplexity.ai');
        expect(perplexity.recommendedModels, contains('sonar-pro'));

        expect(deepInfra, isNotNull);
        expect(deepInfra!.protocol, 'openai_chat');
        expect(deepInfra.openAiCompatible, true);
        expect(deepInfra.baseUrl, 'https://api.deepinfra.com/v1/openai');
        expect(
          deepInfra.recommendedModels,
          contains('deepseek-ai/DeepSeek-V3'),
        );
      },
    );

    test(
      'dwchainless relay preset is openai-compatible and has sign-up url',
      () {
        final preset = findModelProviderPreset('dwchainless');

        expect(preset, isNotNull);
        expect(preset!.id, 'dwchainless');
        expect(preset.protocol, 'openai_chat');
        expect(preset.openAiCompatible, true);
        expect(preset.baseUrl, 'https://api.dwchainless.com/v1');
        expect(preset.docsUrl, 'https://api.dwchainless.com/');
        expect(preset.signUpUrl, 'https://api.dwchainless.com/sign-up');
        expect(preset.recommendedModels, isNotEmpty);
      },
    );

    test('dwchainless preset matches by display name and short alias', () {
      expect(findModelProviderPreset('DW Chainless 中转站'), isNotNull);
      expect(findModelProviderPreset('dw-chainless'), isNull);
      // 预设查找忽略大小写与首尾空格。
      expect(findModelProviderPreset('  DwChainless  '), isNotNull);
    });

    test('ollama is a no-key local preset with starter models', () {
      final ollama = findModelProviderPreset('ollama');

      expect(ollama, isNotNull);
      expect(modelProtocolRequiresApiKey(ollama!.protocol), isFalse);
      expect(ollama.baseUrl, 'http://localhost:11434');
      expect(ollama.recommendedModels, contains('gemma4'));
      expect(ollama.recommendedModels, contains('qwen3:4b'));
    });

    test('cloud protocols still require an API key', () {
      expect(modelProtocolRequiresApiKey('openai_chat'), isTrue);
      expect(modelProtocolRequiresApiKey('claude'), isTrue);
      expect(modelProtocolRequiresApiKey('gemini'), isTrue);
    });
  });
}
