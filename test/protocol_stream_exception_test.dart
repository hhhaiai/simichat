import 'package:ai_chat_app/core/ai/protocol_stream_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts credentials, URLs, local paths, and oversized diagnostics', () {
    final exception = ProtocolStreamException(
      'Bearer live-token sk-live-secret token=raw '
      'https://provider.example.test/error /Users/sanbo/private.json '
      '${'x' * 400}',
      protocol: 'test',
      kind: ProtocolStreamErrorKind.failed,
      code: 'provider_error',
    );

    expect(exception.message, isNot(contains('live-token')));
    expect(exception.message, isNot(contains('sk-live-secret')));
    expect(exception.message, isNot(contains('token=raw')));
    expect(exception.message, isNot(contains('https://provider.example.test')));
    expect(exception.message, isNot(contains('/Users/sanbo/private.json')));
    expect(exception.message.length, lessThanOrEqualTo(241));
    expect(exception.isTerminal, isTrue);
    expect(exception.retryable, isTrue);
  });

  test(
    'classifies safety and cancellation as non-retryable terminal errors',
    () {
      final safety = ProtocolStreamException(
        'blocked',
        protocol: 'gemini',
        kind: ProtocolStreamErrorKind.safety,
      );
      final cancelled = ProtocolStreamException(
        'cancelled',
        protocol: 'sse',
        kind: ProtocolStreamErrorKind.cancelled,
        retryable: false,
      );

      expect(safety.isSafetyBlock, isTrue);
      expect(safety.retryable, isFalse);
      expect(cancelled.isCancellation, isTrue);
      expect(cancelled.retryable, isFalse);
    },
  );
}
