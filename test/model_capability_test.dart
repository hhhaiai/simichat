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
      'uses protocol metadata when model discovery omits vision modalities',
      () {
        expect(
          ModelCapability.supportsVisionModel(
            capability: ModelCapability.chat,
            modelId: 'claude-sonnet-4-20250514',
            protocol: 'claude',
          ),
          isTrue,
        );
        expect(
          ModelCapability.supportsVisionModel(
            capability: ModelCapability.chat,
            modelId: 'claude-2.1',
            protocol: 'claude',
          ),
          isFalse,
        );
        expect(
          ModelCapability.supportsVisionModel(
            capability: ModelCapability.chat,
            modelId: 'gemini-2.5-flash',
            protocol: 'gemini',
          ),
          isTrue,
        );
        expect(
          ModelCapability.supportsVisionModel(
            capability: ModelCapability.chat,
            modelId: 'gemini-2.5-flash-preview-tts',
            protocol: 'gemini',
          ),
          isFalse,
        );
        expect(
          ModelCapability.supportsVisionModel(
            capability: ModelCapability.chat,
            modelId: 'qwen3-vl:8b',
            protocol: 'ollama',
          ),
          isTrue,
        );
        expect(
          ModelCapability.supportsVisionModel(
            capability: ModelCapability.chat,
            modelId: 'grok-4',
            protocol: 'openai_chat',
          ),
          isTrue,
        );
        for (final (modelId, protocol) in const [
          ('grok-voice', 'openai_chat'),
          ('grok-2-image', 'openai_chat'),
          ('gemini-2.0-flash-exp-image-generation', 'gemini'),
          ('gemini-2.5-flash-preview-tts', 'gemini'),
          ('claude-3-embedding-001', 'claude'),
          ('llava-embedding', 'ollama'),
        ]) {
          expect(
            ModelCapability.supportsVisionModel(
              capability: ModelCapability.chat,
              modelId: modelId,
              protocol: protocol,
            ),
            isFalse,
            reason: '$protocol/$modelId must not be treated as Vision',
          );
        }
      },
    );

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

    test('media capabilities require explicit metadata', () {
      expect(
        ModelCapability.supportsVideoModel(
          capability: ModelCapability.chat,
          modelId: 'video-generation-unknown',
        ),
        isFalse,
      );
      expect(
        ModelCapability.supportsMusicModel(
          capability: ModelCapability.chat,
          modelId: 'music-unknown',
        ),
        isFalse,
      );

      final capabilities = ModelCapability.capabilitiesFromMetadata(
        'relay-model',
        metadata: {
          'capabilities': ['chat', 'audio', 'video', 'music'],
        },
      );
      expect(
        capabilities,
        containsAll(<String>[
          ModelCapability.chat,
          ModelCapability.audio,
          ModelCapability.video,
          ModelCapability.music,
        ]),
      );
      expect(
        ModelCapability.supportsAudioModel(
          capability: ModelCapability.chat,
          modelId: 'relay-model',
          capabilities: capabilities,
        ),
        isTrue,
      );
      expect(
        ModelCapability.supportsVideoModel(
          capability: ModelCapability.chat,
          modelId: 'relay-model',
          capabilities: capabilities,
        ),
        isTrue,
      );
      expect(ModelCapability.normalizeMedia('tts'), ModelCapability.audio);
    });

    test(
      'normalizes aliases and does not infer dedicated media from names',
      () {
        expect(ModelCapability.normalize(' VIDEO '), ModelCapability.video);
        expect(
          ModelCapability.normalize('audio-generation'),
          ModelCapability.music,
        );
        expect(ModelCapability.normalize('multimodal'), ModelCapability.vision);
        expect(ModelCapability.normalize('completion'), ModelCapability.chat);

        for (final modelId in [
          'grok-4.6',
          'grok-voice',
          'grok-imagine-video',
          'gemini-2.5-flash-preview-tts',
          'claude-sonnet-4-20250514',
          'video-generation-unknown',
          'musicgen-small',
          'whisper-1',
        ]) {
          expect(
            ModelCapability.inferFromModel(modelId),
            ModelCapability.chat,
            reason: '$modelId 的名称不是专用媒体能力证据',
          );
        }
        expect(
          ModelCapability.supportsVideoModel(
            capability: ModelCapability.chat,
            modelId: 'grok-imagine-video',
          ),
          isFalse,
        );
        expect(
          ModelCapability.supportsAudioModel(
            capability: ModelCapability.chat,
            modelId: 'grok-voice',
          ),
          isFalse,
        );
      },
    );

    test('nested input/output modalities retain explicit direction', () {
      final capabilities = ModelCapability.capabilitiesFromMetadata(
        'opaque-model',
        metadata: {
          'modalities': {
            'input': ['text', 'image'],
            'output': ['text'],
          },
        },
        inferFromModelName: false,
      );

      expect(capabilities, contains(ModelCapability.chat));
      expect(capabilities, contains(ModelCapability.vision));
      expect(capabilities, isNot(contains(ModelCapability.image)));
      expect(
        ModelCapability.primaryCapability(
          'opaque-model',
          metadata: {
            'modalities': {
              'input': ['text', 'image'],
              'output': ['text'],
            },
          },
          inferFromModelName: false,
        ),
        ModelCapability.vision,
      );
    });
  });

  group('ModelCapability rerank', () {
    test('infers rerank from common model names', () {
      expect(
        ModelCapability.inferFromModel('jina-reranker-v2-base-multilingual'),
        ModelCapability.rerank,
      );
      expect(
        ModelCapability.inferFromModel('BAAI/bge-reranker-v2-m3'),
        ModelCapability.rerank,
      );
      expect(
        ModelCapability.inferFromModel('gte-rerank'),
        ModelCapability.rerank,
      );
      expect(
        ModelCapability.inferFromModel('rerank-v3.5'),
        ModelCapability.rerank,
      );
      expect(
        ModelCapability.inferFromModel('jina-colbert-v2'),
        ModelCapability.rerank,
      );
    });

    test('rerank inference wins over embedding prefix hints', () {
      // bge-/gte- 同时是 embedding hints，rerank 判断必须在前。
      expect(
        ModelCapability.inferFromModel('BAAI/bge-reranker-v2-m3'),
        ModelCapability.rerank,
      );
      expect(
        ModelCapability.inferFromModel('Alibaba-NLP/gte-rerank'),
        ModelCapability.rerank,
      );
      expect(
        ModelCapability.inferFromModel('text-embedding-3-small'),
        ModelCapability.embedding,
      );
      expect(
        ModelCapability.inferFromModel('BAAI/bge-m3'),
        ModelCapability.embedding,
      );
    });

    test('normalizes aliases and labels rerank', () {
      expect(ModelCapability.normalize('re-rank'), ModelCapability.rerank);
      expect(ModelCapability.normalize('reranker'), ModelCapability.rerank);
      expect(ModelCapability.isRerank('re_rank'), isTrue);
      expect(ModelCapability.label(ModelCapability.rerank), contains('重排'));
    });

    test('rerank models are excluded from the chat selector', () {
      expect(
        ModelCapability.isChatSelectableModel(
          modelId: 'jina-reranker-v2-base-multilingual',
          capability: ModelCapability.chat,
        ),
        isFalse,
      );
      expect(
        ModelCapability.isChatSelectableModel(
          modelId: 'rerank-v3.5',
          capability: ModelCapability.rerank,
        ),
        isFalse,
      );
      expect(ModelCapability.isChat(ModelCapability.rerank), isFalse);
    });

    test('explicit rerank metadata is recognized', () {
      expect(
        ModelCapability.inferFromModel(
          'provider-neutral-model',
          metadata: {'model_type': 'reranker'},
        ),
        ModelCapability.rerank,
      );
      expect(
        ModelCapability.primaryCapability(
          'provider-neutral-model',
          metadata: {'capabilities': ['rerank']},
        ),
        ModelCapability.rerank,
      );
    });

    test('rerank capability vetoes vision and reasoner', () {
      expect(
        ModelCapability.supportsVisionModel(
          capability: ModelCapability.rerank,
          modelId: 'grok-rerank',
        ),
        isFalse,
      );
      expect(
        ModelCapability.supportsReasonerModel(
          capability: ModelCapability.rerank,
          modelId: 'think-rerank-v1',
        ),
        isFalse,
      );
    });
  });
}
