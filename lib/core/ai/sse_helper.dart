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

  const SseRequestConfig({
    required this.url,
    required this.headers,
    required this.body,
  });
}

/// 解析字节流为 SSE 数据事件
/// 处理：utf8 解码、行缓冲、data: 前缀剥离、空行跳过、[DONE] 哨兵检测
Stream<SseEvent> parseSseStream(Stream<List<int>> byteStream) async* {
  String buffer = '';
  await for (final chunk in byteStream) {
    buffer += utf8.decode(chunk);
    final lines = buffer.split('\n');
    buffer = lines.removeLast();

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
      final data = trimmed.substring(6);
      if (data == '[DONE]') return;
      yield SseEvent(data);
    }
  }
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
    );
    return response.data!.stream;
  } on DioException catch (e) {
    throw Exception(formatDioError(e));
  }
}

/// 标准化 URL（去除尾部斜杠）
String normalizeUrl(String baseUrl) {
  return baseUrl.replaceAll(RegExp(r'/+$'), '');
}
