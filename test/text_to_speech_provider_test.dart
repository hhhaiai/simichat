import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:ai_chat_app/core/archive/structured_data_backup.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/media/speech_provider_preset.dart';
import 'package:ai_chat_app/core/media/reference_audio_store.dart';
import 'package:ai_chat_app/core/media/text_to_speech_service.dart';
import 'package:ai_chat_app/core/media/xai_custom_voice_adapter.dart';
import 'package:ai_chat_app/shared/providers/text_to_speech_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'task voice loader decrypts the key and returns provider voices',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = Completer<({String path, String authorization})>();
      unawaited(
        server.forEach((request) async {
          seen.complete((
            path: request.uri.toString(),
            authorization: request.headers.value('authorization') ?? '',
          ));
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'voices': [
                  {'id': 'provider-voice', 'label': '渠道音色'},
                ],
              }),
            );
          await request.response.close();
        }),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final config = TextToSpeechConfig(
        enabled: true,
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        model: 'mimo-v2.5-tts',
        voice: 'alloy',
        apiKeyEncrypted: KeyEncryptor.encrypt('voice-loader-key'),
      );

      final voices = await container.read(textToSpeechVoiceLoaderProvider)(
        config,
      );

      expect(voices.single.id, 'provider-voice');
      expect(voices.single.displayLabel, '渠道音色 (provider-voice)');
      final request = await seen.future;
      expect(request.path, '/v1/tts/voices?model=mimo-v2.5-tts');
      expect(request.authorization, 'Bearer voice-loader-key');
    },
  );

  test(
    'xAI custom voice creation decrypts the stored key and persists only the returned voice_id',
    () async {
      SharedPreferences.setMockInitialValues({});
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestSeen = Completer<({String authorization, String body})>();
      unawaited(
        server.forEach((request) async {
          final bytes = await request.fold<List<int>>(
            <int>[],
            (buffer, chunk) => buffer..addAll(chunk),
          );
          requestSeen.complete((
            authorization: request.headers.value('authorization') ?? '',
            body: latin1.decode(bytes),
          ));
          request.response
            ..statusCode = HttpStatus.created
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'voice_id': 'xy12ab34'}));
          await request.response.close();
        }),
      );

      final temp = await Directory.systemTemp.createTemp(
        'simichat_xai_provider_voice_',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final reference = File('${temp.path}/reference.wav');
      await reference.writeAsBytes([0x52, 0x49, 0x46, 0x46, 1, 2]);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(textToSpeechConfigProvider.notifier);
      await notifier.ready;
      final baseUrl = 'http://${server.address.host}:${server.port}';
      await notifier.saveXai(
        enabled: true,
        baseUrl: baseUrl,
        voice: 'eve',
        apiKey: 'xai-decrypted-key',
      );

      final result = await notifier.createAndSaveXaiCustomVoice(
        enabled: true,
        baseUrl: baseUrl,
        request: XaiCustomVoiceRequest(
          audioPath: reference.path,
          fileName: 'reference.wav',
          name: 'Provider test voice',
          description: 'Created through provider',
          language: 'en',
        ),
        // Blank means the notifier must decrypt the key already in state.
        apiKey: '',
      );

      expect(result.voiceId, 'xy12ab34');
      expect(container.read(textToSpeechConfigProvider).voice, 'xy12ab34');
      expect(
        container.read(textToSpeechConfigProvider).referenceAudioPath,
        isNull,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          kTextToSpeechVoiceStorageKey,
        ),
        'xy12ab34',
      );
      final seen = await requestSeen.future;
      expect(seen.authorization, 'Bearer xai-decrypted-key');
      expect(seen.body, contains('Provider test voice'));
      expect(seen.body, contains('Created through provider'));
      expect(seen.body, isNot(contains(reference.path)));
    },
  );

  test(
    'xAI custom voice failure never persists a pseudo voice_id and redacts local paths',
    () async {
      SharedPreferences.setMockInitialValues({});
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          await request.drain<void>();
          request.response
            ..statusCode = HttpStatus.created
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'voice_id': 'not-valid',
                'error': 'Bearer raw-secret /Users/private/reference.wav',
              }),
            );
          await request.response.close();
        }),
      );

      final temp = await Directory.systemTemp.createTemp(
        'simichat_xai_provider_invalid_',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final reference = File('${temp.path}/reference.wav');
      await reference.writeAsBytes([1, 2, 3]);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(textToSpeechConfigProvider.notifier);
      await notifier.ready;
      final baseUrl = 'http://${server.address.host}:${server.port}';
      await notifier.saveXai(
        enabled: true,
        baseUrl: baseUrl,
        voice: 'eve',
        apiKey: 'xai-secret',
      );

      await expectLater(
        notifier.createAndSaveXaiCustomVoice(
          enabled: true,
          baseUrl: baseUrl,
          request: XaiCustomVoiceRequest(audioPath: reference.path),
        ),
        throwsA(
          isA<XaiCustomVoiceException>()
              .having((error) => error.message, 'message', contains('voice_id'))
              .having(
                (error) => error.message,
                'message does not contain path',
                isNot(contains(reference.path)),
              )
              .having(
                (error) => error.message,
                'message does not contain token',
                isNot(contains('xai-secret')),
              ),
        ),
      );
      expect(container.read(textToSpeechConfigProvider).voice, 'eve');
      expect(
        (await SharedPreferences.getInstance()).getString(
          kTextToSpeechVoiceStorageKey,
        ),
        'eve',
      );
    },
  );

  test('xAI TTS status exposes the custom voice permission boundary', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(textToSpeechConfigProvider.notifier);
    await notifier.ready;

    await notifier.saveXai(
      enabled: true,
      voice: 'xy12ab34',
      apiKey: 'xai-status-key',
    );

    final config = container.read(textToSpeechConfigProvider);
    expect(config.statusLabel, contains('/v1/tts'));
    expect(config.statusLabel, contains('xy12ab34'));
    expect(config.statusLabel, contains('Enterprise API 权限'));
  });

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

  test(
    'generic OpenAI-compatible TTS service keeps the configured output extension',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(textToSpeechConfigProvider.notifier);
      await notifier.ready;

      await notifier.saveOpenAiCompatible(
        enabled: true,
        baseUrl: 'https://speech.example.test/v1',
        model: 'tts-compatible',
        voice: 'alloy',
        apiKey: 'tts-output-key',
        responseFormat: 'wav',
      );

      expect(
        container.read(textToSpeechServiceProvider)?.audioFileExtension,
        'wav',
        reason: '响应格式是 WAV 时不能把文件错误保存为 .mp3',
      );
    },
  );

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
    'custom OpenAI-compatible voice design stays configurable but not ready',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(textToSpeechConfigProvider.notifier);
      await notifier.ready;

      await notifier.saveOpenAiCompatible(
        enabled: true,
        baseUrl: 'https://custom.example.test/v1',
        model: 'mimo-v2.5-tts-voicedesign',
        voice: 'alloy',
        apiKey: 'custom-tts-key',
        style: '温柔自然的年轻女声',
      );

      final config = container.read(textToSpeechConfigProvider);
      expect(config.style, '温柔自然的年轻女声');
      expect(config.isConfigured, isFalse);
      expect(config.statusLabel, contains('未声明'));
      expect(container.read(textToSpeechEngineProvider), isNull);
    },
  );

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
