import 'dart:convert';

import 'package:ai_chat_app/core/ai/universal_media_service.dart';
import 'package:ai_chat_app/shared/providers/universal_media_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('exposes key-free mainstream video and music profiles', () {
    final videoProfiles = universalMediaProviderProfilesFor(
      UniversalMediaKind.video,
    );
    final musicProfiles = universalMediaProviderProfilesFor(
      UniversalMediaKind.music,
    );

    expect(
      videoProfiles.map((profile) => profile.id),
      containsAll(<String>[
        kUniversalMediaProfileOpenAiSora,
        kUniversalMediaProfileXaiGrokVideo,
        kUniversalMediaProfileOpenAiCompatibleCustom,
      ]),
    );
    expect(
      musicProfiles.map((profile) => profile.id),
      containsAll(<String>[
        kUniversalMediaProfileMusicOpenAiCompatible,
        kUniversalMediaProfileMusicCustomAsync,
      ]),
    );

    final sora = findUniversalMediaProviderProfile(
      kUniversalMediaProfileOpenAiSora,
      kind: UniversalMediaKind.video,
    )!;
    expect(sora.endpoint, '/v1/videos');
    expect(sora.model, 'sora-2');
    expect(sora.taskOptions.protocol, UniversalMediaProtocol.openAiVideo);
    expect(sora.taskOptions.referenceField, 'input_reference');

    final grok = findUniversalMediaProviderProfile(
      kUniversalMediaProfileXaiGrokVideo,
      kind: UniversalMediaKind.video,
    )!;
    expect(grok.endpoint, '/v1/videos/generations');
    expect(grok.model, 'grok-imagine-video');
    expect(grok.taskOptions.protocol, UniversalMediaProtocol.xAiVideo);
    expect(grok.taskOptions.requestFormat, UniversalMediaRequestFormat.json);

    final asyncMusic = findUniversalMediaProviderProfile(
      kUniversalMediaProfileMusicCustomAsync,
      kind: UniversalMediaKind.music,
    )!;
    expect(
      asyncMusic.taskOptions.protocol,
      UniversalMediaProtocol.configuredAsync,
    );
    expect(asyncMusic.taskOptions.pollUrlTemplate, contains('{id}'));
    expect(asyncMusic.taskOptions.contentUrlTemplate, contains('{id}'));
    expect(asyncMusic.taskOptions.cancelUrlTemplate, contains('{id}'));
    expect(asyncMusic.wireSummary, contains('protocol=configuredAsync'));

    final compatibleMusic = findUniversalMediaProviderProfile(
      kUniversalMediaProfileMusicOpenAiCompatible,
      kind: UniversalMediaKind.music,
    )!;
    expect(
      compatibleMusic.taskOptions.requestFormat,
      UniversalMediaRequestFormat.json,
    );
  });

  test('loads legacy fields and migrates only the new profile IDs', () async {
    final legacyMusicOptions = const UniversalMediaTaskOptions(
      protocol: UniversalMediaProtocol.configuredAsync,
      requestFormat: UniversalMediaRequestFormat.json,
      pollUrlTemplate: '/jobs/{id}/status',
      contentUrlTemplate: '/jobs/{id}/download',
    );
    SharedPreferences.setMockInitialValues({
      kUniversalMediaVideoModelStorageKey: 'grok-imagine-video',
      kUniversalMediaVideoEndpointStorageKey: '/v1/videos/generations',
      kUniversalMediaMusicModelStorageKey: 'legacy-music',
      kUniversalMediaMusicEndpointStorageKey: '/v1/audio/tasks',
      kUniversalMediaMusicTaskOptionsStorageKey: jsonEncode(
        legacyMusicOptions.toJson(),
      ),
      'unrelated.preference': 'preserve-me',
    });

    final notifier = UniversalMediaConfigNotifier();
    await notifier.ready;
    final prefs = await SharedPreferences.getInstance();

    expect(notifier.state.videoModel, 'grok-imagine-video');
    expect(notifier.state.videoEndpoint, '/v1/videos/generations');
    expect(notifier.state.videoProfileId, kUniversalMediaProfileXaiGrokVideo);
    expect(notifier.state.musicModel, 'legacy-music');
    expect(notifier.state.musicEndpoint, '/v1/audio/tasks');
    expect(
      notifier.state.musicTaskOptions.protocol,
      UniversalMediaProtocol.configuredAsync,
    );
    expect(
      notifier.state.musicProfileId,
      kUniversalMediaProfileMusicCustomAsync,
    );
    expect(
      prefs.getString(kUniversalMediaVideoProfileStorageKey),
      kUniversalMediaProfileXaiGrokVideo,
    );
    expect(
      prefs.getString(kUniversalMediaMusicProfileStorageKey),
      kUniversalMediaProfileMusicCustomAsync,
    );
    expect(prefs.getString('unrelated.preference'), 'preserve-me');
    expect(prefs.getKeys(), isNot(contains('universal_media_api_key')));
    expect(notifier.state.videoChannelModelId, isNull);
    expect(notifier.state.musicChannelModelId, isNull);
  });

  test(
    'persists, restores, and explicitly clears media channel model IDs',
    () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = UniversalMediaConfigNotifier();
      addTearDown(notifier.dispose);
      await notifier.ready;

      await notifier.save(
        videoModel: 'sora-2',
        videoEndpoint: '/v1/videos',
        videoChannelModelId: ' video-channel-model ',
        musicModel: 'lyria-2',
        musicEndpoint: '/v1/audio/music',
        musicChannelModelId: 'music-channel-model',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(notifier.state.videoChannelModelId, 'video-channel-model');
      expect(notifier.state.musicChannelModelId, 'music-channel-model');
      expect(
        prefs.getString(kUniversalMediaVideoChannelModelIdStorageKey),
        'video-channel-model',
      );
      expect(
        prefs.getString(kUniversalMediaMusicChannelModelIdStorageKey),
        'music-channel-model',
      );
      expect(prefs.getKeys(), isNot(contains('api_key')));

      final restored = UniversalMediaConfigNotifier();
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.state.videoChannelModelId, 'video-channel-model');
      expect(restored.state.musicChannelModelId, 'music-channel-model');

      final copied = restored.state.copyWith(
        videoChannelModelId: null,
        musicChannelModelId: 'copied-music-model',
      );
      expect(copied.videoChannelModelId, isNull);
      expect(copied.musicChannelModelId, 'copied-music-model');

      await notifier.save(
        videoModel: notifier.state.videoModel,
        videoEndpoint: notifier.state.videoEndpoint,
        videoChannelModelId: null,
        musicModel: notifier.state.musicModel,
        musicEndpoint: notifier.state.musicEndpoint,
        musicChannelModelId: null,
      );
      expect(notifier.state.videoChannelModelId, isNull);
      expect(notifier.state.musicChannelModelId, isNull);
      expect(
        prefs.containsKey(kUniversalMediaVideoChannelModelIdStorageKey),
        isFalse,
      );
      expect(
        prefs.containsKey(kUniversalMediaMusicChannelModelIdStorageKey),
        isFalse,
      );
    },
  );

  test(
    'saves profile and wire options without introducing a key field',
    () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = UniversalMediaConfigNotifier();
      await notifier.ready;

      const musicOptions = UniversalMediaTaskOptions.configuredAsync(
        requestFormat: UniversalMediaRequestFormat.json,
        pollUrlTemplate: '/tasks/{id}/status',
        contentUrlTemplate: '/tasks/{id}/output',
        cancelUrlTemplate: '/tasks/{id}',
      );
      await notifier.save(
        videoModel: 'grok-imagine-video',
        videoEndpoint: '/v1/videos/generations',
        musicModel: 'custom-music',
        musicEndpoint: '/v1/audio/tasks',
        videoProfileId: kUniversalMediaProfileXaiGrokVideo,
        musicProfileId: kUniversalMediaProfileMusicCustomAsync,
        videoTaskOptions: const UniversalMediaTaskOptions.xAiVideo(),
        musicTaskOptions: musicOptions,
      );

      final prefs = await SharedPreferences.getInstance();
      final restored = UniversalMediaConfigNotifier();
      await restored.ready;

      expect(restored.state.videoProfileId, kUniversalMediaProfileXaiGrokVideo);
      expect(
        restored.state.videoTaskOptions.protocol,
        UniversalMediaProtocol.xAiVideo,
      );
      expect(
        restored.state.musicProfileId,
        kUniversalMediaProfileMusicCustomAsync,
      );
      expect(
        restored.state.musicTaskOptions.contentUrlTemplate,
        '/tasks/{id}/output',
      );
      expect(
        prefs.getString(kUniversalMediaVideoModelStorageKey),
        'grok-imagine-video',
      );
      expect(
        prefs.getString(kUniversalMediaMusicEndpointStorageKey),
        '/v1/audio/tasks',
      );
      expect(prefs.getKeys(), isNot(contains('api_key')));
    },
  );

  test('local route readiness does not claim channel capability', () {
    const configured = UniversalMediaConfig(
      videoModel: 'sora-2',
      videoEndpoint: '/v1/videos',
      musicModel: 'music-1',
      musicEndpoint: '/v1/audio/music',
    );
    const incomplete = UniversalMediaConfig(
      videoModel: ' ',
      videoEndpoint: ' ',
      musicModel: ' ',
      musicEndpoint: ' ',
    );

    expect(configured.videoRouteConfigured, isTrue);
    expect(configured.musicRouteConfigured, isTrue);
    expect(incomplete.videoRouteConfigured, isFalse);
    expect(incomplete.musicRouteConfigured, isFalse);
  });
}
