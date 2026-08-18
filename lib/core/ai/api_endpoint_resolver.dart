/// URL/path resolver shared by protocol and media adapters.
///
/// A configured Base URL is treated as an API prefix, not necessarily as the
/// origin. For example, https://router.example/v2 resolves
/// chat/completions to https://router.example/v2/chat/completions, while an
/// origin-only URL resolves it to /v1/chat/completions.
abstract final class ApiEndpointResolver {
  /// Normalize a user-entered URL while retaining its configured path.
  static String normalizeUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return trimmed;

    var normalized = trimmed.replaceFirst(RegExp(r'/+(?=[?#]|$)'), '');
    final hasScheme = RegExp(
      r'^[a-zA-Z][a-zA-Z0-9+.-]*://',
    ).hasMatch(normalized);
    if (hasScheme) return normalized;

    final lower = normalized.toLowerCase();
    final isIpv4 = RegExp(
      r'^(\d{1,3}\.){3}\d{1,3}(:\d+)?(/.*)?$',
    ).hasMatch(lower);
    final isPrivateIpv4 = RegExp(
      r'^(127\.\d+\.\d+\.\d+|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+)(:\d+)?(/.*)?$',
    ).hasMatch(lower);
    final isIpv6 =
        RegExp(
          r'^\[[0-9a-f:]+\](:\d+)?(/.*)?$',
          caseSensitive: false,
        ).hasMatch(lower) ||
        RegExp(r'^[0-9a-f:]+$', caseSensitive: false).hasMatch(lower);
    final isLocalHost =
        lower == 'localhost' ||
        lower.startsWith('localhost:') ||
        lower.startsWith('localhost/') ||
        lower == '0.0.0.0' ||
        lower.startsWith('0.0.0.0:') ||
        lower.startsWith('0.0.0.0/') ||
        lower == '[::1]' ||
        lower.startsWith('[::1]:') ||
        lower.startsWith('[::1]/') ||
        lower == '::1';

    final bareIpv6 = _bareIpv6Host(normalized);
    final scheme =
        (isLocalHost || isPrivateIpv4 || isIpv4 || isIpv6 || bareIpv6 != null)
        ? 'http'
        : 'https';
    normalized = bareIpv6 == null
        ? '$scheme://$normalized'
        : '$scheme://[${bareIpv6.host}]${bareIpv6.suffix}';
    return normalized;
  }

  /// Resolve a relative endpoint against baseUrl.
  ///
  /// When the Base URL has no path, defaultPrefix is inserted. When it has a
  /// path, that path is assumed to be intentional and is preserved. A path
  /// that already contains an API version (/v1, /v2, /api/v3, /v1beta) is
  /// therefore never followed by another default /v1.
  static String resolve(
    String baseUrl,
    String endpoint, {
    String? defaultPrefix,
  }) {
    final normalized = normalizeUrl(baseUrl);
    final base = Uri.tryParse(normalized);
    final baseScheme = base?.scheme.toLowerCase();
    if (base == null ||
        !base.hasScheme ||
        base.host.isEmpty ||
        (baseScheme != 'http' && baseScheme != 'https')) {
      throw FormatException('Invalid Base URL: $baseUrl');
    }

    final rawEndpoint = endpoint.trim();
    if (rawEndpoint.isEmpty) {
      throw const FormatException('Endpoint must not be empty');
    }
    final parsedEndpoint = Uri.tryParse(rawEndpoint);
    if (parsedEndpoint != null && parsedEndpoint.hasScheme) {
      final endpointScheme = parsedEndpoint.scheme.toLowerCase();
      if (endpointScheme == 'http' || endpointScheme == 'https') {
        if (parsedEndpoint.host.isEmpty) {
          throw const FormatException('Endpoint URL host must not be empty');
        }
        return rawEndpoint;
      }
      throw const FormatException('Endpoint URL only supports HTTP(S)');
    }

    final endpointPath = (parsedEndpoint?.path ?? rawEndpoint)
        .replaceFirst(RegExp(r'^/+'), '')
        .replaceFirst(RegExp(r'/+$'), '');
    if (endpointPath.isEmpty) {
      throw const FormatException('Endpoint path must not be empty');
    }

    final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    final effectiveBasePath = basePath.isEmpty
        ? _defaultPath(defaultPrefix)
        : defaultPrefix != null && !hasApiVersionPath(baseUrl)
        ? '$basePath${_defaultPath(defaultPrefix)}'
        : basePath;
    final endpointSegments = _pathSegments(endpointPath);
    final baseSegments = _pathSegments(effectiveBasePath);

    String combinedPath;
    if (baseSegments.isNotEmpty &&
        _startsWithSegments(endpointSegments, baseSegments)) {
      combinedPath = '/${endpointSegments.join('/')}';
    } else if (baseSegments.isEmpty) {
      combinedPath = '/${endpointSegments.join('/')}';
    } else {
      combinedPath = '/${[...baseSegments, ...endpointSegments].join('/')}';
    }

    final endpointHasQuery = parsedEndpoint?.hasQuery ?? false;
    final query = endpointHasQuery ? parsedEndpoint!.query : base.query;
    final fragment = parsedEndpoint?.fragment.isNotEmpty == true
        ? parsedEndpoint!.fragment
        : base.fragment;

    // Passing an empty string to Uri.replace deliberately creates a trailing
    // `?` / `#`.  Endpoint builders are used in request URLs, so do not emit
    // those empty delimiters for the overwhelmingly common no-query case.
    return Uri(
      scheme: base.scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: base.port,
      path: combinedPath,
      query: query.isEmpty ? null : query,
      fragment: fragment.isEmpty ? null : fragment,
    ).toString();
  }

  /// OpenAI-compatible endpoints. Origin-only Base URLs get /v1.
  static String openAi(String baseUrl, String endpoint) =>
      resolve(baseUrl, endpoint, defaultPrefix: '/v1');

  /// Anthropic Messages endpoints. Custom prefixes are retained.
  static String claude(String baseUrl, String endpoint) =>
      resolve(baseUrl, endpoint, defaultPrefix: '/v1');

  /// Gemini REST endpoints. Official origin-only URLs use /v1beta.
  static String gemini(String baseUrl, String endpoint) =>
      resolve(baseUrl, endpoint, defaultPrefix: '/v1beta');

  /// Ollama endpoints have no implicit version prefix.
  static String ollama(String baseUrl, String endpoint) =>
      resolve(baseUrl, endpoint);

  static String _defaultPath(String? prefix) {
    if (prefix == null || prefix.trim().isEmpty) return '';
    return '/${prefix.trim().replaceFirst(RegExp(r'^/+'), '').replaceFirst(RegExp(r'/+$'), '')}';
  }

  static List<String> _pathSegments(String path) => path
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);

  static bool _startsWithSegments(List<String> value, List<String> prefix) {
    if (value.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (value[index].toLowerCase() != prefix[index].toLowerCase()) {
        return false;
      }
    }
    return true;
  }
}

/// Compatibility wrapper retained for callers that previously imported these
/// helpers from sse_helper.dart.
String normalizeUrl(String baseUrl) =>
    ApiEndpointResolver.normalizeUrl(baseUrl);

/// Legacy helper: it intentionally strips only a terminal /v1 for code that
/// needs an origin-like value. Endpoint construction must use
/// resolveOpenAiEndpoint so /v2, /v1/openai, and /api/v3 remain intact.
String normalizeOpenAiBaseUrl(String baseUrl) {
  final normalized = normalizeUrl(baseUrl);
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) return normalized;
  final segments = uri.pathSegments;
  if (segments.isEmpty || segments.last.toLowerCase() != 'v1') {
    return normalized;
  }
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: segments.sublist(0, segments.length - 1),
    query: uri.hasQuery ? uri.query : null,
    fragment: uri.hasFragment ? uri.fragment : null,
  ).toString();
}

String resolveApiEndpoint(
  String baseUrl,
  String endpoint, {
  String? defaultPrefix,
}) => ApiEndpointResolver.resolve(
  baseUrl,
  endpoint,
  defaultPrefix: defaultPrefix,
);

String resolveOpenAiEndpoint(String baseUrl, String endpoint) =>
    ApiEndpointResolver.openAi(baseUrl, endpoint);

String resolveClaudeEndpoint(String baseUrl, String endpoint) =>
    ApiEndpointResolver.claude(baseUrl, endpoint);

String resolveGeminiEndpoint(String baseUrl, String endpoint) =>
    ApiEndpointResolver.gemini(baseUrl, endpoint);

String resolveOllamaEndpoint(String baseUrl, String endpoint) =>
    ApiEndpointResolver.ollama(baseUrl, endpoint);

/// Whether a configured path already carries a version-like API segment.
bool hasApiVersionPath(String baseUrl) {
  final normalized = normalizeUrl(baseUrl);
  final uri = Uri.tryParse(normalized);
  if (uri == null) return false;
  final segments = uri.path.split('/').where((part) => part.isNotEmpty);
  return segments.any(
    (segment) =>
        RegExp(r'^v\d+(?:[a-z]+\d*)?$', caseSensitive: false).hasMatch(segment),
  );
}

({String host, String suffix})? _bareIpv6Host(String value) {
  var boundary = value.length;
  for (final marker in const <String>['/', '?', '#']) {
    final index = value.indexOf(marker);
    if (index >= 0 && index < boundary) boundary = index;
  }
  final host = value.substring(0, boundary);
  if (!host.contains(':') ||
      host.isEmpty ||
      host.startsWith('[') ||
      !RegExp(r'^[0-9a-f:]+$', caseSensitive: false).hasMatch(host)) {
    return null;
  }
  return (host: host, suffix: value.substring(boundary));
}
