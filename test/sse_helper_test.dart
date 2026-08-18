import 'dart:convert';

import 'package:ai_chat_app/core/ai/sse_helper.dart';
import 'package:flutter_test/flutter_test.dart';

Stream<List<int>> _oneByteAtATime(String value) async* {
  final bytes = utf8.encode(value);
  for (final byte in bytes) {
    yield <int>[byte];
  }
}

void main() {
  group('SseIncrementalParser', () {
    test('decodes Chinese and emoji split at every UTF-8 byte', () async {
      final events = await parseSseStream(
        _oneByteAtATime('event: message\ndata: 你好 👋\n\n'),
      ).toList();

      expect(events, hasLength(1));
      expect(events.single.event, 'message');
      expect(events.single.eventType, 'message');
      expect(events.single.data, '你好 👋');
    });

    test(
      'joins multiple data lines and uses blank lines as boundaries',
      () async {
        final events = await parseSseStream(
          _oneByteAtATime(
            'event: delta\n'
            'data: first\n'
            'data: second\n'
            '\n'
            'data: third\n\n',
          ),
        ).toList();

        expect(events.map((event) => event.event), ['delta', null]);
        expect(events.map((event) => event.data), ['first\nsecond', 'third']);
      },
    );

    test('accepts LF, CRLF, and CR line endings', () async {
      final events = await parseSseStream(
        _oneByteAtATime(
          'data: lf\n\n'
          'data: crlf\r\n\r\n'
          'data: cr\r\r',
        ),
      ).toList();

      expect(events.map((event) => event.data), ['lf', 'crlf', 'cr']);
    });

    test(
      'ignores comment lines and flushes an event without a final blank line',
      () async {
        final events = await parseSseStream(
          _oneByteAtATime(': keep-alive\ndata: final payload'),
        ).toList();

        expect(events.map((event) => event.data), ['final payload']);
      },
    );

    test('does not emit a split [DONE] sentinel as a normal event', () async {
      final events = await parseSseStream(
        _oneByteAtATime('data: before\n\ndata: [DONE]\n\n'),
      ).toList();

      expect(events.map((event) => event.data), ['before']);
    });

    test('reports malformed UTF-8 as a safe protocol exception', () async {
      final stream = Stream<List<int>>.fromIterable(const [
        <int>[0xff],
      ]);

      await expectLater(
        parseSseStream(stream).toList(),
        throwsA(
          isA<ProtocolStreamException>()
              .having(
                (error) => error.kind,
                'kind',
                ProtocolStreamErrorKind.malformed,
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('0xff')),
              ),
        ),
      );
    });
  });
}
