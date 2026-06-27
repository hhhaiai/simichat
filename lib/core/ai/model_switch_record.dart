const String kModelSwitchMessageType = 'model_switch';

String resolveModelSwitchLabel(String? label) {
  final trimmed = label?.trim();
  return trimmed == null || trimmed.isEmpty ? '未选择模型' : trimmed;
}

String buildModelSwitchRecordContent({
  required String? fromLabel,
  required String toLabel,
}) {
  final from = resolveModelSwitchLabel(fromLabel);
  final to = resolveModelSwitchLabel(toLabel);
  return '已切换模型：$from → $to\n后续回复将默认使用 $to。';
}
