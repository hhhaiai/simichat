import 'package:ai_chat_app/core/media/media_model_capability.dart';
import 'package:ai_chat_app/core/media/media_provider_profile.dart';
import 'package:ai_chat_app/core/media/media_request_options.dart';
import 'package:ai_chat_app/core/media/provider_request_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('一次性媒体请求 Options', () {
    const imageCapability = MediaModelCapability(
      supportedAspectRatios: ['1:1', '16:9'],
      supportedResolutions: ['1K', '2K'],
      supportedSizes: ['1024x1024', '1536x1024'],
      supportedQualities: ['auto', 'high'],
      maxReferenceImages: 3,
      supportsMultipleOutputs: true,
      minOutputs: 1,
      maxOutputs: 4,
    );

    test('图片数量与多个参考图保留在请求对象中并按能力校验', () {
      const options = ImageGenerationOptions(
        model: 'image-model',
        prompt: '夜晚的城市',
        count: 3,
        referenceImages: ['/private/a.png', '/private/b.png'],
        aspectRatio: '16:9',
        resolution: '2K',
        size: '1536x1024',
        quality: 'high',
      );

      expect(options.validationErrors(capability: imageCapability), isEmpty);
      expect(options.referenceImages, ['/private/a.png', '/private/b.png']);
      expect(options.count, 3);
      expect(options.resolution, '2K');
      expect(options.size, '1536x1024');
    });

    test('图片清晰度与像素分辨率分别校验，不能混用同一组选项', () {
      const invalid = ImageGenerationOptions(
        model: 'image-model',
        prompt: 'test',
        resolution: '1536x1024',
        size: '2K',
      );

      final errors = invalid.validationErrors(capability: imageCapability);
      expect(errors, contains('当前模型不支持图片清晰度 1536x1024'));
      expect(errors, contains('当前模型不支持图片像素尺寸 2K'));
    });

    test('未声明能力的模型拒绝高级图片参数，而不是静默发送', () {
      const options = ImageGenerationOptions(
        model: 'custom',
        prompt: 'test',
        count: 2,
        aspectRatio: '16:9',
      );

      final errors = options.validationErrors(
        capability: MediaModelCapability.undeclared,
      );
      expect(errors.join('\n'), contains('生成数量'));
      expect(errors.join('\n'), contains('图片比例'));
    });

    test('xAI/Grok 视频 mapper 使用 duration 与 aspect_ratio', () {
      const options = VideoGenerationOptions(
        model: 'grok-imagine-video-1.5',
        prompt: 'A paper airplane flying over a city',
        duration: 8,
        aspectRatio: '16:9',
        resolution: '720p',
      );

      final fields = MediaRequestProviderProfile.xAiGrokVideo
          .serializeVideoGeneration(options);
      expect(fields, {
        'duration': 8,
        'aspect_ratio': '16:9',
        'resolution': '720p',
      });
      expect(fields.containsKey('seconds'), isFalse);
      expect(fields.containsKey('aspectRatio'), isFalse);
    });

    test('三种语音请求使用独立字段，克隆路径不会泄漏到 JSON', () {
      const profile = MediaRequestProviderProfile.openAiCompatibleSpeech;
      expect(
        profile.serializeSpeechSynthesis(
          const SpeechSynthesisOptions(
            model: 'mimo-v2.5-tts',
            input: '你好',
            voice: 'female-qn-qingse',
            speed: 1.25,
            responseFormat: 'opus',
          ),
        ),
        {
          'input': '你好',
          'voice': 'female-qn-qingse',
          'speed': 1.25,
          'response_format': 'opus',
        },
      );
      expect(
        profile.serializeVoiceDesign(
          const VoiceDesignOptions(
            model: 'mimo-v2.5-tts-voicedesign',
            input: '说明内容',
            style: '自然、亲切的女声',
          ),
        ),
        containsPair('style', '自然、亲切的女声'),
      );
      final cloneFields = profile.serializeVoiceClone(
        const VoiceCloneOptions(
          model: 'mimo-v2.5-tts-voiceclone',
          input: '克隆文本',
          referenceAudio: '/private/reference.wav',
        ),
      );
      expect(cloneFields, isNot(contains('referenceAudio')));
      expect(cloneFields.values.join(), isNot(contains('/private/')));
    });

    test('xAI 旧视频参数迁移时只输出 duration 和 aspect_ratio', () {
      expect(
        MediaRequestProviderProfile.normalizeLegacyVideoFields(
          profileId: 'xai_grok_video',
          rawFields: const <String, dynamic>{
            'seconds': 8,
            'aspectRatio': '16:9',
            'resolution': '720p',
            'unrecognized': 'must not pass',
          },
        ),
        {'duration': 8, 'aspect_ratio': '16:9', 'resolution': '720p'},
      );
    });

    test('语音识别语言只在中文或 English 时生成 wire 值', () {
      expect(SpeechRecognitionLanguage.auto.wireLanguage, isNull);
      expect(SpeechRecognitionLanguage.chinese.wireLanguage, 'zh');
      expect(SpeechRecognitionLanguage.english.wireLanguage, 'en');
    });

    test('图片 profile 对 Grok 显式提供任务参数，未知兼容模型仍保持保守', () {
      final grok = resolveImageRequestProfile(
        modelName: 'grok-imagine-image-quality',
        protocol: 'openai_chat',
        baseUrl: 'https://gateway.example.test/v1',
      );
      expect(grok.id, 'xai_grok_images');
      expect(grok.capability.maxReferenceImages, 1);
      expect(grok.capability.supportsAspectRatio('16:9'), isTrue);
      expect(grok.capability.supportsResolution('4K'), isTrue);
      expect(grok.capability.supportsQuality('high'), isTrue);
      expect(
        const ImageGenerationOptions(
          model: 'grok-imagine-image-quality',
          prompt: 'test',
          aspectRatio: '16:9',
          resolution: '4K',
          quality: 'high',
        ).validationErrors(capability: grok.capability),
        isEmpty,
      );
      expect(
        grok.serializeImageGeneration(
          const ImageGenerationOptions(
            model: 'grok-imagine-image-quality',
            prompt: 'test',
            count: 2,
            aspectRatio: '16:9',
            resolution: '4K',
            quality: 'high',
          ),
        ),
        {'n': 2, 'aspect_ratio': '16:9', 'resolution': '4K', 'quality': 'high'},
      );

      final unknown = resolveImageRequestProfile(
        modelName: 'custom-image-model',
        protocol: 'openai_chat',
      );
      expect(unknown.id, 'openai_compatible_images');
      expect(unknown.capability.supportsOutputCount(1), isTrue);
      expect(unknown.capability.supportsOutputCount(2), isFalse);

      final gptImage = resolveImageRequestProfile(
        modelName: 'gpt-image-2',
        protocol: 'openai_chat',
      );
      expect(gptImage.id, 'openai_images');
      expect(gptImage.capability.supportsResolution('4K'), isTrue);
      expect(gptImage.capability.supportsSize('1536x1024'), isTrue);
      expect(
        gptImage.serializeImageGeneration(
          const ImageGenerationOptions(
            model: 'gpt-image-2',
            prompt: 'test',
            resolution: '2K',
            size: '1536x1024',
          ),
        ),
        {'n': 1, 'resolution': '2K', 'size': '1536x1024'},
      );
    });

    test('只发送 profile 明确声明的清晰度或像素尺寸字段', () {
      const resolutionOnly = MediaRequestProviderProfile(
        id: 'resolution-only',
        capability: MediaModelCapability(supportedResolutions: ['2K']),
        imageResolutionField: 'resolution',
      );
      const sizeOnly = MediaRequestProviderProfile(
        id: 'size-only',
        capability: MediaModelCapability(supportedSizes: ['1536x1024']),
        imageSizeField: 'size',
      );

      expect(
        resolutionOnly.serializeImageGeneration(
          const ImageGenerationOptions(
            model: 'resolution-model',
            prompt: 'test',
            resolution: '2K',
          ),
        ),
        {'resolution': '2K'},
      );
      expect(
        sizeOnly.serializeImageGeneration(
          const ImageGenerationOptions(
            model: 'size-model',
            prompt: 'test',
            size: '1536x1024',
          ),
        ),
        {'size': '1536x1024'},
      );
    });
  });
  _runProviderRequestAdapterTests();
}

void _runProviderRequestAdapterTests() {
  group('ProviderRequestAdapter', () {
    test(
      'adapter constructs Grok wire fields and preserves attachment roles',
      () {
        final request =
            const VideoGenerationRequestAdapter(
              MediaRequestProviderProfile.xAiGrokVideo,
            ).build(
              const VideoGenerationOptions(
                model: 'grok-imagine-video-1.5',
                prompt: 'A paper airplane flying over a city',
                duration: 8,
                aspectRatio: '16:9',
                resolution: '720p',
              ),
              MediaRequestProviderProfile.xAiGrokVideo.modelCapabilities,
            );
        expect(request.fields, {
          'model': 'grok-imagine-video-1.5',
          'prompt': 'A paper airplane flying over a city',
          'duration': 8,
          'aspect_ratio': '16:9',
          'resolution': '720p',
        });
        expect(request.attachments, isEmpty);
      },
    );

    test('clone adapter keeps a local reference path out of request JSON', () {
      final request =
          const VoiceCloneRequestAdapter(
            MediaRequestProviderProfile.openAiCompatibleSpeech,
          ).build(
            const VoiceCloneOptions(
              model: 'mimo-v2.5-tts-voiceclone',
              input: '请朗读',
              referenceAudio: '/private/voice.wav',
            ),
            MediaRequestProviderProfile
                .openAiCompatibleSpeech
                .modelCapabilities,
          );
      expect(request.fields.values.join(), isNot(contains('/private/')));
      expect(
        request.attachments.single.role,
        ProviderAttachmentRole.referenceAudio,
      );
      expect(request.attachments.single.field, 'voice');
      expect(request.attachments.single.paths, ['/private/voice.wav']);
    });
  });
}
