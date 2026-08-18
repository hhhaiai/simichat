import '../ai/ai_protocol.dart';
import '../database/dao/message_dao.dart';
import 'context_budget_trimmer.dart';

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
  ///   1. 没有预算时：所有 summary + 最近 K 条未压缩 original，保持旧行为
  ///   2. 有预算时：summary + 所有未压缩 original 中，从最新消息往前尽量装入预算
  /// 返回 (systemPrompt, messages)
  Future<(String, List<AiMessage>)> buildContext(
    String sessionId, {
    int recentK = 20,
    int? maxInputTokens,
    String? customSystemPrompt,
    String? memoryPrompt,
    String? skillsPrompt,
    String? mcpToolsPrompt,
    String? upToMessageId,
    String? targetMessageContent,
    List<Attachment>? targetMessageAttachments,
  }) async {
    var summaries = await _messageDao.getSummaries(sessionId);
    var originals = await _messageDao.getUnsummarizedOriginals(sessionId);

    // Regenerate must replay only the conversation prefix ending at the
    // target user turn. The normal call path does not pass this boundary and
    // therefore retains the historical context behavior.
    if (upToMessageId != null && upToMessageId.trim().isNotEmpty) {
      final allMessages = await _messageDao.getMessagesBySession(sessionId);
      final targetIndex = allMessages.indexWhere(
        (message) => message.id == upToMessageId,
      );
      if (targetIndex >= 0) {
        final visibleIds = allMessages
            .take(targetIndex + 1)
            .map((message) => message.id)
            .toSet();
        final target = allMessages[targetIndex];

        originals = originals
            .where((message) => visibleIds.contains(message.id))
            .toList();
        // A target can already be marked summarized. It still has to be
        // replayed as the current user turn; the summary covers older
        // history, while this original message is the actual request.
        if (target.messageType == 'original' &&
            target.role == 'user' &&
            !originals.any((message) => message.id == target.id)) {
          originals = [...originals, target];
        }

        summaries = summaries.where((summary) {
          final endId = summary.summaryEndId;
          if (endId != null && endId.isNotEmpty) {
            final endIndex = allMessages.indexWhere(
              (message) => message.id == endId,
            );
            return endIndex >= 0 && endIndex <= targetIndex;
          }
          return summary.createdAt <= target.createdAt;
        }).toList();
      }
    }

    var systemPrompt = _buildSystemPrompt(
      customSystemPrompt: customSystemPrompt,
      memoryPrompt: memoryPrompt,
      skillsPrompt: skillsPrompt,
      mcpToolsPrompt: mcpToolsPrompt,
    );
    if (maxInputTokens != null) {
      systemPrompt = trimTextToTokenBudget(
        systemPrompt,
        _systemPromptBudget(maxInputTokens),
      );
    }

    final messages = <AiMessage>[];

    // 1. 所有 summary（用 assistant 角色，表示这是 AI 之前的总结）
    for (final s in summaries) {
      messages.add(
        AiMessage(role: 'assistant', content: '[历史摘要] ${s.content}'),
      );
    }

    // 2. 没有预算时保持旧的 K 条；有预算时先放入全部候选，再统一按预算裁剪。
    final recent = maxInputTokens != null
        ? originals
        : (originals.length <= recentK
              ? originals
              : originals.sublist(originals.length - recentK));

    for (final m in recent) {
      final isTargetUser =
          upToMessageId != null && m.id == upToMessageId && m.role == 'user';
      messages.add(
        AiMessage(
          role: m.role,
          content: isTargetUser && targetMessageContent != null
              ? targetMessageContent
              : m.content,
          attachments:
              isTargetUser &&
                  targetMessageAttachments != null &&
                  targetMessageAttachments.isNotEmpty
              ? targetMessageAttachments
              : null,
        ),
      );
    }

    if (maxInputTokens != null) {
      return (
        systemPrompt,
        trimAiMessagesToTokenBudget(
          systemPrompt: systemPrompt,
          messages: messages,
          maxInputTokens: maxInputTokens,
        ),
      );
    }

    // 确保消息列表以 user 消息开头（如果以 summary 开头，需要调整）
    // 如果第一条是 assistant（summary），在前面加一条 user 消息
    if (messages.isNotEmpty && messages.first.role == 'assistant') {
      messages.insert(0, const AiMessage(role: 'user', content: '请继续我们的对话。'));
    }

    return (systemPrompt, messages);
  }

  String _buildSystemPrompt({
    String? customSystemPrompt,
    String? memoryPrompt,
    String? skillsPrompt,
    String? mcpToolsPrompt,
  }) {
    var systemPrompt = customSystemPrompt ?? defaultSystemPrompt;
    if (memoryPrompt != null && memoryPrompt.isNotEmpty) {
      systemPrompt = '$systemPrompt\n\n$memoryPrompt';
    }
    if (skillsPrompt != null && skillsPrompt.isNotEmpty) {
      systemPrompt = '$systemPrompt\n\n$skillsPrompt';
    }
    if (mcpToolsPrompt != null && mcpToolsPrompt.isNotEmpty) {
      systemPrompt = '$systemPrompt\n\n$mcpToolsPrompt';
    }
    return systemPrompt;
  }

  int _systemPromptBudget(int maxInputTokens) {
    if (maxInputTokens <= 0) return 0;
    final quarter = (maxInputTokens * 0.25).floor();
    final lowerBounded = quarter < 64 ? 64 : quarter;
    final upperBound = maxInputTokens ~/ 2;
    return lowerBounded > upperBound ? upperBound : lowerBounded;
  }
}
