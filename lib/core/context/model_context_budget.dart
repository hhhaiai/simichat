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
      model.contains('o1') ||
      model.contains('o3') ||
      model.contains('o4')) {
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
