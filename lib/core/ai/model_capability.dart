/// Model capability labels used to keep chat, embedding, and future model types
/// separated in generic OpenAI-compatible providers.
abstract final class ModelCapability {
  static const chat = 'chat';
  static const embedding = 'embedding';

  static const all = {chat, embedding};

  static String normalize(String? value) {
    if (value == null) return chat;
    final lowered = value.trim().toLowerCase();
    return all.contains(lowered) ? lowered : chat;
  }

  static bool isChat(String? value) => normalize(value) == chat;
  static bool isEmbedding(String? value) => normalize(value) == embedding;

  /// Conservative capability inference for OpenAI-compatible `/v1/models`.
  /// Providers vary widely in metadata shape, so prefer explicit metadata when
  /// present and fall back to common embedding model naming patterns.
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
    return chat;
  }

  static String? _explicitCapability(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    for (final key in ['capability', 'type', 'model_type', 'task']) {
      final raw = metadata[key]?.toString().toLowerCase();
      if (raw == null) continue;
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
      if (lowered.any((e) => e.contains('chat') || e.contains('completion'))) {
        return chat;
      }
    }
    return null;
  }

  static String label(String capability) {
    switch (normalize(capability)) {
      case embedding:
        return 'Embedding';
      case chat:
      default:
        return 'Chat';
    }
  }
}
