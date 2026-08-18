import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/background/dreaming_background_workmanager.dart';
import '../../core/background/ios_background_refresh_status.dart';
import '../../core/archive/data_import_service.dart';
import '../../core/archive/data_export_service.dart';
import '../../core/archive/data_export_share_service.dart';
import '../../core/archive/markdown_conversation_archive.dart';
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
import '../../core/database/dao/persona_audit_log_dao.dart';
import '../../core/memory/dreaming_service.dart';
import '../../core/memory/dreaming_schedule.dart';
import '../../core/memory/reflection_service.dart';
import '../../core/memory/user_profile.dart';
import '../../core/twin/persona_profile.dart';
import '../../core/twin/live_stream_service.dart';
import '../../core/media/media_job.dart';
import '../../core/media/speech_provider_preset.dart';
import '../../core/media/text_to_speech_service.dart';
import '../../core/media/xai_custom_voice_adapter.dart';
import '../../core/media/xai_speech_provider_profile.dart';
import '../../core/mcp/mcp_client.dart';
import '../../core/relay/openai_compatible_relay_server.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/audio_transcription_provider.dart';
import '../../shared/providers/image_generation_provider.dart';
import '../../shared/providers/universal_media_provider.dart';
import '../../shared/providers/webdav_backup_provider.dart';
import '../../shared/providers/s3_backup_provider.dart';
import '../../shared/providers/one_drive_backup_provider.dart';
import '../../shared/providers/persona_provider.dart';
import '../../shared/providers/telegram_bot_provider.dart';
import '../../shared/providers/discord_bot_provider.dart';
import '../../shared/providers/feishu_bot_provider.dart';
import '../../shared/providers/webhook_bot_provider.dart';
import '../../shared/providers/notion_sync_provider.dart';
import '../../shared/providers/note_sync_providers.dart';
import '../../core/backup/webdav_backup_service.dart';
import '../../core/backup/s3_backup_service.dart';
import '../../core/backup/one_drive_backup_service.dart';
import '../../core/archive/notion_sync_service.dart';
import '../../core/archive/yuque_sync_service.dart';
import '../../core/archive/siyuan_sync_service.dart';
import '../../shared/providers/channel_provider.dart';
import '../../shared/providers/chat_provider.dart';
import '../../shared/providers/conversation_archive_provider.dart';
import '../../shared/providers/dreaming_provider.dart';
import '../../shared/providers/mcp_provider.dart';
import '../../shared/providers/mcp_runtime_provider.dart';
import '../../shared/providers/model_test_history_provider.dart';
import '../../shared/providers/openai_relay_provider.dart';
import '../../shared/providers/prompt_provider.dart';
import '../../shared/providers/reflection_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/skill_provider.dart';
import '../../shared/providers/session_provider.dart';
import '../../shared/providers/text_to_speech_provider.dart';
import '../../shared/providers/user_profile_provider.dart';
import '../../shared/widgets/in_app_h5_page.dart';
import '../skills/skills_hub_page.dart';

typedef SettingsModelTestRunner =
    Future<ModelTestResult> Function({
      required String protocol,
      required String baseUrl,
      required String apiKey,
      required String model,
      required String capability,
    });

String _safeTtsDialogError(Object error, {bool customVoice = true}) {
  if (error is XaiCustomVoiceException) return error.message;
  if (error is TextToSpeechException) return error.message;
  return customVoice
      ? 'xAI custom voice 创建或 TTS 配置保存失败，请检查设置后重试'
      : 'TTS 配置保存失败，请检查设置后重试';
}

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
          _buildWebDavBackupTile(context, ref),
          _buildS3BackupTile(context, ref),
          _buildOneDriveBackupTile(context, ref),
          _buildNotionSyncTile(context, ref),
          _buildYuqueSyncTile(context, ref),
          _buildSiyuanSyncTile(context, ref),

          const Divider(),

          // 记忆与画像
          _buildSectionHeader(context, '记忆与画像'),
          _buildUserProfileTile(context, ref),
          _buildDigitalTwinTile(context, ref),
          _buildLiveStreamTile(context, ref),
          _buildReflectionTile(context, ref),

          const Divider(),

          // 语音与多模态
          _buildSectionHeader(context, '语音与多模态'),
          _buildVoiceInputTile(context, ref),
          _buildTextToSpeechTile(context, ref),

          const Divider(),

          // 图片生成
          _buildSectionHeader(context, '图片生成'),
          _buildImageGenerationTile(context, ref),
          _buildUniversalMediaTile(context, ref),

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

          // 社交通道
          _buildSectionHeader(context, '社交通道'),
          _buildTelegramBotTile(context, ref),
          _buildDiscordBotTile(context, ref),
          _buildFeishuBotTile(context, ref),
          _buildWebhookChannelTile(context, ref),

          const Divider(),

          // 关于
          _buildSectionHeader(context, '关于'),
          const ListTile(title: Text('版本'), subtitle: Text('1.0.0')),
          _buildCreditsTile(context),
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
            _buildDwChainlessCard(context, ref, channels),
            const InAppH5Prewarm(url: kSimiRouterHomeUrl),
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

  /// 找到已接入 SimiRouter（dwchainless）中转站的渠道（按 Base URL 域名匹配）。
  ModelChannel? _findDwChainlessChannel(List<ModelChannel> channels) {
    for (final channel in channels) {
      final uri = Uri.tryParse(channel.baseUrl.trim());
      if (uri?.scheme == 'https' &&
          uri?.host.toLowerCase() == 'api.dwchainless.com' &&
          uri?.port == 443 &&
          uri?.userInfo.isEmpty == true) {
        return channel;
      }
    }
    return null;
  }

  /// 在应用内打开 H5 页面，不调用系统浏览器，也不把地址展示给用户。
  Future<void> _openInAppH5(
    BuildContext context, {
    required String url,
    required String title,
  }) async {
    final uri = normalizeInAppH5Url(url);
    if (uri == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('页面地址无效，暂时无法打开')));
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InAppH5Page(
          initialUrl: uri.toString(),
          title: title,
          brandAsset: 'assets/branding/simirouter.png',
        ),
      ),
    );
  }

  /// SimiRouter AI 中转站紧凑接入卡片。
  ///
  /// 未接入时只保留一句定位和三个直接动作；接入后折叠为状态 + 管理/官网，
  /// 不再长期占用设置页首屏展示六个营销标签。
  Widget _buildDwChainlessCard(
    BuildContext context,
    WidgetRef ref,
    List<ModelChannel> channels,
  ) {
    final preset = findModelProviderPreset('dwchainless');
    final channel = _findDwChainlessChannel(channels);
    final hasKey = channel != null && channel.apiKeyEncrypted.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const actionStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, 44)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
    );

    return Container(
      key: const Key('simirouter_channel_card'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.55),
            scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: scheme.surface,
                backgroundImage: const AssetImage(
                  'assets/branding/simirouter.png',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SimiRouter AI 中转站',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      hasKey
                          ? '已接入 · 可管理模型和 API Key'
                          : channel != null
                          ? '已添加 · 尚未填写 API Key'
                          : '主流模型统一接入 · 智能路由',
                      style: textTheme.bodySmall?.copyWith(
                        color: hasKey
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                channel == null
                    ? Icons.bolt_outlined
                    : hasKey
                    ? Icons.check_circle
                    : Icons.error_outline,
                color: channel == null
                    ? scheme.primary
                    : hasKey
                    ? Colors.green[700]
                    : scheme.error,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!hasKey) ...[
                Expanded(
                  child: FilledButton(
                    style: actionStyle,
                    child: const Text('获取 Key'),
                    onPressed: () {
                      final signUpUrl =
                          preset?.signUpUrl ?? kSimiRouterSignUpUrl;
                      _openInAppH5(context, url: signUpUrl, title: '获取 Key');
                    },
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: OutlinedButton(
                  style: actionStyle,
                  child: Text(
                    hasKey
                        ? '管理'
                        : channel != null
                        ? '补充 Key'
                        : '一键接入',
                  ),
                  onPressed: () => _showChannelEditDialog(
                    context,
                    ref,
                    channel: channel,
                    initialPresetId: channel == null ? preset?.id : null,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextButton(
                  style: actionStyle,
                  child: const Text('官网'),
                  onPressed: () => _openInAppH5(
                    context,
                    url: preset?.docsUrl ?? kSimiRouterHomeUrl,
                    title: '访问官网',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ====== 社交通道 / Telegram Bot ======

  Widget _buildTelegramBotTile(BuildContext context, WidgetRef ref) {
    final state = ref.watch(telegramBotProvider);
    final subtitle = state.running
        ? '运行中${state.botUsername != null ? ' · @${state.botUsername}' : ''}'
        : state.lastError != null
        ? '上次错误：${state.lastError}'
        : '未启动 · 配置 Bot Token 后可在 Telegram 中与 AI 对话';
    return ListTile(
      leading: Icon(
        state.running ? Icons.smart_toy : Icons.smart_toy_outlined,
        color: state.running ? Colors.green[700] : null,
      ),
      title: const Text('Telegram Bot'),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showTelegramBotDialog(context, ref),
    );
  }

  void _showTelegramBotDialog(BuildContext context, WidgetRef ref) {
    final state = ref.read(telegramBotProvider);
    final tokenCtrl = TextEditingController();
    var busy = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Telegram Bot 社交通道'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Bot Token',
                    hintText: '123456:ABC...',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '在 @BotFather 创建 Bot 后填入 Token。启动后 Bot 会通过长轮询接收消息，用当前默认聊天模型回复。',
                  style: TextStyle(fontSize: 12),
                ),
                if (state.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '上次错误：${state.lastError}',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await ref
                    .read(telegramBotProvider.notifier)
                    .saveToken(tokenCtrl.text);
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
              },
              child: const Text('保存 Token'),
            ),
            if (!state.running)
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setDialogState(() => busy = true);
                        final token = tokenCtrl.text.trim();
                        if (token.isNotEmpty) {
                          await ref
                              .read(telegramBotProvider.notifier)
                              .saveToken(token);
                        }
                        final error = await ref
                            .read(telegramBotProvider.notifier)
                            .start();
                        if (!ctx.mounted) return;
                        setDialogState(() => busy = false);
                        if (error != null) {
                          ScaffoldMessenger.of(ctx)
                            ..clearSnackBars()
                            ..showSnackBar(SnackBar(content: Text(error)));
                        } else {
                          Navigator.of(ctx).pop();
                        }
                      },
                child: const Text('启动 Bot'),
              )
            else
              TextButton(
                onPressed: () async {
                  await ref.read(telegramBotProvider.notifier).stop();
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                },
                child: const Text('停止 Bot'),
              ),
          ],
        ),
      ),
    );
  }

  // ====== S3 云备份 ======

  Widget _buildS3BackupTile(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(s3BackupSettingsProvider);
    final subtitle = settings.isConfigured
        ? '已配置 ${settings.endpoint} / ${settings.bucket}'
        : '未配置 · 导出包加密上传到 S3 兼容存储';
    return ListTile(
      leading: Icon(
        settings.isConfigured
            ? Icons.cloud_done_outlined
            : Icons.cloud_outlined,
        color: settings.isConfigured ? Colors.orange[700] : null,
      ),
      title: const Text('S3 云备份'),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showS3BackupDialog(context, ref),
    );
  }

  void _showS3BackupDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(s3BackupSettingsProvider);
    final endpointCtrl = TextEditingController(text: current.endpoint);
    final regionCtrl = TextEditingController(text: current.region);
    final accessCtrl = TextEditingController(text: current.accessKey);
    final secretCtrl = TextEditingController(text: current.secretKey);
    final bucketCtrl = TextEditingController(text: current.bucket);
    var busy = false;

    S3BackupConfig s3Config(String passphrase) => S3BackupConfig(
      endpoint: endpointCtrl.text,
      region: regionCtrl.text,
      accessKey: accessCtrl.text,
      secretKey: secretCtrl.text,
      bucket: bucketCtrl.text,
      passphrase: passphrase,
    );

    Future<void> backupNow(String passphrase) async {
      if (kIsWeb) {
        _showArchiveSnack(context, '当前平台暂不支持 S3 备份');
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
        ).exportLocalData(includeAudioFiles: true);

        await const S3BackupService().uploadBackup(
          exportFile: result.file,
          config: s3Config(passphrase),
        );
        if (!context.mounted) return;
        _showArchiveSnack(
          context,
          'S3 备份已上传：${result.file.uri.pathSegments.last}',
        );
      } catch (e) {
        if (!context.mounted) return;
        _showArchiveSnack(context, 'S3 备份失败：$e');
      }
    }

    Future<void> restoreFromS3(String passphrase) async {
      if (kIsWeb) {
        _showArchiveSnack(context, '当前平台暂不支持 S3 恢复');
        return;
      }
      try {
        final service = const S3BackupService();
        final entries = await service.listBackups(s3Config(passphrase));
        if (!context.mounted) return;
        if (entries.isEmpty) {
          _showArchiveSnack(context, '远端没有可恢复的备份');
          return;
        }
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('选择要恢复的备份'),
            children: [
              for (final entry in entries)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(entry.key),
                  child: Text(
                    '${entry.key} · ${(entry.size / 1024).toStringAsFixed(1)} KB',
                  ),
                ),
            ],
          ),
        );
        if (choice == null || !context.mounted) return;

        final root = await getApplicationDocumentsDirectory();
        final tmp = Directory(
          p.join((await getTemporaryDirectory()).path, 's3_restore'),
        );
        final downloaded = await service.downloadBackup(
          key: choice,
          config: s3Config(passphrase),
          downloadDirectory: tmp,
        );
        final importResult = await DataImportService(
          rootDirectory: root,
          localDatabaseSnapshotService: LocalDatabaseSnapshotService(
            database: ref.read(databaseProvider),
            rootDirectory: root,
          ),
        ).importExport(downloaded, overwriteExisting: false);
        if (!context.mounted) return;
        _showArchiveSnack(context, '已恢复：${importResult.summary}');
      } catch (e) {
        if (!context.mounted) return;
        _showArchiveSnack(context, 'S3 恢复失败：$e');
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('S3 云备份'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: endpointCtrl,
                  decoration: const InputDecoration(
                    labelText: 'S3 端点',
                    hintText:
                        'https://s3.us-east-1.amazonaws.com 或 MinIO/R2/COS',
                  ),
                ),
                TextField(
                  controller: regionCtrl,
                  decoration: const InputDecoration(labelText: 'Region'),
                ),
                TextField(
                  controller: accessCtrl,
                  decoration: const InputDecoration(labelText: 'Access Key'),
                ),
                TextField(
                  controller: secretCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Secret Key'),
                ),
                TextField(
                  controller: bucketCtrl,
                  decoration: const InputDecoration(labelText: '存储桶'),
                ),
                const SizedBox(height: 12),
                const Text(
                  '备份口令用于端到端加密，不会保存在本机；每次备份 / 恢复都需要输入，请务必牢记。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref
                    .read(s3BackupSettingsProvider.notifier)
                    .save(
                      S3BackupSettings(
                        endpoint: endpointCtrl.text,
                        region: regionCtrl.text,
                        accessKey: accessCtrl.text,
                        secretKey: secretCtrl.text,
                        bucket: bucketCtrl.text,
                      ),
                    );
                Navigator.of(ctx).pop();
              },
              child: const Text('保存配置'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final pass = await _askBackupPassphrase(ctx);
                      if (pass == null || !ctx.mounted) return;
                      setDialogState(() => busy = true);
                      await backupNow(pass);
                      if (!ctx.mounted) return;
                      setDialogState(() => busy = false);
                    },
              child: const Text('立即备份'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final pass = await _askBackupPassphrase(ctx);
                      if (pass == null || !ctx.mounted) return;
                      setDialogState(() => busy = true);
                      await restoreFromS3(pass);
                      if (!ctx.mounted) return;
                      setDialogState(() => busy = false);
                    },
              child: const Text('从云端恢复'),
            ),
            if (current.isConfigured)
              TextButton(
                onPressed: () {
                  ref.read(s3BackupSettingsProvider.notifier).clear();
                  Navigator.of(ctx).pop();
                },
                child: const Text('清除配置'),
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askBackupPassphrase(BuildContext ctx) async {
    final passCtrl = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (pctx) => AlertDialog(
        title: const Text('输入备份口令'),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(hintText: '至少 8 位'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(pctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(pctx).pop(passCtrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ====== OneDrive 云盘备份 ======

  Widget _buildOneDriveBackupTile(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(oneDriveBackupSettingsProvider);
    return ListTile(
      leading: Icon(
        settings.isConfigured
            ? Icons.cloud_done_outlined
            : Icons.cloud_outlined,
        color: settings.isConfigured ? Colors.blue[700] : null,
      ),
      title: const Text('OneDrive 云盘备份'),
      subtitle: Text(
        settings.isConfigured
            ? '已配置 · ${settings.folder}'
            : '未配置 · 导出包加密上传到 OneDrive',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showOneDriveBackupDialog(context, ref),
    );
  }

  void _showOneDriveBackupDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(oneDriveBackupSettingsProvider);
    final tokenCtrl = TextEditingController(text: current.accessToken);
    final folderCtrl = TextEditingController(text: current.folder);
    var busy = false;

    OneDriveBackupConfig odConfig(String passphrase) => OneDriveBackupConfig(
      accessToken: tokenCtrl.text,
      folder: folderCtrl.text,
      passphrase: passphrase,
    );

    Future<void> backupNow(String passphrase) async {
      if (kIsWeb) {
        _showArchiveSnack(context, '当前平台暂不支持 OneDrive 备份');
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
        ).exportLocalData(includeAudioFiles: true);

        await OneDriveBackupService().uploadBackup(
          exportFile: result.file,
          config: odConfig(passphrase),
        );
        if (!context.mounted) return;
        _showArchiveSnack(
          context,
          'OneDrive 备份已上传：${result.file.uri.pathSegments.last}',
        );
      } catch (e) {
        if (!context.mounted) return;
        _showArchiveSnack(context, 'OneDrive 备份失败：$e');
      }
    }

    Future<void> restoreFromOneDrive(String passphrase) async {
      if (kIsWeb) {
        _showArchiveSnack(context, '当前平台暂不支持 OneDrive 恢复');
        return;
      }
      try {
        final service = OneDriveBackupService();
        final entries = await service.listBackups(odConfig(passphrase));
        if (!context.mounted) return;
        if (entries.isEmpty) {
          _showArchiveSnack(context, '远端没有可恢复的备份');
          return;
        }
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('选择要恢复的备份'),
            children: [
              for (final entry in entries)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(entry.name),
                  child: Text(
                    '${entry.name} · ${(entry.size / 1024).toStringAsFixed(1)} KB',
                  ),
                ),
            ],
          ),
        );
        if (choice == null || !context.mounted) return;

        final root = await getApplicationDocumentsDirectory();
        final tmp = Directory(
          p.join((await getTemporaryDirectory()).path, 'onedrive_restore'),
        );
        final downloaded = await service.downloadBackup(
          name: choice,
          config: odConfig(passphrase),
          downloadDirectory: tmp,
        );
        final importResult = await DataImportService(
          rootDirectory: root,
          localDatabaseSnapshotService: LocalDatabaseSnapshotService(
            database: ref.read(databaseProvider),
            rootDirectory: root,
          ),
        ).importExport(downloaded, overwriteExisting: false);
        if (!context.mounted) return;
        _showArchiveSnack(context, '已恢复：${importResult.summary}');
      } catch (e) {
        if (!context.mounted) return;
        _showArchiveSnack(context, 'OneDrive 恢复失败：$e');
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('OneDrive 云盘备份'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Graph Access Token',
                    hintText: '需在应用内 OAuth 或另行获取',
                  ),
                ),
                TextField(
                  controller: folderCtrl,
                  decoration: const InputDecoration(labelText: '备份目录'),
                ),
                const SizedBox(height: 12),
                const Text(
                  '备份口令用于端到端加密，不会保存在本机；每次备份 / 恢复都需要输入，请务必牢记。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref
                    .read(oneDriveBackupSettingsProvider.notifier)
                    .save(
                      OneDriveBackupSettings(
                        accessToken: tokenCtrl.text,
                        folder: folderCtrl.text,
                      ),
                    );
                Navigator.of(ctx).pop();
              },
              child: const Text('保存配置'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final pass = await _askBackupPassphrase(ctx);
                      if (pass == null || !ctx.mounted) return;
                      setDialogState(() => busy = true);
                      await backupNow(pass);
                      if (!ctx.mounted) return;
                      setDialogState(() => busy = false);
                    },
              child: const Text('立即备份'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final pass = await _askBackupPassphrase(ctx);
                      if (pass == null || !ctx.mounted) return;
                      setDialogState(() => busy = true);
                      await restoreFromOneDrive(pass);
                      if (!ctx.mounted) return;
                      setDialogState(() => busy = false);
                    },
              child: const Text('从云端恢复'),
            ),
            if (current.isConfigured)
              TextButton(
                onPressed: () {
                  ref.read(oneDriveBackupSettingsProvider.notifier).clear();
                  Navigator.of(ctx).pop();
                },
                child: const Text('清除配置'),
              ),
          ],
        ),
      ),
    );
  }

  // ====== Notion 同步 ======

  Widget _buildNotionSyncTile(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notionSyncSettingsProvider);
    final subtitle = settings.isConfigured
        ? '已配置 · 可导出会话到 Notion'
        : '未配置 · 同步会话到 Notion 页面';
    return ListTile(
      leading: Icon(
        settings.isConfigured ? Icons.article_outlined : Icons.article,
        color: settings.isConfigured ? Colors.blue[700] : null,
      ),
      title: const Text('Notion 同步'),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showNotionSyncDialog(context, ref),
    );
  }

  void _showNotionSyncDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(notionSyncSettingsProvider);
    final tokenCtrl = TextEditingController(text: current.token);
    final parentCtrl = TextEditingController(text: current.parentPageId);
    var busy = false;

    Future<void> exportAllToNotion() async {
      if (kIsWeb) {
        _showArchiveSnack(context, '当前平台暂不支持 Notion 同步');
        return;
      }
      try {
        final root = await getApplicationDocumentsDirectory();
        final archive = MarkdownConversationArchive(rootDirectory: root);
        final sessions = await ref.read(sessionDaoProvider).getAllSessions();
        final service = const NotionSyncService();
        var exported = 0;
        for (final session in sessions) {
          final file = archive.conversationFile(session.id);
          if (!await file.exists()) continue;
          final content = await file.readAsString();
          if (content.trim().isEmpty) continue;
          await service.exportConversation(
            token: tokenCtrl.text,
            parentPageId: parentCtrl.text,
            title: session.title ?? 'SimiChat 会话',
            markdownContent: content,
          );
          exported++;
        }
        if (!context.mounted) return;
        _showArchiveSnack(
          context,
          exported == 0 ? '没有可导出的会话' : '已导出 $exported 个会话到 Notion',
        );
      } catch (e) {
        if (!context.mounted) return;
        _showArchiveSnack(context, 'Notion 同步失败：$e');
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Notion 同步'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Integration Token',
                    hintText: 'ntn_...',
                  ),
                ),
                TextField(
                  controller: parentCtrl,
                  decoration: const InputDecoration(
                    labelText: '父页面 ID 或 URL',
                    hintText:
                        'https://www.notion.so/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '在 Notion 集成页面创建 Integration 并连接目标页面后，把 Token 和父页面 ID 填到这里，即可把会话 Markdown 导出为 Notion 子页面。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref
                    .read(notionSyncSettingsProvider.notifier)
                    .save(
                      NotionSyncSettings(
                        token: tokenCtrl.text,
                        parentPageId: parentCtrl.text,
                      ),
                    );
                Navigator.of(ctx).pop();
              },
              child: const Text('保存配置'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() => busy = true);
                      await exportAllToNotion();
                      if (!ctx.mounted) return;
                      setDialogState(() => busy = false);
                    },
              child: const Text('导出全部会话'),
            ),
            if (current.isConfigured)
              TextButton(
                onPressed: () {
                  ref.read(notionSyncSettingsProvider.notifier).clear();
                  Navigator.of(ctx).pop();
                },
                child: const Text('清除配置'),
              ),
          ],
        ),
      ),
    );
  }

  // ====== 语雀 / 思源同步 ======

  /// 读取全部会话 Markdown 并调用 [exportOne]，返回成功导出数。
  Future<int> _exportAllSessionsToNoteSync(
    WidgetRef ref, {
    required Future<void> Function(String title, String markdown) exportOne,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final archive = MarkdownConversationArchive(rootDirectory: root);
    final sessions = await ref.read(sessionDaoProvider).getAllSessions();
    var exported = 0;
    for (final session in sessions) {
      final file = archive.conversationFile(session.id);
      if (!await file.exists()) continue;
      final content = await file.readAsString();
      if (content.trim().isEmpty) continue;
      await exportOne(session.title ?? 'SimiChat 会话', content);
      exported++;
    }
    return exported;
  }

  Widget _buildYuqueSyncTile(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(yuqueSyncProvider);
    return ListTile(
      leading: const Icon(Icons.book_outlined),
      title: const Text('语雀同步'),
      subtitle: Text(
        settings.isConfigured ? '已配置 · ${settings.namespace}' : '未配置 · 同步会话到语雀',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showYuqueSyncDialog(context, ref),
    );
  }

  void _showYuqueSyncDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(yuqueSyncProvider);
    final tokenCtrl = TextEditingController(text: current.token);
    final namespaceCtrl = TextEditingController(text: current.namespace);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('语雀同步'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: tokenCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '语雀 Token',
                  hintText: '个人令牌',
                ),
              ),
              TextField(
                controller: namespaceCtrl,
                decoration: const InputDecoration(
                  labelText: '仓库 namespace',
                  hintText: 'login/repo',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '在语雀「设置 → Token」创建令牌，并把仓库 namespace（如 username/repo）填入这里，即可把会话 Markdown 导出为语雀文档。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref
                  .read(yuqueSyncProvider.notifier)
                  .save(
                    YuqueSyncSettings(
                      token: tokenCtrl.text,
                      namespace: namespaceCtrl.text,
                    ),
                  );
              Navigator.of(ctx).pop();
            },
            child: const Text('保存配置'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final exported = await _exportAllSessionsToNoteSync(
                  ref,
                  exportOne: (title, markdown) =>
                      const YuqueSyncService().exportConversation(
                        token: tokenCtrl.text,
                        namespace: namespaceCtrl.text,
                        title: title,
                        markdownContent: markdown,
                      ),
                );
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        exported == 0 ? '没有可导出的会话' : '已导出 $exported 个会话到语雀',
                      ),
                    ),
                  );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(content: Text('语雀同步失败：$e')));
              }
            },
            child: const Text('导出全部会话'),
          ),
          if (current.isConfigured)
            TextButton(
              onPressed: () {
                ref.read(yuqueSyncProvider.notifier).clear();
                Navigator.of(ctx).pop();
              },
              child: const Text('清除配置'),
            ),
        ],
      ),
    );
  }

  Widget _buildSiyuanSyncTile(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(siyuanSyncProvider);
    return ListTile(
      leading: const Icon(Icons.edit_note),
      title: const Text('思源同步'),
      subtitle: Text(
        settings.isConfigured ? '已配置 · ${settings.baseUrl}' : '未配置 · 同步会话到思源笔记',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showSiyuanSyncDialog(context, ref),
    );
  }

  void _showSiyuanSyncDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(siyuanSyncProvider);
    final baseUrlCtrl = TextEditingController(text: current.baseUrl);
    final tokenCtrl = TextEditingController(text: current.token);
    final notebookCtrl = TextEditingController(text: current.notebook);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('思源同步'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: baseUrlCtrl,
                decoration: const InputDecoration(
                  labelText: '思源 API 地址',
                  hintText: 'http://127.0.0.1:6806',
                ),
              ),
              TextField(
                controller: tokenCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'API Token'),
              ),
              TextField(
                controller: notebookCtrl,
                decoration: const InputDecoration(labelText: '笔记本 ID'),
              ),
              const SizedBox(height: 12),
              const Text(
                '在思源「设置 → 关于 → API Token」获取令牌，填入笔记本 ID，即可把会话 Markdown 创建为思源文档。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref
                  .read(siyuanSyncProvider.notifier)
                  .save(
                    SiyuanSyncSettings(
                      baseUrl: baseUrlCtrl.text,
                      token: tokenCtrl.text,
                      notebook: notebookCtrl.text,
                    ),
                  );
              Navigator.of(ctx).pop();
            },
            child: const Text('保存配置'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final exported = await _exportAllSessionsToNoteSync(
                  ref,
                  exportOne: (title, markdown) =>
                      SiyuanSyncService(
                        apiBaseUrl: baseUrlCtrl.text,
                      ).exportConversation(
                        token: tokenCtrl.text,
                        notebook: notebookCtrl.text,
                        title: title,
                        markdownContent: markdown,
                      ),
                );
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        exported == 0 ? '没有可导出的会话' : '已导出 $exported 个会话到思源',
                      ),
                    ),
                  );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(content: Text('思源同步失败：$e')));
              }
            },
            child: const Text('导出全部会话'),
          ),
          if (current.isConfigured)
            TextButton(
              onPressed: () {
                ref.read(siyuanSyncProvider.notifier).clear();
                Navigator.of(ctx).pop();
              },
              child: const Text('清除配置'),
            ),
        ],
      ),
    );
  }

  Widget _buildDiscordBotTile(BuildContext context, WidgetRef ref) {
    final state = ref.watch(discordBotProvider);
    final subtitle = state.running
        ? '运行中${state.botUsername != null ? ' · ${state.botUsername}' : ''}'
        : state.lastError != null
        ? '上次错误：${state.lastError}'
        : '未启动 · 配置 Bot Token 后可在 Discord 中与 AI 对话';
    return ListTile(
      leading: Icon(
        state.running ? Icons.chat_bubble : Icons.chat_bubble_outline,
        color: state.running ? Colors.indigo[700] : null,
      ),
      title: const Text('Discord Bot'),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showDiscordBotDialog(context, ref),
    );
  }

  void _showDiscordBotDialog(BuildContext context, WidgetRef ref) {
    final state = ref.read(discordBotProvider);
    final tokenCtrl = TextEditingController();
    var busy = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Discord Bot 社交通道'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Bot Token',
                    hintText: 'Bot token from Discord Developer Portal',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '在 Discord Developer Portal 创建应用并添加 Bot 后填入 Token。启动后 Bot 通过 Gateway 接收消息，用当前默认聊天模型回复。',
                  style: TextStyle(fontSize: 12),
                ),
                if (state.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '上次错误：${state.lastError}',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await ref
                    .read(discordBotProvider.notifier)
                    .saveToken(tokenCtrl.text);
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
              },
              child: const Text('保存 Token'),
            ),
            if (!state.running)
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setDialogState(() => busy = true);
                        final token = tokenCtrl.text.trim();
                        if (token.isNotEmpty) {
                          await ref
                              .read(discordBotProvider.notifier)
                              .saveToken(token);
                        }
                        final error = await ref
                            .read(discordBotProvider.notifier)
                            .start();
                        if (!ctx.mounted) return;
                        setDialogState(() => busy = false);
                        if (error != null) {
                          ScaffoldMessenger.of(ctx)
                            ..clearSnackBars()
                            ..showSnackBar(SnackBar(content: Text(error)));
                        } else {
                          Navigator.of(ctx).pop();
                        }
                      },
                child: const Text('启动 Bot'),
              )
            else
              TextButton(
                onPressed: () async {
                  await ref.read(discordBotProvider.notifier).stop();
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                },
                child: const Text('停止 Bot'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeishuBotTile(BuildContext context, WidgetRef ref) {
    final state = ref.watch(feishuBotProvider);
    final subtitle = state.running
        ? '运行中 · 回调地址 ${state.webhookBase}/feishu/webhook'
        : state.lastError != null
        ? '上次错误：${state.lastError}'
        : '未启动 · 配置 App ID / Secret 后接收飞书消息';
    return ListTile(
      leading: Icon(
        state.running ? Icons.forward_to_inbox : Icons.outbox_outlined,
        color: state.running ? Colors.teal[700] : null,
      ),
      title: const Text('飞书 Bot'),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showFeishuBotDialog(context, ref),
    );
  }

  void _showFeishuBotDialog(BuildContext context, WidgetRef ref) {
    final state = ref.read(feishuBotProvider);
    final appIdCtrl = TextEditingController();
    final secretCtrl = TextEditingController();
    var busy = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('飞书 Bot 社交通道'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: appIdCtrl,
                  decoration: const InputDecoration(labelText: 'App ID'),
                ),
                TextField(
                  controller: secretCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'App Secret'),
                ),
                const SizedBox(height: 12),
                const Text(
                  '在飞书开放平台创建企业自建应用并启用「机器人」后，填入 App ID / Secret。启动后应用在本机开一个 webhook 收件箱，请把事件回调 URL 配置为下方地址的公网隧道，即可在飞书中与 AI 对话。',
                  style: TextStyle(fontSize: 12),
                ),
                if (state.running)
                  Text(
                    '回调地址：${state.webhookBase}/feishu/webhook',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                  ),
                if (state.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '上次错误：${state.lastError}',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await ref
                    .read(feishuBotProvider.notifier)
                    .saveCredentials(appIdCtrl.text, secretCtrl.text);
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
              },
              child: const Text('保存配置'),
            ),
            if (!state.running)
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setDialogState(() => busy = true);
                        if (appIdCtrl.text.trim().isNotEmpty ||
                            secretCtrl.text.trim().isNotEmpty) {
                          await ref
                              .read(feishuBotProvider.notifier)
                              .saveCredentials(appIdCtrl.text, secretCtrl.text);
                        }
                        final error = await ref
                            .read(feishuBotProvider.notifier)
                            .start();
                        if (!ctx.mounted) return;
                        setDialogState(() => busy = false);
                        if (error != null) {
                          ScaffoldMessenger.of(ctx)
                            ..clearSnackBars()
                            ..showSnackBar(SnackBar(content: Text(error)));
                        } else {
                          Navigator.of(ctx).pop();
                        }
                      },
                child: const Text('启动 Bot'),
              )
            else
              TextButton(
                onPressed: () async {
                  await ref.read(feishuBotProvider.notifier).stop();
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                },
                child: const Text('停止 Bot'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebhookChannelTile(BuildContext context, WidgetRef ref) {
    final state = ref.watch(webhookBotProvider);
    final label = state.kind?.label ?? '未选择';
    final subtitle = state.running
        ? '运行中 · $label · 回调 ${state.webhookBase}/webhook'
        : state.lastError != null
        ? '上次错误：${state.lastError}'
        : 'WhatsApp / Slack / 微信公众号 / QQ 一键接入';
    return ListTile(
      leading: Icon(
        state.running ? Icons.hub : Icons.hub_outlined,
        color: state.running ? Colors.purple[700] : null,
      ),
      title: const Text('Webhook 社交通道'),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showWebhookChannelDialog(context, ref),
    );
  }

  void _showWebhookChannelDialog(BuildContext context, WidgetRef ref) {
    final state = ref.read(webhookBotProvider);
    final config = ref.read(webhookBotProvider.notifier);
    var kind = WebhookChannelKind.whatsapp;
    final tokenCtrl = TextEditingController();
    final secondaryCtrl = TextEditingController();
    var busy = false;

    Future<void> runStart(StateSetter setDialogState) async {
      setDialogState(() => busy = true);
      await config.saveConfig(
        WebhookChannelConfig(
          kind: kind,
          token: tokenCtrl.text,
          secondary: secondaryCtrl.text,
        ),
      );
      final error = await config.start();
      if (!context.mounted) return;
      setDialogState(() => busy = false);
      if (error != null) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(error)));
      } else {
        Navigator.of(context).pop();
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Webhook 社交通道'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<WebhookChannelKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: '平台'),
                  items: [
                    for (final k in WebhookChannelKind.values)
                      DropdownMenuItem(value: k, child: Text(k.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) kind = v;
                  },
                ),
                TextField(
                  controller: tokenCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: kind == WebhookChannelKind.wechatMp
                        ? 'AppID'
                        : kind == WebhookChannelKind.whatsapp
                        ? 'Access Token'
                        : 'Bot Token',
                  ),
                ),
                if (kind == WebhookChannelKind.wechatMp ||
                    kind == WebhookChannelKind.whatsapp)
                  TextField(
                    controller: secondaryCtrl,
                    obscureText: kind == WebhookChannelKind.wechatMp,
                    decoration: InputDecoration(
                      labelText: kind == WebhookChannelKind.wechatMp
                          ? 'AppSecret'
                          : 'Phone Number ID',
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  '在对应开放平台创建应用并启用 Bot 后填入凭据。启动后应用在本机开 webhook 收件箱，请把平台事件回调 URL 配置为该地址的公网隧道。',
                  style: TextStyle(fontSize: 12),
                ),
                if (state.running)
                  Text(
                    '回调地址：${state.webhookBase}/webhook',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                  ),
                if (state.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '上次错误：${state.lastError}',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await config.saveConfig(
                  WebhookChannelConfig(
                    kind: kind,
                    token: tokenCtrl.text,
                    secondary: secondaryCtrl.text,
                  ),
                );
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
              },
              child: const Text('保存配置'),
            ),
            if (!state.running)
              FilledButton(
                onPressed: busy ? null : () => runStart(setState),
                child: const Text('启动 Bot'),
              )
            else
              TextButton(
                onPressed: () async {
                  await config.stop();
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                },
                child: const Text('停止 Bot'),
              ),
          ],
        ),
      ),
    );
  }

  // ====== WebDAV 云备份 ======

  Widget _buildWebDavBackupTile(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(webDavBackupSettingsProvider);
    final subtitle = settings.isConfigured
        ? '已配置 ${settings.baseUrl}'
        : '未配置 · 导出包加密上传到 WebDAV 并可恢复';
    return ListTile(
      leading: Icon(
        settings.isConfigured
            ? Icons.cloud_done_outlined
            : Icons.cloud_outlined,
        color: settings.isConfigured ? Colors.green[700] : null,
      ),
      title: const Text('云备份 (WebDAV)'),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showWebDavBackupDialog(context, ref),
    );
  }

  void _showWebDavBackupDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(webDavBackupSettingsProvider);
    final baseUrlCtrl = TextEditingController(text: current.baseUrl);
    final usernameCtrl = TextEditingController(text: current.username);
    final passwordCtrl = TextEditingController(text: current.password);
    var isBusy = false;

    Future<void> backupNow(String passphrase) async {
      if (kIsWeb) {
        _showArchiveSnack(context, '当前平台暂不支持云备份');
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
        ).exportLocalData(includeAudioFiles: true);

        await const WebDavBackupService().uploadBackup(
          exportFile: result.file,
          config: WebDavBackupConfig(
            baseUrl: baseUrlCtrl.text,
            username: usernameCtrl.text,
            password: passwordCtrl.text,
            passphrase: passphrase,
          ),
        );
        if (!context.mounted) return;
        _showArchiveSnack(
          context,
          '云备份已上传：${result.file.uri.pathSegments.last}',
        );
      } catch (e) {
        if (!context.mounted) return;
        _showArchiveSnack(context, '云备份失败：$e');
      }
    }

    Future<void> restoreFromServer(String passphrase) async {
      if (kIsWeb) {
        _showArchiveSnack(context, '当前平台暂不支持云恢复');
        return;
      }
      try {
        final service = const WebDavBackupService();
        final entries = await service.listBackups(
          WebDavBackupConfig(
            baseUrl: baseUrlCtrl.text,
            username: usernameCtrl.text,
            password: passwordCtrl.text,
            passphrase: passphrase,
          ),
        );
        if (!context.mounted) return;
        if (entries.isEmpty) {
          _showArchiveSnack(context, '远端没有可恢复的备份');
          return;
        }
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('选择要恢复的备份'),
            children: [
              for (final entry in entries)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(entry.name),
                  child: Text(
                    '${entry.name} · ${(entry.size / 1024).toStringAsFixed(1)} KB',
                  ),
                ),
            ],
          ),
        );
        if (choice == null || !context.mounted) return;

        final root = await getApplicationDocumentsDirectory();
        final tmp = Directory(
          p.join((await getTemporaryDirectory()).path, 'webdav_restore'),
        );
        final downloaded = await service.downloadBackup(
          name: choice,
          config: WebDavBackupConfig(
            baseUrl: baseUrlCtrl.text,
            username: usernameCtrl.text,
            password: passwordCtrl.text,
            passphrase: passphrase,
          ),
          downloadDirectory: tmp,
        );
        final importResult = await DataImportService(
          rootDirectory: root,
          localDatabaseSnapshotService: LocalDatabaseSnapshotService(
            database: ref.read(databaseProvider),
            rootDirectory: root,
          ),
        ).importExport(downloaded, overwriteExisting: false);
        if (!context.mounted) return;
        _showArchiveSnack(context, '已恢复：${importResult.summary}');
      } catch (e) {
        if (!context.mounted) return;
        _showArchiveSnack(context, '云恢复失败：$e');
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('云备份 (WebDAV)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: baseUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'WebDAV 地址',
                    hintText: 'https://dav.example.com/backup/simichat/',
                  ),
                ),
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                ),
                const SizedBox(height: 12),
                const Text(
                  '备份口令用于端到端加密，不会保存在本机；每次备份 / 恢复都需要输入，请务必牢记。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref
                    .read(webDavBackupSettingsProvider.notifier)
                    .save(
                      WebDavBackupSettings(
                        baseUrl: baseUrlCtrl.text,
                        username: usernameCtrl.text,
                        password: passwordCtrl.text,
                      ),
                    );
                Navigator.of(ctx).pop();
              },
              child: const Text('保存配置'),
            ),
            FilledButton(
              onPressed: isBusy
                  ? null
                  : () async {
                      final passCtrl = TextEditingController();
                      final pass = await showDialog<String>(
                        context: context,
                        builder: (pctx) => AlertDialog(
                          title: const Text('输入备份口令'),
                          content: TextField(
                            controller: passCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              hintText: '至少 8 位',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(pctx).pop(),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(pctx).pop(passCtrl.text.trim()),
                              child: const Text('开始备份'),
                            ),
                          ],
                        ),
                      );
                      if (pass == null || pass.isEmpty || !ctx.mounted) return;
                      setDialogState(() => isBusy = true);
                      await backupNow(pass);
                      if (!ctx.mounted) return;
                      setDialogState(() => isBusy = false);
                    },
              child: const Text('立即备份'),
            ),
            TextButton(
              onPressed: isBusy
                  ? null
                  : () async {
                      final passCtrl = TextEditingController();
                      final pass = await showDialog<String>(
                        context: context,
                        builder: (pctx) => AlertDialog(
                          title: const Text('输入备份口令'),
                          content: TextField(
                            controller: passCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              hintText: '至少 8 位',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(pctx).pop(),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(pctx).pop(passCtrl.text.trim()),
                              child: const Text('从云端恢复'),
                            ),
                          ],
                        ),
                      );
                      if (pass == null || pass.isEmpty || !ctx.mounted) return;
                      setDialogState(() => isBusy = true);
                      await restoreFromServer(pass);
                      if (!ctx.mounted) return;
                      setDialogState(() => isBusy = false);
                    },
              child: const Text('从云端恢复'),
            ),
            if (current.isConfigured)
              TextButton(
                onPressed: () {
                  ref.read(webDavBackupSettingsProvider.notifier).clear();
                  Navigator.of(ctx).pop();
                },
                child: const Text('清除配置'),
              ),
          ],
        ),
      ),
    );
  }

  /// 关于区：鸣谢为应用提供模型接入能力的中转站。
  Widget _buildCreditsTile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: scheme.surface,
        backgroundImage: const AssetImage('assets/branding/simirouter.png'),
      ),
      title: const Text('鸣谢 · SimiRouter AI 中转站'),
      subtitle: const Text('为本应用提供 OpenAI 兼容模型接入服务 · 点击查看官网'),
      trailing: const Icon(Icons.open_in_new),
      onTap: () =>
          _openInAppH5(context, url: kSimiRouterHomeUrl, title: '访问官网'),
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
    final channelLogoAsset = getChannelLogoAsset(
      channel.protocol,
      channel.baseUrl,
    );
    return ExpansionTile(
      leading: channelLogoAsset != null
          ? CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              backgroundImage: AssetImage(channelLogoAsset),
            )
          : Icon(getChannelIcon(channel.protocol, channel.baseUrl)),
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
                      onTap: () => _showAddModelDialog(context, ref, channel),
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
    final exampleJson = const JsonEncoder.withIndent('  ').convert({
      'channels': [
        {
          'presetId': 'groq',
          'apiKey': '在这里粘贴自己的 Groq Key',
          'models': [
            {'name': 'llama-3.1-8b-instant', 'capability': 'chat'},
          ],
        },
      ],
    });
    final importCtrl = TextEditingController(text: exampleJson);

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
                          '支持渠道对象、数组或 {"channels": [...]}；可用 presetId/provider 自动补名称、Base URL 和协议；单模型可用 model/modelName',
                    ),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (!ctx.mounted) return;
                        final text = data?.text ?? '';
                        if (text.trim().isEmpty) {
                          if (context.mounted) {
                            _showArchiveSnack(context, '剪贴板没有可粘贴的 JSON');
                          }
                          return;
                        }
                        importCtrl.text = text;
                        importCtrl.selection = TextSelection.collapsed(
                          offset: importCtrl.text.length,
                        );
                        if (context.mounted) {
                          _showArchiveSnack(context, '已从剪贴板粘贴 JSON');
                        }
                      },
                      child: const Text('粘贴剪贴板'),
                    ),
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: exampleJson));
                        _showArchiveSnack(context, '示例 JSON 已复制');
                      },
                      child: const Text('复制示例 JSON'),
                    ),
                    TextButton(
                      onPressed: () {
                        importCtrl.text = exampleJson;
                        importCtrl.selection = TextSelection.collapsed(
                          offset: importCtrl.text.length,
                        );
                        _showArchiveSnack(context, '已恢复示例 JSON');
                      },
                      child: const Text('恢复示例'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
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
          capabilities: model.capabilities,
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
    String? initialPresetId,
  }) {
    final nameCtrl = TextEditingController(text: channel?.name ?? '');
    final urlCtrl = TextEditingController(text: channel?.baseUrl ?? '');
    final keyCtrl = TextEditingController();
    String protocol = channel?.protocol ?? 'openai_chat';
    String? selectedPresetId;
    bool obscureKey = true;

    // 支持一键接入：预选厂商预设并自动填充名称 / Base URL / 协议。
    if (channel == null && initialPresetId != null) {
      final preset = findModelProviderPreset(initialPresetId);
      if (preset != null) {
        selectedPresetId = preset.id;
        nameCtrl.text = preset.name;
        urlCtrl.text = preset.baseUrl;
        protocol = preset.protocol;
      }
    } else if (channel != null) {
      // 编辑内置渠道时同样锁定为预设配置，只留 API Key 可改。
      selectedPresetId = findModelProviderPresetByBaseUrl(
        channel.protocol,
        channel.baseUrl,
      )?.id;
    }

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
                    DropdownButtonFormField<String>(
                      initialValue: selectedPresetId,
                      decoration: InputDecoration(
                        labelText: '厂商预设',
                        helperText: selectedPresetId != null
                            ? '内置渠道只需填写 API Key，名称 / Base URL / 协议已自动配置'
                            : '选择预设后可一键接入；也可改为自定义渠道',
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('自定义渠道')),
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
                        onOpenSignUp: () {
                          final selected = findModelProviderPreset(
                            selectedPresetId!,
                          );
                          if (selected?.signUpUrl == null) return;
                          _openInAppH5(
                            context,
                            url: selected!.signUpUrl!,
                            title: '获取 Key',
                          );
                        },
                        onOpenDocs: () {
                          final selected = findModelProviderPreset(
                            selectedPresetId!,
                          );
                          if (selected == null) return;
                          _openInAppH5(
                            context,
                            url: selected.docsUrl,
                            title: '访问官网',
                          );
                        },
                      ),
                    if (selectedPresetId != null) const SizedBox(height: 12),
                    // 内置预设：名称 / Base URL / 协议由预设锁定，只留 API Key。
                    if (selectedPresetId == null) ...[
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
                    ],
                    TextField(
                      controller: keyCtrl,
                      obscureText: obscureKey,
                      decoration: InputDecoration(
                        labelText: modelProtocolRequiresApiKey(protocol)
                            ? 'API Key'
                            : 'API Key（可选）',
                        hintText: modelProtocolRequiresApiKey(protocol)
                            ? (channel != null ? '留空则不修改' : '请输入 API Key')
                            : '本地 Ollama 通常留空；仅反向代理鉴权时填写',
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
                    if (selectedPresetId == null)
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
                            // 内置预设锁定时名称 / Base URL / 协议以预设为准。
                            final lockedPreset = selectedPresetId == null
                                ? null
                                : findModelProviderPreset(selectedPresetId!);
                            final name =
                                lockedPreset?.name ?? nameCtrl.text.trim();
                            final baseUrl = normalizeUrl(
                              lockedPreset?.baseUrl ?? urlCtrl.text,
                            );
                            final saveProtocol =
                                lockedPreset?.protocol ?? protocol;
                            final apiKey = keyCtrl.text.trim();
                            final encryptedKey = KeyEncryptor.encrypt(apiKey);
                            final isNew = channel == null;
                            final channelId = channel?.id ?? const Uuid().v4();
                            final requiresApiKey = modelProtocolRequiresApiKey(
                              saveProtocol,
                            );

                            if (name.isEmpty ||
                                baseUrl.isEmpty ||
                                (isNew && requiresApiKey && apiKey.isEmpty)) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      lockedPreset != null
                                          ? '请填写 API Key'
                                          : (requiresApiKey
                                                ? '请完整填写渠道名称、Base URL 和 API Key'
                                                : '请完整填写渠道名称和 Base URL'),
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
                                protocol: saveProtocol,
                              );
                            } else {
                              await channelDao.updateChannel(
                                channel.id,
                                name: name,
                                baseUrl: baseUrl,
                                apiKeyEncrypted: apiKey.isNotEmpty
                                    ? encryptedKey
                                    : null,
                                protocol: saveProtocol,
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
                                    protocol: saveProtocol,
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
    ModelChannel channel,
  ) {
    final modelCtrl = TextEditingController();
    final recommendedModels =
        findModelProviderPresetByBaseUrl(
          channel.protocol,
          channel.baseUrl,
        )?.recommendedModels ??
        const [];
    var capability = ModelCapability.chat;
    var capabilityTouched = false;
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
                onChanged: (v) {
                  if (!capabilityTouched) {
                    setDialogState(
                      () => capability = ModelCapability.inferFromModel(v),
                    );
                  }
                },
              ),
              if (recommendedModels.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '预设推荐模型',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final modelName in recommendedModels)
                        ActionChip(
                          label: Text(modelName),
                          onPressed: () {
                            setDialogState(() {
                              modelCtrl.text = modelName;
                              modelCtrl.selection = TextSelection.collapsed(
                                offset: modelName.length,
                              );
                              if (!capabilityTouched) {
                                capability = ModelCapability.inferFromModel(
                                  modelName,
                                );
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: capability,
                decoration: const InputDecoration(
                  labelText: '模型能力',
                  helperText:
                      '图片输入请选择 Vision；生成图片 / 语音 / 视频 / 音乐 / 重排请选择对应能力，Relay 会据此路由',
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
                  DropdownMenuItem(
                    value: ModelCapability.rerank,
                    child: Text('Rerank 重排'),
                  ),
                  DropdownMenuItem(
                    value: ModelCapability.reasoner,
                    child: Text('Reasoner 推理'),
                  ),
                  DropdownMenuItem(
                    value: ModelCapability.image,
                    child: Text('Image 图片生成'),
                  ),
                  DropdownMenuItem(
                    value: ModelCapability.audio,
                    child: Text('Audio 语音'),
                  ),
                  DropdownMenuItem(
                    value: ModelCapability.video,
                    child: Text('Video 视频生成'),
                  ),
                  DropdownMenuItem(
                    value: ModelCapability.music,
                    child: Text('Music 音乐生成'),
                  ),
                ],
                onChanged: (v) => setDialogState(() {
                  capabilityTouched = true;
                  capability = v!;
                }),
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
                        channelId: channel.id,
                        modelName: modelCtrl.text.trim(),
                        capability: capability,
                      );
                  refreshChannelModels(ref, channel.id);
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
      final apiKey = KeyEncryptor.decryptOrEmpty(channel.apiKeyEncrypted);
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
        _showFetchResultDialog(
          context,
          ref,
          channel.id,
          newModels,
          preferredModel: channel.protocol == 'ollama' ? 'gemma4' : null,
        );
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
    List<FetchedModel> models, {
    String? preferredModel,
  }) {
    final selected = ModelFetcher.defaultSelectedModelIds(
      models,
      preferredModel: preferredModel,
    );

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
                    capabilities: model?.capabilities ?? const <String>{},
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
      final apiKey = KeyEncryptor.decryptOrEmpty(channel.apiKeyEncrypted);
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
      final apiKey = KeyEncryptor.decryptOrEmpty(channel.apiKeyEncrypted);

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
    var language = config.language;
    final languageController = TextEditingController(text: language);
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
                Text(
                  selectedPresetId == kXaiSpeechProviderId
                      ? '厂商：xAI / Grok Voice REST'
                      : '厂商：OpenAI 兼容 STT',
                ),
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
                            modelController.text = preset.sttModel ?? '';
                          });
                        },
                ),
                const SizedBox(height: 6),
                Text(
                  findSpeechProviderPreset(selectedPresetId)?.description ??
                      '选择预设后会自动填充 Base URL 与协议参数，API Key 仍只保存在本机。',
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
                if (selectedPresetId == kXaiSpeechProviderId)
                  const Text(
                    '模型字段不是 xAI Voice REST 的请求参数；/v1/stt 不使用模型字段，当前页面不会把聊天模型名伪装成 STT 模型。',
                  )
                else
                  TextField(
                    controller: modelController,
                    enabled: !isSaving,
                    // 模型名决定是否显示识别语言下拉，输入后需重建。
                    onChanged: isSaving ? null : (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: '模型',
                      hintText: 'whisper-1',
                    ),
                  ),
                if (selectedPresetId == kXaiSpeechProviderId)
                  TextField(
                    controller: languageController,
                    enabled: !isSaving,
                    onChanged: (value) => language = value,
                    decoration: const InputDecoration(
                      labelText: '语言（xAI BCP-47 / auto）',
                      helperText:
                          '公开 batch STT 默认不发送 language；保存后按 profile 兼容边界处理。',
                    ),
                  )
                // mimo-v2.5-asr：识别语言选择。
                else if (isSimiRouterAsrModel(modelController.text)) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: language,
                    decoration: const InputDecoration(
                      labelText: '识别语言',
                      helperText: '自动 / 中文 / 英文',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('自动检测')),
                      DropdownMenuItem(value: 'zh', child: Text('中文')),
                      DropdownMenuItem(value: 'en', child: Text('英文')),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) => setState(() => language = value ?? 'auto'),
                  ),
                ],
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
                        final notifier = ref.read(
                          speechToTextConfigProvider.notifier,
                        );
                        if (selectedPresetId == kXaiSpeechProviderId) {
                          await notifier.saveXai(
                            enabled: enabled,
                            baseUrl: baseUrlController.text,
                            apiKey: apiKeyController.text,
                            language: language,
                          );
                        } else {
                          await notifier.saveOpenAiCompatible(
                            enabled: enabled,
                            baseUrl: baseUrlController.text,
                            model: modelController.text,
                            apiKey: apiKeyController.text,
                            language: language,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('STT 配置已保存')),
                          );
                        }
                      } catch (error) {
                        setState(() {
                          isSaving = false;
                          errorText = _safeTtsDialogError(
                            error,
                            customVoice:
                                selectedPresetId == kXaiSpeechProviderId,
                          );
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
      languageController.dispose();
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

  // ====== 数字孪生 / 镜像数字人 v1 ======

  Widget _buildDigitalTwinTile(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final hasProfile = profile?.hasContent == true;
    return ListTile(
      leading: const Icon(Icons.face_retouching_natural),
      title: const Text('数字孪生 / 镜像数字人'),
      subtitle: Text(
        hasProfile ? '已根据画像生成人格配置 · 可预览' : '先完善用户画像后可生成镜像人格',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showDigitalTwinDialog(context, ref, profile),
    );
  }

  void _showDigitalTwinDialog(
    BuildContext context,
    WidgetRef ref,
    UserProfile? profile,
  ) {
    final persona = const PersonaProfileGenerator().fromUserProfile(
      profile ?? UserProfile.empty(),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('数字孪生 / 镜像数字人'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '镜像数字人 v1：把本地用户画像（风格 / 作息 / 偏好 / 目标 / 任务）蒸馏成可注入的人格配置，'
                '用于「替身回复」。替身回复必须由用户显式授权，且全程保留审计。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Text(
                '人格配置预览',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  persona.isEmpty
                      ? '画像信号不足，暂无可生成的人格配置。'
                      : persona.buildPersonaSystemPrompt(),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 24),
              // 替身回复授权开关。
              Consumer(
                builder: (ctx, ref, _) {
                  final auth = ref.watch(personaAuthorizationProvider);
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用替身回复'),
                    subtitle: Text(
                      auth.isAuthorized
                          ? '已授权${auth.authorizedAtIso != null ? ' · ${auth.authorizedAtIso!.substring(0, 10)}' : ''}'
                          : '代表用户本人以镜像人格发言，须显式授权',
                    ),
                    value: auth.isAuthorized,
                    onChanged: (value) async {
                      if (value) {
                        final confirmed = await showDialog<bool>(
                          context: ctx,
                          builder: (pctx) => AlertDialog(
                            title: const Text('授权替身回复'),
                            content: const Text(
                              '启用后，AI 将以你的口吻代表你发言。请确认你清楚这一行为并愿意授权。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(pctx).pop(false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(pctx).pop(true),
                                child: const Text('确认授权'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && ctx.mounted) {
                          await ref
                              .read(personaAuthorizationProvider.notifier)
                              .authorize();
                          try {
                            await ref
                                .read(personaAuditLogDaoProvider)
                                .insertLog(
                                  eventType: PersonaAuditEventType.authorize,
                                  summary: '用户显式授权替身回复',
                                );
                          } catch (_) {}
                        }
                      } else {
                        await ref
                            .read(personaAuthorizationProvider.notifier)
                            .revoke();
                        try {
                          await ref
                              .read(personaAuditLogDaoProvider)
                              .insertLog(
                                eventType: PersonaAuditEventType.revoke,
                                summary: '用户撤销替身回复授权',
                              );
                        } catch (_) {}
                      }
                    },
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final logs = await ref
                  .read(personaAuditLogDaoProvider)
                  .getRecentLogs(limit: 100);
              if (!ctx.mounted) return;
              await showDialog<void>(
                context: ctx,
                builder: (dctx) => AlertDialog(
                  title: const Text('替身审计日志'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: logs.isEmpty
                        ? const Text('暂无审计记录')
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final log in logs)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.policy_outlined,
                                    size: 18,
                                  ),
                                  title: Text(_auditEventLabel(log.eventType)),
                                  subtitle: Text(
                                    '${_formatAuditTime(log.createdAt)}${log.summary.isEmpty ? '' : ' · ${log.summary}'}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await ref.read(personaAuditLogDaoProvider).clearLogs();
                        if (!dctx.mounted) return;
                        Navigator.of(dctx).pop();
                      },
                      child: const Text('清空日志'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dctx).pop(),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('审计日志'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _auditEventLabel(String eventType) {
    switch (eventType) {
      case PersonaAuditEventType.authorize:
        return '授权替身回复';
      case PersonaAuditEventType.revoke:
        return '撤销替身回复';
      case PersonaAuditEventType.personaReply:
        return '替身回复';
      default:
        return eventType;
    }
  }

  String _formatAuditTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // ====== 数字人直播 v1 ======

  Widget _buildLiveStreamTile(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final hasProfile = profile?.hasContent == true;
    return ListTile(
      leading: const Icon(Icons.live_tv_outlined),
      title: const Text('数字人直播'),
      subtitle: Text(
        hasProfile ? '从镜像人格生成直播脚本 · 可配置 RTMP 目标' : '先完善用户画像后可生成直播脚本',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showLiveStreamDialog(context, ref, profile),
    );
  }

  void _showLiveStreamDialog(
    BuildContext context,
    WidgetRef ref,
    UserProfile? profile,
  ) {
    final platformCtrl = TextEditingController();
    final rtmpCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final topicCtrl = TextEditingController();
    String? scriptPreview;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('数字人直播'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: platformCtrl,
                  decoration: const InputDecoration(
                    labelText: '平台',
                    hintText: '如 YouTube / 抖音 / Twitch',
                  ),
                ),
                TextField(
                  controller: rtmpCtrl,
                  decoration: const InputDecoration(
                    labelText: 'RTMP 推流地址',
                    hintText: 'rtmp://a.rtmp.youtube.com/live2',
                  ),
                ),
                TextField(
                  controller: keyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '串流密钥'),
                ),
                TextField(
                  controller: topicCtrl,
                  decoration: const InputDecoration(labelText: '本次直播主题（可选）'),
                ),
                const SizedBox(height: 12),
                const Text(
                  '从镜像人格生成直播脚本（开场 / 话题 / 结束）。实际推流请在 OBS 等工具中指向上述 RTMP 地址。',
                  style: TextStyle(fontSize: 12),
                ),
                if (scriptPreview != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      scriptPreview!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                final persona = const PersonaProfileGenerator().fromUserProfile(
                  profile ?? UserProfile.empty(),
                );
                if (persona.isEmpty) {
                  ScaffoldMessenger.of(ctx)
                    ..clearSnackBars()
                    ..showSnackBar(
                      const SnackBar(content: Text('画像信号不足，暂无可生成直播脚本')),
                    );
                  return;
                }
                final script = const LiveStreamScriptGenerator().generate(
                  persona,
                  topic: topicCtrl.text,
                );
                setState(() => scriptPreview = script.toMarkdown());
              },
              child: const Text('生成直播脚本'),
            ),
            FilledButton(
              onPressed: () {
                final persona = const PersonaProfileGenerator().fromUserProfile(
                  profile ?? UserProfile.empty(),
                );
                try {
                  const service = LiveStreamService();
                  final config = LiveStreamConfig(
                    platform: platformCtrl.text,
                    rtmpUrl: rtmpCtrl.text,
                    streamKey: keyCtrl.text,
                  );
                  final session = service.startSession(
                    config: config,
                    persona: persona,
                    topic: topicCtrl.text,
                  );
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          '已记录开播会话：${session.platform} · ${session.topic}',
                        ),
                      ),
                    );
                  Navigator.of(ctx).pop();
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx)
                    ..clearSnackBars()
                    ..showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const Text('记录开播会话'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  // ====== 图片生成 ======

  Widget _buildUniversalMediaTile(BuildContext context, WidgetRef ref) {
    final config = ref.watch(universalMediaConfigProvider);
    final videoProfile = config.videoProfile;
    final musicProfile = config.musicProfile;
    return ListTile(
      leading: const Icon(Icons.perm_media_outlined),
      title: const Text('视频 / 音乐 / 通用媒体接口'),
      subtitle: Text(
        '视频：${videoProfile.name} · ${config.videoModel}\n音乐：${musicProfile.name} · ${config.musicModel}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(_showUniversalMediaDialog(context, ref)),
    );
  }

  Future<void> _showUniversalMediaDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(universalMediaConfigProvider.notifier).ready;
    if (!context.mounted) return;
    final config = ref.read(universalMediaConfigProvider);
    var selectedVideoProfileId = config.videoProfile.id;
    var selectedMusicProfileId = config.musicProfile.id;
    var selectedVideoChannelModelId = config.videoChannelModelId;
    var selectedMusicChannelModelId = config.musicChannelModelId;
    var videoModelSelectionManual = false;
    var musicModelSelectionManual = false;
    var videoProtocol = config.videoTaskOptions.protocol;
    var videoRequestFormat = config.videoTaskOptions.requestFormat;
    var musicProtocol = config.musicTaskOptions.protocol;
    var musicRequestFormat = config.musicTaskOptions.requestFormat;
    final videoModelController = TextEditingController(text: config.videoModel);
    final videoEndpointController = TextEditingController(
      text: config.videoEndpoint,
    );
    final musicModelController = TextEditingController(text: config.musicModel);
    final musicEndpointController = TextEditingController(
      text: config.musicEndpoint,
    );
    final videoReferenceFieldController = TextEditingController(
      text: config.videoTaskOptions.referenceField ?? '',
    );
    final videoPollUrlController = TextEditingController(
      text: config.videoTaskOptions.pollUrlTemplate ?? '',
    );
    final videoContentUrlController = TextEditingController(
      text: config.videoTaskOptions.contentUrlTemplate ?? '',
    );
    final videoCancelUrlController = TextEditingController(
      text: config.videoTaskOptions.cancelUrlTemplate ?? '',
    );
    final musicPollUrlController = TextEditingController(
      text: config.musicTaskOptions.pollUrlTemplate ?? '',
    );
    final musicContentUrlController = TextEditingController(
      text: config.musicTaskOptions.contentUrlTemplate ?? '',
    );
    final musicCancelUrlController = TextEditingController(
      text: config.musicTaskOptions.cancelUrlTemplate ?? '',
    );
    var saving = false;
    String? errorText;

    String? optionalText(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    UniversalMediaTaskOptions buildVideoTaskOptions() {
      return UniversalMediaTaskOptions(
        protocol: videoProtocol,
        requestFormat: videoRequestFormat,
        referenceField: optionalText(videoReferenceFieldController),
        pollUrlTemplate: optionalText(videoPollUrlController),
        contentUrlTemplate: optionalText(videoContentUrlController),
        cancelUrlTemplate: optionalText(videoCancelUrlController),
      );
    }

    UniversalMediaTaskOptions buildMusicTaskOptions() {
      return UniversalMediaTaskOptions(
        protocol: musicProtocol,
        requestFormat: musicRequestFormat,
        pollUrlTemplate: optionalText(musicPollUrlController),
        contentUrlTemplate: optionalText(musicContentUrlController),
        cancelUrlTemplate: optionalText(musicCancelUrlController),
      );
    }

    Widget buildMediaModelSelector({
      required UniversalMediaKind kind,
      required TextEditingController modelController,
      required StateSetter setState,
    }) {
      final label = kind == UniversalMediaKind.video ? '视频' : '音乐';
      return Consumer(
        builder: (selectorContext, selectorRef, _) {
          final candidatesAsync = selectorRef.watch(
            universalMediaModelCandidatesProvider(kind),
          );
          return candidatesAsync.when(
            loading: () => InputDecorator(
              decoration: InputDecoration(
                labelText: '$label媒体模型选择',
                helperText: '正在读取启用渠道的媒体模型目录…',
              ),
              child: const LinearProgressIndicator(),
            ),
            error: (_, _) => InputDecorator(
              decoration: InputDecoration(
                labelText: '$label媒体模型选择',
                helperText: '媒体目录读取失败，可继续手动输入模型。',
              ),
              child: const Text('手动输入 / 自定义模型'),
            ),
            data: (candidates) {
              final currentModel = modelController.text.trim();
              final manualFallback = UniversalMediaModelCandidate.manual(
                modelName: currentModel,
              );
              final selectionManual = kind == UniversalMediaKind.video
                  ? videoModelSelectionManual
                  : musicModelSelectionManual;
              final selectedChannelModelId = kind == UniversalMediaKind.video
                  ? selectedVideoChannelModelId
                  : selectedMusicChannelModelId;
              UniversalMediaModelCandidate? selected;
              if (!selectionManual) {
                for (final candidate in candidates) {
                  final matchesId =
                      selectedChannelModelId != null &&
                      candidate.channelModelId?.trim() ==
                          selectedChannelModelId.trim();
                  final matchesLegacyName =
                      selectedChannelModelId == null &&
                      candidate.modelName == currentModel;
                  if (matchesId || matchesLegacyName) {
                    selected = candidate;
                    break;
                  }
                }
              }
              if (!selectionManual &&
                  selectedChannelModelId != null &&
                  selected == null) {
                // 渠道模型被删除、禁用或不再声明媒体能力时，显示手动回退，
                // 并在保存时清掉已经失效的来源 ID。
                if (kind == UniversalMediaKind.video) {
                  selectedVideoChannelModelId = null;
                  videoModelSelectionManual = true;
                } else {
                  selectedMusicChannelModelId = null;
                  musicModelSelectionManual = true;
                }
              }
              final selectedValue = selected ?? manualFallback;
              return DropdownButtonFormField<UniversalMediaModelCandidate>(
                key: ValueKey(
                  '$kind-media-model-${modelController.text}-${candidates.length}',
                ),
                initialValue: selectedValue,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '$label媒体模型选择',
                  helperText:
                      '候选显示的来源渠道会成为实际$label媒体路由来源，不会修改顶部 Chat 模型；旧配置无渠道模型 ID 时仍复用当前 Chat 渠道。仅显式 $label 能力标记会显示为已声明。',
                ),
                items: [
                  for (final candidate in candidates)
                    DropdownMenuItem<UniversalMediaModelCandidate>(
                      value: candidate,
                      child: Text(
                        candidate.displayText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  DropdownMenuItem<UniversalMediaModelCandidate>(
                    value: manualFallback,
                    child: const Text('手动输入 / 自定义模型 · 保存时清空媒体渠道来源 ID'),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (candidate) {
                        final model = candidate?.modelName.trim() ?? '';
                        final channelModelId = candidate?.channelModelId;
                        setState(() {
                          modelController.text = model;
                          if (kind == UniversalMediaKind.video) {
                            selectedVideoChannelModelId = channelModelId;
                            videoModelSelectionManual = channelModelId == null;
                          } else {
                            selectedMusicChannelModelId = channelModelId;
                            musicModelSelectionManual = channelModelId == null;
                          }
                        });
                      },
              );
            },
          );
        },
      );
    }

    void applyProfile(UniversalMediaProviderProfile profile) {
      final options = profile.taskOptions;
      if (profile.kind == UniversalMediaKind.video) {
        selectedVideoProfileId = profile.id;
        selectedVideoChannelModelId = null;
        videoModelSelectionManual = true;
        videoModelController.text = profile.model;
        videoEndpointController.text = profile.endpoint;
        videoProtocol = options.protocol;
        videoRequestFormat = options.requestFormat;
        videoReferenceFieldController.text = options.referenceField ?? '';
        videoPollUrlController.text = options.pollUrlTemplate ?? '';
        videoContentUrlController.text = options.contentUrlTemplate ?? '';
        videoCancelUrlController.text = options.cancelUrlTemplate ?? '';
      } else {
        selectedMusicProfileId = profile.id;
        selectedMusicChannelModelId = null;
        musicModelSelectionManual = true;
        musicModelController.text = profile.model;
        musicEndpointController.text = profile.endpoint;
        musicProtocol = options.protocol;
        musicRequestFormat = options.requestFormat;
        musicPollUrlController.text = options.pollUrlTemplate ?? '';
        musicContentUrlController.text = options.contentUrlTemplate ?? '';
        musicCancelUrlController.text = options.cancelUrlTemplate ?? '';
      }
    }

    Widget buildProfileDropdown({
      required UniversalMediaKind kind,
      required StateSetter setState,
    }) {
      final profiles = universalMediaProviderProfilesFor(kind);
      final selectedId = kind == UniversalMediaKind.video
          ? selectedVideoProfileId
          : selectedMusicProfileId;
      return DropdownButtonFormField<String>(
        key: ValueKey('${kind.name}-media-profile-$selectedId'),
        initialValue: selectedId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: kind == UniversalMediaKind.video
              ? '视频 provider profile'
              : '音乐 provider profile',
        ),
        items: profiles
            .map(
              (profile) => DropdownMenuItem<String>(
                value: profile.id,
                child: Text(profile.name),
              ),
            )
            .toList(growable: false),
        onChanged: saving
            ? null
            : (value) {
                if (value == null) return;
                final profile = findUniversalMediaProviderProfile(
                  value,
                  kind: kind,
                );
                if (profile == null) return;
                setState(() => applyProfile(profile));
              },
      );
    }

    Widget buildTaskOptionsEditor({
      required UniversalMediaKind kind,
      required StateSetter setState,
    }) {
      final isVideo = kind == UniversalMediaKind.video;
      final protocol = isVideo ? videoProtocol : musicProtocol;
      final requestFormat = isVideo ? videoRequestFormat : musicRequestFormat;
      final allowedProtocols = isVideo
          ? const [
              UniversalMediaProtocol.auto,
              UniversalMediaProtocol.openAiVideo,
              UniversalMediaProtocol.xAiVideo,
              UniversalMediaProtocol.configuredAsync,
            ]
          : const [
              UniversalMediaProtocol.auto,
              UniversalMediaProtocol.configuredAsync,
            ];
      final options = isVideo
          ? buildVideoTaskOptions()
          : buildMusicTaskOptions();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<UniversalMediaProtocol>(
            key: ValueKey('${kind.name}-media-protocol-${protocol.name}'),
            initialValue: allowedProtocols.contains(protocol)
                ? protocol
                : allowedProtocols.first,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '任务协议'),
            items: allowedProtocols
                .map(
                  (value) => DropdownMenuItem<UniversalMediaProtocol>(
                    value: value,
                    child: Text(universalMediaProtocolLabel(value)),
                  ),
                )
                .toList(growable: false),
            onChanged: saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      if (isVideo) {
                        videoProtocol = value;
                      } else {
                        musicProtocol = value;
                      }
                    });
                  },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<UniversalMediaRequestFormat>(
            key: ValueKey('${kind.name}-media-format-${requestFormat.name}'),
            initialValue: requestFormat,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '请求编码'),
            items: UniversalMediaRequestFormat.values
                .map(
                  (value) => DropdownMenuItem<UniversalMediaRequestFormat>(
                    value: value,
                    child: Text(universalMediaRequestFormatLabel(value)),
                  ),
                )
                .toList(growable: false),
            onChanged: saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      if (isVideo) {
                        videoRequestFormat = value;
                      } else {
                        musicRequestFormat = value;
                      }
                    });
                  },
          ),
          if (isVideo) ...[
            const SizedBox(height: 8),
            TextField(
              controller: videoReferenceFieldController,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: '参考图字段（可选）',
                hintText: 'input_reference 或 image',
                helperText:
                    'xAI / Grok profile 会使用 image.url data URL，不会把本机路径发给服务端。',
              ),
            ),
          ],
          if (protocol == UniversalMediaProtocol.configuredAsync) ...[
            const SizedBox(height: 8),
            TextField(
              controller: isVideo
                  ? videoPollUrlController
                  : musicPollUrlController,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: '轮询 URL 模板',
                hintText: '/jobs/{id}/status',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: isVideo
                  ? videoContentUrlController
                  : musicContentUrlController,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: '结果 URL 模板',
                hintText: '/jobs/{id}/content',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: isVideo
                  ? videoCancelUrlController
                  : musicCancelUrlController,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: '取消 URL 模板（可选）',
                hintText: '/jobs/{id}',
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '已保存 wire options：${universalMediaTaskOptionsSummary(options)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('通用媒体接口'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '媒体模型与顶部 Chat 模型选择器分离，不会把视频 / 音乐模型送入普通 Chat 发送路径。候选显示的来源渠道会成为实际媒体路由来源，不会修改顶部 Chat 模型；旧配置没有渠道模型 ID 时仍复用当前 Chat 渠道，直到用户选择具体媒体渠道。这里从启用渠道的全部模型目录读取显式媒体候选；TTS 仍从独立的语音播报配置选择。profile 只快速填充公开的模型、endpoint 和任务协议；不会复制 API Key。',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                buildProfileDropdown(
                  kind: UniversalMediaKind.video,
                  setState: setState,
                ),
                const SizedBox(height: 4),
                Text(
                  (findUniversalMediaProviderProfile(
                            selectedVideoProfileId,
                            kind: UniversalMediaKind.video,
                          ) ??
                          config.videoProfile)
                      .description,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                buildMediaModelSelector(
                  kind: UniversalMediaKind.video,
                  modelController: videoModelController,
                  setState: setState,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: videoModelController,
                  enabled: !saving,
                  onChanged: saving
                      ? null
                      : (_) {
                          setState(() {
                            selectedVideoChannelModelId = null;
                            videoModelSelectionManual = true;
                          });
                        },
                  decoration: const InputDecoration(labelText: '视频模型'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: videoEndpointController,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: '视频接口路径',
                    hintText: '/v1/videos/generations',
                  ),
                ),
                const SizedBox(height: 12),
                buildTaskOptionsEditor(
                  kind: UniversalMediaKind.video,
                  setState: setState,
                ),
                const Divider(height: 24),
                buildProfileDropdown(
                  kind: UniversalMediaKind.music,
                  setState: setState,
                ),
                const SizedBox(height: 4),
                Text(
                  (findUniversalMediaProviderProfile(
                            selectedMusicProfileId,
                            kind: UniversalMediaKind.music,
                          ) ??
                          config.musicProfile)
                      .description,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                buildMediaModelSelector(
                  kind: UniversalMediaKind.music,
                  modelController: musicModelController,
                  setState: setState,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: musicModelController,
                  enabled: !saving,
                  onChanged: saving
                      ? null
                      : (_) {
                          setState(() {
                            selectedMusicChannelModelId = null;
                            musicModelSelectionManual = true;
                          });
                        },
                  decoration: const InputDecoration(labelText: '音乐模型'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: musicEndpointController,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: '音乐接口路径',
                    hintText: '/v1/audio/music',
                  ),
                ),
                const SizedBox(height: 8),
                buildTaskOptionsEditor(
                  kind: UniversalMediaKind.music,
                  setState: setState,
                ),
                const SizedBox(height: 8),
                Text(
                  '图片 / 视频 / 音乐生成仅在用户主动点击工具后调用；生成文件默认保存到应用私有目录。',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() {
                        saving = true;
                        errorText = null;
                      });
                      try {
                        await ref
                            .read(universalMediaConfigProvider.notifier)
                            .save(
                              videoModel: videoModelController.text,
                              videoEndpoint: videoEndpointController.text,
                              videoChannelModelId: videoModelSelectionManual
                                  ? null
                                  : selectedVideoChannelModelId,
                              musicModel: musicModelController.text,
                              musicEndpoint: musicEndpointController.text,
                              musicChannelModelId: musicModelSelectionManual
                                  ? null
                                  : selectedMusicChannelModelId,
                              videoProfileId: selectedVideoProfileId,
                              musicProfileId: selectedMusicProfileId,
                              videoTaskOptions: buildVideoTaskOptions(),
                              musicTaskOptions: buildMusicTaskOptions(),
                            );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (error) {
                        setState(() {
                          saving = false;
                          errorText = '保存失败：$error';
                        });
                      }
                    },
              child: Text(saving ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      // showDialog completes when Navigator.pop is requested, while the
      // route's exit transition can still rebuild the dialog.  Dispose after
      // that transition instead of invalidating TextFields during the pop.
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        videoModelController.dispose();
        videoEndpointController.dispose();
        musicModelController.dispose();
        musicEndpointController.dispose();
        videoReferenceFieldController.dispose();
        videoPollUrlController.dispose();
        videoContentUrlController.dispose();
        videoCancelUrlController.dispose();
        musicPollUrlController.dispose();
        musicContentUrlController.dispose();
        musicCancelUrlController.dispose();
      });
    });
  }

  Widget _buildImageGenerationTile(BuildContext context, WidgetRef ref) {
    final config = ref.watch(imageGenerationConfigProvider);
    return ListTile(
      leading: const Icon(Icons.auto_awesome_outlined),
      title: const Text('图片生成配置'),
      subtitle: Text(
        '模型：${config.model}\n在聊天输入框输入描述后，点“✨”按钮生成图片',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showImageGenerationDialog(context, ref),
    );
  }

  void _showImageGenerationDialog(BuildContext context, WidgetRef ref) {
    final config = ref.read(imageGenerationConfigProvider);
    final modelController = TextEditingController(text: config.model);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('图片生成模型'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: modelController,
                decoration: const InputDecoration(
                  labelText: '模型名',
                  hintText: '如 dall-e-3 / gpt-image-1 / 中继支持的其他图像模型',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '使用当前渠道的 Base URL 与 API Key，通过 OpenAI 兼容 /v1/images/generations 生成；图片本地保存，不进入云端。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(imageGenerationConfigProvider.notifier)
                  .setModel(modelController.text.trim());
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
        ],
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
    // mimo 模式识别大小写不敏感，但 Dropdown 的 value 必须与 items 精确
    // 相等；旧配置若保存了大写模型名，先归一为规范值，避免打开弹窗时
    // 触发 DropdownButton 的唯一 value 断言。
    final modelController = TextEditingController(
      text: simiRouterTtsModeOf(config.model) == null
          ? config.model
          : config.model.trim().toLowerCase(),
    );
    final voiceController = TextEditingController(text: config.voice);
    final apiKeyController = TextEditingController();
    final styleController = TextEditingController(text: config.style);
    final xaiCustomVoiceNameController = TextEditingController();
    final xaiCustomVoiceDescriptionController = TextEditingController();
    final xaiCustomVoiceGenderController = TextEditingController();
    final xaiCustomVoiceAccentController = TextEditingController();
    final xaiCustomVoiceAgeController = TextEditingController();
    final xaiCustomVoiceLanguageController = TextEditingController(
      text: config.language.toLowerCase() == 'auto' ? '' : config.language,
    );
    final xaiCustomVoiceUseCaseController = TextEditingController();
    final xaiCustomVoiceToneController = TextEditingController();
    var enabled = config.enabled || hasTtsEngine;
    var isSaving = false;
    var isCreatingCustomVoice = false;
    String? errorText;
    String? xaiCustomVoiceAudioPath;
    String? xaiCustomVoiceAudioName;
    String? xaiCustomVoiceStatusText;
    var speed = double.tryParse(config.speed) ?? 1.0;
    var responseFormat = config.responseFormat;
    String? referenceAudioPath = config.referenceAudioPath;
    String? referenceAudioName = config.referenceAudioPath?.split('/').last;
    var selectedPresetId = config.isXai
        ? kXaiSpeechProviderId
        : inferTextToSpeechPreset(
                baseUrl: config.baseUrl,
                model: config.model,
                voice: config.voice,
              )?.id ??
              'custom_openai_compatible';
    if (selectedPresetId == kXaiSpeechProviderId &&
        !kXaiTextToSpeechPlaybackFormats.contains(responseFormat)) {
      responseFormat = 'mp3';
    }

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
                const Text('• xAI / Grok Voice REST TTS 语音生成'),
                const Text('• AI 回复卡片一键语音播报'),
                const Text('• iOS / Android 原生本地音频播放通道'),
                const SizedBox(height: 12),
                Text(hasTtsEngine ? '当前：TTS 引擎已配置。' : '当前：TTS 引擎未配置。'),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用 TTS 语音播报'),
                  subtitle: const Text('点击 AI 回复下方播报按钮时生成临时音频并调用系统播放。'),
                  value: enabled,
                  onChanged: isSaving
                      ? null
                      : (value) => setState(() => enabled = value),
                ),
                const SizedBox(height: 8),
                Text(
                  selectedPresetId == kXaiSpeechProviderId
                      ? '厂商：xAI / Grok Voice REST'
                      : '厂商：OpenAI 兼容 TTS',
                ),
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
                            modelController.text = preset.ttsModel ?? '';
                            voiceController.text = preset.ttsVoice!;
                            if (preset.id == kXaiSpeechProviderId) {
                              speed = speed.clamp(
                                kXaiTextToSpeechMinSpeed,
                                kXaiTextToSpeechMaxSpeed,
                              );
                              if (!kXaiTextToSpeechPlaybackFormats.contains(
                                responseFormat,
                              )) {
                                responseFormat = 'mp3';
                              }
                            }
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
                if (selectedPresetId == kXaiSpeechProviderId) ...[
                  const Text(
                    'xAI / Grok Voice REST 不使用 model；TTS 使用 voice_id。',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Custom Voice 创建是 POST /v1/custom-voices 的真实网络能力：参考音频最多 120 秒，API 创建可能要求团队 / Enterprise 权限；403 或 413 会明确提示，不会生成伪 voice_id。',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.library_music_outlined, size: 18),
                    label: Text(
                      isCreatingCustomVoice ? '创建 custom voice 中…' : '选择参考音频',
                    ),
                    onPressed: isSaving || isCreatingCustomVoice
                        ? null
                        : () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.audio,
                              allowMultiple: false,
                            );
                            final path = result?.files.single.path?.trim();
                            if (path == null || path.isEmpty || !ctx.mounted) {
                              return;
                            }
                            setState(() {
                              xaiCustomVoiceAudioPath = path;
                              xaiCustomVoiceAudioName = p.basename(path);
                              errorText = null;
                              xaiCustomVoiceStatusText = null;
                            });
                          },
                  ),
                  if (xaiCustomVoiceAudioName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '已选择参考音频：$xaiCustomVoiceAudioName',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: xaiCustomVoiceNameController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(
                      labelText: 'name（可选）',
                      hintText: '例如：Friendly Narrator',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: xaiCustomVoiceDescriptionController,
                    enabled: !isSaving,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'description（可选）',
                      hintText: '声音用途或特点',
                    ),
                  ),
                  const SizedBox(height: 4),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: true,
                    title: const Text('官方 metadata（可选）'),
                    subtitle: const Text(
                      '仅发送 xAI 文档定义的 gender / accent / age / language / use_case / tone',
                    ),
                    children: [
                      TextField(
                        controller: xaiCustomVoiceGenderController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'gender（可选）',
                          hintText: 'male / female / neutral',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: xaiCustomVoiceAccentController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'accent（可选）',
                          hintText: '例如：American / British',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: xaiCustomVoiceAgeController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'age（可选）',
                          hintText: 'young / middle-aged / old',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: xaiCustomVoiceLanguageController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'language（可选）',
                          hintText: 'en / zh-CN',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: xaiCustomVoiceUseCaseController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'use_case（可选）',
                          hintText: 'narration / conversational',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: xaiCustomVoiceToneController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'tone（可选）',
                          hintText: 'warm / calm / professional',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text(
                      isCreatingCustomVoice ? '向 xAI 创建中…' : '创建并保存 voice_id',
                    ),
                    onPressed: isSaving || isCreatingCustomVoice
                        ? null
                        : () async {
                            final audioPath = xaiCustomVoiceAudioPath;
                            if (audioPath == null || audioPath.isEmpty) {
                              setState(() {
                                errorText = '请先选择参考音频';
                                xaiCustomVoiceStatusText = null;
                              });
                              return;
                            }
                            setState(() {
                              isSaving = true;
                              isCreatingCustomVoice = true;
                              errorText = null;
                              xaiCustomVoiceStatusText = null;
                            });
                            try {
                              final result = await ref
                                  .read(textToSpeechConfigProvider.notifier)
                                  .createAndSaveXaiCustomVoice(
                                    enabled: enabled,
                                    baseUrl: baseUrlController.text,
                                    request: XaiCustomVoiceRequest(
                                      audioPath: audioPath,
                                      fileName:
                                          xaiCustomVoiceAudioName ??
                                          p.basename(audioPath),
                                      name: xaiCustomVoiceNameController.text,
                                      description:
                                          xaiCustomVoiceDescriptionController
                                              .text,
                                      gender:
                                          xaiCustomVoiceGenderController.text,
                                      accent:
                                          xaiCustomVoiceAccentController.text,
                                      age: xaiCustomVoiceAgeController.text,
                                      language:
                                          xaiCustomVoiceLanguageController.text,
                                      useCase:
                                          xaiCustomVoiceUseCaseController.text,
                                      tone: xaiCustomVoiceToneController.text,
                                    ),
                                    apiKey: apiKeyController.text,
                                    language: config.language,
                                    speed: speed.toStringAsFixed(2),
                                    responseFormat: responseFormat,
                                  );
                              if (!ctx.mounted) return;
                              setState(() {
                                voiceController.text = result.voiceId;
                                isSaving = false;
                                isCreatingCustomVoice = false;
                                xaiCustomVoiceStatusText =
                                    '已创建并保存 voice_id=${result.voiceId}，后续 xAI TTS 将使用该 voice_id。';
                              });
                            } catch (error) {
                              if (!ctx.mounted) return;
                              setState(() {
                                isSaving = false;
                                isCreatingCustomVoice = false;
                                errorText = _safeTtsDialogError(error);
                              });
                            }
                          },
                  ),
                  if (xaiCustomVoiceStatusText != null) ...[
                    const SizedBox(height: 6),
                    Text(xaiCustomVoiceStatusText!),
                  ],
                ] else if (simiRouterTtsModeOf(modelController.text) != null)
                  DropdownButtonFormField<String>(
                    initialValue: modelController.text,
                    decoration: const InputDecoration(
                      labelText: '模型（SimiRouter）',
                      helperText: '三种 mimo 模式：合成 / 声音设计 / 声音克隆',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'mimo-v2.5-tts',
                        child: Text('mimo-v2.5-tts · 语音合成'),
                      ),
                      DropdownMenuItem(
                        value: 'mimo-v2.5-tts-voicedesign',
                        child: Text('mimo-v2.5-tts-voicedesign · 声音设计'),
                      ),
                      DropdownMenuItem(
                        value: 'mimo-v2.5-tts-voiceclone',
                        child: Text('mimo-v2.5-tts-voiceclone · 声音克隆'),
                      ),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) {
                            setState(() {
                              modelController.text =
                                  value ?? modelController.text;
                              if (value == 'mimo-v2.5-tts' &&
                                  !kSimiRouterTtsVoices.any(
                                    (v) => v.value == voiceController.text,
                                  )) {
                                // 切回合成模式时确保音色在预设列表内。
                                voiceController.text = 'alloy';
                              }
                            });
                          },
                  )
                else
                  TextField(
                    controller: modelController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(
                      labelText: '模型',
                      hintText: 'tts-1',
                    ),
                  ),
                if (simiRouterTtsModeOf(modelController.text) ==
                    SimiRouterTtsMode.standard) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue:
                        kSimiRouterTtsVoices.any(
                          (v) => v.value == voiceController.text,
                        )
                        ? voiceController.text
                        : 'alloy',
                    decoration: const InputDecoration(
                      labelText: '音色',
                      helperText: '8 种预设音色',
                    ),
                    items: [
                      for (final voice in kSimiRouterTtsVoices)
                        DropdownMenuItem(
                          value: voice.value,
                          child: Text(voice.label),
                        ),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) {
                            setState(
                              () => voiceController.text = value ?? 'alloy',
                            );
                          },
                  ),
                ] else if (simiRouterTtsModeOf(modelController.text) == null)
                  TextField(
                    controller: voiceController,
                    enabled: !isSaving,
                    decoration: InputDecoration(
                      labelText: selectedPresetId == kXaiSpeechProviderId
                          ? 'voice_id（内置或已创建 custom voice）'
                          : '音色',
                      hintText: 'alloy',
                      helperText: selectedPresetId == kXaiSpeechProviderId
                          ? '可填内置 voice_id 或已由 xAI Console/API 创建的 custom voice ID。'
                          : '仅允许字母、数字、点、下划线和短横线',
                    ),
                  ),
                // 声音设计模式：风格描述。
                if (simiRouterTtsModeOf(modelController.text) ==
                    SimiRouterTtsMode.voiceDesign) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: styleController,
                    enabled: !isSaving,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '声音风格描述',
                      hintText: '如：温柔自然的年轻女声，普通话标准',
                    ),
                  ),
                ],
                // 声音克隆模式：参考音频选择。
                if (simiRouterTtsModeOf(modelController.text) ==
                    SimiRouterTtsMode.voiceClone) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.audio_file_outlined, size: 18),
                    label: Text(
                      referenceAudioName == null
                          ? '选择参考音频（wav）'
                          : '参考音频：$referenceAudioName',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: isSaving
                        ? null
                        : () async {
                            final result = await FilePicker.platform.pickFiles(
                              // file_picker 只有 FileType.custom 才允许同时
                              // 传 allowedExtensions；否则真机会直接拒绝调用。
                              type: FileType.custom,
                              allowedExtensions: ['wav'],
                              allowMultiple: false,
                            );
                            final path = result?.files.single.path;
                            if (path == null || !ctx.mounted) return;
                            setState(() {
                              referenceAudioPath = path;
                              referenceAudioName = path.split('/').last;
                            });
                          },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '最大 10 MB；保存配置时会复制到应用私有目录，原文件后续移动或删除不影响使用。',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
                // mimo 模式通用：语速 + 输出格式。
                if (simiRouterTtsModeOf(modelController.text) != null ||
                    selectedPresetId == kXaiSpeechProviderId) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '语速 ${speed.toStringAsFixed(2)}x',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Expanded(
                        child: Slider(
                          value: speed.clamp(
                            selectedPresetId == kXaiSpeechProviderId
                                ? kXaiTextToSpeechMinSpeed
                                : kSimiRouterTtsMinSpeed,
                            selectedPresetId == kXaiSpeechProviderId
                                ? kXaiTextToSpeechMaxSpeed
                                : kSimiRouterTtsMaxSpeed,
                          ),
                          min: selectedPresetId == kXaiSpeechProviderId
                              ? kXaiTextToSpeechMinSpeed
                              : kSimiRouterTtsMinSpeed,
                          max: selectedPresetId == kXaiSpeechProviderId
                              ? kXaiTextToSpeechMaxSpeed
                              : kSimiRouterTtsMaxSpeed,
                          divisions: 60,
                          label: speed.toStringAsFixed(2),
                          onChanged: isSaving
                              ? null
                              : (value) => setState(() => speed = value),
                        ),
                      ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: responseFormat,
                    decoration: const InputDecoration(labelText: '输出格式'),
                    items: [
                      for (final format
                          in selectedPresetId == kXaiSpeechProviderId
                              ? kXaiTextToSpeechPlaybackFormats
                              : kSimiRouterTtsResponseFormats)
                        DropdownMenuItem(value: format, child: Text(format)),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) =>
                              setState(() => responseFormat = value ?? 'mp3'),
                  ),
                ],
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
                        final notifier = ref.read(
                          textToSpeechConfigProvider.notifier,
                        );
                        if (selectedPresetId == kXaiSpeechProviderId) {
                          await notifier.saveXai(
                            enabled: enabled,
                            baseUrl: baseUrlController.text,
                            voice: voiceController.text,
                            apiKey: apiKeyController.text,
                            language: config.language,
                            speed: speed.toStringAsFixed(2),
                            responseFormat: responseFormat,
                          );
                        } else {
                          await notifier.saveOpenAiCompatible(
                            enabled: enabled,
                            baseUrl: baseUrlController.text,
                            model: modelController.text,
                            voice: voiceController.text,
                            apiKey: apiKeyController.text,
                            speed: speed.toStringAsFixed(2),
                            responseFormat: responseFormat,
                            style: styleController.text,
                            referenceAudioPath: referenceAudioPath,
                          );
                        }
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
      styleController.dispose();
      xaiCustomVoiceNameController.dispose();
      xaiCustomVoiceDescriptionController.dispose();
      xaiCustomVoiceGenderController.dispose();
      xaiCustomVoiceAccentController.dispose();
      xaiCustomVoiceAgeController.dispose();
      xaiCustomVoiceLanguageController.dispose();
      xaiCustomVoiceUseCaseController.dispose();
      xaiCustomVoiceToneController.dispose();
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
      _showDataImportPreviewDialog(context, ref, service, file, preview);
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
    WidgetRef ref,
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
              _importLocalData(context, ref, service, file);
            },
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _importLocalData(
    BuildContext context,
    WidgetRef ref,
    DataImportService service,
    File file,
  ) async {
    try {
      final result = await service.importExport(file);
      ref.invalidate(assistantReflectionPendingProvider);
      var dreamingSyncSuffix = '';
      try {
        final restoredDreamingReports =
            await syncDreamingDigestStateFromDatabase(ref);
        if (restoredDreamingReports > 0) {
          dreamingSyncSuffix = '；Dreaming 报告已同步 $restoredDreamingReports 条';
        }
      } catch (_) {
        // Dreaming 状态回灌失败不应阻断文件 / 数据导入结果。
      }
      if (!context.mounted) return;
      _showArchiveSnack(context, '${result.summary}$dreamingSyncSuffix');
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
    final history = ref.watch(dreamingDigestHistoryProvider);
    final schedule = ref.watch(dreamingScheduleProvider);
    final iosBackgroundRefreshStatus = ref
        .watch(iosBackgroundRefreshStatusProvider)
        .valueOrNull;
    final latestFailedJob = ref
        .watch(latestFailedDreamingJobProvider)
        .valueOrNull;
    final scheduleText =
        '${schedule.enabled ? '自动整理已开启' : '自动整理已关闭'} · ${formatDreamingScheduleTime(schedule)}';
    final backgroundConditionsText = formatDreamingBackgroundConditions(
      schedule,
    );
    const scheduleBoundaryText =
        'Android WorkManager / iOS BGTaskScheduler 系统后台择机执行 · 前台到期兜底';
    final nextRunText = formatNextDreamingForegroundRun(
      schedule,
      now: DateTime.now(),
    );
    final historyText = history.isEmpty ? '' : ' · 历史 ${history.length} 次';
    final failedText = latestFailedJob == null
        ? ''
        : ' · 最近失败 ${latestFailedJob.dayKey} · 可重试';
    final iosBackgroundRefreshText =
        iosBackgroundRefreshStatus?.settingsSummary == null
        ? ''
        : ' · ${iosBackgroundRefreshStatus!.settingsSummary}';
    final subtitle = digest == null
        ? '$scheduleText · $backgroundConditionsText · $scheduleBoundaryText$iosBackgroundRefreshText · $nextRunText · 可手动生成今日摘要$historyText$failedText'
        : '$scheduleText · $backgroundConditionsText · $scheduleBoundaryText$iosBackgroundRefreshText · $nextRunText · 最近 ${digest.dayKey} · ${_formatDreamingMessageCoverage(digest)}$historyText$failedText';

    return ListTile(
      leading: const Icon(Icons.nightlight_round_outlined),
      title: const Text('Dreaming 夜间整理'),
      subtitle: Text(subtitle),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showDreamingDialog(context, ref),
    );
  }

  void _showDreamingDialog(BuildContext context, WidgetRef ref) {
    final pageRef = ref;
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final digest = ref.watch(dreamingDigestProvider);
          final history = ref.watch(dreamingDigestHistoryProvider);
          final schedule = ref.watch(dreamingScheduleProvider);
          final iosBackgroundRefreshStatus = ref
              .watch(iosBackgroundRefreshStatusProvider)
              .valueOrNull;
          final latestFailedJob = ref
              .watch(latestFailedDreamingJobProvider)
              .valueOrNull;
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
                      '当前不会上传云端，也不会调用远端模型。Android WorkManager 与 iOS BGTaskScheduler 会交给系统后台择机执行；系统不保证精确时刻，打开应用后的前台到期检查仍作为兜底。iOS 关闭“后台 App 刷新”后不会执行系统后台任务。',
                    ),
                    if (iosBackgroundRefreshStatus?.settingsSummary !=
                        null) ...[
                      const SizedBox(height: 8),
                      Text(
                        iosBackgroundRefreshStatus!.settingsSummary!,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:
                              iosBackgroundRefreshStatus ==
                                      IosBackgroundRefreshStatus.denied ||
                                  iosBackgroundRefreshStatus ==
                                      IosBackgroundRefreshStatus.restricted
                              ? Theme.of(ctx).colorScheme.error
                              : null,
                        ),
                      ),
                      if (iosBackgroundRefreshStatus ==
                              IosBackgroundRefreshStatus.denied ||
                          iosBackgroundRefreshStatus ==
                              IosBackgroundRefreshStatus.restricted)
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                final opened = await openIosAppSettings();
                                if (!opened && ctx.mounted) {
                                  _showArchiveSnack(ctx, '无法打开系统设置，请手动前往设置。');
                                }
                              },
                              icon: const Icon(Icons.settings_outlined),
                              label: const Text('打开系统设置'),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                ref.invalidate(
                                  iosBackgroundRefreshStatusProvider,
                                );
                              },
                              icon: const Icon(Icons.refresh_outlined),
                              label: const Text('重新检查'),
                            ),
                          ],
                        ),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动 Dreaming'),
                      subtitle: Text(
                        '默认夜间 ${formatDreamingScheduleTime(schedule)}',
                      ),
                      value: schedule.enabled,
                      onChanged: (value) async {
                        await ref
                            .read(dreamingScheduleProvider.notifier)
                            .setEnabled(value);
                        if (!ctx.mounted) return;
                        await _syncDreamingBackgroundScheduleWithFeedback(
                          ctx,
                          ref,
                        );
                      },
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
                        if (!ctx.mounted) return;
                        await _syncDreamingBackgroundScheduleWithFeedback(
                          ctx,
                          ref,
                        );
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('仅充电时执行'),
                      subtitle: const Text(
                        'Android / iOS 系统后台任务都会要求系统判定设备正在充电。',
                      ),
                      value: schedule.requiresCharging,
                      onChanged: (value) async {
                        await ref
                            .read(dreamingScheduleProvider.notifier)
                            .setRequiresCharging(value);
                        if (!ctx.mounted) return;
                        await _syncDreamingBackgroundScheduleWithFeedback(
                          ctx,
                          ref,
                        );
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('仅非计费网络执行'),
                      subtitle: const Text(
                        'Android 通常对应 Wi-Fi；iOS BGTaskScheduler 只能要求联网，无法保证 Wi-Fi。',
                      ),
                      value: schedule.requiresUnmeteredNetwork,
                      onChanged: (value) async {
                        await ref
                            .read(dreamingScheduleProvider.notifier)
                            .setRequiresUnmeteredNetwork(value);
                        if (!ctx.mounted) return;
                        await _syncDreamingBackgroundScheduleWithFeedback(
                          ctx,
                          ref,
                        );
                      },
                    ),
                    if (latestFailedJob != null) ...[
                      const SizedBox(height: 8),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              leading: const Icon(Icons.error_outline),
                              title: Text(
                                '最近 Dreaming 失败：${latestFailedJob.dayKey}',
                              ),
                              subtitle: Text(
                                _formatDreamingFailedJob(latestFailedJob),
                              ),
                              trailing: TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _runDreaming(
                                    context,
                                    pageRef,
                                    day: _parseDreamingDayKey(
                                      latestFailedJob.dayKey,
                                    ),
                                  );
                                },
                                child: const Text('重试最近失败'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (digest == null)
                      const Text('暂无 Dreaming 报告。')
                    else ...[
                      Text(
                        '最近报告：${digest.dayKey} · ${_formatDreamingMessageCoverage(digest)} · 耗时 ${digest.elapsedMs} ms',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        preview == null || preview.isEmpty ? '暂无摘要内容' : preview,
                        maxLines: 12,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (history.isEmpty)
                      const Text('暂无历史报告。')
                    else ...[
                      Text('历史报告已保留 ${history.length} 次'),
                      const SizedBox(height: 4),
                      ...history.take(5).map((item) {
                        final markdown = item.toMarkdown();
                        return ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: Text(
                            '${item.dayKey} · ${_formatDreamingMessageCoverage(item)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '会话 ${item.sessionCount} 个 · 耗时 ${item.elapsedMs} ms',
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                markdown.isEmpty ? '暂无报告内容' : markdown,
                                maxLines: 12,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _deleteDreamingReport(
                                  context,
                                  pageRef,
                                  item.dayKey,
                                ),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('删除此报告'),
                              ),
                            ),
                          ],
                        );
                      }),
                      if (history.length > 5)
                        Text(
                          '仅显示最近 5 次，其余仍保留在本机历史中。',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (latestFailedJob != null)
                TextButton(
                  onPressed: () => _dismissDreamingFailedJob(
                    context,
                    pageRef,
                    latestFailedJob,
                  ),
                  child: const Text('清除此失败'),
                ),
              TextButton(
                onPressed: digest == null && history.isEmpty
                    ? null
                    : () => _clearDreamingReports(context, pageRef),
                child: const Text('清空报告'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _runDreaming(context, pageRef);
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

  Future<void> _syncDreamingBackgroundScheduleWithFeedback(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      await syncDreamingBackgroundSchedule(ref.read(dreamingScheduleProvider));
    } on IosBackgroundRefreshUnavailableException catch (error) {
      if (context.mounted) {
        _showArchiveSnack(context, error.userMessage);
      }
    } catch (_) {
      if (context.mounted) {
        _showArchiveSnack(context, '系统后台调度更新失败，自动 Dreaming 将使用前台到期兜底。');
      }
    } finally {
      ref.invalidate(iosBackgroundRefreshStatusProvider);
    }
  }

  Future<void> _clearDreamingReports(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(dreamingDaoProvider).clearReports();
    await ref.read(dreamingDigestProvider.notifier).clear();
    await ref.read(dreamingDigestHistoryProvider.notifier).clear();
    await ref.read(assistantReflectionPendingProvider.notifier).clear();
    if (!context.mounted) return;
    _showArchiveSnack(context, 'Dreaming 报告已清空');
  }

  Future<void> _deleteDreamingReport(
    BuildContext context,
    WidgetRef ref,
    String dayKey,
  ) async {
    final digest = ref.read(dreamingDigestProvider);
    await ref.read(dreamingDaoProvider).deleteReportByDay(dayKey);
    await ref.read(dreamingDigestHistoryProvider.notifier).removeDay(dayKey);
    final pending = ref.read(assistantReflectionPendingProvider);
    if (pending?.sourceDigestDayKey == dayKey) {
      await ref.read(assistantReflectionPendingProvider.notifier).clear();
    }
    if (digest?.dayKey == dayKey) {
      final remainingHistory = ref.read(dreamingDigestHistoryProvider);
      if (remainingHistory.isEmpty) {
        await ref.read(dreamingDigestProvider.notifier).clear();
      } else {
        await ref
            .read(dreamingDigestProvider.notifier)
            .save(remainingHistory.first);
      }
    }
    if (!context.mounted) return;
    _showArchiveSnack(context, '已删除 Dreaming 报告：$dayKey');
  }

  Future<void> _dismissDreamingFailedJob(
    BuildContext context,
    WidgetRef ref,
    DreamingJob job,
  ) async {
    await ref.read(dreamingDaoProvider).dismissFailedJob(job.id);
    ref.invalidate(latestFailedDreamingJobProvider);
    if (!context.mounted) return;
    _showArchiveSnack(context, '已清除 Dreaming 失败提示：${job.dayKey}');
  }

  Future<void> _runDreaming(
    BuildContext context,
    WidgetRef ref, {
    DateTime? day,
  }) async {
    final DreamingDigest digest;
    try {
      digest = await runDreamingDigest(ref, day: day);
    } catch (_) {
      if (!context.mounted) return;
      _showArchiveSnack(context, 'Dreaming 失败，可到设置页重试');
      return;
    }
    final proposal = digest.hasContent
        ? await proposeUserProfileChanges(ref, reason: 'profile_proposal')
        : null;
    var reflectionActionCount = 0;
    var reflectionPending = false;
    if (digest.hasContent) {
      try {
        final reflection = await runAssistantReflection(
          ref,
          digest: digest,
          pendingProfileProposalCount: proposal?.diff.items.length ?? 0,
        );
        reflectionActionCount = reflection?.actionItems.length ?? 0;
      } catch (_) {
        // 反思失败不能影响 Dreaming 和画像候选主链路。
        reflectionPending = true;
      }
    }
    if (!context.mounted) return;
    final reflectionSuffix = reflectionActionCount > 0
        ? '，反思 $reflectionActionCount 个行动项'
        : reflectionPending
        ? '，反思待重试'
        : '';
    final messageCoverage = _formatDreamingMessageCoverage(digest);
    final message = digest.hasContent
        ? proposal == null
              ? 'Dreaming 已完成：$messageCoverage，画像暂无新增变更$reflectionSuffix'
              : 'Dreaming 已完成：$messageCoverage，已生成待确认画像变更（${proposal.diff.summary}）$reflectionSuffix'
        : 'Dreaming 已完成：今天暂无可整理对话';
    _showArchiveSnack(context, message);
  }

  String _formatDreamingFailedJob(DreamingJob job) {
    final trigger = switch (job.trigger) {
      'manual' => '手动运行',
      'foreground_due' => '前台到期',
      _ => job.trigger,
    };
    final error = _sanitizeDreamingFailedJobError(job.error);
    final errorText = error == null || error.isEmpty
        ? '未知错误'
        : error.length > 120
        ? '${error.substring(0, 120)}…'
        : error;
    return '$trigger · $errorText';
  }

  DateTime? _parseDreamingDayKey(String dayKey) {
    final parts = dayKey.split('-');
    if (parts.length != 3) return DateTime.tryParse(dayKey);
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return DateTime.tryParse(dayKey);
    }
    return DateTime(year, month, day, 22);
  }

  String? _sanitizeDreamingFailedJobError(String? raw) {
    if (raw == null) return null;
    var sanitized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (sanitized.isEmpty) return sanitized;
    sanitized = sanitized
        .replaceAll(
          RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
          'Bearer ***',
        )
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{6,}'), 'sk-***')
        .replaceAll(RegExp(r'AIza[0-9A-Za-z_-]{10,}'), 'AIza***')
        .replaceAll(
          RegExp(r'xox[baprs]-[A-Za-z0-9-]+', caseSensitive: false),
          'xox***',
        )
        .replaceAll(
          RegExp(r'https?://[^\s，。；;,)]+', caseSensitive: false),
          '[链接]',
        )
        .replaceAllMapped(
          RegExp(
            r'((?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password|passwd)=)[^\s&]+',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)}***',
        )
        .replaceAll(RegExp(r'(/Users/|/var/|/private/)[^\s，。；;,)]+'), '[本机路径]');
    return sanitized;
  }

  // ====== 本地反思 / 自我优化 ======

  Widget _buildReflectionTile(BuildContext context, WidgetRef ref) {
    final report = ref.watch(assistantReflectionProvider);
    final history = ref.watch(assistantReflectionHistoryProvider);
    final digest = ref.watch(dreamingDigestProvider);
    final pending = ref.watch(assistantReflectionPendingProvider);
    final promptEnabled = ref.watch(assistantReflectionPromptEnabledProvider);
    final modelEnabled = ref.watch(assistantReflectionModelEnabledProvider);
    final reflectionFreshnessText =
        report != null &&
            report.sourceDigestDayKey.isNotEmpty &&
            report.sourceDigestDayKey != report.dayKey
        ? ' · 来源 ${report.sourceDigestDayKey} · 先运行今日 Dreaming'
        : '';
    final pendingSuffix = pending == null
        ? ''
        : ' · 反思待重试 ${pending.sourceDigestDayKey}';
    final subtitle = report == null
        ? digest == null
              ? '暂无反思 · 先运行 Dreaming 后再生成$pendingSuffix'
              : '可基于 ${digest.dayKey} 的 Dreaming 报告生成本地反思$pendingSuffix'
        : '最近 ${report.dayKey}$reflectionFreshnessText · ${report.insights.length} 条结论 · ${report.actionItems.length} 个行动项 · ${report.generationModeLabel} · 历史 ${history.length} 次 · 短期提示${promptEnabled ? '开启' : '关闭'} · 模型开关${modelEnabled ? '开启' : '关闭'}$pendingSuffix';

    return ListTile(
      leading: const Icon(Icons.psychology_alt_outlined),
      title: const Text('本地反思 / 自我优化'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showReflectionDialog(context, ref),
    );
  }

  void _showReflectionDialog(BuildContext context, WidgetRef ref) {
    final parentRef = ref;
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, dialogRef, _) {
          final report = dialogRef.watch(assistantReflectionProvider);
          final history = dialogRef.watch(assistantReflectionHistoryProvider);
          final digest = dialogRef.watch(dreamingDigestProvider);
          final pending = dialogRef.watch(assistantReflectionPendingProvider);
          final promptEnabled = dialogRef.watch(
            assistantReflectionPromptEnabledProvider,
          );
          final modelEnabled = dialogRef.watch(
            assistantReflectionModelEnabledProvider,
          );
          final preview = report?.toMarkdown();
          final promptPreview = promptEnabled
              ? buildAssistantReflectionSystemPrompt(report)
              : null;
          return AlertDialog(
            title: const Text('本地反思 / 自我优化'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modelEnabled
                          ? '反思先在本机生成安全基线，再尝试使用默认聊天模型增强；模型失败、响应异常或无可用模型时会自动回退本地反思。'
                          : '本地 v1 基于最近 Dreaming 报告和用户画像，生成对回应质量、长期记忆、画像确认和下一步任务的可解释反思；当前不上传云端。',
                    ),
                    if (report?.generationMode ==
                        kReflectionGenerationModeModelFallback) ...[
                      const SizedBox(height: 12),
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.info_outline),
                        title: Text('最近一次模型增强失败，已安全回退本地反思'),
                        subtitle: Text('本地安全结论和行动项已正常保存，可稍后重新运行模型增强。'),
                      ),
                    ],
                    if (pending != null) ...[
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.sync_problem_outlined),
                        title: Text(
                          'Reflection 待重试：来源 Dreaming ${pending.sourceDigestDayKey}',
                        ),
                        subtitle: Text(
                          '已尝试 ${pending.attemptCount} 次；应用启动或恢复前台时会自动重试。',
                        ),
                        trailing: TextButton(
                          onPressed: () => _clearAssistantReflectionPending(
                            context,
                            parentRef,
                          ),
                          child: const Text('清除待重试'),
                        ),
                      ),
                    ],
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('使用模型增强反思'),
                      subtitle: const Text(
                        '默认关闭。开启后，经过长度限制和密钥 / URL / 本机路径脱敏的 Dreaming 摘要与本地反思可能发送给默认聊天模型；失败会自动回退本地反思。',
                      ),
                      value: modelEnabled,
                      onChanged: (enabled) {
                        unawaited(
                          dialogRef
                              .read(
                                assistantReflectionModelEnabledProvider
                                    .notifier,
                              )
                              .setEnabled(enabled),
                        );
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('用于下一轮短期提示'),
                      subtitle: const Text(
                        '开启后只把少量高优先级结论和行动项加入本机 system prompt；不会上传反思全文，且会被上下文预算裁剪。',
                      ),
                      value: promptEnabled,
                      onChanged: (enabled) {
                        unawaited(
                          dialogRef
                              .read(
                                assistantReflectionPromptEnabledProvider
                                    .notifier,
                              )
                              .setEnabled(enabled),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    if (digest == null)
                      const Text('暂无 Dreaming 报告。请先运行 Dreaming 夜间整理。')
                    else
                      Text(
                        '可用 Dreaming：${digest.dayKey} · ${digest.originalMessageCount} 条消息',
                      ),
                    const SizedBox(height: 12),
                    if (report == null)
                      const Text('暂无本地反思报告。')
                    else ...[
                      Text(
                        '最近反思：${report.dayKey} · 来源 ${report.sourceDigestDayKey} · ${report.generationMode == kReflectionGenerationModeModel ? '模型增强 + 本地规则' : '本地规则'}',
                      ),
                      Text(
                        '结论 ${report.insights.length} 条 · 行动项 ${report.actionItems.length} 个',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        preview == null || preview.isEmpty ? '暂无反思内容' : preview,
                        maxLines: 16,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      if (history.isNotEmpty) ...[
                        Text('历史反思已保留 ${history.length} 次'),
                        const SizedBox(height: 4),
                        ...history.take(5).map((item) {
                          final markdown = item.toMarkdown();
                          return ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: EdgeInsets.zero,
                            title: Text(
                              '${item.dayKey} · 来源 ${item.sourceDigestDayKey}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              '结论 ${item.insights.length} 条 · 行动项 ${item.actionItems.length} 个',
                            ),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  markdown.isEmpty ? '暂无反思内容' : markdown,
                                  maxLines: 12,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => _deleteAssistantReflection(
                                    context,
                                    parentRef,
                                    item.dayKey,
                                    item.sourceDigestDayKey,
                                  ),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('删除此反思'),
                                ),
                              ),
                            ],
                          );
                        }),
                        if (history.length > 5)
                          Text(
                            '仅显示最近 5 次，其余仍保留在本机历史中。',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (promptEnabled &&
                          promptPreview != null &&
                          promptPreview.isNotEmpty) ...[
                        const Text('下一轮短期提示预览'),
                        const SizedBox(height: 4),
                        Text(
                          promptPreview,
                          maxLines: 8,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ] else
                        Text(
                          promptEnabled
                              ? '暂无可注入的短期提示。'
                              : '短期提示已关闭，反思不会影响下一轮 system prompt。',
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: report == null && history.isEmpty && pending == null
                    ? null
                    : () => _clearAssistantReflection(context, parentRef),
                child: const Text('清空反思'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _runReflection(context, parentRef);
                },
                child: const Text('运行反思'),
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

  Future<void> _clearAssistantReflection(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(assistantReflectionProvider.notifier).clear();
    await ref.read(assistantReflectionHistoryProvider.notifier).clear();
    await ref.read(assistantReflectionPendingProvider.notifier).clear();
    if (!context.mounted) return;
    _showArchiveSnack(context, '本地反思报告已清空');
  }

  Future<void> _clearAssistantReflectionPending(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await ref.read(assistantReflectionPendingProvider.notifier).clear();
    if (!context.mounted) return;
    _showArchiveSnack(context, '已清除 Reflection 待重试状态');
  }

  Future<void> _deleteAssistantReflection(
    BuildContext context,
    WidgetRef ref,
    String dayKey,
    String sourceDigestDayKey,
  ) async {
    final report = ref.read(assistantReflectionProvider);
    await ref
        .read(assistantReflectionHistoryProvider.notifier)
        .removeReport(dayKey: dayKey, sourceDigestDayKey: sourceDigestDayKey);
    if (report?.dayKey == dayKey &&
        report?.sourceDigestDayKey == sourceDigestDayKey) {
      final remainingHistory = ref.read(assistantReflectionHistoryProvider);
      if (remainingHistory.isEmpty) {
        await ref.read(assistantReflectionProvider.notifier).clear();
      } else {
        await ref
            .read(assistantReflectionProvider.notifier)
            .save(remainingHistory.first);
      }
    }
    if (!context.mounted) return;
    _showArchiveSnack(context, '已删除本地反思：$dayKey · 来源 $sourceDigestDayKey');
  }

  Future<void> _runReflection(BuildContext context, WidgetRef ref) async {
    final pendingProfileProposalCount = ref
        .read(userProfileChangeProposalsProvider)
        .fold<int>(0, (total, proposal) => total + proposal.diff.items.length);
    ReflectionReport? report;
    try {
      report = await runAssistantReflection(
        ref,
        pendingProfileProposalCount: pendingProfileProposalCount,
      );
    } catch (_) {
      if (!context.mounted) return;
      _showArchiveSnack(context, '反思失败，已标记待重试');
      return;
    }
    if (!context.mounted) return;
    final message = report == null
        ? '请先运行 Dreaming 并积累可整理对话，再生成本地反思'
        : switch (report.generationMode) {
            kReflectionGenerationModeModel =>
              '模型增强反思已完成：${report.insights.length} 条结论，${report.actionItems.length} 个行动项',
            kReflectionGenerationModeModelFallback =>
              '模型增强不可用，本次已安全回退本地反思：${report.insights.length} 条结论',
            _ =>
              '本地反思已完成：${report.insights.length} 条结论，${report.actionItems.length} 个行动项',
          };
    _showArchiveSnack(context, message);
  }

  // ====== 用户画像 / 镜像数字人基础 ======

  Widget _buildUserProfileTile(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final proposals = ref.watch(userProfileChangeProposalsProvider);
    final modelEnabled = ref.watch(userProfileModelEnabledProvider);
    final proposalSuffix = proposals.isEmpty
        ? ''
        : ' · ${proposals.length} 个待确认变更';
    final subtitle = profile == null
        ? '尚未生成 · 可从本地 Key Points 与 Dreaming 报告重建$proposalSuffix'
        : profile.hasContent
        ? '${profile.sourceCount} 条来源 · ${profile.totalSignalCount} 个画像信号 · 本地保存 · 模型候选${modelEnabled ? '开启' : '关闭'}$proposalSuffix'
        : '暂无足够画像信号 · 继续聊天或添加记忆后重建 · 模型候选${modelEnabled ? '开启' : '关闭'}$proposalSuffix';

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
          final modelEnabled = ref.watch(userProfileModelEnabledProvider);
          return AlertDialog(
            title: const Text('用户画像 / 镜像数字人基础'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modelEnabled
                          ? '本地规则先生成画像候选，再尝试使用默认聊天模型补充少量有证据的待确认候选；模型失败会回退本地候选。'
                          : '本地 v1 只读取本机 Key Points 与最近 Dreaming 报告，生成可解释画像；不上传云端，模型辅助默认关闭。',
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('使用模型辅助画像候选'),
                      subtitle: const Text(
                        '默认关闭。开启后，只发送限长、脱敏的 Dreaming 摘要和本地候选；模型只能追加少量有证据的待确认候选，不能直接修改正式画像，也不能删除或覆盖已有画像，失败会回退本地规则。',
                      ),
                      value: modelEnabled,
                      onChanged: (enabled) {
                        unawaited(
                          ref
                              .read(userProfileModelEnabledProvider.notifier)
                              .setEnabled(enabled),
                        );
                      },
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

  Widget _buildMcpRuntimeTile(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(mcpRuntimeControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final running = runtime.isRunning;
    final subtitle = runtime.supportsContainerRuntime
        ? '${runtime.message}\nPC Node MCP 通过本地容器侧车运行；移动端继续使用 App 内建 Runtime。'
        : '${runtime.message}\nApp 内建 MCP 可直接在移动端运行。';

    return ListTile(
      leading: Icon(
        running ? Icons.developer_board : Icons.developer_board_outlined,
        color: running ? Colors.green[700] : scheme.primary,
      ),
      title: const Text('MCP Runtime（内建 / PC 容器）'),
      subtitle: Text(
        subtitle,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      isThreeLine: true,
      trailing: runtime.isBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: () => _showMcpRuntimeDialog(context, ref),
    );
  }

  void _showMcpRuntimeDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, dialogRef, _) {
          final runtime = dialogRef.watch(mcpRuntimeControllerProvider);
          final controller = dialogRef.read(
            mcpRuntimeControllerProvider.notifier,
          );
          final output = runtime.lastOutput.trim();
          return AlertDialog(
            title: const Text('MCP Runtime'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      runtime.message,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: runtime.status == McpRuntimeStatus.error
                            ? Theme.of(ctx).colorScheme.error
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '移动端默认使用 App 内建 MCP Runtime，不启动外部进程；PC 端需要 Node MCP 时使用容器侧车，通过本地 SSE 接入。',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      'Health: ${runtime.healthUrl}\nMCP SSE: ${runtime.sseUrl}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    if (!runtime.supportsContainerRuntime) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '当前平台无需也不支持启动 Docker / Podman 容器；请安装并启用「SimiChat 内建工具」。',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                    if (output.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '最近输出',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            ctx,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          output,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: runtime.isBusy ? null : () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: runtime.isBusy
                    ? null
                    : () => controller.refreshStatus(),
                child: const Text('刷新'),
              ),
              if (runtime.supportsContainerRuntime) ...[
                TextButton(
                  onPressed: runtime.isBusy ? null : () => controller.stop(),
                  child: const Text('停止'),
                ),
                TextButton(
                  onPressed: runtime.isBusy ? null : () => controller.smoke(),
                  child: const Text('自检'),
                ),
                FilledButton(
                  onPressed: runtime.isBusy ? null : () => controller.start(),
                  child: const Text('启动容器'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildMcpSection(BuildContext context, WidgetRef ref) {
    final mcpServers = ref.watch(mcpManagerProvider);
    final manager = ref.read(mcpManagerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildMcpRuntimeTile(context, ref),
        for (final server in mcpServers)
          ListTile(
            leading: Icon(
              server.transport == kMcpTransportAppNative
                  ? Icons.phone_iphone
                  : server.transport == kMcpTransportStdio
                  ? Icons.terminal
                  : Icons.cloud,
              size: 20,
            ),
            title: Text(server.name),
            subtitle: Text(
              [
                isMobileMcpPlatform && isPcOnlyMcpConfig(server)
                    ? '仅 PC · 需要 Docker/Podman'
                    : server.transport == kMcpTransportAppNative
                    ? 'App 内建 · 无需 Node/npx/Python · 移动端/PC 直接运行'
                    : server.transport == kMcpTransportStdio
                    ? isMobileMcpPlatform
                          ? mobileStdioDescription(server)
                          : '${server.command} ${(server.args ?? []).join(' ')}'
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
                  onChanged: isMobileMcpPlatform && isPcOnlyMcpConfig(server)
                      ? null
                      : (v) async {
                          final updated = server.copyWith(isEnabled: v);
                          await manager.updateServer(updated);
                          if (v) {
                            try {
                              await manager.connectServer(updated);
                            } catch (e) {
                              // Do not persist a broken enabled row. Otherwise the
                              // next cold start repeats the same failed handshake.
                              await manager.updateServer(
                                updated.copyWith(isEnabled: false),
                              );
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
    String transport = kMcpTransportAppNative;
    final transportItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: kMcpTransportAppNative,
        child: Text('App 内建（移动端/PC 直接运行）'),
      ),
      const DropdownMenuItem(
        value: kMcpTransportStdio,
        child: Text('Stdio（移动兼容 / 内置 Runtime）'),
      ),
      const DropdownMenuItem(value: kMcpTransportSse, child: Text('SSE（远程服务）')),
    ];

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
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '传输方式'),
                  items: transportItems,
                  onChanged: (v) => setDialogState(() => transport = v!),
                ),
                const SizedBox(height: 12),
                if (transport == kMcpTransportAppNative) ...[
                  const Text(
                    '使用 SimiChat 内建 MCP Runtime，不启动外部进程，'
                    '移动端无需安装 Node / npx / Python 即可连接。',
                    style: TextStyle(fontSize: 12),
                  ),
                ] else if (transport == kMcpTransportStdio) ...[
                  if (isMobileMcpPlatform)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        '移动端支持已审核适配器和移动扩展；不会启动手机外部命令。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
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
                  command: transport == kMcpTransportStdio
                      ? commandCtrl.text
                      : null,
                  args:
                      transport == kMcpTransportStdio &&
                          argsCtrl.text.isNotEmpty
                      ? argsCtrl.text.split(' ')
                      : null,
                  url: transport == kMcpTransportSse ? urlCtrl.text : null,
                );
                final manager = ref.read(mcpManagerProvider.notifier);
                await manager.addServer(config);
                try {
                  await manager.connectServer(config);
                } catch (e) {
                  await manager.updateServer(config.copyWith(isEnabled: false));
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

String _formatDreamingMessageCoverage(DreamingDigest digest) {
  final total = digest.totalOriginalMessageCount;
  if (total > digest.originalMessageCount) {
    return '${digest.originalMessageCount} / $total 条消息';
  }
  return '${digest.originalMessageCount} 条消息';
}

/// 推广卡片内的能力要点标签：小图标 + 短文案。
class _ProviderPresetHint extends StatelessWidget {
  final ModelProviderPreset preset;
  final VoidCallback? onOpenSignUp;
  final VoidCallback? onOpenDocs;

  const _ProviderPresetHint({
    required this.preset,
    this.onOpenSignUp,
    this.onOpenDocs,
  });

  bool get _isSimiRouter => preset.id == 'dwchainless';

  Widget _buildSimiRouterHint(BuildContext context, ColorScheme scheme) {
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
              if (preset.logoAsset != null)
                CircleAvatar(
                  radius: 9,
                  backgroundColor: scheme.surface,
                  backgroundImage: AssetImage(preset.logoAsset!),
                )
              else
                Icon(
                  getProviderIcon(preset.id),
                  size: 18,
                  color: scheme.primary,
                ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  preset.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
              Text(
                '推荐接入',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '填写 API Key 即可完成接入。还没有 Key？先注册，注册页会在应用内打开。',
            style: TextStyle(fontSize: 12),
          ),
          if (preset.recommendedModels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '推荐模型 · ${preset.recommendedModels.join('、')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '复制推荐模型名',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: preset.recommendedModels.join('\n')),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(const SnackBar(content: Text('推荐模型名已复制')));
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onOpenSignUp,
                icon: const Icon(Icons.person_add_alt_1, size: 16),
                label: const Text('获取 Key'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenDocs,
                icon: const Icon(Icons.language, size: 16),
                label: const Text('访问官网'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_isSimiRouter) {
      return _buildSimiRouterHint(context, scheme);
    }
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
              if (preset.logoAsset != null)
                CircleAvatar(
                  radius: 8,
                  backgroundColor: scheme.surface,
                  backgroundImage: AssetImage(preset.logoAsset!),
                )
              else
                Icon(
                  getProviderIcon(preset.id),
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
          if (preset.recommendedModels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '建议模型名',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              preset.recommendedModels.join('、'),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: preset.recommendedModels.join('\n')),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(const SnackBar(content: Text('建议模型名已复制')));
                },
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('复制建议模型名'),
              ),
            ),
          ],
          if (!_isSimiRouter) ...[
            const SizedBox(height: 6),
            SelectableText(
              preset.docsUrl,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (preset.signUpUrl != null)
                  TextButton.icon(
                    onPressed: onOpenSignUp,
                    icon: const Icon(Icons.person_add_alt_1, size: 16),
                    label: const Text('去注册'),
                  ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: preset.baseUrl),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        const SnackBar(content: Text('Base URL 已复制')),
                      );
                  },
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('复制 Base URL'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: preset.docsUrl),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(const SnackBar(content: Text('文档链接已复制')));
                  },
                  icon: const Icon(Icons.link_outlined, size: 16),
                  label: const Text('复制文档链接'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
