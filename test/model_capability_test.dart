import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelCapability reasoner', () {
    test('infers reasoner from common model names', () {
      expect(
        ModelCapability.inferFromModel('deepseek-reasoner'),
        ModelCapability.reasoner,
      );
      expect(
        ModelCapability.inferFromModel('deepseek-r1'),
        ModelCapability.reasoner,
      );
      expect(
        ModelCapability.inferFromModel('openai/o3-mini'),
        ModelCapability.reasoner,
      );
      expect(
        ModelCapability.inferFromModel('custom-deep-think-v1'),
        ModelCapability.reasoner,
      );
    });

    test('reasoner does not shadow chat models', () {
      expect(
        ModelCapability.inferFromModel('deepseek-chat'),
        ModelCapability.chat,
      );
      expect(
        ModelCapability.inferFromModel('llama-3.3-70b-versatile'),
        ModelCapability.chat,
      );
      expect(ModelCapability.inferFromModel('qwen3:4b'), ModelCapability.chat);
      expect(ModelCapability.inferFromModel('foo1'), ModelCapability.chat);
      expect(ModelCapability.inferFromModel('mirror1'), ModelCapability.chat);
      expect(ModelCapability.inferFromModel('audio4'), ModelCapability.chat);
    });

    test('reasoner is chat-compatible and labelled', () {
      expect(ModelCapability.isReasoner(ModelCapability.reasoner), isTrue);
      expect(ModelCapability.isChat(ModelCapability.reasoner), isTrue);
      expect(ModelCapability.label(ModelCapability.reasoner), contains('深度思考'));
      expect(ModelCapability.normalize('reasoner'), ModelCapability.reasoner);
    });

    test('recognizes explicit reasoner metadata', () {
      expect(
        ModelCapability.inferFromModel(
          'provider-neutral-model',
          metadata: {'capability': 'reasoning'},
        ),
        ModelCapability.reasoner,
      );
      expect(
        ModelCapability.inferFromModel(
          'provider-neutral-model',
          metadata: {
            'capabilities': ['chat', 'reasoner'],
          },
        ),
        ModelCapability.reasoner,
      );
    });

    test('vision and reasoner support can coexist for one model', () {
      const model = 'gpt-4o-reasoning';
      expect(
        ModelCapability.supportsVisionModel(
          capability: ModelCapability.reasoner,
          modelId: model,
        ),
        isTrue,
      );
      expect(
        ModelCapability.supportsReasonerModel(
          capability: ModelCapability.reasoner,
          modelId: model,
        ),
        isTrue,
      );
    });

    test('embedding and vision inference still works', () {
      expect(
        ModelCapability.inferFromModel('text-embedding-3-small'),
        ModelCapability.embedding,
      );
      expect(
        ModelCapability.inferFromModel('qwen2.5-vl-7b'),
        ModelCapability.vision,
      );
    });

    test(
      'explicit embedding capability vetoes broad vision/reasoner hints',
      () {
        expect(
          ModelCapability.supportsVisionModel(
            capability: ModelCapability.embedding,
            modelId: 'gemini-embedding-001',
          ),
          isFalse,
        );
        expect(
          ModelCapability.supportsReasonerModel(
            capability: ModelCapability.embedding,
            modelId: 'think-embedding-v1',
          ),
          isFalse,
        );
      },
    );
  });
}
