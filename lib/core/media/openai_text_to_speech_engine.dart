import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../ai/http_helper.dart';
import '../ai/sse_helper.dart';
import 'speech_provider_preset.dart';
import 'text_to_speech_service.dart';

const kDefaultTextToSpeechBaseUrl = 'https://api.openai.com';
const kDefaultTextToSpeechModel = 'tts-1';
const kDefaultTextToSpeechVoice = 'alloy';
const kTextToSpeechMaxAudioBytes = 10 * 1024 * 1024;
const kTextToSpeechMaxReferenceAudioBytes = 10 * 1024 * 1024;

/// 校验语速：mimo 支持 0.25-4。
String normalizeTextToSpeechSpeed(String speed) {
  final value = double.tryParse(speed.trim());
  if (value == null ||
      value < kSimiRouterTtsMinSpeed ||
      value > kSimiRouterTtsMaxSpeed) {
    throw const TextToSpeechException('语速需在 0.25 - 4 之间');
  }
  return speed.trim();
}

/// 校验输出格式：mp3 / wav / opus / aac / flac。
String normalizeTextToSpeechResponseFormat(String format) {
  final value = format.trim().toLowerCase();
  if (!kSimiRouterTtsResponseFormats.contains(value)) {
    throw const TextToSpeechException('不支持的输出格式');
  }
  return value;
}

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

/// 根据模型模式构造 /v1/audio/speech 请求体。
///
/// - `mimo-v2.5-tts`（standard）：`voice` 音色 + 可选 `speed` / `response_format`
/// - `mimo-v2.5-tts-voicedesign`：`style` 音色描述 + `speed` / `response_format`
/// - `mimo-v2.5-tts-voiceclone`：`voice` 传参考音频 base64 data URI
/// - 其他模型（如 tts-1）：保持原 4 字段行为，不带 speed / format 扩展字段
Map<String, dynamic> _buildRequestBody({
  required String model,
  required String voice,
  required String text,
  required String speed,
  required String format,
  required String style,
  String? referenceAudioPath,
}) {
  final mode = simiRouterTtsModeOf(model);
  switch (mode) {
    case SimiRouterTtsMode.voiceDesign:
      if (style.trim().isEmpty) {
        throw const TextToSpeechException('声音设计模式需要填写声音风格描述');
      }
      return {
        'model': model,
        'input': text,
        'style': style.trim(),
        'speed': speed,
        'response_format': format,
      };
    case SimiRouterTtsMode.voiceClone:
      final referencePath = referenceAudioPath;
      if (referencePath == null || referencePath.isEmpty) {
        throw const TextToSpeechException('声音克隆需要选择参考音频');
      }
      return {
        'model': model,
        'input': text,
        'voice': _referenceAudioDataUri(referencePath),
        'speed': speed,
        'response_format': format,
      };
    case SimiRouterTtsMode.standard:
      return {
        'model': model,
        'voice': voice,
        'input': text,
        'speed': speed,
        'response_format': format,
      };
    case null:
      // 非 SimiRouter 模型（OpenAI tts-1 等）保持原有请求体。
      return {
        'model': model,
        'voice': voice,
        'input': text,
        'response_format': 'mp3',
      };
  }
}

/// 把参考音频文件编码为 `data:audio/wav;base64,...` 请求值。
String _referenceAudioDataUri(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    throw const TextToSpeechException('参考音频文件不存在，请重新选择');
  }
  final byteLength = file.lengthSync();
  if (byteLength <= 0) {
    throw const TextToSpeechException('参考音频文件为空');
  }
  if (byteLength > kTextToSpeechMaxReferenceAudioBytes) {
    throw const TextToSpeechException('参考音频超过 10 MB，请压缩后重试');
  }
  // 先检查长度再读取，避免异常大的外部文件瞬间占满内存。
  final bytes = file.readAsBytesSync();
  final ext = path.toLowerCase().endsWith('.wav') ? 'wav' : 'audio';
  return 'data:audio/$ext;base64,${base64Encode(bytes)}';
}

class OpenAiCompatibleTextToSpeechEngine implements TextToSpeechEngine {
  const OpenAiCompatibleTextToSpeechEngine({
    required this.baseUrl,
    required this.apiKey,
    this.model = kDefaultTextToSpeechModel,
    this.speed = '1.0',
    this.responseFormat = 'mp3',
    this.style = '',
    this.referenceAudioPath,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  /// mimo TTS 语速（0.25-4，字符串存储）。
  final String speed;

  /// 输出格式：mp3 / wav / opus / aac / flac。
  final String responseFormat;

  /// 声音设计模式的音色文字描述（mimo-v2.5-tts-voicedesign）。
  final String style;

  /// 声音克隆模式的参考音频本地路径（mimo-v2.5-tts-voiceclone）。
  final String? referenceAudioPath;

  @override
  Future<List<int>> synthesize(
    TextToSpeechInput input, {
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw const TextToSpeechException('TTS 请求已取消');
    }
    normalizeTextToSpeechBaseUrl(baseUrl);
    final normalizedModel = normalizeTextToSpeechModel(model);
    final normalizedVoice = normalizeTextToSpeechVoice(input.voice);
    final normalizedText = normalizeTextToSpeechInput(input.text);
    final token = apiKey.trim();
    if (token.isEmpty) {
      throw const TextToSpeechException('TTS API Key 未配置');
    }

    final normalizedSpeed = normalizeTextToSpeechSpeed(speed);
    final normalizedFormat = normalizeTextToSpeechResponseFormat(
      responseFormat,
    );
    final mode = simiRouterTtsModeOf(normalizedModel);
    // 非 mimo 的 OpenAI 兼容模型仍固定请求 mp3；mimo 才使用用户选择的格式。
    final effectiveFormat = mode == null ? 'mp3' : normalizedFormat;
    final dio = createDio();
    try {
      final response = await dio.post<List<int>>(
        resolveOpenAiEndpoint(baseUrl, 'audio/speech'),
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': _audioMimeType(effectiveFormat),
          },
          responseType: ResponseType.bytes,
        ),
        data: jsonEncode(
          _buildRequestBody(
            model: normalizedModel,
            voice: normalizedVoice,
            text: normalizedText,
            speed: normalizedSpeed,
            format: effectiveFormat,
            style: style,
            referenceAudioPath: referenceAudioPath,
          ),
        ),
        cancelToken: cancelToken,
      );
      if (cancelToken?.isCancelled == true) {
        throw const TextToSpeechException('TTS 请求已取消');
      }
      final bytes = response.data ?? const <int>[];
      if (bytes.isEmpty) {
        throw const TextToSpeechException('TTS 响应为空，无法播放');
      }
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

  static String _audioMimeType(String format) {
    return switch (format) {
      'wav' => 'audio/wav',
      'opus' => 'audio/ogg',
      'aac' => 'audio/aac',
      'flac' => 'audio/flac',
      _ => 'audio/mpeg',
    };
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
