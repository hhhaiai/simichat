import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const kStructuredDataArchivePath = 'structured_data/shared_preferences.json';
const kStructuredDataFormat = 'simichat.structured_preferences.v1';

const kStructuredPreferenceKeys = <String>{
  'key_point_memory_v1',
  'dreaming_digest_v1',
  'dreaming_schedule_v1',
  'user_profile_v1',
  'user_profile_controls_v1',
  'user_profile_history_v1',
  'user_profile_change_proposals_v1',
  'theme_mode',
  'compress_threshold',
  'font_scale',
  'semantic_search_enabled',
  'system_prompts',
};

class StructuredDataBackupService {
  const StructuredDataBackupService({DateTime Function()? now}) : _now = now;

  final DateTime Function()? _now;

  Future<List<int>?> exportSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, Object?>{};
    for (final key in kStructuredPreferenceKeys) {
      if (!prefs.containsKey(key)) continue;
      final value = prefs.get(key);
      final encoded = _encodePreferenceValue(value);
      if (encoded != null) values[key] = encoded;
    }
    if (values.isEmpty) return null;

    final payload = {
      'format': kStructuredDataFormat,
      'exported_at': (_now ?? DateTime.now)().toUtc().toIso8601String(),
      'privacy': {
        'contains_model_api_keys': false,
        'note': '仅导出白名单本地偏好、记忆、Dreaming 和用户画像数据，不导出模型渠道 API Key。',
      },
      'allowed_keys': kStructuredPreferenceKeys.toList()..sort(),
      'values': values,
    };
    return utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
  }

  StructuredDataBackupPreview previewSharedPreferences(List<int> bytes) {
    final decoded = _decodePayload(bytes);
    var supportedKeys = 0;
    var unsupportedKeys = 0;

    for (final entry in decoded.entries) {
      if (kStructuredPreferenceKeys.contains(entry.key) &&
          _canRestorePreferenceValue(entry.value)) {
        supportedKeys++;
      } else {
        unsupportedKeys++;
      }
    }

    return StructuredDataBackupPreview(
      supportedKeys: supportedKeys,
      unsupportedKeys: unsupportedKeys,
    );
  }

  Future<StructuredDataRestoreResult> restoreSharedPreferences(
    List<int> bytes, {
    bool overwriteExisting = false,
  }) async {
    final decoded = _decodePayload(bytes);
    final prefs = await SharedPreferences.getInstance();
    var restored = 0;
    var skippedExisting = 0;
    var skippedUnsupported = 0;

    for (final entry in decoded.entries) {
      final key = entry.key;
      if (!kStructuredPreferenceKeys.contains(key)) {
        skippedUnsupported++;
        continue;
      }
      if (!_canRestorePreferenceValue(entry.value)) {
        skippedUnsupported++;
        continue;
      }
      if (prefs.containsKey(key) && !overwriteExisting) {
        skippedExisting++;
        continue;
      }
      final ok = await _writePreferenceValue(prefs, key, entry.value);
      if (ok) {
        restored++;
      } else {
        skippedUnsupported++;
      }
    }

    return StructuredDataRestoreResult(
      restoredKeys: restored,
      skippedExistingKeys: skippedExisting,
      skippedUnsupportedKeys: skippedUnsupported,
    );
  }

  Future<bool> hasAnyStoredPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return kStructuredPreferenceKeys.any(prefs.containsKey);
  }
}

class StructuredDataBackupPreview {
  const StructuredDataBackupPreview({
    required this.supportedKeys,
    required this.unsupportedKeys,
  });

  final int supportedKeys;
  final int unsupportedKeys;
}

class StructuredDataRestoreResult {
  const StructuredDataRestoreResult({
    required this.restoredKeys,
    required this.skippedExistingKeys,
    required this.skippedUnsupportedKeys,
  });

  final int restoredKeys;
  final int skippedExistingKeys;
  final int skippedUnsupportedKeys;
}

Map<String, Object?>? _encodePreferenceValue(Object? value) {
  return switch (value) {
    String() => {'type': 'string', 'value': value},
    bool() => {'type': 'bool', 'value': value},
    int() => {'type': 'int', 'value': value},
    double() => {'type': 'double', 'value': value},
    List<String>() => {'type': 'stringList', 'value': value},
    _ => null,
  };
}

Map<String, Map<String, Object?>> _decodePayload(List<int> bytes) {
  try {
    final root = jsonDecode(utf8.decode(bytes));
    if (root is! Map<String, Object?> ||
        root['format'] != kStructuredDataFormat) {
      throw const FormatException('unsupported structured data format');
    }
    final rawValues = root['values'];
    if (rawValues is! Map) return const {};
    return rawValues.map((key, value) {
      if (key is! String || value is! Map) {
        throw const FormatException('invalid structured data value');
      }
      return MapEntry(key, value.cast<String, Object?>());
    });
  } catch (_) {
    throw const FormatException('structured data parse failed');
  }
}

bool _canRestorePreferenceValue(Map<String, Object?> encoded) {
  final type = encoded['type'];
  final value = encoded['value'];
  switch (type) {
    case 'string':
      return value is String;
    case 'bool':
      return value is bool;
    case 'int':
      return value is int;
    case 'double':
      return value is num;
    case 'stringList':
      return value is List && value.every((item) => item is String);
    default:
      return false;
  }
}

Future<bool> _writePreferenceValue(
  SharedPreferences prefs,
  String key,
  Map<String, Object?> encoded,
) async {
  final type = encoded['type'];
  final value = encoded['value'];
  switch (type) {
    case 'string':
      return value is String && await prefs.setString(key, value);
    case 'bool':
      return value is bool && await prefs.setBool(key, value);
    case 'int':
      return value is int && await prefs.setInt(key, value);
    case 'double':
      if (value is num) return prefs.setDouble(key, value.toDouble());
      return false;
    case 'stringList':
      if (value is List && value.every((item) => item is String)) {
        return prefs.setStringList(key, value.cast<String>());
      }
      return false;
    default:
      return false;
  }
}
