import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import '../ai/endpoint_resolver.dart';
import 'audio_transcription_service.dart';
import 'xai_speech_provider_profile.dart';

/// xAI's batch REST STT adapter.
///
/// This is intentionally not an OpenAI-compatible adapter.  It calls
/// `/v1/stt`, never sends `model`, and validates the JSON response's required
/// `text` field.  WebSocket `/v1/stt` streaming is a separate contract and is
/// not implemented by this batch engine.
class XaiSpeechToTextEngine implements SpeechToTextEngine {
  const XaiSpeechToTextEngine({
    required this.baseUrl,
    required this.apiKey,
    this.language = kXaiDefaultSpeechLanguage,
    this.profile = kXaiSpeechProviderProfile,
  });

  final String baseUrl;
  final String apiKey;
  final String language;
  final XaiSpeechProviderProfile profile;

  @override
  Future<String> transcribe(
    AudioTranscriptionInput input, {
    CancelToken? cancelToken,
  }) async {
    _throwIfCancelled(cancelToken);
    normalizeXaiSpeechBaseUrl(baseUrl);
    final normalizedLanguage = normalizeXaiSpeechLanguage(language);
    final token = apiKey.trim();
    if (token.isEmpty) {
      throw const AudioTranscriptionException('xAI STT API Key 未配置');
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
    if (size > profile.maxSttAudioBytes) {
      throw AudioTranscriptionException(
        '语音文件超过 ${_megabytes(profile.maxSttAudioBytes)} MB，无法转写',
      );
    }
    _throwIfCancelled(cancelToken);

    final url = resolveXaiSpeechEndpoint(baseUrl, profile.sttEndpoint);
    final dio = createDio();
    try {
      final requestBody = await _buildRequestBody(
        input: input,
        file: file,
        language: normalizedLanguage,
      );
      final response = await dio.post<List<int>>(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            if (profile.sttRequestBodyMode ==
                XaiSpeechToTextRequestBodyMode.rawAudio)
              'Content-Type': _audioContentType(input.fileName),
          },
          responseType: ResponseType.bytes,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
        data: requestBody,
        cancelToken: cancelToken,
      );
      _throwIfCancelled(cancelToken);
      final statusCode = response.statusCode;
      if (statusCode == null || statusCode < 200 || statusCode >= 300) {
        throw AudioTranscriptionException(_httpError(statusCode));
      }
      return _decodeTranscript(_responseBytes(response.data));
    } on AudioTranscriptionException {
      rethrow;
    } on DioException catch (error) {
      throw AudioTranscriptionException(_safeDioError(error));
    } catch (_) {
      throw const AudioTranscriptionException('xAI STT 请求失败，请稍后重试');
    } finally {
      dio.close(force: true);
    }
  }

  Future<Object> _buildRequestBody({
    required AudioTranscriptionInput input,
    required File file,
    required String language,
  }) async {
    switch (profile.sttRequestBodyMode) {
      case XaiSpeechToTextRequestBodyMode.multipart:
        return FormData.fromMap({
          // xAI's public batch STT form does not use a model field and its
          // documented request has no language field. Only an explicitly
          // selected compatible-gateway profile may add language.
          'file': await MultipartFile.fromFile(
            file.path,
            filename: _safeUploadFileName(input.fileName),
          ),
          if (profile.includeSttLanguageField &&
              language != kXaiDefaultSpeechLanguage)
            'language': language,
        });
      case XaiSpeechToTextRequestBodyMode.rawAudio:
        // Some xAI-compatible gateways expose /v1/stt as a binary endpoint.
        // In this mode the request body is exactly the audio bytes: no JSON,
        // form fields, language field, or model is invented.
        return await file.readAsBytes();
    }
  }

  String _decodeTranscript(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const AudioTranscriptionException('xAI STT 响应为空，无法解析');
    }
    if (bytes.length > profile.maxSttResponseBytes) {
      throw const AudioTranscriptionException('xAI STT 响应过大，已拒绝解析');
    }

    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const AudioTranscriptionException('xAI STT 响应 JSON 格式无效');
      }
      final text = decoded['text'];
      if (text is! String) {
        throw const AudioTranscriptionException('xAI STT 响应缺少 text');
      }
      return text.trim();
    } on AudioTranscriptionException {
      rethrow;
    } catch (_) {
      throw const AudioTranscriptionException('xAI STT 响应 JSON 格式无效');
    }
  }

  List<int> _responseBytes(dynamic data) {
    if (data is List<int>) return data;
    if (data is List && data.every((item) => item is int)) {
      return data.cast<int>();
    }
    if (data is String) return utf8.encode(data);
    throw const AudioTranscriptionException('xAI STT 响应格式无效');
  }

  static String _safeUploadFileName(String value) {
    final candidate = value.trim();
    if (candidate.isEmpty) return 'audio.bin';
    final sanitized = candidate.replaceAll(RegExp(r'[/\\]'), '_');
    return sanitized.isEmpty ? 'audio.bin' : sanitized;
  }

  static String _audioContentType(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.ogg') || lower.endsWith('.oga')) return 'audio/ogg';
    if (lower.endsWith('.webm')) return 'audio/webm';
    return 'application/octet-stream';
  }

  static String _megabytes(int bytes) =>
      (bytes / (1024 * 1024)).round().toString();

  static void _throwIfCancelled(CancelToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw const AudioTranscriptionException('xAI STT 请求已取消');
    }
  }

  static String _httpError(int? statusCode) {
    if (statusCode == 401) return 'xAI STT API Key 无效，请检查配置';
    if (statusCode == 403) return 'xAI STT 访问被拒绝，请检查权限';
    if (statusCode == 413) return '语音文件过大，xAI STT 服务拒绝处理';
    if (statusCode == 429) return 'xAI STT 请求频率超限，请稍后重试';
    if (statusCode != null && statusCode >= 500) {
      return 'xAI STT 服务暂时不可用（HTTP $statusCode）';
    }
    return statusCode == null
        ? 'xAI STT 请求失败，请稍后重试'
        : 'xAI STT 请求失败（HTTP $statusCode）';
  }

  static String _safeDioError(DioException error) {
    if (error.type == DioExceptionType.cancel) return 'xAI STT 请求已取消';
    final statusCode = error.response?.statusCode;
    if (statusCode != null) return _httpError(statusCode);
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'xAI STT 请求超时，请检查网络';
      case DioExceptionType.connectionError:
        return '无法连接 xAI STT 服务，请检查 Base URL 和网络';
      default:
        return 'xAI STT 请求失败，请稍后重试';
    }
  }
}

String normalizeXaiSpeechBaseUrl(String baseUrl) {
  final normalized = normalizeOpenAiBaseUrl(baseUrl);
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const AudioTranscriptionException('xAI STT Base URL 格式无效');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const AudioTranscriptionException('xAI STT Base URL 仅支持 HTTP(S)');
  }
  return normalized;
}

String normalizeXaiSpeechLanguage(String language) {
  final value = language.trim();
  if (value.isEmpty || value.toLowerCase() == kXaiDefaultSpeechLanguage) {
    return kXaiDefaultSpeechLanguage;
  }
  if (value.length > 35 ||
      !RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(value)) {
    throw const AudioTranscriptionException('xAI STT 语言代码格式无效');
  }
  return value;
}

String resolveXaiSpeechEndpoint(String baseUrl, String endpoint) =>
    resolveApiEndpoint(baseUrl, endpoint, defaultPrefix: '/v1');
