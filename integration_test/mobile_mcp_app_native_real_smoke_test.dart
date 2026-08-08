import 'dart:convert';

import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/mcp/mcp_client.dart';
import 'package:ai_chat_app/main.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile MCP App Native runs on-device without external runtime', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.mcpDao.insertServer(
      id: 'real-mobile-app-native-mcp',
      name: 'SimiChat 内建工具',
      transport: kMcpTransportAppNative,
      isEnabled: true,
      source: 'marketplace',
      marketplaceId: kAppNativeMcpServerId,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const AiChatApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiChatApp)),
      listen: false,
    );
    final manager = container.read(mcpManagerProvider.notifier);
    await manager.ready;
    await tester.pumpAndSettle();

    expect(manager.isConnected('real-mobile-app-native-mcp'), isTrue);
    expect(manager.connectionErrorFor('real-mobile-app-native-mcp'), isNull);
    expect(
      manager.getAllTools().map((entry) => entry.tool.name),
      containsAll(['simichat.now', 'simichat.runtime_info']),
    );

    final runtimeResult = await manager.callTool(
      'real-mobile-app-native-mcp',
      'simichat.runtime_info',
      const <String, dynamic>{},
    );
    expect(runtimeResult.isError, isFalse);
    final runtime =
        jsonDecode(runtimeResult.content.single.text!) as Map<String, dynamic>;
    expect(runtime['transport'], kMcpTransportAppNative);
    expect(runtime['dependencyMode'], 'in_app');
    expect(runtime['externalProcess'], isFalse);
    expect(runtime['requiresNode'], isFalse);
    expect(runtime['requiresNpx'], isFalse);
    expect(runtime['requiresPython'], isFalse);
    expect(runtime['mobileReady'], isTrue);

    final nowResult = await manager.callTool(
      'real-mobile-app-native-mcp',
      'simichat.now',
      const {'timezoneOffsetMinutes': 480},
    );
    expect(nowResult.isError, isFalse);
    final now =
        jsonDecode(nowResult.content.single.text!) as Map<String, dynamic>;
    expect(now['runtime'], kMcpTransportAppNative);
    expect(now['timezoneOffsetMinutes'], 480);
    expect(DateTime.parse(now['iso8601'] as String), isA<DateTime>());

    // The marker is useful in device logs and contains no network or secret.
    // ignore: avoid_print
    print('SIMICHAT_MOBILE_MCP_APP_NATIVE_READY');
    expect(tester.takeException(), isNull);
  });
}
