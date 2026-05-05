import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'channel_dao.g.dart';

@DriftAccessor(tables: [ModelChannels, ChannelModels])
class ChannelDao extends DatabaseAccessor<AppDatabase> with _$ChannelDaoMixin {
  ChannelDao(super.db);

  Future<List<ModelChannel>> getEnabledChannels() {
    return (select(modelChannels)..where((t) => t.isEnabled.equals(true))).get();
  }

  Future<List<ModelChannel>> getAllChannels() {
    return select(modelChannels).get();
  }

  Future<List<ChannelModel>> getModelsByChannel(String channelId) {
    return (select(channelModels)..where((t) => t.channelId.equals(channelId)))
        .get();
  }

  Future<List<ChannelModelWithChannel>> getAllModels() async {
    final query = select(channelModels).join([
      innerJoin(modelChannels,
          modelChannels.id.equalsExp(channelModels.channelId)),
    ])
      ..where(modelChannels.isEnabled.equals(true))
      ..orderBy([OrderingTerm.asc(modelChannels.name)]);

    final results = await query.get();
    return results.map((row) {
      return ChannelModelWithChannel(
        channelModel: row.readTable(channelModels),
        channel: row.readTable(modelChannels),
      );
    }).toList();
  }

  Future<int> createChannel({
    required String id,
    required String name,
    required String baseUrl,
    required String apiKeyEncrypted,
    required String protocol,
  }) {
    return into(modelChannels).insert(ModelChannelsCompanion.insert(
      id: id,
      name: name,
      baseUrl: baseUrl,
      apiKeyEncrypted: apiKeyEncrypted,
      protocol: protocol,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> updateChannel(String id, {
    String? name,
    String? baseUrl,
    String? apiKeyEncrypted,
    String? protocol,
    bool? isEnabled,
  }) {
    return (update(modelChannels)..where((t) => t.id.equals(id))).write(
      ModelChannelsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        baseUrl: baseUrl != null ? Value(baseUrl) : const Value.absent(),
        apiKeyEncrypted: apiKeyEncrypted != null
            ? Value(apiKeyEncrypted)
            : const Value.absent(),
        protocol: protocol != null ? Value(protocol) : const Value.absent(),
        isEnabled: isEnabled != null ? Value(isEnabled) : const Value.absent(),
      ),
    );
  }

  Future<void> deleteChannel(String id) {
    return (delete(modelChannels)..where((t) => t.id.equals(id))).go();
  }

  Future<int> addModel({
    required String id,
    required String channelId,
    required String modelName,
  }) {
    return into(channelModels).insert(ChannelModelsCompanion.insert(
      id: id,
      channelId: channelId,
      modelName: modelName,
    ));
  }

  Future<void> deleteModel(String id) {
    return (delete(channelModels)..where((t) => t.id.equals(id))).go();
  }

  Future<void> setDefaultModel(String channelId, String modelId) async {
    await (update(channelModels)..where((t) => t.channelId.equals(channelId)))
        .write(const ChannelModelsCompanion(isDefault: Value(false)));
    await (update(channelModels)..where((t) => t.id.equals(modelId)))
        .write(const ChannelModelsCompanion(isDefault: Value(true)));
  }

  Future<ChannelModelWithChannel?> getModelWithChannel(String modelId) async {
    final query = select(channelModels).join([
      innerJoin(modelChannels,
          modelChannels.id.equalsExp(channelModels.channelId)),
    ])
      ..where(channelModels.id.equals(modelId));

    final results = await query.get();
    if (results.isEmpty) return null;
    final row = results.first;
    return ChannelModelWithChannel(
      channelModel: row.readTable(channelModels),
      channel: row.readTable(modelChannels),
    );
  }
}

class ChannelModelWithChannel {
  final ChannelModel channelModel;
  final ModelChannel channel;

  const ChannelModelWithChannel({
    required this.channelModel,
    required this.channel,
  });

  String get displayLabel => '${channel.name} / ${channelModel.modelName}';
}
