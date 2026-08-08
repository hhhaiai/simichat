import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';

void main() {
  group('KeyEncryptor', () {
    test('encrypt and decrypt round-trip', () {
      const original = 'sk-test-key-12345';
      final encrypted = KeyEncryptor.encrypt(original);
      final decrypted = KeyEncryptor.decrypt(encrypted);
      expect(decrypted, original);
    });

    test('encrypted format has two parts separated by colon', () {
      final encrypted = KeyEncryptor.encrypt('test');
      final parts = encrypted.split(':');
      expect(parts.length, 2);
      expect(parts[0], isNotEmpty);
      expect(parts[1], isNotEmpty);
    });

    test('empty string round-trip', () {
      final encrypted = KeyEncryptor.encrypt('');
      final decrypted = KeyEncryptor.decrypt(encrypted);
      expect(decrypted, '');
    });

    test('decryptOrEmpty accepts an unencrypted empty optional key', () {
      expect(KeyEncryptor.decryptOrEmpty(''), isEmpty);
      expect(KeyEncryptor.decryptOrEmpty(KeyEncryptor.encrypt('')), isEmpty);
      expect(
        KeyEncryptor.decryptOrEmpty(KeyEncryptor.encrypt('local-proxy-key')),
        'local-proxy-key',
      );
    });

    test('decrypt supports legacy dot format', () {
      const original = 'legacy-secret';
      final encoded = base64Encode(utf8.encode(original));
      final checksum = sha256
          .convert(utf8.encode('${original}ai_chat_app_2024'))
          .toString()
          .substring(0, 8);

      final decrypted = KeyEncryptor.decrypt('$encoded.$checksum');
      expect(decrypted, original);
    });

    test('decrypt throws on invalid format', () {
      expect(() => KeyEncryptor.decrypt('invalid'), throwsFormatException);
    });

    test('decrypt throws on malformed encrypted payload', () {
      final encrypted = KeyEncryptor.encrypt('secret');
      final parts = encrypted.split(':');
      final tampered = '${parts[0]}:!!!!';
      expect(() => KeyEncryptor.decrypt(tampered), throwsFormatException);
    });

    test('decrypt throws on tampered legacy data', () {
      const original = 'legacy-secret';
      final encoded = base64Encode(utf8.encode(original));
      final tampered = '$encoded.ffffffff';
      expect(() => KeyEncryptor.decrypt(tampered), throwsFormatException);
    });
  });
}
