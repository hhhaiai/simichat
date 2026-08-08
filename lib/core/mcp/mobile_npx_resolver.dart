/// Resolves the small, audited set of legacy npm MCP entries that have a
/// mobile equivalent.  Resolution is deliberately deterministic: it never
/// downloads a package and never returns a command for Process.start().
class MobileNpxResolution {
  const MobileNpxResolution({required this.packageName, required this.profile});

  final String packageName;
  final String profile;
}

class MobileNpxResolver {
  MobileNpxResolver._();

  static const Map<String, String> _knownPackages = <String, String>{
    '@modelcontextprotocol/server-time': 'time',
    '@modelcontextprotocol/server-memory': 'memory',
    '@modelcontextprotocol/server-fetch': 'fetch',
    '@modelcontextprotocol/server-filesystem': 'filesystem',
  };

  static MobileNpxResolution? resolve({
    required String command,
    List<String> args = const <String>[],
  }) {
    if (command.trim().toLowerCase() != 'npx') return null;
    final packageSpec = args
        .map((arg) => arg.trim())
        .firstWhere(
          (arg) => arg.startsWith('@') && !arg.startsWith('--'),
          orElse: () => '',
        );
    final packageName = _stripVersion(packageSpec);
    final profile = _knownPackages[packageName];
    if (profile == null) return null;
    return MobileNpxResolution(packageName: packageName, profile: profile);
  }

  static String _stripVersion(String packageSpec) {
    if (!packageSpec.startsWith('@')) return packageSpec;
    final separator = packageSpec.indexOf('@', 1);
    return separator == -1 ? packageSpec : packageSpec.substring(0, separator);
  }
}
