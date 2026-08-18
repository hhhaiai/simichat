import 'dart:io';

import 'package:ai_chat_app/core/ai/file_content_extractor.dart';
import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/ai/model_provider_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SimiRouter mimo-v2.5-chat Vision contract', () {
    test('matches only the exact chat model on both OpenAI protocols', () {
      for (final protocol in ['openai_chat', 'openai_response']) {
        expect(
          ModelCapability.supportsVisionModel(
            capability: ModelCapability.chat,
            modelId: 'mimo-v2.5-chat',
            protocol: protocol,
          ),
          isTrue,
          reason: '$protocol must accept the exact persisted chat model',
        );
      }

      expect(
        ModelCapability.supportsVisionModel(
          capability: ' CHAT ',
          modelId: 'MIMO-V2.5-CHAT',
          protocol: ' OPENAI_RESPONSE ',
        ),
        isTrue,
      );
      expect(
        ModelCapability.supportsVisionModel(
          capability: ModelCapability.chat,
          modelId: 'mimo-v2.5-chat',
          protocol: 'claude',
        ),
        isFalse,
      );
      expect(
        ModelCapability.supportsVisionModel(
          capability: null,
          modelId: 'mimo-v2.5-chat',
          protocol: 'openai_chat',
        ),
        isFalse,
      );
    });

    test('vetoes TTS ASR voice and inexact ids unless Vision is explicit', () {
      const vetoedModelIds = [
        'mimo-v2.5-tts',
        'mimo-v2.5-asr',
        'mimo-v2.5-voiceclone',
        'mimo-v2.5-voicedesign',
        'prefix-mimo-v2.5-chat',
        'mimo-v2.5-chat-preview',
        'mimo-v2.5-chat-v2',
      ];

      for (final modelId in vetoedModelIds) {
        expect(
          ModelCapability.supportsVisionModel(
            capability: ModelCapability.chat,
            modelId: modelId,
            protocol: 'openai_chat',
          ),
          isFalse,
          reason: '$modelId must not inherit the exact-model exception',
        );
        expect(
          ModelCapability.supportsVisionModel(
            capability: ModelCapability.chat,
            modelId: modelId,
            protocol: 'openai_response',
          ),
          isFalse,
          reason: '$modelId must not inherit the exact-model exception',
        );
      }

      expect(
        ModelCapability.supportsVisionModel(
          capability: ModelCapability.vision,
          modelId: 'mimo-v2.5-tts',
          protocol: 'openai_chat',
        ),
        isTrue,
        reason: 'explicit persisted Vision is allowed to override name vetoes',
      );
      expect(
        ModelCapability.supportsVisionModel(
          capability: ModelCapability.audio,
          modelId: 'mimo-v2.5-chat',
          protocol: 'openai_chat',
        ),
        isFalse,
      );
    });

    test('keeps the existing SimiRouter recommendations and adds Mimo', () {
      final preset = findModelProviderPreset('dwchainless');

      expect(preset, isNotNull);
      expect(
        preset!.recommendedModels,
        containsAll(<String>[
          'gpt-4o-mini',
          'deepseek-chat',
          'qwen-plus',
          'mimo-v2.5-chat',
        ]),
      );
    });

    test(
      'does not claim a native PDF contract for exact Mimo Responses chat',
      () {
        expect(
          ModelCapability.supportsVerifiedNativeFile(
            capability: ModelCapability.chat,
            modelId: 'mimo-v2.5-chat',
            protocol: 'openai_response',
            attachmentType: 'pdf',
          ),
          isFalse,
        );
        expect(
          ModelCapability.supportsVerifiedNativeFile(
            capability: ModelCapability.chat,
            modelId: 'another-chat-model',
            protocol: 'openai_response',
            attachmentType: 'pdf',
          ),
          isTrue,
        );
        expect(
          ModelCapability.supportsVerifiedNativeFile(
            capability: ModelCapability.chat,
            modelId: 'mimo-v2.5-chat',
            protocol: 'openai_chat',
            attachmentType: 'pdf',
          ),
          isFalse,
        );
      },
    );
  });

  group('SimiRouter text fallback boundary', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'simichat_simirouter_mimo_contract_',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('reuses bounded UTF-8 document/text extraction', () async {
      final source = File('${tempDirectory.path}/notes.md');
      const expected = '# Mimo text fallback\n唯一实际文件内容：mimo-text-7f8b2c';
      await source.writeAsString(expected, flush: true);

      for (final attachmentType in ['document', 'text']) {
        final result = await extractFileContent(
          path: source.path,
          fileName: source.uri.pathSegments.last,
          attachmentType: attachmentType,
          mimeType: 'text/markdown',
        );
        expect(result.text, expected);
        expect(result.content, expected);
      }
    });

    test(
      'does not turn PDF, Office, or native_file into text fallback',
      () async {
        final cases = [
          (fileName: 'report.pdf', attachmentType: 'pdf'),
          (fileName: 'report.docx', attachmentType: 'document'),
          (fileName: 'report.txt', attachmentType: 'native_file'),
        ];

        for (final item in cases) {
          final error = await _captureExtractionError(
            () => extractFileContent(
              path: '${tempDirectory.path}/${item.fileName}',
              fileName: item.fileName,
              attachmentType: item.attachmentType,
            ),
          );
          expect(
            error.kind,
            FileContentExtractionFailureKind.unsupportedType,
            reason:
                '${item.attachmentType}/${item.fileName} is not text fallback',
          );
        }
      },
    );
  });

  group('extended vision inference', () {
    test('gpt-5 family models infer vision capability', () {
      for (final id in ['gpt-5.4', 'gpt-5.5', 'gpt-5.6-terra']) {
        expect(
          ModelCapability.inferFromModel(id),
          ModelCapability.vision,
          reason: id,
        );
      }
    });

    test(
      'mimo-v2.5-pro-chat inherits the exact SimiRouter vision contract',
      () {
        expect(
          ModelCapability.supportsVisionModel(
            capability: 'chat',
            modelId: 'mimo-v2.5-pro-chat',
            protocol: 'openai_chat',
          ),
          true,
        );
        // 带后缀 / 前缀变体仍不继承。
        expect(
          ModelCapability.supportsVisionModel(
            capability: 'chat',
            modelId: 'mimo-v2.5-pro-chat-v2',
            protocol: 'openai_chat',
          ),
          false,
        );
      },
    );
  });

}

Future<FileContentExtractionException> _captureExtractionError(
  Future<FileContentExtractionResult> Function() action,
) async {
  try {
    await action();
  } on FileContentExtractionException catch (error) {
    return error;
  }
  fail('expected FileContentExtractionException');
}
