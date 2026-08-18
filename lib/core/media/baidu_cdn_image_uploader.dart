import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../ai/http_helper.dart';

/// 百度图床（image.baidu.com 图片编辑上传通道）上传器。
///
/// 协议与用户自有的 `imgtool.py` 保持一致：form-urlencoded 提交
/// `token` / `scene=pic_edit` / `picInfo`(data URI) / `timestamp`，
/// token = md5(md5(picInfo) + 'pic_edit' + timestamp) 的前 5 位。
/// 注意：这是非官方接口，仅按用户授权同其自有工具同等行为接入。
class BaiduCdnImageUploader {
  const BaiduCdnImageUploader({Uri? endpoint})
    : _endpoint = endpoint;

  static const _defaultEndpoint = 'https://image.baidu.com/aigc/pic_upload';
  static const _maxAttempts = 3;

  /// 可注入端点（测试用）。
  final Uri? _endpoint;

  /// 直接上传图片字节，返回 CDN URL。
  Future<String> uploadBytes(
    List<int> bytes, {
    required String mimeType,
  }) {
    if (bytes.isEmpty) {
      throw const BaiduCdnUploadException('图片数据为空');
    }
    if (bytes.length > 10 * 1024 * 1024) {
      throw const BaiduCdnUploadException('图片超过 10 MB，无法上传');
    }
    return _upload(mimeType: mimeType, bytes: bytes);
  }

  /// 上传本地图片文件，返回 CDN URL。
  Future<String> uploadFile(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw const BaiduCdnUploadException('图片文件不存在');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const BaiduCdnUploadException('图片文件为空');
    }
    if (bytes.length > 10 * 1024 * 1024) {
      throw const BaiduCdnUploadException('图片超过 10 MB，无法上传');
    }
    return _upload(
      mimeType: _mimeTypeForPath(imagePath),
      bytes: bytes,
    );
  }

  Future<String> _upload({
    required String mimeType,
    required List<int> bytes,
  }) async {
    final picInfo = 'data:$mimeType;base64,${base64Encode(bytes)}';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final token = _generateToken(picInfo, timestamp);
    final dio = createDio();

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await dio.post<Map<String, dynamic>>(
          (_endpoint ?? Uri.parse(_defaultEndpoint)).toString(),
          data: {
            'token': token,
            'scene': 'pic_edit',
            'picInfo': picInfo,
            'timestamp': timestamp,
          },
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              'Referer': 'https://image.baidu.com/',
              'Origin': 'https://image.baidu.com',
              'Accept': '*/*',
            },
            responseType: ResponseType.json,
          ),
        );
        final data = response.data?['data'];
        if (data is Map && data['url'] is String) {
          final url = (data['url'] as String).trim();
          if (url.isNotEmpty) return url;
        }
        lastError = '百度返回异常: ${response.data}';
      } on DioException catch (e) {
        lastError = formatDioError(e);
      } catch (e) {
        lastError = e.toString();
      }
      if (attempt < _maxAttempts) {
        await Future<void>.delayed(
          Duration(seconds: pow(2, attempt - 1).toInt()),
        );
      }
    }
    throw BaiduCdnUploadException('图床上传失败：$lastError');
  }

  static String _generateToken(String picInfo, String timestamp) {
    final first = md5.convert(utf8.encode(picInfo)).toString();
    final combined = '$first${'pic_edit'}$timestamp';
    final digest = md5.convert(utf8.encode(combined)).toString();
    return digest.substring(0, 5);
  }

  static String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/jpeg';
  }
}

class BaiduCdnUploadException implements Exception {
  const BaiduCdnUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}
