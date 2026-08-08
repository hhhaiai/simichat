import 'dart:convert';

import '../skills/skill.dart';
import 'mobile_extension_manifest.dart';

class MobileAgentDefinitionException implements Exception {
  const MobileAgentDefinitionException(this.message);

  final String message;

  @override
  String toString() => 'Invalid mobile agent definition: $message';
}

/// Declarative agent payload. It contains no executable code.
class MobileAgentDefinition {
  const MobileAgentDefinition({
    required this.id,
    required this.name,
    required this.model,
    required this.systemPrompt,
    required this.skillIds,
    required this.mcpServerIds,
    required this.permissions,
  });

  final String id;
  final String name;
  final String model;
  final String systemPrompt;
  final List<String> skillIds;
  final List<String> mcpServerIds;
  final List<String> permissions;

  factory MobileAgentDefinition.fromPackage(MobileExtensionPackage package) {
    final manifest = package.manifest;
    if (manifest.type != MobileExtensionType.agent ||
        manifest.runtime != MobileExtensionRuntime.declarative) {
      throw const MobileAgentDefinitionException(
        '不是 declarative Agent package',
      );
    }
    final rawEntry = package.files[manifest.entry];
    if (rawEntry == null) {
      throw const MobileAgentDefinitionException('Agent entry 文件不存在');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(rawEntry));
    } on Object {
      throw const MobileAgentDefinitionException('Agent entry 不是有效 JSON');
    }
    if (decoded is! Map) {
      throw const MobileAgentDefinitionException('Agent entry 顶层必须是 object');
    }
    final json = decoded.cast<String, dynamic>();
    final name = _optionalString(json['name']) ?? manifest.name ?? manifest.id;
    final model = _optionalString(json['model']) ?? 'gemma4';
    final promptRef = _optionalString(json['prompt']);
    String? prompt = _optionalString(json['systemPrompt']);
    if (promptRef != null) {
      MobileExtensionManifest.validateRelativePath(promptRef, field: 'prompt');
      final promptBytes = package.files[promptRef];
      if (promptBytes == null) {
        throw MobileAgentDefinitionException('Agent prompt 文件不存在: $promptRef');
      }
      try {
        prompt = utf8.decode(promptBytes);
      } on FormatException {
        throw MobileAgentDefinitionException(
          'Agent prompt 不是有效 UTF-8: $promptRef',
        );
      }
    }
    if (prompt == null || prompt.trim().isEmpty) {
      throw const MobileAgentDefinitionException(
        'Agent 必须声明 prompt 或 systemPrompt',
      );
    }
    final permissions = <String>{
      ...manifest.permissions,
      ..._stringList(json['permissions'], 'permissions'),
    }.toList(growable: false);
    final unknownPermissions = permissions
        .where(
          (permission) => !kMobileExtensionPermissions.contains(permission),
        )
        .toList(growable: false);
    if (unknownPermissions.isNotEmpty) {
      throw MobileAgentDefinitionException(
        'Agent permissions 包含未知 capability: ${unknownPermissions.join(', ')}',
      );
    }
    return MobileAgentDefinition(
      id: manifest.id,
      name: name,
      model: model,
      systemPrompt: prompt,
      skillIds: _stringList(json['skills'], 'skills'),
      mcpServerIds: _stringList(json['mcpServers'], 'mcpServers'),
      permissions: permissions,
    );
  }
}

class MobileAgentExecutionPlan {
  const MobileAgentExecutionPlan({
    required this.agent,
    required this.model,
    required this.systemPrompt,
    required this.skillIds,
    required this.mcpServerIds,
    required this.permissions,
  });

  final MobileAgentDefinition agent;
  final String model;
  final String systemPrompt;
  final List<String> skillIds;
  final List<String> mcpServerIds;
  final List<String> permissions;
}

/// Turns a declarative Agent into the exact local request plan.
///
/// The actual model call remains owned by the existing Flutter AI service. In
/// particular, this planner does not spawn a process and cannot silently
/// replace the user's configured provider. When the agent does not specify a
/// model, `gemma4` is the stable local-model default.
class MobileAgentRuntime {
  const MobileAgentRuntime();

  MobileAgentExecutionPlan buildPlan({
    required MobileAgentDefinition agent,
    required Iterable<Skill> availableSkills,
    required Iterable<String> availableMcpServerIds,
  }) {
    final skills = availableSkills
        .where((skill) => skill.isEnabled && agent.skillIds.contains(skill.id))
        .toList(growable: false);
    final missingSkills = agent.skillIds
        .where((id) => !skills.any((skill) => skill.id == id))
        .toList(growable: false);
    if (missingSkills.isNotEmpty) {
      throw MobileAgentDefinitionException(
        'Agent 依赖的 Skill 未启用或不存在: ${missingSkills.join(', ')}',
      );
    }

    final availableMcp = availableMcpServerIds.toSet();
    final missingMcp = agent.mcpServerIds
        .where((id) => !availableMcp.contains(id))
        .toList(growable: false);
    if (missingMcp.isNotEmpty) {
      throw MobileAgentDefinitionException(
        'Agent 依赖的 MCP 未连接: ${missingMcp.join(', ')}',
      );
    }

    final skillsPrompt = buildSkillsSystemPrompt(skills);
    final systemPrompt = skillsPrompt.isEmpty
        ? agent.systemPrompt
        : '${agent.systemPrompt}\n\n$skillsPrompt';
    return MobileAgentExecutionPlan(
      agent: agent,
      model: agent.model.trim().isEmpty ? 'gemma4' : agent.model.trim(),
      systemPrompt: systemPrompt,
      skillIds: List.unmodifiable(agent.skillIds),
      mcpServerIds: List.unmodifiable(agent.mcpServerIds),
      permissions: List.unmodifiable(agent.permissions),
    );
  }
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final result = value.trim();
  return result.isEmpty ? null : result;
}

List<String> _stringList(Object? value, String field) {
  if (value == null) return const <String>[];
  if (value is! List || value.any((item) => item is! String)) {
    throw MobileAgentDefinitionException('$field 必须是字符串数组');
  }
  return value
      .cast<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
