import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/channel_quota_client.dart';

final channelQuotaClientProvider = Provider<ChannelQuotaClient>((ref) {
  return const ChannelQuotaClient();
});

class ChannelQuotaState {
  const ChannelQuotaState({this.snapshot, this.error, this.loading = false});

  final ChannelQuotaSnapshot? snapshot;
  final String? error;
  final bool loading;
}

final channelQuotaProvider = StateNotifierProvider.autoDispose
    .family<ChannelQuotaNotifier, ChannelQuotaState, String>((ref, channelId) {
      return ChannelQuotaNotifier(ref, channelId);
    });

class ChannelQuotaNotifier extends StateNotifier<ChannelQuotaState> {
  ChannelQuotaNotifier(this._ref, this.channelId)
    : super(const ChannelQuotaState());

  final Ref _ref;
  final String channelId;

  void setError(String message) {
    state = ChannelQuotaState(snapshot: state.snapshot, error: message);
  }

  Future<void> refresh({
    required String protocol,
    required String baseUrl,
    required String apiKey,
  }) async {
    if (state.loading) return;
    state = ChannelQuotaState(snapshot: state.snapshot, loading: true);
    try {
      final snapshot = await _ref
          .read(channelQuotaClientProvider)
          .fetch(protocol: protocol, baseUrl: baseUrl, apiKey: apiKey);
      state = ChannelQuotaState(snapshot: snapshot);
    } on ChannelQuotaException catch (error) {
      state = ChannelQuotaState(snapshot: state.snapshot, error: error.message);
    } catch (_) {
      state = ChannelQuotaState(
        snapshot: state.snapshot,
        error: '额度查询失败，请稍后重试',
      );
    }
  }
}
