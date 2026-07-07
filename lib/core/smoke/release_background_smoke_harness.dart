import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../../shared/providers/database_provider.dart';

const releaseBackgroundSmokeEnabled = bool.fromEnvironment(
  'SIMICHAT_RELEASE_BACKGROUND_SMOKE',
);
const _releaseBackgroundSmokeRunId = String.fromEnvironment(
  'SIMICHAT_RELEASE_BACKGROUND_SMOKE_RUN_ID',
  defaultValue: 'manual',
);

const _readyMarker = 'SIMICHAT_RELEASE_BACKGROUND_READY';

Future<void> runReleaseBackgroundSmokeApp({required Widget child}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await _writeBackgroundSmokeResult({'status': 'starting'});
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: _ReleaseBackgroundSmokeBootstrap(db: db, child: child),
    ),
  );
}

class _ReleaseBackgroundSmokeBootstrap extends StatefulWidget {
  const _ReleaseBackgroundSmokeBootstrap({
    required this.db,
    required this.child,
  });

  final AppDatabase db;
  final Widget child;

  @override
  State<_ReleaseBackgroundSmokeBootstrap> createState() =>
      _ReleaseBackgroundSmokeBootstrapState();
}

class _ReleaseBackgroundSmokeBootstrapState
    extends State<_ReleaseBackgroundSmokeBootstrap>
    with WidgetsBindingObserver {
  Timer? _ticker;
  DateTime? _readyAt;
  DateTime? _lastTickAt;
  bool _passed = false;
  bool _sawNonResumedLifecycle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_markReady());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.db.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _sawNonResumedLifecycle = true;
      unawaited(
        _writeBackgroundSmokeResult({
          'status': 'observing',
          'stage': 'non_resumed',
          'lifecycleState': state.name,
        }),
      );
    } else {
      unawaited(_maybePass(reason: 'lifecycle_resumed'));
    }
  }

  Future<void> _markReady() async {
    final now = DateTime.now();
    _readyAt = now;
    _lastTickAt = now;
    await _writeBackgroundSmokeResult({
      'status': 'ready',
      'marker': _readyMarker,
      'pid': pid,
      'lifecycleState':
          WidgetsBinding.instance.lifecycleState?.name ??
          AppLifecycleState.resumed.name,
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      unawaited(_onTick());
    });
  }

  Future<void> _onTick() async {
    final previous = _lastTickAt;
    final now = DateTime.now();
    _lastTickAt = now;
    if (previous == null || _readyAt == null) return;
    final gapMs = now.difference(previous).inMilliseconds;
    if (gapMs >= 1500) {
      await _maybePass(reason: 'process_suspend_resume_gap', gapMs: gapMs);
    }
  }

  Future<void> _maybePass({required String reason, int? gapMs}) async {
    if (_passed || _readyAt == null) return;
    final lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    if (lifecycleState != AppLifecycleState.resumed) return;
    _passed = true;
    _ticker?.cancel();
    await _writeBackgroundSmokeResult({
      'status': 'passed',
      'marker': _readyMarker,
      'pid': pid,
      'reason': reason,
      'gapMs': gapMs,
      'sawNonResumedLifecycle': _sawNonResumedLifecycle,
      'lifecycleState': AppLifecycleState.resumed.name,
      'elapsedMs': DateTime.now().difference(_readyAt!).inMilliseconds,
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> _writeBackgroundSmokeResult(Map<String, Object?> data) async {
  try {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(root.path, 'ai_chat', 'release_background_smoke'),
    );
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'ios-release-background-smoke.json'));
    final body = <String, Object?>{
      'runId': _releaseBackgroundSmokeRunId,
      'updatedAt': DateTime.now().toIso8601String(),
      ...data,
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(body),
      flush: true,
    );
  } catch (error) {
    debugPrint('Release background smoke result write failed: $error');
  }
}
