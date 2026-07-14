import 'dart:async';
import 'dart:convert';

import 'dreaming_service.dart';
import 'user_profile.dart';

const kModelUserProfileMaxPromptChars = 9000;
const kModelUserProfileMaxResponseChars = 16000;
const kModelUserProfileMaxAdditionalItems = 6;
const kModelUserProfileMaxAdditionalItemsPerSection = 2;
const kModelUserProfileTimeout = Duration(seconds: 60);

class ModelUserProfileFormatException implements Exception {
  const ModelUserProfileFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ModelUserProfileService {
  const ModelUserProfileService();

  String get systemPrompt => '''
你是 SimiChat 的用户画像候选增强器。你只能基于提供的 Dreaming / 本地候选证据，补充少量需要用户确认的画像候选。

只输出一个 JSON 对象，不要输出 Markdown、解释或代码围栏：
{"additions":[{"section":"preferences|goals|tasks|styleSignals|scheduleSignals|keywords","value":"候选内容","evidence":"原样引用一条提供的证据"}]}

约束：
- additions 最多 6 条，同一 section 最多 2 条；
- evidence 必须逐字引用输入中的一条证据，不能改写或虚构来源；
- 只能追加候选，不能删除、覆盖或修改已有画像；
- 禁止输出 profileFacts、conflicts 或任何基础身份事实；
- 不输出密钥、令牌、URL、本机路径或对话原文；
- 不诊断心理或健康状况，不推断疾病、职业、住址、身份或其他未明确给出的事实；
- 来源不足时返回 {"additions":[]}；
- 所有内容都只是待确认候选，不能声称已经修改正式画像。
''';

  String buildUserPrompt({
    required DreamingDigest digest,
    required UserProfile localCandidate,
  }) {
    final evidence = _evidenceValues(
      digest: digest,
      localCandidate: localCandidate,
    );
    final localSummary = jsonEncode({
      'preferences': localCandidate.preferences,
      'goals': localCandidate.goals,
      'tasks': localCandidate.tasks,
      'styleSignals': localCandidate.styleSignals,
      'scheduleSignals': localCandidate.scheduleSignals,
      'keywords': localCandidate.keywords,
    });
    final prompt =
        '''
## 本地规则画像候选
${_bounded(_redactPromptText(localSummary), 3600)}

## 只允许引用下列 Dreaming / 本地候选证据
${evidence.isEmpty ? '- 无可用证据' : evidence.map((item) => '- $item').join('\n')}

请只补充有逐字证据支撑、需要用户确认的新增候选；不要重复已有候选，只返回约定 JSON。
'''
            .trim();
    return _bounded(prompt, kModelUserProfileMaxPromptChars);
  }

  Future<String> collectResponse({
    required Stream<String> chunks,
    Duration timeout = kModelUserProfileTimeout,
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
        if (response.length > kModelUserProfileMaxResponseChars) {
          throw const ModelUserProfileFormatException('模型画像响应过长');
        }
      }
      return response.toString();
    }();
    return collection.timeout(
      timeout,
      onTimeout: () {
        onTimeout?.call();
        throw TimeoutException('模型画像超过总时限', timeout);
      },
    );
  }

  UserProfile enhanceFromResponse({
    required DreamingDigest digest,
    required UserProfile localCandidate,
    UserProfileControls controls = const UserProfileControls(),
    required String response,
  }) {
    if (response.length > kModelUserProfileMaxResponseChars) {
      throw const ModelUserProfileFormatException('模型画像响应过长');
    }
    final decoded = _decodeResponse(response);
    final rawAdditions = decoded['additions'];
    if (rawAdditions is! List) {
      throw const ModelUserProfileFormatException('模型画像缺少 additions');
    }

    final allowedEvidence = _evidenceValues(
      digest: digest,
      localCandidate: localCandidate,
    ).map(_evidenceKey).toSet();
    final additions = <String, List<String>>{};
    var acceptedCount = 0;

    for (final raw in rawAdditions.whereType<Map>()) {
      if (acceptedCount >= kModelUserProfileMaxAdditionalItems) break;
      final item = raw.cast<Object?, Object?>();
      final section = item['section'];
      final value = item['value'];
      final evidence = item['evidence'];
      if (section is! String ||
          !_allowedSections.contains(section) ||
          value is! String ||
          evidence is! String) {
        continue;
      }
      if (!_isSafeModelProfileText(value, keyword: section == 'keywords') ||
          !_isSafeModelProfileText(evidence) ||
          !allowedEvidence.contains(_evidenceKey(evidence))) {
        continue;
      }
      final controlled = controls.applyToSignal(value);
      if (controlled == null ||
          !_isSafeModelProfileText(
            controlled,
            keyword: section == 'keywords',
          )) {
        continue;
      }
      final currentValues = _sectionValues(localCandidate, section);
      final sectionAdditions = additions.putIfAbsent(section, () => <String>[]);
      if (sectionAdditions.length >=
          kModelUserProfileMaxAdditionalItemsPerSection) {
        continue;
      }
      if ([
        ...currentValues,
        ...sectionAdditions,
      ].any((item) => _sameValue(item, controlled))) {
        continue;
      }
      sectionAdditions.add(controlled.trim());
      acceptedCount += 1;
    }

    if (acceptedCount == 0) {
      throw const ModelUserProfileFormatException('模型画像没有新增可安全使用的候选');
    }

    final preferences = _mergedSection(
      localCandidate.preferences,
      additions['preferences'],
      12,
    );
    return localCandidate.copyWith(
      preferences: preferences,
      goals: _mergedSection(localCandidate.goals, additions['goals'], 12),
      tasks: _mergedSection(localCandidate.tasks, additions['tasks'], 12),
      styleSignals: _mergedSection(
        localCandidate.styleSignals,
        additions['styleSignals'],
        12,
      ),
      scheduleSignals: _mergedSection(
        localCandidate.scheduleSignals,
        additions['scheduleSignals'],
        12,
      ),
      keywords: _mergedSection(
        localCandidate.keywords,
        additions['keywords'],
        24,
      ),
      conflicts: detectUserProfileConflicts(preferences),
    );
  }

  Map<String, dynamic> _decodeResponse(String response) {
    final trimmed = response.trim();
    for (final candidate in _completeJsonObjects(trimmed)) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } on FormatException {
        continue;
      }
    }
    throw const ModelUserProfileFormatException('模型画像不是可解析的 JSON 对象');
  }
}

const _allowedSections = {
  'preferences',
  'goals',
  'tasks',
  'styleSignals',
  'scheduleSignals',
  'keywords',
};

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
      depth += 1;
    } else if (character == '}' && depth > 0) {
      depth -= 1;
      if (depth == 0 && start >= 0) {
        yield input.substring(start, index + 1);
        start = -1;
      }
    }
  }
}

List<String> _evidenceValues({
  required DreamingDigest digest,
  required UserProfile localCandidate,
}) {
  final values = <String>[
    ...localCandidate.preferences,
    ...localCandidate.goals,
    ...localCandidate.tasks,
    ...localCandidate.profileFacts,
    ...localCandidate.styleSignals,
    ...localCandidate.scheduleSignals,
    ...localCandidate.keywords,
    ...digest.memoryCandidates.map((item) => item.content),
    ...digest.sessions.expand((session) => session.highlights),
    ...digest.keywords,
  ];
  final result = <String>[];
  final seen = <String>{};
  for (final raw in values) {
    final value = _bounded(_redactPromptText(raw).trim(), 180);
    if (!_isSafeModelProfileText(value)) continue;
    if (!seen.add(_evidenceKey(value))) continue;
    result.add(value);
    if (result.length >= 40) break;
  }
  return List.unmodifiable(result);
}

List<String> _sectionValues(UserProfile profile, String section) {
  return switch (section) {
    'preferences' => profile.preferences,
    'goals' => profile.goals,
    'tasks' => profile.tasks,
    'styleSignals' => profile.styleSignals,
    'scheduleSignals' => profile.scheduleSignals,
    'keywords' => profile.keywords,
    _ => const [],
  };
}

List<String> _mergedSection(
  List<String> current,
  List<String>? additions,
  int maxItems,
) {
  if (additions == null || additions.isEmpty || current.length >= maxItems) {
    return current;
  }
  return List.unmodifiable([...current, ...additions].take(maxItems));
}

bool _sameValue(String left, String right) =>
    _evidenceKey(left) == _evidenceKey(right);

String _evidenceKey(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

bool _isSafeModelProfileText(String value, {bool keyword = false}) {
  final normalized = value.trim();
  if (normalized.length < 2 || normalized.length > (keyword ? 24 : 180)) {
    return false;
  }
  return isSafeUserProfileSignal(normalized) &&
      !_modelProfileUrlPattern.hasMatch(normalized) &&
      !_modelProfileLocalPathPattern.hasMatch(normalized) &&
      !_modelProfileDiagnosisPattern.hasMatch(normalized) &&
      !_modelProfilePlaceholderTexts.contains(normalized);
}

String _bounded(String value, int maxChars) {
  if (value.length <= maxChars) return value;
  return '${value.substring(0, maxChars - 1)}…';
}

String _redactPromptText(String value) {
  return value
      .replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9._~+\-/=]+', caseSensitive: false),
        '[敏感信息]',
      )
      .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]{8,}\b'), '[敏感信息]')
      .replaceAllMapped(
        RegExp(
          r'\b(api[_-]?key|token|secret|password)\s*[:=]\s*[^\s，。；;]+',
          caseSensitive: false,
        ),
        (match) => '[敏感信息]',
      )
      .replaceAll(_modelProfileUrlPattern, '[链接]')
      .replaceAll(_modelProfileLocalPathPattern, '[本机路径]');
}

const _modelProfilePlaceholderTexts = {
  '候选内容',
  '原样引用一条提供的证据',
  'preferences|goals|tasks|styleSignals|scheduleSignals|keywords',
};

final _modelProfileUrlPattern = RegExp(
  r'https?://[^\s，。；;]+',
  caseSensitive: false,
);
final _modelProfileLocalPathPattern = RegExp(
  r'(?:(?:/Users|/var|/private|/data|/storage|/sdcard|/home)/[^\s，。；;,)]+|[A-Za-z]:\\[^\s，。；;,)]+)',
);
final _modelProfileDiagnosisPattern = RegExp(
  r'(诊断|患有|抑郁症|焦虑症|双相|精神疾病|心理疾病|人格障碍|癌症|糖尿病|高血压|ADHD|自闭症)',
  caseSensitive: false,
);
