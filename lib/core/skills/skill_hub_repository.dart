import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'skill.dart';

/// SkillHub.cn API 客户端 + 本地持久化
class SkillHubRepository {
  SkillHubRepository({http.Client? client, Uri? skillHubApiBase})
      : _client = client ?? http.Client(),
        _skillHubApiBase = skillHubApiBase ?? Uri.parse(skillHubApiBaseUrl);

  static const skillHubHomeUrl = 'https://skillhub.cn/';
  static const skillHubApiBaseUrl = 'https://api.skillhub.cn';
  static const _storageFileName = 'online_skills.json';
  static const _maxSkillBytes = 512 * 1024;
  static const _skillHubPageSize = 20;
  static final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

  final http.Client _client;
  final Uri _skillHubApiBase;

  // ─── 本地持久化 ───

  Future<List<Skill>> loadOnlineSkills() async {
    final file = await _storageFile();
    if (!await file.exists()) return const [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(_skillFromJson)
        .where((s) => s.name.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<List<Skill>> saveOnlineSkill(Skill skill) async {
    final skills = await loadOnlineSkills();
    final merged = <Skill>[
      for (final item in skills)
        if (item.name != skill.name) item,
      skill,
    ]..sort((a, b) => a.name.compareTo(b.name));
    await _saveOnlineSkills(merged);
    return merged;
  }

  Future<List<Skill>> deleteOnlineSkill(String name) async {
    final skills = await loadOnlineSkills();
    final remaining =
        skills.where((s) => s.name != name).toList(growable: false);
    await _saveOnlineSkills(remaining);
    return remaining;
  }

  // ─── SkillHub 搜索 ───

  Future<SkillHubSearchResult> searchSkillHub({
    String keyword = '',
    int page = 1,
    int pageSize = _skillHubPageSize,
  }) async {
    final normalizedPage = page < 1 ? 1 : page;
    final normalizedPageSize = pageSize.clamp(1, 50).toInt();
    final query = <String, String>{
      'page': normalizedPage.toString(),
      'pageSize': normalizedPageSize.toString(),
      if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
    };
    final uri = _skillHubUri('/api/skills', query);
    final decoded = await _getJson(uri);
    if (decoded['code'] != 0) {
      throw SkillImportException(
        'SkillHub 返回错误：${decoded['message'] ?? decoded['code']}',
      );
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const SkillImportException('SkillHub 返回结构异常：缺少 data。');
    }
    final skills = (data['skills'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SkillHubSkillSummary.fromJson)
        .where((s) => s.slug.isNotEmpty)
        .toList(growable: false);
    return SkillHubSearchResult(
      skills: skills,
      total: _intFromJson(data['total']),
      page: normalizedPage,
      pageSize: normalizedPageSize,
      keyword: keyword.trim(),
    );
  }

  // ─── SkillHub 导入 ───

  Future<Skill> importSkillHubSkill(String slug) async {
    final normalizedSlug = _normalizeSkillHubSlug(slug);
    final filesUri = _skillHubUri('/api/v1/skills/$normalizedSlug/files');
    final filesJson = await _getJson(filesUri);
    final files = (filesJson['files'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final skillFile = files.cast<Map<String, dynamic>?>().firstWhere(
          (f) {
            final path = f?['path']?.toString() ?? '';
            return path == 'SKILL.md' || path.endsWith('/SKILL.md');
          },
          orElse: () => null,
        );
    if (skillFile == null) {
      throw SkillImportException(
        'SkillHub skill `$normalizedSlug` 没有 SKILL.md。',
      );
    }
    final skillPath = skillFile['path']?.toString() ?? 'SKILL.md';
    final size = _intFromJson(skillFile['size']);
    final expectedSha256 = _sha256FromJson(skillFile['sha256']);
    if (expectedSha256 == null) {
      throw SkillImportException(
        'SkillHub skill `$normalizedSlug` 的 SKILL.md 缺少 sha256，已拒绝导入。',
      );
    }
    if (size > _maxSkillBytes) {
      throw const SkillImportException('Skill 文件超过 512KB，已拒绝导入。');
    }

    final skillUri = _skillHubUri('/api/v1/skills/$normalizedSlug/file', {
      'path': skillPath,
    });
    final response = await _get(skillUri);
    final bodyBytes = response.bodyBytes;
    final body = response.body;
    if (bodyBytes.length > _maxSkillBytes) {
      throw const SkillImportException('Skill 文件超过 512KB，已拒绝导入。');
    }
    final actualSha256 = _sha256Hex(bodyBytes);
    if (actualSha256 != expectedSha256) {
      throw SkillImportException(
        'SkillHub skill `$normalizedSlug` 的 SKILL.md sha256 校验失败，已拒绝导入。',
      );
    }
    return _parseSkillMarkdown(
      body,
      sourceUrl: skillUri.toString(),
      sourceSha256: actualSha256,
      sha256Verified: true,
      fallbackName: normalizedSlug,
    );
  }

  // ─── URL 导入 ───

  Future<Skill> importFromUrl(String inputUrl) async {
    final normalized = _normalizeSkillUrl(inputUrl);
    final response = await _get(normalized);
    var bodyBytes = response.bodyBytes;
    var body = response.body;
    var sourceUrl = normalized.toString();

    if (_looksLikeHtml(response, body)) {
      final linkedSkill = _findSkillMarkdownLink(normalized, body);
      if (linkedSkill == null) {
        throw const SkillImportException(
          '这个页面不像 SKILL.md，也没有找到指向 SKILL.md 的链接。',
        );
      }
      final linkedResponse = await _get(linkedSkill);
      bodyBytes = linkedResponse.bodyBytes;
      body = linkedResponse.body;
      sourceUrl = linkedSkill.toString();
    }

    if (bodyBytes.length > _maxSkillBytes) {
      throw const SkillImportException('Skill 文件超过 512KB，已拒绝导入。');
    }
    return _parseSkillMarkdown(
      body,
      sourceUrl: sourceUrl,
      sourceSha256: _sha256Hex(bodyBytes),
      sha256Verified: false,
    );
  }

  // ─── 内部方法 ───

  Future<File> _storageFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_storageFileName');
  }

  Future<void> _saveOnlineSkills(List<Skill> skills) async {
    final file = await _storageFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(skills.map(_skillToJson).toList(growable: false)),
    );
  }

  Future<http.Response> _get(Uri uri) async {
    final response = await _client
        .get(
          uri,
          headers: const {
            'accept': 'text/markdown,text/plain,text/html;q=0.8,*/*;q=0.5',
            'user-agent': 'ai_chat_app Skills Hub importer',
          },
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SkillImportException(
        '下载失败：HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}',
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client
        .get(
          uri,
          headers: const {
            'accept': 'application/json,text/plain;q=0.8,*/*;q=0.5',
            'user-agent': 'ai_chat_app Skills Hub importer',
          },
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SkillImportException(
        'SkillHub 请求失败：HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SkillImportException('SkillHub 返回不是 JSON object。');
    }
    return decoded;
  }

  Uri _skillHubUri(String path, [Map<String, String>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return _skillHubApiBase.replace(
      path: normalizedPath,
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Uri _normalizeSkillUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const SkillImportException('请输入线上 Skill URL。');
    }
    var uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      uri = Uri.tryParse('https://$trimmed');
    }
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw const SkillImportException('只支持 http/https URL。');
    }
    if (uri.host == 'github.com' && uri.path.contains('/blob/')) {
      final parts = uri.pathSegments;
      final blobIndex = parts.indexOf('blob');
      if (parts.length > blobIndex + 2) {
        final owner = parts[0];
        final repo = parts[1];
        final ref = parts[blobIndex + 1];
        final rest = parts.sublist(blobIndex + 2).join('/');
        return Uri.https(
          'raw.githubusercontent.com',
          '/$owner/$repo/$ref/$rest',
        );
      }
    }
    return uri;
  }

  String _normalizeSkillHubSlug(String slug) {
    final normalized = slug.trim();
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{1,127}$').hasMatch(normalized)) {
      throw SkillImportException('SkillHub slug 不合法：$slug');
    }
    return normalized;
  }

  String? _sha256FromJson(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return null;
    if (!_sha256Pattern.hasMatch(normalized)) {
      throw SkillImportException('sha256 元数据不合法：$normalized');
    }
    return normalized;
  }

  String _sha256Hex(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();

  bool _looksLikeHtml(http.Response response, String body) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final prefix = body.trimLeft().toLowerCase();
    return contentType.contains('text/html') ||
        prefix.startsWith('<!doctype html') ||
        prefix.startsWith('<html');
  }

  Uri? _findSkillMarkdownLink(Uri base, String html) {
    final linkPattern = RegExp(
      r'''href=["']([^"']*(?:SKILL\.md|skill\.md)[^"']*)["']''',
      caseSensitive: false,
    );
    final match = linkPattern.firstMatch(html);
    if (match == null) return null;
    return base.resolve(match.group(1)!);
  }

  Skill _parseSkillMarkdown(
    String markdown, {
    required String sourceUrl,
    String? sourceSha256,
    bool sha256Verified = false,
    String? fallbackName,
  }) {
    final normalized = markdown.replaceAll('\r\n', '\n');
    final frontMatterMatch =
        RegExp(r'^---\s*\n([\s\S]*?)\n---\s*\n?').firstMatch(normalized);
    final frontMatter = frontMatterMatch?.group(1) ?? '';
    final body = frontMatterMatch == null
        ? normalized.trim()
        : normalized.substring(frontMatterMatch.end).trim();
    final meta = <String, String>{};
    for (final line in frontMatter.split('\n')) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      meta[key] = value.replaceAll(RegExp(r'''^["']|["']$'''), '');
    }
    final uri = Uri.tryParse(sourceUrl);
    final urlFallbackName = uri == null || uri.pathSegments.isEmpty
        ? 'online-skill'
        : uri.pathSegments.reversed.firstWhere(
            (seg) => seg.toLowerCase() != 'skill.md',
            orElse: () => 'online-skill',
          );
    final rawName =
        (meta['name'] ?? fallbackName ?? urlFallbackName).trim();
    final name = _sanitizeSkillName(rawName);
    final description =
        (meta['description'] ?? 'Online skill from $sourceUrl').trim();
    if (body.isEmpty) {
      throw const SkillImportException('Skill instructions 为空。');
    }
    return Skill(
      id: name,
      name: name,
      description: description,
      instructions: body.length > 20000 ? body.substring(0, 20000) : body,
      sourceUrl: sourceUrl,
      sourceSha256: sourceSha256,
      sha256Verified: sha256Verified,
      online: true,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static String _sanitizeSkillName(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-');
    s = s.replaceAll(RegExp(r'-{2,}'), '-');
    s = s.replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    if (s.length > 64) s = s.substring(0, 64);
    s = s.replaceAll(RegExp(r'[-.]+$'), '');
    if (s.length < 2) s = 'online-skill';
    return s;
  }

  Map<String, dynamic> _skillToJson(Skill skill) => {
        'id': skill.id,
        'name': skill.name,
        'description': skill.description,
        'instructions': skill.instructions,
        'sourceUrl': skill.sourceUrl,
        'sourceSha256': skill.sourceSha256,
        'sha256Verified': skill.sha256Verified,
        'online': skill.online,
        'isEnabled': skill.isEnabled,
        'createdAt': skill.createdAt,
      };

  Skill _skillFromJson(Map<String, dynamic> json) => Skill(
        id: json['id']?.toString() ?? json['name']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        instructions: json['instructions']?.toString() ?? '',
        sourceUrl: json['sourceUrl']?.toString(),
        sourceSha256: json['sourceSha256']?.toString(),
        sha256Verified: json['sha256Verified'] == true,
        online: json['online'] == true,
        isEnabled: json['isEnabled'] != false,
        createdAt: _intFromJson(json['createdAt']),
      );
}

// ─── 辅助类 ───

class SkillHubSearchResult {
  const SkillHubSearchResult({
    required this.skills,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.keyword,
  });

  final List<SkillHubSkillSummary> skills;
  final int total;
  final int page;
  final int pageSize;
  final String keyword;
}

class SkillHubSkillSummary {
  const SkillHubSkillSummary({
    required this.slug,
    required this.name,
    required this.description,
    required this.ownerName,
    required this.category,
    required this.source,
    required this.version,
    required this.downloads,
    required this.installs,
    required this.stars,
    required this.requiresApiKey,
  });

  factory SkillHubSkillSummary.fromJson(Map<String, dynamic> json) {
    final labels = json['labels'];
    final requiresApiKey = labels is Map
        ? labels['requires_api_key']?.toString().toLowerCase() == 'true'
        : false;
    return SkillHubSkillSummary(
      slug: json['slug']?.toString() ?? '',
      name: (json['name'] ?? json['slug'] ?? '').toString(),
      description:
          (json['description_zh'] ?? json['description'] ?? '').toString(),
      ownerName: json['ownerName']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      downloads: _intFromJson(json['downloads']),
      installs: _intFromJson(json['installs']),
      stars: _intFromJson(json['stars']),
      requiresApiKey: requiresApiKey,
    );
  }

  final String slug;
  final String name;
  final String description;
  final String ownerName;
  final String category;
  final String source;
  final String version;
  final int downloads;
  final int installs;
  final int stars;
  final bool requiresApiKey;
}

int _intFromJson(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class SkillImportException implements Exception {
  const SkillImportException(this.message);
  final String message;

  @override
  String toString() => message;
}
