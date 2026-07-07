import 'dart:convert';
import 'dart:math';

const kKeyPointMemoryPromptTitle = '用户核心记忆（本地提取）';

final _secretLikePattern = RegExp(
  r'(api[_ -]?key|authorization|bearer\s+|password|passwd|secret|token|密钥|密码|sk-[A-Za-z0-9_-]{10,}|AIza[0-9A-Za-z_-]{20,}|xox[baprs]-)',
  caseSensitive: false,
);

final _whitespacePattern = RegExp(r'\s+');

const _semanticAliasGroups = [
  ['移动端', '手机端', '手机', '小屏', '移动应用'],
  ['本地', '本机', '离线', '隐私', '不上云'],
  ['dreaming', '夜间整理', '夜间', '整理', '总结'],
  ['数字孪生', '镜像数字人', '数字人', '画像', '代理思维'],
  ['语音', '转写', '语音转文字', 'stt'],
  ['图片', '多模态', '视觉', '图像'],
  ['模型', '渠道', '厂商', '供应商', 'api'],
  ['技能', 'skills', '插件', '市场'],
  ['提醒', '日历', '闹钟', '定时任务'],
];

class KeyPointMemoryItem {
  const KeyPointMemoryItem({
    required this.id,
    required this.sessionId,
    required this.sourceMessageId,
    required this.category,
    required this.content,
    required this.keywords,
    required this.confidence,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
  });

  final String id;
  final String sessionId;
  final String sourceMessageId;
  final String category;
  final String content;
  final List<String> keywords;
  final double confidence;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'sourceMessageId': sourceMessageId,
    'category': category,
    'content': content,
    'keywords': keywords,
    'confidence': confidence,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
  };

  factory KeyPointMemoryItem.fromJson(Map<String, dynamic> json) {
    return KeyPointMemoryItem(
      id: (json['id'] as String?) ?? '',
      sessionId: (json['sessionId'] as String?) ?? '',
      sourceMessageId: (json['sourceMessageId'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'note',
      content: (json['content'] as String?) ?? '',
      keywords:
          (json['keywords'] as List?)
              ?.whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList() ??
          const [],
      confidence: ((json['confidence'] as num?) ?? 0.5).toDouble(),
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastUsedAt: DateTime.tryParse((json['lastUsedAt'] as String?) ?? ''),
    );
  }

  KeyPointMemoryItem copyWith({
    String? id,
    String? sessionId,
    String? sourceMessageId,
    String? category,
    String? content,
    List<String>? keywords,
    double? confidence,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
  }) {
    return KeyPointMemoryItem(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      category: category ?? this.category,
      content: content ?? this.content,
      keywords: keywords ?? this.keywords,
      confidence: confidence ?? this.confidence,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }
}

class KeyPointExtractor {
  const KeyPointExtractor();

  List<KeyPointMemoryItem> extractFromUserMessage({
    required String sessionId,
    required String sourceMessageId,
    required String content,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final sentences = _splitSentences(content);
    final items = <KeyPointMemoryItem>[];
    final seen = <String>{};

    for (final sentence in sentences) {
      final normalized = normalizeMemoryContent(sentence);
      if (!_shouldRemember(normalized)) continue;
      if (seen.contains(normalized)) continue;
      seen.add(normalized);

      final keywords = extractMemoryKeywords(normalized);
      if (keywords.isEmpty) continue;

      final category = classifyMemoryCategory(normalized);
      items.add(
        KeyPointMemoryItem(
          id: makeMemoryItemId(sessionId, normalized),
          sessionId: sessionId,
          sourceMessageId: sourceMessageId,
          category: category,
          content: normalized,
          keywords: keywords,
          confidence: _confidenceFor(normalized, category),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
    }

    return items;
  }

  bool _shouldRemember(String value) {
    if (value.length < 4 || value.length > 240) return false;
    if (_secretLikePattern.hasMatch(value)) return false;
    final lower = value.toLowerCase();
    return lower.contains('记住') ||
        lower.contains('remember') ||
        value.contains('以后') ||
        value.contains('下次') ||
        value.contains('我喜欢') ||
        value.contains('我不喜欢') ||
        value.contains('偏好') ||
        value.contains('习惯') ||
        value.contains('作息') ||
        value.contains('我是') ||
        value.contains('我叫') ||
        value.contains('我的') ||
        value.contains('目标') ||
        value.contains('计划') ||
        value.contains('打算') ||
        value.contains('希望') ||
        _looksLikeActionableMemoryTask(value) ||
        lower.contains('todo');
  }

  double _confidenceFor(String value, String category) {
    var score = category == 'note' ? 0.56 : 0.72;
    if (value.contains('记住') || value.toLowerCase().contains('remember')) {
      score += 0.16;
    }
    if (value.contains('以后') || value.contains('下次')) score += 0.08;
    return min(score, 0.96);
  }
}

abstract class KeyPointMemoryStore {
  Future<List<KeyPointMemoryItem>> load();
  Future<List<KeyPointMemoryItem>> rememberAll(List<KeyPointMemoryItem> items);
  Future<List<KeyPointMemoryItem>> searchRelevant(
    String query, {
    String? sessionId,
    int limit = 8,
  });
}

List<KeyPointMemoryItem> decodeKeyPointMemoryItems(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .whereType<Map>()
        .map(
          (item) => KeyPointMemoryItem.fromJson(item.cast<String, dynamic>()),
        )
        .where((item) => item.id.isNotEmpty && item.content.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

String encodeKeyPointMemoryItems(List<KeyPointMemoryItem> items) {
  return jsonEncode(items.map((item) => item.toJson()).toList());
}

String normalizeMemoryContent(String value) {
  return value.trim().replaceAll(_whitespacePattern, ' ');
}

String makeMemoryItemId(String sessionId, String content) {
  final normalized = normalizeMemoryContent(content).toLowerCase();
  final hash = normalized.codeUnits.fold<int>(
    0x811c9dc5,
    (previous, unit) => ((previous ^ unit) * 0x01000193) & 0xffffffff,
  );
  return '${sessionId.isEmpty ? "global" : sessionId}-$hash';
}

String classifyMemoryCategory(String value) {
  final lower = value.toLowerCase();
  if (value.contains('喜欢') ||
      value.contains('不喜欢') ||
      value.contains('偏好') ||
      value.contains('习惯') ||
      value.contains('作息') ||
      value.contains('风格') ||
      value.contains('以后') ||
      value.contains('下次')) {
    return 'preference';
  }
  if (value.contains('我是') ||
      value.contains('我叫') ||
      value.contains('我的') ||
      value.contains('住在') ||
      value.contains('工作')) {
    return 'profile';
  }
  if (value.contains('目标') ||
      value.contains('计划') ||
      value.contains('打算') ||
      value.contains('希望')) {
    return 'goal';
  }
  if (lower.contains('todo') ||
      value.contains('任务') ||
      value.contains('提醒') ||
      _looksLikeActionableMemoryTask(value)) {
    return 'task';
  }
  return 'note';
}

bool _looksLikeActionableMemoryTask(String value) {
  final normalized = value.toLowerCase().replaceAll(
    RegExp(r"[\s，。！？,.!?；;：:“”‘’'（）()\[\]【】、]+"),
    '',
  );
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

List<String> extractMemoryKeywords(String value) {
  final normalized = normalizeMemoryContent(value).toLowerCase();
  final keywords = <String>{};

  for (final match in RegExp(r'[a-z0-9_+-]{2,}').allMatches(normalized)) {
    final token = match.group(0);
    if (token != null && !_isStopWord(token)) keywords.add(token);
  }

  for (final match in RegExp(r'[\u4e00-\u9fa5]{2,12}').allMatches(normalized)) {
    final token = match.group(0);
    if (token == null) continue;
    keywords.add(token);
    if (token.length > 4) {
      for (var i = 0; i <= token.length - 2 && i < 8; i++) {
        keywords.add(token.substring(i, i + 2));
      }
    }
  }

  return keywords.take(16).toList(growable: false);
}

List<KeyPointMemoryItem> rankRelevantKeyPoints(
  List<KeyPointMemoryItem> items,
  String query, {
  String? sessionId,
  int limit = 8,
  DateTime? now,
}) {
  final queryKeywords = extractMemoryKeywords(query);
  if (queryKeywords.isEmpty) return const [];
  final querySet = queryKeywords.toSet();
  final queryVector = buildLocalSemanticVector(query);
  final scored = <({KeyPointMemoryItem item, double score})>[];

  for (final item in items) {
    if (item.content.isEmpty) continue;
    final itemKeywords = item.keywords.toSet();
    final overlap = itemKeywords.intersection(querySet).length;
    final semanticScore = cosineSimilarity(
      queryVector,
      buildLocalSemanticVector(
        item.keywords.isEmpty
            ? item.content
            : '${item.content} ${item.keywords.join(' ')}',
      ),
    );
    var score = overlap * 2.0 + semanticScore * 3.0 + item.confidence;
    if (sessionId != null && item.sessionId == sessionId) score += 0.75;
    if (item.lastUsedAt != null) score += 0.1;
    if (overlap == 0 && semanticScore < 0.18 && !item.content.contains(query)) {
      score -= 1.25;
    }
    if (score > 0.95) scored.add((item: item, score: score));
  }

  scored.sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;
    return b.item.updatedAt.compareTo(a.item.updatedAt);
  });
  return scored.map((entry) => entry.item).take(limit).toList(growable: false);
}

Map<String, double> buildLocalSemanticVector(String value) {
  final terms = _semanticTerms(value);
  if (terms.isEmpty) return const {};
  final vector = <String, double>{};
  for (final term in terms) {
    vector[term] = (vector[term] ?? 0) + 1;
  }
  final norm = sqrt(vector.values.fold<double>(0, (sum, v) => sum + v * v));
  if (norm == 0) return const {};
  return {for (final entry in vector.entries) entry.key: entry.value / norm};
}

double cosineSimilarity(Map<String, double> a, Map<String, double> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final smaller = a.length <= b.length ? a : b;
  final larger = identical(smaller, a) ? b : a;
  var sum = 0.0;
  for (final entry in smaller.entries) {
    final other = larger[entry.key];
    if (other != null) sum += entry.value * other;
  }
  return sum;
}

String? buildKeyPointMemorySystemPrompt(List<KeyPointMemoryItem> items) {
  if (items.isEmpty) return null;
  final buffer = StringBuffer()
    ..writeln('## $kKeyPointMemoryPromptTitle')
    ..writeln('以下内容来自本机历史对话提取，仅作为个性化参考；若与用户当前明确表达冲突，以当前表达为准。');
  for (final item in items.take(8)) {
    final safeContent = normalizeMemoryContent(item.content);
    if (safeContent.isEmpty || _secretLikePattern.hasMatch(safeContent)) {
      continue;
    }
    final clipped = safeContent.length <= 140
        ? safeContent
        : '${safeContent.substring(0, 140)}…';
    buffer.writeln('- [${_categoryLabel(item.category)}] $clipped');
  }
  final prompt = buffer.toString().trim();
  return prompt.contains('- [') ? prompt : null;
}

List<String> _semanticTerms(String value) {
  final normalized = normalizeMemoryContent(value).toLowerCase();
  final terms = <String>{...extractMemoryKeywords(normalized)};

  for (final group in _semanticAliasGroups) {
    final matched = group.any((alias) => normalized.contains(alias));
    if (!matched) continue;
    for (final alias in group) {
      terms.add(alias.toLowerCase());
    }
  }

  for (final match in RegExp(r'[\u4e00-\u9fa5]{2,12}').allMatches(normalized)) {
    final token = match.group(0);
    if (token == null) continue;
    for (var size = 2; size <= 3; size++) {
      if (token.length < size) continue;
      for (var i = 0; i <= token.length - size && i < 10; i++) {
        terms.add(token.substring(i, i + size));
      }
    }
  }

  for (final match in RegExp(r'[a-z0-9_+-]{2,}').allMatches(normalized)) {
    final token = match.group(0);
    if (token != null && !_isStopWord(token)) terms.add(token);
  }

  return terms.toList(growable: false);
}

List<String> _splitSentences(String content) {
  return content
      .split(RegExp(r'[\n。！？!?；;]+'))
      .map(normalizeMemoryContent)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String _categoryLabel(String category) {
  switch (category) {
    case 'preference':
      return '偏好';
    case 'profile':
      return '画像';
    case 'goal':
      return '目标';
    case 'task':
      return '任务';
    default:
      return '备注';
  }
}

bool _isStopWord(String value) {
  const stopWords = {
    'the',
    'and',
    'for',
    'with',
    'this',
    'that',
    'you',
    'are',
    'todo',
  };
  return stopWords.contains(value);
}
