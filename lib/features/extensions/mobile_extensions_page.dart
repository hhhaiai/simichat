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

/// Local package manager for Android / iOS MCP, Skill and Agent packages.
class MobileExtensionsPage extends ConsumerWidget {
  const MobileExtensionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extensions = ref.watch(installedMobileExtensionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('移动端扩展'),
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
            ? const Center(child: Text('还没有扩展。点击右上角导入经过校验的 package JSON。'))
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
    try {
      await ref
          .read(mobileExtensionServiceProvider)
          .setEnabled(manifest.id, enabled);
      if (manifest.type == MobileExtensionType.skill) {
        await ref.read(skillDaoProvider).toggleEnabled(manifest.id, enabled);
        ref.invalidate(skillsProvider);
        ref.invalidate(enabledSkillsProvider);
      } else if (manifest.type == MobileExtensionType.mcp &&
          manifest.mcpTransport == 'app_native') {
        final serverId = 'mobile-extension-${manifest.id}';
        final manager = ref.read(mcpManagerProvider.notifier);
        if (enabled) {
          final config = ref
              .read(mcpManagerProvider)
              .where((server) => server.id == serverId)
              .toList(growable: false);
          if (config.isNotEmpty) {
            await manager.connectServer(config.first);
          }
        } else {
          await manager.disconnectServer(serverId);
        }
      }
      ref.invalidate(installedMobileExtensionsProvider);
    } on Object catch (error) {
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
