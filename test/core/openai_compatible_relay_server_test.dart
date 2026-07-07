import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/ai/attachment_helper.dart';
import 'package:ai_chat_app/core/relay/openai_compatible_relay_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = 'local-relay-token-123456';
  const model = OpenAiCompatibleRelayModel(
    id: 'relay-model-1',
    modelName: 'gpt-test',
    displayName: '测试渠道 / gpt-test',
  );
  const fallbackModel = OpenAiCompatibleRelayModel(
    id: 'relay-model-2',
    modelName: 'gpt-fallback',
    displayName: '备用渠道 / gpt-fallback',
  );
  const visionModel = OpenAiCompatibleRelayModel(
    id: 'relay-vision-1',
    modelName: 'gpt-4o',
    displayName: '视觉渠道 / gpt-4o',
    supportsVision: true,
  );

  test('relay requires a strong local token', () async {
    expect(
      () => const OpenAiCompatibleRelayServer().start(
        relayToken: 'short',
        listModels: () => const [model],
        resolveModel: (_) => model,
        forward: _echoForwarder,
      ),
      throwsA(isA<OpenAiCompatibleRelayException>()),
    );
  });

  test(
    'GET /v1/models requires bearer token and returns OpenAI model list',
    () async {
      final session = await _startRelay(token: token, model: model);
      addTearDown(session.close);

      final unauthorized = await _get(session.baseUri.resolve('/v1/models'));
      expect(unauthorized.statusCode, HttpStatus.unauthorized);
      expect(unauthorized.body, isNot(contains('gpt-test')));

      final authorized = await _get(
        session.baseUri.resolve('/v1/models'),
        token: token,
      );
      expect(authorized.statusCode, HttpStatus.ok);
      expect(authorized.headers.value('cache-control'), 'no-store');
      expect(authorized.headers.value('x-content-type-options'), 'nosniff');
      final json = jsonDecode(authorized.body) as Map<String, dynamic>;
      expect(json['object'], 'list');
      expect(jsonEncode(json), contains('relay-model-1'));
      expect(jsonEncode(json), isNot(contains('sk-')));
      final modelJson = (json['data'] as List).single as Map<String, dynamic>;
      expect(modelJson['capabilities'], ['chat']);
      expect(modelJson['supports_vision'], isFalse);
    },
  );

  test(
    'GET /health requires bearer token and returns safe relay status',
    () async {
      var listedModels = false;
      final events = <OpenAiRelayAuditEvent>[];
      final session = await const OpenAiCompatibleRelayServer(now: _fixedNow)
          .start(
            relayToken: token,
            listModels: () {
              listedModels = true;
              return const [model];
            },
            resolveModel: (id) => id == model.id ? model : null,
            forward: _echoForwarder,
            maxConcurrentRequests: 8,
            auditSink: events.add,
            remoteImagePolicy: const OpenAiRelayRemoteImagePolicy.enabled(),
          );
      addTearDown(session.close);

      final unauthorized = await _get(session.baseUri.resolve('/health'));
      expect(unauthorized.statusCode, HttpStatus.unauthorized);
      expect(unauthorized.body, isNot(contains('max_concurrent')));
      expect(unauthorized.body, isNot(contains(token)));

      final authorized = await _get(
        session.baseUri.resolve('/health'),
        token: token,
      );
      expect(authorized.statusCode, HttpStatus.ok);
      expect(authorized.headers.value('cache-control'), 'no-store');
      expect(authorized.headers.value('x-content-type-options'), 'nosniff');
      final json = jsonDecode(authorized.body) as Map<String, dynamic>;
      expect(json['object'], 'simichat.relay.health');
      expect(json['status'], 'ok');
      expect(json['active_chat_requests'], 0);
      expect(json['max_concurrent_chat_requests'], 8);
      expect(json['remote_image_download_enabled'], isTrue);
      expect(jsonEncode(json), isNot(contains(token)));
      expect(jsonEncode(json), isNot(contains('gpt-test')));
      expect(listedModels, isFalse);

      final v1Health = await _get(
        session.baseUri.resolve('/v1/health'),
        token: token,
      );
      expect(v1Health.statusCode, HttpStatus.ok);

      expect(events.map((event) => event.path), [
        '/health',
        '/health',
        '/v1/health',
      ]);
      expect(events.first.authorized, isFalse);
      expect(events[1].code, 'ok');
    },
  );

  test(
    'relay supports browser CORS preflight without token or state exposure',
    () async {
      final events = <OpenAiRelayAuditEvent>[];
      final session = await _startRelay(
        token: token,
        model: model,
        auditSink: events.add,
      );
      addTearDown(session.close);

      final preflight = await _options(
        session.baseUri.resolve('/v1/chat/completions'),
      );
      expect(preflight.statusCode, HttpStatus.noContent);
      expect(preflight.body, isEmpty);
      expect(preflight.headers.value('cache-control'), 'no-store');
      expect(preflight.headers.value('x-content-type-options'), 'nosniff');
      expect(preflight.headers.value('access-control-allow-origin'), '*');
      expect(
        preflight.headers.value('access-control-allow-methods'),
        contains('POST'),
      );
      expect(
        preflight.headers.value('access-control-allow-headers'),
        contains('authorization'),
      );
      expect(
        preflight.headers.value('access-control-allow-headers'),
        contains('content-type'),
      );
      expect(preflight.headers.value('access-control-max-age'), '600');

      final unsupported = await _options(session.baseUri.resolve('/v1/files'));
      expect(unsupported.statusCode, HttpStatus.notFound);
      expect(unsupported.headers.value('access-control-allow-origin'), '*');
      expect(unsupported.body, contains('not_found'));
      expect(unsupported.body, isNot(contains(token)));

      final actual = await _get(
        session.baseUri.resolve('/v1/models'),
        token: token,
      );
      expect(actual.statusCode, HttpStatus.ok);
      expect(actual.headers.value('access-control-allow-origin'), '*');

      final responsesPreflight = await _options(
        session.baseUri.resolve('/v1/responses'),
      );
      expect(responsesPreflight.statusCode, HttpStatus.noContent);

      expect(events.map((event) => event.code), [
        'cors_preflight',
        'not_found',
        'ok',
        'cors_preflight',
      ]);
      expect(events.first.authorized, isTrue);
      expect(events.first.path, '/v1/chat/completions');
    },
  );

  test('GET /v1/models exposes safe vision capability metadata', () async {
    final session = await const OpenAiCompatibleRelayServer(now: _fixedNow)
        .start(
          relayToken: token,
          listModels: () => const [model, visionModel],
          resolveModel: (id) {
            if (id == model.id) return model;
            if (id == visionModel.id) return visionModel;
            return null;
          },
          forward: _echoForwarder,
        );
    addTearDown(session.close);

    final authorized = await _get(
      session.baseUri.resolve('/v1/models'),
      token: token,
    );

    expect(authorized.statusCode, HttpStatus.ok);
    final json = jsonDecode(authorized.body) as Map<String, dynamic>;
    final models = (json['data'] as List).cast<Map<String, dynamic>>();
    final text = models.firstWhere((item) => item['id'] == model.id);
    final vision = models.firstWhere((item) => item['id'] == visionModel.id);
    expect(text['capabilities'], ['chat']);
    expect(text['supports_vision'], isFalse);
    expect(vision['capabilities'], ['chat', 'vision']);
    expect(vision['supports_vision'], isTrue);
    expect(jsonEncode(json), isNot(contains('local-relay-token')));
  });

  test(
    'POST /v1/chat/completions returns buffered OpenAI-compatible response',
    () async {
      OpenAiCompatibleRelayModel? routedModel;
      List<AiMessage>? routedMessages;
      String? routedSystemPrompt;
      final session = await _startRelay(
        token: token,
        model: model,
        forward: ({required model, required messages, systemPrompt}) {
          routedModel = model;
          routedMessages = messages;
          routedSystemPrompt = systemPrompt;
          return Stream.fromIterable(const [
            AiChunk(thinking: '先思考'),
            AiChunk(content: '你好'),
            AiChunk(content: '，世界'),
          ]);
        },
      );
      addTearDown(session.close);

      final response = await _postJson(
        session.baseUri.resolve('/v1/chat/completions'),
        token: token,
        body: {
          'model': model.id,
          'messages': [
            {'role': 'system', 'content': '你是 SimiChat'},
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': '请回答'},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'file:///private/local-image.png'},
                },
              ],
            },
          ],
        },
      );

      expect(response.statusCode, HttpStatus.ok);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choice = (json['choices'] as List).single as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>;
      expect(json['object'], 'chat.completion');
      expect(json['model'], model.id);
      expect(message['content'], '你好，世界');
      expect(message['reasoning_content'], '先思考');
      expect(routedModel, model);
      expect(routedSystemPrompt, '你是 SimiChat');
      expect(routedMessages!.single.content, contains('请回答'));
      expect(routedMessages!.single.content, contains('已省略非文本内容: image_url'));
      expect(routedMessages!.single.content, isNot(contains('/private')));
      expect(routedMessages!.single.attachments, isNull);
    },
  );

  test(
    'POST /v1/responses returns buffered Responses-compatible output',
    () async {
      List<AiMessage>? routedMessages;
      String? routedSystemPrompt;
      final session = await _startRelay(
        token: token,
        model: model,
        forward: ({required model, required messages, systemPrompt}) {
          routedMessages = messages;
          routedSystemPrompt = systemPrompt;
          return Stream.fromIterable([
            AiChunk(content: '收到：${messages.last.content}'),
          ]);
        },
      );
      addTearDown(session.close);

      final response = await _postJson(
        session.baseUri.resolve('/v1/responses'),
        token: token,
        body: {'model': model.id, 'instructions': '只用中文回答', 'input': '你好'},
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value('access-control-allow-origin'), '*');
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['object'], 'response');
      expect(json['status'], 'completed');
      expect(json['model'], model.id);
      expect(json['output_text'], '收到：你好');
      final output = (json['output'] as List).single as Map<String, dynamic>;
      expect(output['type'], 'message');
      final content =
          (output['content'] as List).single as Map<String, dynamic>;
      expect(content['type'], 'output_text');
      expect(content['text'], '收到：你好');
      expect(jsonEncode(json), isNot(contains(token)));
      expect(routedSystemPrompt, '只用中文回答');
      expect(routedMessages!.single.role, 'user');
      expect(routedMessages!.single.content, '你好');
    },
  );

  test('POST /v1/responses safely parses multimodal response input', () async {
    List<AiMessage>? routedMessages;
    final session = await _startRelay(
      token: token,
      model: model,
      forward: ({required model, required messages, systemPrompt}) {
        routedMessages = messages;
        return Stream.fromIterable([AiChunk(content: messages.last.content)]);
      },
    );
    addTearDown(session.close);

    final response = await _postJson(
      session.baseUri.resolve('/v1/responses'),
      token: token,
      body: {
        'model': model.id,
        'input': [
          {
            'type': 'message',
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': '分析这张图'},
              {
                'type': 'input_image',
                'image_url': 'file:///private/local-image.png',
              },
            ],
          },
        ],
      },
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(routedMessages!.single.attachments, isNull);
    expect(routedMessages!.single.content, contains('分析这张图'));
    expect(routedMessages!.single.content, contains('已省略非文本内容: input_image'));
    expect(response.body, contains('已省略非文本内容: input_image'));
    expect(response.body, isNot(contains('file:///private')));
  });

  test('POST /v1/responses safely degrades unsupported input items', () async {
    List<AiMessage>? routedMessages;
    final session = await _startRelay(
      token: token,
      model: model,
      forward: ({required model, required messages, systemPrompt}) {
        routedMessages = messages;
        return Stream.fromIterable([AiChunk(content: messages.last.content)]);
      },
    );
    addTearDown(session.close);

    final response = await _postJson(
      session.baseUri.resolve('/v1/responses'),
      token: token,
      body: {
        'model': model.id,
        'input': [
          {'type': 'input_text', 'text': '继续处理'},
          {'type': 'item_reference', 'id': 'resp-secret-item-123'},
        ],
      },
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(routedMessages, isNotNull);
    final content = routedMessages!
        .map((message) => message.content)
        .join('\n');
    expect(content, contains('继续处理'));
    expect(content, contains('已省略非文本内容: item_reference'));
    expect(response.body, contains('已省略非文本内容: item_reference'));
    expect(response.body, isNot(contains('resp-secret-item-123')));
  });

  test('POST /v1/responses streams Responses-compatible SSE chunks', () async {
    final session = await _startRelay(
      token: token,
      model: model,
      forward: ({required model, required messages, systemPrompt}) {
        return Stream.fromIterable(const [
          AiChunk(content: 'A'),
          AiChunk(content: 'B'),
        ]);
      },
    );
    addTearDown(session.close);

    final response = await _postJson(
      session.baseUri.resolve('/v1/responses'),
      token: token,
      body: {'model': model.id, 'stream': true, 'input': 'hello'},
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType?.mimeType, 'text/event-stream');
    final eventNames = response.body
        .split('\n')
        .where((line) => line.startsWith('event: '))
        .map((line) => line.substring('event: '.length))
        .toList();
    expect(eventNames, [
      'response.created',
      'response.in_progress',
      'response.output_item.added',
      'response.content_part.added',
      'response.output_text.delta',
      'response.output_text.delta',
      'response.output_text.done',
      'response.content_part.done',
      'response.output_item.done',
      'response.completed',
    ]);
    expect(response.body, contains('event: response.in_progress'));
    expect(response.body, contains('"type":"response.in_progress"'));
    expect(response.body, contains('event: response.output_item.added'));
    expect(response.body, contains('"item":{"id":"msg-'));
    expect(response.body, contains('"role":"assistant"'));
    expect(response.body, contains('event: response.content_part.added'));
    expect(
      response.body,
      contains('"part":{"type":"output_text","text":"","annotations":[]}'),
    );
    expect(response.body, contains('event: response.output_text.delta'));
    expect(response.body, contains('"delta":"A"'));
    expect(response.body, contains('"delta":"B"'));
    expect(response.body, contains('event: response.output_text.done'));
    expect(response.body, contains('"text":"AB"'));
    expect(response.body, contains('event: response.content_part.done'));
    expect(
      response.body,
      contains('"part":{"type":"output_text","text":"AB","annotations":[]}'),
    );
    expect(response.body, contains('event: response.output_item.done'));
    expect(response.body, contains('event: response.completed'));
    expect(response.body, contains('"output_text":"AB"'));
    expect(response.body, contains('data: [DONE]'));
    expect(response.body, isNot(contains(token)));
  });

  test(
    'POST /v1/responses streams safe failed event on upstream error',
    () async {
      final events = <OpenAiRelayAuditEvent>[];
      final session = await _startRelay(
        token: token,
        model: model,
        auditSink: events.add,
        forward: ({required model, required messages, systemPrompt}) async* {
          yield const AiChunk(content: 'A');
          throw const OpenAiCompatibleRelayException(
            'upstream secret sk-test /Users/private',
          );
        },
      );
      addTearDown(session.close);

      final response = await _postJson(
        session.baseUri.resolve('/v1/responses'),
        token: token,
        body: {'model': model.id, 'stream': true, 'input': 'hello'},
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      expect(response.body, contains('event: response.output_text.delta'));
      expect(response.body, contains('"delta":"A"'));
      expect(response.body, contains('event: response.failed'));
      expect(response.body, contains('"status":"failed"'));
      expect(response.body, contains('"code":"upstream_error"'));
      expect(response.body, contains('data: [DONE]'));
      expect(response.body, isNot(contains('sk-test')));
      expect(response.body, isNot(contains('/Users/private')));
      expect(response.body, isNot(contains(token)));
      expect(events, hasLength(1));
      expect(events.single.code, 'upstream_error');
      expect(events.single.statusCode, HttpStatus.ok);
      expect(events.single.stream, isTrue);
    },
  );

  test('relay parses multimodal content with safe local degradation', () {
    final parsed = parseOpenAiRelayMessages([
      {
        'role': 'system',
        'content': [
          {'type': 'input_text', 'text': '只做安全摘要'},
        ],
      },
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '请看这些内容'},
          {
            'type': 'image_url',
            'image_url': {'url': 'https://example.com/private-image.png'},
          },
          {
            'type': 'input_image',
            'image_url': 'data:image/png;base64,UEFZTE9BRE1BUktFUg==',
          },
          {
            'type': 'input_audio',
            'input_audio': {'data': 'AUDIOPAYLOADMARKER', 'format': 'wav'},
          },
          {
            'type': 'file',
            'file': {'file_id': 'file-opaque-id-123'},
          },
          {
            'type': 'file:///private/local-image.png',
            'value': 'local path must not leak',
          },
        ],
      },
    ]);

    expect(parsed, isNotNull);
    expect(parsed!.systemPrompt, '只做安全摘要');
    expect(parsed.omittedPartCount, 4);
    expect(parsed.omittedPartTypes['image_url'], 1);
    expect(parsed.omittedPartTypes['input_image'], isNull);
    expect(parsed.omittedPartTypes['input_audio'], 1);
    expect(parsed.omittedPartTypes['file'], 1);
    expect(parsed.omittedPartTypes['unknown'], 1);

    final content = parsed.messages.single.content;
    expect(content, contains('请看这些内容'));
    expect(content, contains('已省略非文本内容: image_url'));
    expect(content, isNot(contains('已省略非文本内容: input_image')));
    expect(content, contains('已省略非文本内容: input_audio'));
    expect(content, contains('已省略非文本内容: file'));
    expect(content, contains('已省略非文本内容: unknown'));
    expect(content, isNot(contains('https://example.com')));
    expect(content, isNot(contains('UEFZTE9BRE1BUktFUg')));
    expect(parsed.attachedImageCount, 1);
    expect(parsed.messages.single.attachments, hasLength(1));
    expect(parsed.messages.single.attachments!.single.mimeType, 'image/png');
    expect(content, isNot(contains('AUDIOPAYLOADMARKER')));
    expect(content, isNot(contains('file-opaque-id-123')));
    expect(content, isNot(contains('/private')));
  });

  test('relay remote image safety policy rejects unsafe local addresses', () {
    expect(
      isSafeOpenAiRelayRemoteImageUri(Uri.parse('https://example.com/a.png')),
      isTrue,
    );
    expect(
      isSafeOpenAiRelayRemoteImageUri(Uri.parse('http://127.0.0.1/a.png')),
      isFalse,
    );
    expect(
      isSafeOpenAiRelayRemoteImageUri(Uri.parse('http://localhost/a.png')),
      isFalse,
    );
    expect(
      isSafeOpenAiRelayRemoteImageUri(Uri.parse('http://dev.localhost/a.png')),
      isFalse,
    );
    expect(
      isSafeOpenAiRelayRemoteImageUri(Uri.parse('http://10.0.0.1/a.png')),
      isFalse,
    );
    expect(
      isSafeOpenAiRelayRemoteImageUri(Uri.parse('http://[fc00::1]/a.png')),
      isFalse,
    );
    expect(
      isSafeOpenAiRelayRemoteImageUri(Uri.parse('file:///private/a.png')),
      isFalse,
    );
    expect(
      isSafeOpenAiRelayRemoteImageUri(
        Uri.parse('https://user:pass@example.com/a.png'),
      ),
      isFalse,
    );
  });

  test(
    'relay downloads remote image urls only when policy is enabled',
    () async {
      Uri? fetchedUri;
      List<AiMessage>? routedMessages;
      AttachmentData? loadedRemoteImage;
      final session = await _startRelay(
        token: token,
        model: visionModel,
        remoteImagePolicy: const OpenAiRelayRemoteImagePolicy.enabled(),
        remoteImageFetcher: (uri, policy) async {
          fetchedUri = uri;
          return OpenAiRelayRemoteImageFetchResult(
            mimeType: 'image/png',
            bytes: utf8.encode('REMOTEIMG'),
          );
        },
        forward: ({required model, required messages, systemPrompt}) async* {
          routedMessages = messages;
          loadedRemoteImage = (await loadAttachments(
            messages.single.attachments!,
          )).single;
          yield AiChunk(content: messages.single.content);
        },
      );
      addTearDown(session.close);

      final response = await _postJson(
        session.baseUri.resolve('/v1/chat/completions'),
        token: token,
        body: {
          'model': visionModel.id,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': '分析远端图'},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'https://example.com/private.png'},
                },
              ],
            },
          ],
        },
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(fetchedUri.toString(), 'https://example.com/private.png');
      expect(routedMessages!.single.content, '分析远端图');
      expect(routedMessages!.single.attachments, hasLength(1));
      expect(loadedRemoteImage?.mimeType, 'image/png');
      expect(loadedRemoteImage?.base64, base64Encode(utf8.encode('REMOTEIMG')));
      expect(response.body, contains('分析远端图'));
      expect(response.body, isNot(contains('https://example.com/private.png')));
      expect(response.body, isNot(contains('REMOTEIMG')));
    },
  );

  test(
    'relay safely degrades remote image urls when download is disabled',
    () async {
      var fetched = false;
      final session = await _startRelay(
        token: token,
        model: visionModel,
        remoteImageFetcher: (uri, policy) async {
          fetched = true;
          return OpenAiRelayRemoteImageFetchResult(
            mimeType: 'image/png',
            bytes: utf8.encode('REMOTEIMG'),
          );
        },
        forward: ({required model, required messages, systemPrompt}) async* {
          expect(messages.single.attachments, isNull);
          yield AiChunk(content: messages.single.content);
        },
      );
      addTearDown(session.close);

      final response = await _postJson(
        session.baseUri.resolve('/v1/chat/completions'),
        token: token,
        body: {
          'model': visionModel.id,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': '分析远端图'},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'https://example.com/private.png'},
                },
              ],
            },
          ],
        },
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(fetched, isFalse);
      expect(response.body, contains('已省略非文本内容: image_url'));
      expect(response.body, isNot(contains('https://example.com/private.png')));
    },
  );

  test('relay response and audit omit multimodal source payloads', () async {
    final events = <OpenAiRelayAuditEvent>[];
    List<AiMessage>? routedMessages;
    AttachmentData? loadedInlineImage;
    final session = await _startRelay(
      token: token,
      model: visionModel,
      auditSink: events.add,
      forward: ({required model, required messages, systemPrompt}) async* {
        routedMessages = messages;
        loadedInlineImage = (await loadAttachments(
          messages.last.attachments!,
        )).single;
        yield AiChunk(content: messages.last.content);
      },
    );
    addTearDown(session.close);

    final response = await _postJson(
      session.baseUri.resolve('/v1/chat/completions'),
      token: token,
      body: {
        'model': visionModel.id,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': '分析这张图'},
              {
                'type': 'image_url',
                'image_url': {'url': 'https://example.com/private.png'},
              },
              {
                'type': 'input_image',
                'image_url': 'data:image/png;base64,UEFZTE9BRE1BUktFUg==',
              },
            ],
          },
        ],
      },
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(routedMessages, isNotNull);
    expect(routedMessages!.single.attachments, hasLength(1));
    expect(loadedInlineImage?.mimeType, 'image/png');
    expect(loadedInlineImage?.base64, 'UEFZTE9BRE1BUktFUg==');

    final responseDump = response.body;
    expect(responseDump, contains('分析这张图'));
    expect(responseDump, contains('已省略非文本内容: image_url'));
    expect(responseDump, isNot(contains('已省略非文本内容: input_image')));
    expect(responseDump, isNot(contains('https://example.com/private.png')));
    expect(responseDump, isNot(contains('UEFZTE9BRE1BUktFUg')));

    final auditDump = events.map((event) => event.toString()).join('\n');
    expect(auditDump, isNot(contains('https://example.com/private.png')));
    expect(auditDump, isNot(contains('UEFZTE9BRE1BUktFUg')));
  });

  test('relay audit model id keeps only safe identifier shape', () async {
    final events = <OpenAiRelayAuditEvent>[];
    final session = await _startRelay(
      token: token,
      model: model,
      auditSink: events.add,
    );
    addTearDown(session.close);

    final response = await _postJson(
      session.baseUri.resolve('/v1/chat/completions'),
      token: token,
      body: {
        'model': 'file:///private/private-model.png',
        'messages': [
          {'role': 'user', 'content': 'hello'},
        ],
      },
    );

    expect(response.statusCode, HttpStatus.notFound);
    expect(events, hasLength(1));
    expect(events.single.code, 'model_not_found');
    expect(events.single.modelId, isNull);
  });

  test(
    'relay rejects image input when exact model lacks vision support',
    () async {
      var forwarded = false;
      final session = await _startRelay(
        token: token,
        model: model,
        forward: ({required model, required messages, systemPrompt}) {
          forwarded = true;
          return Stream.fromIterable(const [AiChunk(content: 'unexpected')]);
        },
      );
      addTearDown(session.close);

      final response = await _postJson(
        session.baseUri.resolve('/v1/chat/completions'),
        token: token,
        body: {
          'model': model.id,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': '分析图片'},
                {
                  'type': 'input_image',
                  'image_url': 'data:image/png;base64,UEFZTE9BRE1BUktFUg==',
                },
              ],
            },
          ],
        },
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.body, contains('vision_model_required'));
      expect(response.body, isNot(contains('UEFZTE9BRE1BUktFUg')));
      expect(forwarded, isFalse);
    },
  );

  test(
    'relay filters fallback candidates to vision-capable models for image input',
    () async {
      final seenModels = <String>[];
      final session = await const OpenAiCompatibleRelayServer(now: _fixedNow)
          .start(
            relayToken: token,
            listModels: () => const [model, fallbackModel, visionModel],
            resolveModel: (id) {
              if (id == model.id) return model;
              if (id == fallbackModel.id) return fallbackModel;
              if (id == visionModel.id) return visionModel;
              return null;
            },
            routeModel: (_) => const OpenAiCompatibleRelayRoute(
              primary: model,
              fallbacks: [fallbackModel, visionModel],
              routeCode: 'default_model',
            ),
            forward: ({required model, required messages, systemPrompt}) {
              seenModels.add(model.id);
              expect(messages.single.attachments, hasLength(1));
              return Stream.fromIterable([AiChunk(content: 'hit:${model.id}')]);
            },
          );
      addTearDown(session.close);

      final response = await _postJson(
        session.baseUri.resolve('/v1/chat/completions'),
        token: token,
        body: {
          'model': kOpenAiRelayRouteAliasDefault,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': '分析图片'},
                {
                  'type': 'input_image',
                  'image_url': 'data:image/png;base64,UEFZTE9BRE1BUktFUg==',
                },
              ],
            },
          ],
        },
      );

      expect(response.statusCode, HttpStatus.ok);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['model'], visionModel.id);
      expect(jsonEncode(json), contains('hit:${visionModel.id}'));
      expect(jsonEncode(json), isNot(contains('UEFZTE9BRE1BUktFUg')));
      expect(seenModels, [visionModel.id]);
    },
  );

  test(
    'POST /v1/chat/completions streams SSE chunks and DONE marker',
    () async {
      final session = await _startRelay(
        token: token,
        model: model,
        forward: ({required model, required messages, systemPrompt}) {
          return Stream.fromIterable(const [
            AiChunk(content: 'A'),
            AiChunk(thinking: 'B'),
          ]);
        },
      );
      addTearDown(session.close);

      final response = await _postJson(
        session.baseUri.resolve('/v1/chat/completions'),
        token: token,
        body: {
          'model': model.id,
          'stream': true,
          'messages': [
            {'role': 'user', 'content': 'hello'},
          ],
        },
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      expect(response.body, contains('"content":"A"'));
      expect(response.body, contains('"reasoning_content":"B"'));
      expect(response.body, contains('data: [DONE]'));
    },
  );

  test(
    'POST /v1/chat/completions streams safe error on upstream failure',
    () async {
      final events = <OpenAiRelayAuditEvent>[];
      final session = await _startRelay(
        token: token,
        model: model,
        auditSink: events.add,
        forward: ({required model, required messages, systemPrompt}) async* {
          yield const AiChunk(content: 'A');
          throw const OpenAiCompatibleRelayException(
            'upstream secret sk-chat /Users/private',
          );
        },
      );
      addTearDown(session.close);

      final response = await _postJson(
        session.baseUri.resolve('/v1/chat/completions'),
        token: token,
        body: {
          'model': model.id,
          'stream': true,
          'messages': [
            {'role': 'user', 'content': 'hello'},
          ],
        },
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/event-stream');
      expect(response.body, contains('"content":"A"'));
      expect(response.body, contains('"error":'));
      expect(response.body, contains('"code":"upstream_error"'));
      expect(response.body, contains('data: [DONE]'));
      expect(response.body, isNot(contains('sk-chat')));
      expect(response.body, isNot(contains('/Users/private')));
      expect(response.body, isNot(contains(token)));
      expect(events, hasLength(1));
      expect(events.single.code, 'upstream_error');
      expect(events.single.statusCode, HttpStatus.ok);
      expect(events.single.stream, isTrue);
    },
  );

  test(
    'relay returns safe OpenAI errors for unknown model and oversized request',
    () async {
      final session = await _startRelay(
        token: token,
        model: model,
        maxRequestBytes: 32,
      );
      addTearDown(session.close);

      final unknown = await _postJson(
        session.baseUri.resolve('/v1/chat/completions'),
        token: token,
        body: {'model': 'missing', 'messages': []},
      );
      // The small max body can reject before model routing for this compact server.
      expect({
        HttpStatus.notFound,
        HttpStatus.requestEntityTooLarge,
      }, contains(unknown.statusCode));
      expect(unknown.body, isNot(contains('sk-')));
      expect(unknown.body, isNot(contains('/Users/')));

      final oversized = await _postJson(
        session.baseUri.resolve('/v1/chat/completions'),
        token: token,
        body: {
          'model': model.id,
          'messages': [
            {'role': 'user', 'content': 'x' * 128},
          ],
        },
      );
      expect(oversized.statusCode, HttpStatus.requestEntityTooLarge);
      expect(oversized.body, contains('request_too_large'));
    },
  );

  test('relay audits requests without payloads or secrets', () async {
    final events = <OpenAiRelayAuditEvent>[];
    final session = await _startRelay(
      token: token,
      model: model,
      auditSink: events.add,
    );
    addTearDown(session.close);

    await _get(session.baseUri.resolve('/v1/models'));
    await _get(session.baseUri.resolve('/v1/models'), token: token);
    await _postJson(
      session.baseUri.resolve('/v1/chat/completions'),
      token: token,
      body: {
        'model': model.id,
        'messages': [
          {'role': 'user', 'content': 'secret prompt should not be audited'},
        ],
      },
    );

    expect(events, hasLength(3));
    expect(events[0].authorized, isFalse);
    expect(events[0].statusCode, HttpStatus.unauthorized);
    expect(events[1].authorized, isTrue);
    expect(events[1].code, 'ok');
    expect(events[2].modelId, model.id);
    final auditDump = events
        .map(
          (event) =>
              '${event.method} ${event.path} ${event.code} ${event.modelId}',
        )
        .join('\n');
    expect(auditDump, isNot(contains('secret prompt')));
    expect(auditDump, isNot(contains(token)));
  });

  test('relay rejects chat completions above concurrency limit', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final session = await _startRelay(
      token: token,
      model: model,
      maxConcurrentRequests: 1,
      forward: ({required model, required messages, systemPrompt}) async* {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        yield const AiChunk(content: 'done');
      },
    );
    addTearDown(session.close);

    final firstClient = HttpClient();
    addTearDown(() => firstClient.close(force: true));
    final firstRequest = await firstClient.postUrl(
      session.baseUri.resolve('/v1/chat/completions'),
    );
    firstRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    firstRequest.headers.contentType = ContentType.json;
    firstRequest.write(
      jsonEncode({
        'model': model.id,
        'messages': [
          {'role': 'user', 'content': 'first'},
        ],
      }),
    );
    final first = firstRequest.close().then(_BufferedResponse.from);
    await entered.future.timeout(const Duration(seconds: 2));

    final second = await _postJson(
      session.baseUri.resolve('/v1/chat/completions'),
      token: token,
      body: {
        'model': model.id,
        'messages': [
          {'role': 'user', 'content': 'second'},
        ],
      },
    );
    expect(second.statusCode, HttpStatus.tooManyRequests);
    expect(second.headers.value(HttpHeaders.retryAfterHeader), '1');
    expect(second.body, contains('concurrency_limit'));

    release.complete();
    expect((await first).statusCode, HttpStatus.ok);
  });

  test(
    'relay routes missing model through router and falls back buffered',
    () async {
      final events = <OpenAiRelayAuditEvent>[];
      final seenModels = <String>[];
      final session = await _startRelay(
        token: token,
        model: model,
        auditSink: events.add,
        routeModel: (requested) {
          expect(requested, isNull);
          return const OpenAiCompatibleRelayRoute(
            primary: model,
            fallbacks: [fallbackModel],
            routeCode: 'free_first',
          );
        },
        forward: ({required model, required messages, systemPrompt}) async* {
          seenModels.add(model.id);
          if (model.id == 'relay-model-1') {
            throw const OpenAiCompatibleRelayException(
              'upstream secret detail',
            );
          }
          yield AiChunk(content: 'fallback:${messages.last.content}');
        },
      );
      addTearDown(session.close);

      final response = await _postJson(
        session.baseUri.resolve('/v1/chat/completions'),
        token: token,
        body: {
          'messages': [
            {'role': 'user', 'content': 'hello'},
          ],
        },
      );

      expect(response.statusCode, HttpStatus.ok);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['model'], fallbackModel.id);
      expect(jsonEncode(json), contains('fallback:hello'));
      expect(jsonEncode(json), isNot(contains('upstream secret detail')));
      expect(seenModels, ['relay-model-1', 'relay-model-2']);
      expect(events.last.code, 'ok_free_first');
      expect(events.last.modelId, fallbackModel.id);
    },
  );
}

Stream<AiChunk> _echoForwarder({
  required OpenAiCompatibleRelayModel model,
  required List<AiMessage> messages,
  String? systemPrompt,
}) {
  return Stream.fromIterable([AiChunk(content: messages.last.content)]);
}

Future<OpenAiCompatibleRelaySession> _startRelay({
  required String token,
  required OpenAiCompatibleRelayModel model,
  OpenAiRelayForwarder forward = _echoForwarder,
  OpenAiRelayModelRouter? routeModel,
  int maxRequestBytes = kOpenAiRelayDefaultMaxRequestBytes,
  int maxConcurrentRequests = kOpenAiRelayDefaultMaxConcurrentRequests,
  OpenAiRelayAuditSink? auditSink,
  OpenAiRelayRemoteImagePolicy remoteImagePolicy =
      const OpenAiRelayRemoteImagePolicy.disabled(),
  OpenAiRelayRemoteImageFetcher? remoteImageFetcher,
}) {
  return const OpenAiCompatibleRelayServer(now: _fixedNow).start(
    relayToken: token,
    listModels: () => [model],
    resolveModel: (id) => id == model.id ? model : null,
    routeModel: routeModel,
    forward: forward,
    maxRequestBytes: maxRequestBytes,
    maxConcurrentRequests: maxConcurrentRequests,
    auditSink: auditSink,
    remoteImagePolicy: remoteImagePolicy,
    remoteImageFetcher: remoteImageFetcher,
  );
}

DateTime _fixedNow() => DateTime.utc(2026, 6, 27, 12, 0, 0);

Future<_BufferedResponse> _get(Uri uri, {String? token}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
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
    request.headers.set(
      'Access-Control-Request-Method',
      (uri.path == '/v1/chat/completions' || uri.path == '/v1/responses')
          ? 'POST'
          : 'GET',
    );
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
  const _BufferedResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final HttpHeaders headers;
  final String body;

  static Future<_BufferedResponse> from(HttpClientResponse response) async {
    final body = await utf8.decodeStream(response);
    return _BufferedResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: body,
    );
  }
}
