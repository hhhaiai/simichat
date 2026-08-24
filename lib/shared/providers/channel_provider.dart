import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/channel_dao.dart';
import 'database_provider.dart';

/// 用户没有显式选择聊天模型时使用的低成本默认模型。
///
/// 这里只选择已经存在于启用渠道中的模型，不会凭空创建渠道、模型或凭据。
const kDefaultChatModelName = 'gpt-5.3-codex-spark';

/// 解析本次聊天应使用的默认模型。
///
/// 已选择且仍可用的模型永远优先；只有选择为空或模型已经被删除时，才回退到
/// [kDefaultChatModelName]。兼容网关返回的 `provider/model` 命名，但不会把
/// 名字相似的其它 Codex 模型误认为默认值。
String? resolvePreferredChatModelId(
  List<ChannelModelWithChannel> models, {
  required String? selectedModelId,
}) {
  final selected = selectedModelId?.trim();
  if (selected != null &&
      selected.isNotEmpty &&
      models.any((model) => model.channelModel.id == selected)) {
    return selected;
  }

  for (final model in models) {
    final name = model.channelModel.modelName.trim().toLowerCase();
    final leaf = name.split('/').last;
    if (name == kDefaultChatModelName || leaf == kDefaultChatModelName) {
      return model.channelModel.id;
    }
  }
  return null;
}

/// 所有模型列表（跨渠道，不去重）
final allModelsProvider = FutureProvider<List<ChannelModelWithChannel>>((ref) {
  return ref.watch(channelDaoProvider).getChatModels();
});

/// All models belonging to enabled channels, including media-only and
/// embedding rows.  The chat selector must continue to use
/// [allModelsProvider]; settings pages that configure a non-chat route use
/// this unfiltered catalog instead.
final allConfiguredModelsProvider =
    FutureProvider<List<ChannelModelWithChannel>>((ref) {
      return ref.watch(channelDaoProvider).getAllModels();
    });

/// 所有渠道列表
final channelsProvider = FutureProvider<List<ModelChannel>>((ref) {
  return ref.watch(channelDaoProvider).getAllChannels();
});

/// 单个渠道的模型列表
final modelsByChannelProvider = FutureProvider.autoDispose
    .family<List<ChannelModel>, String>((ref, channelId) {
      return ref.watch(channelDaoProvider).getModelsByChannel(channelId);
    });

/// 当前选中的模型（channel_model_id）
final selectedModelIdProvider = StateProvider<String?>((ref) => null);

/// 刷新模型列表
void refreshModels(WidgetRef ref) {
  ref.invalidate(allModelsProvider);
  ref.invalidate(allConfiguredModelsProvider);
  ref.invalidate(channelsProvider);
}

void refreshChannelModels(WidgetRef ref, String channelId) {
  refreshModels(ref);
  ref.invalidate(modelsByChannelProvider(channelId));
}
