import 'dart:convert';
import 'package:dio/dio.dart';
import 'http_helper.dart';

/// SSE 流式事件
class SseEvent {
  final String data;
  const SseEvent(this.data);
}

/// SSE 请求配置
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

/// 解析字节流为 SSE 数据事件
/// 处理：utf8 解码（多字节安全）、行缓冲、data: 前缀剥离、空行跳过、[DONE] 哨兵检测
Stream<SseEvent> parseSseStream(Stream<List<int>> byteStream) async* {
  String lineBuffer = '';
  List<int> byteBuffer = [];

  await for (final chunk in byteStream) {
    byteBuffer.addAll(chunk);

    // 找到安全的 UTF-8 解码边界：丢弃尾部可能不完整的多字节序列
    final safeBytes = _trimIncompleteUtf8(byteBuffer);
    if (safeBytes.isEmpty) continue; // 还没有足够的字节

    final decoded = utf8.decode(safeBytes);
    final lastNewline = decoded.lastIndexOf('\n');

    if (lastNewline == -1) {
      // 没有换行，全部累积到 lineBuffer
      lineBuffer += decoded;
      byteBuffer = [];
      continue;
    }

    final completeText = lineBuffer + decoded.substring(0, lastNewline);
    lineBuffer = decoded.substring(lastNewline + 1);

    // 保留最后一行对应的原始字节（未解码部分）
    byteBuffer = List<int>.from(
      utf8.encode(decoded.substring(lastNewline + 1)),
    );

    final lines = completeText.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
      final data = trimmed.substring(5).trimLeft();
      if (data == '[DONE]') return;
      yield SseEvent(data);
    }
  }

  // 流结束，处理剩余缓冲（此时不会有更多数据，强制解码）
  if (byteBuffer.isNotEmpty) {
    final remaining = utf8.decode(byteBuffer, allowMalformed: true);
    lineBuffer += remaining;
  }
  if (lineBuffer.isNotEmpty) {
    final trimmed = lineBuffer.trim();
    if (trimmed.isNotEmpty &&
        trimmed.startsWith('data:') &&
        trimmed != 'data:[DONE]' &&
        trimmed != 'data: [DONE]') {
      yield SseEvent(trimmed.substring(5).trimLeft());
    }
  }
}

/// 从字节序列尾部移除可能不完整的 UTF-8 多字节序列
/// UTF-8 编码规则：首字节高位标识长度，后续字节以 10xxxxxx 开头
List<int> _trimIncompleteUtf8(List<int> bytes) {
  if (bytes.isEmpty) return bytes;
  // 从尾部向前检查最多 4 字节（UTF-8 最大长度）
  for (var i = 1; i <= 4 && i <= bytes.length; i++) {
    final b = bytes[bytes.length - i];
    if (b & 0x80 == 0) {
      // ASCII 字节（0xxxxxxx），截断点在它之后
      return bytes.sublist(0, bytes.length - i + 1);
    } else if (b & 0xC0 == 0xC0) {
      // 多字节序列首字节（11xxxxxx）
      final expectedLen = (b & 0xE0) == 0xC0
          ? 2
          : (b & 0xF0) == 0xE0
          ? 3
          : 4;
      final actualLen = i;
      if (actualLen >= expectedLen) {
        return bytes; // 完整的多字节序列
      } else {
        return bytes.sublist(0, bytes.length - i); // 不完整，截掉
      }
    }
    // 0x80-0xBF 是后续字节，继续向前检查
  }
  // 全是后续字节，全部截掉
  return const [];
}

/// 执行 POST 请求并返回 SSE 字节流
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
    return _cancelAwareByteStream(response.data!.stream, config.cancelToken);
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) {
      throw Exception('请求已取消');
    }
    // 保留状态码信息
    final statusCode = e.response?.statusCode;
    final message = formatDioError(e);
    if (statusCode != null) {
      throw Exception('[$statusCode] $message');
    }
    throw Exception(message);
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
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel &&
        cancelToken != null &&
        cancelToken.isCancelled) {
      completedNormally = true;
      return;
    }
    rethrow;
  } finally {
    if (!completedNormally && cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('SSE stream subscription cancelled');
    }
  }
}

/// 标准化 URL（去除尾部斜杠）
String normalizeUrl(String baseUrl) {
  final trimmed = baseUrl.trim();
  if (trimmed.isEmpty) return trimmed;

  final normalized = trimmed.replaceAll(RegExp(r'/+$'), '');
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(normalized);
  if (hasScheme) return normalized;

  final lower = normalized.toLowerCase();
  final isIpv4 = RegExp(
    r'^(\d{1,3}\.){3}\d{1,3}(:\d+)?(/.*)?$',
  ).hasMatch(lower);
  final isPrivateIpv4 = RegExp(
    r'^(127\.\d+\.\d+\.\d+|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+)(:\d+)?(/.*)?$',
  ).hasMatch(lower);
  final isIpv6 =
      RegExp(r'^\[[0-9a-f:]+\](:\d+)?(/.*)?$').hasMatch(lower) ||
      RegExp(r'^[0-9a-f:]+$').hasMatch(lower);
  final isLocalHost =
      lower == 'localhost' ||
      lower.startsWith('localhost:') ||
      lower.startsWith('localhost/') ||
      lower == '0.0.0.0' ||
      lower.startsWith('0.0.0.0:') ||
      lower.startsWith('0.0.0.0/') ||
      lower == '[::1]' ||
      lower.startsWith('[::1]:') ||
      lower.startsWith('[::1]/') ||
      lower == '::1';

  final scheme = (isLocalHost || isPrivateIpv4 || isIpv4 || isIpv6)
      ? 'http'
      : 'https';
  return '$scheme://$normalized';
}

String normalizeOpenAiBaseUrl(String baseUrl) {
  final normalized = normalizeUrl(baseUrl);
  if (normalized.endsWith('/v1')) {
    return normalized.substring(0, normalized.length - 3);
  }
  return normalized;
}
