import 'dart:convert';

import 'package:drift/drift.dart';
import '../../ai/model_capability.dart';
import '../app_database.dart';
import '../tables.dart';

part 'channel_dao.g.dart';

@DriftAccessor(tables: [ModelChannels, ChannelModels, Sessions, Messages])
class ChannelDao extends DatabaseAccessor<AppDatabase> with _$ChannelDaoMixin {
  ChannelDao(super.db);

  Future<List<ModelChannel>> getEnabledChannels() {
    return (select(
      modelChannels,
    )..where((t) => t.isEnabled.equals(true))).get();
  }

  Future<List<ModelChannel>> getAllChannels() {
    return select(modelChannels).get();
  }

  Future<List<ChannelModel>> getModelsByChannel(String channelId) {
    return (select(
      channelModels,
    )..where((t) => t.channelId.equals(channelId))).get();
  }

  Future<List<ChannelModelWithChannel>> getAllModels() async {
    final query =
        select(channelModels).join([
            innerJoin(
              modelChannels,
              modelChannels.id.equalsExp(channelModels.channelId),
            ),
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

  Future<List<ChannelModelWithChannel>> getChatModels() async {
    final query =
        select(channelModels).join([
            innerJoin(
              modelChannels,
              modelChannels.id.equalsExp(channelModels.channelId),
            ),
          ])
          ..where(modelChannels.isEnabled.equals(true))
          ..orderBy([OrderingTerm.asc(modelChannels.name)]);

    final results = await query.get();
    final models = results.map((row) {
      return ChannelModelWithChannel(
        channelModel: row.readTable(channelModels),
        channel: row.readTable(modelChannels),
      );
    }).toList();

    // 导入或旧版数据中的能力元数据可能已过时（例如把图片生成模型持久化为
    // `chat`）。同时基于实际模型名和存储能力应用严格选择器谓词，避免明确的
    // 媒体 / Embedding 专用模型进入聊天选择器，同时保留 Chat、Vision、Reasoner。
    return models
        .where(
          (model) => ModelCapability.isChatSelectableModel(
            modelId: model.channelModel.modelName,
            capability: model.channelModel.capability,
            capabilities: model.capabilities,
          ),
        )
        .toList();
  }

  Future<int> createChannel({
    required String id,
    required String name,
    required String baseUrl,
    required String apiKeyEncrypted,
    required String protocol,
  }) {
    return into(modelChannels).insert(
      ModelChannelsCompanion.insert(
        id: id,
        name: name,
        baseUrl: baseUrl,
        apiKeyEncrypted: apiKeyEncrypted,
        protocol: protocol,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> updateChannel(
    String id, {
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
    return transaction(() async {
      final channelModelIds = selectOnly(channelModels)
        ..addColumns([channelModels.id])
        ..where(channelModels.channelId.equals(id));

      await (update(sessions)
            ..where((t) => t.defaultChannelModelId.isInQuery(channelModelIds)))
          .write(const SessionsCompanion(defaultChannelModelId: Value(null)));
      await (update(messages)
            ..where((t) => t.channelModelId.isInQuery(channelModelIds)))
          .write(const MessagesCompanion(channelModelId: Value(null)));
      await (delete(channelModels)..where((t) => t.channelId.equals(id))).go();
      await (delete(modelChannels)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<int> addModel({
    required String id,
    required String channelId,
    required String modelName,
    String capability = ModelCapability.chat,
    Iterable<String> capabilities = const <String>[],
  }) {
    final normalizedCapability = ModelCapability.normalize(capability);
    final normalizedCapabilities = <String>{
      normalizedCapability,
      ...capabilities.map(ModelCapability.normalize),
    }.toList()..sort();
    return into(channelModels).insert(
      ChannelModelsCompanion.insert(
        id: id,
        channelId: channelId,
        modelName: modelName,
        capability: Value(normalizedCapability),
        capabilities: Value(jsonEncode(normalizedCapabilities)),
      ),
    );
  }

  Future<void> deleteModel(String id) {
    return transaction(() async {
      await (update(sessions)..where((t) => t.defaultChannelModelId.equals(id)))
          .write(const SessionsCompanion(defaultChannelModelId: Value(null)));
      await (update(messages)..where((t) => t.channelModelId.equals(id))).write(
        const MessagesCompanion(channelModelId: Value(null)),
      );
      await (delete(channelModels)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<void> setDefaultModel(String channelId, String modelId) async {
    await (update(channelModels)..where((t) => t.channelId.equals(channelId)))
        .write(const ChannelModelsCompanion(isDefault: Value(false)));
    await (update(channelModels)..where((t) => t.id.equals(modelId))).write(
      const ChannelModelsCompanion(isDefault: Value(true)),
    );
  }

  Future<ChannelModelWithChannel?> getModelWithChannel(String modelId) async {
    final query = select(channelModels).join([
      innerJoin(
        modelChannels,
        modelChannels.id.equalsExp(channelModels.channelId),
      ),
    ])..where(channelModels.id.equals(modelId));

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

  Set<String> get capabilities => decodeModelCapabilities(
    channelModel.capability,
    channelModel.capabilities,
  );

  String get displayLabel => '${channel.name} / ${channelModel.modelName}';
}

Set<String> decodeModelCapabilities(String? primary, String? encoded) {
  final result = <String>{ModelCapability.normalize(primary)};
  final raw = encoded?.trim();
  if (raw == null || raw.isEmpty) return result;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Iterable) {
      result.addAll(
        decoded
            .map((value) => ModelCapability.normalize(value?.toString()))
            .where(ModelCapability.all.contains),
      );
    }
  } catch (_) {
    // Corrupt or pre-migration metadata must not hide the primary capability.
  }
  return result;
}
