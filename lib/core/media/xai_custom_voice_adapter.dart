import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../ai/api_endpoint_resolver.dart';
import '../ai/http_helper.dart';
import 'xai_speech_provider_profile.dart';

/// Metadata and local reference audio for xAI's custom-voice create call.
///
/// The adapter only considers the operation successful after the server
/// returns a valid `voice_id`. It never invents an ID and does not claim that
/// a key has Enterprise/custom-voice entitlement.
class XaiCustomVoiceRequest {
  const XaiCustomVoiceRequest({
    required this.audioPath,
    this.fileName = '',
    this.name,
    this.description,
    this.gender,
    this.accent,
    this.age,
    this.language,
    this.useCase,
    this.tone,
  });

  final String audioPath;
  final String fileName;
  final String? name;
  final String? description;
  final String? gender;
  final String? accent;
  final String? age;
  final String? language;
  final String? useCase;
  final String? tone;
}

class XaiCustomVoiceResult {
  const XaiCustomVoiceResult({
    required this.voiceId,
    this.name,
    this.description,
  });

  final String voiceId;
  final String? name;
  final String? description;
}

class XaiCustomVoiceException implements Exception {
  const XaiCustomVoiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// xAI `/v1/custom-voices` multipart adapter.
///
/// This is deliberately separate from the normal xAI TTS engine. The public
/// endpoint is plan-gated and the app must keep that failure visible instead
/// of falling back to a locally fabricated custom voice ID.
class XaiCustomVoiceAdapter {
  const XaiCustomVoiceAdapter({
    required this.baseUrl,
    required this.apiKey,
    this.profile = kXaiSpeechProviderProfile,
  });

  final String baseUrl;
  final String apiKey;
  final XaiSpeechProviderProfile profile;

  Future<XaiCustomVoiceResult> createVoice(
    XaiCustomVoiceRequest request, {
    CancelToken? cancelToken,
  }) async {
    _throwIfCancelled(cancelToken);
    final normalizedBaseUrl = _normalizeBaseUrl(baseUrl);
    final token = apiKey.trim();
    if (token.isEmpty) {
      throw const XaiCustomVoiceException('xAI custom voice API Key 未配置');
    }

    final file = File(request.audioPath);
    try {
      if (!await file.exists()) {
        throw const XaiCustomVoiceException('声音克隆参考音频不存在');
      }
      final fileSize = await file.length();
      if (fileSize <= 0) {
        throw const XaiCustomVoiceException('声音克隆参考音频为空');
      }
      if (fileSize > profile.maxCustomVoiceAudioBytes) {
        throw XaiCustomVoiceException(
          '声音克隆参考音频超过 ${_megabytes(profile.maxCustomVoiceAudioBytes)} MB',
        );
      }
      _throwIfCancelled(cancelToken);

      // xAI's documented multipart metadata is explicit; do not serialize a
      // generic `metadata` JSON field that the endpoint does not define.
      final fields = <String, dynamic>{
        'file': await MultipartFile.fromFile(
          file.path,
          filename: _safeFileName(request.fileName, file.path),
        ),
      };
      _putOptional(fields, 'name', request.name);
      _putOptional(fields, 'description', request.description);
      _putOptional(fields, 'gender', request.gender);
      _putOptional(fields, 'accent', request.accent);
      _putOptional(fields, 'age', request.age);
      _putOptional(fields, 'language', request.language);
      _putOptional(fields, 'use_case', request.useCase);
      _putOptional(fields, 'tone', request.tone);

      final dio = createDio();
      try {
        final response = await dio.post<dynamic>(
          resolveApiEndpoint(
            normalizedBaseUrl,
            profile.customVoiceEndpoint,
            defaultPrefix: '/v1',
          ),
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
            responseType: ResponseType.json,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 300,
          ),
          data: FormData.fromMap(fields),
          cancelToken: cancelToken,
        );
        _throwIfCancelled(cancelToken);
        final statusCode = response.statusCode;
        if (statusCode == null || statusCode < 200 || statusCode >= 300) {
          throw XaiCustomVoiceException(_httpError(statusCode));
        }
        return _decodeResult(response.data);
      } finally {
        dio.close(force: true);
      }
    } on XaiCustomVoiceException {
      rethrow;
    } on DioException catch (error) {
      throw XaiCustomVoiceException(_safeDioError(error));
    } catch (_) {
      throw const XaiCustomVoiceException('xAI custom voice 创建失败，请稍后重试');
    }
  }

  static XaiCustomVoiceResult _decodeResult(dynamic data) {
    dynamic decoded = data;
    if (data is List<int>) {
      decoded = _decodeJsonString(utf8.decode(data));
    } else if (data is String) {
      decoded = _decodeJsonString(data);
    }
    if (decoded is! Map) {
      throw const XaiCustomVoiceException('xAI custom voice 响应 JSON 格式无效');
    }
    final voiceId = decoded['voice_id'];
    if (voiceId is! String || !RegExp(r'^[a-z0-9]{8}$').hasMatch(voiceId)) {
      throw const XaiCustomVoiceException('xAI custom voice 响应缺少有效 voice_id');
    }
    return XaiCustomVoiceResult(
      voiceId: voiceId,
      name: decoded['name'] is String ? decoded['name'] as String : null,
      description: decoded['description'] is String
          ? decoded['description'] as String
          : null,
    );
  }

  static dynamic _decodeJsonString(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      throw const XaiCustomVoiceException('xAI custom voice 响应 JSON 格式无效');
    }
  }

  static void _putOptional(
    Map<String, dynamic> fields,
    String key,
    String? value,
  ) {
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      fields[key] = normalized;
    }
  }

  static String _normalizeBaseUrl(String value) {
    final normalized = normalizeOpenAiBaseUrl(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const XaiCustomVoiceException('xAI custom voice Base URL 格式无效');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const XaiCustomVoiceException(
        'xAI custom voice Base URL 仅支持 HTTP(S)',
      );
    }
    return normalized;
  }

  static String _safeFileName(String requested, String path) {
    final candidate = requested.trim().isEmpty
        ? path.split(RegExp(r'[/\\]')).last
        : requested.trim();
    final sanitized = candidate.replaceAll(RegExp(r'[/\\]'), '_');
    return sanitized.trim().isEmpty ? 'reference-audio.bin' : sanitized;
  }

  static String _megabytes(int bytes) =>
      (bytes / (1024 * 1024)).round().toString();

  static void _throwIfCancelled(CancelToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw const XaiCustomVoiceException('xAI custom voice 请求已取消');
    }
  }

  static String _httpError(int? statusCode) {
    if (statusCode == 401) return 'xAI custom voice API Key 无效，请检查配置';
    if (statusCode == 403) {
      return 'xAI custom voice 创建 API 未开通（HTTP 403），请检查团队或 Enterprise 权限';
    }
    if (statusCode == 413) {
      return 'xAI custom voice 参考音频超过服务限制（HTTP 413，最多 120 秒）或请求过大';
    }
    if (statusCode == 429) return 'xAI custom voice 请求频率超限，请稍后重试';
    if (statusCode != null && statusCode >= 500) {
      return 'xAI custom voice 服务暂时不可用（HTTP $statusCode）';
    }
    return statusCode == null
        ? 'xAI custom voice 创建失败，请稍后重试'
        : 'xAI custom voice 创建失败（HTTP $statusCode）';
  }

  static String _safeDioError(DioException error) {
    if (error.type == DioExceptionType.cancel) {
      return 'xAI custom voice 请求已取消';
    }
    final statusCode = error.response?.statusCode;
    if (statusCode != null) return _httpError(statusCode);
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'xAI custom voice 请求超时，请检查网络';
      case DioExceptionType.connectionError:
        return '无法连接 xAI custom voice 服务，请检查 Base URL 和网络';
      default:
        return 'xAI custom voice 创建失败，请稍后重试';
    }
  }
}
