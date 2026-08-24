import 'dart:async';

import 'package:uuid/uuid.dart';

import '../ai/ai_protocol.dart';
import '../ai/ai_service.dart';
import '../database/app_database.dart';
import '../database/dao/message_dao.dart';
import 'context_budget_trimmer.dart';
import 'model_context_budget.dart';
import 'token_estimator.dart';

typedef ContextSummaryGenerator =
    Future<String> Function({
      required String protocol,
      required String baseUrl,
      required String apiKey,
      required String model,
      required String prompt,
    });

/// 上下文压缩器：把旧轮次合并成一个有界的滚动摘要，完整原文仍保存在本地。
class ContextCompressor {
  ContextCompressor(
    this._messageDao, {
    ContextSummaryGenerator? summaryGenerator,
  }) : _summaryGenerator = summaryGenerator ?? _generateSummaryWithAi;

  final MessageDao _messageDao;
  final ContextSummaryGenerator _summaryGenerator;

  static const _uuid = Uuid();
  static const _recentMessagesToKeep = 10;
  static const _maxCompressionPasses = 4;
  static const _maxStoredSummaryTokens = 1024;
  static final Map<String, Future<bool>> _inFlight = {};

  static const _summaryInstruction =
      '''你是一个对话长期记忆压缩器。请把下面的既有长期摘要与更近的旧对话合并成一个新的结构化摘要。必须保留：
1. 用户明确事实、人物设定、偏好与约束
2. 已确认的决定、结果、代码/项目标识和未完成事项
3. 关键问答的因果关系，以及后续回答需要引用的具体值
4. 冲突信息以较新的明确陈述为准，并标出仍不确定的内容

不要续写对话，不要回答用户问题，不要虚构。输出简洁中文，不超过 800 字。''';

  /// 达到阈值时执行滚动压缩。
  ///
  /// 同一会话的请求前压缩与回答后后台压缩可能相遇；共享同一个 Future，避免
  /// 重复调用模型并写出相互覆盖的摘要。
  Future<bool> compressIfNeeded({
    required String sessionId,
    int threshold = 2000,
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) {
    final running = _inFlight[sessionId];
    if (running != null) return running;

    late final Future<bool> operation;
    operation =
        _compressUntilWithinThreshold(
          sessionId: sessionId,
          threshold: threshold,
          protocol: protocol,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
        ).whenComplete(() {
          if (identical(_inFlight[sessionId], operation)) {
            _inFlight.remove(sessionId);
          }
        });
    _inFlight[sessionId] = operation;
    return operation;
  }

  Future<bool> _compressUntilWithinThreshold({
    required String sessionId,
    required int threshold,
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    var changed = false;
    for (var pass = 0; pass < _maxCompressionPasses; pass++) {
      final tokenCount = await _messageDao.getUnsummarizedTokenCount(sessionId);
      if (tokenCount <= threshold) break;

      final passChanged = await _compressOnePass(
        sessionId: sessionId,
        protocol: protocol,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
      );
      if (!passChanged) break;
      changed = true;
    }
    return changed;
  }

  Future<bool> _compressOnePass({
    required String sessionId,
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final summaries = await _messageDao.getSummaries(sessionId);
    final originals = await _messageDao.getUnsummarizedOriginals(sessionId);
    if (originals.length <= _recentMessagesToKeep) return false;

    final modelBudget = resolveModelContextBudget(
      protocol: protocol,
      modelName: model,
    );
    final sourceBudget = (modelBudget.maxInputTokens * 0.72)
        .floor()
        .clamp(1024, 80000)
        .toInt();
    final summaryBudget = (sourceBudget * 0.35).floor();

    final selectedSummaries = <Message>[];
    var summaryTokens = 0;
    for (final summary in summaries) {
      final rendered = _renderSummary(summary);
      final cost = TokenEstimator.estimate(rendered);
      if (selectedSummaries.isNotEmpty &&
          summaryTokens + cost > summaryBudget) {
        break;
      }
      if (cost > summaryBudget) break;
      selectedSummaries.add(summary);
      summaryTokens += cost;
    }

    // 极老版本可能已经积累了大量 summary。先层级折叠一部分摘要，再在下一
    // pass 合并原始消息；不能截断旧摘要后就把未读内容从远程记忆中删掉。
    final allSummariesFit = selectedSummaries.length == summaries.length;
    if (!allSummariesFit && selectedSummaries.isNotEmpty) {
      return _writeRollingSummary(
        sessionId: sessionId,
        summaries: selectedSummaries,
        originals: const [],
        protocol: protocol,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
      );
    }
    if (!allSummariesFit) return false;

    final candidates = originals.sublist(
      0,
      originals.length - _recentMessagesToKeep,
    );
    final selectedOriginals = <Message>[];
    var used = summaryTokens;
    for (final message in candidates) {
      final cost = TokenEstimator.estimate(_renderOriginal(message));
      if (used + cost > sourceBudget) break;
      selectedOriginals.add(message);
      used += cost;
    }
    if (selectedOriginals.isEmpty) return false;

    return _writeRollingSummary(
      sessionId: sessionId,
      summaries: selectedSummaries,
      originals: selectedOriginals,
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
    );
  }

  Future<bool> _writeRollingSummary({
    required String sessionId,
    required List<Message> summaries,
    required List<Message> originals,
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final source = StringBuffer();
    if (summaries.isNotEmpty) {
      source.writeln('【既有长期摘要】');
      for (final summary in summaries) {
        source.writeln(_renderSummary(summary));
      }
    }
    if (originals.isNotEmpty) {
      if (source.isNotEmpty) source.writeln();
      source.writeln('【需要并入的旧对话】');
      for (final message in originals) {
        source.writeln(_renderOriginal(message));
      }
    }

    final generated = await _summaryGenerator(
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      prompt: '$_summaryInstruction\n\n$source',
    );
    final summaryContent = trimTextToTokenBudget(
      generated.trim(),
      _maxStoredSummaryTokens,
    );
    if (summaryContent.isEmpty) return false;

    final firstSummary = summaries.firstOrNull;
    final lastSummary = summaries.lastOrNull;
    final firstOriginal = originals.firstOrNull;
    final lastOriginal = originals.lastOrNull;
    final summaryStartId =
        firstSummary?.summaryStartId ??
        firstOriginal?.id ??
        firstSummary?.id ??
        lastSummary?.id;
    final summaryEndId =
        lastOriginal?.id ??
        lastSummary?.summaryEndId ??
        lastSummary?.id ??
        firstOriginal?.id;
    if (summaryStartId == null || summaryEndId == null) return false;

    await _messageDao.replaceSummariesWithRollingSummary(
      summaryIdsToReplace: summaries.map((summary) => summary.id).toList(),
      originalMessageIds: originals.map((message) => message.id).toList(),
      id: _uuid.v4(),
      sessionId: sessionId,
      content: summaryContent,
      summaryStartId: summaryStartId,
      summaryEndId: summaryEndId,
      tokens: TokenEstimator.estimate(summaryContent),
    );
    return true;
  }

  String _renderSummary(Message summary) => '- ${summary.content.trim()}';

  String _renderOriginal(Message message) {
    final speaker = message.role == 'user' ? '用户' : 'AI';
    return '$speaker：${message.content.trim()}';
  }

  static Future<String> _generateSummaryWithAi({
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
  }) async {
    final buffer = StringBuffer();
    await for (final token in AiService.sendMessage(
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: [AiMessage(role: 'user', content: prompt)],
      systemPrompt: '你是一个对话长期记忆压缩器，只输出新的滚动摘要。',
    )) {
      if (token.content != null) buffer.write(token.content);
    }
    return buffer.toString();
  }
}
