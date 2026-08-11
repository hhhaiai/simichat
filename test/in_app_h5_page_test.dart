import 'dart:async';

import 'package:ai_chat_app/shared/widgets/in_app_h5_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('in-app H5 URL validation only accepts HTTPS', () {
    expect(
      normalizeInAppH5Url('https://api.dwchainless.com/sign-up?aff=Bslh'),
      isNotNull,
    );
    expect(normalizeInAppH5Url('http://example.test/'), isNull);
    expect(normalizeInAppH5Url('intent://open'), isNull);
    expect(normalizeInAppH5Url('mailto:support@example.test'), isNull);
    expect(
      normalizeInAppH5Url('https://user:pass@api.dwchainless.com/'),
      isNull,
    );
    expect(normalizeInAppH5Url('not a url'), isNull);
  });

  test('trusted navigation stays on the configured HTTPS host', () {
    final initial = Uri.parse('https://api.dwchainless.com/');
    expect(
      isAllowedInAppH5Navigation(
        Uri.parse('https://api.dwchainless.com/sign-in'),
        initial,
      ),
      isTrue,
    );
    expect(
      isAllowedInAppH5Navigation(
        Uri.parse('https://api.dwchainless.com.evil.example/sign-in'),
        initial,
      ),
      isFalse,
    );
    expect(
      isAllowedInAppH5Navigation(
        Uri.parse('http://api.dwchainless.com/sign-in'),
        initial,
      ),
      isFalse,
    );
    expect(
      isAllowedInAppH5Navigation(
        Uri.parse('https://api.dwchainless.com:8443/sign-in'),
        initial,
      ),
      isFalse,
    );
    expect(
      isAllowedInAppH5Navigation(
        Uri.parse('https://user:pass@api.dwchainless.com/sign-in'),
        initial,
      ),
      isFalse,
    );
  });

  test('persistent profile flush is delegated to the native WebView', () async {
    MethodCall? received;
    const channel = MethodChannel('simichat/in_app_h5_profile');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(await flushPersistentInAppH5Profile(), isTrue);
    expect(received?.method, 'flush');
  });

  test('persistent profile flush timeout never blocks page close', () async {
    const channel = MethodChannel('simichat/in_app_h5_profile');
    final never = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => never.future);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(
      await flushPersistentInAppH5Profile(
        timeout: const Duration(milliseconds: 10),
      ),
      isFalse,
    );
  });

  testWidgets('native H5 shell does not render an address bar', (tester) async {
    const url = 'https://api.dwchainless.com/';
    await tester.pumpWidget(
      const MaterialApp(
        home: InAppH5Page(initialUrl: url, title: '访问官网'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('访问官网'), findsOneWidget);
    expect(find.text(url), findsNothing);
    expect(find.byTooltip('返回'), findsOneWidget);
  });

  testWidgets('native H5 shell exposes a close action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const InAppH5Page(
                    initialUrl: 'https://example.test/',
                    title: '获取 Key',
                  ),
                ),
              ),
              child: const Text('打开 H5'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 H5'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('关闭'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    // 关闭按钮直接退出 H5 页面并回到设置页一侧的原生路由。
    expect(find.byType(InAppH5Page), findsNothing);
    expect(find.text('打开 H5'), findsOneWidget);

    // 不支持 WebView / 地址无效状态页中的正文“返回”同样能关闭路由，
    // 不会被外层 PopScope 拦住。
    await tester.tap(find.text('打开 H5'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '返回'));
    await tester.pumpAndSettle();
    expect(find.byType(InAppH5Page), findsNothing);
  });
}
