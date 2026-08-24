class ModelContextBudget {
  const ModelContextBudget({
    required this.contextWindowTokens,
    required this.reservedOutputTokens,
    required this.maxInputTokens,
  });

  final int contextWindowTokens;
  final int reservedOutputTokens;
  final int maxInputTokens;
}

ModelContextBudget resolveModelContextBudget({
  required String protocol,
  required String modelName,
  int? reservedOutputTokens,
}) {
  final contextWindow = _inferContextWindowTokens(protocol, modelName);
  final reserve =
      (reservedOutputTokens ?? _defaultReservedOutput(contextWindow))
          .clamp(512, contextWindow ~/ 2)
          .toInt();
  final safetyInputLimit = (contextWindow * 0.90).floor();
  final hardInputLimit = contextWindow - reserve;
  final maxInput = hardInputLimit < safetyInputLimit
      ? hardInputLimit
      : safetyInputLimit;
  return ModelContextBudget(
    contextWindowTokens: contextWindow,
    reservedOutputTokens: reserve,
    maxInputTokens: maxInput > 0 ? maxInput : 1,
  );
}

int dynamicCompressThresholdForBudget(
  ModelContextBudget budget,
  int userThreshold,
) {
  final target = (budget.maxInputTokens * 0.50).floor().clamp(2000, 80000);
  return userThreshold > target ? userThreshold : target.toInt();
}

int _defaultReservedOutput(int contextWindow) {
  if (contextWindow <= 8192) return 2048;
  if (contextWindow <= 32768) return 4096;
  return 8192;
}

int _inferContextWindowTokens(String protocol, String modelName) {
  final protocolKey = protocol.toLowerCase();
  final model = modelName.toLowerCase();

  // SimiChat 的默认低成本模型明确按有限窗口处理。即使自定义网关没有在
  // protocol 名称中包含 openai，也必须在客户端 128K 边界前开始滚动摘要，
  // 不能把“长期本地会话”误当成上游拥有无限输入窗口。
  if (model.split('/').last == 'gpt-5.3-codex-spark') {
    return 128000;
  }

  if (model.contains('1m') ||
      model.contains('1000k') ||
      model.contains('gpt-4.1') ||
      model.contains('gemini-1.5') ||
      model.contains('gemini-2.0') ||
      model.contains('gemini-2.5')) {
    return 1000000;
  }

  if (protocolKey.contains('claude') || model.contains('claude')) {
    return 200000;
  }

  if (model.contains('200k')) return 200000;
  if (model.contains('gpt-3.5')) return 16384;
  if (model == 'gpt-4' || model == 'gpt-4-0314' || model == 'gpt-4-0613') {
    return 8192;
  }
  if (model.contains('128k') ||
      model.contains('gpt-4o') ||
      model.contains('gpt-4-turbo') ||
      _hasDelimitedModelToken(model, 'o1') ||
      _hasDelimitedModelToken(model, 'o3') ||
      _hasDelimitedModelToken(model, 'o4')) {
    return 128000;
  }
  if (model.contains('64k') ||
      model.contains('deepseek') ||
      model.contains('qwen')) {
    return 64000;
  }
  if (model.contains('32k')) return 32768;
  if (model.contains('16k')) return 16384;
  if (model.contains('8k')) return 8192;

  if (protocolKey.contains('gemini')) return 1000000;
  if (protocolKey.contains('openai')) return 128000;
  if (protocolKey.contains('ollama')) return 8192;

  return 8192;
}

/// OpenAI o 系列短代号必须是独立模型 token。
///
/// 直接 `contains('o1')` 会把 `foo1`、`mirror1` 等普通名称错误提升到
/// 128K 上下文，进而延后压缩并增加真实小窗口模型的超限风险。
bool _hasDelimitedModelToken(String modelName, String token) {
  return RegExp(
    '(^|[^a-z0-9])${RegExp.escape(token)}([^a-z0-9]|\$)',
  ).hasMatch(modelName);
}
