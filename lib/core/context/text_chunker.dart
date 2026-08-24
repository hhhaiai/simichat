import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'token_estimator.dart';

/// 分批长内容的切分参数。实际任务应根据有效上下文预算计算
/// [targetChunkTokens]，而不是使用固定字符数。
class TextChunkingConfig {
  const TextChunkingConfig({
    required this.targetChunkTokens,
    this.overlapTokens = 0,
  }) : assert(targetChunkTokens > 0),
       assert(overlapTokens >= 0),
       assert(overlapTokens < targetChunkTokens);

  final int targetChunkTokens;
  final int overlapTokens;
}

/// 一个可恢复批次的不可变文本片段。
class TextChunk {
  const TextChunk({
    required this.batchId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.sourceAttachmentId,
    required this.startOffset,
    required this.endOffset,
    required this.text,
    required this.estimatedTokens,
    required this.sha256,
  });

  final String batchId;
  final int chunkIndex;
  final int totalChunks;
  final String sourceAttachmentId;
  final int startOffset;
  final int endOffset;
  final String text;
  final int estimatedTokens;
  final String sha256;
}

class _Boundary {
  const _Boundary(this.offset, this.priority);

  final int offset;
  final int priority;
}

class _OffsetRange {
  const _OffsetRange(this.start, this.end);

  final int start;
  final int end;

  bool contains(int offset) => offset >= start && offset < end;
}

/// 面向长文附件的内容切分器。
///
/// 不以“固定 N 个字符”作为正常路径：每个 chunk 先根据 token 预算找出可
/// 达到的最大位置，再优先在 H1/H2、代码围栏、段落、行和句子边界切分。
/// 单个代码块本身超过预算时才会退化为安全的 code-point 边界硬切。
class TextChunker {
  const TextChunker();

  List<TextChunk> chunk(
    String source,
    TextChunkingConfig config, {
    String batchId = '',
    String sourceAttachmentId = '',
  }) {
    if (source.isEmpty) return const <TextChunk>[];
    final boundaries = _buildBoundaries(source);
    final raw = <_RawChunk>[];
    var start = 0;
    while (start < source.length) {
      final maxEnd = _maxEndWithinTokenBudget(
        source,
        start,
        config.targetChunkTokens,
      );
      var end = maxEnd >= source.length
          ? source.length
          : _chooseNaturalBoundary(
              start: start,
              maxEnd: maxEnd,
              boundaries: boundaries,
            );
      if (end == null || end <= start) end = maxEnd;
      end = _safeBoundaryAtOrBefore(source, end);
      if (end <= start) end = _nextCodePointBoundary(source, start);
      final text = source.substring(start, end);
      raw.add(
        _RawChunk(
          startOffset: start,
          endOffset: end,
          text: text,
          estimatedTokens: TokenEstimator.estimate(text),
        ),
      );
      if (end >= source.length) break;
      final nextStart = config.overlapTokens == 0
          ? end
          : _overlapStart(
              source: source,
              chunkStart: start,
              chunkEnd: end,
              overlapTokens: config.overlapTokens,
            );
      // 极小预算 + 大 overlap 时不能重复同一个 range 并无限循环。无 overlap
      // 时 `nextStart == end` 是正常的连续切分，不能额外跳过一个字符。
      start = nextStart <= start
          ? _nextCodePointBoundary(source, start)
          : nextStart;
    }

    final total = raw.length;
    return List<TextChunk>.unmodifiable([
      for (var index = 0; index < raw.length; index++)
        TextChunk(
          batchId: batchId,
          chunkIndex: index,
          totalChunks: total,
          sourceAttachmentId: sourceAttachmentId,
          startOffset: raw[index].startOffset,
          endOffset: raw[index].endOffset,
          text: raw[index].text,
          estimatedTokens: raw[index].estimatedTokens,
          sha256: sha256.convert(utf8.encode(raw[index].text)).toString(),
        ),
    ]);
  }

  int _maxEndWithinTokenBudget(String source, int start, int budget) {
    if (TokenEstimator.estimate(source.substring(start)) <= budget) {
      return source.length;
    }
    var low = _nextCodePointBoundary(source, start);
    var high = source.length;
    var best = start;
    while (low <= high) {
      var mid = (low + high) ~/ 2;
      mid = _safeBoundaryAtOrBefore(source, mid);
      if (mid <= start) mid = _nextCodePointBoundary(source, start);
      final tokens = TokenEstimator.estimate(source.substring(start, mid));
      if (tokens <= budget) {
        best = mid;
        low = _nextCodePointBoundary(source, mid);
      } else {
        high = _safeBoundaryAtOrBefore(source, mid - 1);
      }
    }
    return best > start ? best : _nextCodePointBoundary(source, start);
  }

  int? _chooseNaturalBoundary({
    required int start,
    required int maxEnd,
    required List<_Boundary> boundaries,
  }) {
    _Boundary? selected;
    for (final boundary in boundaries) {
      if (boundary.offset <= start || boundary.offset > maxEnd) continue;
      if (selected == null ||
          boundary.priority > selected.priority ||
          (boundary.priority == selected.priority &&
              boundary.offset > selected.offset)) {
        selected = boundary;
      }
    }
    return selected?.offset;
  }

  int _overlapStart({
    required String source,
    required int chunkStart,
    required int chunkEnd,
    required int overlapTokens,
  }) {
    final totalTokens = TokenEstimator.estimate(
      source.substring(chunkStart, chunkEnd),
    );
    if (totalTokens <= overlapTokens) return chunkStart;
    var low = chunkStart + 1;
    var high = chunkEnd;
    var best = chunkEnd;
    while (low <= high) {
      var mid = (low + high) ~/ 2;
      mid = _safeBoundaryAtOrBefore(source, mid);
      if (mid <= chunkStart) mid = _nextCodePointBoundary(source, chunkStart);
      final suffixTokens = TokenEstimator.estimate(
        source.substring(mid, chunkEnd),
      );
      if (suffixTokens <= overlapTokens) {
        best = mid;
        high = _safeBoundaryAtOrBefore(source, mid - 1);
      } else {
        low = _nextCodePointBoundary(source, mid);
      }
    }
    if (best <= chunkStart) return _nextCodePointBoundary(source, chunkStart);
    // 有配置重叠时至少保留一个完整 code point；二分在极短 ASCII 后缀上
    // 可能直接命中 chunkEnd，不能静默退化为零重叠。
    return best >= chunkEnd
        ? _previousCodePointBoundary(source, chunkEnd)
        : best;
  }

  List<_Boundary> _buildBoundaries(String source) {
    final priorityByOffset = <int, int>{};
    void add(int offset, int priority) {
      if (offset <= 0 || offset >= source.length) return;
      final safeOffset = _safeBoundaryAtOrBefore(source, offset);
      if (safeOffset <= 0 || safeOffset >= source.length) return;
      final existing = priorityByOffset[safeOffset] ?? 0;
      if (priority > existing) priorityByOffset[safeOffset] = priority;
    }

    final fencedRanges = _fencedCodeRanges(source);
    var lineStart = 0;
    while (lineStart < source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline == -1 ? source.length : newline + 1;
      final line = source.substring(lineStart, lineEnd);
      final trimmed = line.trim();
      final insideCode = fencedRanges.any((range) => range.contains(lineStart));
      if (!insideCode) {
        if (RegExp(r'^#{1,2}\s+').hasMatch(trimmed)) add(lineStart, 5);
        if (trimmed.isEmpty) add(lineEnd, 3);
        add(lineEnd, 2);
      } else if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        // 完整代码围栏优先级仅次于标题，防止在 block 内的普通换行处分片。
        add(lineEnd, 4);
      }
      lineStart = lineEnd;
    }

    for (var index = 0; index < source.length; index++) {
      if (fencedRanges.any((range) => range.contains(index))) continue;
      final unit = source.codeUnitAt(index);
      if (unit == 0x002E || // .
          unit == 0x0021 || // !
          unit == 0x003F || // ?
          unit == 0x3002 || // 。
          unit == 0xFF01 || // ！
          unit == 0xFF1F || // ？
          unit == 0xFF1B) {
        // ；
        add(index + 1, 1);
      }
    }
    final boundaries =
        priorityByOffset.entries
            .map((entry) => _Boundary(entry.key, entry.value))
            .toList()
          ..sort((a, b) => a.offset.compareTo(b.offset));
    return List<_Boundary>.unmodifiable(boundaries);
  }

  List<_OffsetRange> _fencedCodeRanges(String source) {
    final ranges = <_OffsetRange>[];
    int? fenceStart;
    String? fence;
    var lineStart = 0;
    while (lineStart < source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline == -1 ? source.length : newline + 1;
      final trimmed = source.substring(lineStart, lineEnd).trimLeft();
      final marker = trimmed.startsWith('```')
          ? '```'
          : trimmed.startsWith('~~~')
          ? '~~~'
          : null;
      if (fenceStart == null && marker != null) {
        fenceStart = lineStart;
        fence = marker;
      } else if (fenceStart != null && marker == fence) {
        ranges.add(_OffsetRange(fenceStart, lineEnd));
        fenceStart = null;
        fence = null;
      }
      lineStart = lineEnd;
    }
    // 未闭合代码围栏也视为代码区域。它可以被最后的硬切分割，但不能被一条
    // “普通换行”边界错误地切开。
    if (fenceStart != null) ranges.add(_OffsetRange(fenceStart, source.length));
    return List<_OffsetRange>.unmodifiable(ranges);
  }

  int _safeBoundaryAtOrBefore(String source, int offset) {
    var safe = offset.clamp(0, source.length).toInt();
    if (safe > 0 &&
        safe < source.length &&
        _isHighSurrogate(source.codeUnitAt(safe - 1)) &&
        _isLowSurrogate(source.codeUnitAt(safe))) {
      safe--;
    }
    return safe;
  }

  int _nextCodePointBoundary(String source, int offset) {
    var next = (offset + 1).clamp(0, source.length).toInt();
    if (next < source.length &&
        _isHighSurrogate(source.codeUnitAt(next - 1)) &&
        _isLowSurrogate(source.codeUnitAt(next))) {
      next++;
    }
    return next;
  }

  int _previousCodePointBoundary(String source, int offset) {
    var previous = (offset - 1).clamp(0, source.length).toInt();
    if (previous > 0 &&
        previous < source.length &&
        _isLowSurrogate(source.codeUnitAt(previous)) &&
        _isHighSurrogate(source.codeUnitAt(previous - 1))) {
      previous--;
    }
    return previous;
  }

  bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
  bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
}

class _RawChunk {
  const _RawChunk({
    required this.startOffset,
    required this.endOffset,
    required this.text,
    required this.estimatedTokens,
  });

  final int startOffset;
  final int endOffset;
  final String text;
  final int estimatedTokens;
}
