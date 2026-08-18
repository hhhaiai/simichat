import 'dart:convert';
import 'dart:typed_data';

/// Supported realtime providers.  The wire event names intentionally remain
/// OpenAI-compatible because xAI's realtime API uses the same event family
/// with a small number of documented naming differences.
enum RealtimeVoiceProvider { openAi, xAi, geminiLive, custom }

/// How a realtime credential is presented during the WebSocket handshake.
enum RealtimeVoiceAuthMode { bearer, ephemeral, apiKeyHeader }

/// Controls how Gemini Live transcription text is interpreted.
///
/// The raw WebSocket reference exposes a `text` field but does not label each
/// transcription message as a delta or a cumulative snapshot.  The default
/// is therefore the append-only mode used by the public examples; callers
/// talking to a gateway that emits snapshots can opt into [cumulative].
enum RealtimeVoiceGeminiTranscriptMode { delta, cumulative }

/// Audio bytes can travel as JSON/base64 or as a native binary WebSocket
/// frame.  JSON is the default and is supported by both provider profiles.
enum RealtimeVoiceAudioTransport { json, binary }

/// Selects the session.update field layout.
///
/// [providerDefault] uses the legacy OpenAI field names for OpenAI and the
/// nested `audio` fields for xAI/custom endpoints.  [modern] is useful for a
/// current OpenAI-compatible gateway that implements the nested layout;
/// [legacy] is useful for older OpenAI-compatible deployments.
enum RealtimeVoiceSessionWireFormat { providerDefault, modern, legacy }

/// Lifecycle state for a [RealtimeVoiceSession].
enum RealtimeVoiceSessionState {
  idle,
  connecting,
  connected,
  closing,
  cancelling,
  closed,
  cancelled,
  failed,
}

extension RealtimeVoiceSessionStateX on RealtimeVoiceSessionState {
  bool get isTerminal => switch (this) {
    RealtimeVoiceSessionState.closed ||
    RealtimeVoiceSessionState.cancelled ||
    RealtimeVoiceSessionState.failed => true,
    _ => false,
  };
}

/// The source of a text event delivered by the realtime server.
enum RealtimeVoiceTextSource { inputTranscript, outputText, outputTranscript }

/// Response lifecycle phase.
enum RealtimeVoiceResponsePhase { started, done }

/// A bearer or provider-specific ephemeral credential.
///
/// The token is kept only in this in-memory configuration object so it can be
/// handed to the native WebSocket handshake.  It is deliberately excluded
/// from [toString], session snapshots, and all event objects.
class RealtimeVoiceAuth {
  const RealtimeVoiceAuth.bearer(String token)
    : this._(mode: RealtimeVoiceAuthMode.bearer, token: token);

  const RealtimeVoiceAuth.ephemeral(String token, {String? protocolPrefix})
    : this._(
        mode: RealtimeVoiceAuthMode.ephemeral,
        token: token,
        protocolPrefix: protocolPrefix,
      );

  /// Presents an API key as a handshake header.  Gemini Live uses
  /// `x-goog-api-key` for this profile instead of putting the key in the
  /// WebSocket URL.  [headerName] is configurable for a compatible gateway,
  /// but the direct Gemini profile defaults to the documented header name.
  const RealtimeVoiceAuth.apiKeyHeader(
    String token, {
    String headerName = 'x-goog-api-key',
  }) : this._(
         mode: RealtimeVoiceAuthMode.apiKeyHeader,
         token: token,
         headerName: headerName,
       );

  const RealtimeVoiceAuth._({
    required this.mode,
    required this.token,
    this.protocolPrefix,
    this.headerName,
  });

  final RealtimeVoiceAuthMode mode;
  final String token;

  /// Optional custom subprotocol prefix, without the trailing `.<token>`.
  /// OpenAI and xAI choose their documented defaults when this is null.
  final String? protocolPrefix;

  /// Header used when [mode] is [RealtimeVoiceAuthMode.apiKeyHeader].
  final String? headerName;

  bool get isConfigured => token.trim().isNotEmpty;

  @override
  String toString() => 'RealtimeVoiceAuth(mode: $mode)';
}

/// Wire-level knobs for the Gemini Live adapter.
///
/// The base session config remains provider-neutral so existing OpenAI/xAI/
/// custom callers keep their old API.  These options only affect a
/// [RealtimeVoiceProvider.geminiLive] setup and make fields whose behavior
/// varies across Gemini Live models or compatible gateways explicit.
class RealtimeVoiceGeminiLiveOptions {
  const RealtimeVoiceGeminiLiveOptions({
    this.inputAudioTranscription = true,
    this.outputAudioTranscription = true,
    this.transcriptMode = RealtimeVoiceGeminiTranscriptMode.delta,
    this.modelResourcePrefix = 'models/',
    this.inputAudioMimeType,
    Map<String, dynamic> setupFields = const <String, dynamic>{},
  }) : _setupFields = setupFields;

  /// Includes `inputAudioTranscription: {}` in `setup` when true.
  final bool inputAudioTranscription;

  /// Includes `outputAudioTranscription: {}` in `setup` when true.
  final bool outputAudioTranscription;

  /// Interprets Gemini `inputTranscription.text`,
  /// `outputTranscription.text`, and model text parts as deltas or snapshots.
  final RealtimeVoiceGeminiTranscriptMode transcriptMode;

  /// Prefix used to turn a short model name into the Live API resource name.
  /// Set it to an empty string for a gateway that expects the model verbatim.
  final String modelResourcePrefix;

  /// Optional MIME type override for `realtimeInput.audio`.
  ///
  /// If omitted, the adapter derives `audio/pcm;rate=<sample rate>` from
  /// [RealtimeVoiceSessionConfig.inputAudio].
  final String? inputAudioMimeType;

  /// Additional fields merged into the Gemini `setup` object.  This is the
  /// escape hatch for preview-only or gateway-specific fields not yet covered
  /// by the stable adapter surface.
  final Map<String, dynamic> _setupFields;

  /// Returns a defensive copy so callers cannot mutate the configuration that
  /// was supplied to the const-friendly constructor.
  Map<String, dynamic> get setupFields => _copyJsonMap(_setupFields);
}

/// Codec and sample-rate description used by modern nested audio fields.
class RealtimeVoiceAudioFormat {
  const RealtimeVoiceAudioFormat({required this.type, this.sampleRate});

  const RealtimeVoiceAudioFormat.pcm16({this.sampleRate = 24000})
    : type = 'audio/pcm';

  final String type;
  final int? sampleRate;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type,
    if (sampleRate != null) 'rate': sampleRate,
  };

  /// The legacy OpenAI spelling for the common audio codecs.
  String get legacyType {
    switch (type.toLowerCase()) {
      case 'audio/pcm':
      case 'pcm16':
        return 'pcm16';
      case 'audio/pcmu':
      case 'g711_ulaw':
      case 'g711-ulaw':
        return 'g711_ulaw';
      case 'audio/pcma':
      case 'g711_alaw':
      case 'g711-alaw':
        return 'g711_alaw';
      default:
        return type;
    }
  }

  @override
  String toString() =>
      'RealtimeVoiceAudioFormat(type: $type, rate: $sampleRate)';
}

/// Server VAD or manual turn configuration.
class RealtimeVoiceTurnDetection {
  const RealtimeVoiceTurnDetection({
    this.type,
    this.threshold,
    this.silenceDurationMs,
    this.prefixPaddingMs,
    this.idleTimeoutMs,
    this.createResponse,
    this.interruptResponse,
  });

  const RealtimeVoiceTurnDetection.serverVad({
    this.threshold,
    this.silenceDurationMs,
    this.prefixPaddingMs,
    this.idleTimeoutMs,
    this.createResponse,
    this.interruptResponse,
  }) : type = 'server_vad';

  const RealtimeVoiceTurnDetection.manual()
    : type = null,
      threshold = null,
      silenceDurationMs = null,
      prefixPaddingMs = null,
      idleTimeoutMs = null,
      createResponse = null,
      interruptResponse = null;

  final String? type;
  final num? threshold;
  final int? silenceDurationMs;
  final int? prefixPaddingMs;
  final int? idleTimeoutMs;
  final bool? createResponse;
  final bool? interruptResponse;

  /// A null type represents the explicit `turn_detection: null` setting.
  Map<String, dynamic>? toJson() {
    if (type == null) return null;
    return <String, dynamic>{
      'type': type,
      if (threshold != null) 'threshold': threshold,
      if (silenceDurationMs != null) 'silence_duration_ms': silenceDurationMs,
      if (prefixPaddingMs != null) 'prefix_padding_ms': prefixPaddingMs,
      if (idleTimeoutMs != null) 'idle_timeout_ms': idleTimeoutMs,
      if (createResponse != null) 'create_response': createResponse,
      if (interruptResponse != null) 'interrupt_response': interruptResponse,
    };
  }
}

/// Immutable configuration for one native realtime voice connection.
class RealtimeVoiceSessionConfig {
  RealtimeVoiceSessionConfig({
    required this.endpoint,
    required this.auth,
    this.provider = RealtimeVoiceProvider.openAi,
    this.model,
    this.instructions,
    this.voice,
    this.inputAudio,
    this.outputAudio,
    this.inputAudioTransport = RealtimeVoiceAudioTransport.json,
    this.outputAudioTransport = RealtimeVoiceAudioTransport.json,
    this.transcriptionModel,
    this.languageHint,
    this.turnDetection,
    List<String>? outputModalities,
    this.sessionWireFormat = RealtimeVoiceSessionWireFormat.providerDefault,
    this.geminiLiveOptions = const RealtimeVoiceGeminiLiveOptions(),
    Map<String, dynamic> additionalSessionFields = const <String, dynamic>{},
    Map<String, String> headers = const <String, String>{},
    List<String> protocols = const <String>[],
    this.connectTimeout = const Duration(seconds: 20),
    this.pingInterval,
    this.sendSessionUpdate = true,
  }) : additionalSessionFields = _copyJsonMap(additionalSessionFields),
       headers = Map<String, String>.unmodifiable(headers),
       protocols = List<String>.unmodifiable(protocols),
       outputModalities = outputModalities == null
           ? null
           : List<String>.unmodifiable(outputModalities);

  factory RealtimeVoiceSessionConfig.openAi({
    required RealtimeVoiceAuth auth,
    Uri? endpoint,
    String model = 'gpt-realtime',
    String? instructions,
    String? voice,
    RealtimeVoiceAudioFormat? inputAudio,
    RealtimeVoiceAudioFormat? outputAudio,
    RealtimeVoiceAudioTransport inputAudioTransport =
        RealtimeVoiceAudioTransport.json,
    RealtimeVoiceAudioTransport outputAudioTransport =
        RealtimeVoiceAudioTransport.json,
    String? transcriptionModel,
    RealtimeVoiceTurnDetection? turnDetection,
    List<String>? outputModalities,
    RealtimeVoiceSessionWireFormat sessionWireFormat =
        RealtimeVoiceSessionWireFormat.providerDefault,
    Map<String, dynamic> additionalSessionFields = const <String, dynamic>{},
    Map<String, String> headers = const <String, String>{},
    List<String> protocols = const <String>[],
    Duration connectTimeout = const Duration(seconds: 20),
    Duration? pingInterval,
    bool sendSessionUpdate = true,
  }) {
    return RealtimeVoiceSessionConfig(
      endpoint: endpoint ?? Uri.parse('wss://api.openai.com/v1/realtime'),
      auth: auth,
      provider: RealtimeVoiceProvider.openAi,
      model: model,
      instructions: instructions,
      voice: voice,
      inputAudio: inputAudio,
      outputAudio: outputAudio,
      inputAudioTransport: inputAudioTransport,
      outputAudioTransport: outputAudioTransport,
      transcriptionModel: transcriptionModel,
      turnDetection: turnDetection,
      outputModalities: outputModalities,
      sessionWireFormat: sessionWireFormat,
      additionalSessionFields: additionalSessionFields,
      headers: headers,
      protocols: protocols,
      connectTimeout: connectTimeout,
      pingInterval: pingInterval,
      sendSessionUpdate: sendSessionUpdate,
    );
  }

  factory RealtimeVoiceSessionConfig.xAi({
    required RealtimeVoiceAuth auth,
    Uri? endpoint,
    String model = 'grok-voice-latest',
    String? instructions,
    String? voice,
    RealtimeVoiceAudioFormat? inputAudio,
    RealtimeVoiceAudioFormat? outputAudio,
    RealtimeVoiceAudioTransport inputAudioTransport =
        RealtimeVoiceAudioTransport.json,
    RealtimeVoiceAudioTransport outputAudioTransport =
        RealtimeVoiceAudioTransport.json,
    String? transcriptionModel,
    String? languageHint,
    RealtimeVoiceTurnDetection? turnDetection,
    List<String>? outputModalities,
    RealtimeVoiceSessionWireFormat sessionWireFormat =
        RealtimeVoiceSessionWireFormat.providerDefault,
    Map<String, dynamic> additionalSessionFields = const <String, dynamic>{},
    Map<String, String> headers = const <String, String>{},
    List<String> protocols = const <String>[],
    Duration connectTimeout = const Duration(seconds: 20),
    Duration? pingInterval,
    bool sendSessionUpdate = true,
  }) {
    return RealtimeVoiceSessionConfig(
      endpoint: endpoint ?? Uri.parse('wss://api.x.ai/v1/realtime'),
      auth: auth,
      provider: RealtimeVoiceProvider.xAi,
      model: model,
      instructions: instructions,
      voice: voice,
      inputAudio: inputAudio,
      outputAudio: outputAudio,
      inputAudioTransport: inputAudioTransport,
      outputAudioTransport: outputAudioTransport,
      transcriptionModel: transcriptionModel,
      languageHint: languageHint,
      turnDetection: turnDetection,
      outputModalities: outputModalities,
      sessionWireFormat: sessionWireFormat,
      additionalSessionFields: additionalSessionFields,
      headers: headers,
      protocols: protocols,
      connectTimeout: connectTimeout,
      pingInterval: pingInterval,
      sendSessionUpdate: sendSessionUpdate,
    );
  }

  factory RealtimeVoiceSessionConfig.geminiLive({
    required RealtimeVoiceAuth auth,
    Uri? endpoint,
    String model = 'gemini-3.1-flash-live-preview',
    String? instructions,
    String? voice,
    RealtimeVoiceAudioFormat? inputAudio,
    RealtimeVoiceAudioFormat? outputAudio,
    RealtimeVoiceAudioTransport inputAudioTransport =
        RealtimeVoiceAudioTransport.json,
    RealtimeVoiceAudioTransport outputAudioTransport =
        RealtimeVoiceAudioTransport.json,
    String? languageHint,
    RealtimeVoiceTurnDetection? turnDetection,
    List<String>? outputModalities,
    RealtimeVoiceGeminiLiveOptions geminiLiveOptions =
        const RealtimeVoiceGeminiLiveOptions(),
    Map<String, dynamic> additionalSessionFields = const <String, dynamic>{},
    Map<String, String> headers = const <String, String>{},
    List<String> protocols = const <String>[],
    Duration connectTimeout = const Duration(seconds: 20),
    Duration? pingInterval,
    bool sendSessionUpdate = true,
  }) {
    return RealtimeVoiceSessionConfig(
      endpoint:
          endpoint ??
          Uri.parse(
            'wss://generativelanguage.googleapis.com/ws/'
            'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent',
          ),
      auth: auth,
      provider: RealtimeVoiceProvider.geminiLive,
      model: model,
      instructions: instructions,
      voice: voice,
      inputAudio:
          inputAudio ?? const RealtimeVoiceAudioFormat.pcm16(sampleRate: 16000),
      outputAudio:
          outputAudio ??
          const RealtimeVoiceAudioFormat.pcm16(sampleRate: 24000),
      inputAudioTransport: inputAudioTransport,
      outputAudioTransport: outputAudioTransport,
      languageHint: languageHint,
      turnDetection: turnDetection,
      outputModalities: outputModalities,
      geminiLiveOptions: geminiLiveOptions,
      additionalSessionFields: additionalSessionFields,
      headers: headers,
      protocols: protocols,
      connectTimeout: connectTimeout,
      pingInterval: pingInterval,
      sendSessionUpdate: sendSessionUpdate,
    );
  }

  final Uri endpoint;
  final RealtimeVoiceProvider provider;
  final RealtimeVoiceAuth auth;
  final String? model;
  final String? instructions;
  final String? voice;
  final RealtimeVoiceAudioFormat? inputAudio;
  final RealtimeVoiceAudioFormat? outputAudio;
  final RealtimeVoiceAudioTransport inputAudioTransport;
  final RealtimeVoiceAudioTransport outputAudioTransport;
  final String? transcriptionModel;
  final String? languageHint;
  final RealtimeVoiceTurnDetection? turnDetection;
  final List<String>? outputModalities;
  final RealtimeVoiceSessionWireFormat sessionWireFormat;
  final RealtimeVoiceGeminiLiveOptions geminiLiveOptions;
  final Map<String, dynamic> additionalSessionFields;
  final Map<String, String> headers;
  final List<String> protocols;
  final Duration connectTimeout;
  final Duration? pingInterval;
  final bool sendSessionUpdate;

  /// Adds [model] to the endpoint only when the caller did not already put a
  /// model query parameter there.  Gemini carries its model in `setup`, so it
  /// never receives a model query parameter.  Credentials are never added to
  /// the URI.
  Uri get resolvedEndpoint {
    final normalizedModel = model?.trim() ?? '';
    if (provider == RealtimeVoiceProvider.geminiLive ||
        normalizedModel.isEmpty ||
        endpoint.queryParameters.containsKey('model')) {
      return endpoint;
    }
    final query = <String, String>{
      ...endpoint.queryParameters,
      'model': normalizedModel,
    };
    return endpoint.replace(queryParameters: query);
  }

  bool get usesModernSessionFields => switch (sessionWireFormat) {
    RealtimeVoiceSessionWireFormat.modern => true,
    RealtimeVoiceSessionWireFormat.legacy => false,
    RealtimeVoiceSessionWireFormat.providerDefault =>
      provider != RealtimeVoiceProvider.openAi ||
          inputAudioTransport == RealtimeVoiceAudioTransport.binary ||
          outputAudioTransport == RealtimeVoiceAudioTransport.binary,
  };

  /// Validates only local invariants.  The remote endpoint may still reject a
  /// model or a provider-specific option; that error is delivered sanitized
  /// through the session event stream.
  void validate() {
    if (endpoint.scheme.toLowerCase() != 'wss' || endpoint.host.isEmpty) {
      throw RealtimeVoiceSessionException(
        '实时语音 endpoint 必须是有效的 wss URL',
        kind: RealtimeVoiceSessionErrorKind.invalidConfiguration,
      );
    }
    if (endpoint.userInfo.isNotEmpty || endpoint.fragment.isNotEmpty) {
      throw RealtimeVoiceSessionException(
        '实时语音 endpoint 不支持用户信息或 fragment',
        kind: RealtimeVoiceSessionErrorKind.invalidConfiguration,
      );
    }
    const sensitiveQueryKeys = <String>{
      'api_key',
      'apikey',
      'authorization',
      'client_secret',
      'secret',
      'token',
    };
    final queryKeys = endpoint.queryParameters.keys
        .map((key) => key.toLowerCase())
        .toSet();
    if (queryKeys.any(sensitiveQueryKeys.contains) ||
        (provider == RealtimeVoiceProvider.geminiLive &&
            queryKeys.any(
              const <String>{
                'key',
                'access_token',
                'api-key',
                'x-goog-api-key',
              }.contains,
            ))) {
      throw RealtimeVoiceSessionException(
        '实时语音 endpoint 不得通过 query 传递凭据',
        kind: RealtimeVoiceSessionErrorKind.invalidConfiguration,
      );
    }
    if (!auth.isConfigured) {
      throw RealtimeVoiceSessionException(
        '实时语音凭据未配置',
        kind: RealtimeVoiceSessionErrorKind.invalidConfiguration,
      );
    }
    if (connectTimeout <= Duration.zero) {
      throw RealtimeVoiceSessionException(
        '实时语音连接超时配置无效',
        kind: RealtimeVoiceSessionErrorKind.invalidConfiguration,
      );
    }
    if (auth.mode == RealtimeVoiceAuthMode.apiKeyHeader) {
      final headerName = auth.headerName?.trim() ?? '';
      if (headerName.isEmpty ||
          !RegExp(r'^[A-Za-z0-9-]+$').hasMatch(headerName)) {
        throw RealtimeVoiceSessionException(
          '实时语音 API key header 名称无效',
          kind: RealtimeVoiceSessionErrorKind.invalidConfiguration,
        );
      }
    }
    if (provider == RealtimeVoiceProvider.geminiLive &&
        auth.mode != RealtimeVoiceAuthMode.apiKeyHeader) {
      throw RealtimeVoiceSessionException(
        'Gemini Live 必须通过 x-goog-api-key header 传递凭据',
        kind: RealtimeVoiceSessionErrorKind.invalidConfiguration,
      );
    }
    if (provider == RealtimeVoiceProvider.geminiLive &&
        auth.headerName?.trim().toLowerCase() != 'x-goog-api-key') {
      throw RealtimeVoiceSessionException(
        'Gemini Live 必须使用 x-goog-api-key header 传递凭据',
        kind: RealtimeVoiceSessionErrorKind.invalidConfiguration,
      );
    }
    if (provider == RealtimeVoiceProvider.geminiLive &&
        (inputAudioTransport != RealtimeVoiceAudioTransport.json ||
            outputAudioTransport != RealtimeVoiceAudioTransport.json)) {
      throw RealtimeVoiceSessionException(
        'Gemini Live 音频必须使用 JSON/base64 realtimeInput，不支持 binary WebSocket frame',
        kind: RealtimeVoiceSessionErrorKind.invalidConfiguration,
      );
    }
    if (auth.mode == RealtimeVoiceAuthMode.ephemeral &&
        provider == RealtimeVoiceProvider.custom &&
        (auth.protocolPrefix?.trim().isEmpty ?? true)) {
      throw RealtimeVoiceSessionException(
        'custom realtime endpoint 的 ephemeral token 需要 protocolPrefix',
        kind: RealtimeVoiceSessionErrorKind.invalidConfiguration,
      );
    }
  }

  @override
  String toString() =>
      'RealtimeVoiceSessionConfig('
      'provider: $provider, endpoint: ${redactRealtimeVoiceSecrets(resolvedEndpoint.toString())}, '
      'model: $model, auth: ${auth.mode})';
}

/// Protocol event builders shared by UI adapters and [RealtimeVoiceSession].
class RealtimeVoiceProtocol {
  const RealtimeVoiceProtocol._();

  static Map<String, dynamic> sessionUpdate(RealtimeVoiceSessionConfig config) {
    if (config.provider == RealtimeVoiceProvider.geminiLive) {
      return geminiSetup(config);
    }
    return <String, dynamic>{
      'type': 'session.update',
      'session': _buildSessionFields(config),
    };
  }

  /// Builds Gemini's first WebSocket message.
  ///
  /// The stable fields below are from the raw Live WebSocket union. Preview
  /// or gateway-specific setup fields can be supplied through
  /// [RealtimeVoiceGeminiLiveOptions.setupFields] or
  /// [RealtimeVoiceSessionConfig.additionalSessionFields].
  static Map<String, dynamic> geminiSetup(RealtimeVoiceSessionConfig config) {
    final options = config.geminiLiveOptions;
    final setup = <String, dynamic>{
      'model': _geminiModelResourceName(config.model, options),
    };
    final generationConfig = <String, dynamic>{};
    final modalities = _geminiResponseModalities(
      config.outputModalities,
      audioOutputConfigured: config.outputAudio != null,
    );
    if (modalities.isNotEmpty) {
      generationConfig['responseModalities'] = modalities;
    } else if (config.outputAudio != null) {
      generationConfig['responseModalities'] = <String>['AUDIO'];
    }

    final speechConfig = <String, dynamic>{};
    if (config.voice?.trim().isNotEmpty == true) {
      speechConfig['voiceConfig'] = <String, dynamic>{
        'prebuiltVoiceConfig': <String, dynamic>{
          'voiceName': config.voice!.trim(),
        },
      };
    }
    final languageCode = config.languageHint?.trim() ?? '';
    if (languageCode.isNotEmpty && languageCode.toLowerCase() != 'auto') {
      speechConfig['languageCode'] = languageCode;
    }
    if (speechConfig.isNotEmpty) {
      generationConfig['speechConfig'] = speechConfig;
    }
    if (generationConfig.isNotEmpty) {
      setup['generationConfig'] = generationConfig;
    }

    final instructions = config.instructions?.trim() ?? '';
    if (instructions.isNotEmpty) {
      setup['systemInstruction'] = <String, dynamic>{
        'parts': <Map<String, String>>[
          <String, String>{'text': instructions},
        ],
      };
    }
    if (options.inputAudioTranscription) {
      setup['inputAudioTranscription'] = <String, dynamic>{};
    }
    if (options.outputAudioTranscription) {
      setup['outputAudioTranscription'] = <String, dynamic>{};
    }
    final turnDetection = config.turnDetection;
    if (turnDetection?.type == 'server_vad') {
      final automaticActivityDetection = <String, dynamic>{
        if (turnDetection!.prefixPaddingMs != null)
          'prefixPaddingMs': turnDetection.prefixPaddingMs,
        if (turnDetection.silenceDurationMs != null)
          'silenceDurationMs': turnDetection.silenceDurationMs,
      };
      final realtimeInputConfig = <String, dynamic>{
        if (automaticActivityDetection.isNotEmpty)
          'automaticActivityDetection': automaticActivityDetection,
        if (turnDetection.interruptResponse != null)
          'activityHandling': turnDetection.interruptResponse == true
              ? 'START_OF_ACTIVITY_INTERRUPTS'
              : 'NO_INTERRUPTION',
      };
      if (realtimeInputConfig.isNotEmpty) {
        setup['realtimeInputConfig'] = realtimeInputConfig;
      }
    }

    final withSessionFields = _deepMerge(setup, config.additionalSessionFields);
    return <String, dynamic>{
      'setup': _deepMerge(withSessionFields, options.setupFields),
    };
  }

  /// Builds a Gemini `clientContent` message.  `turns` is optional in the
  /// wire schema, which is useful for the best-effort response interruption
  /// used by [responseCancel] for Gemini.
  static Map<String, dynamic> geminiClientContent({
    List<Map<String, dynamic>>? turns,
    bool? turnComplete,
  }) => <String, dynamic>{
    'clientContent': <String, dynamic>{
      if (turns != null)
        'turns': turns.map(_copyJsonMap).toList(growable: false),
      ...switch (turnComplete) {
        bool value => <String, dynamic>{'turnComplete': value},
        null => const <String, dynamic>{},
      },
    },
  };

  static Map<String, dynamic> geminiClientContentText(
    String text, {
    bool turnComplete = true,
  }) => geminiClientContent(
    turns: <Map<String, dynamic>>[
      <String, dynamic>{
        'role': 'user',
        'parts': <Map<String, String>>[
          <String, String>{'text': text},
        ],
      },
    ],
    turnComplete: turnComplete,
  );

  static Map<String, dynamic> geminiRealtimeInputText(String text) =>
      <String, dynamic>{
        'realtimeInput': <String, dynamic>{'text': text},
      };

  static Map<String, dynamic> geminiRealtimeInputAudio(
    String base64Audio, {
    required String mimeType,
  }) => <String, dynamic>{
    'realtimeInput': <String, dynamic>{
      'audio': <String, dynamic>{'data': base64Audio, 'mimeType': mimeType},
    },
  };

  static Map<String, dynamic> geminiRealtimeInputAudioStreamEnd() =>
      <String, dynamic>{
        'realtimeInput': <String, dynamic>{'audioStreamEnd': true},
      };

  static Map<String, dynamic> inputAudioAppend(
    String base64Audio, {
    RealtimeVoiceSessionConfig? config,
  }) {
    if (config?.provider == RealtimeVoiceProvider.geminiLive) {
      return geminiRealtimeInputAudio(
        base64Audio,
        mimeType: _geminiInputAudioMimeType(config!),
      );
    }
    return <String, dynamic>{
      'type': 'input_audio_buffer.append',
      'audio': base64Audio,
    };
  }

  static Map<String, dynamic> inputAudioCommit({
    RealtimeVoiceSessionConfig? config,
  }) {
    if (config?.provider == RealtimeVoiceProvider.geminiLive) {
      return geminiRealtimeInputAudioStreamEnd();
    }
    return <String, dynamic>{'type': 'input_audio_buffer.commit'};
  }

  static Map<String, dynamic> inputAudioClear({
    RealtimeVoiceSessionConfig? config,
  }) {
    if (config?.provider == RealtimeVoiceProvider.geminiLive) {
      // Gemini has no input-buffer clear message; closing the current audio
      // stream is the closest protocol-level equivalent and is safe to send
      // before the next audio chunk reopens it.
      return geminiRealtimeInputAudioStreamEnd();
    }
    return <String, dynamic>{'type': 'input_audio_buffer.clear'};
  }

  static Map<String, dynamic> responseCreate({
    Map<String, dynamic>? response,
    RealtimeVoiceSessionConfig? config,
  }) {
    if (config?.provider == RealtimeVoiceProvider.geminiLive) {
      return geminiClientContent(turnComplete: true);
    }
    return <String, dynamic>{
      'type': 'response.create',
      if (response != null && response.isNotEmpty)
        'response': _copyJsonMap(response),
    };
  }

  static Map<String, dynamic> responseCancel({
    String? responseId,
    RealtimeVoiceSessionConfig? config,
  }) {
    if (config?.provider == RealtimeVoiceProvider.geminiLive) {
      // BidiGenerateContent has no response.cancel event.  A clientContent
      // message is documented to interrupt active generation; turnComplete
      // then leaves the existing WebSocket session usable.
      return geminiClientContent(turnComplete: true);
    }
    return <String, dynamic>{
      'type': 'response.cancel',
      if (responseId != null && responseId.trim().isNotEmpty)
        'response_id': responseId.trim(),
    };
  }

  static Map<String, dynamic> conversationItemCreate({
    required String text,
    RealtimeVoiceSessionConfig? config,
  }) {
    if (config?.provider == RealtimeVoiceProvider.geminiLive) {
      return geminiRealtimeInputText(text);
    }
    return <String, dynamic>{
      'type': 'conversation.item.create',
      'item': <String, dynamic>{
        'type': 'message',
        'role': 'user',
        'content': <Map<String, String>>[
          <String, String>{'type': 'input_text', 'text': text},
        ],
      },
    };
  }
}

/// Base class for the small, provider-neutral event surface exposed to UI.
sealed class RealtimeVoiceEvent {
  const RealtimeVoiceEvent({required this.type});

  final String type;
}

class RealtimeVoiceSessionEvent extends RealtimeVoiceEvent {
  const RealtimeVoiceSessionEvent({
    required super.type,
    this.sessionId,
    this.eventId,
  });

  final String? sessionId;
  final String? eventId;
}

class RealtimeVoiceLifecycleEvent extends RealtimeVoiceEvent {
  const RealtimeVoiceLifecycleEvent({
    required super.type,
    this.eventId,
    this.itemId,
    this.responseId,
  });

  final String? eventId;
  final String? itemId;
  final String? responseId;
}

class RealtimeVoiceTextEvent extends RealtimeVoiceEvent {
  const RealtimeVoiceTextEvent({
    required super.type,
    required this.source,
    required this.delta,
    required this.text,
    required this.isFinal,
    required this.isCumulative,
    this.itemId,
    this.responseId,
  });

  final RealtimeVoiceTextSource source;

  /// Append this value only when [isCumulative] is false.  For cumulative or
  /// final events use [text] as the current complete value.
  final String delta;
  final String text;
  final bool isFinal;
  final bool isCumulative;
  final String? itemId;
  final String? responseId;

  RealtimeVoiceTextEvent copyWith({String? delta}) => RealtimeVoiceTextEvent(
    type: type,
    source: source,
    delta: delta ?? this.delta,
    text: text,
    isFinal: isFinal,
    isCumulative: isCumulative,
    itemId: itemId,
    responseId: responseId,
  );
}

class RealtimeVoiceAudioEvent extends RealtimeVoiceEvent {
  RealtimeVoiceAudioEvent({
    required super.type,
    required Uint8List bytes,
    required this.base64Audio,
    this.itemId,
    this.responseId,
    this.isBinary = false,
  }) : bytes = Uint8List.fromList(bytes);

  final Uint8List bytes;
  final String base64Audio;
  final String? itemId;
  final String? responseId;
  final bool isBinary;
}

class RealtimeVoiceResponseEvent extends RealtimeVoiceEvent {
  const RealtimeVoiceResponseEvent({
    required super.type,
    required this.phase,
    this.responseId,
    this.status,
  });

  final RealtimeVoiceResponsePhase phase;
  final String? responseId;
  final String? status;
}

class RealtimeVoiceErrorEvent extends RealtimeVoiceEvent {
  RealtimeVoiceErrorEvent({
    required super.type,
    required String message,
    this.errorType,
    this.code,
    this.param,
    this.isRemote = true,
  }) : message = redactRealtimeVoiceSecrets(message);

  final String message;
  final String? errorType;
  final String? code;
  final String? param;
  final bool isRemote;
}

/// Safe parser for text JSON events and native binary audio frames.
///
/// Unknown event types, malformed JSON, malformed known payloads, and invalid
/// base64 are ignored.  The session never needs to retain or expose the raw
/// server payload.
class RealtimeVoiceEventParser {
  const RealtimeVoiceEventParser._();

  static RealtimeVoiceEvent? parse(
    Object? raw, {
    RealtimeVoiceGeminiTranscriptMode geminiTranscriptMode =
        RealtimeVoiceGeminiTranscriptMode.delta,
  }) {
    final events = parseMany(raw, geminiTranscriptMode: geminiTranscriptMode);
    return events.isEmpty ? null : events.first;
  }

  /// Parses one WebSocket frame into every normalized UI event it contains.
  ///
  /// Gemini `serverContent` can carry input transcription, output
  /// transcription, several model parts, and a completion flag in one JSON
  /// frame.  The old [parse] API remains first-event compatible while the
  /// session consumes this lossless list form.
  static List<RealtimeVoiceEvent> parseMany(
    Object? raw, {
    RealtimeVoiceGeminiTranscriptMode geminiTranscriptMode =
        RealtimeVoiceGeminiTranscriptMode.delta,
  }) {
    if (raw is List<int>) {
      final event = _parseLegacy(raw);
      return event == null
          ? const <RealtimeVoiceEvent>[]
          : <RealtimeVoiceEvent>[event];
    }
    final payload = _decodeMap(raw);
    if (payload == null) return const <RealtimeVoiceEvent>[];

    final serverContent = _asMap(
      payload['serverContent'] ?? payload['server_content'],
    );
    if (serverContent != null) {
      return _parseGeminiServerContent(
        serverContent,
        geminiTranscriptMode: geminiTranscriptMode,
      );
    }
    if (payload.containsKey('setupComplete') ||
        payload.containsKey('setup_complete')) {
      return const <RealtimeVoiceEvent>[
        RealtimeVoiceSessionEvent(type: 'gemini.setupComplete'),
      ];
    }
    if (payload['error'] is Map && payload['type'] == null) {
      return <RealtimeVoiceEvent>[_parseError(payload)];
    }

    final event = _parseLegacy(raw);
    return event == null
        ? const <RealtimeVoiceEvent>[]
        : <RealtimeVoiceEvent>[event];
  }

  static RealtimeVoiceEvent? _parseLegacy(Object? raw) {
    if (raw is List<int>) {
      if (raw.isEmpty) return null;
      final bytes = Uint8List.fromList(raw);
      return RealtimeVoiceAudioEvent(
        type: 'binary.audio',
        bytes: bytes,
        base64Audio: base64Encode(bytes),
        isBinary: true,
      );
    }

    final payload = _decodeMap(raw);
    if (payload == null) return null;
    final type = _safeEventType(payload['type']);
    if (type == null) return null;

    switch (type) {
      case 'session.created':
      case 'session.updated':
        final session = _asMap(payload['session']);
        return RealtimeVoiceSessionEvent(
          type: type,
          sessionId: _safeIdentifier(session?['id']),
          eventId: _safeIdentifier(payload['event_id']),
        );
      case 'conversation.created':
        final conversation = _asMap(payload['conversation']);
        return RealtimeVoiceSessionEvent(
          type: type,
          sessionId: _safeIdentifier(conversation?['id']),
          eventId: _safeIdentifier(payload['event_id']),
        );
      case 'response.created':
        final response = _asMap(payload['response']);
        return RealtimeVoiceResponseEvent(
          type: type,
          phase: RealtimeVoiceResponsePhase.started,
          responseId: _safeIdentifier(
            response?['id'] ?? payload['response_id'],
          ),
          status: _safeStatus(response?['status']),
        );
      case 'response.done':
        final response = _asMap(payload['response']);
        return RealtimeVoiceResponseEvent(
          type: type,
          phase: RealtimeVoiceResponsePhase.done,
          responseId: _safeIdentifier(
            response?['id'] ?? payload['response_id'],
          ),
          status: _safeStatus(response?['status']),
        );
      case 'error':
        return _parseError(payload);
      case 'conversation.item.input_audio_transcription.delta':
        return _parseText(
          payload,
          source: RealtimeVoiceTextSource.inputTranscript,
          isFinal: false,
          isCumulative: false,
          textValue: payload['delta'],
        );
      case 'conversation.item.input_audio_transcription.updated':
        return _parseText(
          payload,
          source: RealtimeVoiceTextSource.inputTranscript,
          isFinal: false,
          isCumulative: true,
          textValue: payload['text'] ?? payload['transcript'],
        );
      case 'conversation.item.input_audio_transcription.completed':
        return _parseText(
          payload,
          source: RealtimeVoiceTextSource.inputTranscript,
          isFinal: true,
          isCumulative: true,
          textValue: payload['transcript'] ?? payload['text'],
        );
      case 'conversation.item.input_audio_transcription.segment':
        return _parseText(
          payload,
          source: RealtimeVoiceTextSource.inputTranscript,
          isFinal: false,
          isCumulative: false,
          textValue: payload['text'] ?? payload['transcript'],
        );
      case 'response.output_text.delta':
        return _parseText(
          payload,
          source: RealtimeVoiceTextSource.outputText,
          isFinal: false,
          isCumulative: false,
          textValue: payload['delta'],
        );
      case 'response.output_text.done':
        return _parseText(
          payload,
          source: RealtimeVoiceTextSource.outputText,
          isFinal: true,
          isCumulative: true,
          textValue: payload['text'] ?? payload['delta'],
        );
      case 'response.audio_transcript.delta':
      case 'response.output_audio_transcript.delta':
        return _parseText(
          payload,
          source: RealtimeVoiceTextSource.outputTranscript,
          isFinal: false,
          isCumulative: false,
          textValue: payload['delta'],
        );
      case 'response.audio_transcript.done':
      case 'response.output_audio_transcript.done':
        return _parseText(
          payload,
          source: RealtimeVoiceTextSource.outputTranscript,
          isFinal: true,
          isCumulative: true,
          textValue: payload['transcript'] ?? payload['text'],
        );
      case 'response.audio.delta':
      case 'response.output_audio.delta':
        return _parseAudio(
          payload,
          audioValue: payload['delta'] ?? payload['audio'],
        );
      case 'response.content_part.added':
      case 'response.content_part.done':
        return _parseContentPart(payload);
      default:
        if (_knownLifecycleEvents.contains(type)) {
          return RealtimeVoiceLifecycleEvent(
            type: type,
            eventId: _safeIdentifier(payload['event_id']),
            itemId: _safeIdentifier(payload['item_id']),
            responseId: _safeIdentifier(payload['response_id']),
          );
        }
        return null;
    }
  }

  static List<RealtimeVoiceEvent> _parseGeminiServerContent(
    Map<String, dynamic> serverContent, {
    required RealtimeVoiceGeminiTranscriptMode geminiTranscriptMode,
  }) {
    final events = <RealtimeVoiceEvent>[];
    final finalTurn =
        serverContent['generationComplete'] == true ||
        serverContent['generation_complete'] == true ||
        serverContent['turnComplete'] == true ||
        serverContent['turn_complete'] == true;
    final interrupted =
        serverContent['interrupted'] == true ||
        serverContent['interrupted'] == 'true';

    final inputTranscription = _asMap(
      serverContent['inputTranscription'] ??
          serverContent['input_transcription'],
    );
    final inputText = _parseText(
      serverContent,
      eventType: 'gemini.serverContent.inputTranscription',
      source: RealtimeVoiceTextSource.inputTranscript,
      isFinal: false,
      isCumulative:
          geminiTranscriptMode == RealtimeVoiceGeminiTranscriptMode.cumulative,
      textValue: inputTranscription?['text'],
    );
    if (inputText != null) events.add(inputText);

    final outputTranscription = _asMap(
      serverContent['outputTranscription'] ??
          serverContent['output_transcription'],
    );
    final outputTranscript = _parseText(
      serverContent,
      eventType: 'gemini.serverContent.outputTranscription',
      source: RealtimeVoiceTextSource.outputTranscript,
      isFinal: finalTurn,
      isCumulative:
          geminiTranscriptMode == RealtimeVoiceGeminiTranscriptMode.cumulative,
      textValue: outputTranscription?['text'],
    );
    if (outputTranscript != null) events.add(outputTranscript);

    final modelTurn = _asMap(
      serverContent['modelTurn'] ?? serverContent['model_turn'],
    );
    final parts = modelTurn?['parts'];
    if (parts is Iterable) {
      for (final rawPart in parts) {
        final part = _asMap(rawPart);
        if (part == null) continue;

        final text = _parseText(
          serverContent,
          eventType: 'gemini.serverContent.modelTurn.text',
          source: RealtimeVoiceTextSource.outputText,
          isFinal: finalTurn,
          isCumulative:
              geminiTranscriptMode ==
              RealtimeVoiceGeminiTranscriptMode.cumulative,
          textValue: part['text'],
        );
        if (text != null) events.add(text);

        final inlineData = _asMap(part['inlineData'] ?? part['inline_data']);
        if (inlineData == null) continue;
        final mimeType = inlineData['mimeType'] ?? inlineData['mime_type'];
        if (mimeType is String &&
            mimeType.trim().isNotEmpty &&
            !mimeType.toLowerCase().startsWith('audio/')) {
          continue;
        }
        final audio = _parseAudio(
          serverContent,
          eventType: 'gemini.serverContent.modelTurn.inlineData',
          audioValue: inlineData['data'],
        );
        if (audio != null) events.add(audio);
      }
    }

    if (interrupted) {
      events.add(
        const RealtimeVoiceLifecycleEvent(
          type: 'gemini.serverContent.interrupted',
        ),
      );
    }
    if (finalTurn || interrupted) {
      events.add(
        RealtimeVoiceResponseEvent(
          type: interrupted
              ? 'gemini.serverContent.interrupted'
              : 'gemini.serverContent.turnComplete',
          phase: RealtimeVoiceResponsePhase.done,
          status: interrupted ? 'interrupted' : 'completed',
        ),
      );
    }
    return events;
  }

  static RealtimeVoiceTextEvent? _parseText(
    Map<String, dynamic> payload, {
    String? eventType,
    required RealtimeVoiceTextSource source,
    required bool isFinal,
    required bool isCumulative,
    required Object? textValue,
  }) {
    if (textValue is! String) return null;
    final text = _boundedText(textValue);
    if (text == null) return null;
    final delta = isCumulative ? '' : text;
    return RealtimeVoiceTextEvent(
      type: eventType ?? _safeEventType(payload['type']) ?? 'realtime.text',
      source: source,
      delta: delta,
      text: text,
      isFinal: isFinal,
      isCumulative: isCumulative,
      itemId: _safeIdentifier(payload['item_id']),
      responseId: _safeIdentifier(payload['response_id']),
    );
  }

  static RealtimeVoiceAudioEvent? _parseAudio(
    Map<String, dynamic> payload, {
    String? eventType,
    required Object? audioValue,
  }) {
    if (audioValue is! String || audioValue.length > _maxAudioBase64Length) {
      return null;
    }
    try {
      final bytes = Uint8List.fromList(base64Decode(audioValue));
      if (bytes.isEmpty) return null;
      return RealtimeVoiceAudioEvent(
        type: eventType ?? _safeEventType(payload['type']) ?? 'realtime.audio',
        bytes: bytes,
        base64Audio: audioValue,
        itemId: _safeIdentifier(payload['item_id']),
        responseId: _safeIdentifier(payload['response_id']),
      );
    } on FormatException {
      return null;
    }
  }

  static RealtimeVoiceEvent? _parseContentPart(Map<String, dynamic> payload) {
    final part = _asMap(payload['part']);
    if (part == null) return null;
    final partType = _safeEventType(part['type']);
    if (partType == 'text') {
      return _parseText(
        payload,
        source: RealtimeVoiceTextSource.outputText,
        isFinal: payload['type'] == 'response.content_part.done',
        isCumulative: payload['type'] == 'response.content_part.done',
        textValue: part['text'],
      );
    }
    if (partType == 'audio') {
      final transcript = part['transcript'];
      if (transcript is String) {
        return _parseText(
          payload,
          source: RealtimeVoiceTextSource.outputTranscript,
          isFinal: payload['type'] == 'response.content_part.done',
          isCumulative: payload['type'] == 'response.content_part.done',
          textValue: transcript,
        );
      }
      return _parseAudio(payload, audioValue: part['audio']);
    }
    return null;
  }

  static RealtimeVoiceErrorEvent _parseError(Map<String, dynamic> payload) {
    final error = _asMap(payload['error']);
    return RealtimeVoiceErrorEvent(
      type: 'error',
      message: _boundedText(error?['message']) ?? '实时语音服务返回错误',
      errorType: _safeStatus(error?['type']),
      code: _safeStatus(error?['code']),
      param: redactRealtimeVoiceSecrets(_boundedText(error?['param']) ?? ''),
    );
  }
}

const Set<String> _knownLifecycleEvents = <String>{
  'input_audio_buffer.committed',
  'input_audio_buffer.cleared',
  'input_audio_buffer.speech_started',
  'input_audio_buffer.speech_stopped',
  'input_audio_buffer.timeout_triggered',
  'conversation.item.created',
  'conversation.item.deleted',
  'conversation.item.truncated',
  'response.output_item.added',
  'response.output_item.done',
  'response.content_part.added',
  'response.content_part.done',
  'response.audio.done',
  'response.output_audio.done',
};

/// State visible to UI.  It intentionally contains no credential, header, or
/// raw server payload.
class RealtimeVoiceSessionSnapshot {
  const RealtimeVoiceSessionSnapshot({
    required this.state,
    this.sessionId,
    this.activeResponseId,
    this.errorMessage,
    this.closeCode,
    this.closeReason,
  });

  const RealtimeVoiceSessionSnapshot.idle()
    : this(state: RealtimeVoiceSessionState.idle);

  final RealtimeVoiceSessionState state;
  final String? sessionId;
  final String? activeResponseId;
  final String? errorMessage;
  final int? closeCode;
  final String? closeReason;

  RealtimeVoiceSessionSnapshot copyWith({
    RealtimeVoiceSessionState? state,
    String? sessionId,
    bool clearSessionId = false,
    String? activeResponseId,
    bool clearActiveResponseId = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    int? closeCode,
    String? closeReason,
  }) {
    return RealtimeVoiceSessionSnapshot(
      state: state ?? this.state,
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      activeResponseId: clearActiveResponseId
          ? null
          : (activeResponseId ?? this.activeResponseId),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      closeCode: closeCode ?? this.closeCode,
      closeReason: closeReason ?? this.closeReason,
    );
  }

  @override
  String toString() =>
      'RealtimeVoiceSessionSnapshot('
      'state: $state, sessionId: $sessionId, activeResponseId: $activeResponseId, '
      'errorMessage: $errorMessage, closeCode: $closeCode, closeReason: $closeReason)';
}

enum RealtimeVoiceSessionErrorKind {
  invalidConfiguration,
  invalidState,
  cancelled,
  protocol,
  transport,
}

class RealtimeVoiceSessionException implements Exception {
  RealtimeVoiceSessionException(
    String message, {
    this.kind = RealtimeVoiceSessionErrorKind.transport,
  }) : message = redactRealtimeVoiceSecrets(message);

  final String message;
  final RealtimeVoiceSessionErrorKind kind;

  @override
  String toString() => message;
}

String _geminiModelResourceName(
  String? model,
  RealtimeVoiceGeminiLiveOptions options,
) {
  final value = model?.trim() ?? '';
  final prefix = options.modelResourcePrefix.trim();
  if (value.isEmpty || prefix.isEmpty || value.startsWith(prefix)) {
    return value;
  }
  return '$prefix$value';
}

List<String> _geminiResponseModalities(
  List<String>? modalities, {
  required bool audioOutputConfigured,
}) {
  if (modalities == null) return const <String>[];
  final normalized = modalities
      .map((value) => value.trim().toUpperCase())
      .where((value) => value.isNotEmpty)
      .map((value) => value == 'PCM' ? 'AUDIO' : value)
      .toSet()
      .toList(growable: false);
  // Native audio Live models only accept AUDIO as the response modality; the
  // text equivalent is delivered through outputAudioTranscription.  The
  // provider config still exposes the provider-neutral list so text-only
  // Gemini gateways can opt into TEXT when no audio output is configured.
  if (audioOutputConfigured) {
    return const <String>['AUDIO'];
  }
  return normalized;
}

String _geminiInputAudioMimeType(RealtimeVoiceSessionConfig config) {
  final override = config.geminiLiveOptions.inputAudioMimeType?.trim() ?? '';
  if (override.isNotEmpty) return override;
  final format = config.inputAudio;
  if (format == null) return 'audio/pcm;rate=16000';
  final type = format.type.trim().isEmpty ? 'audio/pcm' : format.type.trim();
  if (format.sampleRate == null || type.contains(';')) return type;
  return '$type;rate=${format.sampleRate}';
}

Map<String, dynamic> _buildSessionFields(RealtimeVoiceSessionConfig config) {
  final session = <String, dynamic>{};
  if (config.usesModernSessionFields) {
    if (config.instructions != null) {
      session['instructions'] = config.instructions;
    }
    if (config.voice != null) session['voice'] = config.voice;
    if (config.turnDetection != null) {
      session['turn_detection'] = config.turnDetection!.toJson();
    }
    if (config.outputModalities != null) {
      session['output_modalities'] = List<String>.from(
        config.outputModalities!,
      );
    }
    final audio = <String, dynamic>{};
    final input = <String, dynamic>{};
    final output = <String, dynamic>{};
    if (config.inputAudio != null) {
      input['format'] = config.inputAudio!.toJson();
    }
    if (config.inputAudioTransport == RealtimeVoiceAudioTransport.binary) {
      input['transport'] = 'binary';
    }
    if (config.transcriptionModel != null || config.languageHint != null) {
      input['transcription'] = <String, dynamic>{
        if (config.transcriptionModel != null)
          'model': config.transcriptionModel,
        if (config.languageHint != null) 'language_hint': config.languageHint,
      };
    }
    if (config.outputAudio != null) {
      output['format'] = config.outputAudio!.toJson();
    }
    if (config.outputAudioTransport == RealtimeVoiceAudioTransport.binary) {
      output['transport'] = 'binary';
    }
    if (input.isNotEmpty) audio['input'] = input;
    if (output.isNotEmpty) audio['output'] = output;
    if (audio.isNotEmpty) session['audio'] = audio;
  } else {
    if (config.instructions != null) {
      session['instructions'] = config.instructions;
    }
    if (config.voice != null) session['voice'] = config.voice;
    if (config.outputModalities != null) {
      session['modalities'] = List<String>.from(config.outputModalities!);
    }
    if (config.inputAudio != null) {
      session['input_audio_format'] = config.inputAudio!.legacyType;
    }
    if (config.outputAudio != null) {
      session['output_audio_format'] = config.outputAudio!.legacyType;
    }
    if (config.transcriptionModel != null || config.languageHint != null) {
      session['input_audio_transcription'] = <String, dynamic>{
        if (config.transcriptionModel != null)
          'model': config.transcriptionModel,
        if (config.languageHint != null) 'language': config.languageHint,
      };
    }
  }
  if (config.turnDetection != null && !config.usesModernSessionFields) {
    session['turn_detection'] = config.turnDetection!.toJson();
  }
  return _deepMerge(session, config.additionalSessionFields);
}

Map<String, dynamic> _deepMerge(
  Map<String, dynamic> base,
  Map<String, dynamic> overrides,
) {
  final result = _copyJsonMap(base);
  for (final entry in overrides.entries) {
    final current = result[entry.key];
    final override = entry.value;
    if (current is Map && override is Map) {
      result[entry.key] = _deepMerge(
        current.map((key, value) => MapEntry(key.toString(), value)),
        override.map((key, value) => MapEntry(key.toString(), value)),
      );
    } else {
      result[entry.key] = _copyJsonValue(override);
    }
  }
  return result;
}

Map<String, dynamic> _copyJsonMap(Map<String, dynamic> source) =>
    source.map((key, value) => MapEntry(key, _copyJsonValue(value)));

Object? _copyJsonValue(Object? value) {
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(key.toString(), _copyJsonValue(nested)),
    );
  }
  if (value is Iterable) return value.map(_copyJsonValue).toList();
  return value;
}

Map<String, dynamic>? _decodeMap(Object? raw) {
  Object? decoded = raw;
  if (raw is String) {
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
  return _asMap(decoded);
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, nested) => MapEntry(key.toString(), nested));
}

String? _safeEventType(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  if (text.isEmpty || text.length > 128) return null;
  if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(text)) return null;
  return text;
}

String? _safeIdentifier(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  if (text.isEmpty || text.length > 160) return null;
  if (!RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(text)) return null;
  return text;
}

String? _safeStatus(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  if (text.isEmpty || text.length > 80) return null;
  if (!RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(text)) return null;
  return text;
}

String? _boundedText(Object? value) {
  if (value is! String || value.length > _maxTextLength) return null;
  return value;
}

/// Removes common bearer, API-key, token, and secret forms from diagnostics.
/// This function is intentionally conservative: unknown server event fields
/// are not exposed at all, while known human-readable messages remain useful.
String redactRealtimeVoiceSecrets(String value) {
  var redacted = value;
  redacted = redacted.replaceAllMapped(
    RegExp(r'\bBearer\s+[^\s,;]+', caseSensitive: false),
    (_) => 'Bearer ***',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(
      r'\b(?:sk|xai|ek|sess|rt|client[_-]?secret)[-_][A-Za-z0-9._~-]+\b',
      caseSensitive: false,
    ),
    (_) => '***',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(
      r'((?:api[_-]?key|token|secret|client[_-]?secret|authorization)\s*[:=]\s*)[^\s,;&}]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}***',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(
      r'([?&](?:api[_-]?key|x-goog-api-key|key|token|secret|client[_-]?secret|authorization)=)[^&#\s]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}***',
  );
  if (redacted.length > _maxErrorLength) {
    redacted = redacted.substring(0, _maxErrorLength);
  }
  return redacted;
}

const int _maxTextLength = 1024 * 1024;
const int _maxAudioBase64Length = 16 * 1024 * 1024;
const int _maxErrorLength = 512;
