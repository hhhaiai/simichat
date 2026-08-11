import 'dart:io';
import 'dart:convert';

import 'package:ai_chat_app/core/archive/structured_data_backup.dart';
import 'package:ai_chat_app/core/media/speech_provider_preset.dart';
import 'package:ai_chat_app/core/media/reference_audio_store.dart';
import 'package:ai_chat_app/core/media/text_to_speech_service.dart';
import 'package:ai_chat_app/shared/providers/text_to_speech_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('TTS config persists encrypted key and builds engine/service', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(textToSpeechConfigProvider.notifier);
    await notifier.ready;

    expect(container.read(textToSpeechEngineProvider), isNull);
    expect(container.read(textToSpeechServiceProvider), isNull);

    await notifier.saveOpenAiCompatible(
      enabled: true,
      baseUrl: 'api.openai.com/v1/',
      model: ' tts-1 ',
      voice: ' alloy ',
      apiKey: 'tts-secret-key',
    );

    final state = container.read(textToSpeechConfigProvider);
    expect(state.isConfigured, true);
    expect(state.baseUrl, 'https://api.openai.com');
    expect(state.model, 'tts-1');
    expect(state.voice, 'alloy');
    expect(container.read(textToSpeechEngineProvider), isNotNull);
    expect(container.read(textToSpeechServiceProvider), isNotNull);

    final prefs = await SharedPreferences.getInstance();
    final storedKey = prefs.getString(kTextToSpeechApiKeyStorageKey);
    expect(storedKey, isNotNull);
    expect(storedKey, isNot('tts-secret-key'));
    expect(prefs.getKeys(), contains(kTextToSpeechApiKeyStorageKey));

    final exported = await const StructuredDataBackupService()
        .exportSharedPreferences();
    if (exported != null) {
      final exportedText = utf8.decode(exported);
      expect(exportedText, isNot(contains('tts-secret-key')));
      expect(exportedText, isNot(contains(kTextToSpeechApiKeyStorageKey)));
      expect(exportedText, isNot(contains(kTextToSpeechBaseUrlStorageKey)));
      expect(exportedText, isNot(contains(kTextToSpeechVoiceStorageKey)));
    }
  });

  test('saving enabled TTS without key is rejected', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(textToSpeechConfigProvider.notifier);
    await notifier.ready;

    await expectLater(
      notifier.saveOpenAiCompatible(
        enabled: true,
        baseUrl: 'https://api.openai.com',
        model: 'tts-1',
        voice: 'alloy',
        apiKey: '',
      ),
      throwsA(anything),
    );
    expect(container.read(textToSpeechEngineProvider), isNull);
    expect(container.read(textToSpeechServiceProvider), isNull);
  });

  test('TTS config can be saved from a provider preset', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(textToSpeechConfigProvider.notifier);
    await notifier.ready;
    final openAi = findSpeechProviderPreset('openai')!;

    await notifier.saveOpenAiCompatible(
      enabled: true,
      baseUrl: openAi.baseUrl,
      model: openAi.ttsModel!,
      voice: openAi.ttsVoice!,
      apiKey: 'tts-secret-key',
    );

    final state = container.read(textToSpeechConfigProvider);
    expect(state.baseUrl, 'https://api.openai.com');
    expect(state.model, 'tts-1');
    expect(state.voice, 'alloy');
    expect(state.isConfigured, true);
    expect(
      inferTextToSpeechPreset(
        baseUrl: state.baseUrl,
        model: state.model,
        voice: state.voice,
      )?.id,
      'openai',
    );
  });

  test('TTS keys are not part of structured backup allowlist', () async {
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechEnabledStorageKey)),
    );
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechProviderStorageKey)),
    );
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechBaseUrlStorageKey)),
    );
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechModelStorageKey)),
    );
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechVoiceStorageKey)),
    );
    expect(
      kStructuredPreferenceKeys,
      isNot(contains(kTextToSpeechApiKeyStorageKey)),
    );
  });

  test('SimiRouter TTS extended fields persist and validate', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(textToSpeechConfigProvider.notifier).ready;

    await container
        .read(textToSpeechConfigProvider.notifier)
        .saveOpenAiCompatible(
          enabled: true,
          baseUrl: 'https://api.dwchainless.com',
          model: 'mimo-v2.5-tts-voicedesign',
          voice: 'alloy',
          apiKey: 'test-key',
          speed: '1.25',
          responseFormat: 'wav',
          style: '温柔自然的年轻女声',
        );
    final config = container.read(textToSpeechConfigProvider);
    expect(config.speed, '1.25');
    expect(config.responseFormat, 'wav');
    expect(config.style, '温柔自然的年轻女声');
    expect(config.model, 'mimo-v2.5-tts-voicedesign');
    expect(config.statusLabel, contains('声音设计'));
    expect(config.statusLabel, isNot(contains('alloy')));
    expect(
      container.read(textToSpeechServiceProvider)?.audioFileExtension,
      'wav',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kTextToSpeechSpeedStorageKey), '1.25');
    expect(prefs.getString(kTextToSpeechResponseFormatStorageKey), 'wav');
    expect(prefs.getString(kTextToSpeechStyleStorageKey), contains('年轻女声'));
  });

  test('SimiRouter TTS rejects out-of-range speed and bad format', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(textToSpeechConfigProvider.notifier).ready;

    await expectLater(
      container
          .read(textToSpeechConfigProvider.notifier)
          .saveOpenAiCompatible(
            enabled: true,
            baseUrl: 'https://api.dwchainless.com',
            model: 'mimo-v2.5-tts',
            voice: 'alloy',
            apiKey: 'test-key',
            speed: '5.0',
          ),
      throwsA(isA<TextToSpeechException>()),
    );
    await expectLater(
      container
          .read(textToSpeechConfigProvider.notifier)
          .saveOpenAiCompatible(
            enabled: true,
            baseUrl: 'https://api.dwchainless.com',
            model: 'mimo-v2.5-tts',
            voice: 'alloy',
            apiKey: 'test-key',
            responseFormat: 'midi',
          ),
      throwsA(isA<TextToSpeechException>()),
    );
  });

  test('voice clone save requires reference audio', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(textToSpeechConfigProvider.notifier).ready;

    await expectLater(
      container
          .read(textToSpeechConfigProvider.notifier)
          .saveOpenAiCompatible(
            enabled: true,
            baseUrl: 'https://api.dwchainless.com',
            model: 'mimo-v2.5-tts-voiceclone',
            voice: 'alloy',
            apiKey: 'test-key',
          ),
      throwsA(
        isA<TextToSpeechException>().having(
          (e) => e.message,
          'message',
          contains('参考音频'),
        ),
      ),
    );
  });

  test('voice design save requires a style when enabled', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(textToSpeechConfigProvider.notifier).ready;

    await expectLater(
      container
          .read(textToSpeechConfigProvider.notifier)
          .saveOpenAiCompatible(
            enabled: true,
            baseUrl: 'https://api.dwchainless.com',
            model: 'mimo-v2.5-tts-voicedesign',
            voice: 'alloy',
            apiKey: 'test-key',
            style: '',
          ),
      throwsA(
        isA<TextToSpeechException>().having(
          (error) => error.message,
          'message',
          contains('声音风格描述'),
        ),
      ),
    );
  });

  test(
    'voice clone config archives, reloads, replaces and clears private wav',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp(
        'simichat_tts_clone_config_',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final support = Directory(p.join(temp.path, 'support'));
      final store = ReferenceAudioStore(
        rootResolver: () async => support,
        now: () => DateTime.fromMicrosecondsSinceEpoch(987654),
      );
      final firstSource = File(p.join(temp.path, 'first.wav'));
      await firstSource.writeAsBytes([0x52, 0x49, 0x46, 0x46, 1]);
      final notifier = TextToSpeechConfigNotifier(referenceAudioStore: store);
      await notifier.ready;

      await notifier.saveOpenAiCompatible(
        enabled: true,
        baseUrl: 'https://api.dwchainless.com',
        model: 'mimo-v2.5-tts-voiceclone',
        voice: 'alloy',
        apiKey: 'test-key',
        referenceAudioPath: firstSource.path,
      );
      final firstArchived = notifier.state.referenceAudioPath!;
      expect(firstArchived, isNot(firstSource.path));
      expect(await File(firstArchived).exists(), isTrue);
      expect(notifier.state.isConfigured, isTrue);
      expect(notifier.state.statusLabel, contains('声音克隆'));
      await firstSource.delete();
      notifier.dispose();

      final reloaded = TextToSpeechConfigNotifier(referenceAudioStore: store);
      await reloaded.ready;
      expect(reloaded.state.referenceAudioPath, firstArchived);
      expect(await File(firstArchived).exists(), isTrue);

      final secondSource = File(p.join(temp.path, 'second.wav'));
      await secondSource.writeAsBytes([0x52, 0x49, 0x46, 0x46, 2]);
      await reloaded.saveOpenAiCompatible(
        enabled: true,
        baseUrl: 'https://api.dwchainless.com',
        model: 'mimo-v2.5-tts-voiceclone',
        voice: 'alloy',
        referenceAudioPath: secondSource.path,
      );
      final secondArchived = reloaded.state.referenceAudioPath!;
      expect(secondArchived, isNot(firstArchived));
      expect(await File(firstArchived).exists(), isFalse);
      expect(await File(secondArchived).exists(), isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString(
          kTextToSpeechReferenceAudioPathStorageKey,
        ),
        secondArchived,
      );

      await File(secondArchived).delete();
      expect(reloaded.state.isConfigured, isFalse);
      expect(reloaded.state.statusLabel, contains('已失效'));

      await reloaded.clearConfig();
      expect(await File(secondArchived).exists(), isFalse);
      expect(reloaded.state.referenceAudioPath, isNull);
      reloaded.dispose();
    },
  );

  test('missing saved clone wav is cleared during config reload', () async {
    final temp = await Directory.systemTemp.createTemp(
      'simichat_tts_clone_missing_',
    );
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final support = Directory(p.join(temp.path, 'support'));
    SharedPreferences.setMockInitialValues({
      kTextToSpeechEnabledStorageKey: true,
      kTextToSpeechModelStorageKey: 'mimo-v2.5-tts-voiceclone',
      kTextToSpeechReferenceAudioPathStorageKey: p.join(
        temp.path,
        'missing.wav',
      ),
    });
    final notifier = TextToSpeechConfigNotifier(
      referenceAudioStore: ReferenceAudioStore(
        rootResolver: () async => support,
      ),
    );
    await notifier.ready;

    expect(notifier.state.referenceAudioPath, isNull);
    expect(notifier.state.isConfigured, isFalse);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        kTextToSpeechReferenceAudioPathStorageKey,
      ),
      isFalse,
    );
    notifier.dispose();
  });
}
