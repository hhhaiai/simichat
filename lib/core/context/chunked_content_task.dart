import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'text_chunker.dart';

/// 长文本任务的处理模式。
///
/// `mapReduce` 用于总结、问答、分析、提取等需要跨片段整合的请求；
/// `orderedTransform` 用于翻译、改写、润色和格式转换等必须保留原文顺序的
/// 请求。值直接写入本地数据库，因此名称不可随意变更。
enum ChunkedContentStrategy { mapReduce, orderedTransform }

extension ChunkedContentStrategyX on ChunkedContentStrategy {
  String get label => switch (this) {
    ChunkedContentStrategy.mapReduce => '分析整合',
    ChunkedContentStrategy.orderedTransform => '顺序处理',
  };

  static ChunkedContentStrategy parse(String? raw) {
    final normalized = raw?.trim();
    return ChunkedContentStrategy.values.firstWhere(
      (value) => value.name == normalized,
      orElse: () => ChunkedContentStrategy.mapReduce,
    );
  }
}

/// 持久化分批任务的状态。
///
/// `preparing` 只允许本地读文件和切块；`running` 才会发送 chunk；
/// `reducing` 表示 map/reduce 的最终整合阶段；终态不会被过期 worker 回写。
enum ChunkedContentTaskStatus {
  preparing,
  running,
  reducing,
  completed,
  failed,
  cancelled,
}

extension ChunkedContentTaskStatusX on ChunkedContentTaskStatus {
  bool get isTerminal => switch (this) {
    ChunkedContentTaskStatus.completed ||
    ChunkedContentTaskStatus.failed ||
    ChunkedContentTaskStatus.cancelled => true,
    _ => false,
  };

  String get label => switch (this) {
    ChunkedContentTaskStatus.preparing => '正在准备长内容',
    ChunkedContentTaskStatus.running => '正在处理',
    ChunkedContentTaskStatus.reducing => '正在生成最终回答',
    ChunkedContentTaskStatus.completed => '已完成',
    ChunkedContentTaskStatus.failed => '处理失败，可继续或重试',
    ChunkedContentTaskStatus.cancelled => '已停止，可继续或重试',
  };

  static ChunkedContentTaskStatus parse(String? raw) {
    final normalized = raw?.trim();
    return ChunkedContentTaskStatus.values.firstWhere(
      (value) => value.name == normalized,
      orElse: () => ChunkedContentTaskStatus.failed,
    );
  }
}

/// 任务创建时保存的无凭据路由快照。
///
/// API Key 仅从当前受保护的渠道配置即时读取，绝不会进入这个 JSON。快照保存
/// 协议、模型、切块预算和所有源附件 ID，供进程被回收后验证任务是否仍可继续。
class ChunkedContentRequestSnapshot {
  const ChunkedContentRequestSnapshot({
    required this.protocol,
    required this.modelName,
    required this.maxInputTokens,
    required this.targetChunkTokens,
    required this.overlapTokens,
    required this.sourceAttachmentIds,
  });

  final String protocol;
  final String modelName;
  final int maxInputTokens;
  final int targetChunkTokens;
  final int overlapTokens;
  final List<String> sourceAttachmentIds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'protocol': protocol,
    'model_name': modelName,
    'max_input_tokens': maxInputTokens,
    'target_chunk_tokens': targetChunkTokens,
    'overlap_tokens': overlapTokens,
    'source_attachment_ids': sourceAttachmentIds,
  };

  String encode() => jsonEncode(toJson());

  factory ChunkedContentRequestSnapshot.decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      final sourceIds = (decoded['source_attachment_ids'] as List? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false);
      final maxInputTokens = _positiveInt(decoded['max_input_tokens']);
      final targetChunkTokens = _positiveInt(decoded['target_chunk_tokens']);
      final overlapTokens = _nonNegativeInt(decoded['overlap_tokens']);
      if (sourceIds.isEmpty ||
          maxInputTokens == null ||
          targetChunkTokens == null ||
          overlapTokens == null ||
          overlapTokens >= targetChunkTokens) {
        throw const FormatException();
      }
      return ChunkedContentRequestSnapshot(
        protocol: _requiredString(decoded['protocol']),
        modelName: _requiredString(decoded['model_name']),
        maxInputTokens: maxInputTokens,
        targetChunkTokens: targetChunkTokens,
        overlapTokens: overlapTokens,
        sourceAttachmentIds: sourceIds,
      );
    } on Object {
      throw const FormatException('分批任务请求快照损坏，无法继续');
    }
  }

  static String _requiredString(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    if (normalized.isEmpty || normalized.length > 256) {
      throw const FormatException();
    }
    return normalized;
  }

  static int? _positiveInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    return parsed == null || parsed <= 0 ? null : parsed;
  }

  static int? _nonNegativeInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    return parsed == null || parsed < 0 ? null : parsed;
  }
}

/// 一个 chunk 的持久化执行结果。原文不重复写入 SQLite；它始终来自应用私有
/// 附件，数据库只保存可验证范围、哈希、重试次数和模型中间结果。
class ChunkedContentChunkResult {
  const ChunkedContentChunkResult({
    required this.chunkIndex,
    required this.startOffset,
    required this.endOffset,
    required this.sha256,
    required this.estimatedTokens,
    this.attempts = 0,
    this.result,
  });

  final int chunkIndex;
  final int startOffset;
  final int endOffset;
  final String sha256;
  final int estimatedTokens;
  final int attempts;
  final String? result;

  bool get isCompleted => result?.trim().isNotEmpty == true;

  ChunkedContentChunkResult copyWith({int? attempts, String? result}) {
    return ChunkedContentChunkResult(
      chunkIndex: chunkIndex,
      startOffset: startOffset,
      endOffset: endOffset,
      sha256: sha256,
      estimatedTokens: estimatedTokens,
      attempts: attempts ?? this.attempts,
      result: result ?? this.result,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'chunk_index': chunkIndex,
    'start_offset': startOffset,
    'end_offset': endOffset,
    'sha256': sha256,
    'estimated_tokens': estimatedTokens,
    'attempts': attempts,
    if (result != null && result!.trim().isNotEmpty) 'result': result,
  };

  factory ChunkedContentChunkResult.fromTextChunk(TextChunk chunk) {
    return ChunkedContentChunkResult(
      chunkIndex: chunk.chunkIndex,
      startOffset: chunk.startOffset,
      endOffset: chunk.endOffset,
      sha256: chunk.sha256,
      estimatedTokens: chunk.estimatedTokens,
    );
  }

  factory ChunkedContentChunkResult.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException();
    final chunkIndex = _nonNegativeInt(raw['chunk_index']);
    final startOffset = _nonNegativeInt(raw['start_offset']);
    final endOffset = _nonNegativeInt(raw['end_offset']);
    final estimatedTokens = _nonNegativeInt(raw['estimated_tokens']);
    final attempts = _nonNegativeInt(raw['attempts']) ?? 0;
    final sha = raw['sha256']?.toString().trim() ?? '';
    final result = raw['result']?.toString();
    if (chunkIndex == null ||
        startOffset == null ||
        endOffset == null ||
        endOffset < startOffset ||
        estimatedTokens == null ||
        sha.length != 64 ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha)) {
      throw const FormatException();
    }
    return ChunkedContentChunkResult(
      chunkIndex: chunkIndex,
      startOffset: startOffset,
      endOffset: endOffset,
      sha256: sha.toLowerCase(),
      estimatedTokens: estimatedTokens,
      attempts: attempts,
      result: result == null || result.trim().isEmpty ? null : result,
    );
  }

  static int? _nonNegativeInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    return parsed == null || parsed < 0 ? null : parsed;
  }
}

String encodeChunkedContentResults(Iterable<ChunkedContentChunkResult> values) {
  final sorted = values.toList()
    ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
  return jsonEncode(sorted.map((value) => value.toJson()).toList());
}

List<ChunkedContentChunkResult> decodeChunkedContentResults(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException();
    final values =
        decoded.map(ChunkedContentChunkResult.fromJson).toList(growable: false)
          ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    final indexes = <int>{};
    for (final value in values) {
      if (!indexes.add(value.chunkIndex)) throw const FormatException();
    }
    return List<ChunkedContentChunkResult>.unmodifiable(values);
  } on Object {
    throw const FormatException('分批任务中间结果损坏，无法继续');
  }
}

/// 同一输入和配置必须产生稳定的切块计划，恢复时会验证每段 SHA-256，避免
/// 源文件被替换后把旧中间结果交给新的内容。
List<ChunkedContentChunkResult> createChunkedContentPlan({
  required String taskId,
  required String sourceAttachmentId,
  required String source,
  required ChunkedContentRequestSnapshot snapshot,
  TextChunker chunker = const TextChunker(),
}) {
  final chunks = chunker.chunk(
    source,
    TextChunkingConfig(
      targetChunkTokens: snapshot.targetChunkTokens,
      overlapTokens: snapshot.overlapTokens,
    ),
    batchId: taskId,
    sourceAttachmentId: sourceAttachmentId,
  );
  return List<ChunkedContentChunkResult>.unmodifiable(
    chunks.map(ChunkedContentChunkResult.fromTextChunk),
  );
}

/// 选择任务策略。显式传入的 [requested] 永远优先于启发式，避免用户在
/// “翻译后总结”这类复合请求中被静默改写处理方式。
ChunkedContentStrategy resolveChunkedContentStrategy(
  String prompt, {
  ChunkedContentStrategy? requested,
}) {
  if (requested != null) return requested;
  final normalized = prompt.trim().toLowerCase();
  const orderedSignals = <String>[
    '翻译',
    '译成',
    '改写',
    '润色',
    '重写',
    '格式转换',
    '转成',
    '逐段',
    '保持原文顺序',
    'translate',
    'rewrite',
    'rephrase',
    'proofread',
    'format conversion',
  ];
  if (orderedSignals.any(normalized.contains)) {
    return ChunkedContentStrategy.orderedTransform;
  }
  return ChunkedContentStrategy.mapReduce;
}

/// 长内容默认切块预算。模型的完整窗口不能直接作为 chunk 大小：每次请求还
/// 需要放入用户问题、运行指令和安全余量。小窗口模型仍使用其 45%，但永不
/// 产生零或负预算。
int resolveChunkedContentTargetChunkTokens(int maxInputTokens) {
  if (maxInputTokens <= 0) {
    throw ArgumentError.value(maxInputTokens, 'maxInputTokens', '必须大于 0');
  }
  const maxBatchChunkTokens = 6000;
  const minimumChunkTokens = 1000;
  final dynamicTarget = (maxInputTokens * 0.45).floor();
  return dynamicTarget
      .clamp(
        maxInputTokens < minimumChunkTokens ? 1 : minimumChunkTokens,
        maxBatchChunkTokens,
      )
      .toInt();
}

/// 普通分析任务的重叠仅帮助跨段证据理解；顺序型变换为避免最终文本重复，
/// 强制使用零重叠。
int resolveChunkedContentOverlapTokens(ChunkedContentStrategy strategy) {
  return strategy == ChunkedContentStrategy.orderedTransform ? 0 : 160;
}

/// 将一个或多个附件正文做成可安全传递给分块器的源文本。用户问题和附件
/// 正文严格分离；附件内的内容只作为数据，后续请求也会再次明确标出边界。
String buildChunkedContentSource({
  required Iterable<String> contents,
  Iterable<String> fileNames = const <String>[],
}) {
  final contentValues = contents.toList(growable: false);
  final names = fileNames.toList(growable: false);
  final buffer = StringBuffer();
  for (var index = 0; index < contentValues.length; index++) {
    final content = contentValues[index];
    if (content.isEmpty) continue;
    if (buffer.isNotEmpty) buffer.write('\n\n');
    final rawName = index < names.length ? names[index].trim() : '';
    final name = rawName.isEmpty ? '文本附件 ${index + 1}' : rawName;
    buffer
      ..writeln('【附件 ${index + 1}：$name】')
      ..write(content);
  }
  return buffer.toString();
}

/// 用作恢复前的源一致性检查。不是安全机密，也不替代每一个 TextChunk 的哈希。
String chunkedContentSourceSha256(String source) =>
    sha256.convert(utf8.encode(source)).toString();
