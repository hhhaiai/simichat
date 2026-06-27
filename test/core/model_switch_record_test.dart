import 'package:ai_chat_app/core/ai/model_switch_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildModelSwitchRecordContent records old and new model labels', () {
    final content = buildModelSwitchRecordContent(
      fromLabel: 'OpenAI / gpt-4o',
      toLabel: 'Claude / sonnet',
    );

    expect(content, contains('OpenAI / gpt-4o'));
    expect(content, contains('Claude / sonnet'));
    expect(content, contains('后续回复将默认使用 Claude / sonnet'));
  });

  test('resolveModelSwitchLabel falls back to unselected label', () {
    expect(resolveModelSwitchLabel(null), '未选择模型');
    expect(resolveModelSwitchLabel('   '), '未选择模型');
    expect(resolveModelSwitchLabel(' Gemini / pro '), 'Gemini / pro');
  });
}
