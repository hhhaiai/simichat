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

    test('encrypted format has two parts separated by dot', () {
      final encrypted = KeyEncryptor.encrypt('test');
      final parts = encrypted.split('.');
      expect(parts.length, 2);
      expect(parts[1].length, 8);
    });

    test('empty string round-trip', () {
      final encrypted = KeyEncryptor.encrypt('');
      final decrypted = KeyEncryptor.decrypt(encrypted);
      expect(decrypted, '');
    });

    test('decrypt throws on invalid format', () {
      expect(() => KeyEncryptor.decrypt('invalid'), throwsFormatException);
    });

    test('decrypt throws on tampered data', () {
      final encrypted = KeyEncryptor.encrypt('secret');
      final parts = encrypted.split('.');
      final tampered = '${parts[0]}.ffffffff';
      expect(() => KeyEncryptor.decrypt(tampered), throwsFormatException);
    });
  });
}
