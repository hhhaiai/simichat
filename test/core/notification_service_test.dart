import 'package:ai_chat_app/core/notification/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildStableNotificationId', () {
    test('为同一命名空间和 key 生成跨运行稳定的正整数 ID', () {
      final first = buildStableNotificationId('response', '默认会话');
      final second = buildStableNotificationId('response', '默认会话');

      expect(first, second);
      expect(first, greaterThan(0));
      expect(first, lessThanOrEqualTo(kNotificationIdMask));
    });

    test('区分不同命名空间或 key，避免回复和 Dreaming 通知互相覆盖', () {
      final responseId = buildStableNotificationId('response', '2026-06-27');
      final dreamingId = buildStableNotificationId('dreaming', '2026-06-27');
      final nextDayDreamingId = buildStableNotificationId(
        'dreaming',
        '2026-06-28',
      );

      expect(responseId, isNot(dreamingId));
      expect(dreamingId, isNot(nextDayDreamingId));
    });
  });

  group('buildResponseNotificationBody', () {
    test('空内容使用默认回复完成文案', () {
      expect(buildResponseNotificationBody(null), 'AI 已完成回复');
      expect(buildResponseNotificationBody('   \n\t  '), 'AI 已完成回复');
    });

    test('压缩空白并截断过长预览', () {
      expect(buildResponseNotificationBody('第一行\n\n第二行\t第三行'), '第一行 第二行 第三行');

      final body = buildResponseNotificationBody('我' * 120);
      expect(body, endsWith('...'));
      expect(body.length, 83);
    });
  });

  group('buildDreamingDigestNotificationBody', () {
    test('没有可整理消息时提示今天暂无内容', () {
      expect(
        buildDreamingDigestNotificationBody(
          originalMessageCount: 0,
          memoryCandidateCount: 3,
          profileProposalCount: 2,
        ),
        '今天暂无可整理对话',
      );
    });

    test('展示整理消息数、记忆候选和待确认画像变更', () {
      final body = buildDreamingDigestNotificationBody(
        originalMessageCount: 12,
        memoryCandidateCount: 4,
        profileProposalCount: 2,
      );

      expect(body, contains('已整理 12 条消息'));
      expect(body, contains('提取 4 条记忆候选'));
      expect(body, contains('生成 2 个待确认画像变更'));
    });
  });
}
