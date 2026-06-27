import 'dart:convert';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import '../ai/sse_helper.dart';
import 'text_to_speech_service.dart';

const kDefaultTextToSpeechBaseUrl = 'https://api.openai.com';
const kDefaultTextToSpeechModel = 'tts-1';
const kDefaultTextToSpeechVoice = 'alloy';
const kTextToSpeechMaxAudioBytes = 10 * 1024 * 1024;

String normalizeTextToSpeechBaseUrl(String baseUrl) {
  final normalized = normalizeOpenAiBaseUrl(baseUrl);
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const TextToSpeechException('TTS Base URL 格式无效');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const TextToSpeechException('TTS Base URL 仅支持 HTTP(S)');
  }
  return normalized;
}

String normalizeTextToSpeechModel(String model) {
  final value = model.trim();
  if (value.isEmpty) {
    throw const TextToSpeechException('TTS 模型不能为空');
  }
  if (value.length > 96) {
    throw const TextToSpeechException('TTS 模型名称过长');
  }
  return value;
}

class OpenAiCompatibleTextToSpeechEngine implements TextToSpeechEngine {
  const OpenAiCompatibleTextToSpeechEngine({
    required this.baseUrl,
    required this.apiKey,
    this.model = kDefaultTextToSpeechModel,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  @override
  Future<List<int>> synthesize(TextToSpeechInput input) async {
    final normalizedBaseUrl = normalizeTextToSpeechBaseUrl(baseUrl);
    final normalizedModel = normalizeTextToSpeechModel(model);
    final normalizedVoice = normalizeTextToSpeechVoice(input.voice);
    final normalizedText = normalizeTextToSpeechInput(input.text);
    final token = apiKey.trim();
    if (token.isEmpty) {
      throw const TextToSpeechException('TTS API Key 未配置');
    }

    final dio = createDio();
    try {
      final response = await dio.post<List<int>>(
        '$normalizedBaseUrl/v1/audio/speech',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
          },
          responseType: ResponseType.bytes,
        ),
        data: jsonEncode({
          'model': normalizedModel,
          'voice': normalizedVoice,
          'input': normalizedText,
          'response_format': 'mp3',
        }),
      );
      final bytes = response.data ?? const <int>[];
      if (bytes.length > kTextToSpeechMaxAudioBytes) {
        throw const TextToSpeechException('TTS 音频过大，已拒绝保存');
      }
      return bytes;
    } on TextToSpeechException {
      rethrow;
    } on DioException catch (error) {
      throw TextToSpeechException(_safeDioError(error));
    } catch (_) {
      throw const TextToSpeechException('TTS 请求失败，请稍后重试');
    } finally {
      dio.close(force: true);
    }
  }

  static String _safeDioError(DioException error) {
    if (error.type == DioExceptionType.cancel) return 'TTS 请求已取消';
    final statusCode = error.response?.statusCode;
    if (statusCode == 401) return 'TTS API Key 无效，请检查配置';
    if (statusCode == 403) return 'TTS 访问被拒绝，请检查权限';
    if (statusCode == 413) return '播报文本过长或音频过大，TTS 服务拒绝处理';
    if (statusCode == 429) return 'TTS 请求频率超限，请稍后重试';
    if (statusCode != null && statusCode >= 500) {
      return 'TTS 服务暂时不可用（HTTP $statusCode）';
    }
    if (statusCode != null) return 'TTS 请求失败（HTTP $statusCode）';
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'TTS 请求超时，请检查网络';
      case DioExceptionType.connectionError:
        return '无法连接 TTS 服务，请检查 Base URL 和网络';
      default:
        return 'TTS 请求失败，请稍后重试';
    }
  }
}
