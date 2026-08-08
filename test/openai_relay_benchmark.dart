import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/relay/openai_compatible_relay_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local OpenAI relay benchmark for 100 buffered requests', () async {
    const token = 'local-relay-benchmark-token';
    const model = OpenAiCompatibleRelayModel(
      id: 'bench-model',
      modelName: 'bench-model-upstream',
      displayName: 'Bench / bench-model-upstream',
    );
    final session = await const OpenAiCompatibleRelayServer(now: _fixedNow)
        .start(
          relayToken: token,
          listModels: () => const [model],
          resolveModel: (id) => id == model.id ? model : null,
          forward: ({required model, required messages, systemPrompt}) {
            return Stream.fromIterable(const [AiChunk(content: 'pong')]);
          },
        );
    addTearDown(session.close);

    final healthStopwatch = Stopwatch()..start();
    for (var i = 0; i < 100; i += 1) {
      final response = await _get(
        session.baseUri.resolve('/health'),
        token: token,
      );
      expect(response.statusCode, HttpStatus.ok);
    }
    healthStopwatch.stop();
    // ignore: avoid_print
    print(
      'openai_relay_health_benchmark requests=100 total_ms=${healthStopwatch.elapsedMilliseconds} avg_ms=${(healthStopwatch.elapsedMilliseconds / 100).toStringAsFixed(2)}',
    );

    final corsStopwatch = Stopwatch()..start();
    for (var i = 0; i < 100; i += 1) {
      final response = await _options(
        session.baseUri.resolve('/v1/chat/completions'),
      );
      expect(response.statusCode, HttpStatus.noContent);
    }
    corsStopwatch.stop();
    // ignore: avoid_print
    print(
      'openai_relay_cors_preflight_benchmark requests=100 total_ms=${corsStopwatch.elapsedMilliseconds} avg_ms=${(corsStopwatch.elapsedMilliseconds / 100).toStringAsFixed(2)}',
    );

    final responsesStopwatch = Stopwatch()..start();
    for (var i = 0; i < 100; i += 1) {
      final response = await _postJson(
        session.baseUri.resolve('/v1/responses'),
        token: token,
        body: {'model': model.id, 'input': 'ping $i'},
      );
      expect(response.statusCode, HttpStatus.ok);
    }
    responsesStopwatch.stop();
    // ignore: avoid_print
    print(
      'openai_relay_responses_benchmark requests=100 total_ms=${responsesStopwatch.elapsedMilliseconds} avg_ms=${(responsesStopwatch.elapsedMilliseconds / 100).toStringAsFixed(2)}',
    );

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < 100; i += 1) {
      final response = await _postJson(
        session.baseUri.resolve('/v1/chat/completions'),
        token: token,
        body: {
          'model': model.id,
          'messages': [
            {'role': 'user', 'content': 'ping $i'},
          ],
        },
      );
      expect(response.statusCode, HttpStatus.ok);
    }
    stopwatch.stop();
    // ignore: avoid_print
    print(
      'openai_relay_benchmark requests=100 total_ms=${stopwatch.elapsedMilliseconds} avg_ms=${(stopwatch.elapsedMilliseconds / 100).toStringAsFixed(2)}',
    );
  });
}

DateTime _fixedNow() => DateTime.utc(2026, 6, 27, 12, 0, 0);

Future<_BufferedResponse> _get(Uri uri, {required String token}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    return _BufferedResponse.from(await request.close());
  } finally {
    client.close(force: true);
  }
}

Future<_BufferedResponse> _options(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl('OPTIONS', uri);
    request.headers.set('Origin', 'http://localhost:3000');
    request.headers.set('Access-Control-Request-Method', 'POST');
    request.headers.set(
      'Access-Control-Request-Headers',
      'authorization, content-type',
    );
    return _BufferedResponse.from(await request.close());
  } finally {
    client.close(force: true);
  }
}

Future<_BufferedResponse> _postJson(
  Uri uri, {
  required String token,
  required Map<String, dynamic> body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    return _BufferedResponse.from(await request.close());
  } finally {
    client.close(force: true);
  }
}

class _BufferedResponse {
  const _BufferedResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  static Future<_BufferedResponse> from(HttpClientResponse response) async {
    final body = await utf8.decodeStream(response);
    return _BufferedResponse(statusCode: response.statusCode, body: body);
  }
}
