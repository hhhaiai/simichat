import 'dart:convert';
import 'dart:io';

const _maxConfigBytes = 8 * 1024;
const _ownerReadOnly = 0x100;
const _ownerReadWrite = 0x180;
const _permissionMask = 0x1ff;

class ModelReflectionLiveConfig {
  const ModelReflectionLiveConfig({
    required this.protocol,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  factory ModelReflectionLiveConfig.fromJson(Map<String, dynamic> json) {
    final protocol = _requiredString(json, 'protocol', maxLength: 64);
    if (protocol != 'openai_chat') {
      throw const FormatException(
        'Live Reflection quality only accepts remote openai_chat',
      );
    }

    final baseUrl = _requiredString(json, 'baseUrl', maxLength: 2048);
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        _isLoopbackHost(uri.host)) {
      throw const FormatException(
        'Live Reflection quality requires a remote HTTP(S) baseUrl',
      );
    }

    return ModelReflectionLiveConfig(
      protocol: protocol,
      baseUrl: baseUrl.replaceFirst(RegExp(r'/+$'), ''),
      apiKey: _requiredString(json, 'apiKey', maxLength: 4096),
      model: _requiredString(json, 'model', maxLength: 256),
    );
  }

  final String protocol;
  final String baseUrl;
  final String apiKey;
  final String model;
}

Future<ModelReflectionLiveConfig> loadModelReflectionLiveConfig(
  File file,
) async {
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) {
    throw FileSystemException(
      'MODEL_CONFIG_FILE must point to a regular file',
      file.path,
    );
  }
  if (!Platform.isWindows) {
    final permissions = stat.mode & _permissionMask;
    if (permissions != _ownerReadOnly && permissions != _ownerReadWrite) {
      throw FileSystemException(
        'MODEL_CONFIG_FILE permissions must be 600 or 400',
        file.path,
      );
    }
  }
  if (stat.size > _maxConfigBytes) {
    throw const FormatException('Remote model config is too large');
  }

  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Remote model config must be an object');
  }
  return ModelReflectionLiveConfig.fromJson(decoded.cast());
}

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized.endsWith('.localhost') ||
      normalized == '::1' ||
      normalized == '0.0.0.0' ||
      RegExp(r'^127(?:\.|$)').hasMatch(normalized);
}

String _requiredString(
  Map<String, dynamic> json,
  String key, {
  required int maxLength,
}) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Missing remote model config field: $key');
  }
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > maxLength ||
      normalized.contains('\n') ||
      normalized.contains('\r')) {
    throw FormatException('Invalid remote model config field: $key');
  }
  return normalized;
}
