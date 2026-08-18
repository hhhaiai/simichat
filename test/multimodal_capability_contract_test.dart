import 'package:ai_chat_app/core/ai/ai_protocol.dart';
import 'package:ai_chat_app/core/ai/ai_service.dart';
import 'package:ai_chat_app/core/ai/claude_protocol.dart';
import 'package:ai_chat_app/core/ai/gemini_protocol.dart';
import 'package:ai_chat_app/core/ai/model_capability.dart';
import 'package:ai_chat_app/core/ai/model_provider_preset.dart';
import 'package:ai_chat_app/core/ai/ollama_protocol.dart';
import 'package:ai_chat_app/core/ai/openai_chat_protocol.dart';
import 'package:ai_chat_app/core/ai/openai_response_protocol.dart';
import 'package:ai_chat_app/core/ai/universal_media_service.dart';
import 'package:ai_chat_app/shared/providers/chat_provider.dart';
import 'package:ai_chat_app/shared/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('多模态 Composer 入口契约', () {
    testWidgets('移动端加号菜单暴露已配置的多模态回调边界', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TextEditingController(text: '初始媒体描述');
      final focusNode = FocusNode();
      final hasText = ValueNotifier<bool>(true);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);

      final imagePrompts = <String>[];
      final videoPrompts = <String>[];
      final speechPrompts = <String>[];
      final musicPrompts = <String>[];
      var realtimeOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              hasTextNotifier: hasText,
              showVoiceInput: false,
              onSend: (_, _) async => true,
              onGenerateImageWithAttachments: (text, _) async {
                imagePrompts.add(text);
                return true;
              },
              onGenerateVideo: (text, _) async {
                videoPrompts.add(text);
                return true;
              },
              onSynthesizeSpeech: (text) async {
                speechPrompts.add(text);
                return true;
              },
              onGenerateMusic: (text) async {
                musicPrompts.add(text);
                return true;
              },
              onEditImage: (_) async => true,
              onRealtimeVoice: () async {
                realtimeOpened = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> openMenu() async {
        await tester.tap(find.byTooltip('添加附件'));
        await tester.pumpAndSettle();
      }

      Future<void> setPrompt(String prompt) async {
        controller.text = prompt;
        hasText.value = true;
        await tester.pump();
      }

      Future<void> tapMenuItem(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await openMenu();

      // 这里检查的是真实移动端 Composer 条目，不是 service fake；图片生成和图片编辑
      // 当前没有独立 key，因此把用户可见中文标题也纳入入口契约。
      expect(
        find.byKey(const ValueKey('realtime-voice-menu-item')),
        findsOneWidget,
      );
      expect(find.text('编辑图片'), findsOneWidget);
      expect(find.text('生成图片'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('generate-video-menu-item')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('synthesize-speech-menu-item')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('generate-music-menu-item')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('generate-video-menu-item')),
            )
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('synthesize-speech-menu-item')),
            )
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('generate-music-menu-item')),
            )
            .enabled,
        isTrue,
      );

      await tapMenuItem(find.byKey(const ValueKey('realtime-voice-menu-item')));
      expect(realtimeOpened, isTrue);

      await setPrompt('图片描述');
      await openMenu();
      await tapMenuItem(find.text('生成图片'));

      await setPrompt('视频描述');
      await openMenu();
      await tapMenuItem(find.byKey(const ValueKey('generate-video-menu-item')));

      await setPrompt('请朗读这句话');
      await openMenu();
      await tapMenuItem(
        find.byKey(const ValueKey('synthesize-speech-menu-item')),
      );

      await setPrompt('生成一段音乐');
      await openMenu();
      await tapMenuItem(find.byKey(const ValueKey('generate-music-menu-item')));

      expect(imagePrompts, ['图片描述']);
      expect(videoPrompts, ['视频描述']);
      expect(speechPrompts, ['请朗读这句话']);
      expect(musicPrompts, ['生成一段音乐']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('能力被阻断时视频和音乐入口仍可见但保持禁用', (tester) async {
      final controller = TextEditingController(text: '媒体提示词');
      final focusNode = FocusNode();
      final hasText = ValueNotifier<bool>(true);
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(hasText.dispose);

      var videoCalled = false;
      var musicCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              controller: controller,
              focusNode: focusNode,
              isStreaming: false,
              hasTextNotifier: hasText,
              showVoiceInput: false,
              onSend: (_, _) async => true,
              onGenerateVideo: (_, _) async {
                videoCalled = true;
                return true;
              },
              onGenerateMusic: (_) async {
                musicCalled = true;
                return true;
              },
              videoActionDisabledReason: '当前渠道协议不提供通用视频接口',
              musicActionDisabledReason: '请先在当前渠道配置 API Key 后再生成音乐',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();

      final video = tester.widget<ListTile>(
        find.byKey(const ValueKey('generate-video-menu-item')),
      );
      final music = tester.widget<ListTile>(
        find.byKey(const ValueKey('generate-music-menu-item')),
      );
      expect(video.enabled, isFalse);
      expect(music.enabled, isFalse);
      expect(find.text('当前渠道协议不提供通用视频接口'), findsOneWidget);
      expect(find.text('请先在当前渠道配置 API Key 后再生成音乐'), findsOneWidget);
      expect(video.onTap, isNull);
      expect(music.onTap, isNull);
      expect(videoCalled, isFalse);
      expect(musicCalled, isFalse);
    });
  });

  group('多模态能力与协议入口 manifest', () {
    UniversalMediaCapability resolve({
      required UniversalMediaKind kind,
      String protocol = 'openai_chat',
      String? baseUrl = 'https://media.example.test/v1',
      bool? apiKeyConfigured = true,
      String? modelName = 'chat-model',
      String? modelCapability = ModelCapability.chat,
      String? mediaModel = 'media-model',
      String? mediaEndpoint = '/v1/media',
    }) {
      return resolveUniversalMediaCapability(
        kind: kind,
        protocol: protocol,
        baseUrl: baseUrl,
        apiKeyConfigured: apiKeyConfigured,
        modelName: modelName,
        modelCapability: modelCapability,
        mediaModel: mediaModel,
        mediaEndpoint: mediaEndpoint,
      );
    }

    test('通用媒体门禁区分路由配置与厂商能力', () {
      for (final protocol in ['openai_chat', 'openai_response']) {
        expect(
          resolve(kind: UniversalMediaKind.video, protocol: protocol).status,
          UniversalMediaCapabilityStatus.available,
          reason: '$protocol 应暴露已经配置的通用路由',
        );
        expect(
          resolve(kind: UniversalMediaKind.music, protocol: protocol).status,
          UniversalMediaCapabilityStatus.available,
        );
      }

      for (final protocol in ['claude', 'gemini', 'ollama']) {
        final capability = resolve(
          kind: UniversalMediaKind.video,
          protocol: protocol,
        );
        expect(capability.status, UniversalMediaCapabilityStatus.unavailable);
        expect(capability.message, contains('不提供通用视频接口'));
      }

      expect(
        resolve(kind: UniversalMediaKind.video, apiKeyConfigured: false).status,
        UniversalMediaCapabilityStatus.notConfigured,
      );
      expect(
        resolve(kind: UniversalMediaKind.video, mediaModel: null).status,
        UniversalMediaCapabilityStatus.notConfigured,
      );
      expect(
        resolve(
          kind: UniversalMediaKind.video,
          modelCapability: ModelCapability.embedding,
        ).status,
        UniversalMediaCapabilityStatus.unavailable,
      );
      // Chat-compatible 模型可以使用显式配置的通用路由，但不能把模型名本身
      // 当成它是专用视频模型的证据。
      expect(
        ModelCapability.supportsVideoModel(
          capability: ModelCapability.chat,
          modelId: 'video-generation-unknown',
        ),
        isFalse,
      );

      expect(canUseChannelImageGeneration('openai_chat'), isTrue);
      expect(canUseChannelImageGeneration('openai_response'), isTrue);
      expect(canUseChannelImageGeneration('claude'), isFalse);
      expect(canUseChannelImageGeneration('gemini'), isFalse);
      expect(canUseChannelImageGeneration('ollama'), isFalse);
      expect(canUseChannelSpeechToTextFallback('openai_chat'), isTrue);
      expect(canUseChannelSpeechToTextFallback('claude'), isFalse);
    });

    test('协议 registry 包含五个聊天 adapter 且将 xAI 映射到 OpenAI Chat', () {
      final protocols = <String, Type>{
        'openai_chat': OpenAiChatProtocol,
        'openai_response': OpenAiResponseProtocol,
        'claude': ClaudeProtocol,
        'gemini': GeminiProtocol,
        'ollama': OllamaProtocol,
      };

      for (final entry in protocols.entries) {
        final adapter = AiService.getProtocol(entry.key);
        expect(adapter, isA<AiProtocol>());
        expect(adapter.runtimeType, entry.value);
      }

      expect(
        () => AiService.getProtocol('xai'),
        throwsA(isA<UnsupportedError>()),
        reason: 'xAI Chat 是 openai_chat 上的渠道预设，不是独立 adapter',
      );
      final xai = findModelProviderPreset('xai');
      expect(xai, isNotNull);
      expect(xai!.protocol, 'openai_chat');
      expect(xai.openAiCompatible, isTrue);
      expect(xai.baseUrl, 'https://api.x.ai/v1');
    });
  });
}
