import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_chat_app/core/ai/simirouter_billing_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses new-api usage and subscription into usd snapshot', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    unawaited(
      server.forEach((request) async {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              request.uri.path.endsWith('/usage')
                  ? {'object': 'list', 'total_usage': 80141.1968}
                  : {
                      'has_payment_method': true,
                      'soft_limit_usd': 20,
                      'hard_limit_usd': 50,
                    },
            ),
          );
        await request.response.close();
      }),
    );
    final base = 'http://${server.address.host}:${server.port}/v1';

    final snapshot = await const SimiRouterBillingClient().fetch(
      baseUrl: base,
      apiKey: 'test-key',
    );

    // 80141.1968 quota / 500000 = 0.16 USD
    expect(snapshot.usedUsd, closeTo(0.1603, 0.001));
    expect(snapshot.softLimitUsd, 20);
    expect(snapshot.hardLimitUsd, 50);
    expect(snapshot.hasPaymentMethod, true);
    expect(snapshot.usedLabel, '\$0.16');
    expect(snapshot.limitLabel, '限额 \$20.00');
  });

  test('unlimited sentinel limit is treated as no limit', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    unawaited(
      server.forEach((request) async {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              request.uri.path.endsWith('/usage')
                  ? {'object': 'list', 'total_usage': 0}
                  : {
                      'has_payment_method': false,
                      'soft_limit_usd': 100000000,
                      'hard_limit_usd': 100000000,
                    },
            ),
          );
        await request.response.close();
      }),
    );
    final base = 'http://${server.address.host}:${server.port}/v1';

    final snapshot = await const SimiRouterBillingClient().fetch(
      baseUrl: base,
      apiKey: 'test-key',
    );

    expect(snapshot.softLimitUsd, isNull);
    expect(snapshot.hardLimitUsd, isNull);
    expect(snapshot.usedLabel, '\$0');
    expect(snapshot.limitLabel, '未设限额');
  });
}
