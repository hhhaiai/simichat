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

  final selectedNewestFirst = <AiMessage>[];
  var used = 0;

  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    final cost = estimateAiMessageTokens(message);

    if (selectedNewestFirst.isEmpty) {
      if (cost <= messageBudget) {
        selectedNewestFirst.add(message);
        used += cost;
      } else {
        final trimmed = trimTextToTokenBudget(message.content, messageBudget);
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

    if (used + cost <= messageBudget) {
      selectedNewestFirst.add(message);
      used += cost;
    }
  }

  final selected = selectedNewestFirst.reversed.toList();
  if (selected.isEmpty) return const [];
  return _ensureStartsWithUserWithinBudget(
    selected,
    usedTokens: used,
    messageBudget: messageBudget,
  );
}

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
