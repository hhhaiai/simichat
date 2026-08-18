import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'realtime_voice_models.dart';

export 'realtime_voice_models.dart';

/// Native WebSocket abstraction used by [RealtimeVoiceSession].
///
/// Production uses [NativeRealtimeVoiceSocket].  Tests and a future platform
/// adapter can inject a fake without opening a network connection.
abstract interface class RealtimeVoiceSocket {
  Stream<Object?> get incoming;

  void add(Object message);

  Future<void> close({int? code, String? reason});
}

/// Handshake arguments passed to a [RealtimeVoiceSocketConnector].
///
/// The object is short-lived and never stored in a session snapshot.  Its
/// [toString] redacts Authorization and ephemeral subprotocol values so it is
/// safe to include in a diagnostic object if a caller needs one.
class RealtimeVoiceSocketOptions {
  RealtimeVoiceSocketOptions({
    required this.uri,
    required Map<String, String> headers,
    required List<String> protocols,
    required this.connectTimeout,
    required this.pingInterval,
  }) : headers = Map<String, String>.unmodifiable(headers),
       protocols = List<String>.unmodifiable(protocols);

  final Uri uri;
  final Map<String, String> headers;
  final List<String> protocols;
  final Duration connectTimeout;
  final Duration? pingInterval;

  @override
  String toString() =>
      'RealtimeVoiceSocketOptions('
      'uri: ${redactRealtimeVoiceSecrets(uri.toString())}, '
      'headers: ${_redactedHeaders(headers)}, '
      'protocols: ${_redactedProtocols(protocols)})';
}

/// Injectable connector signature for native WebSocket handshakes.
typedef RealtimeVoiceSocketConnector =
    Future<RealtimeVoiceSocket> Function(RealtimeVoiceSocketOptions options);

/// Adapter around dart:io's native [WebSocket].
class NativeRealtimeVoiceSocket implements RealtimeVoiceSocket {
  const NativeRealtimeVoiceSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get incoming => _socket.cast<Object?>();

  @override
  void add(Object message) => _socket.add(message);

  @override
  Future<void> close({int? code, String? reason}) async {
    await _socket.close(code, reason);
  }
}

/// Opens a native dart:io WebSocket using the supplied handshake options.
Future<RealtimeVoiceSocket> connectNativeRealtimeVoiceSocket(
  RealtimeVoiceSocketOptions options,
) async {
  final socket = await WebSocket.connect(
    options.uri.toString(),
    protocols: options.protocols.isEmpty ? null : options.protocols,
    headers: options.headers.isEmpty
        ? null
        : <String, dynamic>{...options.headers},
  ).timeout(options.connectTimeout);
  socket.pingInterval = options.pingInterval;
  return NativeRealtimeVoiceSocket(socket);
}

/// Reusable realtime voice session core.
///
/// A UI layer owns one instance for one voice conversation and subscribes to
/// [events] and [states].  The class handles only protocol transport and safe
/// event normalization; microphone capture, PCM resampling, and audio
/// playback remain platform/UI responsibilities.
class RealtimeVoiceSession {
  RealtimeVoiceSession(this.config, {RealtimeVoiceSocketConnector? connector})
    : _connector = connector ?? connectNativeRealtimeVoiceSocket;

  final RealtimeVoiceSessionConfig config;
  final RealtimeVoiceSocketConnector _connector;
  final StreamController<RealtimeVoiceEvent> _eventController =
      StreamController<RealtimeVoiceEvent>.broadcast(sync: true);
  final StreamController<RealtimeVoiceSessionSnapshot> _stateController =
      StreamController<RealtimeVoiceSessionSnapshot>.broadcast(sync: true);
  final Completer<void> _doneCompleter = Completer<void>();
  final Map<String, String> _cumulativeInputTranscripts = <String, String>{};

  RealtimeVoiceSessionSnapshot _snapshot =
      const RealtimeVoiceSessionSnapshot.idle();
  RealtimeVoiceSocket? _socket;
  StreamSubscription<Object?>? _incomingSubscription;
  CancelToken? _cancelToken;
  String? _activeResponseId;
  bool _terminal = false;
  bool _controllersClosed = false;

  Stream<RealtimeVoiceEvent> get events => _eventController.stream;

  Stream<RealtimeVoiceSessionSnapshot> get states => _stateController.stream;

  RealtimeVoiceSessionSnapshot get snapshot => _snapshot;

  Future<void> get done => _doneCompleter.future;

  bool get isTerminal => _terminal;

  /// Opens the socket, attaches listeners, and sends the initial
  /// `session.update` unless disabled in [RealtimeVoiceSessionConfig].
  Future<void> connect({CancelToken? cancelToken}) async {
    if (_snapshot.state != RealtimeVoiceSessionState.idle) {
      throw RealtimeVoiceSessionException(
        '实时语音 session 只能连接一次',
        kind: RealtimeVoiceSessionErrorKind.invalidState,
      );
    }

    try {
      config.validate();
    } on RealtimeVoiceSessionException catch (error) {
      _finishTerminal(
        RealtimeVoiceSessionState.failed,
        errorMessage: error.message,
      );
      rethrow;
    }

    _setState(RealtimeVoiceSessionState.connecting);
    if (cancelToken != null) {
      _cancelToken = cancelToken;
      _watchCancelToken(cancelToken);
      if (cancelToken.isCancelled) {
        _finishTerminal(RealtimeVoiceSessionState.cancelled);
        throw _cancelledException();
      }
    }

    final options = _buildSocketOptions();
    RealtimeVoiceSocket socket;
    try {
      socket = await _connector(options).timeout(config.connectTimeout);
    } catch (error) {
      if (_terminal || _snapshot.state == RealtimeVoiceSessionState.cancelled) {
        throw _cancelledException();
      }
      final exception = _connectionException(error);
      _finishTerminal(
        RealtimeVoiceSessionState.failed,
        errorMessage: exception.message,
      );
      throw exception;
    }

    if (_terminal || _snapshot.state != RealtimeVoiceSessionState.connecting) {
      await _safeCloseSocket(socket, reason: 'cancelled');
      throw _cancelledException();
    }

    _socket = socket;
    _incomingSubscription = socket.incoming.listen(
      _handleIncoming,
      onError: (Object error, StackTrace stackTrace) {
        _handleSocketError(error);
      },
      onDone: _handleSocketDone,
      cancelOnError: false,
    );
    _setState(RealtimeVoiceSessionState.connected);

    if (config.sendSessionUpdate) {
      try {
        await _sendJson(RealtimeVoiceProtocol.sessionUpdate(config));
      } catch (error) {
        final exception = _asSessionException(error);
        await _safeCloseSocket(socket, reason: 'session update failed');
        _finishTerminal(
          RealtimeVoiceSessionState.failed,
          errorMessage: exception.message,
        );
        throw exception;
      }
    }
  }

  /// Binds an existing Dio [CancelToken] to this session.  Cancellation
  /// sends `response.cancel` when a response is active and then closes the
  /// WebSocket with terminal state [RealtimeVoiceSessionState.cancelled].
  Future<void> bindCancelToken(CancelToken token) async {
    if (_terminal) return;
    _cancelToken = token;
    _watchCancelToken(token);
    if (token.isCancelled) await cancel();
  }

  /// Sends a PCM/codec chunk.  JSON transport encodes it as base64; binary
  /// transport sends the bytes directly as a WebSocket binary frame.
  Future<void> sendPcm(List<int> pcmBytes) async {
    _ensureConnected();
    final bytes = Uint8List.fromList(pcmBytes);
    if (bytes.isEmpty) {
      throw RealtimeVoiceSessionException(
        '实时语音音频块为空',
        kind: RealtimeVoiceSessionErrorKind.protocol,
      );
    }
    if (config.inputAudioTransport == RealtimeVoiceAudioTransport.binary) {
      try {
        _socket!.add(bytes);
      } catch (error) {
        throw _asSessionException(error);
      }
    } else {
      await _sendJson(
        RealtimeVoiceProtocol.inputAudioAppend(
          base64Encode(bytes),
          config: config,
        ),
      );
    }
  }

  /// Sends an already base64-encoded audio chunk using the JSON append event.
  Future<void> sendAudioBase64(String base64Audio) async {
    _ensureConnected();
    final value = base64Audio.trim();
    if (value.isEmpty) {
      throw RealtimeVoiceSessionException(
        '实时语音 base64 音频为空',
        kind: RealtimeVoiceSessionErrorKind.protocol,
      );
    }
    try {
      final bytes = base64Decode(value);
      if (bytes.isEmpty) {
        throw const FormatException('empty audio');
      }
    } on FormatException {
      throw RealtimeVoiceSessionException(
        '实时语音 base64 音频格式无效',
        kind: RealtimeVoiceSessionErrorKind.protocol,
      );
    }
    await _sendJson(
      RealtimeVoiceProtocol.inputAudioAppend(value, config: config),
    );
  }

  /// Alias for callers that do not want to distinguish PCM from another
  /// configured codec.
  Future<void> sendAudioBytes(List<int> bytes) => sendPcm(bytes);

  /// Commits the current input buffer.  The server decides whether the buffer
  /// is valid for the active VAD mode.
  Future<void> commitInputAudio() async {
    _ensureConnected();
    await _sendJson(RealtimeVoiceProtocol.inputAudioCommit(config: config));
  }

  Future<void> clearInputAudio() async {
    _ensureConnected();
    await _sendJson(RealtimeVoiceProtocol.inputAudioClear(config: config));
  }

  /// Creates a model response after a manual commit or a text item.
  Future<void> createResponse({Map<String, dynamic>? response}) async {
    _ensureConnected();
    await _sendJson(
      RealtimeVoiceProtocol.responseCreate(response: response, config: config),
    );
  }

  /// Cancels only the active model response and keeps the voice session open.
  Future<void> cancelResponse({String? responseId}) async {
    _ensureConnected();
    await _sendJson(
      RealtimeVoiceProtocol.responseCancel(
        responseId: responseId ?? _activeResponseId,
        config: config,
      ),
    );
  }

  /// Sends a text conversation item and optionally requests a response.
  Future<void> sendText(String text, {bool createResponse = true}) async {
    _ensureConnected();
    final value = text.trim();
    if (value.isEmpty) {
      throw RealtimeVoiceSessionException(
        '实时语音文本为空',
        kind: RealtimeVoiceSessionErrorKind.protocol,
      );
    }
    await _sendJson(
      RealtimeVoiceProtocol.conversationItemCreate(text: value, config: config),
    );
    if (createResponse) await this.createResponse();
  }

  /// Cancels the whole session.  This is intentionally separate from
  /// [cancelResponse] so a UI can implement a stop button without losing the
  /// socket, or a discard button that tears down the complete session.
  Future<void> cancel({String reason = '请求已取消'}) async {
    if (_terminal) return;
    final socket = _socket;
    if (_snapshot.state == RealtimeVoiceSessionState.connected &&
        socket != null) {
      try {
        await _sendJson(
          RealtimeVoiceProtocol.responseCancel(
            responseId: _activeResponseId,
            config: config,
          ),
        );
      } catch (_) {
        // Closing the transport is the authoritative cancellation action.
      }
    }
    _setState(RealtimeVoiceSessionState.cancelling);
    _socket = null;
    await _safeCloseSocket(socket, reason: 'cancelled');
    _finishTerminal(
      RealtimeVoiceSessionState.cancelled,
      closeReason: redactRealtimeVoiceSecrets(reason),
    );
  }

  /// Gracefully closes the WebSocket.  Calling it repeatedly is safe.
  Future<void> close({int code = 1000, String reason = 'client close'}) async {
    if (_terminal) return;
    final socket = _socket;
    _setState(RealtimeVoiceSessionState.closing);
    _socket = null;
    await _safeCloseSocket(socket, code: _safeCloseCode(code), reason: reason);
    _finishTerminal(
      RealtimeVoiceSessionState.closed,
      closeCode: _safeCloseCode(code),
      closeReason: redactRealtimeVoiceSecrets(reason),
    );
  }

  Future<void> dispose() => close();

  void _watchCancelToken(CancelToken token) {
    final future = token.whenCancel.then<void>((_) async {
      if (!_terminal) await cancel(reason: '请求已取消');
    });
    unawaited(future.catchError((Object _) {}));
  }

  RealtimeVoiceSocketOptions _buildSocketOptions() {
    final headers = <String, String>{...config.headers};
    final apiKeyHeader = config.auth.headerName?.trim().toLowerCase();
    headers.removeWhere((key, value) {
      final lower = key.toLowerCase();
      return lower == 'authorization' ||
          (config.provider == RealtimeVoiceProvider.geminiLive &&
              lower == 'x-goog-api-key') ||
          (config.auth.mode == RealtimeVoiceAuthMode.apiKeyHeader &&
              apiKeyHeader != null &&
              apiKeyHeader.isNotEmpty &&
              lower == apiKeyHeader);
    });
    final protocols = <String>[...config.protocols];
    final token = config.auth.token.trim();
    if (config.auth.mode == RealtimeVoiceAuthMode.bearer) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      final prefix =
          config.auth.protocolPrefix ??
          switch (config.provider) {
            RealtimeVoiceProvider.openAi => 'openai-insecure-api-key',
            RealtimeVoiceProvider.xAi => 'xai-client-secret',
            RealtimeVoiceProvider.geminiLive => null,
            RealtimeVoiceProvider.custom => null,
            RealtimeVoiceProvider.simiRouter => null,
          };
      if (prefix != null && prefix.trim().isNotEmpty) {
        if (config.provider == RealtimeVoiceProvider.openAi &&
            !protocols.contains('realtime')) {
          protocols.insert(0, 'realtime');
        }
        protocols.add('${prefix.trim()}.$token');
      }
    }
    if (config.auth.mode == RealtimeVoiceAuthMode.apiKeyHeader) {
      final headerName = config.auth.headerName?.trim();
      if (headerName != null && headerName.isNotEmpty) {
        headers[headerName] = token;
      }
    }
    return RealtimeVoiceSocketOptions(
      uri: config.resolvedEndpoint,
      headers: headers,
      protocols: protocols,
      connectTimeout: config.connectTimeout,
      pingInterval: config.pingInterval,
    );
  }

  Future<void> _sendJson(Map<String, dynamic> event) async {
    _ensureConnected();
    try {
      _socket!.add(jsonEncode(event));
    } catch (error) {
      throw _asSessionException(error);
    }
  }

  void _ensureConnected() {
    if (_cancelToken?.isCancelled == true) {
      throw _cancelledException();
    }
    if (_snapshot.state != RealtimeVoiceSessionState.connected ||
        _socket == null) {
      throw RealtimeVoiceSessionException(
        '实时语音 session 当前不可发送',
        kind: RealtimeVoiceSessionErrorKind.invalidState,
      );
    }
  }

  void _handleIncoming(Object? raw) {
    if (_terminal) return;
    List<RealtimeVoiceEvent> events;
    try {
      events = RealtimeVoiceEventParser.parseMany(
        raw,
        geminiTranscriptMode: config.geminiLiveOptions.transcriptMode,
      );
    } catch (_) {
      // A malformed or vendor-specific event must not tear down the audio
      // session.  The parser intentionally has no raw-payload error path.
      return;
    }
    if (events.isEmpty) return;

    for (final parsedEvent in events) {
      _handleIncomingEvent(parsedEvent);
    }
  }

  void _handleIncomingEvent(RealtimeVoiceEvent parsedEvent) {
    if (_terminal) return;
    var event = parsedEvent;

    if (event is RealtimeVoiceTextEvent) {
      event = _normalizeTextEvent(event);
    }
    if (event is RealtimeVoiceSessionEvent && event.sessionId != null) {
      _updateSnapshot(sessionId: event.sessionId);
    }
    if (event is RealtimeVoiceResponseEvent) {
      if (event.phase == RealtimeVoiceResponsePhase.started) {
        _activeResponseId = event.responseId;
        _updateSnapshot(activeResponseId: event.responseId);
      } else {
        _activeResponseId = null;
        _updateSnapshot(clearActiveResponseId: true);
      }
    }
    if (!_eventController.isClosed) _eventController.add(event);
  }

  RealtimeVoiceTextEvent _normalizeTextEvent(RealtimeVoiceTextEvent event) {
    if (event.source != RealtimeVoiceTextSource.inputTranscript) {
      return event;
    }
    final key = event.itemId ?? '__unknown_input_item__';
    if (!event.isCumulative) {
      final previous = _cumulativeInputTranscripts[key] ?? '';
      _cumulativeInputTranscripts[key] = '$previous${event.delta}';
      return event;
    }
    final previous = _cumulativeInputTranscripts[key] ?? '';
    final delta = event.text.startsWith(previous)
        ? event.text.substring(previous.length)
        : event.text;
    _cumulativeInputTranscripts[key] = event.text;
    return event.copyWith(delta: delta);
  }

  void _handleSocketError(Object error) {
    if (_terminal) return;
    final exception = _connectionException(error);
    final socket = _socket;
    _socket = null;
    final event = RealtimeVoiceErrorEvent(
      type: 'transport.error',
      message: exception.message,
      isRemote: false,
    );
    if (!_eventController.isClosed) _eventController.add(event);
    _finishTerminal(
      RealtimeVoiceSessionState.failed,
      errorMessage: exception.message,
    );
    // A stream error is not guaranteed to be followed by a WebSocket `done`
    // callback. Close the transport explicitly so a controller can safely
    // reconnect without leaving the failed socket alive.
    unawaited(_safeCloseSocket(socket, code: 1011, reason: 'transport error'));
  }

  void _handleSocketDone() {
    if (_terminal) return;
    final state = _snapshot.state;
    if (state == RealtimeVoiceSessionState.cancelling) {
      _finishTerminal(RealtimeVoiceSessionState.cancelled);
    } else if (state == RealtimeVoiceSessionState.closing) {
      _finishTerminal(RealtimeVoiceSessionState.closed);
    } else {
      _finishTerminal(RealtimeVoiceSessionState.closed);
    }
    _socket = null;
  }

  void _setState(RealtimeVoiceSessionState state) {
    if (_terminal) return;
    _emitSnapshot(_snapshot.copyWith(state: state));
  }

  void _updateSnapshot({
    String? sessionId,
    bool clearSessionId = false,
    String? activeResponseId,
    bool clearActiveResponseId = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    if (_terminal) return;
    _emitSnapshot(
      _snapshot.copyWith(
        sessionId: sessionId,
        clearSessionId: clearSessionId,
        activeResponseId: activeResponseId,
        clearActiveResponseId: clearActiveResponseId,
        errorMessage: errorMessage,
        clearErrorMessage: clearErrorMessage,
      ),
    );
  }

  void _finishTerminal(
    RealtimeVoiceSessionState state, {
    String? errorMessage,
    int? closeCode,
    String? closeReason,
  }) {
    if (_terminal) return;
    _terminal = true;
    _emitSnapshot(
      _snapshot.copyWith(
        state: state,
        errorMessage: errorMessage,
        clearActiveResponseId: true,
        closeCode: closeCode,
        closeReason: closeReason,
      ),
    );
    _closeControllers();
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }

  void _emitSnapshot(RealtimeVoiceSessionSnapshot next) {
    _snapshot = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  void _closeControllers() {
    if (_controllersClosed) return;
    _controllersClosed = true;
    final incomingSubscription = _incomingSubscription;
    _incomingSubscription = null;
    unawaited(incomingSubscription?.cancel() ?? Future<void>.value());
    unawaited(_eventController.close());
    unawaited(_stateController.close());
  }

  Future<void> _safeCloseSocket(
    RealtimeVoiceSocket? socket, {
    int? code,
    required String reason,
  }) async {
    if (socket == null) return;
    try {
      await socket.close(
        code: code,
        reason: redactRealtimeVoiceSecrets(reason),
      );
    } catch (_) {
      // Closing is best effort.  The terminal state remains deterministic.
    }
  }

  RealtimeVoiceSessionException _cancelledException() =>
      RealtimeVoiceSessionException(
        '实时语音请求已取消',
        kind: RealtimeVoiceSessionErrorKind.cancelled,
      );

  RealtimeVoiceSessionException _connectionException(Object error) {
    if (error is RealtimeVoiceSessionException) return error;
    final message = switch (error) {
      TimeoutException() => '实时语音连接超时，请检查网络',
      SocketException() => '无法连接实时语音服务，请检查网络和 endpoint',
      HandshakeException() => '实时语音 TLS 握手失败，请检查 endpoint 证书',
      _ => '实时语音连接失败，请检查网络和 endpoint',
    };
    return RealtimeVoiceSessionException(
      message,
      kind: RealtimeVoiceSessionErrorKind.transport,
    );
  }

  RealtimeVoiceSessionException _asSessionException(Object error) {
    if (error is RealtimeVoiceSessionException) return error;
    return _connectionException(error);
  }
}

int _safeCloseCode(int code) => code >= 1000 && code <= 4999 ? code : 1000;

String _redactedHeaders(Map<String, String> headers) {
  return headers.map((key, value) {
    final lower = key.toLowerCase();
    if (lower == 'authorization' ||
        lower.contains('token') ||
        lower.contains('secret') ||
        lower.contains('api-key') ||
        lower.contains('api_key')) {
      return MapEntry(key, '***');
    }
    return MapEntry(key, redactRealtimeVoiceSecrets(value));
  }).toString();
}

String _redactedProtocols(List<String> protocols) {
  return protocols
      .map(
        (protocol) => protocol.contains('.')
            ? '${protocol.split('.').first}.***'
            : protocol,
      )
      .toList()
      .toString();
}
