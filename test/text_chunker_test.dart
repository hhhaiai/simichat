import 'package:ai_chat_app/core/context/text_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextChunker', () {
    test(
      'splits long markdown at heading boundaries and preserves exact source',
      () {
        const source = '''# 第一章
这里是第一章的正文，包含多个句子。这里是第一章的补充。

# 第二章
这里是第二章的正文，包含多个句子。这里是第二章的补充。

# 第三章
这里是第三章的正文，包含多个句子。这里是第三章的补充。
''';
        final chunks = const TextChunker().chunk(
          source,
          const TextChunkingConfig(targetChunkTokens: 120, overlapTokens: 0),
        );

        expect(chunks, hasLength(greaterThanOrEqualTo(2)));
        expect(chunks.map((chunk) => chunk.text).join(), source);
        expect(chunks.first.text, startsWith('# 第一章'));
        expect(
          chunks.skip(1).every((chunk) => chunk.text.startsWith('# ')),
          isTrue,
        );
        expect(chunks[0].endOffset, chunks[1].startOffset);
      },
    );

    test('keeps complete fenced code blocks together where they fit', () {
      const source = '''# 示例

```dart
void main() {
  print('hello');
  print('world');
}
```

## 说明
代码块之后的说明段落。代码块之后的说明段落。代码块之后的说明段落。代码块之后的说明段落。
''';
      final chunks = const TextChunker().chunk(
        source,
        const TextChunkingConfig(targetChunkTokens: 120, overlapTokens: 0),
      );

      expect(chunks, hasLength(2));
      expect(chunks.first.text, contains('```dart'));
      expect(chunks.first.text, contains('```\n'));
      expect(chunks.first.text, isNot(contains('## 说明')));
      expect(chunks[1].text, startsWith('## 说明'));
    });

    test('adds bounded overlap while retaining stable source metadata', () {
      final source = List<String>.generate(
        40,
        (index) => '第 $index 段用于验证重叠和偏移。',
      ).join('\n\n');
      final chunks = const TextChunker().chunk(
        source,
        const TextChunkingConfig(targetChunkTokens: 45, overlapTokens: 8),
        sourceAttachmentId: 'paste-1',
        batchId: 'batch-1',
      );

      expect(chunks, hasLength(greaterThan(2)));
      for (var index = 0; index < chunks.length; index++) {
        final chunk = chunks[index];
        expect(chunk.batchId, 'batch-1');
        expect(chunk.sourceAttachmentId, 'paste-1');
        expect(chunk.chunkIndex, index);
        expect(chunk.totalChunks, chunks.length);
        expect(chunk.sha256, hasLength(64));
        if (index > 0) {
          expect(chunk.startOffset, lessThan(chunks[index - 1].endOffset));
          expect(
            chunk.startOffset,
            greaterThanOrEqualTo(chunks[index - 1].startOffset),
          );
        }
      }
      expect(chunks.last.endOffset, source.length);
    });

    test('does not split a surrogate pair at hard boundaries', () {
      final source = '${'a' * 30}🙂${'b' * 30}';
      final chunks = const TextChunker().chunk(
        source,
        const TextChunkingConfig(targetChunkTokens: 20, overlapTokens: 0),
      );

      expect(chunks.map((chunk) => chunk.text).join(), source);
      expect(chunks.every((chunk) => !chunk.text.endsWith('\uD83D')), isTrue);
    });
  });
}
