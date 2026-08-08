import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/archive/structured_data_backup.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/relay/openai_compatible_relay_server.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/openai_relay_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'relay provider starts loopback server and persists encrypted token',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedRelayModel(db);

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(openAiRelayControllerProvider.notifier);
      await notifier.ready;

      final token = generateOpenAiRelayToken();
      await notifier.start(token: token, requestedPort: 0);

      final state = container.read(openAiRelayControllerProvider);
      expect(state.isRunning, isTrue);
      expect(state.bindMode, OpenAiRelayBindMode.loopback);
      expect(state.baseUri!.host, '127.0.0.1');
      expect(state.openAiBaseUrl, endsWith('/v1'));

      final unauthorized = await _get(state.baseUri!.resolve('/v1/models'));
      expect(unauthorized.statusCode, HttpStatus.unauthorized);
      expect(unauthorized.body, isNot(contains('chat-model')));

      final authorized = await _get(
        state.baseUri!.resolve('/v1/models'),
        token: token,
      );
      expect(authorized.statusCode, HttpStatus.ok);
      final payload = jsonDecode(authorized.body) as Map<String, dynamic>;
      expect(payload['object'], 'list');
      expect(jsonEncode(payload), contains('chat-model'));

      final audited = container
          .read(openAiRelayControllerProvider)
          .auditSummary;
      expect(audited.totalRequests, 2);
      expect(audited.authorizedRequests, 1);
      expect(audited.rejectedRequests, 1);
      expect(audited.unauthorizedRequests, 1);
      expect(audited.compactSummary, contains('已处理 2 次'));

      final prefs = await SharedPreferences.getInstance();
      final usage = container.read(openAiRelayControllerProvider).usageStats;
      expect(usage.totalRequests, 2);
      expect(usage.successfulRequests, 1);
      expect(usage.rejectedRequests, 1);
      expect(usage.unauthorizedRequests, 1);
      expect(usage.compactSummary, contains('累计 2 次'));
      await _waitForPreference(kOpenAiRelayUsageStatsStorageKey);
      final persistedUsage = OpenAiRelayUsageStats.fromJson(
        jsonDecode(prefs.getString(kOpenAiRelayUsageStatsStorageKey)!)
            as Map<String, dynamic>,
      );
      expect(persistedUsage.totalRequests, 2);
      expect(persistedUsage.successfulRequests, 1);
      expect(persistedUsage.unauthorizedRequests, 1);
      expect(
        container.read(openAiRelayControllerProvider).auditLog,
        hasLength(2),
      );
      expect(
        container.read(openAiRelayControllerProvider).auditLog.first.path,
        '/v1/models',
      );
      await _waitForPreference(kOpenAiRelayAuditLogStorageKey);
      final persistedAudit =
          jsonDecode(prefs.getString(kOpenAiRelayAuditLogStorageKey)!)
              as List<dynamic>;
      expect(persistedAudit, hasLength(2));
      expect(jsonEncode(persistedAudit), isNot(contains(token)));
      expect(
        jsonEncode(persistedAudit),
        isNot(contains('test-key-local-relay')),
      );

      final exportedAudit =
          jsonDecode(
                notifier.exportAuditReportJson(
                  generatedAt: DateTime.utc(2026, 6, 27),
                ),
              )
              as Map<String, dynamic>;
      expect(exportedAudit['schema'], 'simichat.openai_relay_audit.v1');
      expect(exportedAudit['auditLogCount'], 2);
      expect(jsonEncode(exportedAudit), isNot(contains(token)));
      expect(
        jsonEncode(exportedAudit),
        isNot(contains('test-key-local-relay')),
      );
      expect(
        jsonEncode(exportedAudit),
        isNot(contains('https://api.example.com')),
      );

      final encryptedToken = prefs.getString(kOpenAiRelayTokenStorageKey);
      expect(encryptedToken, isNotNull);
      expect(encryptedToken, isNot(contains(token)));
      expect(KeyEncryptor.decrypt(encryptedToken!), token);
      expect(
        kStructuredPreferenceKeys,
        isNot(contains(kOpenAiRelayTokenStorageKey)),
      );
      expect(
        kStructuredPreferenceKeys,
        isNot(contains(kOpenAiRelayBindModeStorageKey)),
      );
      expect(
        kStructuredPreferenceKeys,
        isNot(contains(kOpenAiRelayRouteStrategyStorageKey)),
      );
      expect(
        kStructuredPreferenceKeys,
        isNot(contains(kOpenAiRelayMaxConcurrentRequestsStorageKey)),
      );
      expect(
        kStructuredPreferenceKeys,
        isNot(contains(kOpenAiRelayUsageStatsStorageKey)),
      );
      expect(
        kStructuredPreferenceKeys,
        isNot(contains(kOpenAiRelayAuditLogStorageKey)),
      );

      await notifier.clearUsageStats();
      expect(
        container.read(openAiRelayControllerProvider).usageStats.totalRequests,
        0,
      );
      expect(prefs.getString(kOpenAiRelayUsageStatsStorageKey), isNull);
      await notifier.clearAuditLog();
      expect(container.read(openAiRelayControllerProvider).auditLog, isEmpty);
      expect(prefs.getString(kOpenAiRelayAuditLogStorageKey), isNull);

      await notifier.stop();
      expect(container.read(openAiRelayControllerProvider).isRunning, isFalse);
    },
  );

  test('relay provider rejects weak token and invalid port', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(openAiRelayControllerProvider.notifier);
    await notifier.ready;

    await expectLater(
      notifier.start(token: 'short'),
      throwsA(isA<OpenAiCompatibleRelayException>()),
    );
    await expectLater(
      notifier.saveConfig(token: '1234567890123456', requestedPort: 70000),
      throwsA(isA<OpenAiCompatibleRelayException>()),
    );
    expect(container.read(openAiRelayControllerProvider).isRunning, isFalse);
  });

  test(
    'relay provider persists configurable concurrency and rejects invalid values',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(openAiRelayControllerProvider.notifier);
      await notifier.ready;

      expect(
        container.read(openAiRelayControllerProvider).maxConcurrentRequests,
        kOpenAiRelayDefaultConcurrentRequests,
      );

      await notifier.setMaxConcurrentRequests(8);
      expect(
        container.read(openAiRelayControllerProvider).maxConcurrentRequests,
        8,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(kOpenAiRelayMaxConcurrentRequestsStorageKey), 8);

      await notifier.generateAndSaveToken();
      expect(prefs.getInt(kOpenAiRelayMaxConcurrentRequestsStorageKey), 8);

      await expectLater(
        notifier.setMaxConcurrentRequests(0),
        throwsA(isA<OpenAiCompatibleRelayException>()),
      );
      await expectLater(
        notifier.setMaxConcurrentRequests(33),
        throwsA(isA<OpenAiCompatibleRelayException>()),
      );
      expect(
        container.read(openAiRelayControllerProvider).maxConcurrentRequests,
        8,
      );
      expect(
        kStructuredPreferenceKeys,
        isNot(contains(kOpenAiRelayMaxConcurrentRequestsStorageKey)),
      );
      expect(
        kStructuredPreferenceKeys,
        isNot(contains(kOpenAiRelayUsageStatsStorageKey)),
      );
      expect(
        kStructuredPreferenceKeys,
        isNot(contains(kOpenAiRelayAuditLogStorageKey)),
      );
      expect(
        kStructuredPreferenceKeys,
        isNot(contains(kOpenAiRelayRemoteImageDownloadStorageKey)),
      );

      await notifier.setAllowRemoteImageDownload(true);
      expect(
        container.read(openAiRelayControllerProvider).allowRemoteImageDownload,
        isTrue,
      );
      expect(prefs.getBool(kOpenAiRelayRemoteImageDownloadStorageKey), isTrue);

      final reloaded = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(reloaded.dispose);
      await reloaded.read(openAiRelayControllerProvider.notifier).ready;
      expect(
        reloaded.read(openAiRelayControllerProvider).maxConcurrentRequests,
        8,
      );
      expect(
        reloaded.read(openAiRelayControllerProvider).allowRemoteImageDownload,
        isTrue,
      );
    },
  );

  test(
    'relay provider binds LAN only after local network mode is selected',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedRelayModel(db);

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(openAiRelayControllerProvider.notifier);
      await notifier.ready;

      final token = generateOpenAiRelayToken();
      await notifier.start(token: token, requestedPort: 0);
      expect(
        container.read(openAiRelayControllerProvider).baseUri!.host,
        InternetAddress.loopbackIPv4.address,
      );

      await notifier.setBindMode(OpenAiRelayBindMode.localNetwork);
      final lanState = container.read(openAiRelayControllerProvider);
      expect(lanState.bindMode, OpenAiRelayBindMode.localNetwork);
      expect(lanState.baseUri!.host, InternetAddress.anyIPv4.address);

      final authorized = await _get(
        Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: lanState.baseUri!.port,
          path: '/v1/models',
        ),
        token: token,
      );
      expect(authorized.statusCode, HttpStatus.ok);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(kOpenAiRelayBindModeStorageKey),
        OpenAiRelayBindMode.localNetwork.storageValue,
      );

      await notifier.setBindMode(OpenAiRelayBindMode.loopback);
      final loopbackState = container.read(openAiRelayControllerProvider);
      expect(loopbackState.bindMode, OpenAiRelayBindMode.loopback);
      expect(loopbackState.baseUri!.host, InternetAddress.loopbackIPv4.address);
    },
  );

  test('relay provider persists route strategy and exposes aliases', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedRelayModel(db);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(openAiRelayControllerProvider.notifier);
    await notifier.ready;

    await notifier.setRouteStrategy(OpenAiRelayRouteStrategy.freeFirst);
    expect(
      container.read(openAiRelayControllerProvider).routeStrategy,
      OpenAiRelayRouteStrategy.freeFirst,
    );

    final token = generateOpenAiRelayToken();
    await notifier.start(token: token, requestedPort: 0);
    final state = container.read(openAiRelayControllerProvider);
    final models = await _get(
      state.baseUri!.resolve('/v1/models'),
      token: token,
    );
    expect(models.statusCode, HttpStatus.ok);
    expect(models.body, contains(kOpenAiRelayRouteAliasFree));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(kOpenAiRelayRouteStrategyStorageKey),
      OpenAiRelayRouteStrategy.freeFirst.storageValue,
    );
  });
}

Future<void> _waitForPreference(String key) async {
  for (var i = 0; i < 20; i += 1) {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(key) != null) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final prefs = await SharedPreferences.getInstance();
  expect(prefs.getString(key), isNotNull);
}

Future<void> _seedRelayModel(AppDatabase db) async {
  await db.channelDao.createChannel(
    id: 'channel-1',
    name: 'OpenAI Local',
    baseUrl: 'https://api.example.com/v1',
    apiKeyEncrypted: KeyEncryptor.encrypt('test-key-local-relay'),
    protocol: 'openai_chat',
  );
  await db.channelDao.addModel(
    id: 'chat-model',
    channelId: 'channel-1',
    modelName: 'gpt-test',
  );
}

Future<_HttpBody> _get(Uri uri, {String? token}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    return _HttpBody(response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

class _HttpBody {
  const _HttpBody(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
