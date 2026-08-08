/// 数字人直播 v1。
///
/// 从镜像人格生成直播脚本（开场 / 话题 / 结束），并配置直播平台 RTMP 推流目标；
/// 记录开播会话。实际推流由用户在 OBS 等推流工具中指向 [LiveStreamConfig.rtmpUrl]，
/// 应用负责内容编排与目标配置。
library;

import 'persona_profile.dart';

class LiveStreamConfig {
  final String platform; // 如 YouTube / 抖音 / Twitch
  final String rtmpUrl; // 如 rtmp://a.rtmp.youtube.com/live2
  final String streamKey;

  const LiveStreamConfig({
    this.platform = '',
    this.rtmpUrl = '',
    this.streamKey = '',
  });

  bool get isConfigured =>
      rtmpUrl.trim().isNotEmpty && streamKey.trim().isNotEmpty;
}

class LiveStreamSession {
  final String id;
  final String platform;
  final String topic;
  final DateTime startedAt;
  final String scriptPreview;

  const LiveStreamSession({
    required this.id,
    required this.platform,
    required this.topic,
    required this.startedAt,
    required this.scriptPreview,
  });
}

/// 直播脚本（开场 / 话题 / 结束）。
class LiveStreamScript {
  final String opening;
  final List<String> topics;
  final String closing;

  const LiveStreamScript({
    required this.opening,
    required this.topics,
    required this.closing,
  });

  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('## 开场');
    buffer.writeln(opening);
    buffer.writeln();
    buffer.writeln('## 话题');
    for (final topic in topics) {
      buffer.writeln('- $topic');
    }
    buffer.writeln();
    buffer.writeln('## 结束');
    buffer.writeln(closing);
    return buffer.toString();
  }
}

/// 从镜像人格生成直播脚本。
class LiveStreamScriptGenerator {
  const LiveStreamScriptGenerator();

  LiveStreamScript generate(PersonaProfile persona, {String? topic}) {
    final topics = [
      if (topic != null && topic.trim().isNotEmpty)
        topic.trim()
      else if (persona.goals.isNotEmpty)
        '最近目标：${persona.goals.join('、')}'
      else
        '近况分享',
      if (persona.tasks.isNotEmpty) '当前任务：${persona.tasks.join('、')}',
      if (persona.keywords.isNotEmpty)
        '聊一聊：${persona.keywords.take(3).join('、')}',
    ];

    final styleHint = persona.style.isNotEmpty
        ? '延续你「${persona.style.join('、')}」的表达风格'
        : '保持你一贯自然、亲切的表达风格';

    return LiveStreamScript(
      opening: '大家好，欢迎来到我的直播间。$styleHint，今天想跟大家聊聊这些内容。',
      topics: topics.take(3).toList(growable: false),
      closing: '今天的分享就到这里，感谢大家的陪伴，我们下次直播见！',
    );
  }
}

/// 校验 RTMP 推流地址格式。
bool isValidRtmpUrl(String url) {
  final value = url.trim();
  if (value.isEmpty) return false;
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  if (uri.scheme != 'rtmp' && uri.scheme != 'rtmps') return false;
  if (uri.host.isEmpty) return false;
  return true;
}

/// 数字人直播服务：脚本编排 + 开播会话记录。
class LiveStreamService {
  const LiveStreamService();

  /// 生成一场直播的会话记录（v1 只做内容编排与目标校验，不推送视频）。
  LiveStreamSession startSession({
    required LiveStreamConfig config,
    required PersonaProfile persona,
    String? topic,
  }) {
    if (!config.isConfigured) {
      throw const LiveStreamException('请先配置 RTMP 推流地址与串流密钥');
    }
    if (!isValidRtmpUrl(config.rtmpUrl)) {
      throw const LiveStreamException('RTMP 推流地址格式无效');
    }
    final script = const LiveStreamScriptGenerator().generate(
      persona,
      topic: topic,
    );
    return LiveStreamSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      platform: config.platform.trim().isEmpty
          ? '未命名平台'
          : config.platform.trim(),
      topic: topic?.trim().isNotEmpty == true ? topic!.trim() : '日常直播',
      startedAt: DateTime.now(),
      scriptPreview: script.toMarkdown(),
    );
  }
}

class LiveStreamException implements Exception {
  final String message;
  const LiveStreamException(this.message);

  @override
  String toString() => message;
}
