import 'dart:async';

import 'package:ai_chat_app/shared/providers/connectivity_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  test(
    'connectivity result lists only count online when a transport exists',
    () {
      expect(isOnlineConnectivityResults(const []), isFalse);
      expect(
        isOnlineConnectivityResults(const [ConnectivityResult.none]),
        isFalse,
      );
      expect(
        isOnlineConnectivityResults(const [ConnectivityResult.wifi]),
        isTrue,
      );
      expect(
        isOnlineConnectivityResults(const [
          ConnectivityResult.none,
          ConnectivityResult.mobile,
        ]),
        isTrue,
      );
    },
  );

  test(
    'connectivity provider emits initial platform check before changes',
    () async {
      final monitor = _FakeConnectivityMonitor(
        initialResults: const [ConnectivityResult.none],
      );
      final container = ProviderContainer(
        overrides: [connectivityMonitorProvider.overrideWithValue(monitor)],
      );
      addTearDown(container.dispose);
      addTearDown(monitor.dispose);

      expect(await container.read(connectivityProvider.future), const [
        ConnectivityResult.none,
      ]);
      expect(container.read(isOnlineProvider), isFalse);

      monitor.emit(const [ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(isOnlineProvider), isTrue);
      expect(monitor.checkCount, 1);
    },
  );

  test(
    'connectivity provider keeps listening when initial check fails',
    () async {
      final monitor = _FakeConnectivityMonitor(
        initialResults: const [ConnectivityResult.none],
        failInitialCheck: true,
      );
      final container = ProviderContainer(
        overrides: [connectivityMonitorProvider.overrideWithValue(monitor)],
      );
      addTearDown(container.dispose);
      addTearDown(monitor.dispose);

      expect(container.read(isOnlineProvider), isTrue);
      await Future<void>.delayed(Duration.zero);

      monitor.emit(const [ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(isOnlineProvider), isFalse);
      expect(monitor.checkCount, 1);
    },
  );
}

class _FakeConnectivityMonitor implements ConnectivityMonitor {
  _FakeConnectivityMonitor({
    required this.initialResults,
    this.failInitialCheck = false,
  });

  final List<ConnectivityResult> initialResults;
  final bool failInitialCheck;
  final _controller = StreamController<List<ConnectivityResult>>();
  int checkCount = 0;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    checkCount += 1;
    if (failInitialCheck) {
      throw StateError('initial connectivity check failed');
    }
    return initialResults;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emit(List<ConnectivityResult> results) => _controller.add(results);

  Future<void> dispose() => _controller.close();
}
