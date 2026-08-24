import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/simirouter_billing_client.dart';

/// 可覆盖的客户端（测试注入 fake endpoint）。
final simiRouterBillingClientProvider = Provider<SimiRouterBillingClient>((
  ref,
) {
  return const SimiRouterBillingClient();
});

class SimiRouterBillingState {
  const SimiRouterBillingState._({
    required this.snapshot,
    required this.account,
    this.error,
    this.accountError,
    this.loading = false,
    this.accountLoading = false,
  });

  const SimiRouterBillingState.idle()
    : snapshot = null,
      account = null,
      error = null,
      accountError = null,
      loading = false,
      accountLoading = false;

  final SimiRouterBillingSnapshot? snapshot;
  final SimiRouterAccountSnapshot? account;
  final String? error;
  final String? accountError;
  final bool loading;
  final bool accountLoading;

  SimiRouterBillingState copyWith({
    SimiRouterBillingSnapshot? snapshot,
    SimiRouterAccountSnapshot? account,
    String? error,
    String? accountError,
    bool? loading,
    bool? accountLoading,
  }) {
    return SimiRouterBillingState._(
      snapshot: snapshot ?? this.snapshot,
      account: account ?? this.account,
      error: error ?? this.error,
      accountError: accountError ?? this.accountError,
      loading: loading ?? this.loading,
      accountLoading: accountLoading ?? this.accountLoading,
    );
  }
}

final simiRouterBillingProvider =
    StateNotifierProvider<SimiRouterBillingNotifier, SimiRouterBillingState>((
      ref,
    ) {
      return SimiRouterBillingNotifier(ref);
    });

class SimiRouterBillingNotifier extends StateNotifier<SimiRouterBillingState> {
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
      final snapshot = await _ref
          .read(simiRouterBillingClientProvider)
          .fetch(baseUrl: baseUrl, apiKey: apiKey);
      state = SimiRouterBillingState._(
        snapshot: snapshot,
        account: state.account,
        accountError: state.accountError,
      );
    } catch (e) {
      state = SimiRouterBillingState._(
        snapshot: state.snapshot,
        error: e.toString(),
        account: state.account,
        accountError: state.accountError,
      );
    }
  }

  Future<void> refreshAccount({
    required String baseUrl,
    required String apiKey,
    String? newApiUser,
  }) async {
    if (baseUrl.trim().isEmpty ||
        apiKey.trim().isEmpty ||
        state.accountLoading) {
      return;
    }
    state = SimiRouterBillingState._(
      snapshot: state.snapshot,
      account: state.account,
      error: state.error,
      accountError: null,
      loading: state.loading,
      accountLoading: true,
    );
    try {
      final account = await _ref
          .read(simiRouterBillingClientProvider)
          .fetchAccount(
            baseUrl: baseUrl,
            apiKey: apiKey,
            newApiUser: newApiUser,
          );
      state = SimiRouterBillingState._(
        snapshot: state.snapshot,
        account: account,
        error: state.error,
        accountLoading: false,
      );
    } on SimiRouterBillingException catch (e) {
      state = SimiRouterBillingState._(
        snapshot: state.snapshot,
        account: state.account,
        error: state.error,
        accountError: e.message,
      );
    } catch (_) {
      state = SimiRouterBillingState._(
        snapshot: state.snapshot,
        account: state.account,
        error: state.error,
        accountError: '账号额度查询失败，请稍后重试',
      );
    }
  }
}
