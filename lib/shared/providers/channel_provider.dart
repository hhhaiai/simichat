import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/channel_dao.dart';
import 'database_provider.dart';

/// 所有模型列表（跨渠道，不去重）
final allModelsProvider = FutureProvider<List<ChannelModelWithChannel>>((ref) {
  return ref.watch(channelDaoProvider).getAllModels();
});

/// 所有渠道列表
final channelsProvider = FutureProvider<List<ModelChannel>>((ref) {
  return ref.watch(channelDaoProvider).getAllChannels();
});

/// 当前选中的模型（channel_model_id）
final selectedModelIdProvider = StateProvider<String?>((ref) => null);

/// 刷新模型列表
void refreshModels(WidgetRef ref) {
  ref.invalidate(allModelsProvider);
  ref.invalidate(channelsProvider);
}
