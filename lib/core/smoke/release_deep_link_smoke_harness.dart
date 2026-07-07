import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../crypto/key_encryptor.dart';
import '../database/app_database.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/session_provider.dart';

const releaseDeepLinkSmokeEnabled = bool.fromEnvironment(
  'SIMICHAT_RELEASE_DEEP_LINK_SMOKE',
);
const _releaseDeepLinkSmokeRunId = String.fromEnvironment(
  'SIMICHAT_RELEASE_DEEP_LINK_SMOKE_RUN_ID',
  defaultValue: 'manual',
);

const releaseDeepLinkSmokeSettingsReadyMarker =
    'SIMICHAT_RELEASE_DEEP_LINK_SETTINGS_READY';
const releaseDeepLinkSmokeDefaultSessionId =
    'ios-release-deep-link-default-session';
const releaseDeepLinkSmokeTargetSessionId =
    'ios-release-deep-link-target-session';
const releaseDeepLinkSmokeTargetSessionTitle = 'iOS Release Deep Link Target';

Future<void> runReleaseDeepLinkSmokeApp({
  required Widget Function(List<NavigatorObserver> observers) buildApp,
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await _seedDeepLinkSmokeData(db);
  await _writeDeepLinkSmokeResult({'status': 'starting'});
  final observer = _ReleaseDeepLinkNavigatorObserver();
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        activeSessionIdProvider.overrideWith(
          (ref) => releaseDeepLinkSmokeDefaultSessionId,
        ),
      ],
      child: _ReleaseDeepLinkSmokeBootstrap(
        db: db,
        observer: observer,
        child: buildApp([observer]),
      ),
    ),
  );
}

Future<void> _seedDeepLinkSmokeData(AppDatabase db) async {
  await db.channelDao.createChannel(
    id: 'ios-release-deep-link-channel',
    name: 'iOS Release Deep Link Mock',
    baseUrl: 'https://example.invalid/v1',
    apiKeyEncrypted: KeyEncryptor.encrypt('ios-release-deep-link-test-key'),
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: 'ios-release-deep-link-model',
    channelId: 'ios-release-deep-link-channel',
    modelName: 'ios-release-deep-link-model',
  );
  await db.sessionDao.createSession(
    id: releaseDeepLinkSmokeTargetSessionId,
    defaultChannelModelId: 'ios-release-deep-link-model',
  );
  await db.sessionDao.updateTitle(
    releaseDeepLinkSmokeTargetSessionId,
    releaseDeepLinkSmokeTargetSessionTitle,
  );
  await db.sessionDao.createSession(
    id: releaseDeepLinkSmokeDefaultSessionId,
    defaultChannelModelId: 'ios-release-deep-link-model',
  );
  await db.sessionDao.updateTitle(
    releaseDeepLinkSmokeDefaultSessionId,
    'iOS Release Deep Link Default',
  );
}

class _ReleaseDeepLinkSmokeBootstrap extends ConsumerStatefulWidget {
  const _ReleaseDeepLinkSmokeBootstrap({
    required this.db,
    required this.observer,
    required this.child,
  });

  final AppDatabase db;
  final _ReleaseDeepLinkNavigatorObserver observer;
  final Widget child;

  @override
  ConsumerState<_ReleaseDeepLinkSmokeBootstrap> createState() =>
      _ReleaseDeepLinkSmokeBootstrapState();
}

class _ReleaseDeepLinkSmokeBootstrapState
    extends ConsumerState<_ReleaseDeepLinkSmokeBootstrap> {
  ProviderSubscription<String?>? _activeSessionSubscription;
  bool _settingsReady = false;
  bool _passed = false;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    widget.observer.onSettingsRoute = _markSettingsReady;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeSessionSubscription = ref.listenManual<String?>(
        activeSessionIdProvider,
        (_, next) => unawaited(_handleActiveSession(next)),
        fireImmediately: true,
      );
    });
  }

  @override
  void dispose() {
    widget.observer.onSettingsRoute = null;
    _activeSessionSubscription?.close();
    unawaited(widget.db.close());
    super.dispose();
  }

  Future<void> _markSettingsReady() async {
    if (_settingsReady) return;
    _settingsReady = true;
    await _writeDeepLinkSmokeResult({
      'status': 'settings_ready',
      'marker': releaseDeepLinkSmokeSettingsReadyMarker,
      'pid': pid,
      'activeSessionId': ref.read(activeSessionIdProvider),
    });
    await _handleActiveSession(ref.read(activeSessionIdProvider));
  }

  Future<void> _handleActiveSession(String? sessionId) async {
    if (!_settingsReady || _passed) return;
    if (sessionId != releaseDeepLinkSmokeTargetSessionId) return;
    final session = await ref
        .read(sessionDaoProvider)
        .getSession(releaseDeepLinkSmokeTargetSessionId);
    final targetTitle = session?.title;
    if (targetTitle != releaseDeepLinkSmokeTargetSessionTitle) {
      await _writeDeepLinkSmokeResult({
        'status': 'failed',
        'reason': 'target_session_title_mismatch',
        'activeSessionId': sessionId,
        'targetTitle': targetTitle,
      });
      return;
    }
    _passed = true;
    await _writeDeepLinkSmokeResult({
      'status': 'passed',
      'marker': releaseDeepLinkSmokeSettingsReadyMarker,
      'pid': pid,
      'activeSessionId': sessionId,
      'targetTitle': targetTitle,
      'elapsedMs': _startedAt == null
          ? null
          : DateTime.now().difference(_startedAt!).inMilliseconds,
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ReleaseDeepLinkNavigatorObserver extends NavigatorObserver {
  VoidCallback? onSettingsRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name == '/settings') {
      onSettingsRoute?.call();
    }
  }
}

Future<void> _writeDeepLinkSmokeResult(Map<String, Object?> data) async {
  try {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(root.path, 'ai_chat', 'release_deep_link_smoke'),
    );
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'ios-release-deep-link-smoke.json'));
    final body = <String, Object?>{
      'runId': _releaseDeepLinkSmokeRunId,
      'updatedAt': DateTime.now().toIso8601String(),
      ...data,
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(body),
      flush: true,
    );
  } catch (error) {
    debugPrint('Release deep link smoke result write failed: $error');
  }
}
