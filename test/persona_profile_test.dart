import 'package:ai_chat_app/core/memory/user_profile.dart';
import 'package:ai_chat_app/core/twin/persona_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PersonaProfileGenerator', () {
    test('builds persona from user profile signals', () {
      final profile = UserProfile(
        updatedAt: DateTime(2026, 1, 1),
        sourceCount: 1,
        preferences: const ['喜欢简洁回复'],
        goals: const ['提升英语'],
        tasks: const ['完成项目 X'],
        profileFacts: const [],
        styleSignals: const ['习惯先总结再展开'],
        scheduleSignals: const ['熬夜型'],
        keywords: const ['Flutter', 'Dart'],
        conflicts: const [],
        digestDayKey: '2026-01-01',
      );

      final persona = const PersonaProfileGenerator().fromUserProfile(profile);
      final prompt = persona.buildPersonaSystemPrompt();

      expect(prompt, contains('数字孪生'));
      expect(prompt, contains('习惯先总结再展开'));
      expect(prompt, contains('熬夜型'));
      expect(prompt, contains('完成项目 X'));
      expect(persona.isEmpty, isFalse);
    });
  });

  group('MediaPersonaAnalyzer', () {
    test('counts emoji and attachment signals', () {
      final signals = const MediaPersonaAnalyzer().analyze(
        messageContents: const ['今天很开心 😄😄', '好 👍', '普通文本'],
        audioAttachmentCount: 3,
        imageAttachmentCount: 1,
      );

      expect(signals.emojiCount, 3);
      expect(signals.messageCount, 3);
      expect(signals.prefersVoice, isTrue);
      expect(signals.topEmoji, containsPair('😄', 2));
      expect(signals.describe(), contains('表情'));
      expect(signals.describe(), contains('语音'));
    });

    test('image-heavy profile prefers image', () {
      final signals = const MediaPersonaAnalyzer().analyze(
        messageContents: const ['看图'],
        audioAttachmentCount: 0,
        imageAttachmentCount: 5,
      );
      expect(signals.prefersImage, isTrue);
    });

    test('empty inputs produce empty signals', () {
      final signals = const MediaPersonaAnalyzer().analyze(
        messageContents: const [],
        audioAttachmentCount: 0,
        imageAttachmentCount: 0,
      );
      expect(signals.isEmpty, isTrue);
    });
  });
}
