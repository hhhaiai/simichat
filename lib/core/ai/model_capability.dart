/// Model capability labels used to keep chat, embedding, and media models
/// separate in model catalogs.  `vision` means that a model can consume image
/// input as part of a chat request; `image` means image generation and must
/// not be confused with vision.
abstract final class ModelCapability {
  static const chat = 'chat';
  static const vision = 'vision';
  static const embedding = 'embedding';
  static const image = 'image';
  static const audio = 'audio';

  /// Explicit audio task capabilities. `audio` remains a compatibility
  /// umbrella for imported models, while these labels let the UI route a
  /// model without inspecting its display name.
  static const tts = 'tts';
  static const asr = 'asr';
  static const voiceDesign = 'voice_design';
  static const voiceClone = 'voice_clone';
  static const video = 'video';
  static const music = 'music';

  /// 深度思考（推理）模型：如 deepseek-reasoner / o 系列。
  static const reasoner = 'reasoner';

  /// 重排模型：对候选文档按与查询的相关性打分排序。
  static const rerank = 'rerank';

  static const all = {
    chat,
    vision,
    embedding,
    image,
    reasoner,
    audio,
    tts,
    asr,
    voiceDesign,
    voiceClone,
    video,
    music,
    rerank,
  };

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

  /// These are chat models with image input, not image-generation models.
  static const _visionHints = [
    'llava',
    'pixtral',
    'qwen-vl',
    'qwen2-vl',
    'qwen2.5-vl',
    'gpt-4o',
    'gpt-4.1',
    // GPT-5 全系（gpt-5.4 / gpt-5.5 / gpt-5.6-terra 等）支持图片输入。
    'gpt-5',
    'grok-2-vision',
  ];

  /// SimiRouter exposes these exact models through OpenAI-compatible chat
  /// protocols. Keep the exception equality-based: TTS/ASR/voice models and
  /// provider-qualified or suffixed ids must not inherit chat Vision.
  static const _simiRouterMimoChatModelIds = {
    'mimo-v2.5-chat',
    'mimo-v2.5-pro-chat',
  };
  static const _simiRouterMimoVisionProtocols = {
    'openai_chat',
    'openai_response',
  };

  /// Dedicated non-chat model families.  Deliberately do not include a bare
  /// `image`, `video`, or `audio` token: an opaque model id is not enough
  /// evidence, and names such as `audio4` have historically been chat models.
  static const _imageGenerationHints = [
    'dall-e',
    'gpt-image',
    'imagen-',
    'imagen/',
    'stable-diffusion',
    'stable_diffusion',
    'image-generation',
    'image_generation',
    'imagegen',
    'flux-',
    'flux.',
    'grok-2-image',
    'grok-imagine-image',
  ];

  static const _videoGenerationHints = [
    'sora-',
    'sora/',
    'veo-',
    'video-generation',
    'video_generation',
    'grok-imagine-video',
    'wan-video',
  ];

  static const _musicGenerationHints = [
    'musicgen',
    'music-generation',
    'music_generation',
    'lyria-',
  ];

  static const _audioModelHints = [
    'whisper',
    'transcri',
    'speech-to-text',
    'speech_to_text',
    'text-to-speech',
    'text_to_speech',
    'asr-',
    '-asr',
    'stt',
    '-stt',
    'tts-',
    '-tts',
    'grok-voice',
  ];

  static const _embeddingHints = [
    'embedding',
    'embed',
    'bge-',
    'bge_',
    'bge/',
    'e5-',
    'e5_',
    'e5/',
    'text-embedding',
    'gte-',
    'gte/',
    'jina-embeddings',
    'nomic-embed',
    'mxbai-embed',
    'arctic-embed',
  ];

  /// Rerank 是独立能力而非否决项；但 rerank 名字仍否决聊天选择
  /// （见 `_hasDedicatedNonChatNameHint`）。
  static const _nonChatServiceHints = ['moderation'];

  static const _rerankHints = ['rerank', 're-rank', 're_rank', 'colbert'];

  /// Normalize a persisted capability.  Unknown values intentionally retain
  /// the historical `chat` fallback for old database rows; callers that need
  /// a strict selector decision should use [isChatSelectableModel].
  static String normalize(String? value) {
    if (value == null) return chat;
    final lowered = value.trim().toLowerCase();
    return switch (lowered) {
      'completion' ||
      'completions' ||
      'text-generation' ||
      'text_generation' => chat,
      'multimodal' || 'image-input' || 'image_input' => vision,
      'image-generation' || 'image_generation' || 'imagegen' => image,
      'speech' || 'stt' || 'transcription' => audio,
      'tts' || 'text-to-speech' || 'text_to_speech' => tts,
      'asr' || 'speech-to-text' || 'speech_to_text' => asr,
      'voice-design' || 'voice_design' || 'voicedesign' => voiceDesign,
      'voice-clone' || 'voice_clone' || 'voiceclone' => voiceClone,
      'audio-generation' || 'audio_generation' => music,
      'rerank' || 're-rank' || 're_rank' || 'reranker' => rerank,
      _ when all.contains(lowered) => lowered,
      _ => chat,
    };
  }

  static bool isChat(String? value) {
    final normalized = normalize(value);
    return normalized == chat || normalized == vision || normalized == reasoner;
  }

  static bool isVision(String? value) => normalize(value) == vision;
  static bool isEmbedding(String? value) => normalize(value) == embedding;
  static bool isImage(String? value) => normalize(value) == image;
  static bool isReasoner(String? value) => normalize(value) == reasoner;
  static bool isAudio(String? value) => normalize(value) == audio;
  static bool isTts(String? value) => normalize(value) == tts;
  static bool isAsr(String? value) => normalize(value) == asr;
  static bool isVoiceDesign(String? value) => normalize(value) == voiceDesign;
  static bool isVoiceClone(String? value) => normalize(value) == voiceClone;
  static bool isVideo(String? value) => normalize(value) == video;
  static bool isMusic(String? value) => normalize(value) == music;
  static bool isRerank(String? value) => normalize(value) == rerank;

  /// Resolve the default voice task for legacy rows that only persisted the
  /// umbrella `audio` capability. Explicit capability metadata always wins;
  /// the narrow model-family hints are kept here, in the central capability
  /// registry, rather than scattered through widgets and request builders.
  static String voiceCapabilityForModel({
    required String modelId,
    required Set<String> capabilities,
  }) {
    final normalized = capabilities.map(normalize).toSet();
    for (final explicit in <String>[asr, music, voiceDesign, voiceClone, tts]) {
      if (normalized.contains(explicit)) return explicit;
    }
    final id = modelId.trim().toLowerCase();
    if (id.contains('asr') ||
        id.contains('stt') ||
        id.contains('whisper') ||
        id.contains('transcri') ||
        id.contains('speech-to-text') ||
        id.contains('speech_to_text')) {
      return asr;
    }
    if (id.contains('music') ||
        id.contains('lyria') ||
        id.contains('musicgen')) {
      return music;
    }
    if (id.contains('voiceclone') || id.contains('voice-clone')) {
      return voiceClone;
    }
    if (id.contains('voicedesign') || id.contains('voice-design')) {
      return voiceDesign;
    }
    return tts;
  }

  /// Return whether the model can accept an image in a normal chat request.
  /// Explicit non-chat capabilities veto broad model-name hints.
  static bool supportsVisionModel({
    required String? capability,
    required String modelId,
    Set<String>? capabilities,
    String? protocol,
  }) {
    final known = _knownCapability(capability);
    if (known == embedding ||
        known == image ||
        known == audio ||
        known == video ||
        known == music ||
        known == rerank) {
      return false;
    }
    final knownCapabilities = capabilities?.map(_knownCapability).toSet();
    if (knownCapabilities?.contains(vision) == true) return true;
    if (knownCapabilities?.contains(embedding) == true &&
        knownCapabilities?.contains(vision) != true) {
      return false;
    }
    final id = _lowerModelId(modelId);
    final hasExplicitVision =
        known == vision || knownCapabilities?.contains(vision) == true;
    if (hasExplicitVision) return true;

    // Apply the same dedicated-model veto to protocol fallbacks as to the
    // ordinary name heuristic. Otherwise a broad provider family such as
    // `grok-*` or `gemini-*` can accidentally turn an image-generation,
    // audio, video, or embedding model into a chat Vision candidate.
    final hasDedicatedCapability =
        known == embedding ||
        known == image ||
        known == audio ||
        known == video ||
        known == music ||
        known == rerank ||
        knownCapabilities?.contains(embedding) == true ||
        knownCapabilities?.contains(image) == true ||
        knownCapabilities?.contains(audio) == true ||
        knownCapabilities?.contains(video) == true ||
        knownCapabilities?.contains(music) == true ||
        knownCapabilities?.contains(rerank) == true;
    if (hasDedicatedCapability || _hasDedicatedNonChatNameHint(id)) {
      return false;
    }

    if (_isExactSimiRouterMimoChatVision(
      capability: capability,
      modelId: modelId,
      protocol: protocol,
    )) {
      return true;
    }

    return _protocolVisionHint(protocol, id) ||
        (_isChatSelectableName(id) &&
            (_visionHints.any(id.contains) ||
                id.contains('-vl') ||
                id.contains('_vl') ||
                id.contains('/vl')));
  }

  /// Return whether the app has a verified model-level native file contract
  /// for the requested attachment. The OpenAI Responses adapter has a
  /// first-class `input_file` part for PDF and ordinary document payloads,
  /// but SimiRouter's exact `mimo-v2.5-chat` chat model is not verified to
  /// accept that part. Keep this exception narrow so generic
  /// `openai_response` file support remains available.
  static bool supportsVerifiedNativeFile({
    required String? capability,
    required String modelId,
    required String protocol,
    required String attachmentType,
  }) {
    final type = attachmentType.trim().toLowerCase();
    final normalizedProtocol = protocol.trim().toLowerCase();
    if ((type != 'pdf' && type != 'document') ||
        normalizedProtocol != 'openai_response') {
      return false;
    }
    return !_isExactSimiRouterMimoChatVision(
      capability: capability,
      modelId: modelId,
      protocol: normalizedProtocol,
    );
  }

  /// 判断模型是否支持深度思考，同时兼容显式能力标签和常见模型名。
  static bool supportsReasonerModel({
    required String? capability,
    required String modelId,
    Set<String>? capabilities,
  }) {
    final known = _knownCapability(capability);
    if (known == embedding ||
        known == image ||
        known == audio ||
        known == video ||
        known == music ||
        known == rerank) {
      return false;
    }
    final knownCapabilities = capabilities?.map(_knownCapability).toSet();
    if (knownCapabilities?.contains(reasoner) == true) return true;
    final id = _lowerModelId(modelId);
    return known == reasoner ||
        (_isChatSelectableName(id) && _hasReasonerNameHint(id));
  }

  /// Media capabilities are metadata-only. A protocol name or a model name
  /// such as `video-*` is not evidence that the endpoint can create
  /// video/music, so unknown models never pass these checks by inference.
  static bool supportsAudioModel({
    required String? capability,
    required String modelId,
    Set<String>? capabilities,
  }) => _supportsExplicitMedia(
    capability: capability,
    capabilities: capabilities,
    expected: audio,
  );

  static bool supportsVideoModel({
    required String? capability,
    required String modelId,
    Set<String>? capabilities,
  }) => _supportsExplicitMedia(
    capability: capability,
    capabilities: capabilities,
    expected: video,
  );

  static bool supportsMusicModel({
    required String? capability,
    required String modelId,
    Set<String>? capabilities,
  }) => _supportsExplicitMedia(
    capability: capability,
    capabilities: capabilities,
    expected: music,
  );

  /// Generic media check for callers that store the media kind dynamically.
  static bool supportsMediaModel({
    required String? capability,
    required String modelId,
    required String mediaType,
    Set<String>? capabilities,
  }) {
    final expected = normalizeMedia(mediaType);
    if (expected == null) return false;
    return _supportsExplicitMedia(
      capability: capability,
      capabilities: capabilities,
      expected: expected,
    );
  }

  static String? normalizeMedia(String? value) {
    switch (value?.trim().toLowerCase()) {
      case audio:
      case 'speech':
      case 'stt':
      case 'tts':
      case 'transcription':
        return audio;
      case video:
        return video;
      case music:
      case 'audio_generation':
      case 'audio-generation':
        return music;
      default:
        return null;
    }
  }

  /// Conservative capability inference for OpenAI-compatible `/v1/models`
  /// and model lists from Claude, Gemini, Ollama, xAI/Grok, and compatible
  /// gateways. Explicit metadata is preferred over naming heuristics.
  ///
  /// 中转站目录通常不带能力元数据：媒体模型名命中精心维护的前缀表时
  /// 推断为对应媒体能力（gpt-image-* / grok-imagine-image* / wan-video /
  /// mimo-v2.5-tts* / asr 等），避免被统一标成 chat 而进入聊天选择器。
  /// `supports*Model` 的"媒体能力只信显式元数据"门禁不受影响——目录
  /// 标签与请求门禁是两个层级。
  static String inferFromModel(
    String modelId, {
    Map<String, dynamic>? metadata,
  }) {
    final explicit = _explicitCapability(metadata);
    if (explicit != null) return explicit;

    final id = _lowerModelId(modelId);
    // rerank 检查必须先于 embedding：bge-reranker / gte-rerank 也命中
    // embedding hints（bge-/gte- 前缀）。
    if (_matchesAny(id, _rerankHints)) return rerank;
    if (_matchesAny(id, _embeddingHints)) return embedding;
    if (_matchesAny(id, _nonChatServiceHints)) return chat;
    if (_hasReasonerNameHint(id)) return reasoner;

    // 媒体模型名推断（先于 vision：grok-imagine-* 等不会命中 vision 表）。
    if (_matchesAny(id, _imageGenerationHints)) return image;
    if (_matchesAny(id, _videoGenerationHints)) return video;
    if (_matchesAny(id, _musicGenerationHints)) return music;
    if (_matchesAny(id, _audioModelHints)) return audio;

    if (_visionHints.any(id.contains) ||
        id.contains('-vl') ||
        id.contains('_vl') ||
        id.contains('/vl')) {
      return vision;
    }

    return chat;
  }

  /// Return the primary capability plus explicit secondary capabilities from
  /// provider metadata. A model with explicit `chat` + `video` remains a chat
  /// model with an optional media route; a media-only model stays out of the
  /// chat selector.
  static Set<String> capabilitiesFromMetadata(
    String modelId, {
    Map<String, dynamic>? metadata,
    bool inferFromModelName = true,
  }) {
    final result = <String>{};
    result.addAll(_explicitCapabilities(metadata));
    if (inferFromModelName) {
      result.add(inferFromModel(modelId, metadata: metadata));
    }
    if (result.isEmpty) result.add(chat);
    return result;
  }

  static String primaryCapability(
    String modelId, {
    Map<String, dynamic>? metadata,
    bool inferFromModelName = true,
  }) {
    final capabilities = capabilitiesFromMetadata(
      modelId,
      metadata: metadata,
      inferFromModelName: inferFromModelName,
    );
    final hasChat = capabilities.any((value) => isChat(value));
    if (hasChat) {
      if (capabilities.contains(vision)) return vision;
      if (capabilities.contains(reasoner)) return reasoner;
      return chat;
    }
    for (final preferred in [
      embedding,
      rerank,
      image,
      video,
      audio,
      music,
      vision,
      reasoner,
      chat,
    ]) {
      if (capabilities.contains(preferred)) return preferred;
    }
    return chat;
  }

  /// Strict selector predicate used by channel/model lists. This is separate
  /// from [isChat] so old unknown capability strings cannot silently turn a
  /// known image/video/embedding model into a chat option.
  static bool isChatSelectableModel({
    required String modelId,
    String? capability,
    Set<String>? capabilities,
    Map<String, dynamic>? metadata,
  }) {
    final id = _lowerModelId(modelId);
    if (id.isEmpty) return false;

    final knownPrimary = _knownCapability(capability);
    final knownCapabilities = <String>{
      if (capability != null) knownPrimary,
      ...?capabilities?.map(_knownCapability),
      ..._explicitCapabilities(metadata),
    };
    final inferred = inferFromModel(modelId, metadata: metadata);

    if (_hasDedicatedNonChatNameHint(id)) return false;
    if (knownPrimary == image ||
        knownPrimary == embedding ||
        knownPrimary == rerank ||
        knownPrimary == audio ||
        knownPrimary == video ||
        knownPrimary == music) {
      return knownCapabilities.any((value) => isChat(value)) &&
          !_hasDedicatedNonChatNameHint(id);
    }
    if ((knownCapabilities.contains(embedding) ||
            knownCapabilities.contains(rerank)) &&
        !knownCapabilities.any((value) => isChat(value))) {
      return false;
    }
    if (knownCapabilities.contains(image) ||
        knownCapabilities.contains(video) ||
        knownCapabilities.contains(audio) ||
        knownCapabilities.contains(music)) {
      if (!knownCapabilities.any((value) => isChat(value))) return false;
    }

    return isChat(knownPrimary) && isChat(inferred);
  }

  static String? _explicitCapability(Map<String, dynamic>? metadata) {
    final capabilities = _explicitCapabilities(metadata);
    if (capabilities.isEmpty) return null;
    return _firstCapability(capabilities);
  }

  static Set<String> _explicitCapabilities(Map<String, dynamic>? metadata) {
    if (metadata == null) return <String>{};
    final result = <String>{};
    for (final entry in metadata.entries) {
      final key = entry.key.toString();
      final loweredKey = key.toLowerCase();
      final isInput = loweredKey.contains('input');
      final isOutput = loweredKey.contains('output');
      final isModalities = loweredKey.contains('modalit');
      final isCapabilityField =
          loweredKey == 'capability' ||
          loweredKey == 'capabilities' ||
          loweredKey == 'type' ||
          loweredKey == 'model_type' ||
          loweredKey == 'task' ||
          loweredKey.contains('supported') ||
          isModalities;
      if (!isCapabilityField) continue;
      _collectExplicitCapability(
        result,
        entry.value,
        input: isInput,
        output: isOutput,
      );
    }
    return result;
  }

  static void _collectExplicitCapability(
    Set<String> result,
    dynamic value, {
    bool input = false,
    bool output = false,
  }) {
    if (value is Map) {
      for (final entry in value.entries) {
        final childKey = entry.key.toString().toLowerCase();
        final childInput = input || childKey.contains('input');
        final childOutput = output || childKey.contains('output');
        if (entry.value == true ||
            entry.value is String ||
            entry.value is Iterable) {
          _collectExplicitCapability(
            result,
            entry.key,
            input: childInput,
            output: childOutput,
          );
          _collectExplicitCapability(
            result,
            entry.value,
            input: childInput,
            output: childOutput,
          );
        }
      }
      return;
    }
    if (value is Iterable) {
      for (final item in value) {
        _collectExplicitCapability(result, item, input: input, output: output);
      }
      return;
    }
    if (value == null) return;
    final raw = value.toString().trim().toLowerCase();
    if (raw.isEmpty) return;

    if (raw.contains('embed')) result.add(embedding);
    if (raw.contains('rerank') ||
        raw.contains('re-rank') ||
        raw.contains('re_rank')) {
      result.add(rerank);
    }
    if (raw.contains('reason') || raw.contains('think')) result.add(reasoner);
    if (raw.contains('video')) result.add(video);
    if (raw.contains('music') ||
        raw.contains('audio-generation') ||
        raw.contains('audio_generation')) {
      result.add(music);
    } else if (raw.contains('audio') ||
        raw.contains('voice') ||
        raw.contains('speech') ||
        raw.contains('transcri') ||
        raw.contains('asr') ||
        raw.contains('tts') ||
        raw == 'audio') {
      result.add(audio);
    }
    if (raw.contains('image-generation') ||
        raw.contains('image_generation') ||
        raw.contains('imagegen') ||
        raw.contains('text-to-image') ||
        raw.contains('text_to_image') ||
        (raw == 'image' && !input) ||
        (output && raw.contains('image'))) {
      result.add(image);
    } else if (raw.contains('vision') ||
        raw.contains('multimodal') ||
        raw.contains('multi-modal') ||
        raw == 'vl' ||
        (input && raw.contains('image'))) {
      result.add(vision);
    }
    if (raw.contains('chat') ||
        raw.contains('completion') ||
        raw.contains('generatecontent') ||
        raw == 'text') {
      result.add(chat);
    }
  }

  static bool _supportsExplicitMedia({
    required String? capability,
    required Set<String>? capabilities,
    required String expected,
  }) {
    if (capabilities?.map(_knownCapability).contains(expected) == true) {
      return true;
    }
    return _knownCapability(capability) == expected;
  }

  static String _firstCapability(Set<String> capabilities) {
    for (final preferred in [
      embedding,
      rerank,
      image,
      video,
      music,
      audio,
      reasoner,
      vision,
      chat,
    ]) {
      if (capabilities.contains(preferred)) return preferred;
    }
    return chat;
  }

  static String _knownCapability(String? value) {
    if (value == null) return chat;
    final lowered = value.trim().toLowerCase();
    if (all.contains(lowered)) return lowered;
    return switch (lowered) {
      'completion' ||
      'completions' ||
      'text-generation' ||
      'text_generation' => chat,
      'multimodal' || 'image-input' || 'image_input' => vision,
      'image-generation' || 'image_generation' || 'imagegen' => image,
      'speech' || 'stt' || 'tts' || 'transcription' => audio,
      'audio-generation' || 'audio_generation' => music,
      'rerank' || 're-rank' || 're_rank' || 'reranker' => rerank,
      _ => chat,
    };
  }

  static String _lowerModelId(String modelId) => modelId.trim().toLowerCase();

  static bool _matchesAny(String value, Iterable<String> hints) {
    return hints.any(value.contains);
  }

  static bool _hasDedicatedNonChatNameHint(String id) {
    return _matchesAny(id, _embeddingHints) ||
        _matchesAny(id, _imageGenerationHints) ||
        _matchesAny(id, _videoGenerationHints) ||
        _matchesAny(id, _musicGenerationHints) ||
        _matchesAny(id, _audioModelHints) ||
        _matchesAny(id, _nonChatServiceHints) ||
        _matchesAny(id, _rerankHints);
  }

  /// Protocols with a first-party multimodal contract often expose model
  /// lists that only say "generate content" or omit input modalities. Keep
  /// this provider-aware fallback narrow: it should recover known vision
  /// families without turning every arbitrary chat model into a vision model.
  static bool _protocolVisionHint(String? protocol, String id) {
    switch (protocol?.trim().toLowerCase()) {
      case 'claude':
        // Claude 3 and 4 families accept image content. Claude 2 and older
        // models are intentionally not included.
        return id.startsWith('claude-3') ||
            id.startsWith('claude-4') ||
            RegExp(
              r'^claude-(?:opus|sonnet|haiku)-[34](?:[.-]|$)',
            ).hasMatch(id);
      case 'gemini':
        // Gemini model discovery exposes generateContent but generally omits
        // input modality metadata. TTS / embedding variants are excluded.
        if (id.contains('embedding') ||
            id.contains('tts') ||
            id.contains('text-to-speech') ||
            id.contains('audio')) {
          return false;
        }
        return id.startsWith('gemini-') ||
            id.startsWith('gemma-3') ||
            id.startsWith('gemma3');
      case 'ollama':
        return _ollamaVisionHints.any(id.contains);
      case 'openai_chat' || 'openai_response':
        // xAI's OpenAI-compatible chat endpoint does not publish a reliable
        // input-modality field. Keep its known Grok vision families usable;
        // dedicated Imagine media models remain excluded by the normal chat
        // selector predicate.
        return id.startsWith('grok-') &&
            !id.contains('imagine-image') &&
            !id.contains('imagine-video');
      default:
        return false;
    }
  }

  static bool _isExactSimiRouterMimoChatVision({
    required String? capability,
    required String modelId,
    required String? protocol,
  }) {
    // Do not use normalize(capability) here: unknown/null persisted values
    // must not silently become the explicit `chat` contract.
    return capability?.trim().toLowerCase() == chat &&
        _simiRouterMimoVisionProtocols.contains(
          protocol?.trim().toLowerCase(),
        ) &&
        _simiRouterMimoChatModelIds.contains(_lowerModelId(modelId));
  }

  static const _ollamaVisionHints = [
    'llava',
    'bakllava',
    'qwen-vl',
    'qwen2-vl',
    'qwen2.5-vl',
    'qwen3-vl',
    'gemma3',
    'gemma-3',
    'llama3.2-vision',
    'llama-3.2-vision',
    'llama4',
    'llama-4',
    'minicpm-v',
    'internvl',
    'pixtral',
    'moondream',
    'cogvlm',
    'molmo',
    'phi-3.5-vision',
    'phi-4-multimodal',
  ];

  static bool _isChatSelectableName(String id) {
    return id.isNotEmpty && !_hasDedicatedNonChatNameHint(id);
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
      case rerank:
        return 'Rerank 重排';
      case vision:
        return 'Vision 视觉';
      case image:
        return 'Image 图片生成';
      case reasoner:
        return 'Reasoner 深度思考';
      case audio:
        return 'Audio 音频';
      case tts:
        return 'TTS 语音合成';
      case asr:
        return 'ASR 语音识别';
      case voiceDesign:
        return '声音设计';
      case voiceClone:
        return '声音克隆';
      case video:
        return 'Video 视频';
      case music:
        return 'Music 音乐';
      case chat:
      default:
        return 'Chat 对话';
    }
  }
}
