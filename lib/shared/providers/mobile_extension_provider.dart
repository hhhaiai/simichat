import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mcp/mcp_client.dart';
import '../../core/extensions/mobile_extension_agent.dart';
import '../../core/extensions/mobile_extension_installer.dart';
import '../../core/extensions/mobile_extension_service.dart';
import 'database_provider.dart';
import 'mcp_provider.dart';
import 'skill_provider.dart';

/// App-owned installer used by Android and iOS extension pages.
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
/// Node Mobile packages stay in the verified registry until their bundled
/// runtime endpoint is selected by the platform adapter.
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
    await manager.connectServer(config);
  }
  ref.invalidate(installedMobileExtensionsProvider);
  return installed;
}
