import 'mobile_extension_adapters.dart';
import 'mobile_extension_agent.dart';
import 'mobile_extension_installer.dart';
import 'mobile_extension_manifest.dart';
import 'mobile_extension_registry.dart';
import '../skills/skill.dart';

/// High-level install result consumed by Flutter providers and pages.
class InstalledMobileExtension {
  const InstalledMobileExtension({
    required this.install,
    this.skill,
    this.agent,
    this.mcp,
  });

  final MobileExtensionInstallResult install;
  final Skill? skill;
  final MobileAgentDefinition? agent;
  final MobileMcpInstallDescriptor? mcp;
}

/// Parses and validates all three installable extension types without
/// starting a process. Platform adapters can then decide whether an MCP is
/// app-native, a bundled Node Mobile module, or a remote SSE endpoint.
class MobileExtensionService {
  const MobileExtensionService(this.installer);

  final MobileExtensionInstaller installer;

  Future<InstalledMobileExtension> installBytes(
    List<int> bytes, {
    String? expectedPackageSha256,
  }) async {
    final install = await installer.installBytes(
      bytes,
      expectedPackageSha256: expectedPackageSha256,
    );
    final package = install.package;
    switch (package.manifest.type) {
      case MobileExtensionType.skill:
        return InstalledMobileExtension(
          install: install,
          skill: skillFromMobileExtension(package),
        );
      case MobileExtensionType.agent:
        return InstalledMobileExtension(
          install: install,
          agent: MobileAgentDefinition.fromPackage(package),
        );
      case MobileExtensionType.mcp:
        return InstalledMobileExtension(
          install: install,
          mcp: MobileMcpInstallDescriptor.fromResult(install),
        );
    }
  }

  Future<InstalledMobileExtension> installFromUrl(
    Uri uri, {
    String? expectedPackageSha256,
  }) async {
    final install = await installer.installFromUrl(
      uri,
      expectedPackageSha256: expectedPackageSha256,
    );
    final package = install.package;
    switch (package.manifest.type) {
      case MobileExtensionType.skill:
        return InstalledMobileExtension(
          install: install,
          skill: skillFromMobileExtension(package),
        );
      case MobileExtensionType.agent:
        return InstalledMobileExtension(
          install: install,
          agent: MobileAgentDefinition.fromPackage(package),
        );
      case MobileExtensionType.mcp:
        return InstalledMobileExtension(
          install: install,
          mcp: MobileMcpInstallDescriptor.fromResult(install),
        );
    }
  }

  Future<List<MobileExtensionRecord>> installed() => installer.installed();

  Future<MobileExtensionRecord?> setEnabled(String id, bool enabled) {
    return installer.enable(id, enabled: enabled);
  }

  Future<void> uninstall(String id) => installer.uninstall(id);
}
