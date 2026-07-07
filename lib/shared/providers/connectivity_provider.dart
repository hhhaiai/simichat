import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ConnectivityMonitor {
  Future<List<ConnectivityResult>> checkConnectivity();
  Stream<List<ConnectivityResult>> get onConnectivityChanged;
}

class ConnectivityPlusMonitor implements ConnectivityMonitor {
  ConnectivityPlusMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() {
    return _connectivity.checkConnectivity();
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged;
  }
}

final connectivityMonitorProvider = Provider<ConnectivityMonitor>((ref) {
  return ConnectivityPlusMonitor();
});

/// 网络状态 Provider
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) async* {
  final monitor = ref.watch(connectivityMonitorProvider);
  try {
    yield await monitor.checkConnectivity();
  } catch (_) {
    // 保持 isOnlineProvider 的保守默认值，并继续等待后续网络变化事件。
  }
  yield* monitor.onConnectivityChanged;
});

bool isOnlineConnectivityResults(List<ConnectivityResult> results) {
  return results.any((result) => result != ConnectivityResult.none);
}

/// 当前是否在线
final isOnlineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity.when(
    loading: () => true,
    error: (_, _) => true,
    data: isOnlineConnectivityResults,
  );
});
