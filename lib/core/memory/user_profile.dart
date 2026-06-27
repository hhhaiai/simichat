import 'dart:convert';

import 'dreaming_service.dart';
import 'key_point_memory.dart';

const kLocalUserProfileTitle = '本地用户画像（v1）';

const _kMaxProfileItemsPerSection = 12;
const _kMaxProfileKeywords = 24;

final _profileSecretLikePattern = RegExp(
  r'(api[_ -]?key|authorization|bearer\s+|password|passwd|secret|token|密钥|密码|sk-[A-Za-z0-9_-]{10,}|AIza[0-9A-Za-z_-]{20,}|xox[baprs]-)',
  caseSensitive: false,
);

final _profileWhitespacePattern = RegExp(r'\s+');

class UserProfile {
  const UserProfile({
    required this.updatedAt,
    required this.sourceCount,
    required this.preferences,
    required this.goals,
    required this.tasks,
    required this.profileFacts,
    required this.styleSignals,
    required this.scheduleSignals,
    required this.keywords,
    this.conflicts = const [],
    this.digestDayKey,
  });

  factory UserProfile.empty({DateTime? updatedAt}) {
    return UserProfile(
      updatedAt: updatedAt ?? DateTime.now(),
      sourceCount: 0,
      preferences: const [],
      goals: const [],
      tasks: const [],
      profileFacts: const [],
      styleSignals: const [],
      scheduleSignals: const [],
      keywords: const [],
      conflicts: const [],
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceCount: json['sourceCount'] as int? ?? 0,
      preferences: _readStringList(json['preferences']),
      goals: _readStringList(json['goals']),
      tasks: _readStringList(json['tasks']),
      profileFacts: _readStringList(json['profileFacts']),
      styleSignals: _readStringList(json['styleSignals']),
      scheduleSignals: _readStringList(json['scheduleSignals']),
      keywords: _readStringList(json['keywords']),
      conflicts: _readStringList(json['conflicts']),
      digestDayKey: json['digestDayKey'] as String?,
    );
  }

  final DateTime updatedAt;
  final int sourceCount;
  final List<String> preferences;
  final List<String> goals;
  final List<String> tasks;
  final List<String> profileFacts;
  final List<String> styleSignals;
  final List<String> scheduleSignals;
  final List<String> keywords;
  final List<String> conflicts;
  final String? digestDayKey;

  bool get hasContent =>
      preferences.isNotEmpty ||
      goals.isNotEmpty ||
      tasks.isNotEmpty ||
      profileFacts.isNotEmpty ||
      styleSignals.isNotEmpty ||
      scheduleSignals.isNotEmpty ||
      conflicts.isNotEmpty ||
      keywords.isNotEmpty;

  int get totalSignalCount =>
      preferences.length +
      goals.length +
      tasks.length +
      profileFacts.length +
      styleSignals.length +
      scheduleSignals.length;

  UserProfile copyWith({
    DateTime? updatedAt,
    int? sourceCount,
    List<String>? preferences,
    List<String>? goals,
    List<String>? tasks,
    List<String>? profileFacts,
    List<String>? styleSignals,
    List<String>? scheduleSignals,
    List<String>? keywords,
    List<String>? conflicts,
    String? digestDayKey,
  }) {
    return UserProfile(
      updatedAt: updatedAt ?? this.updatedAt,
      sourceCount: sourceCount ?? this.sourceCount,
      preferences: preferences ?? this.preferences,
      goals: goals ?? this.goals,
      tasks: tasks ?? this.tasks,
      profileFacts: profileFacts ?? this.profileFacts,
      styleSignals: styleSignals ?? this.styleSignals,
      scheduleSignals: scheduleSignals ?? this.scheduleSignals,
      keywords: keywords ?? this.keywords,
      conflicts: conflicts ?? this.conflicts,
      digestDayKey: digestDayKey ?? this.digestDayKey,
    );
  }

  Map<String, dynamic> toJson() => {
    'updatedAt': updatedAt.toIso8601String(),
    'sourceCount': sourceCount,
    'preferences': preferences,
    'goals': goals,
    'tasks': tasks,
    'profileFacts': profileFacts,
    'styleSignals': styleSignals,
    'scheduleSignals': scheduleSignals,
    'keywords': keywords,
    'conflicts': conflicts,
    if (digestDayKey != null) 'digestDayKey': digestDayKey,
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# $kLocalUserProfileTitle')
      ..writeln()
      ..writeln('- 更新时间：${updatedAt.toIso8601String()}')
      ..writeln('- 来源记忆数：$sourceCount')
      ..writeln('- 最近 Dreaming：${digestDayKey ?? '暂无'}')
      ..writeln();

    void section(String title, List<String> values) {
      buffer
        ..writeln('## $title')
        ..writeln();
      if (values.isEmpty) {
        buffer.writeln('- 暂无');
      } else {
        for (final value in values) {
          buffer.writeln('- $value');
        }
      }
      buffer.writeln();
    }

    section('偏好', preferences);
    section('目标', goals);
    section('任务', tasks);
    section('基础画像', profileFacts);
    section('表达风格', styleSignals);
    section('作息线索', scheduleSignals);
    section('冲突提示', conflicts);
    section('关键词', keywords);
    return buffer.toString();
  }
}

class UserProfileHistoryEntry {
  const UserProfileHistoryEntry({
    required this.id,
    required this.createdAt,
    required this.reason,
    required this.profile,
  });

  factory UserProfileHistoryEntry.fromJson(Map<String, dynamic> json) {
    return UserProfileHistoryEntry(
      id: (json['id'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reason: (json['reason'] as String?) ?? 'unknown',
      profile: UserProfile.fromJson(
        (json['profile'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  final String id;
  final DateTime createdAt;
  final String reason;
  final UserProfile profile;

  String get summary =>
      '${_historyReasonLabel(reason)} · ${profile.sourceCount} 条来源 · ${profile.totalSignalCount} 个信号';

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'reason': reason,
    'profile': profile.toJson(),
  };
}

class UserProfileDiffSection {
  const UserProfileDiffSection({
    required this.title,
    required this.added,
    required this.removed,
  });

  final String title;
  final List<String> added;
  final List<String> removed;

  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty;

  List<UserProfileChangeItem> get items => [
    for (final value in added)
      UserProfileChangeItem(
        sectionTitle: title,
        type: UserProfileChangeType.added,
        value: value,
      ),
    for (final value in removed)
      UserProfileChangeItem(
        sectionTitle: title,
        type: UserProfileChangeType.removed,
        value: value,
      ),
  ];

  String get summary => '新增 ${added.length} · 移除 ${removed.length}';
}

class UserProfileDiff {
  const UserProfileDiff({required this.sections});

  final List<UserProfileDiffSection> sections;

  Iterable<UserProfileDiffSection> get changedSections =>
      sections.where((section) => section.hasChanges);

  int get addedCount =>
      sections.fold(0, (total, section) => total + section.added.length);

  int get removedCount =>
      sections.fold(0, (total, section) => total + section.removed.length);

  bool get hasChanges => addedCount > 0 || removedCount > 0;

  List<UserProfileChangeItem> get items => [
    for (final section in sections) ...section.items,
  ];

  String get summary =>
      hasChanges ? '相对当前：新增 $addedCount · 移除 $removedCount' : '与当前画像一致';
}

enum UserProfileChangeType { added, removed }

class UserProfileChangeItem {
  const UserProfileChangeItem({
    required this.sectionTitle,
    required this.type,
    required this.value,
  });

  final String sectionTitle;
  final UserProfileChangeType type;
  final String value;

  String get label => type == UserProfileChangeType.added ? '新增' : '移除';

  String get signedValue =>
      '${type == UserProfileChangeType.added ? '+' : '-'} $value';
}

class UserProfileChangeProposal {
  const UserProfileChangeProposal({
    required this.id,
    required this.createdAt,
    required this.reason,
    required this.candidateProfile,
    this.baseProfile,
  });

  factory UserProfileChangeProposal.fromJson(Map<String, dynamic> json) {
    final base = json['baseProfile'];
    final candidate = json['candidateProfile'];
    return UserProfileChangeProposal(
      id: (json['id'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reason: (json['reason'] as String?) ?? 'unknown',
      baseProfile: base is Map
          ? UserProfile.fromJson(base.cast<String, dynamic>())
          : null,
      candidateProfile: UserProfile.fromJson(
        (candidate as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  final String id;
  final DateTime createdAt;
  final String reason;
  final UserProfile? baseProfile;
  final UserProfile candidateProfile;

  UserProfileChangeProposal copyWith({
    String? id,
    DateTime? createdAt,
    String? reason,
    UserProfile? baseProfile,
    UserProfile? candidateProfile,
  }) {
    return UserProfileChangeProposal(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      reason: reason ?? this.reason,
      baseProfile: baseProfile ?? this.baseProfile,
      candidateProfile: candidateProfile ?? this.candidateProfile,
    );
  }

  UserProfileDiff get diff =>
      diffUserProfiles(current: baseProfile, candidate: candidateProfile);

  bool get hasChanges => diff.hasChanges;

  String get summary =>
      '${_historyReasonLabel(reason)} · ${candidateProfile.sourceCount} 条来源 · ${diff.summary}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'reason': reason,
    if (baseProfile != null) 'baseProfile': baseProfile!.toJson(),
    'candidateProfile': candidateProfile.toJson(),
  };
}

class UserProfileControls {
  const UserProfileControls({
    this.hiddenSignals = const [],
    this.editedSignals = const {},
  });

  factory UserProfileControls.fromJson(Map<String, dynamic> json) {
    final hidden = _readStringList(json['hiddenSignals']);
    final edited = <String, String>{};
    final rawEdited = json['editedSignals'];
    if (rawEdited is Map) {
      for (final entry in rawEdited.entries) {
        final original = _normalizeProfileText(entry.key.toString());
        final editedValue = _normalizeProfileText(entry.value.toString());
        if (!_isSafeProfileText(original) || !_isSafeProfileText(editedValue)) {
          continue;
        }
        edited[original] = editedValue;
      }
    }
    return UserProfileControls(
      hiddenSignals: List.unmodifiable(hidden),
      editedSignals: Map.unmodifiable(edited),
    );
  }

  final List<String> hiddenSignals;
  final Map<String, String> editedSignals;

  bool get hasControls => hiddenSignals.isNotEmpty || editedSignals.isNotEmpty;

  int get hiddenCount => hiddenSignals.length;

  int get editedCount => editedSignals.length;

  Map<String, dynamic> toJson() => {
    'hiddenSignals': hiddenSignals,
    'editedSignals': editedSignals,
  };

  UserProfileControls hideSignal(String signal) {
    final normalized = _normalizeProfileText(signal);
    if (!_isSafeProfileText(normalized)) return this;
    final hidden = {...hiddenSignals, normalized};
    final edited = Map<String, String>.from(editedSignals)..remove(normalized);
    return UserProfileControls(
      hiddenSignals: List.unmodifiable(hidden),
      editedSignals: Map.unmodifiable(edited),
    );
  }

  UserProfileControls editSignal(String original, String edited) {
    final normalizedOriginal = _normalizeProfileText(original);
    final normalizedEdited = _normalizeProfileText(edited);
    if (!_isSafeProfileText(normalizedOriginal) ||
        !_isSafeProfileText(normalizedEdited)) {
      return this;
    }
    final hidden = hiddenSignals
        .where((item) => item != normalizedOriginal && item != normalizedEdited)
        .toList(growable: false);
    final edits = Map<String, String>.from(editedSignals)
      ..[normalizedOriginal] = normalizedEdited;
    return UserProfileControls(
      hiddenSignals: List.unmodifiable(hidden),
      editedSignals: Map.unmodifiable(edits),
    );
  }

  UserProfileControls clear() => const UserProfileControls();

  String? applyToSignal(String value) {
    var current = _normalizeProfileText(value);
    if (!_isSafeProfileText(current)) return null;
    final hidden = hiddenSignals.toSet();
    if (hidden.contains(current)) return null;
    final visited = <String>{};
    for (var i = 0; i < 8; i++) {
      if (!visited.add(current)) break;
      final next = editedSignals[current];
      if (next == null) break;
      final normalizedNext = _normalizeProfileText(next);
      if (!_isSafeProfileText(normalizedNext)) return null;
      current = normalizedNext;
      if (hidden.contains(current)) return null;
    }
    return current;
  }
}

class UserProfileBuilder {
  const UserProfileBuilder();

  UserProfile build({
    required List<KeyPointMemoryItem> keyPoints,
    DreamingDigest? digest,
    UserProfileControls controls = const UserProfileControls(),
    DateTime? now,
  }) {
    final updatedAt = now ?? DateTime.now();
    final allItems = <KeyPointMemoryItem>[
      ...keyPoints,
      if (digest != null) ...digest.memoryCandidates,
    ];

    final seen = <String>{};
    final safeItems = <KeyPointMemoryItem>[];
    for (final item in allItems) {
      final normalized = _normalizeProfileText(item.content);
      if (!_isSafeProfileText(normalized)) continue;
      final controlled = controls.applyToSignal(normalized);
      if (controlled == null) continue;
      if (!seen.add(controlled.toLowerCase())) continue;
      safeItems.add(item.copyWith(content: controlled));
    }

    safeItems.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final preferences = <String>[];
    final goals = <String>[];
    final tasks = <String>[];
    final profileFacts = <String>[];
    final styleSignals = <String>[];
    final scheduleSignals = <String>[];
    final keywords = <String>{};

    if (digest != null) {
      for (final keyword in digest.keywords) {
        final normalizedKeyword = _normalizeKeyword(keyword);
        if (normalizedKeyword != null) keywords.add(normalizedKeyword);
      }
    }

    void addLimited(List<String> target, String value) {
      final clipped = _clipProfileText(value);
      if (clipped.isEmpty) return;
      if (target.contains(clipped)) return;
      if (target.length >= _kMaxProfileItemsPerSection) return;
      target.add(clipped);
    }

    for (final item in safeItems) {
      final content = item.content;
      switch (item.category) {
        case 'preference':
          addLimited(preferences, content);
          break;
        case 'goal':
          addLimited(goals, content);
          break;
        case 'task':
          addLimited(tasks, content);
          break;
        case 'profile':
          addLimited(profileFacts, content);
          break;
        default:
          if (_looksLikeGoal(content)) {
            addLimited(goals, content);
          } else if (_looksLikeTask(content)) {
            addLimited(tasks, content);
          } else if (_looksLikeProfileFact(content)) {
            addLimited(profileFacts, content);
          } else {
            addLimited(preferences, content);
          }
      }

      if (_looksLikeStyleSignal(content)) {
        addLimited(styleSignals, content);
      }
      if (_looksLikeScheduleSignal(content)) {
        addLimited(scheduleSignals, content);
      }

      for (final keyword in item.keywords) {
        final normalizedKeyword = _normalizeKeyword(keyword);
        if (normalizedKeyword != null) keywords.add(normalizedKeyword);
      }
      for (final keyword in extractMemoryKeywords(content)) {
        final normalizedKeyword = _normalizeKeyword(keyword);
        if (normalizedKeyword != null) keywords.add(normalizedKeyword);
      }
    }

    return UserProfile(
      updatedAt: updatedAt,
      sourceCount: safeItems.length,
      preferences: List.unmodifiable(preferences),
      goals: List.unmodifiable(goals),
      tasks: List.unmodifiable(tasks),
      profileFacts: List.unmodifiable(profileFacts),
      styleSignals: List.unmodifiable(styleSignals),
      scheduleSignals: List.unmodifiable(scheduleSignals),
      keywords: List.unmodifiable(keywords.take(_kMaxProfileKeywords)),
      conflicts: List.unmodifiable(_detectProfileConflicts(preferences)),
      digestDayKey: digest?.dayKey,
    );
  }
}

List<UserProfile> decodeUserProfiles(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .whereType<Map>()
        .map((item) => UserProfile.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

UserProfile? decodeUserProfile(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw) as Map;
    return UserProfile.fromJson(decoded.cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

String encodeUserProfile(UserProfile profile) => jsonEncode(profile.toJson());

UserProfileDiff diffUserProfiles({
  UserProfile? current,
  required UserProfile candidate,
}) {
  return UserProfileDiff(
    sections: [
      _diffProfileSection(
        '偏好',
        current?.preferences ?? const [],
        candidate.preferences,
      ),
      _diffProfileSection('目标', current?.goals ?? const [], candidate.goals),
      _diffProfileSection('任务', current?.tasks ?? const [], candidate.tasks),
      _diffProfileSection(
        '基础画像',
        current?.profileFacts ?? const [],
        candidate.profileFacts,
      ),
      _diffProfileSection(
        '表达风格',
        current?.styleSignals ?? const [],
        candidate.styleSignals,
      ),
      _diffProfileSection(
        '作息线索',
        current?.scheduleSignals ?? const [],
        candidate.scheduleSignals,
      ),
      _diffProfileSection(
        '冲突提示',
        current?.conflicts ?? const [],
        candidate.conflicts,
      ),
      _diffProfileSection(
        '关键词',
        current?.keywords ?? const [],
        candidate.keywords,
      ),
    ],
  );
}

UserProfile applyUserProfileChangeItem(
  UserProfile profile,
  UserProfileChangeItem item,
) {
  final values = _profileSectionValues(profile, item.sectionTitle);
  final next = item.type == UserProfileChangeType.added
      ? _addProfileSectionValue(values, item.value)
      : _removeProfileSectionValue(values, item.value);
  return _copyProfileSection(profile, item.sectionTitle, next);
}

UserProfile discardUserProfileChangeItem(
  UserProfile candidateProfile,
  UserProfileChangeItem item,
) {
  final values = _profileSectionValues(candidateProfile, item.sectionTitle);
  final next = item.type == UserProfileChangeType.added
      ? _removeProfileSectionValue(values, item.value)
      : _addProfileSectionValue(values, item.value);
  return _copyProfileSection(candidateProfile, item.sectionTitle, next);
}

List<UserProfileChangeProposal> decodeUserProfileChangeProposals(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .whereType<Map>()
        .map(
          (item) =>
              UserProfileChangeProposal.fromJson(item.cast<String, dynamic>()),
        )
        .where((item) => item.id.isNotEmpty && item.candidateProfile.hasContent)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

String encodeUserProfileChangeProposals(
  List<UserProfileChangeProposal> proposals,
) => jsonEncode(proposals.map((proposal) => proposal.toJson()).toList());

List<UserProfileHistoryEntry> decodeUserProfileHistory(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .whereType<Map>()
        .map(
          (item) =>
              UserProfileHistoryEntry.fromJson(item.cast<String, dynamic>()),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

String encodeUserProfileHistory(List<UserProfileHistoryEntry> entries) =>
    jsonEncode(entries.map((entry) => entry.toJson()).toList());

UserProfileControls decodeUserProfileControls(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const UserProfileControls();
  try {
    final decoded = jsonDecode(raw) as Map;
    return UserProfileControls.fromJson(decoded.cast<String, dynamic>());
  } catch (_) {
    return const UserProfileControls();
  }
}

String encodeUserProfileControls(UserProfileControls controls) =>
    jsonEncode(controls.toJson());

bool isSafeUserProfileSignal(String value) {
  return _isSafeProfileText(_normalizeProfileText(value));
}

UserProfileDiffSection _diffProfileSection(
  String title,
  List<String> current,
  List<String> candidate,
) {
  final currentKeys = current
      .map((item) => _normalizeProfileText(item).toLowerCase())
      .toSet();
  final candidateKeys = candidate
      .map((item) => _normalizeProfileText(item).toLowerCase())
      .toSet();
  return UserProfileDiffSection(
    title: title,
    added: List.unmodifiable(
      candidate.where(
        (item) =>
            !currentKeys.contains(_normalizeProfileText(item).toLowerCase()),
      ),
    ),
    removed: List.unmodifiable(
      current.where(
        (item) =>
            !candidateKeys.contains(_normalizeProfileText(item).toLowerCase()),
      ),
    ),
  );
}

List<String> _profileSectionValues(UserProfile profile, String title) {
  switch (title) {
    case '偏好':
      return profile.preferences;
    case '目标':
      return profile.goals;
    case '任务':
      return profile.tasks;
    case '基础画像':
      return profile.profileFacts;
    case '表达风格':
      return profile.styleSignals;
    case '作息线索':
      return profile.scheduleSignals;
    case '冲突提示':
      return profile.conflicts;
    case '关键词':
      return profile.keywords;
    default:
      return const [];
  }
}

UserProfile _copyProfileSection(
  UserProfile profile,
  String title,
  List<String> values,
) {
  final safeValues = values
      .map(_normalizeProfileText)
      .where(_isSafeProfileText)
      .toList(growable: false);
  switch (title) {
    case '偏好':
      return profile.copyWith(preferences: safeValues);
    case '目标':
      return profile.copyWith(goals: safeValues);
    case '任务':
      return profile.copyWith(tasks: safeValues);
    case '基础画像':
      return profile.copyWith(profileFacts: safeValues);
    case '表达风格':
      return profile.copyWith(styleSignals: safeValues);
    case '作息线索':
      return profile.copyWith(scheduleSignals: safeValues);
    case '冲突提示':
      return profile.copyWith(conflicts: safeValues);
    case '关键词':
      return profile.copyWith(keywords: safeValues);
    default:
      return profile;
  }
}

List<String> _addProfileSectionValue(List<String> values, String value) {
  final normalized = _normalizeProfileText(value);
  if (!_isSafeProfileText(normalized)) return values;
  if (values.any((item) => _sameProfileValue(item, normalized))) return values;
  return List.unmodifiable([...values, normalized]);
}

List<String> _removeProfileSectionValue(List<String> values, String value) {
  final normalized = _normalizeProfileText(value);
  return List.unmodifiable(
    values.where((item) => !_sameProfileValue(item, normalized)),
  );
}

bool _sameProfileValue(String a, String b) {
  return _normalizeProfileText(a).toLowerCase() ==
      _normalizeProfileText(b).toLowerCase();
}

List<String> _readStringList(Object? raw) {
  return (raw as List?)
          ?.whereType<String>()
          .map(_normalizeProfileText)
          .where(_isSafeProfileText)
          .toList(growable: false) ??
      const [];
}

String _normalizeProfileText(String value) {
  return value.trim().replaceAll(_profileWhitespacePattern, ' ');
}

String _clipProfileText(String value) {
  final normalized = _normalizeProfileText(value);
  if (!_isSafeProfileText(normalized)) return '';
  return normalized.length <= 140
      ? normalized
      : '${normalized.substring(0, 140)}…';
}

bool _isSafeProfileText(String value) {
  if (value.length < 2 || value.length > 320) return false;
  return !_profileSecretLikePattern.hasMatch(value);
}

String? _normalizeKeyword(String value) {
  final keyword = _normalizeProfileText(value).toLowerCase();
  if (keyword.length < 2 || keyword.length > 24) return null;
  if (_profileSecretLikePattern.hasMatch(keyword)) return null;
  const blocked = {'todo', 'the', 'and', 'for', 'with', 'this', 'that'};
  if (blocked.contains(keyword)) return null;
  return keyword;
}

bool _looksLikeStyleSignal(String value) {
  final lower = value.toLowerCase();
  return value.contains('风格') ||
      value.contains('语气') ||
      value.contains('表达') ||
      value.contains('中文') ||
      value.contains('英文') ||
      value.contains('简洁') ||
      value.contains('详细') ||
      value.contains('结构化') ||
      value.contains('代码') ||
      value.contains('Markdown') ||
      lower.contains('style');
}

bool _looksLikeScheduleSignal(String value) {
  return value.contains('作息') ||
      value.contains('早上') ||
      value.contains('上午') ||
      value.contains('中午') ||
      value.contains('下午') ||
      value.contains('晚上') ||
      value.contains('夜间') ||
      value.contains('熬夜') ||
      value.contains('睡') ||
      value.contains('起床') ||
      RegExp(r'\d{1,2}\s*[点:]').hasMatch(value);
}

bool _looksLikeGoal(String value) {
  return value.contains('目标') ||
      value.contains('计划') ||
      value.contains('打算') ||
      value.contains('希望');
}

bool _looksLikeTask(String value) {
  final lower = value.toLowerCase();
  return lower.contains('todo') || value.contains('任务') || value.contains('提醒');
}

bool _looksLikeProfileFact(String value) {
  return value.contains('我是') ||
      value.contains('我叫') ||
      value.contains('我的') ||
      value.contains('住在') ||
      value.contains('工作');
}

List<String> _detectProfileConflicts(List<String> preferences) {
  final positives = preferences.where(_isPositivePreference).toList();
  final negatives = preferences.where(_isNegativePreference).toList();
  if (positives.isEmpty || negatives.isEmpty) return const [];

  final conflicts = <String>[];
  final seen = <String>{};
  for (final positive in positives) {
    final positiveKeywords = _conflictKeywords(positive);
    if (positiveKeywords.isEmpty) continue;
    for (final negative in negatives) {
      final overlap = positiveKeywords.intersection(
        _conflictKeywords(negative),
      );
      if (overlap.isEmpty) continue;
      final key = '$positive::$negative';
      if (!seen.add(key)) continue;
      final overlapPreview = overlap.take(3).join('、');
      conflicts.add('可能冲突：$positive ↔ $negative（共同线索：$overlapPreview）');
      if (conflicts.length >= 8) return conflicts;
    }
  }
  return conflicts;
}

bool _isPositivePreference(String value) {
  if (_isNegativePreference(value)) return false;
  return value.contains('喜欢') || value.contains('偏好') || value.contains('希望');
}

bool _isNegativePreference(String value) {
  return value.contains('不喜欢') ||
      value.contains('不要') ||
      value.contains('讨厌') ||
      value.contains('避免');
}

Set<String> _conflictKeywords(String value) {
  const blocked = {
    '我喜',
    '喜欢',
    '不喜',
    '不喜欢',
    '偏好',
    '不要',
    '讨厌',
    '避免',
    '希望',
    '我的',
    '请记',
    '记住',
  };
  return extractMemoryKeywords(value)
      .map(_normalizeProfileText)
      .where((keyword) => keyword.length >= 2)
      .where((keyword) => !blocked.contains(keyword))
      .toSet();
}

String _historyReasonLabel(String reason) {
  switch (reason) {
    case 'dreaming':
      return 'Dreaming 后重建';
    case 'manual_rebuild':
      return '手动重建';
    case 'edit_signal':
      return '编辑画像';
    case 'hide_signal':
      return '删除画像';
    case 'clear_controls':
      return '清除控制后重建';
    case 'restore_history':
      return '恢复历史版本';
    case 'profile_proposal':
      return '待确认画像变更';
    case 'accept_proposal':
      return '采纳画像变更';
    case 'accept_proposal_item':
      return '采纳单条画像变更';
    default:
      return '画像重建';
  }
}
