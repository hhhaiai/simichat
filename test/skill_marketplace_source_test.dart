import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/skills/skill_hub_repository.dart';
import 'package:ai_chat_app/core/skills/skill_marketplace_source.dart';
import 'package:ai_chat_app/core/skills/skill.dart';
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

    test('rejects oversized skill response before decoding it', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          List<int>.filled(kMaxSkillDownloadBytes + 1, 97),
          200,
        );
      });
      final source = GenericHttpSkillMarketplaceSource(
        indexUrl: 'https://example.com/index.json',
        client: client,
      );
      addTearDown(source.dispose);

      await expectLater(
        source.install(
          const SkillMarketplaceSkill(
            id: 'large',
            name: 'large',
            description: 'large',
            installUrl: 'https://example.com/large/SKILL.md',
          ),
        ),
        throwsA(isA<SkillImportException>()),
      );
    });

    test('rejects malformed sha256 metadata', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(utf8.encode('# skill'), 200);
      });
      final source = GenericHttpSkillMarketplaceSource(
        indexUrl: 'https://example.com/index.json',
        client: client,
      );
      addTearDown(source.dispose);

      await expectLater(
        source.install(
          const SkillMarketplaceSkill(
            id: 'bad-sha',
            name: 'bad-sha',
            description: 'bad-sha',
            installUrl: 'https://example.com/bad-sha/SKILL.md',
            sha256: 'not-a-sha256',
          ),
        ),
        throwsA(isA<SkillImportException>()),
      );
    });

    test(
      'normalizes negative page before slicing the mobile result list',
      () async {
        final client = MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'skills': [
                  {
                    'id': 'one',
                    'name': 'one',
                    'description': 'one',
                    'install_url': 'https://example.com/one/SKILL.md',
                  },
                ],
              }),
            ),
            200,
          );
        });
        final source = GenericHttpSkillMarketplaceSource(
          indexUrl: 'https://example.com/index.json',
          client: client,
        );
        addTearDown(source.dispose);

        final result = await source.search(page: -10);
        expect(result.skills, hasLength(1));
      },
    );
  });

  group('SkillHubMarketplaceSource', () {
    test('exposes skillhub source identity', () {
      final source = SkillHubMarketplaceSource();
      expect(source.sourceId, 'skillhub');
      expect(source.sourceName, contains('SkillHub'));
    });

    test('quarantines corrupt local online skill storage', () async {
      final directory = await Directory.systemTemp.createTemp(
        'simichat-online-skills-corrupt-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/online_skills.json');
      final before = await file.exists() ? await file.readAsBytes() : null;
      final existingCorruptFiles = <String>{};
      final parent = Directory(directory.path);
      if (await parent.exists()) {
        await for (final entry in parent.list()) {
          if (entry.path.startsWith('${file.path}.corrupt')) {
            existingCorruptFiles.add(entry.path);
          }
        }
      }

      try {
        await file.parent.create(recursive: true);
        await file.writeAsString('{broken-json');
        final repository = SkillHubRepository(
          client: MockClient((_) async => http.Response('{}', 200)),
          storageDirectory: directory,
        );
        addTearDown(repository.dispose);

        expect(await repository.loadOnlineSkills(), isEmpty);
        expect(await file.exists(), isFalse);
        final quarantined = <File>[];
        await for (final entry in parent.list()) {
          if (entry is File &&
              entry.path.startsWith('${file.path}.corrupt') &&
              !existingCorruptFiles.contains(entry.path)) {
            quarantined.add(entry);
          }
        }
        expect(quarantined, isNotEmpty);
      } finally {
        await for (final entry in parent.list()) {
          if (entry.path.startsWith('${file.path}.corrupt') &&
              !existingCorruptFiles.contains(entry.path)) {
            await entry.delete();
          }
        }
        if (before == null) {
          if (await file.exists()) await file.delete();
        } else {
          await file.writeAsBytes(before, flush: true);
        }
      }
    });

    test('writes online skills through a complete temporary file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'simichat-online-skills-atomic-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/online_skills.json');
      final before = await file.exists() ? await file.readAsBytes() : null;
      final repository = SkillHubRepository(
        client: MockClient((_) async => http.Response('{}', 200)),
        storageDirectory: directory,
      );
      addTearDown(repository.dispose);

      try {
        await repository.saveOnlineSkill(
          const Skill(
            id: 'mobile-skill',
            name: 'mobile-skill',
            description: 'test',
            instructions: '稳定工作',
            online: true,
            createdAt: 1,
          ),
        );
        final decoded = jsonDecode(await file.readAsString());
        expect(decoded, isA<List>());
        expect((decoded as List).single['name'], 'mobile-skill');
        expect(await File('${file.path}.tmp').exists(), isFalse);
      } finally {
        if (before == null) {
          if (await file.exists()) await file.delete();
        } else {
          await file.writeAsBytes(before, flush: true);
        }
      }
    });
  });
}
