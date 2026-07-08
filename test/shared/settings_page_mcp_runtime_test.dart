import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/mcp_runtime_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'settings page exposes MCP runtime status and mobile app-native boundary',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final runtimeController = McpRuntimeController(
        supportsContainerRuntime: false,
        runner: (args, {environment}) async =>
            const McpRuntimeCommandResult(exitCode: 0),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            mcpRuntimeControllerProvider.overrideWith(
              (ref) => runtimeController,
            ),
          ],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('MCP Runtime（内建 / PC 容器）'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('MCP Runtime（内建 / PC 容器）'), findsOneWidget);
      expect(find.textContaining('App 内建 MCP 可直接在移动端运行'), findsOneWidget);

      await tester.tap(find.text('MCP Runtime（内建 / PC 容器）'));
      await tester.pumpAndSettle();

      expect(find.text('MCP Runtime'), findsOneWidget);
      expect(find.textContaining('移动端默认使用 App 内建 MCP Runtime'), findsWidgets);
      expect(
        find.textContaining('当前平台无需也不支持启动 Docker / Podman 容器'),
        findsOneWidget,
      );
      expect(find.text('启动容器'), findsNothing);
    },
  );
}
