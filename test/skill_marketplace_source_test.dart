import 'dart:convert';

import 'package:ai_chat_app/core/skills/skill_hub_repository.dart';
import 'package:ai_chat_app/core/skills/skill_marketplace_source.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('GenericHttpSkillMarketplaceSource', () {
    test('searches index json with keyword filter', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'example.com');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'skills': [
                {
                  'id': 'web-search',
                  'name': 'Web Search',
                  'description': '搜索互联网',
                  'install_url': 'https://example.com/web-search/SKILL.md',
                },
                {
                  'id': 'translate',
                  'name': '翻译助手',
                  'description': '中英互译',
                  'install_url': 'https://example.com/translate/SKILL.md',
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final source = GenericHttpSkillMarketplaceSource(
        indexUrl: 'https://example.com/index.json',
        client: client,
      );

      final result = await source.search(keyword: 'search');
      expect(result.skills, hasLength(1));
      expect(result.skills.first.id, 'web-search');
      expect(result.total, 1);
    });

    test('installs skill with sha256 verification', () async {
      const instructions = '# Web Search\n\n搜索工具';
      final expectedSha = sha256.convert(utf8.encode(instructions)).toString();
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/index.json')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'skills': [
                  {
                    'id': 'web-search',
                    'name': 'Web Search',
                    'description': '搜索互联网',
                    'sha256': expectedSha,
                    'install_url': 'https://example.com/web-search/SKILL.md',
                  },
                ],
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response.bytes(utf8.encode(instructions), 200);
      });
      final source = GenericHttpSkillMarketplaceSource(
        indexUrl: 'https://example.com/index.json',
        client: client,
      );

      final result = await source.search(keyword: '');
      final installed = await source.install(result.skills.first);

      expect(installed.instructions, instructions);
      expect(installed.sourceSha256, expectedSha);
      expect(installed.sourceUrl, 'https://example.com/web-search/SKILL.md');
    });

    test('rejects install when sha256 mismatches', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/index.json')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'skills': [
                  {
                    'id': 'tampered',
                    'name': 'Tampered',
                    'description': 'x',
                    'sha256': 'a' * 64,
                    'install_url': 'https://example.com/tampered/SKILL.md',
                  },
                ],
              }),
            ),
            200,
          );
        }
        return http.Response.bytes(utf8.encode('内容'), 200);
      });
      final source = GenericHttpSkillMarketplaceSource(
        indexUrl: 'https://example.com/index.json',
        client: client,
      );

      final result = await source.search(keyword: '');
      await expectLater(
        source.install(result.skills.first),
        throwsA(isA<SkillImportException>()),
      );
    });

    test('rejects non-http index url at fetch time', () async {
      final source = GenericHttpSkillMarketplaceSource(
        indexUrl: 'file:///tmp/x',
      );
      await expectLater(
        source.search(keyword: ''),
        throwsA(isA<SkillImportException>()),
      );
    });
  });

  group('SkillHubMarketplaceSource', () {
    test('exposes skillhub source identity', () {
      final source = SkillHubMarketplaceSource();
      expect(source.sourceId, 'skillhub');
      expect(source.sourceName, contains('SkillHub'));
    });
  });
}
