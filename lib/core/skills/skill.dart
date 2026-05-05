/// Skill 数据模型
class Skill {
  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.instructions,
    this.sourceUrl,
    this.sourceSha256,
    this.sha256Verified = false,
    this.online = false,
    this.isEnabled = true,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final String instructions;
  final String? sourceUrl;
  final String? sourceSha256;
  final bool sha256Verified;
  final bool online;
  final bool isEnabled;
  final int createdAt;

  Skill copyWith({
    String? id,
    String? name,
    String? description,
    String? instructions,
    String? sourceUrl,
    String? sourceSha256,
    bool? sha256Verified,
    bool? online,
    bool? isEnabled,
    int? createdAt,
  }) {
    return Skill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      instructions: instructions ?? this.instructions,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceSha256: sourceSha256 ?? this.sourceSha256,
      sha256Verified: sha256Verified ?? this.sha256Verified,
      online: online ?? this.online,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 构建 skills 系统提示词片段
String buildSkillsSystemPrompt(Iterable<Skill> skills) {
  final enabled = skills.where((s) => s.isEnabled).toList();
  if (enabled.isEmpty) return '';

  final buffer = StringBuffer();
  buffer.writeln('## Enabled Skills');
  buffer.writeln(
    'The following skills are available. '
    'When a user request matches a skill, follow its instructions precisely.',
  );
  for (final skill in enabled) {
    buffer.writeln();
    buffer.writeln('### ${skill.name}');
    if (skill.description.isNotEmpty) {
      buffer.writeln('Description: ${skill.description}');
    }
    buffer.writeln('Instructions:');
    buffer.writeln(skill.instructions);
  }
  return buffer.toString();
}

/// 内置 Skills 列表
final builtInSkills = <Skill>[
  Skill(
    id: 'builtin-code-reviewer',
    name: 'code-reviewer',
    description: '代码审查助手，检查代码质量、安全性和最佳实践',
    instructions: '''你是一个专业的代码审查助手。当用户分享代码时，请从以下维度进行审查：
1. **正确性**：代码逻辑是否正确，是否有 bug
2. **安全性**：是否存在安全漏洞（SQL 注入、XSS、硬编码密钥等）
3. **性能**：是否有性能瓶颈或可优化之处
4. **可读性**：命名、结构、注释是否清晰
5. **最佳实践**：是否遵循语言/框架的惯用模式

给出具体的问题描述和改进建议，必要时提供修改后的代码。''',
    createdAt: 0,
  ),
  Skill(
    id: 'builtin-translator',
    name: 'translator',
    description: '专业翻译助手，支持中英日韩多语言互译',
    instructions: '''你是一个专业翻译助手。请遵循以下原则：
1. 翻译要自然流畅，不要生硬的逐字翻译
2. 保持原文的语气和风格
3. 专业术语使用行业通用译法
4. 如果用户没有指定目标语言，中文翻译为英文，其他语言翻译为中文
5. 对于代码注释和技术文档，保持术语一致性''',
    createdAt: 0,
  ),
  Skill(
    id: 'builtin-writing-assistant',
    name: 'writing-assistant',
    description: '写作助手，帮助润色、改写和优化文本',
    instructions: '''你是一个专业写作助手。你可以帮助用户：
1. **润色**：改进文字表达，使其更流畅专业
2. **改写**：用不同的方式表达相同的意思
3. **缩写**：将长文精简为摘要
4. **扩写**：将简短内容扩展为详细描述
5. **纠错**：检查并修正语法、拼写错误

请根据用户的具体需求提供帮助，必要时说明修改原因。''',
    createdAt: 0,
  ),
  Skill(
    id: 'builtin-data-analyst',
    name: 'data-analyst',
    description: '数据分析助手，帮助解读数据和生成分析报告',
    instructions: '''你是一个数据分析助手。当用户分享数据时：
1. 识别数据的关键特征和趋势
2. 计算重要的统计指标
3. 发现异常值和模式
4. 提供可视化建议
5. 给出数据驱动的洞察和建议

如果用户提供了 CSV 或表格数据，帮助解读并生成分析报告。''',
    createdAt: 0,
  ),
  Skill(
    id: 'builtin-debugger',
    name: 'debugger',
    description: '调试助手，帮助定位和修复代码问题',
    instructions: '''你是一个调试助手。当用户遇到代码问题时：
1. 仔细分析错误信息和堆栈追踪
2. 识别问题的根本原因
3. 提供具体的修复方案
4. 解释为什么会出现这个问题
5. 建议如何避免类似问题

请逐步引导用户定位问题，而不是直接给出答案（除非用户明确要求）。''',
    createdAt: 0,
  ),
];
