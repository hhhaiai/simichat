import 'dart:convert';

import 'model_capability.dart';
import 'sse_helper.dart';

const supportedImportProtocols = {
  'openai_chat',
  'openai_response',
  'claude',
  'gemini',
  'ollama',
};

class ImportedChannelModel {
  final String name;
  final String capability;

  const ImportedChannelModel({
    required this.name,
    this.capability = ModelCapability.chat,
  });
}

class ImportedModelChannel {
  final String name;
  final String baseUrl;
  final String protocol;
  final String apiKey;
  final List<ImportedChannelModel> models;

  const ImportedModelChannel({
    required this.name,
    required this.baseUrl,
    required this.protocol,
    required this.apiKey,
    required this.models,
  });
}

class ModelChannelImportParseException implements Exception {
  final String message;

  const ModelChannelImportParseException(this.message);

  @override
  String toString() => message;
}

class ModelChannelImportParser {
  static List<ImportedModelChannel> parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw const ModelChannelImportParseException('导入内容不能为空');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const ModelChannelImportParseException('导入内容不是有效 JSON');
    }

    final channelItems = _readChannelList(decoded);
    if (channelItems.isEmpty) {
      throw const ModelChannelImportParseException('未找到可导入的渠道配置');
    }

    return [
      for (var i = 0; i < channelItems.length; i++)
        _parseChannel(channelItems[i], index: i),
    ];
  }

  static List<dynamic> _readChannelList(Object? decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final channels = decoded['channels'];
      if (channels is List) return channels;
    }
    throw const ModelChannelImportParseException(
      '导入 JSON 必须是数组，或包含 channels 数组',
    );
  }

  static ImportedModelChannel _parseChannel(Object? raw, {required int index}) {
    final label = '第 ${index + 1} 个渠道';
    if (raw is! Map) {
      throw ModelChannelImportParseException('$label 必须是对象');
    }
    final map = raw.cast<String, dynamic>();
    final name = _requiredString(map, [
      'name',
      'channelName',
    ], '$label 缺少 name');
    final baseUrl = normalizeUrl(
      _requiredString(map, ['baseUrl', 'base_url', 'url'], '$label 缺少 baseUrl'),
    );
    final protocol = _readString(map, ['protocol']) ?? 'openai_chat';
    if (!supportedImportProtocols.contains(protocol)) {
      throw ModelChannelImportParseException('$label 协议不支持: $protocol');
    }
    final apiKey = _readString(map, ['apiKey', 'api_key', 'key']) ?? '';
    if (protocol != 'ollama' && apiKey.isEmpty) {
      throw ModelChannelImportParseException('$label 缺少 apiKey');
    }

    return ImportedModelChannel(
      name: name,
      baseUrl: baseUrl,
      protocol: protocol,
      apiKey: apiKey,
      models: _parseModels(map['models']),
    );
  }

  static List<ImportedChannelModel> _parseModels(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw const ModelChannelImportParseException('models 必须是数组');
    }

    final models = <ImportedChannelModel>[];
    final seen = <String>{};
    for (final item in raw) {
      final model = _parseModel(item);
      final key = '${model.capability}::${model.name}';
      if (seen.add(key)) models.add(model);
    }
    return models;
  }

  static ImportedChannelModel _parseModel(Object? raw) {
    if (raw is String) {
      final name = raw.trim();
      if (name.isEmpty) {
        throw const ModelChannelImportParseException('模型名称不能为空');
      }
      return ImportedChannelModel(name: name);
    }
    if (raw is Map) {
      final map = raw.cast<String, dynamic>();
      final name = _requiredString(map, [
        'name',
        'modelName',
        'model',
        'id',
      ], '模型缺少 name');
      return ImportedChannelModel(
        name: name,
        capability: ModelCapability.normalize(
          _readString(map, ['capability', 'type']),
        ),
      );
    }
    throw const ModelChannelImportParseException('模型必须是字符串或对象');
  }

  static String _requiredString(
    Map<String, dynamic> map,
    List<String> keys,
    String message,
  ) {
    final value = _readString(map, keys);
    if (value == null || value.isEmpty) {
      throw ModelChannelImportParseException(message);
    }
    return value;
  }

  static String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}
