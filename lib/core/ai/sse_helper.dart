import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'http_helper.dart';
import 'protocol_stream_exception.dart';

export 'api_endpoint_resolver.dart';
export 'protocol_stream_exception.dart';

/// A parsed Server-Sent Event.
///
/// [data] is the SSE payload after all data lines have been joined with a
/// newline. [event] is preserved when the server sends an event field.
class SseEvent {
  final String data;
  final String? event;

  const SseEvent(this.data, {this.event});

  String? get eventType => event;
}

/// SSE request configuration.
class SseRequestConfig {
  final String url;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
  final CancelToken? cancelToken;

  const SseRequestConfig({
    required this.url,
    required this.headers,
    required this.body,
    this.cancelToken,
  });
}

/// Stateful text parser used by [parseSseStream].
///
/// Keeping this parser public makes byte/chunk boundary behavior directly
/// testable without opening a network socket.
class SseIncrementalParser {
  String _lineBuffer = '';
  String? _eventName;
  final List<String> _dataLines = [];
  bool _done = false;

  bool get done => _done;

  /// Feed already UTF-8-decoded text and return complete events.
  List<SseEvent> addText(String text) {
    if (_done || text.isEmpty) return const [];
    _lineBuffer += text;
    final events = <SseEvent>[];

    while (!_done) {
      var newlineIndex = -1;
      var newlineLength = 1;
      for (var index = 0; index < _lineBuffer.length; index++) {
        final codeUnit = _lineBuffer.codeUnitAt(index);
        if (codeUnit == 0x0a) {
          newlineIndex = index;
          newlineLength = 1;
          break;
        }
        if (codeUnit == 0x0d) {
          // Keep a trailing CR until the next chunk so a split CRLF pair is
          // treated as one line ending rather than an empty extra line.
          if (index == _lineBuffer.length - 1) break;
          newlineIndex = index;
          newlineLength = _lineBuffer.codeUnitAt(index + 1) == 0x0a ? 2 : 1;
          break;
        }
      }
      if (newlineIndex < 0) break;

      final line = _lineBuffer.substring(0, newlineIndex);
      _lineBuffer = _lineBuffer.substring(newlineIndex + newlineLength);
      final event = _consumeLine(line);
      if (event != null) events.add(event);
    }
    return events;
  }

  /// Finish the stream and dispatch a final event without a blank line.
  List<SseEvent> finish() {
    if (_done) return const [];
    final events = <SseEvent>[];
    if (_lineBuffer.isNotEmpty) {
      final trailing = _lineBuffer.endsWith('\r')
          ? _lineBuffer.substring(0, _lineBuffer.length - 1)
          : _lineBuffer;
      _lineBuffer = '';
      final event = _consumeLine(trailing);
      if (event != null) events.add(event);
    }
    if (!_done) {
      final event = _dispatch();
      if (event != null) events.add(event);
    }
    return events;
  }

  SseEvent? _consumeLine(String line) {
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return null;

    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'data':
        _dataLines.add(value);
      case 'event':
        _eventName = value;
      // id/retry are intentionally ignored until callers need them. They do
      // not affect the data/event contract used by the protocol adapters.
      case 'id':
      case 'retry':
      default:
        break;
    }
    return null;
  }

  SseEvent? _dispatch() {
    if (_dataLines.isEmpty && _eventName == null) return null;
    final data = _dataLines.join('\n');
    final eventName = _eventName;
    _dataLines.clear();
    _eventName = null;

    if (data.trim() == '[DONE]') {
      _done = true;
      return null;
    }
    return SseEvent(data, event: eventName);
  }
}

/// Parse a byte stream using an incremental UTF-8 decoder and SSE event
/// boundaries. UTF-8 characters may be split at any byte and data may span
/// multiple data lines.
Stream<SseEvent> parseSseStream(Stream<List<int>> byteStream) async* {
  final parser = SseIncrementalParser();
  try {
    await for (final text in byteStream.transform(utf8.decoder)) {
      for (final event in parser.addText(text)) {
        yield event;
      }
      if (parser.done) return;
    }
    for (final event in parser.finish()) {
      yield event;
    }
  } on FormatException catch (error) {
    throw ProtocolStreamException(
      'SSE UTF-8 数据无效: ${error.message}',
      protocol: 'sse',
      kind: ProtocolStreamErrorKind.malformed,
      code: 'invalid_utf8',
    );
  } on ProtocolStreamException {
    rethrow;
  } catch (error) {
    throw ProtocolStreamException(
      error.toString(),
      protocol: 'sse',
      kind: ProtocolStreamErrorKind.transport,
    );
  }
}

/// Execute a POST request and return its response byte stream.
Future<Stream<List<int>>> openSseStream(SseRequestConfig config) async {
  final dio = getDio(config.url);
  try {
    final response = await dio.post<ResponseBody>(
      config.url,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          ...config.headers,
        },
        responseType: ResponseType.stream,
      ),
      data: jsonEncode(config.body),
      cancelToken: config.cancelToken,
    );
    final body = response.data;
    if (body == null) {
      throw ProtocolStreamException(
        '流式接口未返回响应体',
        protocol: 'sse',
        kind: ProtocolStreamErrorKind.remote,
        code: 'empty_response',
      );
    }
    return _cancelAwareByteStream(body.stream, config.cancelToken);
  } on ProtocolStreamException {
    rethrow;
  } on DioException catch (error) {
    if (error.type == DioExceptionType.cancel) {
      throw ProtocolStreamException(
        '请求已取消',
        protocol: 'sse',
        kind: ProtocolStreamErrorKind.cancelled,
        code: 'cancelled',
        retryable: false,
      );
    }
    final statusCode = error.response?.statusCode;
    throw ProtocolStreamException(
      _safeSseDioMessage(error),
      protocol: 'sse',
      kind: statusCode == null
          ? ProtocolStreamErrorKind.transport
          : ProtocolStreamErrorKind.remote,
      code: statusCode == null ? null : 'http_$statusCode',
      statusCode: statusCode,
    );
  } catch (error) {
    throw ProtocolStreamException(
      error.toString(),
      protocol: 'sse',
      kind: ProtocolStreamErrorKind.transport,
    );
  }
}

Stream<List<int>> _cancelAwareByteStream(
  Stream<List<int>> source,
  CancelToken? cancelToken,
) async* {
  var completedNormally = false;
  try {
    await for (final chunk in source) {
      yield chunk;
    }
    completedNormally = true;
  } on DioException catch (error) {
    if (error.type == DioExceptionType.cancel &&
        cancelToken != null &&
        cancelToken.isCancelled) {
      completedNormally = true;
      return;
    }
    throw ProtocolStreamException(
      _safeSseDioMessage(error),
      protocol: 'sse',
      kind: ProtocolStreamErrorKind.transport,
    );
  } catch (error) {
    if (cancelToken?.isCancelled ?? false) {
      completedNormally = true;
      return;
    }
    if (error is ProtocolStreamException) rethrow;
    throw ProtocolStreamException(
      error.toString(),
      protocol: 'sse',
      kind: ProtocolStreamErrorKind.transport,
    );
  } finally {
    if (!completedNormally && cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('SSE stream subscription cancelled');
    }
  }
}

String _safeSseDioMessage(DioException error) {
  final statusCode = error.response?.statusCode;
  if (statusCode != null) {
    switch (statusCode) {
      case 401:
        return 'API Key 无效';
      case 403:
        return '流式接口访问被拒绝';
      case 404:
        return '流式接口不存在，请检查 Base URL';
      case 408:
        return '流式接口请求超时';
      case 429:
        return '请求频率超限，请稍后重试';
      default:
        if (statusCode >= 500) return '上游服务暂时不可用';
        return '流式接口请求失败';
    }
  }
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return '流式接口连接超时，请检查网络';
    case DioExceptionType.connectionError:
      return '无法连接流式接口，请检查 Base URL 和网络';
    case DioExceptionType.cancel:
      return '请求已取消';
    default:
      return '流式接口请求失败';
  }
}
