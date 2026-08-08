import 'dart:convert';

import '../memory/user_profile.dart';

/// 数字孪生 / 镜像数字人 v1。
///
/// - [PersonaProfileGenerator]：把本地用户画像蒸馏成「人格配置」（对话风格 / 作息 /
///   目标 / 任务 / 关键词）与可注入的替身 system prompt；
/// - [MediaPersonaAnalyzer]：从消息中的 emoji 使用与语音 / 图片附件频率提取媒体信号，
///   作为画像的补充来源。

/// 人格配置（镜像数字人 v1）。
class PersonaProfile {
  final String personaName;

  /// 对话风格信号。
  final List<String> style;

  /// 作息线索。
  final List<String> schedule;

  /// 偏好 / 目标 / 任务。
  final List<String> preferences;
  final List<String> goals;
  final List<String> tasks;

  /// 常提关键词。
  final List<String> keywords;

  /// 媒体信号（emoji 风格、语音 / 图片倾向）。
  final MediaPersonaSignals media;

  const PersonaProfile({
    required this.personaName,
    required this.style,
    required this.schedule,
    required this.preferences,
    required this.goals,
    required this.tasks,
    required this.keywords,
    required this.media,
  });

  bool get isEmpty =>
      style.isEmpty &&
      schedule.isEmpty &&
      preferences.isEmpty &&
      goals.isEmpty &&
      tasks.isEmpty &&
      keywords.isEmpty &&
      media.isEmpty;

  /// 生成可注入的「替身回复」system prompt 模板。
  String buildPersonaSystemPrompt() {
    final buffer = StringBuffer(
      '你是「$personaName」，SimiAIChat 生成的镜像数字人，'
      '代表用户本人与对方对话。请严格模仿用户的表达风格与思维习惯：\n',
    );
    if (style.isNotEmpty) buffer.writeln('表达风格：${style.join('、')}');
    if (schedule.isNotEmpty) buffer.writeln('作息习惯：${schedule.join('、')}');
    if (preferences.isNotEmpty) buffer.writeln('偏好：${preferences.join('、')}');
    if (goals.isNotEmpty) buffer.writeln('目标：${goals.join('、')}');
    if (tasks.isNotEmpty) buffer.writeln('当前任务：${tasks.join('、')}');
    if (keywords.isNotEmpty) buffer.writeln('常用词：${keywords.join('、')}');
    if (media.isNotEmpty) {
      buffer.writeln('沟通偏好：${media.describe()}');
    }
    buffer.writeln('遇到不确定的信息不要编造，礼貌说明。');
    return buffer.toString();
  }

  String toJson() => const JsonEncoder.withIndent('  ').convert({
    'personaName': personaName,
    'style': style,
    'schedule': schedule,
    'preferences': preferences,
    'goals': goals,
    'tasks': tasks,
    'keywords': keywords,
    'media': media.toJson(),
  });
}

/// 从用户画像生成人格配置。
class PersonaProfileGenerator {
  const PersonaProfileGenerator();

  PersonaProfile fromUserProfile(UserProfile profile) {
    return PersonaProfile(
      personaName: '数字孪生',
      style: List.of(profile.styleSignals),
      schedule: List.of(profile.scheduleSignals),
      preferences: List.of(profile.preferences),
      goals: List.of(profile.goals),
      tasks: List.of(profile.tasks),
      keywords: List.of(profile.keywords),
      media: MediaPersonaSignals.empty(),
    );
  }
}

/// 媒体人格信号（emoji 风格、语音 / 图片倾向）。
class MediaPersonaSignals {
  final int emojiCount;
  final int audioAttachmentCount;
  final int imageAttachmentCount;
  final int messageCount;
  final Map<String, int> topEmoji;

  const MediaPersonaSignals({
    required this.emojiCount,
    required this.audioAttachmentCount,
    required this.imageAttachmentCount,
    required this.messageCount,
    required this.topEmoji,
  });

  static MediaPersonaSignals empty() => const MediaPersonaSignals(
    emojiCount: 0,
    audioAttachmentCount: 0,
    imageAttachmentCount: 0,
    messageCount: 0,
    topEmoji: {},
  );

  bool get isEmpty => messageCount == 0;
  bool get isNotEmpty => !isEmpty;

  double get emojiPerMessage =>
      messageCount == 0 ? 0 : emojiCount / messageCount;

  bool get prefersVoice => audioAttachmentCount > imageAttachmentCount;
  bool get prefersImage => imageAttachmentCount > audioAttachmentCount;

  /// 中文可读的沟通偏好描述。
  String describe() {
    final parts = <String>[];
    if (emojiPerMessage > 0.3) parts.add('喜欢使用表情符号');
    if (prefersVoice) parts.add('更常发语音');
    if (prefersImage) parts.add('更常发图片');
    if (topEmoji.isNotEmpty) {
      parts.add(
        '常用 emoji：${topEmoji.entries.take(3).map((e) => e.key).join('、')}',
      );
    }
    return parts.isEmpty ? '暂无显著媒体偏好' : parts.join('；');
  }

  Map<String, dynamic> toJson() => {
    'emojiCount': emojiCount,
    'audioAttachmentCount': audioAttachmentCount,
    'imageAttachmentCount': imageAttachmentCount,
    'messageCount': messageCount,
    'topEmoji': topEmoji,
  };
}

/// 从消息文本与附件类型统计媒体信号。
class MediaPersonaAnalyzer {
  const MediaPersonaAnalyzer();

  static final _emojiPattern = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}]',
    unicode: true,
  );

  MediaPersonaSignals analyze({
    required List<String> messageContents,
    required int audioAttachmentCount,
    required int imageAttachmentCount,
  }) {
    var emojiCount = 0;
    final emojiTally = <String, int>{};
    for (final content in messageContents) {
      for (final match in _emojiPattern.allMatches(content)) {
        emojiCount++;
        final emoji = match.group(0)!;
        emojiTally[emoji] = (emojiTally[emoji] ?? 0) + 1;
      }
    }
    final topEmoji = Map<String, int>.from(emojiTally);
    return MediaPersonaSignals(
      emojiCount: emojiCount,
      audioAttachmentCount: audioAttachmentCount,
      imageAttachmentCount: imageAttachmentCount,
      messageCount: messageContents.length,
      topEmoji: topEmoji,
    );
  }
}
