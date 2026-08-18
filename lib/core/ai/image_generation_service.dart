import 'dart:convert';
import 'dart:io';
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

/// 生成的图片结果。
class GeneratedImage {
  final Uint8List bytes;
  final String mimeType;
  final String extension;

  GeneratedImage({required this.bytes, String? mimeType, String? extension})
    : mimeType = _resolveImageMimeType(mimeType, bytes),
      extension = _resolveImageExtension(
        extension,
        _resolveImageMimeType(mimeType, bytes),
      );
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

  Future<GeneratedImage> generate(
    String prompt, {
    String? referenceImagePath,
    Map<String, dynamic> extra = const <String, dynamic>{},
    CancelToken? cancelToken,
    String size = kImageGenerationSize,
  }) async {
    if (referenceImagePath != null && referenceImagePath.trim().isNotEmpty) {
      // “参考图生成”在 OpenAI 兼容生态中通常由 images/edits 承载：
      // 统一走同一条 multipart 链路，既兼容 gpt-image / DALL·E 中转，
      // 也不会把本地参考图路径泄露到 JSON 请求中。
      return edit(
        imagePath: referenceImagePath,
        prompt: prompt,
        extra: extra,
        cancelToken: cancelToken,
        size: size,
      );
    }
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
      final fields = <String, dynamic>{
        'model': normalizedModel,
        'prompt': trimmedPrompt,
        'n': 1,
        'size': size,
        if (!_isGptImageModel(normalizedModel) &&
            !extra.containsKey('response_format') &&
            !extra.containsKey('output_format'))
          'response_format': 'b64_json',
        ...extra,
      };
      final response = await dio.post<List<int>>(
        resolveOpenAiEndpoint(baseUrl, 'images/generations'),
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.bytes,
        ),
        data: fields,
        cancelToken: cancelToken,
      );

      return await _parseGeneratedImage(
        response.data,
        contentType: response.headers.value('content-type'),
        formatHint: _imageFormatMimeHint(extra),
      );
    } on DioException catch (e) {
      throw ImageGenerationException(
        _formatImageEndpointError(e, operation: '图片生成'),
      );
    }
  }

  /// 图片编辑：OpenAI 兼容 `/v1/images/edits`（multipart）。
  ///
  /// `imagePath` 为本地参考图，`prompt` 为编辑提示词；返回编辑后的图片字节。
  Future<GeneratedImage> edit({
    required String imagePath,
    required String prompt,
    Map<String, dynamic> extra = const <String, dynamic>{},
    CancelToken? cancelToken,
    String size = kImageGenerationSize,
  }) async {
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
      throw const ImageGenerationException('编辑提示词不能为空');
    }
    if (trimmedPrompt.length > 4000) {
      throw const ImageGenerationException('编辑提示词过长，请精简后重试');
    }
    final File imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw const ImageGenerationException('参考图片文件不存在');
    }
    final imageSize = await imageFile.length();
    if (imageSize <= 0) {
      throw const ImageGenerationException('参考图片文件为空');
    }
    if (imageSize > kImageGenerationMaxBytes) {
      throw const ImageGenerationException('参考图片超过 10 MB，无法编辑');
    }

    final dio = getDio(normalizedBaseUrl);
    try {
      final fileName = imagePath.split('/').last.split('\\').last;
      final fields = <String, dynamic>{
        'model': normalizedModel,
        'prompt': trimmedPrompt,
        'n': 1,
        'size': size,
        ...extra,
      };
      final response = await dio.post<List<int>>(
        resolveOpenAiEndpoint(baseUrl, 'images/edits'),
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.bytes,
        ),
        data: FormData.fromMap({
          ...fields,
          'image': MultipartFile.fromBytes(
            await imageFile.readAsBytes(),
            filename: fileName,
            contentType: _dioMediaType(_mimeTypeForPath(imagePath)),
          ),
        }),
        cancelToken: cancelToken,
      );
      return await _parseGeneratedImage(
        response.data,
        contentType: response.headers.value('content-type'),
        formatHint: _imageFormatMimeHint(extra),
      );
    } on DioException catch (e) {
      throw ImageGenerationException(
        _formatImageEndpointError(e, operation: '图片编辑'),
      );
    }
  }

  /// 解析 `{data: [{b64_json | url}]}` 响应为图片字节。
  Future<GeneratedImage> _parseGeneratedImage(
    List<int>? body, {
    String? contentType,
    String? formatHint,
  }) async {
    final bytes = body ?? const <int>[];
    if (bytes.isEmpty) {
      throw const ImageGenerationException('图片接口未返回图片数据');
    }
    if (!_looksLikeJson(bytes, contentType: contentType)) {
      return _imageFromBytes(
        Uint8List.fromList(bytes),
        mimeHint:
            _firstUsableImageMime(<String?>[contentType, formatHint]) ??
            contentType ??
            formatHint,
      );
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(bytes).replaceFirst('\uFEFF', ''));
    } catch (_) {
      throw const ImageGenerationException('图片接口返回格式异常');
    }
    final dataList = data is Map ? data['data'] : null;
    final item = data is Map && dataList is List && dataList.isNotEmpty
        ? dataList.first
        : data is Map && dataList is Map
        ? dataList
        : data;
    if (item is! Map) {
      throw const ImageGenerationException('图片接口未返回图片数据');
    }

    final mimeHint = _imageMimeHint(item) ?? formatHint;
    for (final key in const [
      'b64_json',
      'b64Json',
      'base64_json',
      'base64Json',
      'base64',
      'base64_data',
      'base64Data',
      'data_uri',
      'dataUri',
      'data_url',
      'dataUrl',
    ]) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) {
        return _imageFromEncodedValue(value, mimeHint: mimeHint);
      }
    }

    for (final key in const ['url', 'image_url', 'imageUrl', 'uri']) {
      final url = item[key];
      if (url is String && url.trim().isNotEmpty) {
        final normalized = url.trim();
        if (_isDataUrl(normalized)) {
          return _imageFromEncodedValue(normalized, mimeHint: mimeHint);
        }
        return _downloadRemoteImage(normalized, mimeHint: mimeHint);
      }
    }
    throw const ImageGenerationException('图片接口未返回可用图片');
  }

  /// 中继只返回远端 URL 时安全下载图片字节（仅 HTTP(S)、限大小）。
  Future<GeneratedImage> _downloadRemoteImage(
    String url, {
    String? mimeHint,
  }) async {
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
      final responseMime = response.headers.value('content-type');
      return GeneratedImage(
        bytes: Uint8List.fromList(bytes),
        mimeType:
            _firstUsableImageMime(<String?>[
              responseMime,
              mimeHint,
              _mimeTypeForPath(uri.path),
            ]) ??
            responseMime ??
            mimeHint,
        extension: _extensionFromPath(uri.path),
      );
    } on DioException catch (e) {
      throw ImageGenerationException(formatDioError(e));
    }
  }
}

GeneratedImage _imageFromEncodedValue(String value, {String? mimeHint}) {
  final trimmed = value.trim();
  String? dataMime;
  String encoded = trimmed;
  if (_isDataUrl(trimmed)) {
    final comma = trimmed.indexOf(',');
    if (comma <= 5) {
      throw const ImageGenerationException('返回的图片 data URL 无效');
    }
    final header = trimmed.substring(5, comma);
    final parts = header.split(';');
    dataMime = parts.first.trim();
    final isBase64 = parts
        .skip(1)
        .any((part) => part.trim().toLowerCase() == 'base64');
    encoded = trimmed.substring(comma + 1);
    if (!isBase64) {
      try {
        return _imageFromBytes(
          Uint8List.fromList(utf8.encode(Uri.decodeComponent(encoded))),
          mimeHint: dataMime,
        );
      } catch (_) {
        throw const ImageGenerationException('返回的图片 data URL 无效');
      }
    }
  }

  try {
    final normalized = encoded.trim().replaceAll('-', '+').replaceAll('_', '/');
    final remainder = normalized.length % 4;
    final padded = remainder == 0
        ? normalized
        : remainder == 2
        ? '$normalized=='
        : remainder == 3
        ? '$normalized='
        : normalized;
    if (remainder == 1) throw const FormatException();
    return _imageFromBytes(
      Uint8List.fromList(base64Decode(padded)),
      mimeHint: dataMime ?? mimeHint,
    );
  } catch (error) {
    if (error is ImageGenerationException) rethrow;
    throw const ImageGenerationException('返回的图片 base64 数据损坏');
  }
}

GeneratedImage _imageFromBytes(
  Uint8List bytes, {
  String? mimeHint,
  String? extension,
}) {
  if (bytes.isEmpty) {
    throw const ImageGenerationException('图片接口返回空图片');
  }
  if (bytes.length > kImageGenerationMaxBytes) {
    throw const ImageGenerationException('图片过大，已拒绝保存');
  }
  return GeneratedImage(bytes: bytes, mimeType: mimeHint, extension: extension);
}

String? _imageMimeHint(Map item) {
  for (final key in const [
    'mime_type',
    'mimeType',
    'content_type',
    'contentType',
  ]) {
    final value = item[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  for (final key in const ['output_format', 'outputFormat', 'format']) {
    final value = item[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return null;
}

String? _imageFormatMimeHint(Map<String, dynamic> extra) {
  for (final key in const ['output_format', 'outputFormat', 'format']) {
    final value = extra[key];
    if (value is String && value.trim().isNotEmpty) {
      final mime = _normalizeImageMimeType(value);
      if (mime != null) return mime;
    }
  }
  return null;
}

String _resolveImageMimeType(String? declared, Uint8List bytes) {
  final normalized = _normalizeImageMimeType(declared);
  final detected = _detectImageMime(bytes);
  if (detected != null && (normalized == null || normalized != detected)) {
    return detected;
  }
  if (normalized != null) return normalized;
  if (detected != null) return detected;
  // OpenAI-compatible b64_json responses historically default to PNG when
  // no output format is supplied. Keep that protocol fallback only when no
  // stronger MIME or byte signature is available.
  return 'image/png';
}

String _resolveImageExtension(String? declared, String mimeType) {
  final normalized = declared?.trim().toLowerCase().replaceFirst('.', '');
  if (normalized != null && normalized.isNotEmpty) {
    return switch (normalized) {
      'jpeg' || 'jpg' => 'jpg',
      'png' => 'png',
      'webp' => 'webp',
      'gif' => 'gif',
      'bmp' => 'bmp',
      'avif' => 'avif',
      'svg' || 'svg+xml' => 'svg',
      _ => _extensionFromMimeType(mimeType),
    };
  }
  return _extensionFromMimeType(mimeType);
}

String? _normalizeImageMimeType(String? value) {
  if (value == null) return null;
  final normalized = value.trim().toLowerCase().split(';').first;
  return switch (normalized) {
    'jpg' || 'jpeg' || 'image/jpg' || 'image/jpeg' => 'image/jpeg',
    'png' || 'image/png' => 'image/png',
    'webp' || 'image/webp' => 'image/webp',
    'gif' || 'image/gif' => 'image/gif',
    'bmp' || 'image/bmp' => 'image/bmp',
    'avif' || 'image/avif' => 'image/avif',
    'svg' || 'svg+xml' || 'image/svg+xml' => 'image/svg+xml',
    _ => normalized.startsWith('image/') ? normalized : null,
  };
}

String? _firstUsableImageMime(Iterable<String?> values) {
  for (final value in values) {
    final normalized = _normalizeImageMimeType(value);
    if (normalized != null && normalized.startsWith('image/')) {
      return normalized;
    }
  }
  return null;
}

bool _isGptImageModel(String model) =>
    model.trim().toLowerCase().startsWith('gpt-image');

String _extensionFromMimeType(String mimeType) {
  return switch (mimeType.toLowerCase()) {
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    'image/bmp' => 'bmp',
    'image/avif' => 'avif',
    'image/svg+xml' => 'svg',
    _ => 'png',
  };
}

String? _extensionFromPath(String path) {
  final match = RegExp(
    r'\.([a-z0-9]{2,8})$',
    caseSensitive: false,
  ).firstMatch(path);
  return match?.group(1)?.toLowerCase();
}

String _mimeTypeForPath(String path) {
  final extension = _extensionFromPath(path);
  return _normalizeImageMimeType(extension) ?? 'image/png';
}

DioMediaType _dioMediaType(String mimeType) {
  final parts = mimeType.split('/');
  return DioMediaType(
    parts.first,
    parts.length > 1 ? parts[1] : 'octet-stream',
  );
}

bool _isDataUrl(String value) => value.trim().toLowerCase().startsWith('data:');

bool _looksLikePng(Uint8List bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4e &&
    bytes[3] == 0x47 &&
    bytes[4] == 0x0d &&
    bytes[5] == 0x0a &&
    bytes[6] == 0x1a &&
    bytes[7] == 0x0a;

bool _looksLikeJpeg(Uint8List bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xff &&
    bytes[1] == 0xd8 &&
    bytes[2] == 0xff;

bool _looksLikeGif(Uint8List bytes) =>
    bytes.length >= 6 &&
        String.fromCharCodes(bytes.sublist(0, 6)) == 'GIF89a' ||
    bytes.length >= 6 && String.fromCharCodes(bytes.sublist(0, 6)) == 'GIF87a';

bool _looksLikeWebp(Uint8List bytes) =>
    bytes.length >= 12 &&
    String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
    String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';

String? _detectImageMime(Uint8List bytes) {
  if (_looksLikeJpeg(bytes)) return 'image/jpeg';
  if (_looksLikeWebp(bytes)) return 'image/webp';
  if (_looksLikeGif(bytes)) return 'image/gif';
  if (_looksLikePng(bytes)) return 'image/png';
  return null;
}

bool _looksLikeJson(List<int> bytes, {String? contentType}) {
  if (contentType?.toLowerCase().contains('json') == true) return true;
  final text = utf8
      .decode(bytes.take(64).toList(), allowMalformed: true)
      .replaceFirst('\uFEFF', '')
      .trimLeft();
  return text.startsWith('{') || text.startsWith('[');
}

String _formatImageEndpointError(
  DioException error, {
  required String operation,
}) {
  final status = error.response?.statusCode;
  if (status == 404 || status == 405 || status == 501) {
    return '当前渠道不支持$operation接口，请切换渠道或检查 Base URL';
  }
  return formatDioError(error);
}
