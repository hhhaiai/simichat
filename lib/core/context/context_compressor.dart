import 'package:uuid/uuid.dart';
import '../ai/ai_protocol.dart';
import '../ai/ai_service.dart';
import '../database/dao/message_dao.dart';
import 'token_estimator.dart';

/// 上下文压缩器：当未压缩消息的 token 数超过阈值时，调用 AI 生成 summary
class ContextCompressor {
  final MessageDao _messageDao;
  static const _uuid = Uuid();

  /// 压缩提示词模板
  static const _summaryPrompt = '''你是一个对话摘要助手。请将以下对话历史压缩为结构化摘要，保留：
1. 核心议题和背景
2. 重要结论、决策、约定
3. 人物设定（如有）
4. 关键问答的来龙去脉

对话历史：
{messages}

请用简洁的中文输出摘要，不超过 500 字。''';

  ContextCompressor(this._messageDao);

  /// 检查是否需要压缩，如果需要则执行压缩
  /// 返回 true 表示执行了压缩
  Future<bool> compressIfNeeded({
    required String sessionId,
    int threshold = 2000,
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final tokenCount = await _messageDao.getUnsummarizedTokenCount(sessionId);
    if (tokenCount <= threshold) return false;

    await _doCompress(
      sessionId: sessionId,
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
    );
    return true;
  }

  Future<void> _doCompress({
    required String sessionId,
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final originals = await _messageDao.getUnsummarizedOriginals(sessionId);
    if (originals.length <= 10) return;

    // 保留最新 10 条不压缩
    final toCompress = originals.sublist(0, originals.length - 10);

    // 构建压缩用的对话文本
    final conversationText = toCompress
        .map((m) => '${m.role == "user" ? "用户" : "AI"}：${m.content}')
        .join('\n');

    final prompt = _summaryPrompt.replaceAll('{messages}', conversationText);

    // 调用 AI 生成 summary
    final buffer = StringBuffer();
    await for (final token in AiService.sendMessage(
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: [AiMessage(role: 'user', content: prompt)],
      systemPrompt: '你是一个对话摘要助手，擅长提炼关键信息。',
    )) {
      if (token.content != null) buffer.write(token.content);
      if (token.thinking != null) buffer.write(token.thinking);
    }

    final summaryContent = buffer.toString();
    if (summaryContent.isEmpty) return;

    // 写入 summary 消息
    final summaryId = _uuid.v4();
    await _messageDao.insertSummary(
      id: summaryId,
      sessionId: sessionId,
      content: summaryContent,
      summaryStartId: toCompress.first.id,
      summaryEndId: toCompress.last.id,
      tokens: TokenEstimator.estimate(summaryContent),
    );

    // 标记被压缩的消息
    await _messageDao.markAsSummarized(
      toCompress.map((m) => m.id).toList(),
    );
  }
}
