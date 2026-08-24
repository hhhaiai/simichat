import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/channel_quota_client.dart';
import 'package:ai_chat_app/core/ai/simirouter_billing_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Anthropic OAuth windows used by CCSwitch', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    unawaited(
      server.forEach((request) async {
        expect(request.uri.path, '/api/oauth/usage');
        expect(request.headers.value('authorization'), 'Bearer oauth-token');
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'five_hour': {
                'utilization': 0.42,
                'resets_at': '2026-08-21T18:30:00Z',
              },
              'seven_day': {
                'utilization': 18,
                'resets_at': '2026-08-25T00:00:00Z',
              },
            }),
          );
        await request.response.close();
      }),
    );

    final snapshot = await const ChannelQuotaClient().fetch(
      protocol: 'claude',
      baseUrl: 'http://${server.address.host}:${server.port}/v1',
      apiKey: 'oauth-token',
    );

    expect(snapshot.provider, 'Anthropic / CCSwitch');
    expect(snapshot.windows, hasLength(2));
    expect(snapshot.windows.first.label, '5 小时');
    expect(snapshot.windows.first.utilization, closeTo(42, 0.01));
    expect(snapshot.windows.first.resetLabel, contains('重置'));
    expect(snapshot.compactLabel, contains('5 小时 42%'));
  });

  test('parses new-api dashboard quota and optional subscription', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    unawaited(
      server.forEach((request) async {
        expect(request.headers.value('authorization'), 'Bearer key');
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              request.uri.path.endsWith('/usage')
                  ? {'total_usage': 80141.1968}
                  : {'soft_limit_usd': 20},
            ),
          );
        await request.response.close();
      }),
    );
    final snapshot = await const ChannelQuotaClient().fetch(
      protocol: 'openai_chat',
      baseUrl: 'http://${server.address.host}:${server.port}/v1',
      apiKey: 'key',
    );

    expect(snapshot.usedUsd, closeTo(0.1603, 0.001));
    expect(snapshot.limitUsd, 20);
    expect(snapshot.compactLabel, '已用 \$0.16 · 限额 \$20.00');
  });

  test('reports a clear error when a provider has no quota contract', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    unawaited(
      server.forEach((request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }),
    );

    expect(
      () => const ChannelQuotaClient().fetch(
        protocol: 'openai_chat',
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'key',
      ),
      throwsA(
        isA<ChannelQuotaException>().having(
          (error) => error.message,
          'message',
          '当前渠道未提供额度查询接口',
        ),
      ),
    );
  });

  test('parses new-api account quota and sends New-Api-User header', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    unawaited(
      server.forEach((request) async {
        expect(request.uri.path, '/api/user/self');
        expect(request.headers.value('authorization'), 'Bearer account-key');
        expect(request.headers.value('new-api-user'), '42');
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'data': {
                'id': 42,
                'username': 'sanbo',
                'quota': 250000,
                'used_quota': 50000,
              },
            }),
          );
        await request.response.close();
      }),
    );

    final snapshot = await const SimiRouterBillingClient().fetchAccount(
      baseUrl: 'http://${server.address.host}:${server.port}/v1',
      apiKey: 'account-key',
      newApiUser: '42',
    );
    expect(snapshot.userId, '42');
    expect(snapshot.username, 'sanbo');
    expect(snapshot.remainingQuota, 250000);
    expect(snapshot.compactLabel, contains('剩余 0.50 USD'));
  });
}
