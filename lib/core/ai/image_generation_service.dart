import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'http_helper.dart';
import 'sse_helper.dart';

/// 图片生成默认模型（OpenAI 兼容接口标准模型名，可覆盖）。
const kDefaultImageGenerationModel = 'dall-e-3';

/// 生成图片的默认尺寸。
const kImageGenerationSize = '1024x1024';

/// 生成的图片单张大小上限（本地保存前的安全闸门）。
const kImageGenerationMaxBytes = 10 * 1024 * 1024;

class ImageGenerationException implements Exception {
  final String message;
  const ImageGenerationException(this.message);

  @override
  String toString() => message;
}

/// 生成的图片字节。
class GeneratedImage {
  final Uint8List bytes;
  final String? mimeType;

  const GeneratedImage({required this.bytes, this.mimeType});
}

/// 校验图片生成 Base URL，返回去掉尾部 `/v1` 的根地址。
String normalizeImageGenerationBaseUrl(String baseUrl) {
  final normalized = normalizeOpenAiBaseUrl(baseUrl);
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const ImageGenerationException('图片生成 Base URL 格式无效');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const ImageGenerationException('图片生成 Base URL 仅支持 HTTP(S)');
  }
  return normalized;
}

/// OpenAI 兼容 `/v1/images/generations` 图片生成客户端。
///
/// 优先请求 `b64_json` 以本地保存、避免读取远端 URL；
/// 部分中继只返回 URL 时，会在大小与协议安全限制内下载字节。
class ImageGenerationService {
  const ImageGenerationService({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  Future<GeneratedImage> generate(String prompt) async {
    final normalizedBaseUrl = normalizeImageGenerationBaseUrl(baseUrl);
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty) {
      throw const ImageGenerationException('图片生成模型未配置');
    }
    final token = apiKey.trim();
    if (token.isEmpty) {
      throw const ImageGenerationException('API Key 未配置');
    }
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      throw const ImageGenerationException('图片描述不能为空');
    }
    if (trimmedPrompt.length > 4000) {
      throw const ImageGenerationException('图片描述过长，请精简后重试');
    }

    final dio = getDio(normalizedBaseUrl);
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$normalizedBaseUrl/v1/images/generations',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.json,
        ),
        data: {
          'model': normalizedModel,
          'prompt': trimmedPrompt,
          'n': 1,
          'size': kImageGenerationSize,
          'response_format': 'b64_json',
        },
      );

      final data = response.data;
      final dataList = data?['data'];
      if (dataList is! List || dataList.isEmpty) {
        throw const ImageGenerationException('图片生成接口未返回图片数据');
      }
      final item = dataList.first;
      if (item is! Map) {
        throw const ImageGenerationException('图片生成接口返回格式异常');
      }

      final b64 = item['b64_json'];
      if (b64 is String && b64.isNotEmpty) {
        final Uint8List bytes;
        try {
          bytes = base64Decode(b64);
        } catch (_) {
          throw const ImageGenerationException('生成的图片 base64 数据损坏');
        }
        if (bytes.lengthInBytes > kImageGenerationMaxBytes) {
          throw const ImageGenerationException('生成图片过大，已拒绝保存');
        }
        return GeneratedImage(bytes: bytes, mimeType: 'image/png');
      }

      final url = item['url'];
      if (url is String && url.isNotEmpty) {
        return _downloadRemoteImage(url);
      }
      throw const ImageGenerationException('图片生成接口未返回可用图片');
    } on DioException catch (e) {
      throw ImageGenerationException(formatDioError(e));
    }
  }

  /// 中继只返回远端 URL 时安全下载图片字节（仅 HTTP(S)、限大小）。
  Future<GeneratedImage> _downloadRemoteImage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const ImageGenerationException('生成的图片 URL 无效');
    }
    final dio = getDio(uri.origin);
    try {
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const ImageGenerationException('下载生成的图片失败');
      }
      if (bytes.length > kImageGenerationMaxBytes) {
        throw const ImageGenerationException('生成图片过大，已拒绝保存');
      }
      return GeneratedImage(
        bytes: Uint8List.fromList(bytes),
        mimeType: 'image/png',
      );
    } on DioException catch (e) {
      throw ImageGenerationException(formatDioError(e));
    }
  }
}
