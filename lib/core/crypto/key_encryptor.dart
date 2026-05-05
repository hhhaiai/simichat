import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 简单的 API Key 加密工具
/// 生产环境应使用 flutter_secure_storage，这里提供一个备用的混淆方案
class KeyEncryptor {
  static const _salt = 'ai_chat_app_2024';

  /// 加密 API Key（简单混淆，非对称加密用 flutter_secure_storage）
  static String encrypt(String plainText) {
    final bytes = utf8.encode(plainText + _salt);
    final digest = sha256.convert(bytes);
    // 将原文 base64 编码 + hash 前 8 位作为校验
    final encoded = base64Encode(utf8.encode(plainText));
    final checksum = digest.toString().substring(0, 8);
    return '$encoded.$checksum';
  }

  /// 解密 API Key
  static String decrypt(String encrypted) {
    final parts = encrypted.split('.');
    if (parts.length != 2) throw FormatException('Invalid encrypted key format');
    final encoded = parts[0];
    final checksum = parts[1];
    final plainText = utf8.decode(base64Decode(encoded));
    // 校验
    final bytes = utf8.encode(plainText + _salt);
    final digest = sha256.convert(bytes);
    if (digest.toString().substring(0, 8) != checksum) {
      throw FormatException('Key integrity check failed');
    }
    return plainText;
  }
}
