import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/key_encryptor.dart';
import '../../core/media/realtime_pcm_audio.dart';
import '../../core/media/realtime_voice_session.dart';

const kRealtimeVoiceProviderStorageKey = 'realtime_voice_provider_v1';
const kRealtimeVoiceEndpointStorageKey = 'realtime_voice_endpoint_v1';
const kRealtimeVoiceModelStorageKey = 'realtime_voice_model_v1';
const kRealtimeVoiceVoiceStorageKey = 'realtime_voice_voice_v1';
const kRealtimeVoiceAuthModeStorageKey = 'realtime_voice_auth_mode_v1';
const kRealtimeVoiceTokenStorageKey = 'realtime_voice_token_encrypted_v1';
const kRealtimeVoiceProtocolPrefixStorageKey =
    'realtime_voice_protocol_prefix_v1';

const kDefaultRealtimeVoiceOpenAiEndpoint = 'wss://api.openai.com/v1/realtime';
const kDefaultRealtimeVoiceXaiEndpoint = 'wss://api.x.ai/v1/realtime';
const kDefaultRealtimeVoiceGeminiEndpoint =
    'wss://generativelanguage.googleapis.com/ws/'
    'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';
const kDefaultRealtimeVoiceOpenAiModel = 'gpt-realtime';
const kDefaultRealtimeVoiceXaiModel = 'grok-voice-latest';
const kDefaultRealtimeVoiceGeminiModel = 'gemini-3.1-flash-live-preview';
const kDefaultRealtimeVoiceGeminiVoice = 'Kore';
const kDefaultRealtimeVoiceVoice = 'alloy';

/// Configuration owned by the realtime voice UI.
///
/// [token] is intentionally kept only in memory and is never included in
/// [toString] or [RealtimeVoiceState].toString(). It is persisted encrypted
/// through [RealtimeVoiceController.saveConfig].
class RealtimeVoiceConfig {
  const RealtimeVoiceConfig({
    this.provider = RealtimeVoiceProvider.openAi,
    this.endpoint = kDefaultRealtimeVoiceOpenAiEndpoint,
    this.model = kDefaultRealtimeVoiceOpenAiModel,
    this.voice = kDefaultRealtimeVoiceVoice,
    this.authMode = RealtimeVoiceAuthMode.bearer,
    this.token = '',
    this.protocolPrefix,
  });

  final RealtimeVoiceProvider provider;
  final String endpoint;
  final String model;
  final String voice;
  final RealtimeVoiceAuthMode authMode;
  final String token;
  final String? protocolPrefix;

  bool get hasToken => token.trim().isNotEmpty;

  bool get isConfigured {
    final uri = Uri.tryParse(endpoint.trim());
    return hasToken &&
        uri != null &&
        uri.scheme.toLowerCase() == 'wss' &&
        uri.host.trim().isNotEmpty &&
        model.trim().isNotEmpty;
  }

  String get providerLabel => switch (provider) {
    RealtimeVoiceProvider.openAi => 'OpenAI Realtime',
    RealtimeVoiceProvider.xAi => 'xAI Realtime',
    RealtimeVoiceProvider.geminiLive => 'Gemini Live',
    RealtimeVoiceProvider.custom => '自定义 Realtime',
  };

  String get safeSummary {
    final endpointUri = Uri.tryParse(endpoint.trim());
    final endpointLabel = endpointUri == null
        ? endpoint.trim()
        : '${endpointUri.scheme}://${endpointUri.host}${endpointUri.path}';
    return '$providerLabel · ${model.trim().isEmpty ? '未设置模型' : model.trim()} · $endpointLabel';
  }

  String get statusLabel {
    if (endpoint.trim().isEmpty) return '未配置 endpoint';
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'wss') {
      return 'endpoint 必须使用 wss://';
    }
    if (model.trim().isEmpty) return '未配置模型';
    if (!hasToken) return '未配置实时语音凭据';
    return '已配置 · $providerLabel · ${model.trim()}';
  }

  RealtimeVoiceSessionConfig toSessionConfig() {
    final uri = Uri.parse(endpoint.trim());
    final auth = provider == RealtimeVoiceProvider.geminiLive
        ? RealtimeVoiceAuth.apiKeyHeader(token.trim())
        : authMode == RealtimeVoiceAuthMode.ephemeral
        ? RealtimeVoiceAuth.ephemeral(
            token.trim(),
            protocolPrefix: protocolPrefix?.trim().isEmpty == true
                ? null
                : protocolPrefix?.trim(),
          )
        : RealtimeVoiceAuth.bearer(token.trim());
    final input = const RealtimeVoiceAudioFormat.pcm16(sampleRate: 16000);
    final output = const RealtimeVoiceAudioFormat.pcm16(sampleRate: 24000);
    final turnDetection = const RealtimeVoiceTurnDetection.serverVad(
      silenceDurationMs: 700,
      prefixPaddingMs: 300,
    );

    return switch (provider) {
      RealtimeVoiceProvider.openAi => RealtimeVoiceSessionConfig.openAi(
        auth: auth,
        endpoint: uri,
        model: model.trim(),
        voice: voice.trim().isEmpty ? null : voice.trim(),
        inputAudio: input,
        outputAudio: output,
        transcriptionModel: 'gpt-4o-mini-transcribe',
        turnDetection: turnDetection,
        outputModalities: const ['text', 'audio'],
      ),
      RealtimeVoiceProvider.xAi => RealtimeVoiceSessionConfig.xAi(
        auth: auth,
        endpoint: uri,
        model: model.trim(),
        voice: voice.trim().isEmpty ? null : voice.trim(),
        inputAudio: input,
        outputAudio: output,
        // xAI emits cumulative input transcript events only when the
        // documented transcription model is explicitly selected.
        transcriptionModel: 'grok-transcribe',
        languageHint: 'auto',
        turnDetection: turnDetection,
        outputModalities: const ['text', 'audio'],
      ),
      RealtimeVoiceProvider.geminiLive => RealtimeVoiceSessionConfig.geminiLive(
        auth: auth,
        endpoint: uri,
        model: model.trim(),
        voice: voice.trim().isEmpty ? null : voice.trim(),
        inputAudio: input,
        outputAudio: output,
        languageHint: 'auto',
        turnDetection: turnDetection,
        // Native audio Live models accept AUDIO; text is exposed through the
        // outputAudioTranscription setup field and mapped by the session.
        outputModalities: const ['AUDIO'],
      ),
      RealtimeVoiceProvider.custom => RealtimeVoiceSessionConfig(
        endpoint: uri,
        auth: auth,
        provider: RealtimeVoiceProvider.custom,
        model: model.trim(),
        voice: voice.trim().isEmpty ? null : voice.trim(),
        inputAudio: input,
        outputAudio: output,
        turnDetection: turnDetection,
        outputModalities: const ['text', 'audio'],
      ),
    };
  }

  RealtimeVoiceConfig copyWith({
    RealtimeVoiceProvider? provider,
    String? endpoint,
    String? model,
    String? voice,
    RealtimeVoiceAuthMode? authMode,
    String? token,
    String? protocolPrefix,
    bool clearToken = false,
    bool clearProtocolPrefix = false,
  }) {
    return RealtimeVoiceConfig(
      provider: provider ?? this.provider,
      endpoint: endpoint ?? this.endpoint,
      model: model ?? this.model,
      voice: voice ?? this.voice,
      authMode: authMode ?? this.authMode,
      token: clearToken ? '' : (token ?? this.token),
      protocolPrefix: clearProtocolPrefix
          ? null
          : (protocolPrefix ?? this.protocolPrefix),
    );
  }

  @override
  String toString() =>
      'RealtimeVoiceConfig(provider: $provider, endpoint: ${redactRealtimeVoiceSecrets(endpoint)}, model: $model, '
      'voice: $voice, authMode: $authMode, hasToken: $hasToken)';
}

class RealtimeVoiceState {
  const RealtimeVoiceState({
    this.config = const RealtimeVoiceConfig(),
    this.snapshot = const RealtimeVoiceSessionSnapshot.idle(),
    this.inputTranscript = '',
    this.outputText = '',
    this.outputTranscript = '',
    this.receivedAudioBytes = 0,
    this.nativeAudioActive = false,
    this.nativeAudioError,
    this.errorMessage,
  });

  final RealtimeVoiceConfig config;
  final RealtimeVoiceSessionSnapshot snapshot;
  final String inputTranscript;
  final String outputText;
  final String outputTranscript;
  final int receivedAudioBytes;
  final bool nativeAudioActive;
  final String? nativeAudioError;
  final String? errorMessage;

  RealtimeVoiceSessionState get sessionState => snapshot.state;
  bool get isConnected => sessionState == RealtimeVoiceSessionState.connected;
  bool get isBusy => switch (sessionState) {
    RealtimeVoiceSessionState.connecting ||
    RealtimeVoiceSessionState.closing ||
    RealtimeVoiceSessionState.cancelling => true,
    _ => false,
  };

  RealtimeVoiceState copyWith({
    RealtimeVoiceConfig? config,
    RealtimeVoiceSessionSnapshot? snapshot,
    String? inputTranscript,
    String? outputText,
    String? outputTranscript,
    int? receivedAudioBytes,
    bool? nativeAudioActive,
    String? nativeAudioError,
    bool clearNativeAudioError = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return RealtimeVoiceState(
      config: config ?? this.config,
      snapshot: snapshot ?? this.snapshot,
      inputTranscript: inputTranscript ?? this.inputTranscript,
      outputText: outputText ?? this.outputText,
      outputTranscript: outputTranscript ?? this.outputTranscript,
      receivedAudioBytes: receivedAudioBytes ?? this.receivedAudioBytes,
      nativeAudioActive: nativeAudioActive ?? this.nativeAudioActive,
      nativeAudioError: clearNativeAudioError
          ? null
          : (nativeAudioError ?? this.nativeAudioError),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  String toString() =>
      'RealtimeVoiceState(config: $config, snapshot: $snapshot, '
      'inputTranscript: $inputTranscript, outputText: $outputText, '
      'outputTranscript: $outputTranscript, receivedAudioBytes: $receivedAudioBytes, '
      'nativeAudioActive: $nativeAudioActive, '
      'nativeAudioError: $nativeAudioError, '
      'errorMessage: $errorMessage)';
}

final realtimeVoiceProvider =
    StateNotifierProvider<RealtimeVoiceController, RealtimeVoiceState>(
      (ref) => RealtimeVoiceController(),
    );

/// 编排一个用户可见的 Realtime Voice 对话。
///
/// 控制器拥有 Realtime WebSocket/session 生命周期及文本/事件状态。实时 PCM
/// 采集和播放交给 [RealtimePcmAudioPlatform]：Android 已通过
/// AudioRecord/AudioTrack 接入；非 Android 取决于对应平台 bridge，可能报告
/// unsupported。普通文件录音不作为 PCM 流使用。当前 provider/UI 测试只覆盖
/// 本地生命周期和注入边界，不证明真实 Realtime WebSocket 或云端音频 E2E。
class RealtimeVoiceController extends StateNotifier<RealtimeVoiceState> {
  RealtimeVoiceController({
    RealtimeVoiceSocketConnector? connector,
    RealtimePcmAudioPlatform? pcmAudio,
  }) : _connector = connector,
       _pcmAudio = pcmAudio ?? MethodChannelRealtimePcmAudio(),
       super(const RealtimeVoiceState()) {
    ready = _load();
  }

  final RealtimeVoiceSocketConnector? _connector;
  final RealtimePcmAudioPlatform _pcmAudio;
  late final Future<void> ready;

  SharedPreferences? _prefs;
  RealtimeVoiceSession? _session;
  StreamSubscription<RealtimeVoiceEvent>? _eventSubscription;
  StreamSubscription<RealtimeVoiceSessionSnapshot>? _stateSubscription;
  StreamSubscription<Uint8List>? _captureSubscription;
  Future<void> _playbackQueue = Future<void>.value();
  bool _nativeAudioStarting = false;
  bool _nativeAudioStopping = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    final provider = _providerFromString(
      prefs.getString(kRealtimeVoiceProviderStorageKey),
    );
    final endpoint =
        prefs.getString(kRealtimeVoiceEndpointStorageKey) ??
        _defaultEndpoint(provider);
    final model =
        prefs.getString(kRealtimeVoiceModelStorageKey) ??
        _defaultModel(provider);
    final voice =
        prefs.getString(kRealtimeVoiceVoiceStorageKey) ??
        kDefaultRealtimeVoiceVoice;
    final authMode = provider == RealtimeVoiceProvider.geminiLive
        ? RealtimeVoiceAuthMode.apiKeyHeader
        : _authModeFromString(
            prefs.getString(kRealtimeVoiceAuthModeStorageKey),
          );
    var token = '';
    final encryptedToken = prefs.getString(kRealtimeVoiceTokenStorageKey);
    if (encryptedToken != null && encryptedToken.isNotEmpty) {
      try {
        token = KeyEncryptor.decryptOrEmpty(encryptedToken);
      } catch (_) {
        token = '';
      }
    }
    final protocolPrefix = prefs.getString(
      kRealtimeVoiceProtocolPrefixStorageKey,
    );
    if (!mounted) return;
    state = state.copyWith(
      config: RealtimeVoiceConfig(
        provider: provider,
        endpoint: endpoint,
        model: model,
        voice: voice,
        authMode: authMode,
        token: token,
        protocolPrefix: protocolPrefix,
      ),
    );
  }

  Future<void> saveConfig(RealtimeVoiceConfig config) async {
    final normalized = config.copyWith(
      endpoint: config.endpoint.trim(),
      model: config.model.trim(),
      voice: config.voice.trim(),
      protocolPrefix: config.protocolPrefix?.trim(),
      authMode: config.provider == RealtimeVoiceProvider.geminiLive
          ? RealtimeVoiceAuthMode.apiKeyHeader
          : config.authMode,
    );
    _validateConfigShape(normalized);
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(
      kRealtimeVoiceProviderStorageKey,
      normalized.provider.name,
    );
    await prefs.setString(
      kRealtimeVoiceEndpointStorageKey,
      normalized.endpoint,
    );
    await prefs.setString(kRealtimeVoiceModelStorageKey, normalized.model);
    await prefs.setString(kRealtimeVoiceVoiceStorageKey, normalized.voice);
    await prefs.setString(
      kRealtimeVoiceAuthModeStorageKey,
      normalized.authMode.name,
    );
    if (normalized.token.trim().isEmpty) {
      await prefs.remove(kRealtimeVoiceTokenStorageKey);
    } else {
      await prefs.setString(
        kRealtimeVoiceTokenStorageKey,
        KeyEncryptor.encrypt(normalized.token.trim()),
      );
    }
    final prefix = normalized.protocolPrefix?.trim() ?? '';
    if (prefix.isEmpty) {
      await prefs.remove(kRealtimeVoiceProtocolPrefixStorageKey);
    } else {
      await prefs.setString(kRealtimeVoiceProtocolPrefixStorageKey, prefix);
    }
    if (!mounted) return;
    state = state.copyWith(config: normalized, clearErrorMessage: true);
  }

  Future<void> connect() async {
    await ready;
    if (state.isConnected || state.isBusy) return;
    final config = state.config;
    if (!config.isConfigured) {
      final error = RealtimeVoiceSessionException(
        config.statusLabel,
        kind: RealtimeVoiceSessionErrorKind.invalidConfiguration,
      );
      _setError(error.message);
      throw error;
    }

    await _disposeSession();
    final session = RealtimeVoiceSession(
      config.toSessionConfig(),
      connector: _connector,
    );
    _session = session;
    _eventSubscription = session.events.listen(_handleEvent);
    _stateSubscription = session.states.listen(_handleSnapshot);
    if (mounted) state = state.copyWith(clearErrorMessage: true);
    try {
      await session.connect();
    } catch (error) {
      _setError(_messageFor(error));
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final session = _session;
    if (session == null) return;
    try {
      await session.close(reason: '用户结束实时语音对话');
    } catch (error) {
      _setError(_messageFor(error));
    } finally {
      await _disposeSession(clearSnapshot: false);
    }
  }

  Future<void> cancel() async {
    final session = _session;
    if (session == null) return;
    try {
      await session.cancel(reason: '用户取消实时语音对话');
    } catch (error) {
      _setError(_messageFor(error));
    } finally {
      await _disposeSession(clearSnapshot: false);
    }
  }

  Future<void> cancelResponse() async {
    final session = _session;
    if (session == null || !state.isConnected) return;
    try {
      await session.cancelResponse();
    } catch (error) {
      _setError(_messageFor(error));
    }
  }

  /// 在 WebSocket session 已连接后启动原生 PCM 麦克风和扬声器。Android 通过
  /// AudioRecord/AudioTrack 提供实现；非 Android 由对应平台 bridge 决定。
  /// 普通文件录音不用于此路径：每个输入块直接发送到 realtime session，
  /// 每个输出音频 delta 都排入原生扬声器队列。
  Future<void> startNativeAudio() async {
    await ready;
    _requireConnected();
    if (state.nativeAudioActive || _nativeAudioStarting) return;
    if (_nativeAudioStopping) {
      throw const RealtimePcmAudioException(
        message: '实时 PCM 音频正在停止，请稍后重试',
        kind: RealtimePcmAudioErrorKind.invalidState,
        code: 'STOP_IN_PROGRESS',
      );
    }

    _nativeAudioStarting = true;
    StreamSubscription<Uint8List>? captureSubscription;
    try {
      captureSubscription = _pcmAudio.inputPcm.listen(
        _handleCapturedPcm,
        onError: (Object error, StackTrace stackTrace) {
          _setNativeAudioError(error);
          unawaited(stopNativeAudio());
        },
        cancelOnError: false,
      );
      await _pcmAudio.startPlayback(
        sampleRate: kRealtimePcmOutputSampleRate,
        channels: kRealtimePcmChannels,
        bitsPerSample: kRealtimePcmBitsPerSample,
      );
      await _pcmAudio.startCapture(
        sampleRate: kRealtimePcmInputSampleRate,
        channels: kRealtimePcmChannels,
        bitsPerSample: kRealtimePcmBitsPerSample,
      );
      _captureSubscription = captureSubscription;
      captureSubscription = null;
      if (!mounted) return;
      state = state.copyWith(
        nativeAudioActive: true,
        clearNativeAudioError: true,
      );
    } catch (error) {
      await captureSubscription?.cancel();
      await _stopNativePlatformAudio();
      _setNativeAudioError(error);
      rethrow;
    } finally {
      _nativeAudioStarting = false;
    }
  }

  Future<void> stopNativeAudio() async {
    if (_nativeAudioStopping) return;
    if (!state.nativeAudioActive &&
        _captureSubscription == null &&
        !_nativeAudioStarting) {
      return;
    }
    _nativeAudioStopping = true;
    final subscription = _captureSubscription;
    _captureSubscription = null;
    if (mounted && state.nativeAudioActive) {
      state = state.copyWith(nativeAudioActive: false);
    }
    try {
      await subscription?.cancel();
      await _stopNativePlatformAudio();
    } catch (error) {
      _setNativeAudioError(error);
    } finally {
      _nativeAudioStopping = false;
    }
  }

  void _handleCapturedPcm(Uint8List bytes) {
    if (bytes.isEmpty || !state.nativeAudioActive || !state.isConnected) {
      return;
    }
    final session = _session;
    if (session == null) return;
    unawaited(
      session.sendPcm(bytes).catchError((Object error, StackTrace stackTrace) {
        _setNativeAudioError(error);
        unawaited(stopNativeAudio());
      }),
    );
  }

  void _enqueueRealtimePlayback(Uint8List bytes) {
    if (bytes.isEmpty || !state.nativeAudioActive) return;
    _playbackQueue = _playbackQueue.then((_) async {
      if (!state.nativeAudioActive) return;
      try {
        await _pcmAudio.writePlayback(bytes);
      } catch (error) {
        _setNativeAudioError(error);
        unawaited(stopNativeAudio());
      }
    });
  }

  Future<void> _stopNativePlatformAudio() async {
    Object? firstError;
    try {
      await _pcmAudio.stopCapture();
    } catch (error) {
      firstError ??= error;
    }
    try {
      await _playbackQueue;
    } catch (error) {
      firstError ??= error;
    }
    try {
      await _pcmAudio.stopPlayback();
    } catch (error) {
      firstError ??= error;
    }
    _playbackQueue = Future<void>.value();
    if (firstError != null) throw firstError;
  }

  void _setNativeAudioError(Object error) {
    if (!mounted) return;
    final message = error is RealtimePcmAudioException
        ? error.message
        : _messageFor(error);
    state = state.copyWith(nativeAudioError: message, nativeAudioActive: false);
  }

  Future<void> sendText(String text) async {
    final session = _requireConnected();
    try {
      await session.sendText(text);
    } catch (error) {
      _setError(_messageFor(error));
      rethrow;
    }
  }

  Future<void> sendPcm(List<int> bytes) async {
    final session = _requireConnected();
    try {
      await session.sendPcm(bytes);
    } catch (error) {
      _setError(_messageFor(error));
      rethrow;
    }
  }

  Future<void> sendAudioBase64(String base64Audio) async {
    final session = _requireConnected();
    try {
      await session.sendAudioBase64(base64Audio);
    } catch (error) {
      _setError(_messageFor(error));
      rethrow;
    }
  }

  Future<void> commitInputAudio() async {
    final session = _requireConnected();
    try {
      await session.commitInputAudio();
    } catch (error) {
      _setError(_messageFor(error));
      rethrow;
    }
  }

  Future<void> createResponse() async {
    final session = _requireConnected();
    try {
      await session.createResponse();
    } catch (error) {
      _setError(_messageFor(error));
      rethrow;
    }
  }

  void clearTranscript() {
    if (!mounted) return;
    state = state.copyWith(
      inputTranscript: '',
      outputText: '',
      outputTranscript: '',
      receivedAudioBytes: 0,
      clearErrorMessage: true,
    );
  }

  void _handleSnapshot(RealtimeVoiceSessionSnapshot snapshot) {
    if (!mounted) return;
    state = state.copyWith(
      snapshot: snapshot,
      errorMessage: snapshot.errorMessage,
      clearErrorMessage: snapshot.errorMessage == null,
    );
  }

  void _handleEvent(RealtimeVoiceEvent event) {
    if (!mounted) return;
    if (event is RealtimeVoiceTextEvent) {
      final current = switch (event.source) {
        RealtimeVoiceTextSource.inputTranscript => state.inputTranscript,
        RealtimeVoiceTextSource.outputText => state.outputText,
        RealtimeVoiceTextSource.outputTranscript => state.outputTranscript,
      };
      final next = event.isCumulative ? event.text : '$current${event.delta}';
      state = switch (event.source) {
        RealtimeVoiceTextSource.inputTranscript => state.copyWith(
          inputTranscript: next,
        ),
        RealtimeVoiceTextSource.outputText => state.copyWith(outputText: next),
        RealtimeVoiceTextSource.outputTranscript => state.copyWith(
          outputTranscript: next,
        ),
      };
    } else if (event is RealtimeVoiceAudioEvent) {
      state = state.copyWith(
        receivedAudioBytes: state.receivedAudioBytes + event.bytes.length,
      );
      _enqueueRealtimePlayback(event.bytes);
    } else if (event is RealtimeVoiceErrorEvent) {
      _setError(event.message);
    }
  }

  RealtimeVoiceSession _requireConnected() {
    final session = _session;
    if (session == null || !state.isConnected) {
      throw RealtimeVoiceSessionException(
        '请先连接实时语音',
        kind: RealtimeVoiceSessionErrorKind.invalidState,
      );
    }
    return session;
  }

  Future<void> _disposeSession({bool clearSnapshot = true}) async {
    await stopNativeAudio();
    final session = _session;
    _session = null;
    if (session != null && !session.isTerminal) {
      try {
        await session.close(reason: '实时语音 session replaced');
      } catch (_) {
        // Teardown is best effort; the next session owns a fresh socket.
      }
    }
    await _eventSubscription?.cancel();
    await _stateSubscription?.cancel();
    _eventSubscription = null;
    _stateSubscription = null;
    if (mounted && clearSnapshot) {
      state = state.copyWith(
        snapshot: const RealtimeVoiceSessionSnapshot.idle(),
        clearErrorMessage: true,
      );
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    state = state.copyWith(errorMessage: message);
  }

  String _messageFor(Object error) {
    if (error is RealtimeVoiceSessionException) return error.message;
    return redactRealtimeVoiceSecrets(error.toString());
  }

  static void _validateConfigShape(RealtimeVoiceConfig config) {
    final uri = Uri.tryParse(config.endpoint.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'wss' || uri.host.isEmpty) {
      throw const FormatException('实时语音 endpoint 必须是有效的 wss URL');
    }
    const sensitiveQueryKeys = <String>{
      'api_key',
      'apikey',
      'authorization',
      'client_secret',
      'secret',
      'token',
    };
    if (uri.queryParameters.keys.any(
      (key) => sensitiveQueryKeys.contains(key.toLowerCase()),
    )) {
      throw const FormatException('实时语音 endpoint 不得通过 query 传递凭据');
    }
    if (config.provider == RealtimeVoiceProvider.geminiLive &&
        uri.queryParameters.keys.any(
          (key) => const {
            'key',
            'access_token',
            'api-key',
            'x-goog-api-key',
          }.contains(key.toLowerCase()),
        )) {
      throw const FormatException('Gemini Live endpoint 不得通过 query 传递凭据');
    }
    if (config.model.trim().isEmpty) {
      throw const FormatException('实时语音模型不能为空');
    }
    if (config.provider == RealtimeVoiceProvider.geminiLive &&
        config.authMode != RealtimeVoiceAuthMode.apiKeyHeader) {
      throw const FormatException(
        'Gemini Live 必须通过 x-goog-api-key header 传递凭据',
      );
    }
    if (config.authMode == RealtimeVoiceAuthMode.ephemeral &&
        config.provider == RealtimeVoiceProvider.custom &&
        config.protocolPrefix?.trim().isEmpty != false) {
      throw const FormatException('custom ephemeral 模式需要 protocolPrefix');
    }
  }

  static RealtimeVoiceProvider _providerFromString(String? value) {
    return RealtimeVoiceProvider.values.firstWhere(
      (item) => item.name == value,
      orElse: () => RealtimeVoiceProvider.openAi,
    );
  }

  static RealtimeVoiceAuthMode _authModeFromString(String? value) {
    return RealtimeVoiceAuthMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => RealtimeVoiceAuthMode.bearer,
    );
  }

  static String _defaultEndpoint(RealtimeVoiceProvider provider) =>
      switch (provider) {
        RealtimeVoiceProvider.xAi => kDefaultRealtimeVoiceXaiEndpoint,
        RealtimeVoiceProvider.geminiLive => kDefaultRealtimeVoiceGeminiEndpoint,
        _ => kDefaultRealtimeVoiceOpenAiEndpoint,
      };

  static String _defaultModel(RealtimeVoiceProvider provider) =>
      switch (provider) {
        RealtimeVoiceProvider.xAi => kDefaultRealtimeVoiceXaiModel,
        RealtimeVoiceProvider.geminiLive => kDefaultRealtimeVoiceGeminiModel,
        _ => kDefaultRealtimeVoiceOpenAiModel,
      };

  @override
  void dispose() {
    unawaited(_disposeSession());
    super.dispose();
  }
}
