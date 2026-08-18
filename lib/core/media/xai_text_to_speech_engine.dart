import 'dart:convert';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import '../ai/endpoint_resolver.dart';
import 'text_to_speech_service.dart';
import 'xai_speech_provider_profile.dart';

/// xAI's batch REST TTS adapter.
///
/// The request is intentionally xAI-specific: `/v1/tts` receives `text`,
/// `voice_id`, `language`, and optional xAI `speed` / `output_format` fields.
/// It does not send OpenAI's `model`, `input`, `voice`, or `response_format`
/// fields. The WSS `/v1/tts` streaming protocol is a separate session
/// contract and is not implemented here.
class XaiTextToSpeechEngine implements TextToSpeechEngine {
  const XaiTextToSpeechEngine({
    required this.baseUrl,
    required this.apiKey,
    this.language = kXaiDefaultSpeechLanguage,
    this.speed = '1.0',
    this.responseFormat = 'mp3',
    this.profile = kXaiSpeechProviderProfile,
  });

  final String baseUrl;
  final String apiKey;
  final String language;
  final String speed;
  final String responseFormat;
  final XaiSpeechProviderProfile profile;

  @override
  Future<List<int>> synthesize(
    TextToSpeechInput input, {
    CancelToken? cancelToken,
  }) async {
    _throwIfCancelled(cancelToken);
    normalizeXaiTextToSpeechBaseUrl(baseUrl);
    final normalizedText = normalizeTextToSpeechInput(input.text);
    final normalizedVoice = normalizeTextToSpeechVoice(input.voice);
    final normalizedLanguage = normalizeXaiTextToSpeechLanguage(language);
    final normalizedSpeed = normalizeXaiTextToSpeechSpeed(speed);
    final normalizedFormat = normalizeXaiTextToSpeechResponseFormat(
      responseFormat,
      allowWireOnly: true,
    );
    final token = apiKey.trim();
    if (token.isEmpty) {
      throw const TextToSpeechException('xAI TTS API Key 未配置');
    }

    final dio = createDio();
    try {
      final requestBody = <String, dynamic>{
        'text': normalizedText,
        'voice_id': normalizedVoice,
        'language': normalizedLanguage,
      };
      if (normalizedSpeed != '1.0') {
        requestBody['speed'] = double.parse(normalizedSpeed);
      }
      if (normalizedFormat != 'mp3') {
        requestBody['output_format'] = {'codec': normalizedFormat};
      }

      final response = await dio.post<List<int>>(
        resolveXaiTextToSpeechEndpoint(baseUrl, profile.ttsEndpoint),
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': _audioMimeType(normalizedFormat),
          },
          responseType: ResponseType.bytes,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
        data: jsonEncode(requestBody),
        cancelToken: cancelToken,
      );
      _throwIfCancelled(cancelToken);
      final statusCode = response.statusCode;
      if (statusCode == null || statusCode < 200 || statusCode >= 300) {
        throw TextToSpeechException(_httpError(statusCode));
      }
      final contentType = response.headers.value('content-type');
      final bytes = _decodeAudioResponse(
        response.data,
        jsonContentType: _isJsonContentType(contentType),
      );
      if (bytes.isEmpty) {
        throw const TextToSpeechException('xAI TTS 响应为空，无法播放');
      }
      if (bytes.length > profile.maxTtsAudioBytes) {
        throw const TextToSpeechException('xAI TTS 音频过大，已拒绝保存');
      }
      return bytes;
    } on TextToSpeechException {
      rethrow;
    } on DioException catch (error) {
      throw TextToSpeechException(_safeDioError(error));
    } catch (_) {
      throw const TextToSpeechException('xAI TTS 请求失败，请稍后重试');
    } finally {
      dio.close(force: true);
    }
  }

  static bool _isJsonContentType(String? value) {
    final contentType = value?.split(';').first.trim().toLowerCase();
    if (contentType == 'application/json' || contentType == 'text/json') {
      return true;
    }
    if (contentType == null || contentType.isEmpty) return false;
    if (contentType.startsWith('text/')) {
      throw const TextToSpeechException('xAI TTS 响应不是音频字节');
    }
    if (!contentType.startsWith('audio/') &&
        contentType != 'application/octet-stream') {
      throw const TextToSpeechException('xAI TTS 响应音频格式无效');
    }
    return false;
  }

  static String _audioMimeType(String format) {
    return switch (format) {
      'wav' => 'audio/wav',
      'pcm' => 'audio/pcm',
      'mulaw' => 'audio/basic',
      'alaw' => 'audio/alaw',
      _ => 'audio/mpeg',
    };
  }

  static List<int> _responseBytes(dynamic data) {
    if (data is List<int>) return data;
    if (data is List && data.every((item) => item is int)) {
      return data.cast<int>();
    }
    // ResponseType.bytes should never decode JSON.  Treat all other values as
    // a protocol violation instead of accidentally accepting a JSON map as
    // playable audio.
    throw const TextToSpeechException('xAI TTS 响应字节格式无效');
  }

  static List<int> _decodeAudioResponse(
    dynamic data, {
    required bool jsonContentType,
  }) {
    final bytes = _responseBytes(data);
    var index = 0;
    while (index < bytes.length &&
        (bytes[index] == 0x09 ||
            bytes[index] == 0x0a ||
            bytes[index] == 0x0d ||
            bytes[index] == 0x20)) {
      index++;
    }
    final looksLikeJson =
        index < bytes.length && (bytes[index] == 0x7b || bytes[index] == 0x5b);
    if (!jsonContentType && !looksLikeJson) return bytes;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map || decoded['audio'] is! String) {
        throw const TextToSpeechException('xAI TTS 响应不是音频字节');
      }
      var encoded = (decoded['audio'] as String).trim();
      final comma = encoded.indexOf(',');
      if (encoded.toLowerCase().startsWith('data:') && comma > 0) {
        encoded = encoded.substring(comma + 1);
      }
      if (encoded.isEmpty) {
        throw const TextToSpeechException('xAI TTS 响应音频为空');
      }
      try {
        final decodedAudio = base64Decode(encoded);
        if (decodedAudio.isEmpty) {
          throw const TextToSpeechException('xAI TTS 响应音频为空');
        }
        return decodedAudio;
      } on FormatException {
        throw const TextToSpeechException('xAI TTS 响应音频编码无效');
      }
    } on TextToSpeechException {
      rethrow;
    } catch (_) {
      if (jsonContentType) {
        throw const TextToSpeechException('xAI TTS 响应不是音频字节');
      }
      // A binary stream can coincidentally start with `{`/`[`. Only reject it
      // when the complete body is valid JSON.
      return bytes;
    }
  }

  static void _throwIfCancelled(CancelToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw const TextToSpeechException('xAI TTS 请求已取消');
    }
  }

  static String _httpError(int? statusCode) {
    if (statusCode == 401) return 'xAI TTS API Key 无效，请检查配置';
    if (statusCode == 403) return 'xAI TTS 访问被拒绝，请检查权限';
    if (statusCode == 413) return '播报文本过长或音频过大，xAI TTS 服务拒绝处理';
    if (statusCode == 429) return 'xAI TTS 请求频率超限，请稍后重试';
    if (statusCode != null && statusCode >= 500) {
      return 'xAI TTS 服务暂时不可用（HTTP $statusCode）';
    }
    return statusCode == null
        ? 'xAI TTS 请求失败，请稍后重试'
        : 'xAI TTS 请求失败（HTTP $statusCode）';
  }

  static String _safeDioError(DioException error) {
    if (error.type == DioExceptionType.cancel) return 'xAI TTS 请求已取消';
    final statusCode = error.response?.statusCode;
    if (statusCode != null) return _httpError(statusCode);
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'xAI TTS 请求超时，请检查网络';
      case DioExceptionType.connectionError:
        return '无法连接 xAI TTS 服务，请检查 Base URL 和网络';
      default:
        return 'xAI TTS 请求失败，请稍后重试';
    }
  }
}

String normalizeXaiTextToSpeechBaseUrl(String baseUrl) {
  final normalized = normalizeOpenAiBaseUrl(baseUrl);
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const TextToSpeechException('xAI TTS Base URL 格式无效');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const TextToSpeechException('xAI TTS Base URL 仅支持 HTTP(S)');
  }
  return normalized;
}

String normalizeXaiTextToSpeechLanguage(String language) {
  final value = language.trim();
  if (value.isEmpty || value.toLowerCase() == kXaiDefaultSpeechLanguage) {
    return kXaiDefaultSpeechLanguage;
  }
  if (value.length > 35 ||
      !RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(value)) {
    throw const TextToSpeechException('xAI TTS 语言代码格式无效');
  }
  return value;
}

String normalizeXaiTextToSpeechSpeed(String speed) {
  final value = double.tryParse(speed.trim());
  if (value == null ||
      value < kXaiTextToSpeechMinSpeed ||
      value > kXaiTextToSpeechMaxSpeed) {
    throw const TextToSpeechException('xAI TTS 语速需在 0.7 - 1.5 之间');
  }
  return speed.trim();
}

String normalizeXaiTextToSpeechResponseFormat(
  String format, {
  bool allowWireOnly = false,
}) {
  final value = format.trim().toLowerCase();
  final allowed = allowWireOnly
      ? kXaiTextToSpeechWireFormats
      : kXaiTextToSpeechPlaybackFormats;
  if (!allowed.contains(value)) {
    throw TextToSpeechException(
      allowWireOnly
          ? 'xAI TTS 不支持该 output_format'
          : '当前原生播放通道仅支持 xAI TTS 的 mp3 / wav',
    );
  }
  return value;
}

String resolveXaiTextToSpeechEndpoint(String baseUrl, String endpoint) =>
    resolveApiEndpoint(baseUrl, endpoint, defaultPrefix: '/v1');
