import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/archive/data_import_service.dart';
import '../../core/archive/data_export_service.dart';
import '../../core/archive/data_export_share_service.dart';
import '../../core/archive/local_database_snapshot.dart';
import '../../core/archive/local_transfer_server.dart';
import '../../core/archive/obsidian_vault_export_service.dart';
import '../../core/crypto/key_encryptor.dart';
import '../../core/ai/model_capability.dart';
import '../../core/ai/model_channel_importer.dart';
import '../../core/ai/model_fetcher.dart';
import '../../core/ai/model_provider_preset.dart';
import '../../core/ai/model_tester.dart';
import '../../core/ai/protocol_icons.dart';
import '../../core/ai/sse_helper.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/message_dao.dart';
import '../../core/memory/dreaming_schedule.dart';
import '../../core/memory/user_profile.dart';
import '../../core/media/speech_provider_preset.dart';
import '../../core/relay/openai_compatible_relay_server.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/audio_transcription_provider.dart';
import '../../shared/providers/channel_provider.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/providers/conversation_archive_provider.dart';
import '../../shared/providers/dreaming_provider.dart';
import '../../shared/providers/mcp_provider.dart';
import '../../shared/providers/model_test_history_provider.dart';
import '../../shared/providers/openai_relay_provider.dart';
import '../../shared/providers/prompt_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/skill_provider.dart';
import '../../shared/providers/session_provider.dart';
import '../../shared/providers/text_to_speech_provider.dart';
import '../../shared/providers/user_profile_provider.dart';
import '../skills/skills_hub_page.dart';

typedef SettingsModelTestRunner =
    Future<ModelTestResult> Function({
      required String protocol,
      required String baseUrl,
      required String apiKey,
      required String model,
      required String capability,
    });

class ObsidianSyncConflictDetails extends StatelessWidget {
  const ObsidianSyncConflictDetails({
    super.key,
    required this.conflicts,
    this.maxVisibleConflicts = 20,
  });

  final List<ObsidianVaultSyncConflict> conflicts;
  final int maxVisibleConflicts;

  @override
  Widget build(BuildContext context) {
    final visibleConflicts = conflicts
        .take(maxVisibleConflicts)
        .toList(growable: false);
    final mutedStyle = Theme.of(context).textTheme.bodySmall;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('本次同步发现 ${conflicts.length} 个冲突，已全部跳过，没有覆盖或删除 Obsidian 中的文件。'),
        const SizedBox(height: 8),
        const Text('你可以在 Obsidian 中处理这些文件，或等待后续可选覆盖 / 双向同步策略。'),
        const SizedBox(height: 12),
        for (final conflict in visibleConflicts) ...[
          _ObsidianSyncConflictTile(conflict: conflict),
          const SizedBox(height: 8),
        ],
        if (conflicts.length > visibleConflicts.length)
          Text(
            '仅显示前 ${visibleConflicts.length} 个冲突，其余冲突已写入 SimiChat-Sync-State.json。',
            style: mutedStyle,
          ),
      ],
    );
  }
}

class _ObsidianSyncConflictTile extends StatelessWidget {
  const _ObsidianSyncConflictTile({required this.conflict});

  final ObsidianVaultSyncConflict conflict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.bodySmall;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            conflict.path,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(describeObsidianSyncConflictReason(conflict.reason)),
          const SizedBox(height: 6),
          Text('原因代码：${conflict.reason}', style: mutedStyle),
          Text(
            '新版本 SHA-256：${shortObsidianSyncHash(conflict.incomingSha256Hex)}',
            style: mutedStyle,
          ),
          if (conflict.existingSha256Hex != null)
            Text(
              '现有版本 SHA-256：${shortObsidianSyncHash(conflict.existingSha256Hex)}',
              style: mutedStyle,
            ),
        ],
      ),
    );
  }
}

@visibleForTesting
String describeObsidianSyncConflictReason(String reason) {
  switch (reason) {
    case 'target_modified':
      return '目标文件已在 Obsidian 中被手动修改，SimiChat 默认不覆盖用户改动。';
    case 'unsafe_existing_entity':
      return '目标路径不是普通文件，可能是目录或符号链接，已跳过以避免写穿或覆盖非预期文件。';
    case 'source_removed_target_modified':
      return '源文件已从 SimiChat 删除，但 Obsidian 中的目标文件被手动修改过，已保留以避免误删用户内容。';
    case 'stale_unsafe_existing_entity':
      return '源文件已从 SimiChat 删除，但目标路径不是普通文件，已跳过清理以避免写穿或删除非预期内容。';
    default:
      return '检测到同步冲突，SimiChat 已跳过该文件。';
  }
}

@visibleForTesting
String shortObsidianSyncHash(String? value) {
  if (value == null || value.isEmpty) return '无';
  return value.length <= 12 ? value : value.substring(0, 12);
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, this.modelTestRunner});

  final SettingsModelTestRunner? modelTestRunner;

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
          _buildFontScaleTile(context, ref),

          const Divider(),

          // 上下文
          _buildSectionHeader(context, '上下文'),
          _buildCompressThresholdTile(context, ref),

          const Divider(),

          // 数据与档案
          _buildSectionHeader(context, '数据与档案'),
          _buildArchiveMaintenanceTile(context, ref),
          _buildSearchIndexTile(context, ref),
          _buildDreamingTile(context, ref),
          _buildOpenAiRelayTile(context, ref),

          const Divider(),

          // 记忆与画像
          _buildSectionHeader(context, '记忆与画像'),
          _buildUserProfileTile(context, ref),

          const Divider(),

          // 语音与多模态
          _buildSectionHeader(context, '语音与多模态'),
          _buildVoiceInputTile(context, ref),
          _buildTextToSpeechTile(context, ref),

          const Divider(),

          // 提示词库
          _buildSectionHeader(context, '提示词库'),
          _buildPromptsSection(context, ref),

          const Divider(),

          // MCP 服务器
          _buildSectionHeader(context, 'MCP 服务器'),
          _buildMcpSection(context, ref),

          const Divider(),

          // Skills
          _buildSectionHeader(context, 'Skills 技能'),
          _buildSkillsSection(context, ref),

          const Divider(),

          // 关于
          _buildSectionHeader(context, '关于'),
          const ListTile(title: Text('版本'), subtitle: Text('1.0.0')),
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

  Widget _buildFontScaleTile(BuildContext context, WidgetRef ref) {
    final fontScale = ref.watch(fontScaleProvider);
    return ListTile(
      title: const Text('字体大小'),
      subtitle: Text('当前: ${formatFontScale(fontScale)} · 全局生效，布局自适应'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showFontScaleDialog(context, ref, fontScale),
    );
  }

  void _showFontScaleDialog(
    BuildContext context,
    WidgetRef ref,
    double current,
  ) {
    double value = normalizeFontScale(current);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('字体大小'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  formatFontScale(value),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '调整后会影响全局文字大小。移动端布局会随字体自适应，避免大字体下内容不可读。',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Slider(
                value: value,
                min: kMinFontScale,
                max: kMaxFontScale,
                divisions: 6,
                label: formatFontScale(value),
                onChanged: (v) => setDialogState(() => value = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatFontScale(kMinFontScale),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  TextButton(
                    onPressed: () =>
                        setDialogState(() => value = kDefaultFontScale),
                    child: const Text('恢复默认'),
                  ),
                  Text(
                    formatFontScale(kMaxFontScale),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '预览：SimiChat 会记住你的阅读偏好。',
                style: Theme.of(ctx).textTheme.bodyLarge,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                ref.read(fontScaleProvider.notifier).setFontScale(value);
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
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

  void _showThresholdDialog(BuildContext context, WidgetRef ref, int current) {
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
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
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
                  Text(
                    '500',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  Text(
                    '10000',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                ref
                    .read(compressThresholdProvider.notifier)
                    .setThreshold(value.toInt());
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('添加渠道'),
                    onPressed: () => _showChannelEditDialog(context, ref),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.playlist_add_check_circle_outlined),
                    label: const Text('批量导入渠道'),
                    onPressed: () =>
                        _showBatchChannelImportDialog(context, ref),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOpenAiRelayTile(BuildContext context, WidgetRef ref) {
    final relay = ref.watch(openAiRelayControllerProvider);
    final status = relay.isRunning
        ? '已运行 · ${relay.openAiBaseUrl}'
        : relay.status == OpenAiRelayStatus.error
        ? '启动失败 · ${relay.errorMessage ?? '请检查配置'}'
        : '未启动 · ${relay.bindMode.label}';
    return ListTile(
      leading: Icon(
        relay.isRunning ? Icons.hub : Icons.hub_outlined,
        color: relay.isRunning ? Colors.green[700] : null,
      ),
      title: const Text('个人接口中转 / 本地 OpenAI Relay'),
      subtitle: Text(
        '$status\nOpenAI 兼容 /health、/v1/models、/v1/chat/completions 与 /v1/responses，绑定：${relay.bindAddressLabel}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showOpenAiRelayDialog(context, ref),
    );
  }

  void _showOpenAiRelayDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(openAiRelayControllerProvider);
    final tokenCtrl = TextEditingController(text: current.token ?? '');
    final portCtrl = TextEditingController(
      text: current.requestedPort.toString(),
    );

    final dialog = showDialog<void>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, dialogRef, _) {
          final relay = dialogRef.watch(openAiRelayControllerProvider);
          final baseUrl = relay.openAiBaseUrl;
          final lanBaseUrls = relay.localNetworkBaseUrls;
          final concurrencyOptions = <int>{
            1,
            2,
            4,
            8,
            16,
            32,
            relay.maxConcurrentRequests,
          }.toList()..sort();
          final curlExample = _buildOpenAiRelayCurlExample(
            baseUrl ?? 'http://127.0.0.1:<port>/v1',
          );
          return AlertDialog(
            title: const Text('本地 OpenAI Relay'),
            content: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      relay.isRunning ? '状态：已运行' : '状态：未运行',
                      style: TextStyle(
                        color: relay.isRunning ? Colors.green[700] : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      relay.bindMode == OpenAiRelayBindMode.localNetwork
                          ? '当前已允许局域网访问：服务监听 0.0.0.0，同一网络设备持有 Bearer 令牌即可调用。不要在公共 Wi-Fi 或不可信网络开启。'
                          : '默认仅绑定 127.0.0.1，供本机或模拟器工具通过 OpenAI 兼容接口调用已启用的聊天模型。局域网开放必须手动确认风险。',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('允许局域网设备访问'),
                      subtitle: Text(
                        relay.bindMode == OpenAiRelayBindMode.localNetwork
                            ? '已开放到局域网；关闭后会恢复仅本机访问'
                            : '关闭时只监听 127.0.0.1；开启需要二次确认',
                      ),
                      value: relay.bindMode == OpenAiRelayBindMode.localNetwork,
                      onChanged: relay.isBusy
                          ? null
                          : (enabled) async {
                              await _handleOpenAiRelayBindModeChange(
                                context,
                                ctx,
                                dialogRef,
                                enableLocalNetwork: enabled,
                              );
                            },
                    ),
                    if (relay.bindMode == OpenAiRelayBindMode.localNetwork) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '局域网候选地址',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: relay.isBusy
                                ? null
                                : () async {
                                    await dialogRef
                                        .read(
                                          openAiRelayControllerProvider
                                              .notifier,
                                        )
                                        .refreshLanAddresses();
                                    if (context.mounted) {
                                      _showArchiveSnack(context, '局域网地址已刷新');
                                    }
                                  },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('刷新'),
                          ),
                        ],
                      ),
                      if (relay.lanAddresses.isEmpty)
                        const Text(
                          '未发现可展示的局域网 IPv4 地址；请确认设备已连接 Wi-Fi 或局域网。',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        )
                      else if (relay.isRunning && lanBaseUrls.isNotEmpty)
                        ...lanBaseUrls.map(
                          (url) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: SelectableText(
                              url,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                      else
                        Text(
                          '候选 IPv4：${relay.lanAddresses.join('、')}；启动后会显示完整 Base URL。',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: tokenCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Bearer 令牌（至少 16 位）',
                        helperText: '只保存在本机；复制示例时不会带出真实令牌',
                        suffixIcon: IconButton(
                          tooltip: '生成新令牌',
                          icon: const Icon(Icons.refresh),
                          onPressed: relay.isBusy
                              ? null
                              : () async {
                                  final token = await dialogRef
                                      .read(
                                        openAiRelayControllerProvider.notifier,
                                      )
                                      .generateAndSaveToken();
                                  tokenCtrl.text = token;
                                  if (context.mounted) {
                                    _showArchiveSnack(context, '已生成新的本地中转令牌');
                                  }
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '端口',
                        helperText: '0 表示系统自动分配可用端口',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: relay.maxConcurrentRequests,
                      decoration: const InputDecoration(
                        labelText: '并发上限',
                        helperText: '限制同时转发的聊天补全请求，降低本机和上游模型被打爆的风险',
                      ),
                      items: [
                        for (final value in concurrencyOptions)
                          DropdownMenuItem(
                            value: value,
                            child: Text('$value 个聊天请求'),
                          ),
                      ],
                      onChanged: relay.isBusy
                          ? null
                          : (value) async {
                              if (value == null) return;
                              await dialogRef
                                  .read(openAiRelayControllerProvider.notifier)
                                  .setMaxConcurrentRequests(value);
                              if (context.mounted) {
                                _showArchiveSnack(
                                  context,
                                  '本地中转并发上限已切换为：$value',
                                );
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<OpenAiRelayRouteStrategy>(
                      initialValue: relay.routeStrategy,
                      decoration: const InputDecoration(
                        labelText: '路由策略',
                        helperText:
                            '缺省 model 或 simichat:* 路由别名会按此策略选择模型；指定真实模型 id 时仍直连该模型',
                      ),
                      items: [
                        for (final strategy in OpenAiRelayRouteStrategy.values)
                          DropdownMenuItem(
                            value: strategy,
                            child: Text(strategy.label),
                          ),
                      ],
                      onChanged: relay.isBusy
                          ? null
                          : (strategy) async {
                              if (strategy == null) return;
                              await dialogRef
                                  .read(openAiRelayControllerProvider.notifier)
                                  .setRouteStrategy(strategy);
                              if (context.mounted) {
                                _showArchiveSnack(
                                  context,
                                  '本地中转路由策略已切换为：${strategy.label}',
                                );
                              }
                            },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '路由别名：simichat:default / simichat:free / simichat:fast / simichat:auto。非流式请求会在路由候选失败时尝试后续候选；流式请求不做中途回退。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('允许下载远端图片 URL'),
                      subtitle: const Text(
                        '默认关闭。开启后仅尝试公网 HTTP(S) 图片，限制 MIME、大小、超时并禁止内网 / 本机地址。',
                      ),
                      value: relay.allowRemoteImageDownload,
                      onChanged: relay.isBusy
                          ? null
                          : (value) async {
                              if (value) {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (confirmCtx) => AlertDialog(
                                    title: const Text('确认允许下载远端图片？'),
                                    content: const Text(
                                      '开启后，本地 Relay 会代表你访问外部 OpenAI 请求中的公网图片 URL。SimiChat 会阻止内网 / 本机地址、限制 1 MB、校验图片 MIME 并设置超时；仍建议只在可信客户端中使用。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(confirmCtx, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(confirmCtx, true),
                                        child: const Text('确认开启'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                              }
                              await dialogRef
                                  .read(openAiRelayControllerProvider.notifier)
                                  .setAllowRemoteImageDownload(value);
                              if (context.mounted) {
                                _showArchiveSnack(
                                  context,
                                  value ? '已开启远端图片 URL 安全下载' : '已关闭远端图片 URL 下载',
                                );
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    if (baseUrl != null) ...[
                      const Text('Base URL'),
                      const SizedBox(height: 4),
                      SelectableText(baseUrl),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      '令牌：${relay.maskedToken} · 绑定：${relay.bindAddressLabel} · 路由：${relay.routeStrategyLabel} · 请求体上限：1 MB',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '并发保护：最多 ${relay.maxConcurrentRequests} 个聊天请求 · ${relay.auditSummary.compactSummary}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '用量统计：${relay.usageStats.compactSummary}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: relay.usageStats.totalRequests == 0
                              ? null
                              : () async {
                                  await dialogRef
                                      .read(
                                        openAiRelayControllerProvider.notifier,
                                      )
                                      .clearUsageStats();
                                  if (context.mounted) {
                                    _showArchiveSnack(context, '本地中转用量统计已清空');
                                  }
                                },
                          child: const Text('清空统计'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            relay.auditLog.isEmpty
                                ? '最近审计：暂无持久化审计明细'
                                : '最近审计：已本地脱敏保存 ${relay.auditLog.length} 条，最多保留 $kOpenAiRelayMaxAuditLogEntries 条',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final report = dialogRef
                                .read(openAiRelayControllerProvider.notifier)
                                .exportAuditReportJson();
                            Clipboard.setData(ClipboardData(text: report));
                            _showArchiveSnack(context, 'Relay 脱敏审计 JSON 已复制');
                          },
                          child: const Text('复制审计 JSON'),
                        ),
                        TextButton(
                          onPressed: relay.auditLog.isEmpty
                              ? null
                              : () async {
                                  await dialogRef
                                      .read(
                                        openAiRelayControllerProvider.notifier,
                                      )
                                      .clearAuditLog();
                                  if (context.mounted) {
                                    _showArchiveSnack(context, 'Relay 审计明细已清空');
                                  }
                                },
                          child: const Text('清空审计'),
                        ),
                      ],
                    ),
                    if (relay.auditLog.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ...relay.auditLog
                          .take(3)
                          .map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${entry.completedAt.toLocal().toIso8601String()} · ${entry.compactSummary}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                    ],
                    if (relay.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        relay.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text('curl 示例（隐藏真实令牌）'),
                    const SizedBox(height: 4),
                    SelectableText(
                      curlExample,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: baseUrl == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: baseUrl));
                        _showArchiveSnack(context, 'Relay Base URL 已复制');
                      },
                child: const Text('复制 Base URL'),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: curlExample));
                  _showArchiveSnack(context, 'curl 示例已复制，令牌仍为占位符');
                },
                child: const Text('复制 curl 示例'),
              ),
              if (relay.isRunning)
                FilledButton.tonal(
                  onPressed: relay.isBusy
                      ? null
                      : () async {
                          await dialogRef
                              .read(openAiRelayControllerProvider.notifier)
                              .stop();
                          if (context.mounted) {
                            _showArchiveSnack(context, '本地 OpenAI Relay 已停止');
                          }
                        },
                  child: const Text('停止'),
                )
              else
                FilledButton(
                  onPressed: relay.isBusy
                      ? null
                      : () async {
                          await _startOpenAiRelayFromDialog(
                            context,
                            dialogRef,
                            tokenCtrl: tokenCtrl,
                            portCtrl: portCtrl,
                          );
                        },
                  child: const Text('启动'),
                ),
            ],
          );
        },
      ),
    );
    unawaited(
      dialog.whenComplete(() {
        tokenCtrl.dispose();
        portCtrl.dispose();
      }),
    );
  }

  Future<void> _handleOpenAiRelayBindModeChange(
    BuildContext scaffoldContext,
    BuildContext dialogContext,
    WidgetRef ref, {
    required bool enableLocalNetwork,
  }) async {
    final notifier = ref.read(openAiRelayControllerProvider.notifier);
    if (enableLocalNetwork) {
      final confirmed = await _confirmOpenAiRelayLanAccess(dialogContext);
      if (confirmed != true) {
        if (scaffoldContext.mounted) {
          _showArchiveSnack(scaffoldContext, '已取消局域网开放，仍保持仅本机访问');
        }
        return;
      }
      await notifier.setBindMode(OpenAiRelayBindMode.localNetwork);
      await notifier.refreshLanAddresses();
      if (scaffoldContext.mounted) {
        _showArchiveSnack(scaffoldContext, '已允许局域网访问，请只在可信网络中使用');
      }
      return;
    }

    await notifier.setBindMode(OpenAiRelayBindMode.loopback);
    if (scaffoldContext.mounted) {
      _showArchiveSnack(scaffoldContext, '已恢复仅本机访问');
    }
  }

  Future<bool?> _confirmOpenAiRelayLanAccess(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认开放局域网访问？'),
        content: const Text(
          '开启后，SimiChat 会监听 0.0.0.0，同一局域网内持有 Bearer 令牌的设备可以调用你的本地 OpenAI Relay。请只在可信网络中使用，不要把令牌发给他人。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认开放'),
          ),
        ],
      ),
    );
  }

  Future<void> _startOpenAiRelayFromDialog(
    BuildContext context,
    WidgetRef ref, {
    required TextEditingController tokenCtrl,
    required TextEditingController portCtrl,
  }) async {
    var token = tokenCtrl.text.trim();
    if (token.isEmpty) {
      token = generateOpenAiRelayToken();
      tokenCtrl.text = token;
    }
    final port =
        int.tryParse(
          portCtrl.text.trim().isEmpty ? '0' : portCtrl.text.trim(),
        ) ??
        0;
    try {
      await ref
          .read(openAiRelayControllerProvider.notifier)
          .start(token: token, requestedPort: port);
      if (!context.mounted) return;
      final relay = ref.read(openAiRelayControllerProvider);
      if (relay.status == OpenAiRelayStatus.error) {
        _showArchiveSnack(
          context,
          '启动失败：${relay.errorMessage ?? '请检查端口是否被占用'}',
        );
        return;
      }
      final url = relay.openAiBaseUrl;
      _showArchiveSnack(
        context,
        url == null ? '本地 OpenAI Relay 已启动' : '本地 OpenAI Relay 已启动：$url',
      );
    } on OpenAiCompatibleRelayException catch (error) {
      if (!context.mounted) return;
      _showArchiveSnack(context, '启动失败：${error.message}');
    }
  }

  String _buildOpenAiRelayCurlExample(String baseUrl) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return 'curl $normalized/models \\\n'
        '  -H "Authorization: Bearer <YOUR_RELAY_TOKEN>"';
  }

  Widget _buildChannelTile(
    BuildContext context,
    WidgetRef ref,
    ModelChannel channel,
  ) {
    final selectedModelId = ref.watch(selectedModelIdProvider);
    final modelTestHistory = ref.watch(modelTestHistoryProvider);
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
            onPressed: () =>
                _showChannelEditDialog(context, ref, channel: channel),
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
            onPressed: () => _deleteChannel(context, ref, channel),
          ),
        ],
      ),
      children: [
        // 模型列表
        ref
            .watch(modelsByChannelProvider(channel.id))
            .when(
              loading: () => const SizedBox(),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text('加载模型失败: $e', style: const TextStyle(fontSize: 12)),
              ),
              data: (models) {
                return Column(
                  children: [
                    for (final m in models)
                      ListTile(
                        selected: selectedModelId == m.id,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.08),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                m.modelName,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              ModelCapability.label(m.capability),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                        subtitle: _buildModelTestHistorySubtitle(
                          context,
                          modelTestHistory[m.id],
                        ),
                        dense: true,
                        onTap: () => _applyModelSelection(
                          context,
                          ref,
                          modelId: m.id,
                          modelLabel: '${channel.name} / ${m.modelName}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (selectedModelId == m.id)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.play_arrow,
                                size: 18,
                                color: Colors.green,
                              ),
                              tooltip: '测试连接',
                              onPressed: () =>
                                  _testModel(context, ref, channel, m),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                                color: Colors.red,
                              ),
                              onPressed: () async {
                                await ref
                                    .read(channelDaoProvider)
                                    .deleteModel(m.id);
                                await ref
                                    .read(modelTestHistoryProvider.notifier)
                                    .clearModel(m.id);
                                refreshChannelModels(ref, channel.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    ListTile(
                      leading: const Icon(Icons.add, size: 18),
                      title: const Text(
                        '手动添加模型',
                        style: TextStyle(fontSize: 13),
                      ),
                      dense: true,
                      onTap: () =>
                          _showAddModelDialog(context, ref, channel.id),
                    ),
                    ListTile(
                      leading: const Icon(Icons.cloud_download, size: 18),
                      title: const Text(
                        '自动获取模型',
                        style: TextStyle(fontSize: 13),
                      ),
                      dense: true,
                      onTap: () => _fetchAndAddModels(context, ref, channel),
                    ),
                    if (models.isNotEmpty)
                      ListTile(
                        leading: const Icon(
                          Icons.speed,
                          size: 18,
                          color: Colors.blue,
                        ),
                        title: const Text(
                          '一键测试并剔除不可用',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: const Text(
                          '失败模型会自动删除，成功模型保留',
                          style: TextStyle(fontSize: 11),
                        ),
                        dense: true,
                        onTap: () => _testAllModelsAndPrune(
                          context,
                          ref,
                          channel,
                          models,
                        ),
                      ),
                  ],
                );
              },
            ),
      ],
    );
  }

  Widget? _buildModelTestHistorySubtitle(
    BuildContext context,
    ModelTestHistoryItem? history,
  ) {
    if (history == null) return null;
    final color = history.success ? Colors.green[700] : Colors.red[700];
    return Text(
      '最近测试：${history.compactStatus} · ${_formatModelTestedAt(history.testedAt)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: color),
    );
  }

  String _formatModelTestedAt(DateTime testedAt) {
    if (testedAt.year <= 1) return '未知时间';
    final local = testedAt.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  Future<void> _applyModelSelection(
    BuildContext context,
    WidgetRef ref, {
    required String modelId,
    required String modelLabel,
  }) async {
    final previousModelId = ref.read(selectedModelIdProvider);
    try {
      final result = await switchConversationModel(
        ref: ref,
        modelId: modelId,
        modelLabel: modelLabel,
        previousModelId: previousModelId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                result.recorded ? '已切换模型，记录已写入当前对话' : result.message,
              ),
              duration: const Duration(seconds: 2),
            ),
          );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('模型切换失败，已回滚: $e')));
      }
    }
  }

  void _showBatchChannelImportDialog(BuildContext context, WidgetRef ref) {
    final importCtrl = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert({
        'channels': [
          {
            'name': '示例 OpenAI 兼容渠道',
            'baseUrl': 'https://api.example.com/v1',
            'protocol': 'openai_chat',
            'apiKey': '在这里粘贴自己的 Key',
            'models': [
              {'name': 'free-chat-model', 'capability': 'chat'},
              {'name': 'free-embedding-model', 'capability': 'embedding'},
            ],
          },
        ],
      }),
    );

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('批量导入渠道', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  '用于批量接入免费模型或自有 API 渠道。API Key 只会加密写入本地数据库，不会写入日志或文档。',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: TextField(
                    controller: importCtrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      labelText: '渠道 JSON',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      helperText:
                          '支持数组或 {"channels": [...]}；字段：name/baseUrl/protocol/apiKey/models',
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('导入'),
                      onPressed: () async {
                        try {
                          final summary = await _importModelChannels(
                            ref,
                            importCtrl.text,
                          );
                          refreshModels(ref);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(summary)));
                          }
                        } on ModelChannelImportParseException catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('导入失败：${e.message}')),
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('导入失败：请检查 JSON 格式和字段'),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String> _importModelChannels(WidgetRef ref, String rawJson) async {
    final imported = ModelChannelImportParser.parse(rawJson);
    final channelDao = ref.read(channelDaoProvider);
    var modelCount = 0;

    for (final channel in imported) {
      final channelId = const Uuid().v4();
      await channelDao.createChannel(
        id: channelId,
        name: channel.name,
        baseUrl: channel.baseUrl,
        apiKeyEncrypted: KeyEncryptor.encrypt(channel.apiKey),
        protocol: channel.protocol,
      );
      for (final model in channel.models) {
        await channelDao.addModel(
          id: const Uuid().v4(),
          channelId: channelId,
          modelName: model.name,
          capability: model.capability,
        );
        modelCount += 1;
      }
    }

    return '已导入 ${imported.length} 个渠道、$modelCount 个模型';
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
    String? selectedPresetId;
    bool obscureKey = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel == null ? '添加渠道' : '编辑渠道',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    if (channel == null) ...[
                      DropdownButtonFormField<String>(
                        initialValue: selectedPresetId,
                        decoration: const InputDecoration(
                          labelText: '厂商预设',
                          helperText: '选择后自动填充渠道名称、Base URL 与协议，可再手动调整',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('自定义渠道'),
                          ),
                          for (final preset in kModelProviderPresets)
                            DropdownMenuItem(
                              value: preset.id,
                              child: Text(preset.name),
                            ),
                        ],
                        onChanged: (value) {
                          final preset = value == null || value.isEmpty
                              ? null
                              : findModelProviderPreset(value);
                          setDialogState(() {
                            selectedPresetId = value?.isEmpty == true
                                ? null
                                : value;
                            if (preset != null) {
                              nameCtrl.text = preset.name;
                              urlCtrl.text = preset.baseUrl;
                              protocol = preset.protocol;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (selectedPresetId != null)
                        _ProviderPresetHint(
                          preset: findModelProviderPreset(selectedPresetId!)!,
                        ),
                      if (selectedPresetId != null) const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '渠道名称',
                        hintText: '如 OpenAI',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: 'https://api.openai.com',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyCtrl,
                      obscureText: obscureKey,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        hintText: channel != null ? '留空则不修改' : '请输入 API Key',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureKey
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () {
                            setDialogState(() => obscureKey = !obscureKey);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: protocol,
                      decoration: const InputDecoration(labelText: '协议类型'),
                      items: const [
                        DropdownMenuItem(
                          value: 'openai_chat',
                          child: Text('OpenAI Chat'),
                        ),
                        DropdownMenuItem(
                          value: 'openai_response',
                          child: Text('OpenAI Response'),
                        ),
                        DropdownMenuItem(
                          value: 'claude',
                          child: Text('Claude'),
                        ),
                        DropdownMenuItem(
                          value: 'gemini',
                          child: Text('Gemini'),
                        ),
                        DropdownMenuItem(
                          value: 'ollama',
                          child: Text('Ollama'),
                        ),
                      ],
                      onChanged: (v) => setDialogState(() => protocol = v!),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () async {
                            final channelDao = ref.read(channelDaoProvider);
                            final name = nameCtrl.text.trim();
                            final baseUrl = normalizeUrl(urlCtrl.text);
                            final apiKey = keyCtrl.text.trim();
                            final encryptedKey = KeyEncryptor.encrypt(apiKey);
                            final isNew = channel == null;
                            final channelId = channel?.id ?? const Uuid().v4();

                            if (name.isEmpty ||
                                baseUrl.isEmpty ||
                                (isNew && apiKey.isEmpty)) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '请完整填写渠道名称、Base URL 和 API Key',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }

                            if (isNew) {
                              await channelDao.createChannel(
                                id: channelId,
                                name: name,
                                baseUrl: baseUrl,
                                apiKeyEncrypted: encryptedKey,
                                protocol: protocol,
                              );
                            } else {
                              await channelDao.updateChannel(
                                channel.id,
                                name: name,
                                baseUrl: baseUrl,
                                apiKeyEncrypted: apiKey.isNotEmpty
                                    ? encryptedKey
                                    : null,
                                protocol: protocol,
                              );
                            }
                            refreshModels(ref);
                            if (ctx.mounted) Navigator.pop(ctx);

                            if (isNew && context.mounted) {
                              await Future.delayed(
                                const Duration(milliseconds: 400),
                              );
                              if (context.mounted) {
                                _fetchAndAddModels(
                                  context,
                                  ref,
                                  ModelChannel(
                                    id: channelId,
                                    name: name,
                                    baseUrl: baseUrl,
                                    apiKeyEncrypted: encryptedKey,
                                    protocol: protocol,
                                    isEnabled: true,
                                    isDefault: false,
                                    createdAt:
                                        DateTime.now().millisecondsSinceEpoch,
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddModelDialog(
    BuildContext context,
    WidgetRef ref,
    String channelId,
  ) {
    final modelCtrl = TextEditingController();
    var capability = ModelCapability.chat;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加模型'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(
                  labelText: '模型名称',
                  hintText: '如 gpt-4o / BAAI/bge-m3',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: capability,
                decoration: const InputDecoration(
                  labelText: '模型能力',
                  helperText: '图片 / 多模态模型请选择 Vision，Relay 会据此路由图片请求',
                ),
                items: const [
                  DropdownMenuItem(
                    value: ModelCapability.chat,
                    child: Text('Chat 对话'),
                  ),
                  DropdownMenuItem(
                    value: ModelCapability.vision,
                    child: Text('Vision 视觉'),
                  ),
                  DropdownMenuItem(
                    value: ModelCapability.embedding,
                    child: Text('Embedding 向量'),
                  ),
                ],
                onChanged: (v) => setDialogState(() => capability = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (modelCtrl.text.trim().isNotEmpty) {
                  await ref
                      .read(channelDaoProvider)
                      .addModel(
                        id: const Uuid().v4(),
                        channelId: channelId,
                        modelName: modelCtrl.text.trim(),
                        capability: capability,
                      );
                  refreshChannelModels(ref, channelId);
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
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

    var loadingDismissed = false;
    try {
      final apiKey = KeyEncryptor.decrypt(channel.apiKeyEncrypted);
      final models = await ModelFetcher.fetchModelInfos(
        protocol: channel.protocol,
        baseUrl: channel.baseUrl,
        apiKey: apiKey,
      );

      if (context.mounted) {
        Navigator.pop(context);
        loadingDismissed = true;
      }

      if (models.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('未获取到可用模型'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 获取已有的模型列表
      final existingModels = await ref
          .read(channelDaoProvider)
          .getModelsByChannel(channel.id);
      final existingKeys = existingModels
          .map((m) => '${m.capability}::${m.modelName}')
          .toSet();

      // 过滤出新模型
      final newModels = models
          .where((m) => !existingKeys.contains('${m.capability}::${m.id}'))
          .toList();

      if (newModels.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('所有 ${models.length} 个模型已存在，无需添加')),
          );
        }
        return;
      }

      // 显示模型选择对话框
      if (context.mounted) {
        _showFetchResultDialog(context, ref, channel.id, newModels);
      }
    } catch (e) {
      if (!loadingDismissed && context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('获取失败: $e')));
      }
    }
  }

  void _showFetchResultDialog(
    BuildContext context,
    WidgetRef ref,
    String channelId,
    List<FetchedModel> models,
  ) {
    final selected = models.map((m) => m.id).toSet();

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
                  title: Text(model.id, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    ModelCapability.label(model.capability),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  value: selected.contains(model.id),
                  dense: true,
                  onChanged: (checked) {
                    setDialogState(() {
                      if (checked == true) {
                        selected.add(model.id);
                      } else {
                        selected.remove(model.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final channelDao = ref.read(channelDaoProvider);
                final byId = {for (final model in models) model.id: model};
                for (final modelName in selected) {
                  final model = byId[modelName];
                  await channelDao.addModel(
                    id: const Uuid().v4(),
                    channelId: channelId,
                    modelName: modelName,
                    capability: model?.capability ?? ModelCapability.chat,
                  );
                }
                refreshChannelModels(ref, channelId);
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

  void _deleteChannel(
    BuildContext context,
    WidgetRef ref,
    ModelChannel channel,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除渠道'),
        content: Text('确定删除「${channel.name}」及其所有模型？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(channelDaoProvider).deleteChannel(channel.id);
              await ref
                  .read(modelTestHistoryProvider.notifier)
                  .clearChannel(channel.id);
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
      final result = await _runModelTest(
        protocol: channel.protocol,
        baseUrl: channel.baseUrl,
        apiKey: apiKey,
        model: model.modelName,
        capability: model.capability,
      );

      await ref
          .read(modelTestHistoryProvider.notifier)
          .recordResult(
            modelId: model.id,
            modelName: model.modelName,
            channelId: channel.id,
            channelName: channel.name,
            result: result,
          );

      if (!context.mounted) return;
      scaffoldMessenger.hideCurrentSnackBar();

      if (result.success) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('✅ ${model.modelName} ${result.summary}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('❌ ${model.modelName}：${result.compactMessage}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      final result = ModelTestResult.failure(e.toString());
      await ref
          .read(modelTestHistoryProvider.notifier)
          .recordResult(
            modelId: model.id,
            modelName: model.modelName,
            channelId: channel.id,
            channelName: channel.name,
            result: result,
          );
      if (context.mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('❌ 测试异常: ${result.compactMessage}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _testAllModelsAndPrune(
    BuildContext context,
    WidgetRef ref,
    ModelChannel channel,
    List<ChannelModel> models,
  ) async {
    // 显示进度对话框
    final results = <String, ModelTestResult>{}; // modelId → structured result
    final progressNotifier = ValueNotifier<int>(0);
    final globalErrorNotifier = ValueNotifier<String?>(null);
    var cancelled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: progressNotifier,
        builder: (context, progress, child) => ValueListenableBuilder<String?>(
          valueListenable: globalErrorNotifier,
          builder: (context, globalError, child) => AlertDialog(
            title: const Text('测试并剔除不可用模型'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '会逐个测试当前渠道模型；测试失败的模型会在完成后从本地列表删除，成功模型保留。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (globalError != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        globalError,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: models.length,
                      itemBuilder: (_, i) {
                        final m = models[i];
                        final done = i < progress;
                        final testing = i == progress && globalError == null;
                        final result = results[m.id];
                        final success = result?.success == true;
                        return ListTile(
                          dense: true,
                          leading: done
                              ? (success
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 20,
                                      )
                                    : const Icon(
                                        Icons.cancel,
                                        color: Colors.red,
                                        size: 20,
                                      ))
                              : testing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.radio_button_unchecked,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                          title: Text(
                            m.modelName,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: done && result != null && !result.success
                              ? Text(
                                  result.compactMessage,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.red,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  if (progress < models.length) {
                    cancelled = true;
                  }
                  Navigator.pop(ctx);
                },
                child: Text(progress >= models.length ? '完成' : '跳过'),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final apiKey = KeyEncryptor.decrypt(channel.apiKeyEncrypted);

      // 逐个测试（并行会太重）
      for (int i = 0; i < models.length; i++) {
        if (cancelled) break;
        final m = models[i];
        try {
          final result = await _runModelTest(
            protocol: channel.protocol,
            baseUrl: channel.baseUrl,
            apiKey: apiKey,
            model: m.modelName,
            capability: m.capability,
          );
          results[m.id] = result;
          await ref
              .read(modelTestHistoryProvider.notifier)
              .recordResult(
                modelId: m.id,
                modelName: m.modelName,
                channelId: channel.id,
                channelName: channel.name,
                result: result,
              );
        } catch (e) {
          final result = ModelTestResult.failure(e.toString());
          results[m.id] = result;
          await ref
              .read(modelTestHistoryProvider.notifier)
              .recordResult(
                modelId: m.id,
                modelName: m.modelName,
                channelId: channel.id,
                channelName: channel.name,
                result: result,
              );
        }
        progressNotifier.value = i + 1;
      }
      if (!cancelled) {
        final failedModels = models
            .where((model) => results[model.id]?.success == false)
            .toList(growable: false);
        for (final model in failedModels) {
          await ref.read(channelDaoProvider).deleteModel(model.id);
          await ref
              .read(modelTestHistoryProvider.notifier)
              .clearModel(model.id);
        }
        refreshChannelModels(ref, channel.id);
        refreshModels(ref);
        if (context.mounted) {
          final kept = models.length - failedModels.length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '测试完成：保留 $kept 个可用模型，已剔除 ${failedModels.length} 个不可用模型',
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      final result = ModelTestResult.failure(e.toString());
      if (context.mounted) {
        final message = '批量测试失败: ${result.compactMessage}';
        globalErrorNotifier.value = message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<ModelTestResult> _runModelTest({
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String capability,
  }) {
    final runner = modelTestRunner;
    if (runner != null) {
      return runner(
        protocol: protocol,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        capability: capability,
      );
    }
    return ModelTester.testModelDetailed(
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      capability: capability,
    );
  }

  // ====== 语音输入 ======

  Widget _buildVoiceInputTile(BuildContext context, WidgetRef ref) {
    final sttConfig = ref.watch(speechToTextConfigProvider);
    final hasSttEngine = ref.watch(speechToTextEngineProvider) != null;
    final subtitle = hasSttEngine
        ? sttConfig.isConfigured
              ? '麦克风权限已声明 · ${sttConfig.statusLabel}'
              : '麦克风权限已声明 · STT 引擎已配置'
        : '麦克风权限已声明 · STT 引擎未配置 · 可先发送语音文件';

    return ListTile(
      leading: const Icon(Icons.mic_none_outlined),
      title: const Text('语音输入'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showVoiceInputStatusDialog(
        context,
        ref,
        hasSttEngine: hasSttEngine,
        config: sttConfig,
      ),
    );
  }

  void _showVoiceInputStatusDialog(
    BuildContext context,
    WidgetRef ref, {
    required bool hasSttEngine,
    required SpeechToTextConfig config,
  }) {
    final baseUrlController = TextEditingController(text: config.baseUrl);
    final modelController = TextEditingController(text: config.model);
    final apiKeyController = TextEditingController();
    var enabled = config.enabled || hasSttEngine;
    var isSaving = false;
    String? errorText;
    var selectedPresetId =
        inferSpeechToTextPreset(
          baseUrl: config.baseUrl,
          model: config.model,
        )?.id ??
        'custom_openai_compatible';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('语音输入与 STT 配置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('已完成：'),
                const SizedBox(height: 6),
                const Text('• iOS / Android 麦克风权限声明'),
                const Text('• 移动端录音按钮与本地 audio 附件'),
                const Text('• 转写稿件 Markdown sidecar'),
                const Text('• OpenAI 兼容 STT 引擎配置入口'),
                const SizedBox(height: 12),
                Text(hasSttEngine ? '当前：STT 引擎已配置。' : '当前：STT 引擎未配置。'),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用 STT 自动转写'),
                  subtitle: const Text('发送或录制语音后自动调用配置的 STT 服务。'),
                  value: enabled,
                  onChanged: isSaving
                      ? null
                      : (value) => setState(() => enabled = value),
                ),
                const SizedBox(height: 8),
                const Text('厂商：OpenAI 兼容 STT'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedPresetId,
                  decoration: const InputDecoration(labelText: '厂商预设'),
                  items: speechToTextPresets()
                      .map(
                        (preset) => DropdownMenuItem(
                          value: preset.id,
                          child: Text(preset.name),
                        ),
                      )
                      .toList(),
                  onChanged: isSaving
                      ? null
                      : (value) {
                          final preset = value == null
                              ? null
                              : findSpeechProviderPreset(value);
                          if (preset == null || !preset.supportsStt) return;
                          setState(() {
                            selectedPresetId = preset.id;
                            baseUrlController.text = preset.baseUrl;
                            modelController.text = preset.sttModel!;
                          });
                        },
                ),
                const SizedBox(height: 6),
                Text(
                  findSpeechProviderPreset(selectedPresetId)?.description ??
                      '选择预设后会自动填充 Base URL 与模型，API Key 仍只保存在本机。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: baseUrlController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.openai.com',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: modelController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    hintText: 'whisper-1',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: apiKeyController,
                  enabled: !isSaving,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: config.hasApiKey
                        ? 'API Key（留空保留已有密钥）'
                        : 'API Key',
                    hintText: '只保存在本机加密配置中',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '安全：API Key 加密保存在本机 SharedPreferences，不进入结构化备份、导出包、日志或聊天 Markdown。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (config.hasApiKey || config.enabled)
              TextButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setState(() {
                          isSaving = true;
                          errorText = null;
                        });
                        await ref
                            .read(speechToTextConfigProvider.notifier)
                            .clearConfig();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已清除 STT 配置')),
                          );
                        }
                      },
                child: const Text('清除配置'),
              ),
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await ref
                            .read(speechToTextConfigProvider.notifier)
                            .saveOpenAiCompatible(
                              enabled: enabled,
                              baseUrl: baseUrlController.text,
                              model: modelController.text,
                              apiKey: apiKeyController.text,
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('STT 配置已保存')),
                          );
                        }
                      } catch (error) {
                        setState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: Text(isSaving ? '保存中…' : '保存配置'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      baseUrlController.dispose();
      modelController.dispose();
      apiKeyController.dispose();
    });
  }

  Widget _buildTextToSpeechTile(BuildContext context, WidgetRef ref) {
    final ttsConfig = ref.watch(textToSpeechConfigProvider);
    final hasTtsEngine = ref.watch(textToSpeechEngineProvider) != null;
    final subtitle = hasTtsEngine
        ? ttsConfig.isConfigured
              ? ttsConfig.statusLabel
              : 'TTS 引擎已配置'
        : 'TTS 引擎未配置 · 可为 AI 回复生成语音播报';

    return ListTile(
      leading: const Icon(Icons.volume_up_outlined),
      title: const Text('语音播报'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showTextToSpeechConfigDialog(
        context,
        ref,
        hasTtsEngine: hasTtsEngine,
        config: ttsConfig,
      ),
    );
  }

  void _showTextToSpeechConfigDialog(
    BuildContext context,
    WidgetRef ref, {
    required bool hasTtsEngine,
    required TextToSpeechConfig config,
  }) {
    final baseUrlController = TextEditingController(text: config.baseUrl);
    final modelController = TextEditingController(text: config.model);
    final voiceController = TextEditingController(text: config.voice);
    final apiKeyController = TextEditingController();
    var enabled = config.enabled || hasTtsEngine;
    var isSaving = false;
    String? errorText;
    var selectedPresetId =
        inferTextToSpeechPreset(
          baseUrl: config.baseUrl,
          model: config.model,
          voice: config.voice,
        )?.id ??
        'custom_openai_compatible';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('语音播报 TTS 配置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('已完成：'),
                const SizedBox(height: 6),
                const Text('• OpenAI 兼容 TTS 语音生成'),
                const Text('• AI 回复卡片一键语音播报'),
                const Text('• iOS / Android 原生本地音频播放通道'),
                const SizedBox(height: 12),
                Text(hasTtsEngine ? '当前：TTS 引擎已配置。' : '当前：TTS 引擎未配置。'),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用 TTS 语音播报'),
                  subtitle: const Text('点击 AI 回复下方播报按钮时生成临时 mp3 并调用系统播放。'),
                  value: enabled,
                  onChanged: isSaving
                      ? null
                      : (value) => setState(() => enabled = value),
                ),
                const SizedBox(height: 8),
                const Text('厂商：OpenAI 兼容 TTS'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedPresetId,
                  decoration: const InputDecoration(labelText: '厂商预设'),
                  items: textToSpeechPresets()
                      .map(
                        (preset) => DropdownMenuItem(
                          value: preset.id,
                          child: Text(preset.name),
                        ),
                      )
                      .toList(),
                  onChanged: isSaving
                      ? null
                      : (value) {
                          final preset = value == null
                              ? null
                              : findSpeechProviderPreset(value);
                          if (preset == null || !preset.supportsTts) return;
                          setState(() {
                            selectedPresetId = preset.id;
                            baseUrlController.text = preset.baseUrl;
                            modelController.text = preset.ttsModel!;
                            voiceController.text = preset.ttsVoice!;
                          });
                        },
                ),
                const SizedBox(height: 6),
                Text(
                  findSpeechProviderPreset(selectedPresetId)?.description ??
                      '选择预设后会自动填充 Base URL、模型与音色，API Key 仍只保存在本机。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: baseUrlController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.openai.com',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: modelController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    hintText: 'tts-1',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: voiceController,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: '音色',
                    hintText: 'alloy',
                    helperText: '仅允许字母、数字、点、下划线和短横线',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: apiKeyController,
                  enabled: !isSaving,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: config.hasApiKey
                        ? 'API Key（留空保留已有密钥）'
                        : 'API Key',
                    hintText: '只保存在本机加密配置中',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '安全：TTS API Key 加密保存在本机 SharedPreferences，不进入结构化备份、导出包、日志或聊天 Markdown；语音文件仅生成在应用临时目录并由原生通道限制播放范围。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (config.hasApiKey || config.enabled)
              TextButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setState(() {
                          isSaving = true;
                          errorText = null;
                        });
                        await ref
                            .read(textToSpeechConfigProvider.notifier)
                            .clearConfig();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已清除 TTS 配置')),
                          );
                        }
                      },
                child: const Text('清除配置'),
              ),
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await ref
                            .read(textToSpeechConfigProvider.notifier)
                            .saveOpenAiCompatible(
                              enabled: enabled,
                              baseUrl: baseUrlController.text,
                              model: modelController.text,
                              voice: voiceController.text,
                              apiKey: apiKeyController.text,
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('TTS 配置已保存')),
                          );
                        }
                      } catch (error) {
                        setState(() {
                          isSaving = false;
                          errorText = error.toString();
                        });
                      }
                    },
              child: Text(isSaving ? '保存中…' : '保存配置'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      baseUrlController.dispose();
      modelController.dispose();
      voiceController.dispose();
      apiKeyController.dispose();
    });
  }

  // ====== 对话 Markdown 档案 ======

  Widget _buildArchiveMaintenanceTile(BuildContext context, WidgetRef ref) {
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final queue = ref.watch(archiveRepairQueueProvider);
    final queueSummary = queue.isEmpty ? '无待修复项' : '${queue.length} 个待修复项';
    final sessionSummary = activeSessionId == null ? '当前无活跃会话' : '当前会话可检查 / 重建';

    return ListTile(
      title: const Text('对话 Markdown 档案'),
      subtitle: Text('$sessionSummary · $queueSummary'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showArchiveMaintenanceDialog(context, ref, activeSessionId),
    );
  }

  void _showArchiveMaintenanceDialog(
    BuildContext context,
    WidgetRef ref,
    String? activeSessionId,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final queue = ref.watch(archiveRepairQueueProvider);
          return AlertDialog(
            title: const Text('对话 Markdown 档案'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeSessionId == null
                      ? '当前无活跃会话。'
                      : '当前会话：$activeSessionId',
                ),
                const SizedBox(height: 8),
                Text('待修复队列：${queue.length} 项'),
                if (queue.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '最近失败：${queue.first.operation} · ${queue.first.sessionId}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  '检查会对比 SQLite 消息与 Markdown 中的 message id；重建会用 SQLite 重新生成当前会话 Markdown。',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: queue.isEmpty
                    ? null
                    : () {
                        ref
                            .read(archiveRepairQueueProvider.notifier)
                            .clearAll();
                        Navigator.pop(ctx);
                        _showArchiveSnack(context, '已清空待修复队列');
                      },
                child: const Text('清空队列'),
              ),
              TextButton(
                onPressed: queue.isEmpty
                    ? null
                    : () => _repairArchiveQueue(context, ref),
                child: const Text('修复队列'),
              ),
              TextButton(
                onPressed: activeSessionId == null
                    ? null
                    : () => _checkArchive(context, ref, activeSessionId),
                child: const Text('检查'),
              ),
              TextButton(
                onPressed: () => _showDataExportDialog(context, ref),
                child: const Text('导出'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _pickAndPreviewDataImport(context, ref);
                },
                child: const Text('导入'),
              ),
              FilledButton(
                onPressed: activeSessionId == null
                    ? null
                    : () => _rebuildArchive(context, ref, activeSessionId),
                child: const Text('重建'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _checkArchive(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
  ) async {
    final report = await checkConversationArchiveConsistency(ref, sessionId);
    if (!context.mounted) return;
    if (report == null) {
      _showArchiveSnack(context, '当前平台暂不支持档案检查');
      return;
    }
    if (report.isConsistent) {
      _showArchiveSnack(context, 'Markdown 档案一致');
      return;
    }
    final missing = report.missingMessageIds.length;
    final extra = report.extraMessageIds.length;
    _showArchiveSnack(context, '档案不一致：缺失 $missing 条，多余 $extra 条，可点击重建修复');
  }

  Future<void> _rebuildArchive(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
  ) async {
    final ok = await rebuildConversationArchive(ref, sessionId);
    if (!context.mounted) return;
    _showArchiveSnack(context, ok ? 'Markdown 档案已重建' : '重建失败，已加入待修复队列');
  }

  Future<void> _repairArchiveQueue(BuildContext context, WidgetRef ref) async {
    final result = await processConversationArchiveRepairQueue(ref);
    if (!context.mounted) return;
    _showArchiveSnack(context, result.summary);
  }

  void _showDataExportDialog(BuildContext context, WidgetRef ref) {
    var includeAudioFiles = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('导出本地数据'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '将生成本地 .tar.gz 压缩包，包含会话 Markdown、图片 / 文档等附件原文件、语音转写稿、'
                    '本地记忆 / Dreaming / 用户画像 / 设置快照和 manifest。',
                  ),
                  const SizedBox(height: 8),
                  const Text('导出包不包含模型 API Key 或渠道密钥，不会自动上传；分享前请确认目标应用可信。'),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('包含原始语音文件'),
                    subtitle: const Text(
                      '关闭后只导出语音转文字稿件，不导出 audio_files/，Obsidian 也不会复制原始音频；非语音附件仍会随包导出。',
                    ),
                    value: includeAudioFiles,
                    onChanged: (value) =>
                        setState(() => includeAudioFiles = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _exportLocalData(
                    context,
                    ref: ref,
                    includeAudioFiles: includeAudioFiles,
                    shareAfterExport: false,
                  );
                },
                child: const Text('仅生成压缩包'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _exportAndStartLocalTransfer(
                    context,
                    ref: ref,
                    includeAudioFiles: includeAudioFiles,
                  );
                },
                child: const Text('电脑端传输'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _exportObsidianVault(
                    context,
                    ref: ref,
                    includeAudioFiles: includeAudioFiles,
                  );
                },
                child: const Text('Obsidian Vault'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showObsidianSyncOptionsDialog(
                    context,
                    ref: ref,
                    includeAudioFiles: includeAudioFiles,
                  );
                },
                child: const Text('同步到 Obsidian'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _exportLocalData(
                    context,
                    ref: ref,
                    includeAudioFiles: includeAudioFiles,
                    shareAfterExport: true,
                  );
                },
                child: const Text('生成并系统分享'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportLocalData(
    BuildContext context, {
    required WidgetRef ref,
    required bool includeAudioFiles,
    required bool shareAfterExport,
  }) async {
    if (kIsWeb) {
      _showArchiveSnack(context, '当前平台暂不支持本地压缩包导出');
      return;
    }
    try {
      final root = await getApplicationDocumentsDirectory();
      final result = await DataExportService(
        rootDirectory: root,
        listAttachments: () async {
          final rows = await ref
              .read(attachmentDaoProvider)
              .getAllAttachments();
          return rows
              .map(
                (row) => ExportableAttachment(
                  id: row.id,
                  messageId: row.messageId,
                  fileType: row.fileType,
                  localPath: row.localPath,
                  fileName: row.fileName,
                  fileSize: row.fileSize,
                ),
              )
              .toList(growable: false);
        },
        exportLocalDatabase: ({required includeAudioFiles}) {
          return LocalDatabaseSnapshotService(
            database: ref.read(databaseProvider),
            rootDirectory: root,
          ).exportSnapshot(includeAudioFiles: includeAudioFiles);
        },
      ).exportLocalData(includeAudioFiles: includeAudioFiles);
      if (!context.mounted) return;
      final fileName = result.file.uri.pathSegments.last;
      if (shareAfterExport) {
        try {
          await const DataExportShareService().shareExportFile(result.file);
          if (!context.mounted) return;
          _showArchiveSnack(
            context,
            '已生成 ${result.manifest.fileCount} 个文件并打开系统分享：$fileName',
          );
          return;
        } on MissingPluginException {
          if (!context.mounted) return;
          _showArchiveSnack(context, '已生成 $fileName，但当前平台暂不支持系统分享');
          return;
        } on UnsupportedError {
          if (!context.mounted) return;
          _showArchiveSnack(context, '已生成 $fileName，但当前平台暂不支持系统分享');
          return;
        } on PlatformException {
          if (!context.mounted) return;
          _showArchiveSnack(context, '已生成 $fileName，但系统分享失败，请稍后重试');
          return;
        }
      }
      _showArchiveSnack(
        context,
        '已导出 ${result.manifest.fileCount} 个文件：$fileName（已保存到应用文档目录 exports/）',
      );
    } catch (_) {
      if (!context.mounted) return;
      _showArchiveSnack(context, '导出失败，请稍后重试');
    }
  }

  Future<void> _exportObsidianVault(
    BuildContext context, {
    required WidgetRef ref,
    required bool includeAudioFiles,
  }) async {
    if (kIsWeb) {
      _showArchiveSnack(context, '当前平台暂不支持 Obsidian Vault 导出');
      return;
    }
    try {
      final root = await getApplicationDocumentsDirectory();
      final result = await _createObsidianVaultExportService(
        root: root,
        ref: ref,
      ).exportVault(includeAudioAttachments: includeAudioFiles);
      if (!context.mounted) return;
      final directoryName = result.directory.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      _showArchiveSnack(
        context,
        '已生成 Obsidian Vault：$directoryName（会话 ${result.conversationCount} 个，转写 ${result.audioTranscriptCount} 个）',
      );
    } catch (_) {
      if (!context.mounted) return;
      _showArchiveSnack(context, 'Obsidian Vault 导出失败，请稍后重试');
    }
  }

  Future<void> _syncObsidianVault(
    BuildContext context, {
    required WidgetRef ref,
    bool overwriteConflicts = false,
    required bool includeAudioFiles,
  }) async {
    if (kIsWeb) {
      _showArchiveSnack(context, '当前平台暂不支持 Obsidian Vault 同步');
      return;
    }
    try {
      final vaultPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择 Obsidian Vault 文件夹',
      );
      if (vaultPath == null || vaultPath.trim().isEmpty) {
        if (!context.mounted) return;
        _showArchiveSnack(context, '已取消 Obsidian Vault 同步');
        return;
      }
      final root = await getApplicationDocumentsDirectory();
      final result =
          await _createObsidianVaultExportService(
            root: root,
            ref: ref,
          ).syncToExistingVault(
            targetVaultDirectory: Directory(vaultPath),
            overwriteConflicts: overwriteConflicts,
            includeAudioAttachments: includeAudioFiles,
          );
      if (!context.mounted) return;
      final conflictText = result.conflictCount == 0
          ? '无冲突'
          : '冲突 ${result.conflictCount} 个，已跳过';
      final strategyText = overwriteConflicts ? '覆盖冲突模式' : '安全同步模式';
      _showArchiveSnack(
        context,
        '已同步到 Obsidian：新增 ${result.createdCount}，更新 ${result.updatedCount}，未变 ${result.unchangedCount}，清理 ${result.deletedCount}，$conflictText（$strategyText）',
      );
      if (result.conflicts.isNotEmpty && context.mounted) {
        await _showObsidianSyncConflictDialog(
          context,
          conflicts: result.conflicts,
        );
      }
    } on MissingPluginException {
      if (!context.mounted) return;
      _showArchiveSnack(context, '当前平台暂不支持选择 Obsidian 文件夹');
    } on UnsupportedError {
      if (!context.mounted) return;
      _showArchiveSnack(context, '当前平台暂不支持选择 Obsidian 文件夹');
    } on PlatformException {
      if (!context.mounted) return;
      _showArchiveSnack(context, '选择 Obsidian 文件夹失败，请稍后重试');
    } on ArgumentError {
      if (!context.mounted) return;
      _showArchiveSnack(context, '请选择会话档案目录之外的 Obsidian Vault 文件夹');
    } catch (_) {
      if (!context.mounted) return;
      _showArchiveSnack(context, 'Obsidian Vault 同步失败，请稍后重试');
    }
  }

  Future<void> _showObsidianSyncOptionsDialog(
    BuildContext context, {
    required WidgetRef ref,
    required bool includeAudioFiles,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Obsidian 同步策略'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('默认使用安全同步：如果检测到你在 Obsidian 中改过同名文件，SimiChat 会跳过并展示冲突详情。'),
              SizedBox(height: 8),
              Text(
                '只有当你明确希望用 SimiChat 当前档案覆盖 Obsidian 中的冲突文件时，才选择覆盖冲突。目录、符号链接等非普通文件仍会被跳过。',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _syncObsidianVault(
                context,
                ref: ref,
                overwriteConflicts: false,
                includeAudioFiles: includeAudioFiles,
              );
            },
            child: const Text('安全同步'),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(ctx);
              _syncObsidianVault(
                context,
                ref: ref,
                overwriteConflicts: true,
                includeAudioFiles: includeAudioFiles,
              );
            },
            child: const Text('覆盖冲突'),
          ),
        ],
      ),
    );
  }

  Future<void> _showObsidianSyncConflictDialog(
    BuildContext context, {
    required List<ObsidianVaultSyncConflict> conflicts,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Obsidian 同步冲突详情'),
        content: SingleChildScrollView(
          child: ObsidianSyncConflictDetails(conflicts: conflicts),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  ObsidianVaultExportService _createObsidianVaultExportService({
    required Directory root,
    required WidgetRef ref,
  }) {
    return ObsidianVaultExportService(
      rootDirectory: root,
      listAttachments: () async {
        final rows = await ref.read(attachmentDaoProvider).getAllAttachments();
        return rows
            .map(
              (row) => ObsidianExportableAttachment(
                id: row.id,
                messageId: row.messageId,
                fileType: row.fileType,
                localPath: row.localPath,
                fileName: row.fileName,
                fileSize: row.fileSize,
              ),
            )
            .toList(growable: false);
      },
    );
  }

  Future<void> _exportAndStartLocalTransfer(
    BuildContext context, {
    required WidgetRef ref,
    required bool includeAudioFiles,
  }) async {
    if (kIsWeb) {
      _showArchiveSnack(context, '当前平台暂不支持本地传输');
      return;
    }
    try {
      final root = await getApplicationDocumentsDirectory();
      final result = await DataExportService(
        rootDirectory: root,
        listAttachments: () async {
          final rows = await ref
              .read(attachmentDaoProvider)
              .getAllAttachments();
          return rows
              .map(
                (row) => ExportableAttachment(
                  id: row.id,
                  messageId: row.messageId,
                  fileType: row.fileType,
                  localPath: row.localPath,
                  fileName: row.fileName,
                  fileSize: row.fileSize,
                ),
              )
              .toList(growable: false);
        },
        exportLocalDatabase: ({required includeAudioFiles}) {
          return LocalDatabaseSnapshotService(
            database: ref.read(databaseProvider),
            rootDirectory: root,
          ).exportSnapshot(includeAudioFiles: includeAudioFiles);
        },
      ).exportLocalData(includeAudioFiles: includeAudioFiles);
      final session = await const LocalDataTransferServer().startExportTransfer(
        exportFile: result.file,
      );
      final urls = await session.candidateDownloadUris();
      if (!context.mounted) {
        await session.close();
        return;
      }
      _showLocalTransferDialog(
        context,
        session: session,
        urls: urls,
        fileName: result.file.uri.pathSegments.last,
      );
    } on LocalDataTransferException catch (error) {
      if (!context.mounted) return;
      _showArchiveSnack(context, '本地传输启动失败：${error.message}');
    } catch (_) {
      if (!context.mounted) return;
      _showArchiveSnack(context, '本地传输启动失败，请稍后重试');
    }
  }

  void _showLocalTransferDialog(
    BuildContext context, {
    required LocalDataTransferSession session,
    required List<Uri> urls,
    required String fileName,
  }) {
    final primaryUrl = urls.first.toString();
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('电脑端本地传输'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('导出包：$fileName'),
              const SizedBox(height: 8),
              const Text('在同一局域网电脑浏览器打开以下地址下载。链接包含一次性令牌，下载成功或关闭弹窗后会停止传输。'),
              const SizedBox(height: 8),
              SelectableText(primaryUrl),
              if (urls.length > 1) ...[
                const SizedBox(height: 8),
                const Text('其他可尝试地址：'),
                for (final url in urls.skip(1).take(3))
                  SelectableText(url.toString()),
              ],
              const SizedBox(height: 8),
              Text('过期时间：${session.expiresAt.toLocal()}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: primaryUrl));
              _showArchiveSnack(context, '本地传输地址已复制');
            },
            child: const Text('复制地址'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭传输'),
          ),
        ],
      ),
    );
    unawaited(dialog.whenComplete(session.close));
  }

  Future<void> _pickAndPreviewDataImport(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (kIsWeb) {
      _showArchiveSnack(context, '当前平台暂不支持本地导入');
      return;
    }
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gz', 'tgz'],
        allowMultiple: false,
      );
      final path = picked?.files.single.path;
      if (path == null) return;
      final root = await getApplicationDocumentsDirectory();
      final service = DataImportService(
        rootDirectory: root,
        localDatabaseSnapshotService: LocalDatabaseSnapshotService(
          database: ref.read(databaseProvider),
          rootDirectory: root,
        ),
      );
      final file = File(path);
      final preview = await service.previewExport(file);
      if (!context.mounted) return;
      _showDataImportPreviewDialog(context, service, file, preview);
    } on DataImportException catch (error) {
      if (!context.mounted) return;
      _showArchiveSnack(context, '导入预览失败：${error.message}');
    } catch (_) {
      if (!context.mounted) return;
      _showArchiveSnack(context, '导入预览失败，请确认文件来自 SimiChat 导出包');
    }
  }

  void _showDataImportPreviewDialog(
    BuildContext context,
    DataImportService service,
    File file,
    DataImportPreview preview,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入数据预览'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('格式：${preview.exportFormat}'),
            if (preview.createdAt != null) Text('导出时间：${preview.createdAt}'),
            const SizedBox(height: 8),
            Text('可导入文件：${preview.importableFileCount} 个'),
            if (preview.hasStructuredData)
              Text(
                '结构化数据：${preview.structuredKeyCount} 项'
                '${preview.existingStructuredData ? '（本机已有，默认跳过冲突项）' : ''}',
              ),
            Text('已存在冲突：${preview.existingFileCount} 个'),
            Text('跳过不支持项：${preview.unsupportedEntryCount} 个'),
            if (preview.unsupportedStructuredKeyCount > 0)
              Text('跳过不支持结构化项：${preview.unsupportedStructuredKeyCount} 项'),
            Text('总大小：${_formatBytes(preview.totalBytes)}'),
            const SizedBox(height: 8),
            const Text('导入默认不会覆盖已有文件或已有结构化数据；冲突项会被跳过。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _importLocalData(context, service, file);
            },
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _importLocalData(
    BuildContext context,
    DataImportService service,
    File file,
  ) async {
    try {
      final result = await service.importExport(file);
      if (!context.mounted) return;
      _showArchiveSnack(context, result.summary);
    } on DataImportException catch (error) {
      if (!context.mounted) return;
      _showArchiveSnack(context, '导入失败：${error.message}');
    } catch (_) {
      if (!context.mounted) return;
      _showArchiveSnack(context, '导入失败，请稍后重试');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  void _showArchiveSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ====== 本地搜索索引 ======

  Widget _buildSearchIndexTile(BuildContext context, WidgetRef ref) {
    final semanticEnabled = ref.watch(semanticSearchEnabledProvider);
    return ListTile(
      leading: const Icon(Icons.manage_search_outlined),
      title: const Text('本地搜索索引'),
      subtitle: Text(
        'SQLite FTS + 本地语义索引 · 语义搜索${semanticEnabled ? '已开启' : '已关闭'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showSearchIndexDialog(context, ref),
    );
  }

  void _showSearchIndexDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final semanticEnabled = ref.watch(semanticSearchEnabledProvider);
          return AlertDialog(
            title: const Text('本地搜索索引'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('本地搜索使用 SQLite FTS 和本地语义索引加速长会话检索。'),
                const SizedBox(height: 8),
                const Text('检查：只读取索引健康状态。'),
                const Text('预热 / 修复：创建索引、补建历史消息、生成本地语义向量，并修复索引行数不一致。'),
                const SizedBox(height: 8),
                const Text('该操作只处理本机 SQLite 数据，不上传搜索词、消息内容、语义向量或文件路径。'),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用本地语义搜索'),
                  subtitle: Text(
                    semanticEnabled
                        ? '开启后可用近义表达检索历史消息'
                        : '关闭后仅使用标题、FTS/LIKE 和 Key Points 字面检索',
                  ),
                  value: semanticEnabled,
                  onChanged: (value) {
                    ref
                        .read(semanticSearchEnabledProvider.notifier)
                        .setEnabled(value);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _checkSearchIndex(context, ref);
                },
                child: const Text('检查'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _prewarmSearchIndex(context, ref);
                },
                child: const Text('预热 / 修复'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _checkSearchIndex(BuildContext context, WidgetRef ref) async {
    final dao = ref.read(messageDaoProvider);
    final health = await dao.checkMessageFtsIndexHealth();
    final semanticHealth = await dao.checkMessageSemanticIndexHealth();
    if (!context.mounted) return;
    _showArchiveSnack(
      context,
      _formatSearchIndexHealth(health, semanticHealth: semanticHealth),
    );
  }

  Future<void> _prewarmSearchIndex(BuildContext context, WidgetRef ref) async {
    final dao = ref.read(messageDaoProvider);
    final health = await dao.prewarmMessageFtsIndex();
    final semanticHealth = await dao.prewarmMessageSemanticIndex();
    if (!context.mounted) return;
    _showArchiveSnack(
      context,
      _formatSearchIndexHealth(health, semanticHealth: semanticHealth),
    );
  }

  String _formatSearchIndexHealth(
    MessageFtsIndexHealth health, {
    MessageSemanticIndexHealth? semanticHealth,
  }) {
    if (!health.isAvailable) {
      return health.failureReason ?? '搜索索引不可用';
    }
    final semanticText = semanticHealth == null
        ? ''
        : _formatSemanticIndexHealthSuffix(semanticHealth);
    if (health.isConsistent) {
      final prefix = health.rebuilt ? '搜索索引已预热并修复' : '搜索索引健康';
      return '$prefix：FTS ${health.indexedRowCount} 条消息，耗时 ${health.elapsedMs} ms$semanticText';
    }
    return '搜索索引需修复：原始消息 ${health.originalMessageCount} 条，FTS ${health.indexedRowCount} 条，缺失 ${health.missingIndexCount} 条$semanticText';
  }

  String _formatSemanticIndexHealthSuffix(MessageSemanticIndexHealth health) {
    if (!health.isAvailable) {
      return '；语义索引不可用';
    }
    if (health.isConsistent) {
      final prefix = health.rebuilt ? '；语义索引已修复' : '；语义索引健康';
      return '$prefix ${health.indexedRowCount} 条，耗时 ${health.elapsedMs} ms';
    }
    return '；语义索引需修复：索引 ${health.indexedRowCount} 条，缺失/过期 ${health.missingOrStaleIndexCount} 条，多余 ${health.extraIndexCount} 条';
  }

  // ====== Dreaming 夜间整理 ======

  Widget _buildDreamingTile(BuildContext context, WidgetRef ref) {
    final digest = ref.watch(dreamingDigestProvider);
    final schedule = ref.watch(dreamingScheduleProvider);
    final scheduleText =
        '${schedule.enabled ? '自动整理已开启' : '自动整理已关闭'} · ${formatDreamingScheduleTime(schedule)}';
    final subtitle = digest == null
        ? '$scheduleText · 可手动生成今日摘要'
        : '$scheduleText · 最近 ${digest.dayKey} · ${digest.originalMessageCount} 条消息';

    return ListTile(
      leading: const Icon(Icons.nightlight_round_outlined),
      title: const Text('Dreaming 夜间整理'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showDreamingDialog(context, ref),
    );
  }

  void _showDreamingDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final digest = ref.watch(dreamingDigestProvider);
          final schedule = ref.watch(dreamingScheduleProvider);
          final preview = digest?.toMarkdown();
          return AlertDialog(
            title: const Text('Dreaming 夜间整理'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('本地 v1 会整理今日原始消息，生成会话摘要、关键词和记忆候选。'),
                    const SizedBox(height: 8),
                    const Text(
                      '当前不会上传云端，也不会调用远端模型。自动整理采用前台到期触发：到达设定时间后，打开应用会自动整理一次。',
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('前台到期自动整理'),
                      subtitle: Text(
                        '默认夜间 ${formatDreamingScheduleTime(schedule)}',
                      ),
                      value: schedule.enabled,
                      onChanged: (value) => ref
                          .read(dreamingScheduleProvider.notifier)
                          .setEnabled(value),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('整理时间'),
                      subtitle: Text(formatDreamingScheduleTime(schedule)),
                      trailing: const Icon(Icons.schedule_outlined),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay(
                            hour: schedule.hour,
                            minute: schedule.minute,
                          ),
                        );
                        if (picked == null) return;
                        await ref
                            .read(dreamingScheduleProvider.notifier)
                            .setTime(hour: picked.hour, minute: picked.minute);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (digest == null)
                      const Text('暂无 Dreaming 报告。')
                    else ...[
                      Text(
                        '最近报告：${digest.dayKey} · ${digest.originalMessageCount} 条消息 · 耗时 ${digest.elapsedMs} ms',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        preview == null || preview.isEmpty ? '暂无摘要内容' : preview,
                        maxLines: 12,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _runDreaming(context, ref);
                },
                child: const Text('运行今日整理'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _runDreaming(BuildContext context, WidgetRef ref) async {
    final digest = await runDreamingDigest(ref);
    final proposal = digest.hasContent
        ? await proposeUserProfileChanges(ref, reason: 'profile_proposal')
        : null;
    if (!context.mounted) return;
    final message = digest.hasContent
        ? proposal == null
              ? 'Dreaming 已完成：${digest.originalMessageCount} 条消息，画像暂无新增变更'
              : 'Dreaming 已完成：${digest.originalMessageCount} 条消息，已生成待确认画像变更（${proposal.diff.summary}）'
        : 'Dreaming 已完成：今天暂无可整理对话';
    _showArchiveSnack(context, message);
  }

  // ====== 用户画像 / 镜像数字人基础 ======

  Widget _buildUserProfileTile(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final proposals = ref.watch(userProfileChangeProposalsProvider);
    final proposalSuffix = proposals.isEmpty
        ? ''
        : ' · ${proposals.length} 个待确认变更';
    final subtitle = profile == null
        ? '尚未生成 · 可从本地 Key Points 与 Dreaming 报告重建$proposalSuffix'
        : profile.hasContent
        ? '${profile.sourceCount} 条来源 · ${profile.totalSignalCount} 个画像信号 · 本地保存$proposalSuffix'
        : '暂无足够画像信号 · 继续聊天或添加记忆后重建$proposalSuffix';

    return ListTile(
      leading: const Icon(Icons.person_search_outlined),
      title: const Text('用户画像 / 镜像数字人基础'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showUserProfileDialog(context, ref),
    );
  }

  void _showUserProfileDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final profile = ref.watch(userProfileProvider);
          final controls = ref.watch(userProfileControlsProvider);
          final history = ref.watch(userProfileHistoryProvider);
          final proposals = ref.watch(userProfileChangeProposalsProvider);
          return AlertDialog(
            title: const Text('用户画像 / 镜像数字人基础'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '本地 v1 只读取本机 Key Points 与最近 Dreaming 报告，生成可解释画像；不上传云端，不调用远端模型。',
                    ),
                    const SizedBox(height: 12),
                    if (proposals.isNotEmpty) ...[
                      const Text(
                        '待确认画像变更',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      for (final proposal in proposals.take(3))
                        _buildProfileProposalEntry(context, ref, proposal),
                      const SizedBox(height: 12),
                    ],
                    if (profile == null)
                      const Text('尚未生成用户画像。')
                    else if (!profile.hasContent)
                      const Text('当前本地记忆不足，暂未形成有效画像。')
                    else ...[
                      Text('更新时间：${profile.updatedAt.toLocal()}'),
                      Text('来源记忆数：${profile.sourceCount}'),
                      if (profile.digestDayKey != null)
                        Text('最近 Dreaming：${profile.digestDayKey}'),
                      if (controls.hasControls)
                        Text(
                          '用户控制：已隐藏 ${controls.hiddenCount} 条，已编辑 ${controls.editedCount} 条',
                        ),
                      const SizedBox(height: 12),
                      if (profile.conflicts.isNotEmpty) ...[
                        Text(
                          '冲突提示',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 4),
                        for (final conflict in profile.conflicts.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '• $conflict',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                      _buildProfileSection(
                        context,
                        ref,
                        '偏好',
                        profile.preferences,
                      ),
                      _buildProfileSection(context, ref, '目标', profile.goals),
                      _buildProfileSection(context, ref, '任务', profile.tasks),
                      _buildProfileSection(
                        context,
                        ref,
                        '基础画像',
                        profile.profileFacts,
                      ),
                      _buildProfileSection(
                        context,
                        ref,
                        '表达风格',
                        profile.styleSignals,
                      ),
                      _buildProfileSection(
                        context,
                        ref,
                        '作息线索',
                        profile.scheduleSignals,
                      ),
                      _buildProfileSection(
                        context,
                        ref,
                        '关键词',
                        profile.keywords,
                        editable: false,
                      ),
                      if (history.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          '版本历史',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        for (final entry in history.take(5))
                          _buildProfileHistoryEntry(
                            context,
                            ctx,
                            ref,
                            profile,
                            entry,
                          ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      '安全边界：画像只作为本地个性化参考；未来代理用户回复、同步或对外发送前必须明确授权。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (history.isNotEmpty)
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _clearUserProfileHistory(context, ref);
                  },
                  child: const Text('清空历史'),
                ),
              if (controls.hasControls)
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _clearUserProfileControls(context, ref);
                  },
                  child: const Text('清除编辑/删除'),
                ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _rebuildUserProfile(context, ref);
                },
                child: const Text('重建画像'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileSection(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<String> values, {
    bool editable = true,
  }) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          for (final value in values.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '• $value',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (editable) ...[
                    IconButton(
                      tooltip: '编辑画像信号',
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () =>
                          _showEditUserProfileSignalDialog(context, ref, value),
                    ),
                    IconButton(
                      tooltip: '删除画像信号',
                      icon: const Icon(Icons.visibility_off_outlined, size: 16),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () =>
                          _hideUserProfileSignal(context, ref, value),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileProposalEntry(
    BuildContext context,
    WidgetRef ref,
    UserProfileChangeProposal proposal,
  ) {
    final diff = proposal.diff;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              proposal.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '生成时间：${proposal.createdAt.toLocal()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (diff.hasChanges) ...[
              const SizedBox(height: 4),
              for (final section in diff.changedSections.take(3))
                Text(
                  '${section.title}：${section.summary}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 8),
              const Text(
                '逐项确认',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              for (final item in diff.items.take(4))
                _buildProfileProposalChangeItem(context, ref, proposal, item),
              if (diff.items.length > 4)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.format_list_bulleted, size: 16),
                    label: Text('查看全部 ${diff.items.length} 项'),
                    onPressed: () => _showProfileProposalDetailsDialog(
                      context,
                      ref,
                      proposal.id,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('忽略变更'),
                  onPressed: () =>
                      _rejectUserProfileProposal(context, ref, proposal.id),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('采纳变更'),
                  onPressed: () =>
                      _acceptUserProfileProposal(context, ref, proposal.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showProfileProposalDetailsDialog(
    BuildContext context,
    WidgetRef ref,
    String proposalId,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (dialogContext, ref, _) {
          UserProfileChangeProposal? proposal;
          for (final candidate in ref.watch(
            userProfileChangeProposalsProvider,
          )) {
            if (candidate.id == proposalId) {
              proposal = candidate;
              break;
            }
          }
          final currentProposal = proposal;
          if (currentProposal == null) {
            return AlertDialog(
              title: const Text('待确认画像变更详情'),
              content: const Text('该待确认画像变更已处理完毕。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭'),
                ),
              ],
            );
          }

          final diff = currentProposal.diff;
          return AlertDialog(
            title: const Text('待确认画像变更详情'),
            content: SizedBox(
              width: 460,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentProposal.summary,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '生成时间：${currentProposal.createdAt.toLocal()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '全部待确认项',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      if (!diff.hasChanges)
                        const Text('当前已无剩余差异。')
                      else
                        for (final item in diff.items)
                          _buildProfileProposalChangeItem(
                            dialogContext,
                            ref,
                            currentProposal,
                            item,
                          ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileProposalChangeItem(
    BuildContext context,
    WidgetRef ref,
    UserProfileChangeProposal proposal,
    UserProfileChangeItem item,
  ) {
    final color = item.type == UserProfileChangeType.added
        ? Colors.green[700]
        : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.sectionTitle} · ${item.label}：${item.value}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: color),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => _rejectUserProfileProposalItem(
                    context,
                    ref,
                    proposal.id,
                    item,
                  ),
                  child: const Text('忽略此项'),
                ),
                TextButton(
                  onPressed: () => _acceptUserProfileProposalItem(
                    context,
                    ref,
                    proposal.id,
                    item,
                  ),
                  child: const Text('采纳此项'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHistoryEntry(
    BuildContext context,
    BuildContext dialogContext,
    WidgetRef ref,
    UserProfile? currentProfile,
    UserProfileHistoryEntry entry,
  ) {
    final diff = diffUserProfiles(
      current: currentProfile,
      candidate: entry.profile,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${entry.createdAt.toLocal()} · ${diff.summary}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (diff.hasChanges) ...[
              const SizedBox(height: 4),
              for (final section in diff.changedSections.take(2))
                Text(
                  '${section.title}：${section.summary}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('恢复此版本'),
                onPressed: diff.hasChanges
                    ? () {
                        Navigator.pop(dialogContext);
                        _restoreUserProfileHistory(context, ref, entry.id);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditUserProfileSignalDialog(
    BuildContext context,
    WidgetRef ref,
    String original,
  ) {
    final controller = TextEditingController(text: original);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑画像信号'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '画像内容',
            helperText: '只保存在本机；请不要写入 API Key、密码或 token',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final profile = await editUserProfileSignal(
                ref,
                original: original,
                edited: controller.text,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!context.mounted) return;
              _showArchiveSnack(
                context,
                profile == null ? '画像编辑未保存：内容为空或包含敏感字段' : '画像信号已更新',
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _hideUserProfileSignal(
    BuildContext context,
    WidgetRef ref,
    String signal,
  ) async {
    final profile = await hideUserProfileSignal(ref, signal);
    if (!context.mounted) return;
    _showArchiveSnack(
      context,
      profile.hasContent ? '画像信号已删除并在重建时保持隐藏' : '画像信号已删除，当前暂无画像内容',
    );
  }

  Future<void> _clearUserProfileControls(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(userProfileControlsProvider.notifier).clearControls();
    final profile = await rebuildUserProfile(ref, reason: 'clear_controls');
    if (!context.mounted) return;
    _showArchiveSnack(
      context,
      profile.hasContent ? '画像编辑/删除记录已清除，画像已重建' : '画像编辑/删除记录已清除',
    );
  }

  Future<void> _acceptUserProfileProposal(
    BuildContext context,
    WidgetRef ref,
    String proposalId,
  ) async {
    final profile = await acceptUserProfileProposal(ref, proposalId);
    if (!context.mounted) return;
    _showArchiveSnack(
      context,
      profile == null
          ? '待确认画像变更不存在，无法采纳'
          : '已采纳画像变更：${profile.totalSignalCount} 个画像信号',
    );
  }

  Future<void> _acceptUserProfileProposalItem(
    BuildContext context,
    WidgetRef ref,
    String proposalId,
    UserProfileChangeItem item,
  ) async {
    final profile = await acceptUserProfileProposalItem(
      ref,
      proposalId: proposalId,
      item: item,
    );
    if (!context.mounted) return;
    _showArchiveSnack(
      context,
      profile == null
          ? '待确认画像变更不存在，无法采纳'
          : '已采纳单条画像变更：${item.sectionTitle} · ${item.label}',
    );
  }

  Future<void> _rejectUserProfileProposal(
    BuildContext context,
    WidgetRef ref,
    String proposalId,
  ) async {
    final rejected = await rejectUserProfileProposal(ref, proposalId);
    if (!context.mounted) return;
    _showArchiveSnack(context, rejected ? '已忽略待确认画像变更' : '待确认画像变更不存在');
  }

  Future<void> _rejectUserProfileProposalItem(
    BuildContext context,
    WidgetRef ref,
    String proposalId,
    UserProfileChangeItem item,
  ) async {
    final rejected = await rejectUserProfileProposalItem(
      ref,
      proposalId: proposalId,
      item: item,
    );
    if (!context.mounted) return;
    _showArchiveSnack(
      context,
      rejected
          ? '已忽略单条画像变更：${item.sectionTitle} · ${item.label}'
          : '待确认画像变更不存在',
    );
  }

  Future<void> _clearUserProfileHistory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(userProfileHistoryProvider.notifier).clearHistory();
    if (!context.mounted) return;
    _showArchiveSnack(context, '用户画像版本历史已清空');
  }

  Future<void> _restoreUserProfileHistory(
    BuildContext context,
    WidgetRef ref,
    String historyEntryId,
  ) async {
    final profile = await restoreUserProfileFromHistory(ref, historyEntryId);
    if (!context.mounted) return;
    _showArchiveSnack(
      context,
      profile == null
          ? '历史版本不存在，无法恢复'
          : '已恢复历史画像：${profile.totalSignalCount} 个画像信号',
    );
  }

  Future<void> _rebuildUserProfile(BuildContext context, WidgetRef ref) async {
    final profile = await rebuildUserProfile(ref, reason: 'manual_rebuild');
    if (!context.mounted) return;
    final message = profile.hasContent
        ? '用户画像已重建：${profile.sourceCount} 条来源，${profile.totalSignalCount} 个画像信号'
        : '用户画像已重建：暂无足够本地记忆';
    _showArchiveSnack(context, message);
  }

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
                      onPressed: () =>
                          _showPromptEditDialog(context, ref, prompt: p),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete,
                        size: 18,
                        color: Colors.red,
                      ),
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
    final categoryCtrl = TextEditingController(
      text: prompt?.category ?? 'general',
    );

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
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '如 翻译助手',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryCtrl,
                decoration: const InputDecoration(
                  labelText: '分类',
                  hintText: 'general',
                ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref
                  .read(promptNotifierProvider.notifier)
                  .deletePrompt(prompt.id);
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
    final scheme = Theme.of(context).colorScheme;

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
              [
                server.transport == 'stdio'
                    ? '${server.command} ${(server.args ?? []).join(' ')}'
                    : server.url ?? '',
                if (manager.isConnected(server.id))
                  '状态：已连接'
                else if (manager.connectionErrorFor(server.id) != null)
                  '状态：连接失败',
              ].join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: manager.isConnected(server.id)
                    ? Colors.green[600]
                    : manager.connectionErrorFor(server.id) != null
                    ? scheme.error
                    : null,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: server.isEnabled,
                  onChanged: (v) async {
                    await manager.updateServer(server.copyWith(isEnabled: v));
                    if (v) {
                      try {
                        await manager.connectServer(server);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('MCP 连接失败: $e')),
                          );
                        }
                      }
                    } else {
                      await manager.disconnectServer(server.id);
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
        ListTile(
          leading: Icon(
            Icons.store_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('浏览 MCP 市场'),
          subtitle: const Text(
            '发现和安装热门 MCP 服务器',
            style: TextStyle(fontSize: 12),
          ),
          onTap: () => Navigator.pushNamed(context, '/marketplace'),
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
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '如 filesystem',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: transport,
                  decoration: const InputDecoration(labelText: '传输方式'),
                  items: const [
                    DropdownMenuItem(
                      value: 'stdio',
                      child: Text('Stdio（本地进程）'),
                    ),
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
                      hintText:
                          'npx -y @modelcontextprotocol/server-filesystem',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: argsCtrl,
                    decoration: const InputDecoration(
                      labelText: '参数（空格分隔）',
                      hintText: '本地目录路径（例如 Documents）',
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
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
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(SnackBar(content: Text('连接失败: $e')));
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

  // ====== Skills 技能 ======

  Widget _buildSkillsSection(BuildContext context, WidgetRef ref) {
    final skillsAsync = ref.watch(skillsProvider);

    return skillsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListTile(title: Text('加载失败: $e')),
      data: (skills) {
        final enabledCount = skills.where((s) => s.isEnabled).length;
        return Column(
          children: [
            for (final skill in skills)
              ListTile(
                leading: Icon(
                  skill.online
                      ? Icons.cloud_outlined
                      : Icons.inventory_2_outlined,
                  size: 20,
                  color: skill.isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(skill.name, style: const TextStyle(fontSize: 14)),
                subtitle: skill.description.isNotEmpty
                    ? Text(
                        skill.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (skill.sourceSha256 != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          skill.sha256Verified
                              ? Icons.verified
                              : Icons.warning_amber,
                          size: 14,
                          color: skill.sha256Verified
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                    Switch(
                      value: skill.isEnabled,
                      onChanged: (v) => toggleSkill(ref, skill.id, v),
                    ),
                    if (skill.online)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => uninstallSkill(ref, skill.id),
                      ),
                  ],
                ),
              ),
            ListTile(
              leading: Icon(
                Icons.extension_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('Skills Hub'),
              subtitle: Text(
                '已启用 $enabledCount / ${skills.length}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showSkillsHubSheet(context),
            ),
          ],
        );
      },
    );
  }

  void _showSkillsHubSheet(BuildContext context) {
    showSkillsHubSheet(context);
  }
}

class _ProviderPresetHint extends StatelessWidget {
  final ModelProviderPreset preset;

  const _ProviderPresetHint({required this.preset});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                preset.openAiCompatible
                    ? Icons.hub_outlined
                    : getProtocolIcon(preset.protocol),
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  preset.openAiCompatible ? 'OpenAI 兼容预设' : '官方协议预设',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(preset.description, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          SelectableText(
            preset.docsUrl,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
