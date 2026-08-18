import 'dart:io';

import 'package:ai_chat_app/core/ai/file_content_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'simichat_file_content_extractor_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'extracts bounded UTF-8 text without using the filename as content',
    () async {
      final source = File('${tempDirectory.path}/notes.md');
      const text = '# Actual document\n唯一校验文本：file-content-7f8b2c';
      await source.writeAsString(text, flush: true);

      final result = await extractFileContent(
        path: source.path,
        fileName: 'notes.md',
      );

      expect(result.text, text);
      expect(result.content, text);
      expect(result.text, isNot(contains('notes.md')));
      expect(result.byteLength, greaterThan(0));
      expect(result.lineCount, 2);
    },
  );

  test('supports common structured text and code extensions', () async {
    for (final name in ['data.json', 'rows.csv', 'config.yaml', 'main.dart']) {
      final source = File('${tempDirectory.path}/$name');
      await source.writeAsString('value-for-$name', flush: true);

      final result = await extractFileContent(
        path: source.path,
        fileName: name,
      );

      expect(result.text, 'value-for-$name');
    }
  });

  test('enforces byte, line-count, and line-length limits', () async {
    final source = File('${tempDirectory.path}/limits.txt');
    await source.writeAsString('1234567890\nsecond\nthird', flush: true);

    expect(
      () => extractFileContent(path: source.path, maxBytes: 5),
      throwsA(
        isA<FileContentExtractionException>().having(
          (error) => error.kind,
          'kind',
          FileContentExtractionFailureKind.tooLarge,
        ),
      ),
    );
    expect(
      () => extractFileContent(path: source.path, maxLines: 2),
      throwsA(
        isA<FileContentExtractionException>().having(
          (error) => error.kind,
          'kind',
          FileContentExtractionFailureKind.tooManyLines,
        ),
      ),
    );
    expect(
      () => extractFileContent(path: source.path, maxLineBytes: 5),
      throwsA(
        isA<FileContentExtractionException>().having(
          (error) => error.kind,
          'kind',
          FileContentExtractionFailureKind.lineTooLong,
        ),
      ),
    );
  });

  test('rejects invalid UTF-8 and binary content', () async {
    final invalidUtf8 = File('${tempDirectory.path}/invalid.txt');
    await invalidUtf8.writeAsBytes([0x66, 0xFF, 0x67], flush: true);
    expect(
      () => extractFileContent(path: invalidUtf8.path),
      throwsA(
        isA<FileContentExtractionException>().having(
          (error) => error.kind,
          'kind',
          FileContentExtractionFailureKind.invalidUtf8,
        ),
      ),
    );

    final binary = File('${tempDirectory.path}/payload.dat');
    await binary.writeAsBytes([0x41, 0x00, 0x42, 0x43], flush: true);
    expect(
      () => extractFileContent(path: binary.path),
      throwsA(
        isA<FileContentExtractionException>().having(
          (error) => error.kind,
          'kind',
          FileContentExtractionFailureKind.binary,
        ),
      ),
    );
  });

  test('rejects PDF and video with recoverable, explicit errors', () async {
    final pdfError = await _captureError(
      () => extractFileContent(
        path: '${tempDirectory.path}/report.pdf',
        fileName: 'report.pdf',
        attachmentType: 'pdf',
      ),
    );
    expect(pdfError.kind, FileContentExtractionFailureKind.unsupportedType);
    expect(pdfError.message, contains('PDF File API'));
    expect(pdfError.message, contains('保留附件'));

    final videoError = await _captureError(
      () => extractFileContent(
        path: '${tempDirectory.path}/movie.mp4',
        fileName: 'movie.mp4',
        attachmentType: 'video',
      ),
    );
    expect(videoError.kind, FileContentExtractionFailureKind.unsupportedType);
    expect(videoError.message, contains('视频'));
    expect(videoError.message, contains('保留附件'));
  });

  test(
    'path diagnostics do not expose absolute paths or raw secrets',
    () async {
      final error = await _captureError(
        () => extractFileContent(
          path: '${tempDirectory.path}/missing.txt',
          fileName: '/Users/alice/Bearer super-secret-token.txt',
        ),
      );

      expect(error.kind, FileContentExtractionFailureKind.missing);
      expect(error.message, isNot(contains(tempDirectory.path)));
      expect(error.message, isNot(contains('super-secret-token')));
      expect(error.fileName, isNot(contains('/Users/alice')));
      expect(error.fileName, contains('Bearer ***'));
    },
  );
}

Future<FileContentExtractionException> _captureError(
  Future<Object> Function() action,
) async {
  try {
    await action();
  } on FileContentExtractionException catch (error) {
    return error;
  }
  fail('expected FileContentExtractionException');
}
