import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import '../ai/sse_helper.dart';
import 'audio_transcription_service.dart';

const kDefaultSpeechToTextBaseUrl = 'https://api.openai.com';
const kDefaultSpeechToTextModel = 'whisper-1';
const kSpeechToTextMaxAudioBytes = 25 * 1024 * 1024;

String normalizeSpeechToTextBaseUrl(String baseUrl) {
  final normalized = normalizeOpenAiBaseUrl(baseUrl);
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const AudioTranscriptionException('STT Base URL 格式无效');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const AudioTranscriptionException('STT Base URL 仅支持 HTTP(S)');
  }
  return normalized;
}

String normalizeSpeechToTextModel(String model) {
  final value = model.trim();
  if (value.isEmpty) {
    throw const AudioTranscriptionException('STT 模型不能为空');
  }
  if (value.length > 96) {
    throw const AudioTranscriptionException('STT 模型名称过长');
  }
  return value;
}

class OpenAiCompatibleSpeechToTextEngine implements SpeechToTextEngine {
  const OpenAiCompatibleSpeechToTextEngine({
    required this.baseUrl,
    required this.apiKey,
    this.model = kDefaultSpeechToTextModel,
    this.language = 'auto',
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  /// 识别语言：auto（自动）/ zh（中文）/ en（英文）。
  final String language;

  @override
  Future<String> transcribe(AudioTranscriptionInput input) async {
    final normalizedBaseUrl = normalizeSpeechToTextBaseUrl(baseUrl);
    final normalizedModel = normalizeSpeechToTextModel(model);
    final token = apiKey.trim();
    if (token.isEmpty) {
      throw const AudioTranscriptionException('STT API Key 未配置');
    }

    final file = File(input.audioPath);
    final exists = await file.exists();
    if (!exists) {
      throw const AudioTranscriptionException('语音文件不存在，无法转写');
    }
    final size = await file.length();
    if (size <= 0) {
      throw const AudioTranscriptionException('语音文件为空，无法转写');
    }
    if (size > kSpeechToTextMaxAudioBytes) {
      throw const AudioTranscriptionException('语音文件超过 25 MB，无法转写');
    }

    final url = '$normalizedBaseUrl/v1/audio/transcriptions';
    final dio = createDio();
    try {
      final response = await dio.post<dynamic>(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
        data: FormData.fromMap({
          'model': normalizedModel,
          'file': await MultipartFile.fromFile(
            input.audioPath,
            filename: input.fileName,
          ),
          // OpenAI 兼容接口用“省略 language”表示自动检测；把字面值
          // `auto` 作为 ISO-639-1 代码发送会被部分厂商拒绝。
          if (language.trim().isNotEmpty &&
              language.trim().toLowerCase() != 'auto')
            'language': language.trim().toLowerCase(),
        }),
      );
      return _extractTranscriptText(response.data).trim();
    } on AudioTranscriptionException {
      rethrow;
    } on DioException catch (error) {
      throw AudioTranscriptionException(_safeDioError(error));
    } catch (_) {
      throw const AudioTranscriptionException('STT 请求失败，请稍后重试');
    } finally {
      dio.close(force: true);
    }
  }

  static String _extractTranscriptText(dynamic data) {
    if (data is Map) {
      final text = data['text'] ?? data['transcript'] ?? data['output_text'];
      if (text is String) return text;
      if (text is List) {
        return text.whereType<String>().join('\n');
      }
    }
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return _extractTranscriptText(decoded);
      } catch (_) {
        return data;
      }
    }
    return '';
  }

  static String _safeDioError(DioException error) {
    if (error.type == DioExceptionType.cancel) return 'STT 请求已取消';
    final statusCode = error.response?.statusCode;
    if (statusCode == 401) return 'STT API Key 无效，请检查配置';
    if (statusCode == 403) return 'STT 访问被拒绝，请检查权限';
    if (statusCode == 413) return '语音文件过大，STT 服务拒绝处理';
    if (statusCode == 429) return 'STT 请求频率超限，请稍后重试';
    if (statusCode != null && statusCode >= 500) {
      return 'STT 服务暂时不可用（HTTP $statusCode）';
    }
    if (statusCode != null) return 'STT 请求失败（HTTP $statusCode）';
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'STT 请求超时，请检查网络';
      case DioExceptionType.connectionError:
        return '无法连接 STT 服务，请检查 Base URL 和网络';
      default:
        return 'STT 请求失败，请稍后重试';
    }
  }
}
