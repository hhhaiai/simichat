import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/crypto/key_encryptor.dart';
import '../../core/ai/model_fetcher.dart';
import '../../core/ai/model_tester.dart';
import '../../core/ai/protocol_icons.dart';
import '../../core/database/app_database.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/channel_provider.dart';
import '../../shared/providers/mcp_provider.dart';
import '../../shared/providers/prompt_provider.dart';
import '../../shared/providers/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 模型渠道
          _buildSectionHeader(context, '模型渠道'),
          _buildChannelsSection(context, ref),

          const Divider(),

          // 外观
          _buildSectionHeader(context, '外观'),
          _buildThemeModeTile(context, ref),

          const Divider(),

          // 上下文
          _buildSectionHeader(context, '上下文'),
          _buildCompressThresholdTile(context, ref),

          const Divider(),

          // 提示词库
          _buildSectionHeader(context, '提示词库'),
          _buildPromptsSection(context, ref),

          const Divider(),

          // MCP 服务器
          _buildSectionHeader(context, 'MCP 服务器'),
          _buildMcpSection(context, ref),

          const Divider(),

          // 关于
          _buildSectionHeader(context, '关于'),
          const ListTile(
            title: Text('版本'),
            subtitle: Text('1.0.0'),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeModeTile(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    String subtitle;
    switch (themeMode) {
      case ThemeMode.light:
        subtitle = '浅色模式';
        break;
      case ThemeMode.dark:
        subtitle = '深色模式';
        break;
      default:
        subtitle = '跟随系统';
    }

    return ListTile(
      title: const Text('主题模式'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemeModeDialog(context, ref, themeMode),
    );
  }

  void _showThemeModeDialog(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择主题模式'),
        children: [
          _buildThemeOption(ctx, ref, '跟随系统', ThemeMode.system, current),
          _buildThemeOption(ctx, ref, '浅色模式', ThemeMode.light, current),
          _buildThemeOption(ctx, ref, '深色模式', ThemeMode.dark, current),
        ],
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    WidgetRef ref,
    String label,
    ThemeMode mode,
    ThemeMode current,
  ) {
    return ListTile(
      title: Text(label),
      trailing: mode == current
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () {
        ref.read(themeModeProvider.notifier).setThemeMode(mode);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildCompressThresholdTile(BuildContext context, WidgetRef ref) {
    final threshold = ref.watch(compressThresholdProvider);

    return ListTile(
      title: const Text('压缩阈值'),
      subtitle: Text('当前: $threshold tokens · 超过此值自动压缩历史'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThresholdDialog(context, ref, threshold),
    );
  }

  void _showThresholdDialog(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) {
    double value = current.toDouble();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('压缩阈值'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.toInt()} tokens',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '未压缩消息的 token 数超过此值时，自动调用 AI 生成摘要压缩历史上下文。',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Slider(
                value: value,
                min: 500,
                max: 10000,
                divisions: 19,
                label: '${value.toInt()} tokens',
                onChanged: (v) => setDialogState(() => value = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('500', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  Text('10000', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                ref.read(compressThresholdProvider.notifier).setThreshold(value.toInt());
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildChannelsSection(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(channelsProvider);

    return channelsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListTile(title: Text('加载失败: $e')),
      data: (channels) {
        return Column(
          children: [
            for (final channel in channels)
              _buildChannelTile(context, ref, channel),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('添加渠道'),
              onTap: () => _showChannelEditDialog(context, ref),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChannelTile(BuildContext context, WidgetRef ref, ModelChannel channel) {
    return ExpansionTile(
      leading: Icon(getProtocolIcon(channel.protocol)),
      title: Text(channel.name),
      subtitle: Text(
        '${channel.protocol} · ${channel.baseUrl}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => _showChannelEditDialog(context, ref, channel: channel),
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
            onPressed: () => _deleteChannel(context, ref, channel),
          ),
        ],
      ),
      children: [
        // 模型列表
        FutureBuilder<List<ChannelModel>>(
          future: ref.read(channelDaoProvider).getModelsByChannel(channel.id),
          builder: (_, snapshot) {
            if (!snapshot.hasData) return const SizedBox();
            final models = snapshot.data!;
            return Column(
              children: [
                for (final m in models)
                  ListTile(
                    title: Text(m.modelName, style: const TextStyle(fontSize: 13)),
                    dense: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.play_arrow, size: 18, color: Colors.green),
                          tooltip: '测试连接',
                          onPressed: () => _testModel(context, ref, channel, m),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.red),
                          onPressed: () async {
                            await ref.read(channelDaoProvider).deleteModel(m.id);
                            refreshModels(ref);
                          },
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add, size: 18),
                  title: const Text('手动添加模型', style: TextStyle(fontSize: 13)),
                  dense: true,
                  onTap: () => _showAddModelDialog(context, ref, channel.id),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_download, size: 18),
                  title: const Text('自动获取模型', style: TextStyle(fontSize: 13)),
                  dense: true,
                  onTap: () => _fetchAndAddModels(context, ref, channel),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showChannelEditDialog(
    BuildContext context,
    WidgetRef ref, {
    ModelChannel? channel,
  }) {
    final nameCtrl = TextEditingController(text: channel?.name ?? '');
    final urlCtrl = TextEditingController(text: channel?.baseUrl ?? '');
    final keyCtrl = TextEditingController();
    String protocol = channel?.protocol ?? 'openai_chat';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(channel == null ? '添加渠道' : '编辑渠道'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '渠道名称', hintText: '如 OpenAI'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://api.openai.com'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(labelText: 'API Key'),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: protocol,
                  decoration: const InputDecoration(labelText: '协议类型'),
                  items: const [
                    DropdownMenuItem(value: 'openai_chat', child: Text('OpenAI Chat')),
                    DropdownMenuItem(value: 'openai_response', child: Text('OpenAI Response')),
                    DropdownMenuItem(value: 'claude', child: Text('Claude')),
                    DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                    DropdownMenuItem(value: 'ollama', child: Text('Ollama')),
                  ],
                  onChanged: (v) => setDialogState(() => protocol = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final channelDao = ref.read(channelDaoProvider);
                final encryptedKey = KeyEncryptor.encrypt(keyCtrl.text);
                final isNew = channel == null;
                final channelId = channel?.id ?? const Uuid().v4();

                if (isNew) {
                  await channelDao.createChannel(
                    id: channelId,
                    name: nameCtrl.text,
                    baseUrl: urlCtrl.text,
                    apiKeyEncrypted: encryptedKey,
                    protocol: protocol,
                  );
                } else {
                  await channelDao.updateChannel(
                    channel.id,
                    name: nameCtrl.text,
                    baseUrl: urlCtrl.text,
                    apiKeyEncrypted: keyCtrl.text.isNotEmpty ? encryptedKey : null,
                    protocol: protocol,
                  );
                }
                refreshModels(ref);
                if (ctx.mounted) Navigator.pop(ctx);

                // 新建渠道后自动获取模型列表
                if (isNew && context.mounted) {
                  await Future.delayed(const Duration(milliseconds: 400));
                  if (context.mounted) {
                    _fetchAndAddModels(
                      context,
                      ref,
                      ModelChannel(
                        id: channelId,
                        name: nameCtrl.text,
                        baseUrl: urlCtrl.text,
                        apiKeyEncrypted: encryptedKey,
                        protocol: protocol,
                        isEnabled: true,
                        isDefault: false,
                        createdAt: DateTime.now().millisecondsSinceEpoch,
                      ),
                    );
                  }
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddModelDialog(BuildContext context, WidgetRef ref, String channelId) {
    final modelCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加模型'),
        content: TextField(
          controller: modelCtrl,
          decoration: const InputDecoration(labelText: '模型名称', hintText: '如 gpt-4o'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (modelCtrl.text.isNotEmpty) {
                await ref.read(channelDaoProvider).addModel(
                  id: const Uuid().v4(),
                  channelId: channelId,
                  modelName: modelCtrl.text,
                );
                refreshModels(ref);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchAndAddModels(
    BuildContext context,
    WidgetRef ref,
    ModelChannel channel,
  ) async {
    // 显示加载指示器
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在获取模型列表...'),
          ],
        ),
      ),
    );

    try {
      final apiKey = KeyEncryptor.decrypt(channel.apiKeyEncrypted);
      final models = await ModelFetcher.fetchModels(
        protocol: channel.protocol,
        baseUrl: channel.baseUrl,
        apiKey: apiKey,
      );

      if (context.mounted) Navigator.pop(context); // 关闭加载对话框

      if (models.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('未获取到可用的对话模型（可能只有 embedding 模型）'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 获取已有的模型列表
      final existingModels = await ref.read(channelDaoProvider).getModelsByChannel(channel.id);
      final existingNames = existingModels.map((m) => m.modelName).toSet();

      // 过滤出新模型
      final newModels = models.where((m) => !existingNames.contains(m)).toList();

      if (newModels.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('所有 ${models.length} 个对话模型已存在，无需添加')),
          );
        }
        return;
      }

      // 显示模型选择对话框
      if (context.mounted) {
        _showFetchResultDialog(context, ref, channel.id, newModels);
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // 关闭加载对话框
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取失败: $e')),
        );
      }
    }
  }

  void _showFetchResultDialog(
    BuildContext context,
    WidgetRef ref,
    String channelId,
    List<String> models,
  ) {
    final selected = Set<String>.from(models);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('获取到 ${models.length} 个模型'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: models.length,
              itemBuilder: (_, index) {
                final model = models[index];
                return CheckboxListTile(
                  title: Text(model, style: const TextStyle(fontSize: 13)),
                  value: selected.contains(model),
                  dense: true,
                  onChanged: (checked) {
                    setDialogState(() {
                      if (checked == true) {
                        selected.add(model);
                      } else {
                        selected.remove(model);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final channelDao = ref.read(channelDaoProvider);
                for (final modelName in selected) {
                  await channelDao.addModel(
                    id: const Uuid().v4(),
                    channelId: channelId,
                    modelName: modelName,
                  );
                }
                refreshModels(ref);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已添加 ${selected.length} 个模型')),
                  );
                }
              },
              child: Text('添加选中的 ${selected.length} 个'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteChannel(BuildContext context, WidgetRef ref, ModelChannel channel) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除渠道'),
        content: Text('确定删除「${channel.name}」及其所有模型？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(channelDaoProvider).deleteChannel(channel.id);
              refreshModels(ref);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _testModel(
    BuildContext context,
    WidgetRef ref,
    ModelChannel channel,
    ChannelModel model,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('正在测试 ${model.modelName}...'),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final apiKey = KeyEncryptor.decrypt(channel.apiKeyEncrypted);
      final error = await ModelTester.testModel(
        protocol: channel.protocol,
        baseUrl: channel.baseUrl,
        apiKey: apiKey,
        model: model.modelName,
      );

      if (!context.mounted) return;
      scaffoldMessenger.hideCurrentSnackBar();

      if (error == null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('✅ ${model.modelName} 连接成功'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('❌ ${model.modelName} 连接失败: $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('❌ 测试异常: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // ====== 提示词库 ======

  Widget _buildPromptsSection(BuildContext context, WidgetRef ref) {
    final promptsAsync = ref.watch(promptNotifierProvider);

    return promptsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListTile(title: Text('加载失败: $e')),
      data: (prompts) {
        return Column(
          children: [
            for (final p in prompts)
              ListTile(
                leading: const Icon(Icons.text_snippet, size: 20),
                title: Text(p.name),
                subtitle: Text(
                  p.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () => _showPromptEditDialog(context, ref, prompt: p),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                      onPressed: () => _deletePrompt(context, ref, p),
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('添加提示词'),
              onTap: () => _showPromptEditDialog(context, ref),
            ),
          ],
        );
      },
    );
  }

  void _showPromptEditDialog(
    BuildContext context,
    WidgetRef ref, {
    Prompt? prompt,
  }) {
    final nameCtrl = TextEditingController(text: prompt?.name ?? '');
    final contentCtrl = TextEditingController(text: prompt?.content ?? '');
    final categoryCtrl = TextEditingController(text: prompt?.category ?? 'general');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(prompt == null ? '添加提示词' : '编辑提示词'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '名称', hintText: '如 翻译助手'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryCtrl,
                decoration: const InputDecoration(labelText: '分类', hintText: 'general'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(
                  labelText: '提示词内容',
                  hintText: '你是一个翻译助手...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 8,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || contentCtrl.text.isEmpty) return;
              final notifier = ref.read(promptNotifierProvider.notifier);
              if (prompt == null) {
                await notifier.addPrompt(
                  name: nameCtrl.text,
                  content: contentCtrl.text,
                  category: categoryCtrl.text,
                );
              } else {
                await notifier.updatePrompt(
                  id: prompt.id,
                  name: nameCtrl.text,
                  content: contentCtrl.text,
                  category: categoryCtrl.text,
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _deletePrompt(BuildContext context, WidgetRef ref, Prompt prompt) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除提示词'),
        content: Text('确定删除「${prompt.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(promptNotifierProvider.notifier).deletePrompt(prompt.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ====== MCP 服务器 ======

  Widget _buildMcpSection(BuildContext context, WidgetRef ref) {
    final mcpServers = ref.watch(mcpManagerProvider);
    final manager = ref.read(mcpManagerProvider.notifier);

    return Column(
      children: [
        for (final server in mcpServers)
          ListTile(
            leading: Icon(
              server.transport == 'stdio' ? Icons.terminal : Icons.cloud,
              size: 20,
            ),
            title: Text(server.name),
            subtitle: Text(
              server.transport == 'stdio'
                  ? '${server.command} ${(server.args ?? []).join(' ')}'
                  : server.url ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: server.isEnabled,
                  onChanged: (v) {
                    manager.updateServer(server.copyWith(isEnabled: v));
                    if (v) {
                      manager.connectServer(server);
                    } else {
                      manager.disconnectServer(server.id);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                  onPressed: () => manager.removeServer(server.id),
                ),
              ],
            ),
          ),
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: const Text('添加 MCP 服务器'),
          onTap: () => _showMcpServerDialog(context, ref),
        ),
      ],
    );
  }

  void _showMcpServerDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final commandCtrl = TextEditingController();
    final argsCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    String transport = 'stdio';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加 MCP 服务器'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '名称', hintText: '如 filesystem'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: transport,
                  decoration: const InputDecoration(labelText: '传输方式'),
                  items: const [
                    DropdownMenuItem(value: 'stdio', child: Text('Stdio（本地进程）')),
                    DropdownMenuItem(value: 'sse', child: Text('SSE（远程服务）')),
                  ],
                  onChanged: (v) => setDialogState(() => transport = v!),
                ),
                const SizedBox(height: 12),
                if (transport == 'stdio') ...[
                  TextField(
                    controller: commandCtrl,
                    decoration: const InputDecoration(
                      labelText: '命令',
                      hintText: 'npx -y @modelcontextprotocol/server-filesystem',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: argsCtrl,
                    decoration: const InputDecoration(
                      labelText: '参数（空格分隔）',
                      hintText: '/Users/user/Documents',
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SSE URL',
                      hintText: 'http://localhost:3001/sse',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty) return;
                final config = McpServerConfig(
                  id: const Uuid().v4(),
                  name: nameCtrl.text,
                  transport: transport,
                  command: transport == 'stdio' ? commandCtrl.text : null,
                  args: transport == 'stdio' && argsCtrl.text.isNotEmpty
                      ? argsCtrl.text.split(' ')
                      : null,
                  url: transport == 'sse' ? urlCtrl.text : null,
                );
                final manager = ref.read(mcpManagerProvider.notifier);
                manager.addServer(config);
                try {
                  await manager.connectServer(config);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('连接失败: $e')),
                    );
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

}
