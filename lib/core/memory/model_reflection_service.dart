import 'dart:async';
import 'dart:convert';

import 'dreaming_service.dart';
import 'reflection_service.dart';
import 'user_profile.dart';

const kModelReflectionMaxPromptChars = 12000;
const kModelReflectionMaxResponseChars = 20000;
const kModelReflectionMaxAdditionalItems = 4;
const kModelReflectionTimeout = Duration(seconds: 60);

class ModelReflectionFormatException implements Exception {
  const ModelReflectionFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ModelReflectionService {
  const ModelReflectionService();

  String get systemPrompt => '''
你是 SimiChat 的反思增强器。你的任务是基于本地 Dreaming 摘要和已有本地规则反思，补充少量可执行、可验证、不过度推断的结论。

只输出一个 JSON 对象，不要输出 Markdown、解释或代码围栏：
{"insights":[{"category":"分类","text":"结论","priority":"high|normal|low"}],"actionItems":["下一步行动"]}

约束：
- insights 最多 4 条，actionItems 最多 4 条；
- priority 必须从 high、normal、low 中选择一个，不能输出 high|normal|low；
- category 和 text 必须写具体内容，不要照抄“分类”或“结论”；
- actionItems 至少 1 条，并且必须是具体、可执行的下一步；
- 不输出密钥、令牌、URL、本机路径或对话原文；
- 不诊断心理或健康状况，不虚构用户事实；
- 来源不完整时必须保持不确定性；
- 行动项必须能在下一轮对话或下一次验证中执行。
''';

  String buildUserPrompt({
    required DreamingDigest digest,
    required ReflectionReport localReport,
  }) {
    final digestMarkdown = _redactPromptText(digest.toMarkdown());
    final localMarkdown = _redactPromptText(localReport.toMarkdown());
    final prompt =
        '''
## Dreaming 摘要
${_bounded(digestMarkdown, 7600)}

## 本地规则反思
${_bounded(localMarkdown, 3600)}

请在不覆盖本地安全结论的前提下补充模型反思，只返回约定 JSON。
'''
            .trim();
    return _bounded(prompt, kModelReflectionMaxPromptChars);
  }

  Future<String> collectResponse({
    required Stream<String> chunks,
    Duration timeout = kModelReflectionTimeout,
    void Function()? onTimeout,
  }) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', '必须大于零');
    }
    final response = StringBuffer();
    final collection = () async {
      await for (final content in chunks) {
        if (content.isEmpty) continue;
        response.write(content);
        if (response.length > kModelReflectionMaxResponseChars) {
          throw const ModelReflectionFormatException('模型反思响应过长');
        }
      }
      return response.toString();
    }();
    return collection.timeout(
      timeout,
      onTimeout: () {
        onTimeout?.call();
        throw TimeoutException('模型反思超过总时限', timeout);
      },
    );
  }

  ReflectionReport enhanceFromResponse({
    required ReflectionReport localReport,
    required String response,
  }) {
    if (response.length > kModelReflectionMaxResponseChars) {
      throw const ModelReflectionFormatException('模型反思响应过长');
    }
    final decoded = _sanitizeModelResponse(_decodeResponse(response));
    final parsed = ReflectionReport.fromJson({
      ...localReport.toJson(),
      'generationMode': kReflectionGenerationModeModel,
      'insights': decoded['insights'],
      'actionItems': decoded['actionItems'],
    });
    if (parsed.insights.isEmpty && parsed.actionItems.isEmpty) {
      throw const ModelReflectionFormatException('模型反思没有可安全使用的内容');
    }

    var addedModelContent = false;
    final insightKeys = <String>{};
    final insights = <ReflectionInsight>[];
    for (final item in localReport.insights) {
      final key = '${item.category}\u0000${item.text}';
      if (insightKeys.add(key)) insights.add(item);
      if (insights.length == 8) break;
    }
    for (final item in parsed.insights.take(
      kModelReflectionMaxAdditionalItems,
    )) {
      if (insights.length == 8) break;
      final key = '${item.category}\u0000${item.text}';
      if (insightKeys.add(key)) {
        insights.add(item);
        addedModelContent = true;
      }
    }

    final actionItems = <String>[];
    for (final item in localReport.actionItems) {
      if (!actionItems.contains(item)) actionItems.add(item);
      if (actionItems.length == 8) break;
    }
    for (final item in parsed.actionItems.take(
      kModelReflectionMaxAdditionalItems,
    )) {
      if (actionItems.length == 8) break;
      if (!actionItems.contains(item)) {
        actionItems.add(item);
        addedModelContent = true;
      }
    }
    if (!addedModelContent) {
      throw const ModelReflectionFormatException('模型反思没有新增可安全使用的内容');
    }

    return ReflectionReport(
      dayKey: localReport.dayKey,
      generatedAt: localReport.generatedAt,
      sourceDigestDayKey: localReport.sourceDigestDayKey,
      sessionCount: localReport.sessionCount,
      originalMessageCount: localReport.originalMessageCount,
      userMessageCount: localReport.userMessageCount,
      assistantMessageCount: localReport.assistantMessageCount,
      pendingProfileProposalCount: localReport.pendingProfileProposalCount,
      sourceDigestIsTruncated: localReport.sourceDigestIsTruncated,
      sourceDigestMessageLimit: localReport.sourceDigestMessageLimit,
      sourceDigestTotalOriginalMessageCount:
          localReport.sourceDigestTotalOriginalMessageCount,
      generationMode: kReflectionGenerationModeModel,
      insights: List.unmodifiable(insights),
      actionItems: List.unmodifiable(actionItems),
    );
  }

  Map<String, dynamic> _decodeResponse(String response) {
    final trimmed = response.trim();
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0) {
      throw const ModelReflectionFormatException('模型反思不是 JSON 对象');
    }
    final candidates = <String>{..._completeJsonObjects(trimmed)};
    if (end > start) candidates.add(trimmed.substring(start, end + 1));
    final fullCandidate = trimmed.substring(start);
    if (fullCandidate.endsWith(']')) {
      candidates.add('$fullCandidate}');
    }
    if (RegExp(r'[)）】]$').hasMatch(fullCandidate)) {
      candidates.add(
        '${fullCandidate.substring(0, fullCandidate.length - 1)}}',
      );
    }
    for (final candidate in candidates) {
      final repaired = candidate
          .replaceFirstMapped(
            RegExp(r'"}(\s*\])$'),
            (match) => '"${match.group(1)!}\u007d',
          )
          .replaceFirstMapped(
            RegExp(r'"}(\s*\]\s*})$'),
            (match) => '"${match.group(1)!}',
          )
          .replaceAllMapped(RegExp(r',(\s*[}\]])'), (match) => match.group(1)!);
      for (final value in {candidate, repaired}) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is! Map) {
            throw const ModelReflectionFormatException('模型反思不是 JSON 对象');
          }
          return decoded.cast<String, dynamic>();
        } on FormatException {
          continue;
        }
      }
    }
    throw const ModelReflectionFormatException('模型反思 JSON 无法解析');
  }
}

Iterable<String> _completeJsonObjects(String input) sync* {
  var depth = 0;
  var start = -1;
  var inString = false;
  var escaping = false;

  for (var index = 0; index < input.length; index++) {
    final character = input[index];
    if (inString) {
      if (escaping) {
        escaping = false;
      } else if (character == '\\') {
        escaping = true;
      } else if (character == '"') {
        inString = false;
      }
      continue;
    }

    if (character == '"' && depth > 0) {
      inString = true;
    } else if (character == '{') {
      if (depth == 0) start = index;
      depth++;
    } else if (character == '}' && depth > 0) {
      depth--;
      if (depth == 0 && start >= 0) {
        yield input.substring(start, index + 1);
        start = -1;
      }
    }
  }
}

Map<String, dynamic> _sanitizeModelResponse(Map<String, dynamic> decoded) {
  final insights =
      (decoded['insights'] as List?)
          ?.whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .where(
            (item) =>
                _isSafeModelResponseText(item['category']) &&
                _isSafeModelResponseText(item['text']),
          )
          .map(
            (item) => {
              'category': item['category'],
              'text': item['text'],
              'priority': item['priority'],
            },
          )
          .toList(growable: false) ??
      const [];
  final actionItems =
      (decoded['actionItems'] as List?)
          ?.map(
            (item) => switch (item) {
              String value => value,
              Map value =>
                value['text'] ?? value['nextStep'] ?? value['nextAction'],
              _ => null,
            },
          )
          .whereType<String>()
          .where(_isSafeModelResponseText)
          .toList(growable: false) ??
      const [];
  return {'insights': insights, 'actionItems': actionItems};
}

bool _isSafeModelResponseText(Object? value) {
  if (value is! String) return false;
  final normalized = value.trim();
  return !_modelPlaceholderTexts.contains(normalized) &&
      isSafeUserProfileSignal(normalized) &&
      !_modelUrlPattern.hasMatch(normalized) &&
      !_modelLocalPathPattern.hasMatch(normalized);
}

const _modelPlaceholderTexts = {'分类', '结论', 'high|normal|low'};

String _bounded(String value, int maxChars) {
  if (value.length <= maxChars) return value;
  return '${value.substring(0, maxChars - 1)}…';
}

String _redactPromptText(String value) {
  return value
      .replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9._~+\-/=]+', caseSensitive: false),
        'Bearer ***',
      )
      .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]{8,}\b'), 'sk-***')
      .replaceAllMapped(
        RegExp(
          r'\b(api[_-]?key|token|secret|password)\s*[:=]\s*[^\s，。；;]+',
          caseSensitive: false,
        ),
        (match) => '${match.group(1)}=***',
      )
      .replaceAll(_modelUrlPattern, '[链接]')
      .replaceAll(_modelLocalPathPattern, '[本机路径]');
}

final _modelUrlPattern = RegExp(r'https?://[^\s，。；;]+', caseSensitive: false);
final _modelLocalPathPattern = RegExp(
  r'(?:(?:/Users|/var|/private|/data|/storage|/sdcard|/home)/[^\s，。；;,)]+|[A-Za-z]:\\[^\s，。；;,)]+)',
);
