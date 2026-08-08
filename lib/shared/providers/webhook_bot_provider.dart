import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_protocol.dart' as ai;
import '../../core/ai/ai_service.dart';
import '../../core/channels/channel_bot_gateway.dart';
import '../../core/channels/qq_bot_adapter.dart';
import '../../core/channels/slack_bot_adapter.dart';
import '../../core/channels/wechat_mp_adapter.dart';
import '../../core/channels/webhook_channel_adapter.dart';
import '../../core/channels/whatsapp_cloud_adapter.dart';
import '../../core/crypto/key_encryptor.dart';
import 'database_provider.dart';

const kWebhookChannelStorageKey = 'webhook_channel_v1';

enum WebhookChannelKind {
  whatsapp('whatsapp', 'WhatsApp'),
  slack('slack', 'Slack'),
  wechatMp('wechat_mp', '微信公众号'),
  qq('qq', 'QQ');

  const WebhookChannelKind(this.id, this.label);
  final String id;
  final String label;

  static WebhookChannelKind fromId(String id) =>
      values.firstWhere((v) => v.id == id, orElse: () => whatsapp);
}

class WebhookChannelConfig {
  final WebhookChannelKind kind;
  final String token; // access token / bot token
  final String secondary; // phone_number_id / appid / app_secret 等
  const WebhookChannelConfig({
    this.kind = WebhookChannelKind.whatsapp,
    this.token = '',
    this.secondary = '',
  });

  bool get isConfigured => token.trim().isNotEmpty;
}

class WebhookChannelState {
  final bool running;
  final WebhookChannelKind? kind;
  final String? webhookBase;
  final String? lastError;
  const WebhookChannelState({
    this.running = false,
    this.kind,
    this.webhookBase,
    this.lastError,
  });

  WebhookChannelState copyWith({
    bool? running,
    WebhookChannelKind? kind,
    String? webhookBase,
    String? lastError,
  }) {
    return WebhookChannelState(
      running: running ?? this.running,
      kind: kind ?? this.kind,
      webhookBase: webhookBase ?? this.webhookBase,
      lastError: lastError ?? this.lastError,
    );
  }
}

/// 通用 webhook 社交通道控制器：覆盖 WhatsApp / Slack / 微信公众号 / QQ。
class WebhookBotNotifier extends StateNotifier<WebhookChannelState> {
  WebhookBotNotifier({required this.ref}) : super(const WebhookChannelState()) {
    _load();
  }

  final Ref ref;
  WebhookChannelConfig _config = const WebhookChannelConfig();
  Timer? _timer;
  ChannelBotGateway? _gateway;
  WebhookChannelAdapter? _adapter;
  final Map<String, List<ai.AiMessage>> _perUserHistory = {};
  static const _historyLimit = 12;
  static const _pollInterval = Duration(seconds: 10);

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kWebhookChannelStorageKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final secondaryEncrypted = json['secondaryEncrypted'] as String? ?? '';
      _config = WebhookChannelConfig(
        kind: WebhookChannelKind.fromId(json['kind'] as String? ?? ''),
        token: json['tokenEncrypted'] == null
            ? (json['token'] as String? ?? '')
            : KeyEncryptor.decrypt(json['tokenEncrypted'] as String),
        secondary: secondaryEncrypted.isEmpty
            ? ''
            : KeyEncryptor.decrypt(secondaryEncrypted),
      );
    } catch (_) {}
  }

  Future<void> saveConfig(WebhookChannelConfig next) async {
    _config = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kWebhookChannelStorageKey,
        jsonEncode({
          'kind': next.kind.id,
          'tokenEncrypted': KeyEncryptor.encrypt(next.token),
          'secondaryEncrypted': next.secondary.isEmpty
              ? ''
              : KeyEncryptor.encrypt(next.secondary),
        }),
      );
    } catch (_) {}
  }

  WebhookChannelAdapter _buildAdapter() {
    switch (_config.kind) {
      case WebhookChannelKind.slack:
        return SlackBotAdapter(botToken: _config.token);
      case WebhookChannelKind.wechatMp:
        return WechatMpAdapter(
          appId: _config.token,
          appSecret: _config.secondary,
        );
      case WebhookChannelKind.qq:
        return QqBotAdapter(accessToken: _config.token);
      case WebhookChannelKind.whatsapp:
        return WhatsAppCloudAdapter(
          accessToken: _config.token,
          phoneNumberId: _config.secondary,
        );
    }
  }

  Future<String?> start() async {
    if (!_config.isConfigured) return '请先填写该通道的 Token';
    if (state.running) return null;
    try {
      final adapter = _buildAdapter();
      if (!await adapter.testConnection()) {
        return 'Token 校验失败';
      }
      final webhookBase = await adapter.startWebhook();
      _adapter = adapter;
      _gateway = ChannelBotGateway(
        adapter: adapter,
        reply: (text) => _replyViaDefaultModel(text),
      );
      state = state.copyWith(
        running: true,
        kind: _config.kind,
        webhookBase: webhookBase,
        lastError: null,
      );
      _timer = Timer.periodic(_pollInterval, (_) => _pollOnce());
      return null;
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
      return '启动失败：$e';
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _perUserHistory.clear();
    await _adapter?.stopWebhook();
    _adapter = null;
    _gateway = null;
    if (state.running) state = state.copyWith(running: false);
  }

  Future<void> _pollOnce() async {
    final gateway = _gateway;
    if (gateway == null || !state.running) return;
    try {
      await gateway.runOnce();
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
    }
  }

  Future<String> _replyViaDefaultModel(String text) async {
    final channelDao = ref.read(channelDaoProvider);
    final models = await channelDao.getChatModels();
    if (models.isEmpty) return '尚未配置可用的聊天模型，请先在设置中添加渠道和模型。';
    final first = models.first;
    final history = _perUserHistory.putIfAbsent(
      'chat:${first.channelModel.id}',
      () => [],
    );
    history.add(ai.AiMessage(role: 'user', content: text));
    if (history.length > _historyLimit) {
      history.removeRange(0, history.length - _historyLimit);
    }
    final apiKey = KeyEncryptor.decryptOrEmpty(first.channel.apiKeyEncrypted);
    final buffer = StringBuffer();
    await for (final chunk in AiService.sendMessage(
      protocol: first.channel.protocol,
      baseUrl: first.channel.baseUrl,
      apiKey: apiKey,
      model: first.channelModel.modelName,
      messages: List<ai.AiMessage>.from(history),
      systemPrompt: '你是 SimiAIChat 的社交通道助手。基于对话历史用中文简洁回答用户。',
    )) {
      final content = chunk.content ?? '';
      if (content.isNotEmpty) buffer.write(content);
    }
    final reply = buffer.toString().trim();
    if (reply.isEmpty) return '（没有生成有效回复，请重试）';
    history.add(ai.AiMessage(role: 'assistant', content: reply));
    if (history.length > _historyLimit) {
      history.removeRange(0, history.length - _historyLimit);
    }
    return reply;
  }
}

final webhookBotProvider =
    StateNotifierProvider<WebhookBotNotifier, WebhookChannelState>(
      (ref) => WebhookBotNotifier(ref: ref),
    );
