import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile device settings smoke persists theme and font scale', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SimiAIChat'), findsWidgets);
    expect(find.text('未选择模型'), findsOneWidget);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('字体大小'), findsOneWidget);
    expect(find.text('数据与档案'), findsOneWidget);

    await tester.tap(find.text('主题模式'));
    await tester.pumpAndSettle();
    expect(find.text('选择主题模式'), findsOneWidget);

    await tester.tap(find.text('深色模式').last);
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('theme_mode') == ThemeMode.dark.name;
    });

    expect(find.text('深色模式'), findsOneWidget);

    await tester.tap(find.text('字体大小'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged?.call(1.2);
    await tester.pumpAndSettle();
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    final saveButton = dialog.actions!.whereType<FilledButton>().single;
    saveButton.onPressed!();
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () async {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getDouble('font_scale');
      return value != null && value >= 1.19 && value <= 1.20;
    });

    expect(find.textContaining('当前: 120%'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('SimiAIChat'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (await predicate()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for condition');
}
