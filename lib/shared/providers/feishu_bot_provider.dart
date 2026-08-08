import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_protocol.dart' as ai;
import '../../core/ai/ai_service.dart';
import '../../core/channels/channel_bot_gateway.dart';
import '../../core/channels/feishu_bot_adapter.dart';
import '../../core/crypto/key_encryptor.dart';
import 'database_provider.dart';

const kFeishuBotStorageKey = 'feishu_bot_v1';

class FeishuBotState {
  final bool running;
  final String? webhookBase;
  final String? lastError;
  const FeishuBotState({
    this.running = false,
    this.webhookBase,
    this.lastError,
  });

  FeishuBotState copyWith({
    bool? running,
    String? webhookBase,
    String? lastError,
  }) {
    return FeishuBotState(
      running: running ?? this.running,
      webhookBase: webhookBase ?? this.webhookBase,
      lastError: lastError ?? this.lastError,
    );
  }
}

/// 飞书 Bot 通道控制器：配置 App ID / Secret，启动本地 webhook + 轮询，用默认聊天模型应答。
class FeishuBotNotifier extends StateNotifier<FeishuBotState> {
  FeishuBotNotifier({required this.ref}) : super(const FeishuBotState()) {
    _load();
  }

  final Ref ref;
  String _appId = '';
  String _appSecret = '';
  Timer? _timer;
  ChannelBotGateway? _gateway;
  FeishuBotAdapter? _adapter;
  final Map<String, List<ai.AiMessage>> _perUserHistory = {};
  static const _historyLimit = 12;
  static const _pollInterval = Duration(seconds: 10);

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kFeishuBotStorageKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final secretEncrypted = json['appSecretEncrypted'] as String? ?? '';
      _appId = json['appId'] as String? ?? '';
      _appSecret = secretEncrypted.isEmpty
          ? ''
          : KeyEncryptor.decrypt(secretEncrypted);
    } catch (_) {}
  }

  Future<void> saveCredentials(String appId, String appSecret) async {
    _appId = appId.trim();
    _appSecret = appSecret.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_appId.isEmpty || _appSecret.isEmpty) {
        await prefs.remove(kFeishuBotStorageKey);
      } else {
        await prefs.setString(
          kFeishuBotStorageKey,
          jsonEncode({
            'appId': _appId,
            'appSecretEncrypted': KeyEncryptor.encrypt(_appSecret),
          }),
        );
      }
    } catch (_) {}
  }

  Future<String?> start() async {
    if (_appId.isEmpty || _appSecret.isEmpty) {
      return '请先填写飞书 App ID 与 App Secret';
    }
    if (state.running) return null;
    try {
      final adapter = FeishuBotAdapter(appId: _appId, appSecret: _appSecret);
      final webhookBase = await adapter.startWebhook();
      _adapter = adapter;
      _gateway = ChannelBotGateway(
        adapter: adapter,
        reply: (text) => _replyViaDefaultModel(text),
      );
      state = state.copyWith(
        running: true,
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
      systemPrompt: '你是 SimiAIChat 的飞书助手。基于对话历史用中文简洁回答用户。',
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

final feishuBotProvider =
    StateNotifierProvider<FeishuBotNotifier, FeishuBotState>(
      (ref) => FeishuBotNotifier(ref: ref),
    );
