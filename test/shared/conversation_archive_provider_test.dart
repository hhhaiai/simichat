import 'package:ai_chat_app/shared/providers/conversation_archive_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArchiveRepairQueueNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('records, persists, and clears failures', () async {
      final notifier = ArchiveRepairQueueNotifier();
      addTearDown(notifier.dispose);

      await notifier.recordFailure(
        sessionId: 's1',
        operation: 'append-user',
        error: Exception('disk full'),
      );
      expect(notifier.state, hasLength(1));
      expect(notifier.state.single.sessionId, 's1');
      expect(notifier.state.single.operation, 'append-user');

      final restored = ArchiveRepairQueueNotifier();
      addTearDown(restored.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(restored.state, hasLength(1));
      expect(restored.state.single.sessionId, 's1');

      await restored.clearSession('s1');
      expect(restored.state, isEmpty);
    });

    test('deduplicates failures by session and operation', () async {
      final notifier = ArchiveRepairQueueNotifier();
      addTearDown(notifier.dispose);

      await notifier.recordFailure(
        sessionId: 's1',
        operation: 'append-user',
        error: Exception('disk full'),
      );
      await notifier.recordFailure(
        sessionId: 's1',
        operation: 'append-user',
        error: Exception('permission denied'),
      );
      await notifier.recordFailure(
        sessionId: 's1',
        operation: 'append-assistant',
        error: Exception('disk full'),
      );

      expect(notifier.state, hasLength(2));
      expect(notifier.state.first.operation, 'append-assistant');
      expect(notifier.state.last.operation, 'append-user');
      expect(notifier.state.last.error, contains('permission denied'));
    });

    test('uniqueArchiveRepairSessionIds keeps first queue order', () {
      final now = DateTime(2026, 6, 27);
      final sessions = uniqueArchiveRepairSessionIds([
        ArchiveRepairItem(
          sessionId: 's1',
          operation: 'append-user',
          error: 'e1',
          createdAt: now,
        ),
        ArchiveRepairItem(
          sessionId: 's2',
          operation: 'append-user',
          error: 'e2',
          createdAt: now,
        ),
        ArchiveRepairItem(
          sessionId: 's1',
          operation: 'append-assistant',
          error: 'e3',
          createdAt: now,
        ),
      ]);

      expect(sessions, ['s1', 's2']);
    });
  });
}
