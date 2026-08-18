import 'package:ai_chat_app/shared/widgets/streaming_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'streaming thinking toggle keeps a 44dp target on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(240, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StreamingBubble(content: '', thinking: '正在整理上下文'),
          ),
        ),
      );

      final inkWell = find.byType(InkWell);
      expect(inkWell, findsOneWidget);
      expect(tester.getSize(inkWell).height, greaterThanOrEqualTo(44));

      await tester.tap(find.text('思考过程'));
      await tester.pump();

      expect(find.text('正在整理上下文'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
