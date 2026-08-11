import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/mobile_extension_manifest.dart';
import '../../core/extensions/mobile_extension_registry.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/mobile_extension_provider.dart';
import '../../shared/providers/mcp_provider.dart';
import '../../shared/providers/skill_provider.dart';

/// Local package manager for verified MCP, Skill and Agent packages.
class MobileExtensionsPage extends ConsumerWidget {
  const MobileExtensionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isAppManagedMcpExtensionPlatform) {
      return Scaffold(
        appBar: AppBar(title: const Text('本地扩展')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '当前平台没有 App-owned MCP Runtime。\n请使用 App 内建工具或远程 SSE 服务。',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final extensions = ref.watch(installedMobileExtensionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地扩展'),
        actions: [
          IconButton(
            tooltip: '导入扩展包',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _importPackage(context, ref),
          ),
        ],
      ),
      body: extensions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('读取扩展失败：$error')),
        data: (records) => records.isEmpty
            ? const Center(
                child: Text('还没有扩展。点击右上角导入并完成哈希完整性检查的 package JSON。'),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: records.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) =>
                    _buildRecord(context, ref, records[index]),
              ),
      ),
    );
  }

  Widget _buildRecord(
    BuildContext context,
    WidgetRef ref,
    MobileExtensionRecord record,
  ) {
    final manifest = record.manifest;
    final title = manifest.name ?? manifest.id;
    final detail = [
      manifest.type.name,
      'v${manifest.version}',
      record.status.wireName,
      if (manifest.description != null) manifest.description!,
    ].join(' · ');
    return Card(
      child: ListTile(
        leading: Icon(_iconFor(manifest.type)),
        title: Text(title),
        subtitle: Text(detail),
        isThreeLine: manifest.description != null,
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'toggle') {
              await _toggle(context, ref, record);
            } else if (action == 'remove') {
              await _uninstall(context, ref, record);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'toggle',
              child: Text(record.enabled ? '禁用' : '启用'),
            ),
            const PopupMenuItem(value: 'remove', child: Text('卸载')),
          ],
        ),
      ),
    );
  }

  Future<void> _importPackage(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'package'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      if (!context.mounted) return;
      _showMessage(context, '无法读取扩展包');
      return;
    }
    try {
      final installed = await installMobileExtension(ref, bytes);
      if (!context.mounted) return;
      _showMessage(
        context,
        '已安装 ${installed.install.record.manifest.name ?? installed.install.record.manifest.id}',
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      _showMessage(context, '安装失败：$error');
    }
  }

  Future<void> _uninstall(
    BuildContext context,
    WidgetRef ref,
    MobileExtensionRecord record,
  ) async {
    try {
      final id = record.manifest.id;
      await ref.read(mobileExtensionServiceProvider).uninstall(id);
      if (record.manifest.type.name == 'skill') {
        await ref.read(skillDaoProvider).deleteSkill(id);
        ref.invalidate(skillsProvider);
        ref.invalidate(enabledSkillsProvider);
      }
      if (record.manifest.type.name == 'mcp') {
        await ref
            .read(mcpManagerProvider.notifier)
            .removeServer('mobile-extension-$id');
      }
      ref.invalidate(installedMobileExtensionsProvider);
      if (!context.mounted) return;
      _showMessage(context, '已卸载 $id');
    } on Object catch (error) {
      if (!context.mounted) return;
      _showMessage(context, '卸载失败：$error');
    }
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    MobileExtensionRecord record,
  ) async {
    final manifest = record.manifest;
    final enabled = !record.enabled;
    final managedMcp =
        manifest.type == MobileExtensionType.mcp &&
        (manifest.mcpTransport == 'app_native' ||
            manifest.runtime == MobileExtensionRuntime.nodeMobile);
    try {
      final extensionService = ref.read(mobileExtensionServiceProvider);
      // For enable, mark the registry first so a process interruption before
      // the handshake leaves a safe disabled MCP row. For disable, do the
      // reverse: stop and persist the MCP row first, then mark the registry
      // disabled. This prevents a crash window where the UI says disabled but
      // McpManager still auto-connects the extension on the next launch.
      if (!managedMcp || enabled) {
        await extensionService.setEnabled(manifest.id, enabled);
      }
      if (manifest.type == MobileExtensionType.skill) {
        await ref.read(skillDaoProvider).toggleEnabled(manifest.id, enabled);
        ref.invalidate(skillsProvider);
        ref.invalidate(enabledSkillsProvider);
      } else if (managedMcp) {
        final serverId = 'mobile-extension-${manifest.id}';
        final manager = ref.read(mcpManagerProvider.notifier);
        if (enabled) {
          final config = ref
              .read(mcpManagerProvider)
              .where((server) => server.id == serverId)
              .toList(growable: false);
          if (config.isEmpty) {
            throw StateError('找不到 MCP 配置，请重新安装该扩展');
          }
          var connected = false;
          try {
            // Keep the database row disabled until the handshake succeeds;
            // otherwise a failed reconnect would be retried on every cold
            // start even though the registry rollback below marks the
            // package disabled.
            await manager.connectServer(config.first.copyWith(isEnabled: true));
            connected = true;
            await manager.setServerEnabled(serverId, true);
          } catch (_) {
            if (connected) {
              await manager.disconnectServer(serverId);
            }
            await manager.setServerEnabled(serverId, false);
            rethrow;
          }
        } else {
          await manager.disconnectServer(serverId);
          await manager.setServerEnabled(serverId, false);
          await extensionService.setEnabled(manifest.id, false);
        }
      }
      ref.invalidate(installedMobileExtensionsProvider);
    } on Object catch (error) {
      if (enabled && manifest.type == MobileExtensionType.mcp) {
        // A failed reconnect must not leave the registry enabled. Otherwise
        // every cold start retries the same broken extension indefinitely.
        try {
          await ref
              .read(mobileExtensionServiceProvider)
              .setEnabled(manifest.id, false);
        } on Object catch (_) {
          // Preserve the original connection error for the user.
        }
      }
      if (!context.mounted) return;
      _showMessage(context, '启用状态更新失败：$error');
    }
  }

  IconData _iconFor(dynamic type) {
    return switch (type.name) {
      'mcp' => Icons.extension,
      'skill' => Icons.auto_awesome,
      _ => Icons.smart_toy_outlined,
    };
  }

  void _showMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
