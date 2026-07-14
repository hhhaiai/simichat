import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

const kAndroidBackgroundDreamingModelSmokeConfigFileName =
    'android_background_dreaming_model_smoke.json';
const _maxConfigBytes = 8 * 1024;

class AndroidBackgroundDreamingModelSmokeConfig {
  const AndroidBackgroundDreamingModelSmokeConfig({
    required this.protocol,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  factory AndroidBackgroundDreamingModelSmokeConfig.fromJson(
    Map<String, dynamic> json,
  ) {
    final protocol = _requiredString(json, 'protocol', maxLength: 64);
    if (protocol != 'openai_chat') {
      throw const FormatException(
        'Android background model smoke only accepts openai_chat',
      );
    }
    final baseUrl = _requiredString(json, 'baseUrl', maxLength: 2048);
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('Invalid remote model baseUrl');
    }
    return AndroidBackgroundDreamingModelSmokeConfig(
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

Future<AndroidBackgroundDreamingModelSmokeConfig>
loadAndroidBackgroundDreamingModelConfig({File? configFile}) async {
  final file = configFile ?? await _defaultConfigFile();
  try {
    if (await file.length() > _maxConfigBytes) {
      throw const FormatException('Remote model smoke config is too large');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException(
        'Remote model smoke config must be an object',
      );
    }
    return AndroidBackgroundDreamingModelSmokeConfig.fromJson(decoded.cast());
  } finally {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<File> _defaultConfigFile() async {
  final directory = await getApplicationSupportDirectory();
  return File(
    '${directory.path}/$kAndroidBackgroundDreamingModelSmokeConfigFileName',
  );
}

String _requiredString(
  Map<String, dynamic> json,
  String key, {
  required int maxLength,
}) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Missing remote model smoke field: $key');
  }
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > maxLength) {
    throw FormatException('Invalid remote model smoke field: $key');
  }
  return normalized;
}
