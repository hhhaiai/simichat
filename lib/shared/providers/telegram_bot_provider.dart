import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/ai_protocol.dart' as ai;
import '../../core/ai/ai_service.dart';
import '../../core/channels/channel_bot_gateway.dart';
import '../../core/channels/telegram_bot_adapter.dart';
import '../../core/crypto/key_encryptor.dart';
import 'database_provider.dart';

/// Telegram Bot Token 持久化 key。
const kTelegramBotTokenStorageKey = 'telegram_bot_token_encrypted_v1';

class TelegramBotConfig {
  final String botToken;
  const TelegramBotConfig({this.botToken = ''});

  bool get isConfigured => botToken.trim().isNotEmpty;
}

class TelegramBotState {
  final bool running;
  final String? botUsername;
  final String? lastError;
  const TelegramBotState({
    this.running = false,
    this.botUsername,
    this.lastError,
  });

  TelegramBotState copyWith({
    bool? running,
    String? botUsername,
    String? lastError,
  }) {
    return TelegramBotState(
      running: running ?? this.running,
      botUsername: botUsername ?? this.botUsername,
      lastError: lastError ?? this.lastError,
    );
  }
}

/// 默认长轮询间隔。
const kTelegramPollInterval = Duration(seconds: 15);

/// Telegram Bot 通道控制器：持有配置、启动 / 停止轮询，并用默认聊天模型应答。
class TelegramBotNotifier extends StateNotifier<TelegramBotState> {
  TelegramBotNotifier({required this.ref})
    : _config = const TelegramBotConfig(),
      super(const TelegramBotState()) {
    _loadConfig();
  }

  final Ref ref;
  TelegramBotConfig _config;
  Timer? _timer;
  ChannelBotGateway? _gateway;
  final Map<String, List<ai.AiMessage>> _perUserHistory = {};
  static const _historyLimit = 12;

  bool get running => state.running;

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kTelegramBotTokenStorageKey);
      if (raw != null && raw.isNotEmpty) {
        _config = TelegramBotConfig(botToken: KeyEncryptor.decrypt(raw));
      }
    } catch (_) {}
  }

  Future<void> saveToken(String token) async {
    final trimmed = token.trim();
    _config = TelegramBotConfig(botToken: trimmed);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (trimmed.isEmpty) {
        await prefs.remove(kTelegramBotTokenStorageKey);
      } else {
        await prefs.setString(
          kTelegramBotTokenStorageKey,
          KeyEncryptor.encrypt(trimmed),
        );
      }
    } catch (_) {}
  }

  Future<String?> start() async {
    if (_config.botToken.trim().isEmpty) return '请先填写 Telegram Bot Token';
    if (state.running) return null;
    try {
      final adapter = TelegramBotAdapter(botToken: _config.botToken);
      final username = await adapter.getMe();
      _gateway = ChannelBotGateway(
        adapter: adapter,
        reply: (text) => _replyViaDefaultModel(text),
      );
      state = state.copyWith(
        running: true,
        botUsername: username,
        lastError: null,
      );
      _timer = Timer.periodic(kTelegramPollInterval, (_) async {
        await _pollOnce();
      });
      // 启动后立即拉取一次，加快首条回复。
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
    _gateway = null;
    _perUserHistory.clear();
    if (state.running) {
      state = state.copyWith(running: false);
    }
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

  /// 用默认聊天模型应答：维护每用户有界历史，拼接后调用 AiService。
  Future<String> _replyViaDefaultModel(String text) async {
    final channelDao = ref.read(channelDaoProvider);
    final models = await channelDao.getChatModels();
    if (models.isEmpty) {
      return '尚未配置可用的聊天模型，请先在设置中添加渠道和模型。';
    }
    final first = models.first;

    final history = _perUserHistory.putIfAbsent(
      'chat:${first.channelModel.id}',
      () => [],
    );
    history.add(ai.AiMessage(role: 'user', content: text));
    if (history.length > _historyLimit) {
      history.removeRange(0, history.length - _historyLimit);
    }

    final systemPrompt = '你是 SimiAIChat 的 Telegram 助手。基于对话历史用中文简洁回答用户。';

    final apiKey = KeyEncryptor.decryptOrEmpty(first.channel.apiKeyEncrypted);
    final builder = StringBuffer();
    await for (final chunk in AiService.sendMessage(
      protocol: first.channel.protocol,
      baseUrl: first.channel.baseUrl,
      apiKey: apiKey,
      model: first.channelModel.modelName,
      messages: List<ai.AiMessage>.from(history),
      systemPrompt: systemPrompt,
    )) {
      final text = chunk.content ?? '';
      if (text.isNotEmpty) builder.write(text);
    }
    final reply = builder.toString().trim();
    if (reply.isEmpty) {
      return '（没有生成有效回复，请重试）';
    }
    history.add(ai.AiMessage(role: 'assistant', content: reply));
    if (history.length > _historyLimit) {
      history.removeRange(0, history.length - _historyLimit);
    }
    return reply;
  }
}

final telegramBotProvider =
    StateNotifierProvider<TelegramBotNotifier, TelegramBotState>(
      (ref) => TelegramBotNotifier(ref: ref),
    );
