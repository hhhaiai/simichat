import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/simirouter_billing_client.dart';

/// 可覆盖的客户端（测试注入 fake endpoint）。
final simiRouterBillingClientProvider =
    Provider<SimiRouterBillingClient>((ref) {
      return const SimiRouterBillingClient();
    });

class SimiRouterBillingState {
  const SimiRouterBillingState._({
    required this.snapshot,
    this.error,
    this.loading = false,
  });

  const SimiRouterBillingState.idle()
    : snapshot = null,
      error = null,
      loading = false;

  final SimiRouterBillingSnapshot? snapshot;
  final String? error;
  final bool loading;

  SimiRouterBillingState copyWith({
    SimiRouterBillingSnapshot? snapshot,
    String? error,
    bool? loading,
  }) {
    return SimiRouterBillingState._(
      snapshot: snapshot ?? this.snapshot,
      error: error ?? this.error,
      loading: loading ?? this.loading,
    );
  }
}

final simiRouterBillingProvider =
    StateNotifierProvider<SimiRouterBillingNotifier, SimiRouterBillingState>((
      ref,
    ) {
      return SimiRouterBillingNotifier(ref);
    });

class SimiRouterBillingNotifier
    extends StateNotifier<SimiRouterBillingState> {
  SimiRouterBillingNotifier(this._ref)
    : super(const SimiRouterBillingState.idle());

  final Ref _ref;

  /// 拉取用量；baseUrl / apiKey 为空时保持 idle（不产生请求）。
  Future<void> refresh({
    required String baseUrl,
    required String apiKey,
  }) async {
    if (baseUrl.trim().isEmpty || apiKey.trim().isEmpty) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final snapshot = await _ref.read(simiRouterBillingClientProvider).fetch(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      state = SimiRouterBillingState._(snapshot: snapshot);
    } catch (e) {
      state = SimiRouterBillingState._(
        snapshot: state.snapshot,
        error: e.toString(),
      );
    }
  }
}
