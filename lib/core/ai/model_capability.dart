/// Model capability labels used to keep chat, embedding, and future model types
/// separated in generic OpenAI-compatible providers.
abstract final class ModelCapability {
  static const chat = 'chat';
  static const vision = 'vision';
  static const embedding = 'embedding';

  /// 深度思考（推理）模型：如 deepseek-reasoner / o 系列。
  static const reasoner = 'reasoner';

  static const all = {chat, vision, embedding, reasoner};

  static const _reasonerHints = [
    'reasoner',
    'reasoning',
    'deep-think',
    'deepthink',
    'think',
  ];

  /// 短模型代号必须按分隔符匹配。直接用 `contains('o1')` / `contains('r1')`
  /// 会把 `foo1`、`mirror1` 之类普通模型误判为推理模型。
  static const _reasonerShortTokens = ['o1', 'o3', 'o4', 'r1'];

  static const _visionHints = [
    'vision',
    'multimodal',
    'llava',
    'pixtral',
    'qwen-vl',
    'qwen2-vl',
    'qwen2.5-vl',
    'gpt-4o',
    'gpt-4.1',
    'gemini',
    'claude-3',
    'claude-sonnet-4',
    'claude-opus-4',
  ];

  static String normalize(String? value) {
    if (value == null) return chat;
    final lowered = value.trim().toLowerCase();
    return all.contains(lowered) ? lowered : chat;
  }

  static bool isChat(String? value) {
    final normalized = normalize(value);
    return normalized == chat || normalized == vision || normalized == reasoner;
  }

  static bool isVision(String? value) => normalize(value) == vision;
  static bool isEmbedding(String? value) => normalize(value) == embedding;
  static bool isReasoner(String? value) => normalize(value) == reasoner;

  /// Vision 与 Reasoner 是可重叠能力，不能只依赖单值 [inferFromModel]。
  static bool supportsVisionModel({
    required String? capability,
    required String modelId,
  }) {
    // 显式 Embedding 能力优先级高于宽泛的名称提示。例如
    // `gemini-embedding-001` 含有 `gemini`，但不能接收图片消息。
    if (isEmbedding(capability)) return false;
    final id = modelId.toLowerCase();
    return isVision(capability) ||
        _visionHints.any(id.contains) ||
        id.contains('-vl') ||
        id.contains('_vl') ||
        id.contains('/vl');
  }

  /// 判断模型是否支持深度思考，同时兼容显式能力标签和常见模型名。
  static bool supportsReasonerModel({
    required String? capability,
    required String modelId,
  }) {
    // 避免 `think-embedding-*` 等向量模型仅因名称命中 reasoner hint。
    if (isEmbedding(capability)) return false;
    final id = modelId.toLowerCase();
    return isReasoner(capability) || _hasReasonerNameHint(id);
  }

  /// Conservative capability inference for OpenAI-compatible `/v1/models`.
  /// Providers vary widely in metadata shape, so prefer explicit metadata when
  /// present and fall back to common embedding / vision model naming patterns.
  static String inferFromModel(
    String modelId, {
    Map<String, dynamic>? metadata,
  }) {
    final explicit = _explicitCapability(metadata);
    if (explicit != null) return explicit;

    final id = modelId.toLowerCase();
    if (_hasReasonerNameHint(id)) return reasoner;

    final embeddingHints = [
      'embedding',
      'embed',
      'bge-',
      'bge_',
      'bge/',
      'e5-',
      'e5_',
      'text-embedding',
      'gte-',
      'jina-embeddings',
    ];
    if (embeddingHints.any(id.contains)) return embedding;

    if (_visionHints.any(id.contains) ||
        id.contains('-vl') ||
        id.contains('_vl') ||
        id.contains('/vl')) {
      return vision;
    }

    return chat;
  }

  static String? _explicitCapability(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    for (final key in ['capability', 'type', 'model_type', 'task']) {
      final raw = metadata[key]?.toString().toLowerCase();
      if (raw == null) continue;
      if (raw.contains('reasoner') ||
          raw.contains('reasoning') ||
          raw.contains('deep-think') ||
          raw.contains('deepthink')) {
        return reasoner;
      }
      if (raw.contains('vision') ||
          raw.contains('image') ||
          raw.contains('multimodal') ||
          raw.contains('multi-modal') ||
          raw.contains('vl')) {
        return vision;
      }
      if (raw.contains('embed')) return embedding;
      if (raw.contains('chat') || raw.contains('completion')) return chat;
    }

    final capabilities = metadata['capabilities'];
    if (capabilities is List) {
      final lowered = capabilities
          .map((e) => e.toString().toLowerCase())
          .toList();
      if (lowered.any(
        (e) =>
            e.contains('reasoner') ||
            e.contains('reasoning') ||
            e.contains('deep-think') ||
            e.contains('deepthink'),
      )) {
        return reasoner;
      }
      if (lowered.any((e) => e.contains('embed'))) {
        return embedding;
      }
      if (lowered.any(
        (e) =>
            e.contains('vision') ||
            e.contains('image') ||
            e.contains('multimodal') ||
            e.contains('multi-modal') ||
            e.contains('vl'),
      )) {
        return vision;
      }
      if (lowered.any((e) => e.contains('chat') || e.contains('completion'))) {
        return chat;
      }
    }
    return null;
  }

  static bool _hasReasonerNameHint(String loweredModelId) {
    if (_reasonerHints.any(loweredModelId.contains)) return true;
    for (final token in _reasonerShortTokens) {
      final match = RegExp(
        '(^|[^a-z0-9])${RegExp.escape(token)}([^a-z0-9]|\$)',
      );
      if (match.hasMatch(loweredModelId)) return true;
    }
    return false;
  }

  static String label(String capability) {
    switch (normalize(capability)) {
      case embedding:
        return 'Embedding 向量';
      case vision:
        return 'Vision 视觉';
      case reasoner:
        return 'Reasoner 深度思考';
      case chat:
      default:
        return 'Chat 对话';
    }
  }
}
