import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'skill_hub_repository.dart';

/// 市场技能条目（来源无关的通用形态）。
class SkillMarketplaceSkill {
  final String id;
  final String name;
  final String description;
  final String? author;
  final String? category;
  final String? version;

  /// SKILL.md 的安装地址（通用来源用）。
  final String? installUrl;

  /// 可选完整性校验（SHA-256 hex）。
  final String? sha256;

  const SkillMarketplaceSkill({
    required this.id,
    required this.name,
    required this.description,
    this.author,
    this.category,
    this.version,
    this.installUrl,
    this.sha256,
  });
}

class SkillMarketplaceSearchResult {
  final List<SkillMarketplaceSkill> skills;
  final int total;
  const SkillMarketplaceSearchResult({
    required this.skills,
    required this.total,
  });
}

/// 技能市场来源抽象：统一搜索 + 安装，便于接入 SkillHub / OpenClaw / 自定义来源。
abstract interface class SkillMarketplaceSource {
  String get sourceId;
  String get sourceName;
  Future<SkillMarketplaceSearchResult> search({
    String keyword = '',
    int page = 1,
  });

  /// 安装：拉取 SKILL.md 内容（带完整性校验）。
  Future<InstalledSkillBundle> install(SkillMarketplaceSkill skill);
}

/// 安装产物。
class InstalledSkillBundle {
  final String skillName;
  final String skillDescription;
  final String instructions;
  final String? sourceUrl;
  final String? sourceSha256;
  const InstalledSkillBundle({
    required this.skillName,
    required this.skillDescription,
    required this.instructions,
    this.sourceUrl,
    this.sourceSha256,
  });
}

/// SkillHub 来源：适配既有 [SkillHubRepository]。
class SkillHubMarketplaceSource implements SkillMarketplaceSource {
  SkillHubMarketplaceSource({SkillHubRepository? repository})
    : _repository = repository ?? SkillHubRepository();

  final SkillHubRepository _repository;

  void dispose() => _repository.dispose();

  @override
  String get sourceId => 'skillhub';
  @override
  String get sourceName => 'SkillHub.cn';

  @override
  Future<SkillMarketplaceSearchResult> search({
    String keyword = '',
    int page = 1,
  }) async {
    final result = await _repository.searchSkillHub(
      keyword: keyword,
      page: page,
    );
    return SkillMarketplaceSearchResult(
      total: result.total,
      skills: result.skills.map(_fromSummary).toList(growable: false),
    );
  }

  SkillMarketplaceSkill _fromSummary(SkillHubSkillSummary s) {
    return SkillMarketplaceSkill(
      id: s.slug,
      name: s.name,
      description: s.description,
      author: s.ownerName,
      category: s.category,
      version: s.version,
    );
  }

  @override
  Future<InstalledSkillBundle> install(SkillMarketplaceSkill skill) async {
    final imported = await _repository.importSkillHubSkill(skill.id);
    return InstalledSkillBundle(
      skillName: imported.name,
      skillDescription: imported.description,
      instructions: imported.instructions,
      sourceUrl: imported.sourceUrl,
      sourceSha256: imported.sourceSha256,
    );
  }
}

/// 通用 HTTP 技能来源：从可配置 URL 拉取技能索引 JSON。
///
/// 索引格式：
/// ```json
/// {
///   "skills": [
///     {
///       "id": "slug",
///       "name": "技能名",
///       "description": "说明",
///       "sha256": "SKILL.md 的 SHA-256 hex（可选）",
///       "install_url": "https://example.com/.../SKILL.md"
///     }
///   ]
/// }
/// ```
class GenericHttpSkillMarketplaceSource implements SkillMarketplaceSource {
  GenericHttpSkillMarketplaceSource({
    required this.indexUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String indexUrl;
  final http.Client _client;
  static const _maxIndexBytes = kMaxSkillDownloadBytes;
  static const _maxSkillBytes = kMaxSkillDownloadBytes;
  static const _maxResults = 1000;
  static final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

  void dispose() => _client.close();

  @override
  String get sourceId => 'generic-http';
  @override
  String get sourceName => '自定义 HTTP 技能源';

  Future<Map<String, dynamic>> _fetchIndex() async {
    final uri = Uri.parse(indexUrl);
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw SkillImportException('技能源地址仅支持 HTTP(S)');
    }
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw SkillImportException('技能源请求失败：HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.length > _maxIndexBytes) {
      throw const SkillImportException('技能源索引超过 512KB，已拒绝读取');
    }
    final decoded = _decodeJson(response.bodyBytes);
    if (decoded is! Map) {
      throw const SkillImportException('技能源索引结构异常：缺少对象');
    }
    return decoded.cast<String, dynamic>();
  }

  @override
  Future<SkillMarketplaceSearchResult> search({
    String keyword = '',
    int page = 1,
  }) async {
    final data = await _fetchIndex();
    final skills = (data['skills'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_fromJson)
        .where(
          (s) =>
              keyword.trim().isEmpty ||
              s.name.toLowerCase().contains(keyword.trim().toLowerCase()) ||
              s.description.toLowerCase().contains(
                keyword.trim().toLowerCase(),
              ),
        )
        .take(_maxResults)
        .toList(growable: false);
    const pageSize = 20;
    final normalizedPage = page < 1 ? 1 : page;
    final start = (normalizedPage - 1) * pageSize;
    final paged = start >= skills.length
        ? <SkillMarketplaceSkill>[]
        : skills.sublist(start, (start + pageSize).clamp(0, skills.length));
    return SkillMarketplaceSearchResult(total: skills.length, skills: paged);
  }

  SkillMarketplaceSkill _fromJson(Map<String, dynamic> json) {
    return SkillMarketplaceSkill(
      id: json['id']?.toString() ?? json['name']?.toString() ?? '',
      name: (json['name'] ?? json['id'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      category: json['category']?.toString(),
      version: json['version']?.toString(),
      installUrl: json['install_url']?.toString(),
      sha256: json['sha256']?.toString(),
    );
  }

  @override
  Future<InstalledSkillBundle> install(SkillMarketplaceSkill skill) async {
    final installUrl = skill.installUrl;
    if (installUrl == null || installUrl.trim().isEmpty) {
      throw SkillImportException('技能「${skill.name}」缺少 install_url，无法安装');
    }
    final uri = Uri.parse(installUrl);
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw SkillImportException('技能安装地址仅支持 HTTP(S)');
    }
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw SkillImportException('技能文件请求失败：HTTP ${response.statusCode}');
    }
    final bodyBytes = response.bodyBytes;
    if (bodyBytes.length > _maxSkillBytes) {
      throw const SkillImportException('Skill 文件超过 512KB，已拒绝安装');
    }
    final instructions = _decodeUtf8(bodyBytes);
    if (instructions.trim().isEmpty) {
      throw SkillImportException('技能「${skill.name}」的 SKILL.md 为空');
    }
    final expectedSha = skill.sha256?.trim().toLowerCase();
    if (expectedSha != null && expectedSha.isNotEmpty) {
      if (!_sha256Pattern.hasMatch(expectedSha)) {
        throw SkillImportException('技能「${skill.name}」SHA-256 元数据不合法');
      }
      final actual = sha256.convert(bodyBytes).toString();
      if (actual != expectedSha) {
        throw SkillImportException('技能「${skill.name}」SHA-256 校验失败，已拒绝安装');
      }
    }
    return InstalledSkillBundle(
      skillName: skill.name,
      skillDescription: skill.description,
      instructions: instructions,
      sourceUrl: installUrl,
      sourceSha256: skill.sha256,
    );
  }

  dynamic _decodeJson(List<int> bytes) {
    try {
      return jsonDecode(_decodeUtf8(bytes));
    } on Object {
      throw const SkillImportException('技能源索引不是有效 JSON');
    }
  }

  String _decodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const SkillImportException('技能响应不是有效 UTF-8 文本');
    }
  }
}

/// 可用的市场来源列表。
List<SkillMarketplaceSource> kSkillMarketplaceSources({
  SkillHubRepository? skillHubRepository,
}) {
  return [
    SkillHubMarketplaceSource(repository: skillHubRepository),
    GenericHttpSkillMarketplaceSource(
      indexUrl:
          'https://raw.githubusercontent.com/OpenClaw-ai/skills/main/index.json',
    ),
  ];
}
