import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/persona_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('personaAuthorizationProvider', () {
    test('defaults to not authorized', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        container.read(personaAuthorizationProvider).isAuthorized,
        isFalse,
      );
    });

    test('authorize persists and revoke clears', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await container.read(personaAuthorizationProvider.notifier).authorize();
      final auth = container.read(personaAuthorizationProvider);
      expect(auth.isAuthorized, isTrue);
      expect(auth.authorizedAtIso, isNotNull);

      // 重新加载（模拟重启）后仍授权。
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      await container2.read(personaAuthorizationProvider.notifier).ready;
      expect(
        container2.read(personaAuthorizationProvider).isAuthorized,
        isTrue,
      );

      await container.read(personaAuthorizationProvider.notifier).revoke();
      expect(
        container.read(personaAuthorizationProvider).isAuthorized,
        isFalse,
      );
    });
  });

  group('generatePersonaReply', () {
    testWidgets('returns not-authorized error before calling upstream', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.sessionDao.createSession(id: 's1');
      await db.messageDao.insertMessage(
        id: 'm1',
        sessionId: 's1',
        role: 'user',
        content: '你好',
      );

      String? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () async {
                    result = await generatePersonaReply(
                      ref: ref,
                      sessionId: 's1',
                    );
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(result, contains('尚未授权'));
      // 未授权时不应落库 assistant 消息。
      final messages = await db.messageDao.getMessagesBySession('s1');
      expect(messages.where((m) => m.role == 'assistant'), isEmpty);
    });
  });
}
