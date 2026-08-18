/// Error categories emitted by streaming protocol adapters.
enum ProtocolStreamErrorKind {
  transport,
  remote,
  safety,
  failed,
  incomplete,
  malformed,
  cancelled,
  unsupported,
}

/// A terminal, user-safe error from an AI streaming protocol.
///
/// Provider response bodies are deliberately not retained. The public
/// message is normalized and redacted so callers can show it or persist a
/// diagnostic without leaking API keys, URLs, local paths, or raw model
/// payloads.
class ProtocolStreamException implements Exception {
  factory ProtocolStreamException(
    String message, {
    String protocol = 'unknown',
    ProtocolStreamErrorKind kind = ProtocolStreamErrorKind.remote,
    String? code,
    int? statusCode,
    bool? retryable,
    bool terminal = true,
  }) {
    final safeMessage = sanitizeProtocolDiagnostic(message);
    return ProtocolStreamException._(
      message: safeMessage.isEmpty ? '流式请求失败' : safeMessage,
      protocol: protocol,
      kind: kind,
      code: code == null ? null : sanitizeProtocolDiagnostic(code),
      statusCode: statusCode,
      retryable: retryable ?? _defaultRetryable(kind, statusCode),
      terminal: terminal,
    );
  }

  const ProtocolStreamException._({
    required this.message,
    required this.protocol,
    required this.kind,
    required this.code,
    required this.statusCode,
    required this.retryable,
    required this.terminal,
  });

  final String message;
  final String protocol;
  final ProtocolStreamErrorKind kind;
  final String? code;
  final int? statusCode;
  final bool retryable;
  final bool terminal;

  bool get isTerminal => terminal;
  bool get isCancellation => kind == ProtocolStreamErrorKind.cancelled;
  bool get isSafetyBlock => kind == ProtocolStreamErrorKind.safety;
  bool get isIncomplete => kind == ProtocolStreamErrorKind.incomplete;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' HTTP $statusCode';
    final suffix = code == null ? '' : ' ($code)';
    return 'ProtocolStreamException[$protocol/${kind.name}]$status $message$suffix';
  }

  static bool _defaultRetryable(ProtocolStreamErrorKind kind, int? statusCode) {
    if (kind == ProtocolStreamErrorKind.cancelled ||
        kind == ProtocolStreamErrorKind.safety ||
        kind == ProtocolStreamErrorKind.unsupported) {
      return false;
    }
    if (statusCode == 401 || statusCode == 403 || statusCode == 404) {
      return false;
    }
    return kind == ProtocolStreamErrorKind.transport ||
        kind == ProtocolStreamErrorKind.remote ||
        kind == ProtocolStreamErrorKind.failed ||
        kind == ProtocolStreamErrorKind.incomplete ||
        statusCode == 408 ||
        statusCode == 409 ||
        statusCode == 425 ||
        statusCode == 429 ||
        (statusCode != null && statusCode >= 500);
  }
}

/// Redact diagnostics that may have come from an upstream response.
String sanitizeProtocolDiagnostic(String value) {
  var result = value
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ')
      .replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        'Bearer ***',
      )
      .replaceAll(
        RegExp(r'\bsk-[A-Za-z0-9_-]+', caseSensitive: false),
        'sk-***',
      )
      .replaceAll(
        RegExp(
          r'((?:api[_-]?key|token|secret|password|authorization)\s*[:=]\s*)[^\s,;]+',
          caseSensitive: false,
        ),
        r'$1***',
      )
      .replaceAll(RegExp(r'https?://[^\s]+', caseSensitive: false), '[链接]')
      .replaceAll(
        RegExp(r'(?:/Users/|/home/|/private/|/tmp/|[A-Za-z]:\\)[^\s,;]+'),
        '[本机路径]',
      )
      .trim();
  if (result.length > 240) {
    result = '${result.substring(0, 240)}…';
  }
  return result;
}
