import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../../shared/providers/connectivity_provider.dart';
import '../../shared/providers/database_provider.dart';

const releaseNetworkSmokeEnabled = bool.fromEnvironment(
  'SIMICHAT_RELEASE_NETWORK_SMOKE',
);
const _releaseNetworkSmokeRunId = String.fromEnvironment(
  'SIMICHAT_RELEASE_NETWORK_SMOKE_RUN_ID',
  defaultValue: 'manual',
);

const _readyMarker = 'SIMICHAT_RELEASE_NETWORK_READY';
const _offlineDraftMessage = '当前网络不可用，已保留输入，联网后可重试';
const _restoredDraftMessage = '网络已恢复，可发送保留的输入';

Future<void> runReleaseNetworkSmokeApp({required Widget child}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final monitor = _ReleaseNetworkSmokeConnectivityMonitor(const [
    ConnectivityResult.wifi,
  ]);
  await _writeNetworkSmokeResult({'status': 'starting'});
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        connectivityMonitorProvider.overrideWithValue(monitor),
      ],
      child: _ReleaseNetworkSmokeBootstrap(
        db: db,
        monitor: monitor,
        child: child,
      ),
    ),
  );
}

class _ReleaseNetworkSmokeBootstrap extends ConsumerStatefulWidget {
  const _ReleaseNetworkSmokeBootstrap({
    required this.db,
    required this.monitor,
    required this.child,
  });

  final AppDatabase db;
  final _ReleaseNetworkSmokeConnectivityMonitor monitor;
  final Widget child;

  @override
  ConsumerState<_ReleaseNetworkSmokeBootstrap> createState() =>
      _ReleaseNetworkSmokeBootstrapState();
}

class _ReleaseNetworkSmokeBootstrapState
    extends ConsumerState<_ReleaseNetworkSmokeBootstrap> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started) return;
      _started = true;
      unawaited(_runSmoke());
    });
  }

  @override
  void dispose() {
    unawaited(widget.monitor.dispose());
    unawaited(widget.db.close());
    super.dispose();
  }

  Future<void> _runSmoke() async {
    final startedAt = DateTime.now();
    try {
      await _writeNetworkSmokeResult({
        'status': 'observing',
        'stage': 'initial_online',
      });
      await _waitForOnlineState(expected: true);

      widget.monitor.emit(const [ConnectivityResult.none]);
      await _waitForOnlineState(expected: false);
      await _writeNetworkSmokeResult({
        'status': 'ready',
        'marker': _readyMarker,
        'stage': 'offline_observed',
        'connectivity': 'none',
        'offlineMessage': _offlineDraftMessage,
      });

      widget.monitor.emit(const [ConnectivityResult.wifi]);
      await _waitForOnlineState(expected: true);
      await _writeNetworkSmokeResult({
        'status': 'passed',
        'marker': _readyMarker,
        'stage': 'restored_online',
        'connectivity': 'wifi',
        'offlineMessage': _offlineDraftMessage,
        'restoredMessage': _restoredDraftMessage,
        'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
      });
    } catch (error, stackTrace) {
      await _writeNetworkSmokeResult({
        'status': 'failed',
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
    }
  }

  Future<void> _waitForOnlineState({
    required bool expected,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (ref.read(isOnlineProvider) == expected) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('timed out waiting for isOnlineProvider=$expected');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ReleaseNetworkSmokeConnectivityMonitor implements ConnectivityMonitor {
  _ReleaseNetworkSmokeConnectivityMonitor(this._results);

  List<ConnectivityResult> _results;
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _results;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emit(List<ConnectivityResult> results) {
    _results = results;
    _controller.add(results);
  }

  Future<void> dispose() => _controller.close();
}

Future<void> _writeNetworkSmokeResult(Map<String, Object?> data) async {
  try {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(root.path, 'ai_chat', 'release_network_smoke'),
    );
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'ios-release-network-smoke.json'));
    final body = <String, Object?>{
      'runId': _releaseNetworkSmokeRunId,
      'updatedAt': DateTime.now().toIso8601String(),
      ...data,
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(body),
      flush: true,
    );
  } catch (error) {
    debugPrint('Release network smoke result write failed: $error');
  }
}
