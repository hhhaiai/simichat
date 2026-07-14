import 'dart:convert';

import 'package:ai_chat_app/core/archive/structured_data_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('StructuredDataBackupService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('exports only whitelisted local preferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('key_point_memory_v1', '[{"id":"m1"}]');
      await prefs.setString('dreaming_digest_v1', '{"summary":"夜间整理"}');
      await prefs.setString(
        'dreaming_digest_history_v1',
        '[{"dayKey":"2026-07-06"}]',
      );
      await prefs.setString(
        'dreaming_schedule_v1',
        '{"enabled":true,"hour":22,"minute":0,"requiresCharging":true,"requiresUnmeteredNetwork":true}',
      );
      await prefs.setString('user_profile_v1', '{"summary":"用户画像"}');
      await prefs.setString('assistant_reflection_v1', '{"summary":"本地反思"}');
      await prefs.setString(
        'assistant_reflection_history_v1',
        '[{"dayKey":"2026-07-06"}]',
      );
      await prefs.setBool('assistant_reflection_prompt_enabled_v1', false);
      await prefs.setBool('assistant_reflection_model_enabled_v1', true);
      await prefs.setBool('user_profile_model_enabled_v1', true);
      await prefs.setString(
        'assistant_reflection_pending_v1',
        '{"sourceDigestDayKey":"2026-07-06","updatedAt":"2026-07-06T22:00:00Z","attemptCount":1}',
      );
      await prefs.setDouble('font_scale', 1.15);
      await prefs.setBool('semantic_search_enabled', false);
      await prefs.setString('channel_api_key', 'fake-key-should-never-export');

      final bytes = await StructuredDataBackupService(
        now: () => DateTime.utc(2026, 6, 27),
      ).exportSharedPreferences();

      expect(bytes, isNotNull);
      final payload = jsonDecode(utf8.decode(bytes!));
      expect(payload['format'], kStructuredDataFormat);
      expect(payload['privacy']['contains_model_api_keys'], isFalse);
      expect(
        payload['values'],
        containsPair('key_point_memory_v1', isA<Map>()),
      );
      expect(payload['values'], containsPair('dreaming_digest_v1', isA<Map>()));
      expect(
        payload['values'],
        containsPair('dreaming_digest_history_v1', isA<Map>()),
      );
      final scheduleValue =
          payload['values']['dreaming_schedule_v1']['value'] as String;
      expect(jsonDecode(scheduleValue), containsPair('requiresCharging', true));
      expect(
        jsonDecode(scheduleValue),
        containsPair('requiresUnmeteredNetwork', true),
      );
      expect(payload['values'], containsPair('user_profile_v1', isA<Map>()));
      expect(
        payload['values'],
        containsPair('assistant_reflection_v1', isA<Map>()),
      );
      expect(
        payload['values'],
        containsPair('assistant_reflection_history_v1', isA<Map>()),
      );
      expect(
        payload['values'],
        containsPair('assistant_reflection_prompt_enabled_v1', isA<Map>()),
      );
      expect(
        payload['values'],
        containsPair('assistant_reflection_model_enabled_v1', isA<Map>()),
      );
      expect(
        payload['values'],
        containsPair('user_profile_model_enabled_v1', isA<Map>()),
      );
      expect(
        payload['values'],
        containsPair('assistant_reflection_pending_v1', isA<Map>()),
      );
      expect(payload['values'], containsPair('font_scale', isA<Map>()));
      expect(
        payload['values'],
        containsPair('semantic_search_enabled', isA<Map>()),
      );
      expect(payload['values'], isNot(contains('channel_api_key')));
      expect(
        jsonEncode(payload),
        isNot(contains('fake-key-should-never-export')),
      );
    });

    test('returns null when no whitelisted preferences exist', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('channel_api_key', 'fake-key-should-never-export');

      final bytes = await const StructuredDataBackupService()
          .exportSharedPreferences();

      expect(bytes, isNull);
    });

    test('restores supported values and respects overwrite policy', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('key_point_memory_v1', '旧记忆');
      final bytes = utf8.encode(
        jsonEncode({
          'format': kStructuredDataFormat,
          'values': {
            'key_point_memory_v1': {'type': 'string', 'value': '新记忆'},
            'font_scale': {'type': 'double', 'value': 1.3},
            'semantic_search_enabled': {'type': 'bool', 'value': false},
            'assistant_reflection_prompt_enabled_v1': {
              'type': 'bool',
              'value': false,
            },
            'assistant_reflection_model_enabled_v1': {
              'type': 'bool',
              'value': true,
            },
            'user_profile_model_enabled_v1': {'type': 'bool', 'value': true},
            'assistant_reflection_history_v1': {
              'type': 'string',
              'value': '[{"dayKey":"2026-07-06"}]',
            },
            'assistant_reflection_pending_v1': {
              'type': 'string',
              'value':
                  '{"sourceDigestDayKey":"2026-07-06","updatedAt":"2026-07-06T22:00:00Z","attemptCount":1}',
            },
            'dreaming_digest_history_v1': {
              'type': 'string',
              'value': '[{"dayKey":"2026-07-06"}]',
            },
            'dreaming_schedule_v1': {
              'type': 'string',
              'value':
                  '{"enabled":true,"hour":22,"minute":0,"requiresCharging":true,"requiresUnmeteredNetwork":true}',
            },
            'system_prompts': {'type': 'string', 'value': '{"s1":"prompt"}'},
            'not_allowed_key': {'type': 'string', 'value': 'skip'},
          },
        }),
      );

      final service = const StructuredDataBackupService();
      final preview = service.previewSharedPreferences(bytes);
      expect(preview.supportedKeys, 11);
      expect(preview.unsupportedKeys, 1);

      final first = await service.restoreSharedPreferences(bytes);
      expect(first.restoredKeys, 10);
      expect(first.skippedExistingKeys, 1);
      expect(first.skippedUnsupportedKeys, 1);
      expect(prefs.getString('key_point_memory_v1'), '旧记忆');
      expect(prefs.getDouble('font_scale'), 1.3);
      expect(prefs.getBool('semantic_search_enabled'), isFalse);
      expect(prefs.getBool('assistant_reflection_prompt_enabled_v1'), isFalse);
      expect(prefs.getBool('assistant_reflection_model_enabled_v1'), isTrue);
      expect(prefs.getBool('user_profile_model_enabled_v1'), isTrue);
      expect(
        prefs.getString('assistant_reflection_history_v1'),
        '[{"dayKey":"2026-07-06"}]',
      );
      expect(
        prefs.getString('assistant_reflection_pending_v1'),
        '{"sourceDigestDayKey":"2026-07-06","updatedAt":"2026-07-06T22:00:00Z","attemptCount":1}',
      );
      expect(
        prefs.getString('dreaming_digest_history_v1'),
        '[{"dayKey":"2026-07-06"}]',
      );
      expect(
        prefs.getString('dreaming_schedule_v1'),
        contains('"requiresCharging":true'),
      );
      expect(prefs.getString('system_prompts'), '{"s1":"prompt"}');
      expect(prefs.containsKey('not_allowed_key'), isFalse);

      final second = await service.restoreSharedPreferences(
        bytes,
        overwriteExisting: true,
      );
      expect(second.restoredKeys, 11);
      expect(second.skippedExistingKeys, 0);
      expect(second.skippedUnsupportedKeys, 1);
      expect(prefs.getString('key_point_memory_v1'), '新记忆');
    });

    test('throws on unsupported payload format', () async {
      final bytes = utf8.encode(jsonEncode({'format': 'bad', 'values': {}}));

      expect(
        () =>
            const StructuredDataBackupService().previewSharedPreferences(bytes),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        const StructuredDataBackupService().restoreSharedPreferences(bytes),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
