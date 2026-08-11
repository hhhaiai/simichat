import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mcp/mcp_client.dart';
import '../../core/extensions/mobile_extension_agent.dart';
import '../../core/extensions/mobile_extension_installer.dart';
import '../../core/extensions/mobile_extension_service.dart';
import 'database_provider.dart';
import 'mcp_provider.dart';
import 'skill_provider.dart';

/// App-owned installer used by Android, iOS and desktop extension pages.
final mobileExtensionInstallerProvider = Provider<MobileExtensionInstaller>((
  ref,
) {
  final installer = MobileExtensionInstaller();
  ref.onDispose(installer.dispose);
  return installer;
});

final mobileExtensionServiceProvider = Provider<MobileExtensionService>((ref) {
  return MobileExtensionService(ref.watch(mobileExtensionInstallerProvider));
});

final mobileAgentRuntimeProvider = Provider<MobileAgentRuntime>((ref) {
  return const MobileAgentRuntime();
});

final installedMobileExtensionsProvider = FutureProvider(
  (ref) => ref.watch(mobileExtensionServiceProvider).installed(),
);

/// Installs a package and activates the parts that already have a native
/// Flutter boundary. Skills are written to the existing Skills table;
/// app-native MCP packages are connected immediately on both Android and iOS;
/// pure-JS Node Mobile packages are registered in the App-owned runtime and
/// connected through its private JSON-Lines stdio bridge.  No package installation path
/// invokes npm, npx, a shell, or a host process.
Future<InstalledMobileExtension> installMobileExtension(
  WidgetRef ref,
  List<int> bytes, {
  String? expectedPackageSha256,
}) async {
  final service = ref.read(mobileExtensionServiceProvider);
  final installed = await service.installBytes(
    bytes,
    expectedPackageSha256: expectedPackageSha256,
  );
  final skill = installed.skill;
  if (skill != null) {
    await ref
        .read(skillDaoProvider)
        .upsertSkill(
          id: skill.id,
          name: skill.name,
          description: skill.description,
          instructions: skill.instructions,
          sourceUrl: skill.sourceUrl,
          sourceSha256: skill.sourceSha256,
          sha256Verified: skill.sha256Verified,
          online: skill.online,
          isEnabled: skill.isEnabled,
        );
    ref.invalidate(skillsProvider);
    ref.invalidate(enabledSkillsProvider);
  }

  final mcp = installed.mcp;
  if (mcp != null && mcp.isAppNative && mcp.serverId != null) {
    final manager = ref.read(mcpManagerProvider.notifier);
    final serverId = 'mobile-extension-${mcp.id}';
    final existing = ref
        .read(mcpManagerProvider)
        .where((server) => server.id == serverId);
    if (existing.isNotEmpty) await manager.removeServer(serverId);
    final config = McpServerConfig(
      id: serverId,
      name: mcp.name,
      transport: kMcpTransportAppNative,
      isEnabled: true,
      source: 'marketplace',
      marketplaceId: mcp.serverId,
    );
    await manager.addServer(config);
    try {
      await manager.connectServer(config);
    } catch (_) {
      // Keep the package installed for an explicit retry, but do not leave a
      // broken enabled row that retries on every application launch.
      await manager.updateServer(config.copyWith(isEnabled: false));
      rethrow;
    }
  }
  if (mcp != null && mcp.isNodeMobile) {
    final manager = ref.read(mcpManagerProvider.notifier);
    final serverId = 'mobile-extension-${mcp.id}';
    final existing = ref
        .read(mcpManagerProvider)
        .where((server) => server.id == serverId);
    if (existing.isNotEmpty) await manager.removeServer(serverId);
    final config = McpServerConfig(
      id: serverId,
      name: mcp.name,
      // Preserve the user's stdio-compatible MCP semantics in the persisted
      // row. McpManager binds this to the app-owned Node Mobile runtime and
      // uses its private JSON-Lines bridge; no host command is started.
      transport: kMcpTransportStdio,
      isEnabled: true,
      source: 'mobile_extension',
      marketplaceId: '$kMobileExtensionMarketplacePrefix${mcp.id}',
      headers: <String, String>{
        kMobileExtensionRootConfigKey: mcp.installPath,
        kMobileExtensionEntryConfigKey: mcp.entry,
        kMobileExtensionProtocolConfigKey: mcp.protocol ?? 'mobile-mcp-v1',
        kMobileExtensionSha256ConfigKey: mcp.sha256,
        kMobileExtensionPermissionsConfigKey: mcp.permissions.join(','),
      },
    );
    await manager.addServer(config);
    try {
      await manager.connectServer(config);
    } catch (_) {
      await manager.updateServer(config.copyWith(isEnabled: false));
      rethrow;
    }
  }
  ref.invalidate(installedMobileExtensionsProvider);
  return installed;
}
