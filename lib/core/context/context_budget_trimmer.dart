import '../ai/ai_protocol.dart';
import 'token_estimator.dart';

const _bridgeUserMessage = AiMessage(role: 'user', content: '请继续我们的对话。');

int estimateAiMessageTokens(AiMessage message) =>
    TokenEstimator.estimate(message.content);

int estimateContextInputTokens({
  required String? systemPrompt,
  required List<AiMessage> messages,
}) {
  return TokenEstimator.estimate(systemPrompt ?? '') +
      messages.fold<int>(
        0,
        (sum, message) => sum + estimateAiMessageTokens(message),
      );
}

String trimTextToTokenBudget(String text, int maxTokens) {
  if (maxTokens <= 0 || text.isEmpty) return '';
  if (TokenEstimator.estimate(text) <= maxTokens) return text;

  var low = 0;
  var high = text.length;
  var best = '';
  while (low <= high) {
    final mid = (low + high) >> 1;
    final candidate = text.substring(0, mid).trimRight();
    if (TokenEstimator.estimate(candidate) <= maxTokens) {
      best = candidate;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return best;
}

List<AiMessage> trimAiMessagesToTokenBudget({
  required String? systemPrompt,
  required List<AiMessage> messages,
  required int maxInputTokens,
}) {
  if (messages.isEmpty || maxInputTokens <= 0) return const [];

  final systemTokens = TokenEstimator.estimate(systemPrompt ?? '');
  final messageBudget = maxInputTokens - systemTokens;
  if (messageBudget <= 0) return const [];

  // 长会话的滚动摘要是早期事实的唯一远程上下文表示。旧实现单纯从最新消息
  // 倒序装箱；当近期原文填满预算时，会首先丢掉位于列表开头的摘要，导致
  // “客户端无限上下文”在最需要它时失效。为摘要保留一个有界小窗口，剩余
  // 预算仍全部优先给最新原始轮次。
  final summaryMessages = messages
      .where(_isHistoricalSummary)
      .toList(growable: false);
  AiMessage? retainedSummary;
  var summaryEnvelopeCost = 0;
  if (summaryMessages.isNotEmpty) {
    final bridgeCost = estimateAiMessageTokens(_bridgeUserMessage);
    final available = messageBudget - bridgeCost;
    if (available > 0) {
      final preferred = (messageBudget * 0.20).floor().clamp(64, 8192);
      final summaryBudget = preferred < available ? preferred : available;
      final combined = summaryMessages
          .map((message) => message.content)
          .join('\n');
      final content = trimTextToTokenBudget(combined, summaryBudget);
      if (content.isNotEmpty) {
        retainedSummary = AiMessage(role: 'assistant', content: content);
        summaryEnvelopeCost =
            bridgeCost + estimateAiMessageTokens(retainedSummary);
      }
    }
  }

  final ordinaryBudget = messageBudget - summaryEnvelopeCost;
  if (ordinaryBudget <= 0 && retainedSummary != null) {
    return [_bridgeUserMessage, retainedSummary];
  }

  final selectedNewestFirst = <AiMessage>[];
  var used = 0;

  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (_isHistoricalSummary(message) ||
        (retainedSummary != null && _isBridgeUserMessage(message))) {
      continue;
    }
    final cost = estimateAiMessageTokens(message);

    if (selectedNewestFirst.isEmpty) {
      if (cost <= ordinaryBudget) {
        selectedNewestFirst.add(message);
        used += cost;
      } else {
        final trimmed = trimTextToTokenBudget(message.content, ordinaryBudget);
        if (trimmed.isNotEmpty) {
          selectedNewestFirst.add(
            AiMessage(
              role: message.role,
              content: trimmed,
              attachments: message.attachments,
            ),
          );
          used += TokenEstimator.estimate(trimmed);
        }
      }
      continue;
    }

    if (used + cost <= ordinaryBudget) {
      selectedNewestFirst.add(message);
      used += cost;
    }
  }

  final selected = selectedNewestFirst.reversed.toList();
  if (retainedSummary != null) {
    return [_bridgeUserMessage, retainedSummary, ...selected];
  }
  if (selected.isEmpty) return const [];
  return _ensureStartsWithUserWithinBudget(
    selected,
    usedTokens: used,
    messageBudget: messageBudget,
  );
}

bool _isHistoricalSummary(AiMessage message) =>
    message.role == 'assistant' &&
    message.content.trimLeft().startsWith('[历史摘要]');

bool _isBridgeUserMessage(AiMessage message) =>
    message.role == _bridgeUserMessage.role &&
    message.content == _bridgeUserMessage.content;

List<AiMessage> _ensureStartsWithUserWithinBudget(
  List<AiMessage> messages, {
  required int usedTokens,
  required int messageBudget,
}) {
  if (messages.isEmpty || messages.first.role != 'assistant') return messages;

  final mutable = [...messages];
  var used = usedTokens;
  final bridgeCost = estimateAiMessageTokens(_bridgeUserMessage);
  while (mutable.length > 1 && used + bridgeCost > messageBudget) {
    used -= estimateAiMessageTokens(mutable.removeAt(0));
  }
  if (used + bridgeCost <= messageBudget) {
    mutable.insert(0, _bridgeUserMessage);
  }
  return mutable;
}
