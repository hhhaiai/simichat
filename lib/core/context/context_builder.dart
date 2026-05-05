import '../ai/ai_protocol.dart';
import '../database/dao/message_dao.dart';

/// 上下文构建器：从数据库中构建发送给 AI 的上下文消息列表
class ContextBuilder {
  final MessageDao _messageDao;

  ContextBuilder(this._messageDao);

  /// 默认系统提示词
  static const defaultSystemPrompt =
      '你是一个有帮助的 AI 助手。请用简洁、准确的中文回答问题。'
      '如果用户用其他语言提问，请用对应语言回答。';

  /// 构建请求上下文
  /// 规则：
  ///   1. 所有 summary 消息（作为 assistant 消息，保持交替格式）
  ///   2. 最近 K 条未压缩的 original 消息
  /// 返回 (systemPrompt, messages)
  Future<(String, List<AiMessage>)> buildContext(
    String sessionId, {
    int recentK = 20,
    String? customSystemPrompt,
  }) async {
    final summaries = await _messageDao.getSummaries(sessionId);
    final originals = await _messageDao.getUnsummarizedOriginals(sessionId);

    final messages = <AiMessage>[];

    // 1. 所有 summary（用 assistant 角色，表示这是 AI 之前的总结）
    for (final s in summaries) {
      messages.add(AiMessage(role: 'assistant', content: '[历史摘要] ${s.content}'));
    }

    // 2. 最近 K 条 original
    final recent = originals.length <= recentK
        ? originals
        : originals.sublist(originals.length - recentK);

    for (final m in recent) {
      messages.add(AiMessage(role: m.role, content: m.content));
    }

    // 确保消息列表以 user 消息开头（如果以 summary 开头，需要调整）
    // 如果第一条是 assistant（summary），在前面加一条 user 消息
    if (messages.isNotEmpty && messages.first.role == 'assistant') {
      messages.insert(0, const AiMessage(role: 'user', content: '请继续我们的对话。'));
    }

    final systemPrompt = customSystemPrompt ?? defaultSystemPrompt;
    return (systemPrompt, messages);
  }
}
