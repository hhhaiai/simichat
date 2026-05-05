import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'mcp_dao.g.dart';

@DriftAccessor(tables: [McpServers])
class McpDao extends DatabaseAccessor<AppDatabase> with _$McpDaoMixin {
  McpDao(super.db);

  Future<List<McpServer>> getAllServers() {
    return (select(mcpServers)..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<McpServer?> getServer(String id) {
    return (select(mcpServers)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<McpServer?> getServerByMarketplaceId(String marketplaceId) {
    return (select(mcpServers)
          ..where((t) => t.marketplaceId.equals(marketplaceId)))
        .getSingleOrNull();
  }

  Future<int> insertServer({
    required String id,
    required String name,
    required String transport,
    String? command,
    String? args,
    String? url,
    String? headers,
    bool isEnabled = true,
    String source = 'manual',
    String? marketplaceId,
  }) {
    return into(mcpServers).insert(McpServersCompanion.insert(
      id: id,
      name: name,
      transport: transport,
      command: Value(command),
      args: Value(args),
      url: Value(url),
      headers: Value(headers),
      isEnabled: Value(isEnabled),
      source: Value(source),
      marketplaceId: Value(marketplaceId),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> updateServer({
    required String id,
    String? name,
    bool? isEnabled,
    String? command,
    String? args,
    String? url,
    String? headers,
  }) {
    return (update(mcpServers)..where((t) => t.id.equals(id))).write(
      McpServersCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        isEnabled: isEnabled != null ? Value(isEnabled) : const Value.absent(),
        command: command != null ? Value(command) : const Value.absent(),
        args: args != null ? Value(args) : const Value.absent(),
        url: url != null ? Value(url) : const Value.absent(),
        headers: headers != null ? Value(headers) : const Value.absent(),
      ),
    );
  }

  Future<void> deleteServer(String id) {
    return (delete(mcpServers)..where((t) => t.id.equals(id))).go();
  }
}
