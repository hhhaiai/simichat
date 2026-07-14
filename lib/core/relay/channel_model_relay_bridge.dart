import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;

import '../ai/ai_protocol.dart';
import '../ai/ai_service.dart';
import '../ai/model_capability.dart';
import '../ai/openai_chat_protocol.dart';
import '../crypto/key_encryptor.dart';
import '../database/dao/channel_dao.dart';
import 'openai_compatible_relay_server.dart';

typedef OpenAiRelayAiSender =
    Stream<AiChunk> Function({
      required String protocol,
      required String baseUrl,
      required String apiKey,
      required String model,
      required List<AiMessage> messages,
      String? systemPrompt,
      CancelToken? cancelToken,
      required bool jsonResponse,
    });

typedef OpenAiRelayAiFetcher =
    Future<({String content, String? thinking})> Function({
      required String baseUrl,
      required String apiKey,
      required String model,
      required List<AiMessage> messages,
      String? systemPrompt,
      CancelToken? cancelToken,
    });

/// 将数据库中的渠道 / 模型配置桥接到本地 OpenAI 兼容中转服务。
class ChannelModelRelayBridge {
  const ChannelModelRelayBridge({
    required this.channelDao,
    this.routeStrategy = OpenAiRelayRouteStrategy.direct,
    this.decryptApiKey = KeyEncryptor.decrypt,
    this.sendMessage = _defaultSendMessage,
    this.fetchOpenAiMessage = OpenAiChatProtocol.fetchMessageOnce,
  });

  final ChannelDao channelDao;
  final OpenAiRelayRouteStrategy routeStrategy;
  final String Function(String encrypted) decryptApiKey;
  final OpenAiRelayAiSender sendMessage;
  final OpenAiRelayAiFetcher fetchOpenAiMessage;

  Future<List<OpenAiCompatibleRelayModel>> listModels() async {
    final models = await channelDao.getChatModels();
    if (models.isEmpty) return const [];
    final hasVisionModel = models.any(
      (item) => ModelCapability.isVision(item.channelModel.capability),
    );
    return [
      _routeAliasModel(
        id: kOpenAiRelayRouteAliasDefault,
        displayName: 'SimiChat 路由 / 默认模型',
        supportsVision: hasVisionModel,
      ),
      _routeAliasModel(
        id: kOpenAiRelayRouteAliasFree,
        displayName: 'SimiChat 路由 / 免费优先',
        supportsVision: hasVisionModel,
      ),
      _routeAliasModel(
        id: kOpenAiRelayRouteAliasFast,
        displayName: 'SimiChat 路由 / 本地/快速优先',
        supportsVision: hasVisionModel,
      ),
      for (final item in models) _toRelayModel(item),
    ];
  }

  Future<OpenAiCompatibleRelayModel?> resolveModel(String modelId) async {
    final item = await channelDao.getModelWithChannel(modelId);
    if (item == null) return null;
    if (!item.channel.isEnabled) return null;
    if (!ModelCapability.isChat(item.channelModel.capability)) {
      return null;
    }
    return _toRelayModel(item);
  }

  Future<OpenAiCompatibleRelayRoute?> routeModel(String? modelId) async {
    final requested = modelId?.trim();
    if (requested != null && requested.isNotEmpty) {
      final exact = await resolveModel(requested);
      if (exact != null) {
        return OpenAiCompatibleRelayRoute(primary: exact);
      }
    }

    final strategy = _strategyForRequest(requested);
    if (strategy == OpenAiRelayRouteStrategy.direct) return null;

    final models = await channelDao.getChatModels();
    final ranked = _rankModels(models, strategy);
    if (ranked.isEmpty) return null;
    final relayModels = [for (final item in ranked) _toRelayModel(item)];
    return OpenAiCompatibleRelayRoute(
      primary: relayModels.first,
      fallbacks: relayModels.skip(1).toList(),
      routeCode: strategy.storageValue,
    );
  }

  Stream<AiChunk> forward({
    required OpenAiCompatibleRelayModel model,
    required List<AiMessage> messages,
    String? systemPrompt,
    CancelToken? cancelToken,
    bool jsonResponse = false,
  }) async* {
    final item = await channelDao.getModelWithChannel(model.id);
    if (item == null || !item.channel.isEnabled) {
      throw const OpenAiCompatibleRelayException('模型不存在或未启用');
    }
    if (!ModelCapability.isChat(item.channelModel.capability)) {
      throw const OpenAiCompatibleRelayException('模型不是聊天模型');
    }
    final apiKey = item.channel.apiKeyEncrypted.isEmpty
        ? ''
        : decryptApiKey(item.channel.apiKeyEncrypted);
    yield* sendMessage(
      protocol: item.channel.protocol,
      baseUrl: item.channel.baseUrl,
      apiKey: apiKey,
      model: item.channelModel.modelName,
      messages: messages,
      systemPrompt: systemPrompt,
      cancelToken: cancelToken,
      jsonResponse: jsonResponse,
    );
  }

  Future<AiChunk?> forwardOnce({
    required OpenAiCompatibleRelayModel model,
    required List<AiMessage> messages,
    String? systemPrompt,
    CancelToken? cancelToken,
  }) async {
    final item = await channelDao.getModelWithChannel(model.id);
    if (item == null || !item.channel.isEnabled) {
      throw const OpenAiCompatibleRelayException('模型不存在或未启用');
    }
    if (!ModelCapability.isChat(item.channelModel.capability)) {
      throw const OpenAiCompatibleRelayException('模型不是聊天模型');
    }
    if (item.channel.protocol != 'openai_chat') return null;

    final apiKey = item.channel.apiKeyEncrypted.isEmpty
        ? ''
        : decryptApiKey(item.channel.apiKeyEncrypted);
    final result = await fetchOpenAiMessage(
      baseUrl: item.channel.baseUrl,
      apiKey: apiKey,
      model: item.channelModel.modelName,
      messages: messages,
      systemPrompt: systemPrompt,
      cancelToken: cancelToken,
    );
    return AiChunk(content: result.content, thinking: result.thinking);
  }

  OpenAiCompatibleRelayModel _toRelayModel(ChannelModelWithChannel item) {
    return OpenAiCompatibleRelayModel(
      id: item.channelModel.id,
      modelName: item.channelModel.modelName,
      displayName: item.displayLabel,
      ownedBy: item.channel.name,
      supportsVision: ModelCapability.isVision(item.channelModel.capability),
    );
  }

  OpenAiCompatibleRelayModel _routeAliasModel({
    required String id,
    required String displayName,
    required bool supportsVision,
  }) {
    return OpenAiCompatibleRelayModel(
      id: id,
      modelName: id,
      displayName: displayName,
      ownedBy: 'simichat-router',
      supportsVision: supportsVision,
    );
  }

  OpenAiRelayRouteStrategy _strategyForRequest(String? requested) {
    return switch (requested) {
      null || '' || kOpenAiRelayRouteAliasAuto => routeStrategy,
      kOpenAiRelayRouteAliasDefault => OpenAiRelayRouteStrategy.defaultModel,
      kOpenAiRelayRouteAliasFree => OpenAiRelayRouteStrategy.freeFirst,
      kOpenAiRelayRouteAliasFast => OpenAiRelayRouteStrategy.fastFirst,
      _ => OpenAiRelayRouteStrategy.direct,
    };
  }

  List<ChannelModelWithChannel> _rankModels(
    List<ChannelModelWithChannel> models,
    OpenAiRelayRouteStrategy strategy,
  ) {
    final ranked = [...models];
    ranked.sort((a, b) {
      final scoreB = _routeScore(b, strategy);
      final scoreA = _routeScore(a, strategy);
      final scoreCompare = scoreB.compareTo(scoreA);
      if (scoreCompare != 0) return scoreCompare;
      final defaultCompare = _defaultScore(b).compareTo(_defaultScore(a));
      if (defaultCompare != 0) return defaultCompare;
      return a.displayLabel.compareTo(b.displayLabel);
    });
    return ranked;
  }

  int _routeScore(
    ChannelModelWithChannel item,
    OpenAiRelayRouteStrategy strategy,
  ) {
    return switch (strategy) {
      OpenAiRelayRouteStrategy.direct => 0,
      OpenAiRelayRouteStrategy.defaultModel => _defaultScore(item),
      OpenAiRelayRouteStrategy.freeFirst =>
        (_isFreeLike(item) ? 100 : 0) + _defaultScore(item),
      OpenAiRelayRouteStrategy.fastFirst =>
        (_isLocalLike(item) ? 100 : 0) +
            (_isFreeLike(item) ? 10 : 0) +
            _defaultScore(item),
    };
  }

  int _defaultScore(ChannelModelWithChannel item) {
    return item.channelModel.isDefault ? 10 : 0;
  }

  bool _isFreeLike(ChannelModelWithChannel item) {
    final text =
        '${item.channel.name} ${item.channel.baseUrl} ${item.channel.protocol} '
                '${item.channelModel.modelName} ${item.displayLabel}'
            .toLowerCase();
    return item.channel.apiKeyEncrypted.isEmpty ||
        text.contains('free') ||
        text.contains('免费') ||
        text.contains(':free') ||
        text.contains('ollama');
  }

  bool _isLocalLike(ChannelModelWithChannel item) {
    final text =
        '${item.channel.name} ${item.channel.baseUrl} ${item.channel.protocol} '
                '${item.channelModel.modelName}'
            .toLowerCase();
    return text.contains('ollama') ||
        text.contains('localhost') ||
        text.contains('127.0.0.1') ||
        text.contains('0.0.0.0') ||
        text.contains('本地');
  }
}

Stream<AiChunk> _defaultSendMessage({
  required String protocol,
  required String baseUrl,
  required String apiKey,
  required String model,
  required List<AiMessage> messages,
  String? systemPrompt,
  CancelToken? cancelToken,
  required bool jsonResponse,
}) {
  return AiService.sendMessage(
    protocol: protocol,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
    messages: messages,
    systemPrompt: systemPrompt,
    cancelToken: cancelToken,
    jsonResponse: jsonResponse,
  );
}
