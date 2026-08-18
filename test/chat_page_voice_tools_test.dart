import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/media/audio_player.dart';
import 'package:ai_chat_app/core/media/openai_text_to_speech_engine.dart';
import 'package:ai_chat_app/core/media/text_to_speech_service.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/text_to_speech_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'serializes standard, design, and clone requests without leaking paths',
    () async {
      final server = await _FakeSpeechServer.start();
      addTearDown(server.close);
      final root = await Directory.systemTemp.createTemp(
        'simichat-voice-wire-',
      );
      addTearDown(() => root.delete(recursive: true));
      final reference = File(p.join(root.path, 'reference.wav'))
        ..writeAsBytesSync([0x43, 0x4f, 0x4d, 0x50, 0x4f, 0x53, 0x45, 0x52]);

      Future<Map<String, dynamic>> synthesize({
        required String model,
        required String text,
        String style = '',
        String? referenceAudioPath,
      }) async {
        final request = server.nextRequest();
        final engine = OpenAiCompatibleTextToSpeechEngine(
          baseUrl: server.baseUrl,
          apiKey: 'voice-tools-test-key',
          model: model,
          style: style,
          referenceAudioPath: referenceAudioPath,
        );
        await _withLoopbackHttp(
          () =>
              engine.synthesize(TextToSpeechInput(text: text, voice: 'alloy')),
        );
        return request;
      }

      final standard = await synthesize(model: 'tts-1', text: '普通合成');
      expect(standard['model'], 'tts-1');
      expect(standard['voice'], 'alloy');
      expect(standard['input'], '普通合成');
      expect(standard['response_format'], 'mp3');
      expect(standard.containsKey('style'), isFalse);

      final design = await synthesize(
        model: 'mimo-v2.5-tts-voicedesign',
        text: '设计模式要朗读的文字',
        style: '本次请求的临时 style',
      );
      expect(design['model'], 'mimo-v2.5-tts-voicedesign');
      expect(design['input'], '设计模式要朗读的文字');
      expect(design['style'], '本次请求的临时 style');

      final clone = await synthesize(
        model: 'mimo-v2.5-tts-voiceclone',
        text: '克隆模式要朗读的文字',
        referenceAudioPath: reference.path,
      );
      expect(clone['model'], 'mimo-v2.5-tts-voiceclone');
      expect(clone['input'], '克隆模式要朗读的文字');
      expect(
        clone['voice'],
        'data:audio/wav;base64,${base64Encode(reference.readAsBytesSync())}',
      );
      expect(jsonEncode(clone), isNot(contains(reference.path)));
    },
  );

  testWidgets('rejects mode mismatches and does not write partial messages', (
    tester,
  ) async {
    const fakeBaseUrl = 'http://127.0.0.1:1/v1';
    var requestCount = 0;
    final fixture = await _createFixture(
      tester,
      _config(
        baseUrl: fakeBaseUrl,
        provider: kTextToSpeechProviderOpenAiCompatible,
        model: 'tts-1',
      ),
      serviceOverride: TextToSpeechService(
        engine: _FakeSpeechEngine(const []),
        player: _FakeAudioPlayer(),
      ),
    );
    addTearDown(fixture.dispose);

    final mismatchError = await tester.runAsync(
      () => _withLoopbackHttp(
        () => synthesizeSpeechMessage(
          ref: fixture.ref,
          sessionId: fixture.sessionId,
          text: '普通模型不能伪造克隆',
          referenceAudioPath: '/private/not-sent/reference.wav',
        ),
      ),
    );
    expect(mismatchError, contains('未声明声音克隆模式'));
    expect(requestCount, 0);

    fixture.ttsNotifier.state = _config(
      baseUrl: fakeBaseUrl,
      provider: kTextToSpeechProviderSimiRouter,
      model: 'mimo-v2.5-tts-voicedesign',
    );
    await tester.pump();
    final missingStyleError = await tester.runAsync(
      () => _withLoopbackHttp(
        () => synthesizeSpeechMessage(
          ref: fixture.ref,
          sessionId: fixture.sessionId,
          text: '没有风格描述',
        ),
      ),
    );
    expect(missingStyleError, contains('声音设计需要填写声音风格描述'));
    expect(requestCount, 0);

    fixture.ttsNotifier.state = _config(
      baseUrl: fakeBaseUrl,
      provider: kTextToSpeechProviderSimiRouter,
      model: 'mimo-v2.5-tts-voiceclone',
    );
    await tester.pump();
    final missingReferenceError = await tester.runAsync(
      () => _withLoopbackHttp(
        () => synthesizeSpeechMessage(
          ref: fixture.ref,
          sessionId: fixture.sessionId,
          text: '没有参考音频',
        ),
      ),
    );
    expect(missingReferenceError, contains('声音克隆需要选择参考音频'));
    expect(requestCount, 0);

    fixture.ttsNotifier.state = _config(
      baseUrl: fakeBaseUrl,
      provider: kTextToSpeechProviderOpenAiCompatible,
      model: 'tts-1',
    );
    await tester.pump();
    final emptyResponseError = await tester.runAsync(
      () => _withLoopbackHttp(
        () => synthesizeSpeechMessage(
          ref: fixture.ref,
          sessionId: fixture.sessionId,
          text: '服务端返回空音频',
        ),
      ),
    );
    expect(emptyResponseError, contains('声音合成未返回音频'));

    final messages = await tester.runAsync(
      () => fixture.db.messageDao.getMessagesBySession(fixture.sessionId),
    );
    final attachments = await tester.runAsync(
      () => fixture.db.attachmentDao.getAllAttachments(),
    );
    expect(messages, isEmpty);
    expect(attachments, isEmpty);
    expect(
      Directory(p.join(fixture.root.path, 'generated_speech')).existsSync(),
      isFalse,
    );
  });
}

TextToSpeechConfig _config({
  required String baseUrl,
  required String provider,
  required String model,
  String style = '',
  String? referenceAudioPath,
}) {
  return TextToSpeechConfig(
    enabled: true,
    provider: provider,
    baseUrl: baseUrl,
    model: model,
    voice: 'alloy',
    apiKeyEncrypted: KeyEncryptor.encrypt('voice-tools-test-key'),
    speed: '1.0',
    responseFormat: 'mp3',
    style: style,
    referenceAudioPath: referenceAudioPath,
  );
}

Future<_VoiceFixture> _createFixture(
  WidgetTester tester,
  TextToSpeechConfig config, {
  TextToSpeechService? serviceOverride,
}) async {
  // testWidgets runs in Flutter's fake-async zone; asynchronous file-system
  // calls made before tester.runAsync can remain pending indefinitely. The
  // synchronous directory creation is deterministic here and all network /
  // async work below still runs through the test harness.
  final root = Directory.systemTemp.createTempSync('simichat-voice-tools-');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    pathProviderChannel,
    (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
        case 'getTemporaryDirectory':
          return root.path;
        default:
          return null;
      }
    },
  );

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  const sessionId = 'voice-tools-session';
  await db.sessionDao.createSession(id: sessionId);

  SharedPreferences.setMockInitialValues({});
  final ttsNotifier = TextToSpeechConfigNotifier();
  await ttsNotifier.ready;
  ttsNotifier.state = config;
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      textToSpeechConfigProvider.overrideWith((ref) => ttsNotifier),
      if (serviceOverride != null)
        textToSpeechServiceProvider.overrideWithValue(serviceOverride),
    ],
  );
  WidgetRef? capturedRef;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, child) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return _VoiceFixture(
    db: db,
    container: container,
    notifier: ttsNotifier,
    ref: capturedRef!,
    root: root,
    sessionId: sessionId,
    service: serviceOverride,
    pathProviderChannel: pathProviderChannel,
    tester: tester,
  );
}

class _VoiceFixture {
  const _VoiceFixture({
    required this.db,
    required this.container,
    required this.notifier,
    required this.ref,
    required this.root,
    required this.sessionId,
    this.service,
    required this.pathProviderChannel,
    required this.tester,
  });

  final AppDatabase db;
  final ProviderContainer container;
  final TextToSpeechConfigNotifier notifier;
  final WidgetRef ref;
  final Directory root;
  final String sessionId;
  final TextToSpeechService? service;
  final MethodChannel pathProviderChannel;
  final WidgetTester tester;

  TextToSpeechConfigNotifier get ttsNotifier => notifier;

  Future<void> dispose() async {
    service?.dispose();
    container.dispose();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      null,
    );
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

/// TestWidgetsFlutterBinding installs a rejecting HttpClient by default. The
/// fake TTS server is loopback-only, so opt into the standard dart:io client
/// for just these calls instead of weakening the process-wide test binding.
class _AllowLoopbackHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (certificate, host, port) => true;
    return client;
  }
}

Future<T> _withLoopbackHttp<T>(Future<T> Function() action) {
  return HttpOverrides.runWithHttpOverrides(
    action,
    _AllowLoopbackHttpOverrides(),
  );
}

class _FakeSpeechEngine implements TextToSpeechEngine {
  const _FakeSpeechEngine(this.bytes);

  final List<int> bytes;

  @override
  Future<List<int>> synthesize(
    TextToSpeechInput input, {
    CancelToken? cancelToken,
  }) async => bytes;
}

class _FakeAudioPlayer implements AudioPlayerPlatform {
  final StreamController<AudioPlaybackEvent> _events =
      StreamController<AudioPlaybackEvent>.broadcast();

  @override
  Stream<AudioPlaybackEvent> get events => _events.stream;

  @override
  Future<void> playFile(String audioPath) async {}

  @override
  Future<void> stop() async {}
}

class _FakeSpeechServer {
  _FakeSpeechServer._(this.server, this.responseBytes);

  final HttpServer server;
  final List<int> responseBytes;
  final List<Completer<Map<String, dynamic>>> _waiters = [];
  var requestCount = 0;

  String get baseUrl => 'http://${server.address.host}:${server.port}/v1';

  static Future<_FakeSpeechServer> start({
    List<int> responseBytes = const [0x49, 0x44, 0x33],
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeSpeechServer._(server, responseBytes);
    unawaited(
      server.forEach((request) async {
        _requestCountIncrement(fake);
        final body = await utf8.decodeStream(request);
        final payload = jsonDecode(body) as Map<String, dynamic>;
        if (fake._waiters.isNotEmpty) {
          fake._waiters.removeAt(0).complete(payload);
        }
        request.response
          ..headers.contentType = ContentType('audio', 'mpeg')
          ..add(fake.responseBytes);
        await request.response.close();
      }),
    );
    return fake;
  }

  Future<Map<String, dynamic>> nextRequest() {
    final completer = Completer<Map<String, dynamic>>();
    _waiters.add(completer);
    return completer.future;
  }

  Future<void> close() => server.close(force: true);
}

void _requestCountIncrement(_FakeSpeechServer server) {
  server.requestCount++;
}
