import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/features/chat/chat_page.dart';
import 'package:ai_chat_app/shared/providers/channel_provider.dart';
import 'package:ai_chat_app/shared/providers/chat_composer_draft_store.dart';
import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/mcp_provider.dart';
import 'package:ai_chat_app/shared/providers/session_provider.dart';
import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restores persisted composer draft only for its session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const channelId = 'persisted-draft-channel';
    const modelId = 'persisted-draft-model';
    const sessionA = 'persisted-draft-session-a';
    const sessionB = 'persisted-draft-session-b';
    final draftAttachment = const PendingAttachment(
      id: 'persisted-draft-file',
      path: '/private/drafts/persisted-reference.pdf',
      name: 'persisted-reference.pdf',
      type: 'pdf',
      fileSize: 128,
    );
    await ChatComposerDraftStore().save(
      sessionA,
      ChatComposerDraft(
        text: '应用重启后也要恢复这条草稿',
        attachments: [draftAttachment],
        deepThink: true,
      ),
    );

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.channelDao.createChannel(
      id: channelId,
      name: 'Persisted draft channel',
      baseUrl: 'https://example.test/v1',
      apiKeyEncrypted: KeyEncryptor.encrypt('persisted-draft-key'),
      protocol: 'openai_chat',
    );
    await db.channelDao.addModel(
      id: modelId,
      channelId: channelId,
      modelName: 'persisted-draft-model-name',
    );
    await db.sessionDao.createSession(
      id: sessionA,
      defaultChannelModelId: modelId,
    );
    await db.sessionDao.createSession(
      id: sessionB,
      defaultChannelModelId: modelId,
    );

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(true),
        activeSessionIdProvider.overrideWith((ref) => sessionA),
        selectedModelIdProvider.overrideWith((ref) => modelId),
      ],
    );
    addTearDown(container.dispose);
    await container.read(mcpManagerProvider.notifier).ready;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ChatPage())),
      ),
    );
    await tester.pumpAndSettle();

    final textField = find.byType(TextField);
    expect(
      tester.widget<TextField>(textField).controller!.text,
      '应用重启后也要恢复这条草稿',
    );
    expect(
      find.byKey(const ValueKey('pending-attachment-persisted-draft-file')),
      findsOneWidget,
    );
    expect(find.byTooltip('深度思考已开启'), findsOneWidget);

    container.read(activeSessionIdProvider.notifier).state = sessionB;
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(textField).controller!.text, isEmpty);
    expect(
      find.byKey(const ValueKey('pending-attachment-persisted-draft-file')),
      findsNothing,
    );
    expect(find.byTooltip('深度思考'), findsOneWidget);

    container.read(activeSessionIdProvider.notifier).state = sessionA;
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(textField).controller!.text,
      '应用重启后也要恢复这条草稿',
    );
    expect(
      find.byKey(const ValueKey('pending-attachment-persisted-draft-file')),
      findsOneWidget,
    );
    expect(find.byTooltip('深度思考已开启'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
