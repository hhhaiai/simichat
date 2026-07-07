import 'dart:async';

import 'package:flutter/services.dart';

const kSimiDeepLinkChannelName = 'simichat/deep_link';

enum SimiDeepLinkAction { home, newChat, settings, marketplace, session }

class SimiDeepLink {
  const SimiDeepLink({required this.uri, required this.action, this.sessionId});

  final Uri uri;
  final SimiDeepLinkAction action;
  final String? sessionId;
}

final _validSessionIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');

SimiDeepLink? parseSimiDeepLink(String rawLink) {
  final trimmed = rawLink.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme != 'ai-chat') return null;

  final segments = <String>[
    if (uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments.where((segment) => segment.trim().isNotEmpty),
  ];
  final normalized = segments
      .map((segment) => segment.trim().toLowerCase())
      .toList(growable: false);
  final first = normalized.isEmpty ? 'home' : normalized.first;

  switch (first) {
    case 'home':
      return SimiDeepLink(uri: uri, action: SimiDeepLinkAction.home);
    case 'new':
    case 'new-chat':
    case 'new_session':
      return SimiDeepLink(uri: uri, action: SimiDeepLinkAction.newChat);
    case 'settings':
      return SimiDeepLink(uri: uri, action: SimiDeepLinkAction.settings);
    case 'marketplace':
    case 'skills':
      return SimiDeepLink(uri: uri, action: SimiDeepLinkAction.marketplace);
    case 'chat':
    case 'session':
      final hasExplicitSessionId =
          uri.queryParameters.containsKey('sessionId') ||
          uri.queryParameters.containsKey('session') ||
          segments.length >= 2;
      final sessionId = _extractSessionId(uri, segments);
      if (sessionId == null) {
        return hasExplicitSessionId
            ? null
            : SimiDeepLink(uri: uri, action: SimiDeepLinkAction.home);
      }
      return SimiDeepLink(
        uri: uri,
        action: SimiDeepLinkAction.session,
        sessionId: sessionId,
      );
    default:
      return null;
  }
}

String? _extractSessionId(Uri uri, List<String> segments) {
  final querySessionId =
      uri.queryParameters['sessionId'] ?? uri.queryParameters['session'];
  final candidate = querySessionId ?? _pathSessionId(segments);
  if (candidate == null) return null;
  final trimmed = candidate.trim();
  if (!_validSessionIdPattern.hasMatch(trimmed)) return null;
  return trimmed;
}

String? _pathSessionId(List<String> segments) {
  if (segments.length < 2) return null;
  return segments[1];
}

class MethodChannelSimiDeepLinkService {
  MethodChannelSimiDeepLinkService({
    MethodChannel channel = const MethodChannel(kSimiDeepLinkChannelName),
  }) : _channel = channel;

  final MethodChannel _channel;
  final StreamController<SimiDeepLink> _links =
      StreamController<SimiDeepLink>.broadcast();
  bool _isListening = false;

  Stream<SimiDeepLink> get links {
    _ensureListening();
    return _links.stream;
  }

  Future<SimiDeepLink?> getInitialLink() async {
    final raw = await _channel.invokeMethod<String>('getInitialLink');
    if (raw == null || raw.trim().isEmpty) return null;
    return parseSimiDeepLink(raw);
  }

  void _ensureListening() {
    if (_isListening) return;
    _isListening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'linkOpened') return;
      final raw = call.arguments as String?;
      if (raw == null) return;
      final parsed = parseSimiDeepLink(raw);
      if (parsed == null || _links.isClosed) return;
      _links.add(parsed);
    });
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _links.close();
  }
}
