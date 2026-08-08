import 'package:ai_chat_app/core/twin/live_stream_service.dart';
import 'package:ai_chat_app/core/twin/persona_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LiveStreamScriptGenerator', () {
    test('generates opening topics and closing from persona', () {
      const persona = PersonaProfile(
        personaName: '数字孪生',
        style: ['先总结再展开'],
        schedule: ['熬夜型'],
        preferences: ['喜欢简洁'],
        goals: ['提升英语'],
        tasks: ['完成项目 X'],
        keywords: ['Flutter', 'Dart'],
        media: MediaPersonaSignals(
          emojiCount: 0,
          audioAttachmentCount: 0,
          imageAttachmentCount: 0,
          messageCount: 0,
          topEmoji: {},
        ),
      );

      final script = const LiveStreamScriptGenerator().generate(
        persona,
        topic: 'Flutter 分享',
      );
      final md = script.toMarkdown();

      expect(md, contains('开场'));
      expect(md, contains('Flutter 分享'));
      expect(md, contains('完成项目 X'));
      expect(md, contains('结束'));
      expect(script.topics.length, greaterThanOrEqualTo(1));
    });
  });

  group('isValidRtmpUrl', () {
    test('accepts rtmp and rejects others', () {
      expect(isValidRtmpUrl('rtmp://a.rtmp.youtube.com/live2'), isTrue);
      expect(isValidRtmpUrl('rtmps://live.twitch.tv/app'), isTrue);
      expect(isValidRtmpUrl('https://example.com'), isFalse);
      expect(isValidRtmpUrl(''), isFalse);
    });
  });

  group('LiveStreamService', () {
    test('starts a session with validated rtmp config', () {
      const persona = PersonaProfile(
        personaName: 't',
        style: [],
        schedule: [],
        preferences: [],
        goals: [],
        tasks: [],
        keywords: ['Flutter'],
        media: MediaPersonaSignals(
          emojiCount: 0,
          audioAttachmentCount: 0,
          imageAttachmentCount: 0,
          messageCount: 0,
          topEmoji: {},
        ),
      );
      const config = LiveStreamConfig(
        platform: 'YouTube',
        rtmpUrl: 'rtmp://a.rtmp.youtube.com/live2',
        streamKey: 'key-123',
      );

      final session = const LiveStreamService().startSession(
        config: config,
        persona: persona,
        topic: 'Flutter 直播',
      );

      expect(session.platform, 'YouTube');
      expect(session.topic, 'Flutter 直播');
      expect(session.scriptPreview, contains('开场'));
      expect(session.id, isNotEmpty);
    });

    test('rejects invalid rtmp url', () {
      const persona = PersonaProfile(
        personaName: 't',
        style: [],
        schedule: [],
        preferences: [],
        goals: [],
        tasks: [],
        keywords: [],
        media: MediaPersonaSignals(
          emojiCount: 0,
          audioAttachmentCount: 0,
          imageAttachmentCount: 0,
          messageCount: 0,
          topEmoji: {},
        ),
      );
      expect(
        () => const LiveStreamService().startSession(
          config: const LiveStreamConfig(
            rtmpUrl: 'https://not-rtmp.com',
            streamKey: 'k',
          ),
          persona: persona,
        ),
        throwsA(isA<LiveStreamException>()),
      );
    });
  });
}
