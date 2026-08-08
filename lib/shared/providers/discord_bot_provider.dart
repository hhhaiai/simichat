import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_protocol.dart' as ai;
import '../../core/ai/ai_service.dart';
import '../../core/channels/channel_bot_gateway.dart';
import '../../core/channels/discord_bot_adapter.dart';
import '../../core/crypto/key_encryptor.dart';
import 'database_provider.dart';

const kDiscordBotTokenStorageKey = 'discord_bot_token_encrypted_v1';

class DiscordBotState {
  final bool running;
  final String? botUsername;
  final String? lastError;
  const DiscordBotState({
    this.running = false,
    this.botUsername,
    this.lastError,
  });

  DiscordBotState copyWith({
    bool? running,
    String? botUsername,
    String? lastError,
  }) {
    return DiscordBotState(
      running: running ?? this.running,
      botUsername: botUsername ?? this.botUsername,
      lastError: lastError ?? this.lastError,
    );
  }
}

/// Discord Bot 通道控制器：配置 Token、启动 / 停止 Gateway 轮询，并用默认聊天模型应答。
class DiscordBotNotifier extends StateNotifier<DiscordBotState> {
  DiscordBotNotifier({required this.ref}) : super(const DiscordBotState()) {
    _load();
  }

  final Ref ref;
  String _token = '';
  Timer? _timer;
  ChannelBotGateway? _gateway;
  DiscordBotAdapter? _adapter;
  final Map<String, List<ai.AiMessage>> _perUserHistory = {};
  static const _historyLimit = 12;
  static const _pollInterval = Duration(seconds: 15);

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kDiscordBotTokenStorageKey);
      if (raw != null && raw.isNotEmpty) {
        _token = KeyEncryptor.decrypt(raw);
      }
    } catch (_) {}
  }

  Future<void> saveToken(String token) async {
    _token = token.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_token.isEmpty) {
        await prefs.remove(kDiscordBotTokenStorageKey);
      } else {
        await prefs.setString(
          kDiscordBotTokenStorageKey,
          KeyEncryptor.encrypt(_token),
        );
      }
    } catch (_) {}
  }

  Future<String?> start() async {
    if (_token.isEmpty) return '请先填写 Discord Bot Token';
    if (state.running) return null;
    try {
      final adapter = DiscordBotAdapter(botToken: _token);
      final username = await adapter.getMe();
      _adapter = adapter;
      _gateway = ChannelBotGateway(
        adapter: adapter,
        reply: (text) => _replyViaDefaultModel(text),
      );
      state = state.copyWith(
        running: true,
        botUsername: username,
        lastError: null,
      );
      _timer = Timer.periodic(_pollInterval, (_) => _pollOnce());
      unawaited(_pollOnce());
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
    await _adapter?.dispose();
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
      systemPrompt: '你是 SimiAIChat 的 Discord 助手。基于对话历史用中文简洁回答用户。',
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

final discordBotProvider =
    StateNotifierProvider<DiscordBotNotifier, DiscordBotState>(
      (ref) => DiscordBotNotifier(ref: ref),
    );
