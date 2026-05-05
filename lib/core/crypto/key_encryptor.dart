import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// API Key 加密工具
/// 使用 AES-CBC + PBKDF2 密钥派生，每次加密生成随机 IV
class KeyEncryptor {
  static const _passphrase = 'ai_chat_app_2024_secure';
  static const _saltPrefix = 'aichat_salt_v1_';
  static const _iterations = 10000;
  static const _keyLength = 32; // AES-256

  /// 加密 API Key
  static String encrypt(String plainText) {
    final key = _deriveKey(_passphrase);
    final iv = _randomBytes(16);
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), iv));
    final padded = _pkcs7Pad(utf8.encode(plainText), 16);
    final output = Uint8List(padded.length);
    for (var offset = 0; offset < padded.length; offset += 16) {
      cipher.processBlock(padded, offset, output, offset);
    }
    // IV:ciphertext (both base64)
    return '${base64Encode(iv)}:${base64Encode(output)}';
  }

  /// 解密 API Key（兼容旧的 base64 格式）
  static String decrypt(String encrypted) {
    // 新格式: IV:ciphertext (base64:base64)
    if (encrypted.contains(':') && !encrypted.contains('.')) {
      final parts = encrypted.split(':');
      if (parts.length == 2) {
        try {
          final iv = base64Decode(parts[0]);
          final ciphertext = base64Decode(parts[1]);
          final key = _deriveKey(_passphrase);
          final cipher = CBCBlockCipher(AESEngine())
            ..init(false, ParametersWithIV(KeyParameter(key), iv));
          final output = Uint8List(ciphertext.length);
          for (var offset = 0; offset < ciphertext.length; offset += 16) {
            cipher.processBlock(ciphertext, offset, output, offset);
          }
          return utf8.decode(_pkcs7Unpad(output));
        } catch (_) {
          // Fall through to legacy format
        }
      }
    }

    // 兼容旧格式: base64Encoded.sha256checksum
    return _decryptLegacy(encrypted);
  }

  /// 旧格式解密（兼容）
  static String _decryptLegacy(String encrypted) {
    final parts = encrypted.split('.');
    if (parts.length != 2) throw FormatException('Invalid encrypted key format');
    final encoded = parts[0];
    final checksum = parts[1];
    final plainText = utf8.decode(base64Decode(encoded));
    final bytes = utf8.encode(plainText + 'ai_chat_app_2024');
    final digest = sha256.convert(bytes);
    if (digest.toString().substring(0, 8) != checksum) {
      throw FormatException('Key integrity check failed');
    }
    return plainText;
  }

  static Uint8List _deriveKey(String passphrase) {
    final params = Pbkdf2Parameters(
      utf8.encode(_saltPrefix + passphrase),
      _iterations,
      _keyLength,
    );
    final generator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(params);
    return generator.process(utf8.encode(passphrase));
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  static Uint8List _pkcs7Pad(List<int> data, int blockSize) {
    final padLen = blockSize - (data.length % blockSize);
    return Uint8List.fromList([...data, ...List.filled(padLen, padLen)]);
  }

  static Uint8List _pkcs7Unpad(Uint8List data) {
    final padLen = data.last;
    if (padLen < 1 || padLen > 16) return data;
    return data.sublist(0, data.length - padLen);
  }
}
