/// Model capability labels used to keep chat, embedding, and future model types
/// separated in generic OpenAI-compatible providers.
abstract final class ModelCapability {
  static const chat = 'chat';
  static const vision = 'vision';
  static const embedding = 'embedding';

  static const all = {chat, vision, embedding};

  static String normalize(String? value) {
    if (value == null) return chat;
    final lowered = value.trim().toLowerCase();
    return all.contains(lowered) ? lowered : chat;
  }

  static bool isChat(String? value) {
    final normalized = normalize(value);
    return normalized == chat || normalized == vision;
  }

  static bool isVision(String? value) => normalize(value) == vision;
  static bool isEmbedding(String? value) => normalize(value) == embedding;

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

    final visionHints = [
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
    if (visionHints.any(id.contains) ||
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

  static String label(String capability) {
    switch (normalize(capability)) {
      case embedding:
        return 'Embedding 向量';
      case vision:
        return 'Vision 视觉';
      case chat:
      default:
        return 'Chat 对话';
    }
  }
}
