import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/ai/universal_media_service.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/universal_media_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'media catalog keeps explicit models and manual fallbacks separate',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedMediaModels(db);

      final models = await db.channelDao.getAllModels();
      final video = buildUniversalMediaModelCandidates(
        kind: UniversalMediaKind.video,
        models: models,
        currentModel: 'custom-video-route',
      );
      final music = buildUniversalMediaModelCandidates(
        kind: UniversalMediaKind.music,
        models: models,
        currentModel: 'custom-music-route',
      );

      final videoByName = {for (final item in video) item.modelName: item};
      final musicByName = {for (final item in music) item.modelName: item};
      expect(videoByName['sora-2']?.isDeclared, isTrue);
      expect(videoByName['sora-2']?.capability, ModelCapability.video);
      expect(videoByName['grok-imagine-video']?.isDeclared, isFalse);
      expect(
        videoByName['grok-imagine-video']?.capabilityLabel,
        kUniversalMediaUndeclaredModelCapabilityLabel,
      );
      expect(videoByName['custom-video-route']?.isCurrent, isTrue);
      expect(videoByName['custom-video-route']?.isManual, isTrue);
      expect(videoByName.containsKey('mimo-v2.5-tts'), isFalse);

      expect(musicByName['lyria-2']?.isDeclared, isTrue);
      expect(musicByName['lyria-2']?.capability, ModelCapability.music);
      expect(musicByName['custom-music-route']?.isCurrent, isTrue);
      expect(musicByName.containsKey('mimo-v2.5-tts'), isFalse);
      expect(musicByName.containsKey('sora-2'), isFalse);
    },
  );

  test(
    'media candidate selection prefers channelModelId for duplicate names',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedMediaModels(db);
      await db.channelDao.addModel(
        id: 'video-explicit-duplicate',
        channelId: 'media-channel',
        modelName: 'sora-2',
        capability: ModelCapability.video,
      );

      final models = await db.channelDao.getAllModels();
      final candidates = buildUniversalMediaModelCandidates(
        kind: UniversalMediaKind.video,
        models: models,
        currentModel: 'sora-2',
        currentChannelModelId: 'video-explicit-duplicate',
      );
      final byId = {
        for (final candidate in candidates)
          if (candidate.channelModelId != null)
            candidate.channelModelId!: candidate,
      };
      expect(byId['video-explicit-duplicate']?.isCurrent, isTrue);
      expect(byId['video-explicit']?.isCurrent, isFalse);
      expect(
        byId['video-explicit-duplicate']?.selectionKey,
        'channel-model:video-explicit-duplicate',
      );

      final staleCandidates = buildUniversalMediaModelCandidates(
        kind: UniversalMediaKind.video,
        models: models,
        currentModel: 'sora-2',
        currentChannelModelId: 'deleted-video-model',
      );
      final staleCurrent = staleCandidates
          .where((item) => item.isCurrent)
          .toList();
      expect(staleCurrent, hasLength(1));
      expect(staleCurrent.single.isManual, isTrue);
      expect(staleCurrent.single.channelModelId, isNull);
    },
  );

  test(
    'provider reads enabled all-model catalog instead of chat-only catalog',
    () async {
      SharedPreferences.setMockInitialValues({
        kUniversalMediaVideoModelStorageKey: 'custom-video-route',
        kUniversalMediaVideoEndpointStorageKey: '/v1/videos',
        kUniversalMediaMusicModelStorageKey: 'custom-music-route',
        kUniversalMediaMusicEndpointStorageKey: '/v1/audio/music',
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedMediaModels(db);

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await container.read(universalMediaConfigProvider.notifier).ready;

      final video = await container.read(
        universalMediaModelCandidatesProvider(UniversalMediaKind.video).future,
      );
      final music = await container.read(
        universalMediaModelCandidatesProvider(UniversalMediaKind.music).future,
      );
      expect(video.map((item) => item.modelName), contains('sora-2'));
      expect(music.map((item) => item.modelName), contains('lyria-2'));
      expect(
        video.map((item) => item.modelName),
        isNot(contains('mimo-v2.5-tts')),
      );
      expect(
        music.map((item) => item.modelName),
        isNot(contains('mimo-v2.5-tts')),
      );
    },
  );

  testWidgets(
    'media selection saves only media model and keeps Chat selection unchanged',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kUniversalMediaVideoModelStorageKey: 'custom-video-route',
        kUniversalMediaVideoEndpointStorageKey: '/v1/videos',
        kUniversalMediaMusicModelStorageKey: 'custom-music-route',
        kUniversalMediaMusicEndpointStorageKey: '/v1/audio/music',
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedMediaModels(db);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          selectedModelIdProvider.overrideWith((_) => 'chat-default'),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('视频 / 音乐 / 通用媒体接口'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('视频 / 音乐 / 通用媒体接口'));
      await tester.pumpAndSettle();

      final videoSelector = find
          .byType(DropdownButtonFormField<UniversalMediaModelCandidate>)
          .first;
      await tester.ensureVisible(videoSelector);
      await tester.tap(videoSelector);
      await tester.pumpAndSettle();
      expect(find.textContaining('媒体渠道 / sora-2'), findsWidgets);
      await tester.tap(find.textContaining('媒体渠道 / sora-2').last);
      await tester.pumpAndSettle();

      expect(container.read(selectedModelIdProvider), 'chat-default');
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((field) => field.controller?.text)
            .whereType<String>(),
        contains('sora-2'),
      );

      await tester.tap(find.text('保存').last);
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kUniversalMediaVideoModelStorageKey), 'sora-2');
      expect(
        prefs.getString(kUniversalMediaVideoChannelModelIdStorageKey),
        'video-explicit',
      );
      expect(container.read(selectedModelIdProvider), 'chat-default');
      expect(
        prefs.getString(kUniversalMediaMusicModelStorageKey),
        'custom-music-route',
      );
    },
  );

  testWidgets('manual media model selection clears the persisted channel ID', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kUniversalMediaVideoModelStorageKey: 'sora-2',
      kUniversalMediaVideoEndpointStorageKey: '/v1/videos',
      kUniversalMediaVideoChannelModelIdStorageKey: 'video-explicit',
      kUniversalMediaMusicModelStorageKey: 'custom-music-route',
      kUniversalMediaMusicEndpointStorageKey: '/v1/audio/music',
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedMediaModels(db);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        selectedModelIdProvider.overrideWith((_) => 'chat-default'),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('视频 / 音乐 / 通用媒体接口'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频 / 音乐 / 通用媒体接口'));
    await tester.pumpAndSettle();

    final videoSelector = find
        .byType(DropdownButtonFormField<UniversalMediaModelCandidate>)
        .first;
    await tester.tap(videoSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('保存时清空媒体渠道来源 ID').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(kUniversalMediaVideoChannelModelIdStorageKey),
      isNull,
    );
    expect(container.read(selectedModelIdProvider), 'chat-default');
  });
}

Future<void> _seedMediaModels(AppDatabase db) async {
  await db.channelDao.createChannel(
    id: 'media-channel',
    name: '媒体渠道',
    baseUrl: 'https://media.example.test/v1',
    apiKeyEncrypted: 'encrypted-media-key',
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: 'video-explicit',
    channelId: 'media-channel',
    modelName: 'sora-2',
    capability: ModelCapability.video,
  );
  await db.channelDao.addModel(
    id: 'video-undeclared',
    channelId: 'media-channel',
    modelName: 'grok-imagine-video',
    capability: ModelCapability.chat,
  );
  await db.channelDao.addModel(
    id: 'music-explicit',
    channelId: 'media-channel',
    modelName: 'lyria-2',
    capability: ModelCapability.music,
  );
  await db.channelDao.addModel(
    id: 'tts-only',
    channelId: 'media-channel',
    modelName: 'mimo-v2.5-tts',
    capability: ModelCapability.audio,
  );
}
