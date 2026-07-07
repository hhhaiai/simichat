import 'dart:convert';

import 'dreaming_service.dart';
import 'user_profile.dart';

const kAssistantReflectionTitle = '本地反思报告';
const kAssistantReflectionPromptTitle = '本地反思行动提示';

class ReflectionInsight {
  const ReflectionInsight({
    required this.category,
    required this.text,
    this.priority = 'normal',
  });

  factory ReflectionInsight.fromJson(Map<String, dynamic> json) {
    return ReflectionInsight(
      category: _safeLabel(json['category'] as String? ?? '其他'),
      text: _safeBody(json['text'] as String? ?? ''),
      priority: _safePriority(json['priority'] as String? ?? 'normal'),
    );
  }

  final String category;
  final String text;
  final String priority;

  Map<String, dynamic> toJson() => {
    'category': category,
    'text': text,
    'priority': priority,
  };
}

class ReflectionReport {
  const ReflectionReport({
    required this.dayKey,
    required this.generatedAt,
    required this.sourceDigestDayKey,
    required this.sessionCount,
    required this.originalMessageCount,
    required this.userMessageCount,
    required this.assistantMessageCount,
    required this.pendingProfileProposalCount,
    required this.insights,
    required this.actionItems,
    this.sourceDigestIsTruncated = false,
    this.sourceDigestMessageLimit = 0,
    int? sourceDigestTotalOriginalMessageCount,
  }) : sourceDigestTotalOriginalMessageCount =
           sourceDigestTotalOriginalMessageCount ?? originalMessageCount;

  factory ReflectionReport.fromJson(Map<String, dynamic> json) {
    return ReflectionReport(
      dayKey: _safeLabel(json['dayKey'] as String? ?? ''),
      generatedAt:
          DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceDigestDayKey: _safeLabel(
        json['sourceDigestDayKey'] as String? ?? '',
      ),
      sessionCount: json['sessionCount'] as int? ?? 0,
      originalMessageCount: json['originalMessageCount'] as int? ?? 0,
      userMessageCount: json['userMessageCount'] as int? ?? 0,
      assistantMessageCount: json['assistantMessageCount'] as int? ?? 0,
      pendingProfileProposalCount:
          json['pendingProfileProposalCount'] as int? ?? 0,
      sourceDigestIsTruncated:
          json['sourceDigestIsTruncated'] as bool? ?? false,
      sourceDigestMessageLimit: json['sourceDigestMessageLimit'] as int? ?? 0,
      sourceDigestTotalOriginalMessageCount:
          json['sourceDigestTotalOriginalMessageCount'] as int? ??
          json['originalMessageCount'] as int? ??
          0,
      insights:
          (json['insights'] as List?)
              ?.whereType<Map>()
              .map((item) => ReflectionInsight.fromJson(item.cast()))
              .where((item) => item.text.isNotEmpty)
              .toList(growable: false) ??
          const [],
      actionItems:
          (json['actionItems'] as List?)
              ?.whereType<String>()
              .map(_safeBody)
              .where((item) => item.isNotEmpty)
              .toList(growable: false) ??
          const [],
    );
  }

  final String dayKey;
  final DateTime generatedAt;
  final String sourceDigestDayKey;
  final int sessionCount;
  final int originalMessageCount;
  final int userMessageCount;
  final int assistantMessageCount;
  final int pendingProfileProposalCount;
  final bool sourceDigestIsTruncated;
  final int sourceDigestMessageLimit;
  final int sourceDigestTotalOriginalMessageCount;
  final List<ReflectionInsight> insights;
  final List<String> actionItems;

  bool get hasContent => originalMessageCount > 0 && insights.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'dayKey': dayKey,
    'generatedAt': generatedAt.toIso8601String(),
    'sourceDigestDayKey': sourceDigestDayKey,
    'sessionCount': sessionCount,
    'originalMessageCount': originalMessageCount,
    'userMessageCount': userMessageCount,
    'assistantMessageCount': assistantMessageCount,
    'pendingProfileProposalCount': pendingProfileProposalCount,
    'sourceDigestIsTruncated': sourceDigestIsTruncated,
    if (sourceDigestMessageLimit > 0)
      'sourceDigestMessageLimit': sourceDigestMessageLimit,
    'sourceDigestTotalOriginalMessageCount':
        sourceDigestTotalOriginalMessageCount,
    'insights': insights.map((item) => item.toJson()).toList(),
    'actionItems': actionItems,
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# $kAssistantReflectionTitle $dayKey')
      ..writeln()
      ..writeln('- 生成时间：${generatedAt.toIso8601String()}')
      ..writeln('- 来源 Dreaming：$sourceDigestDayKey')
      ..writeln('- 会话数：$sessionCount')
      ..writeln('- 已反思原始消息数：$originalMessageCount')
      ..writeln('- 来源 Dreaming 原始消息总数：$sourceDigestTotalOriginalMessageCount')
      ..writeln('- 用户 / 助手消息：$userMessageCount / $assistantMessageCount')
      ..writeln('- 待确认画像变更：$pendingProfileProposalCount')
      ..writeln()
      ..writeln('## 反思结论')
      ..writeln();

    if (sourceDigestIsTruncated) {
      buffer
        ..writeln(
          '> 注意：来源 Dreaming 只整理了最近 $sourceDigestMessageLimit / $sourceDigestTotalOriginalMessageCount 条原始消息，本反思不代表当天全部对话。',
        )
        ..writeln();
    }

    if (insights.isEmpty) {
      buffer.writeln('- 暂无可反思内容');
    } else {
      for (final insight in insights) {
        buffer.writeln('- [${insight.category}] ${insight.text}');
      }
    }

    buffer
      ..writeln()
      ..writeln('## 下一步行动')
      ..writeln();
    if (actionItems.isEmpty) {
      buffer.writeln('- 继续积累对话后再反思');
    } else {
      for (final item in actionItems) {
        buffer.writeln('- $item');
      }
    }
    return buffer.toString();
  }
}

class ReflectionService {
  const ReflectionService({DateTime Function()? now}) : _now = now;

  final DateTime Function()? _now;

  ReflectionReport buildDailyReflection({
    required DreamingDigest digest,
    UserProfile? profile,
    int pendingProfileProposalCount = 0,
  }) {
    final generatedAt = _now?.call() ?? DateTime.now();
    final insights = <ReflectionInsight>[];
    final actionItems = <String>[];

    void addInsight(
      String category,
      String text, {
      String priority = 'normal',
    }) {
      final safe = _safeBody(text);
      if (safe.isEmpty) return;
      if (insights.any(
        (item) => item.category == category && item.text == safe,
      )) {
        return;
      }
      insights.add(
        ReflectionInsight(
          category: _safeLabel(category),
          text: safe,
          priority: _safePriority(priority),
        ),
      );
    }

    void addAction(String text) {
      final safe = _safeBody(text);
      if (safe.isEmpty || actionItems.contains(safe)) return;
      actionItems.add(safe);
    }

    if (!digest.hasContent) {
      addInsight('节奏', '今天暂无可整理对话，暂不生成质量判断。');
      addAction('继续积累对话，下一次 Dreaming 后再运行反思。');
    } else {
      _reflectSourceFreshness(digest, generatedAt, addInsight, addAction);
      _reflectDigestCompleteness(digest, addInsight, addAction);
      _reflectUnansweredSessions(digest, addInsight, addAction);
      _reflectRepeatedUserIntent(digest, addInsight, addAction);
      _reflectSessionFollowUpPressure(digest, addInsight, addAction);
      _reflectLastUserMessageSessions(digest, addInsight, addAction);
      _reflectLatestUserTask(digest, addInsight, addAction);
      _reflectNextBestFollowUp(profile, digest, addInsight, addAction);
      _reflectConversationBalance(digest, addInsight, addAction);
      _reflectLongSessions(digest, addInsight, addAction);
      _reflectMemoryAndProfile(
        digest,
        profile,
        pendingProfileProposalCount,
        addInsight,
        addAction,
      );
    }

    return ReflectionReport(
      dayKey: formatDreamingDay(generatedAt),
      generatedAt: generatedAt,
      sourceDigestDayKey: digest.dayKey,
      sessionCount: digest.sessionCount,
      originalMessageCount: digest.originalMessageCount,
      userMessageCount: digest.userMessageCount,
      assistantMessageCount: digest.assistantMessageCount,
      pendingProfileProposalCount: pendingProfileProposalCount,
      sourceDigestIsTruncated: digest.isTruncated,
      sourceDigestMessageLimit: digest.messageLimit,
      sourceDigestTotalOriginalMessageCount: digest.totalOriginalMessageCount,
      insights: List.unmodifiable(insights.take(8)),
      actionItems: List.unmodifiable(actionItems.take(8)),
    );
  }
}

ReflectionReport? decodeReflectionReport(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw) as Map;
    return ReflectionReport.fromJson(decoded.cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

String encodeReflectionReport(ReflectionReport report) =>
    jsonEncode(report.toJson());

List<ReflectionReport> decodeReflectionReportHistory(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .whereType<Map>()
        .map((item) => ReflectionReport.fromJson(item.cast<String, dynamic>()))
        .where((report) => report.hasContent)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

String encodeReflectionReportHistory(List<ReflectionReport> reports) =>
    jsonEncode(reports.map((report) => report.toJson()).toList());

String? buildAssistantReflectionSystemPrompt(
  ReflectionReport? report, {
  int maxInsights = 2,
  int maxActionItems = 3,
}) {
  if (report == null || !report.hasContent) return null;

  final highInsights = report.insights
      .where((item) => item.priority == 'high')
      .map((item) {
        final category = _safeLabel(item.category);
        final text = _safeBody(item.text);
        return text.isEmpty ? '' : '[$category] $text';
      })
      .where((item) => item.isNotEmpty)
      .take(maxInsights)
      .toList(growable: false);
  final actions = report.actionItems
      .map(_safeBody)
      .where((item) => item.isNotEmpty)
      .take(maxActionItems)
      .toList(growable: false);

  if (highInsights.isEmpty && actions.isEmpty) return null;

  final buffer = StringBuffer()
    ..writeln('## $kAssistantReflectionPromptTitle')
    ..writeln(
      '以下内容来自本机 Dreaming 后的反思，只用于改善下一轮回复；不要主动暴露报告内容，若与用户当前明确表达冲突，以当前表达为准。',
    );
  if (highInsights.isNotEmpty) {
    buffer.writeln('关注点：');
    for (final insight in highInsights) {
      buffer.writeln('- $insight');
    }
  }
  if (actions.isNotEmpty) {
    buffer.writeln('建议行动：');
    for (final action in actions) {
      buffer.writeln('- $action');
    }
  }
  return buffer.toString().trim();
}

void _reflectSourceFreshness(
  DreamingDigest digest,
  DateTime generatedAt,
  void Function(String category, String text, {String priority}) addInsight,
  void Function(String text) addAction,
) {
  final reflectionDayKey = formatDreamingDay(generatedAt);
  if (digest.dayKey == reflectionDayKey) return;
  addInsight(
    '来源新鲜度',
    '当前反思日期是 $reflectionDayKey，但来源 Dreaming 是 ${digest.dayKey}，可能不是今日最新上下文。',
    priority: 'high',
  );
  addAction('先运行今日 Dreaming，再基于最新日报确认反思和长期画像。');
}

void _reflectUnansweredSessions(
  DreamingDigest digest,
  void Function(String category, String text, {String priority}) addInsight,
  void Function(String text) addAction,
) {
  final unanswered =
      digest.sessions
          .where(
            (session) =>
                session.userMessageCount > 0 &&
                session.assistantMessageCount == 0,
          )
          .toList(growable: false)
        ..sort((a, b) => b.userMessageCount.compareTo(a.userMessageCount));
  if (unanswered.isEmpty) return;

  final session = unanswered.first;
  final title = _safeBody(session.title).isNotEmpty
      ? _safeBody(session.title)
      : '未命名会话';
  addInsight(
    '未回复会话',
    '会话「$title」有 ${session.userMessageCount} 条用户消息但没有助手回复，可能存在局部未收口问题。',
    priority: 'high',
  );
  addAction('下次打开「$title」时，先补一个简短回应和未完成问题清单。');
}

void _reflectLastUserMessageSessions(
  DreamingDigest digest,
  void Function(String category, String text, {String priority}) addInsight,
  void Function(String text) addAction,
) {
  final pending =
      digest.sessions
          .where(
            (session) =>
                session.lastMessageRole == 'user' &&
                session.assistantMessageCount > 0,
          )
          .toList(growable: false)
        ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
  if (pending.isEmpty) return;

  final session = pending.first;
  final title = _safeBody(session.title).isNotEmpty
      ? _safeBody(session.title)
      : '未命名会话';
  addInsight(
    '最后一问未答',
    _lastUserMessageInsightText(title, session.latestUserHighlight),
    priority: 'high',
  );
  addAction('下次打开「$title」时，先回应最新追问，再总结未完成问题。');
}

String _lastUserMessageInsightText(String title, String latestUserHighlight) {
  final latest = _safeBody(latestUserHighlight);
  if (latest.isEmpty) {
    return '会话「$title」最后一条消息来自用户，说明已有回复后仍有新的追问待收口。';
  }
  return '会话「$title」最后一条消息来自用户，最新追问是：$latest';
}

void _reflectRepeatedUserIntent(
  DreamingDigest digest,
  void Function(String category, String text, {String priority}) addInsight,
  void Function(String text) addAction,
) {
  final repeated =
      digest.sessions
          .where((session) => session.userMessageCount >= 3)
          .map((session) => _RepeatedIntentCandidate.fromSession(session))
          .whereType<_RepeatedIntentCandidate>()
          .toList(growable: false)
        ..sort((a, b) {
          final byUserMessages = b.session.userMessageCount.compareTo(
            a.session.userMessageCount,
          );
          if (byUserMessages != 0) return byUserMessages;
          return b.session.lastMessageAt.compareTo(a.session.lastMessageAt);
        });
  if (repeated.isEmpty) return;

  final candidate = repeated.first;
  final title = _safeBody(candidate.session.title).isNotEmpty
      ? _safeBody(candidate.session.title)
      : '未命名会话';
  addInsight(
    '重复追问',
    '会话「$title」多次出现相近追问：${candidate.highlight}，说明同一问题可能反复未解。',
    priority: 'high',
  );
  addAction('下次打开「$title」时，先明确状态、阻塞点和下一步，再继续展开细节。');
}

void _reflectSessionFollowUpPressure(
  DreamingDigest digest,
  void Function(String category, String text, {String priority}) addInsight,
  void Function(String text) addAction,
) {
  final pressured =
      digest.sessions
          .where(
            (session) =>
                session.assistantMessageCount > 0 &&
                session.userMessageCount >= session.assistantMessageCount + 2,
          )
          .toList(growable: false)
        ..sort((a, b) {
          final byGap = (b.userMessageCount - b.assistantMessageCount)
              .compareTo(a.userMessageCount - a.assistantMessageCount);
          if (byGap != 0) return byGap;
          return b.messageCount.compareTo(a.messageCount);
        });
  if (pressured.isEmpty) return;

  final session = pressured.first;
  final title = _safeBody(session.title).isNotEmpty
      ? _safeBody(session.title)
      : '未命名会话';
  final gap = session.userMessageCount - session.assistantMessageCount;
  addInsight(
    '会话追问压力',
    '会话「$title」用户消息比助手回复多 $gap 条，可能存在多轮追问没有充分收束。',
    priority: 'high',
  );
  addAction('下次打开「$title」时，先给出阶段性总结，再逐项回应仍未解决的问题。');
}

void _reflectLatestUserTask(
  DreamingDigest digest,
  void Function(String category, String text, {String priority}) addInsight,
  void Function(String text) addAction,
) {
  final sessions =
      digest.sessions
          .where(
            (session) =>
                session.lastMessageRole == 'user' &&
                _safeBody(session.latestUserHighlight).isNotEmpty,
          )
          .toList(growable: false)
        ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
  for (final session in sessions) {
    final latest = _safeBody(session.latestUserHighlight);
    if (!_looksLikeActionableUserTask(latest)) continue;
    addInsight('最新任务推进', '用户最新明确任务：$latest', priority: 'high');
    addAction('下次对话优先推进这个最新任务：$latest');
    return;
  }
}

void _reflectConversationBalance(
  DreamingDigest digest,
  void Function(String category, String text, {String priority}) addInsight,
  void Function(String text) addAction,
) {
  if (digest.assistantMessageCount == 0) {
    addInsight('回应质量', '今天只有用户消息，没有助手回复记录。', priority: 'high');
    addAction('检查模型配置、网络状态或中断记录，确保用户问题能得到回复。');
    return;
  }
  if (digest.userMessageCount > digest.assistantMessageCount + 2) {
    addInsight('回应质量', '用户消息明显多于助手回复，可能存在未收口问题或多轮追问。', priority: 'high');
    addAction('下次打开相关会话时，优先补一个简短总结和未完成问题清单。');
    return;
  }
  addInsight('回应质量', '今日用户与助手轮次基本均衡，主聊天链路有连续回应。');
}

void _reflectDigestCompleteness(
  DreamingDigest digest,
  void Function(String category, String text, {String priority}) addInsight,
  void Function(String text) addAction,
) {
  if (!digest.isTruncated) return;
  final limit = digest.messageLimit > 0
      ? digest.messageLimit
      : digest.originalMessageCount;
  final total = digest.totalOriginalMessageCount > 0
      ? digest.totalOriginalMessageCount
      : digest.originalMessageCount;
  addInsight(
    '整理完整性',
    '来源 Dreaming 已达到本机整理上限，只覆盖最近 $limit / $total 条原始消息，后续画像和反思可能缺少当天较早线索。',
    priority: 'high',
  );
  addAction('先不要把本次 Dreaming 当作当天完整画像；需要继续分段整理或补跑更高上限后再确认长期记忆。');
}

void _reflectLongSessions(
  DreamingDigest digest,
  void Function(String category, String text, {String priority}) addInsight,
  void Function(String text) addAction,
) {
  final longSessions = digest.sessions
      .where((session) => session.messageCount >= 30)
      .toList(growable: false);
  if (longSessions.isEmpty) {
    addInsight('上下文', '今日没有超过 30 条消息的长会话，暂不触发长上下文风险。');
    return;
  }
  final totalMessages = longSessions.fold<int>(
    0,
    (total, session) => total + session.messageCount,
  );
  addInsight(
    '上下文',
    '发现 ${longSessions.length} 个长会话，共 $totalMessages 条消息，需要关注压缩质量和最新问题保留。',
    priority: 'high',
  );
  addAction('对长会话优先复查摘要、最近用户问题和模型上下文预算裁剪效果。');
}

void _reflectMemoryAndProfile(
  DreamingDigest digest,
  UserProfile? profile,
  int pendingProfileProposalCount,
  void Function(String category, String text, {String priority}) addInsight,
  void Function(String text) addAction,
) {
  if (digest.memoryCandidates.isEmpty) {
    addInsight('长期记忆', '今日没有新增记忆候选，画像不会自动增长。');
    addAction('如果用户表达了稳定偏好、目标或任务，后续应显式沉淀为 Key Points。');
  } else {
    addInsight(
      '长期记忆',
      '今日产生 ${digest.memoryCandidates.length} 条记忆候选，可用于后续个性化回复。',
    );
  }

  if (pendingProfileProposalCount > 0) {
    addInsight(
      '用户画像',
      '当前有 $pendingProfileProposalCount 条待确认画像变更，正式画像尚未吸收这些线索。',
      priority: 'high',
    );
    addAction('进入“用户画像 / 镜像数字人基础”逐项采纳或拒绝画像变更。');
  } else if (profile == null || !profile.hasContent) {
    addInsight('用户画像', '当前画像信号不足，数字孪生基础仍偏弱。');
    addAction('继续通过对话收集偏好、目标、表达风格和作息线索。');
  } else {
    addInsight('用户画像', '当前画像已有 ${profile.totalSignalCount} 个信号，可作为个性化回复基础。');
  }
}

void _reflectNextBestFollowUp(
  UserProfile? profile,
  DreamingDigest digest,
  void Function(String category, String text, {String priority}) addInsight,
  void Function(String text) addAction,
) {
  final task = _firstSafe(profile?.tasks ?? const []);
  if (task != null) {
    addInsight('任务推进', '画像中已有待跟进任务：$task', priority: 'high');
    addAction('下次对话优先询问或推进这项任务：$task');
    return;
  }

  final goal = _firstSafe(profile?.goals ?? const []);
  if (goal != null) {
    addInsight('目标推进', '画像中已有长期目标：$goal');
    addAction('围绕该目标给出下一步可执行建议：$goal');
    return;
  }

  final preference = _firstSafe(profile?.preferences ?? const []);
  if (preference != null) {
    addInsight('个性化', '回复时可优先尊重用户偏好：$preference');
    addAction('后续回复保持与该偏好一致：$preference');
    return;
  }

  final keyword = _firstSafe(digest.keywords);
  if (keyword != null) {
    addInsight('主题连续性', '今日高频主题包含：$keyword');
    addAction('下次会话可先回顾该主题的结论和未完成事项。');
  }
}

String? _firstSafe(List<String> values) {
  for (final value in values) {
    final safe = _safeBody(value);
    if (safe.isNotEmpty) return safe;
  }
  return null;
}

class _RepeatedIntentCandidate {
  const _RepeatedIntentCandidate({
    required this.session,
    required this.highlight,
  });

  final DreamingSessionDigest session;
  final String highlight;

  static _RepeatedIntentCandidate? fromSession(DreamingSessionDigest session) {
    final snippets = <String>[];
    for (final value in [...session.highlights, session.latestUserHighlight]) {
      final safe = _safeBody(value);
      if (safe.isEmpty || snippets.contains(safe)) continue;
      snippets.add(safe);
    }
    if (snippets.length < 2) return null;

    for (var i = 0; i < snippets.length; i++) {
      for (var j = i + 1; j < snippets.length; j++) {
        if (_looksLikeRepeatedIntent(snippets[i], snippets[j])) {
          return _RepeatedIntentCandidate(
            session: session,
            highlight: snippets[j],
          );
        }
      }
    }
    return null;
  }
}

bool _looksLikeRepeatedIntent(String left, String right) {
  final a = _normalizeIntentText(left);
  final b = _normalizeIntentText(right);
  if (a.length < 8 || b.length < 8) return false;
  if (a == b || a.contains(b) || b.contains(a)) return true;

  final aSet = a.runes.toSet();
  final bSet = b.runes.toSet();
  final intersection = aSet.intersection(bSet).length;
  final union = aSet.union(bSet).length;
  return union > 0 && intersection / union >= 0.72;
}

bool _looksLikeActionableUserTask(String value) {
  final normalized = _normalizeIntentText(value);
  if (normalized.length < 6) return false;
  const taskMarkers = [
    '继续推进',
    '请继续',
    '请帮',
    '帮我',
    '现在帮我',
    '修复',
    '验证',
    '复跑',
    '补',
    '实现',
    '看下',
    '检查',
  ];
  return taskMarkers.any((marker) => normalized.contains(marker));
}

String _normalizeIntentText(String value) {
  return value.toLowerCase().replaceAll(
    RegExp(r"[\s，。！？,.!?；;：:“”‘’'（）()\[\]【】、]+"),
    '',
  );
}

String _safeLabel(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return '其他';
  if (normalized.length > 24) return normalized.substring(0, 24);
  return normalized;
}

String _safePriority(String value) {
  switch (value) {
    case 'high':
    case 'normal':
    case 'low':
      return value;
    default:
      return 'normal';
  }
}

String _safeBody(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length < 2) return '';
  if (!isSafeUserProfileSignal(normalized)) return '';
  return normalized.length <= 180
      ? normalized
      : '${normalized.substring(0, 180)}…';
}
