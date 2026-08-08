import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/memory/key_point_memory.dart';
import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/key_point_memory_provider.dart';
import 'package:ai_chat_app/shared/providers/user_profile_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('profile model candidate switch is independent and default off', (
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
      find.text('用户画像 / 镜像数字人基础'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();

    expect(find.text('使用模型辅助画像候选'), findsOneWidget);
    expect(find.textContaining('默认关闭。开启后'), findsOneWidget);
    expect(find.textContaining('不能直接修改正式画像'), findsOneWidget);

    final switchTile = find.ancestor(
      of: find.text('使用模型辅助画像候选'),
      matching: find.byType(SwitchListTile),
    );
    await tester.tap(switchTile);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kUserProfileModelEnabledStorageKey), isTrue);
  });

  testWidgets('settings page can rebuild and show local user profile', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 6, 27);
    SharedPreferences.setMockInitialValues({
      kKeyPointMemoryStorageKey: encodeKeyPointMemoryItems([
        _memory('preference', '我喜欢中文回复和结构化总结', now),
        _memory('preference', '我不喜欢中文回复太啰嗦', now),
        _memory('goal', '我的目标是把 SimiChat 做成移动端优先的 AI 伙伴', now),
      ]),
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
      find.text('用户画像 / 镜像数字人基础'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();

    expect(find.text('用户画像 / 镜像数字人基础'), findsOneWidget);
    expect(find.textContaining('尚未生成'), findsOneWidget);

    await tester.tap(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();

    expect(find.text('重建画像'), findsOneWidget);
    expect(find.textContaining('不上传云端'), findsOneWidget);

    await tester.tap(find.text('重建画像'));
    await tester.pumpAndSettle();

    expect(find.textContaining('用户画像已重建'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final profile = decodeUserProfile(prefs.getString(kUserProfileStorageKey));
    expect(profile, isNotNull);
    expect(profile!.goals.join('\n'), contains('移动端优先'));
    expect(profile.conflicts, isNotEmpty);
    final history = decodeUserProfileHistory(
      prefs.getString(kUserProfileHistoryStorageKey),
    );
    expect(history, hasLength(1));
    expect(history.single.summary, contains('手动重建'));
  });

  testWidgets('settings page can edit and delete local profile signals', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 6, 27);
    final memories = [
      _memory('preference', '我喜欢中文回复和结构化总结', now),
      _memory('goal', '我的目标是把 SimiChat 做成移动端优先的 AI 伙伴', now),
    ];
    final profile = const UserProfileBuilder().build(
      keyPoints: memories,
      now: now,
    );
    SharedPreferences.setMockInitialValues({
      kKeyPointMemoryStorageKey: encodeKeyPointMemoryItems(memories),
      kUserProfileStorageKey: encodeUserProfile(profile),
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
      find.text('用户画像 / 镜像数字人基础'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('编辑画像信号'), findsWidgets);
    expect(find.byTooltip('删除画像信号'), findsWidgets);

    await tester.tap(find.byTooltip('编辑画像信号').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '我喜欢中文回复和短句总结');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('画像信号已更新'), findsOneWidget);

    var prefs = await SharedPreferences.getInstance();
    var controls = decodeUserProfileControls(
      prefs.getString(kUserProfileControlsStorageKey),
    );
    expect(controls.editedSignals.values, contains('我喜欢中文回复和短句总结'));

    await tester.tap(find.byTooltip('删除画像信号').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('画像信号已删除'), findsOneWidget);
    prefs = await SharedPreferences.getInstance();
    controls = decodeUserProfileControls(
      prefs.getString(kUserProfileControlsStorageKey),
    );
    expect(controls.hiddenSignals, isNotEmpty);
    final history = decodeUserProfileHistory(
      prefs.getString(kUserProfileHistoryStorageKey),
    );
    expect(history.length, greaterThanOrEqualTo(2));
  });

  testWidgets('settings page compares and restores user profile history', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 6, 27);
    final current = UserProfile(
      updatedAt: now,
      sourceCount: 1,
      preferences: const ['我喜欢当前画像'],
      goals: const [],
      tasks: const [],
      profileFacts: const [],
      styleSignals: const [],
      scheduleSignals: const [],
      keywords: const ['current'],
    );
    final historical = current.copyWith(
      preferences: const ['我喜欢历史画像'],
      keywords: const ['history'],
    );
    final history = [
      UserProfileHistoryEntry(
        id: 'history-1',
        createdAt: now.subtract(const Duration(hours: 1)),
        reason: 'manual_rebuild',
        profile: historical,
      ),
    ];
    SharedPreferences.setMockInitialValues({
      kUserProfileStorageKey: encodeUserProfile(current),
      kUserProfileHistoryStorageKey: encodeUserProfileHistory(history),
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
      find.text('用户画像 / 镜像数字人基础'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();

    expect(find.text('版本历史'), findsOneWidget);
    expect(find.textContaining('相对当前'), findsOneWidget);
    expect(find.textContaining('偏好：新增 1 · 移除 1'), findsOneWidget);

    await tester.ensureVisible(find.text('恢复此版本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复此版本'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已恢复历史画像'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final restored = decodeUserProfile(prefs.getString(kUserProfileStorageKey));
    expect(restored, isNotNull);
    expect(restored!.preferences.single, '我喜欢历史画像');
    expect(restored.keywords, contains('history'));
    final nextHistory = decodeUserProfileHistory(
      prefs.getString(kUserProfileHistoryStorageKey),
    );
    expect(nextHistory.first.summary, contains('恢复历史版本'));
  });

  testWidgets('settings page can accept pending user profile proposal', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 6, 27);
    final current = UserProfile(
      updatedAt: now,
      sourceCount: 1,
      preferences: const ['我喜欢当前画像'],
      goals: const [],
      tasks: const [],
      profileFacts: const [],
      styleSignals: const [],
      scheduleSignals: const [],
      keywords: const ['current'],
    );
    final candidate = current.copyWith(
      preferences: const ['我喜欢待确认画像'],
      keywords: const ['proposal'],
    );
    final proposal = UserProfileChangeProposal(
      id: 'proposal-1',
      createdAt: now,
      reason: 'profile_proposal',
      baseProfile: current,
      candidateProfile: candidate,
    );
    SharedPreferences.setMockInitialValues({
      kUserProfileStorageKey: encodeUserProfile(current),
      kUserProfileChangeProposalsStorageKey: encodeUserProfileChangeProposals([
        proposal,
      ]),
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
      find.text('用户画像 / 镜像数字人基础'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();

    expect(find.text('待确认画像变更'), findsOneWidget);
    expect(find.textContaining('偏好：新增 1 · 移除 1'), findsOneWidget);

    await tester.ensureVisible(find.text('采纳变更'));
    await tester.tap(find.text('采纳变更'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已采纳画像变更'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final accepted = decodeUserProfile(prefs.getString(kUserProfileStorageKey));
    expect(accepted, isNotNull);
    expect(accepted!.preferences.single, '我喜欢待确认画像');
    expect(
      decodeUserProfileChangeProposals(
        prefs.getString(kUserProfileChangeProposalsStorageKey),
      ),
      isEmpty,
    );
  });

  testWidgets('settings page can accept one pending profile proposal item', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 6, 27);
    final current = UserProfile(
      updatedAt: now,
      sourceCount: 1,
      preferences: const ['我喜欢当前画像'],
      goals: const [],
      tasks: const [],
      profileFacts: const [],
      styleSignals: const [],
      scheduleSignals: const [],
      keywords: const [],
    );
    final candidate = current.copyWith(
      sourceCount: 2,
      goals: const ['目标是逐项采纳画像变更'],
    );
    final proposal = UserProfileChangeProposal(
      id: 'proposal-item-accept',
      createdAt: now,
      reason: 'profile_proposal',
      baseProfile: current,
      candidateProfile: candidate,
    );
    SharedPreferences.setMockInitialValues({
      kUserProfileStorageKey: encodeUserProfile(current),
      kUserProfileChangeProposalsStorageKey: encodeUserProfileChangeProposals([
        proposal,
      ]),
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
      find.text('用户画像 / 镜像数字人基础'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();

    expect(find.text('逐项确认'), findsOneWidget);
    expect(find.text('采纳此项'), findsOneWidget);
    expect(find.text('忽略此项'), findsOneWidget);
    expect(find.textContaining('目标 · 新增'), findsOneWidget);

    await tester.ensureVisible(find.text('采纳此项'));
    await tester.tap(find.text('采纳此项'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已采纳单条画像变更'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final accepted = decodeUserProfile(prefs.getString(kUserProfileStorageKey));
    expect(accepted, isNotNull);
    expect(accepted!.goals, contains('目标是逐项采纳画像变更'));
    expect(accepted.preferences, contains('我喜欢当前画像'));
    expect(
      decodeUserProfileChangeProposals(
        prefs.getString(kUserProfileChangeProposalsStorageKey),
      ),
      isEmpty,
    );
  });

  testWidgets('settings page can reject one pending profile proposal item', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 6, 27);
    final current = UserProfile(
      updatedAt: now,
      sourceCount: 1,
      preferences: const ['我喜欢当前画像'],
      goals: const [],
      tasks: const [],
      profileFacts: const [],
      styleSignals: const [],
      scheduleSignals: const [],
      keywords: const [],
    );
    final candidate = current.copyWith(
      sourceCount: 2,
      goals: const ['目标是被忽略的画像变更'],
    );
    final proposal = UserProfileChangeProposal(
      id: 'proposal-item-reject',
      createdAt: now,
      reason: 'profile_proposal',
      baseProfile: current,
      candidateProfile: candidate,
    );
    SharedPreferences.setMockInitialValues({
      kUserProfileStorageKey: encodeUserProfile(current),
      kUserProfileChangeProposalsStorageKey: encodeUserProfileChangeProposals([
        proposal,
      ]),
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
      find.text('用户画像 / 镜像数字人基础'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户画像 / 镜像数字人基础'));
    await tester.pumpAndSettle();

    expect(find.text('逐项确认'), findsOneWidget);
    expect(find.text('忽略此项'), findsOneWidget);

    await tester.ensureVisible(find.text('忽略此项'));
    await tester.tap(find.text('忽略此项'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已忽略单条画像变更'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final unchanged = decodeUserProfile(
      prefs.getString(kUserProfileStorageKey),
    );
    expect(unchanged, isNotNull);
    expect(unchanged!.goals, isEmpty);
    expect(unchanged.preferences, contains('我喜欢当前画像'));
    expect(
      decodeUserProfileChangeProposals(
        prefs.getString(kUserProfileChangeProposalsStorageKey),
      ),
      isEmpty,
    );
  });

  testWidgets(
    'settings page can show all pending profile proposal items in details',
    (tester) async {
      final now = DateTime.utc(2026, 6, 27);
      final current = UserProfile(
        updatedAt: now,
        sourceCount: 1,
        preferences: const ['我喜欢当前画像'],
        goals: const [],
        tasks: const [],
        profileFacts: const [],
        styleSignals: const [],
        scheduleSignals: const [],
        keywords: const [],
      );
      final candidate = current.copyWith(
        sourceCount: 7,
        goals: const [
          '目标是详情第 1 项',
          '目标是详情第 2 项',
          '目标是详情第 3 项',
          '目标是详情第 4 项',
          '目标是详情第 5 项',
          '目标是详情第 6 项',
        ],
      );
      final proposal = UserProfileChangeProposal(
        id: 'proposal-item-details',
        createdAt: now,
        reason: 'profile_proposal',
        baseProfile: current,
        candidateProfile: candidate,
      );
      SharedPreferences.setMockInitialValues({
        kUserProfileStorageKey: encodeUserProfile(current),
        kUserProfileChangeProposalsStorageKey: encodeUserProfileChangeProposals(
          [proposal],
        ),
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
        find.text('用户画像 / 镜像数字人基础'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('用户画像 / 镜像数字人基础'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('用户画像 / 镜像数字人基础'));
      await tester.pumpAndSettle();

      expect(find.text('查看全部 6 项'), findsOneWidget);
      expect(find.textContaining('目标是详情第 6 项'), findsNothing);

      await tester.ensureVisible(find.text('查看全部 6 项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看全部 6 项'));
      await tester.pumpAndSettle();

      expect(find.text('待确认画像变更详情'), findsOneWidget);
      expect(find.text('全部待确认项'), findsOneWidget);
      expect(find.textContaining('目标是详情第 6 项'), findsOneWidget);

      await tester.ensureVisible(find.textContaining('目标是详情第 6 项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('采纳此项').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('已采纳单条画像变更'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final accepted = decodeUserProfile(
        prefs.getString(kUserProfileStorageKey),
      );
      expect(accepted, isNotNull);
      expect(accepted!.goals, contains('目标是详情第 6 项'));

      final proposals = decodeUserProfileChangeProposals(
        prefs.getString(kUserProfileChangeProposalsStorageKey),
      );
      expect(proposals, hasLength(1));
      expect(proposals.single.diff.addedCount, 5);
    },
  );
}

KeyPointMemoryItem _memory(String category, String content, DateTime now) {
  return KeyPointMemoryItem(
    id: makeMemoryItemId('s1', content),
    sessionId: 's1',
    sourceMessageId: 'm-${content.hashCode}',
    category: category,
    content: content,
    keywords: extractMemoryKeywords(content),
    confidence: 0.8,
    createdAt: now,
    updatedAt: now,
  );
}
