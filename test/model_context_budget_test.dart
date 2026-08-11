import 'package:ai_chat_app/core/context/model_context_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model context budget', () {
    test(
      'uses larger known context windows instead of a tiny fixed history',
      () {
        final openAi = resolveModelContextBudget(
          protocol: 'openai_chat',
          modelName: 'gpt-4o-mini',
        );
        final claude = resolveModelContextBudget(
          protocol: 'claude',
          modelName: 'claude-3-5-sonnet-latest',
        );

        expect(openAi.contextWindowTokens, greaterThanOrEqualTo(128000));
        expect(claude.contextWindowTokens, greaterThanOrEqualTo(200000));
        expect(openAi.maxInputTokens, lessThan(openAi.contextWindowTokens));
        expect(claude.maxInputTokens, lessThan(claude.contextWindowTokens));
      },
    );

    test('falls back to a conservative unknown-model budget', () {
      final budget = resolveModelContextBudget(
        protocol: 'custom',
        modelName: 'unknown-small-model',
      );

      expect(budget.contextWindowTokens, 8192);
      expect(budget.reservedOutputTokens, 2048);
      expect(budget.maxInputTokens, lessThan(8192));
      expect(budget.maxInputTokens, greaterThan(0));
    });

    test('keeps legacy small OpenAI models conservative', () {
      final gpt4 = resolveModelContextBudget(
        protocol: 'openai_chat',
        modelName: 'gpt-4',
      );
      final gpt35 = resolveModelContextBudget(
        protocol: 'openai_chat',
        modelName: 'gpt-3.5-turbo',
      );

      expect(gpt4.contextWindowTokens, 8192);
      expect(gpt35.contextWindowTokens, 16384);
    });

    test('short o-series names require model-token boundaries', () {
      for (final ordinaryName in ['foo1', 'audio4', 'mirror1']) {
        final ordinary = resolveModelContextBudget(
          protocol: 'custom',
          modelName: ordinaryName,
        );
        expect(
          ordinary.contextWindowTokens,
          8192,
          reason: '$ordinaryName 不是 OpenAI o 系列短代号',
        );
      }

      final o3 = resolveModelContextBudget(
        protocol: 'custom',
        modelName: 'openai/o3-mini',
      );
      expect(o3.contextWindowTokens, 128000);
    });

    test('raises compression threshold for long-context models', () {
      final budget = resolveModelContextBudget(
        protocol: 'openai_chat',
        modelName: 'gpt-4o-mini',
      );

      expect(
        dynamicCompressThresholdForBudget(budget, 2000),
        greaterThan(2000),
      );
      expect(dynamicCompressThresholdForBudget(budget, 90000), 90000);
    });
  });
}
