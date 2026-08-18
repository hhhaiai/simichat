import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/universal_media_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('media settings exposes profiles and editable wire options', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
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

    expect(find.text('通用媒体接口'), findsOneWidget);
    expect(find.text('OpenAI / Sora 视频'), findsOneWidget);
    expect(find.text('xAI / Grok 视频'), findsNothing);
    expect(find.text('视频模型'), findsOneWidget);
    expect(find.text('视频接口路径'), findsOneWidget);
    expect(find.text('任务协议'), findsNWidgets(2));
    expect(find.textContaining('已保存 wire options'), findsNWidgets(2));
    expect(find.textContaining('不会复制 API Key'), findsOneWidget);
    expect(find.textContaining('旧配置没有渠道模型 ID 时仍复用当前 Chat 渠道'), findsOneWidget);
  });

  testWidgets(
    'media settings opens with persisted values after the ready gate',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kUniversalMediaVideoModelStorageKey: 'persisted-video-model',
        kUniversalMediaVideoEndpointStorageKey: '/persisted/video',
        kUniversalMediaMusicModelStorageKey: 'persisted-music-model',
        kUniversalMediaMusicEndpointStorageKey: '/persisted/music',
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('视频 / 音乐 / 通用媒体接口'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('视频 / 音乐 / 通用媒体接口'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('视频 / 音乐 / 通用媒体接口'));
      await tester.pumpAndSettle();

      final fieldValues = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.controller?.text)
          .whereType<String>();
      expect(fieldValues, contains('persisted-video-model'));
      expect(fieldValues, contains('/persisted/video'));
      expect(fieldValues, contains('persisted-music-model'));
      expect(fieldValues, contains('/persisted/music'));
    },
  );

  testWidgets('media settings applies profiles and persists protocol options', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
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

    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('xAI / Grok 视频').last);
    await tester.pumpAndSettle();

    expect(find.text('xAI Videos'), findsOneWidget);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.controller?.text)
          .whereType<String>(),
      containsAll(<String>['grok-imagine-video', '/v1/videos/generations']),
    );

    final musicProfileDropdown = find
        .byType(DropdownButtonFormField<String>)
        .at(1);
    await tester.ensureVisible(musicProfileDropdown);
    await tester.pumpAndSettle();
    await tester.tap(musicProfileDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('音乐 / 自定义异步任务').last);
    await tester.pumpAndSettle();
    expect(find.text('自定义异步'), findsOneWidget);
    expect(find.text('/v1/audio/music/tasks/{id}'), findsWidgets);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(kUniversalMediaVideoProfileStorageKey),
      kUniversalMediaProfileXaiGrokVideo,
    );
    expect(
      prefs.getString(kUniversalMediaMusicProfileStorageKey),
      kUniversalMediaProfileMusicCustomAsync,
    );
    expect(
      prefs.getString(kUniversalMediaVideoTaskOptionsStorageKey),
      contains('xAiVideo'),
    );
    expect(
      prefs.getString(kUniversalMediaMusicTaskOptionsStorageKey),
      contains('configuredAsync'),
    );
    expect(prefs.getKeys(), isNot(contains('api_key')));
  });
}
