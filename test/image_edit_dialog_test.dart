import 'dart:io';

import 'package:ai_chat_app/features/chat/image_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('image edit dialog keeps prompt and shows exact inline error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = Directory.systemTemp.createTempSync(
      'simichat_image_edit_dialog_',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final image = File('${temp.path}/source.png');
    image.writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);
    String? submittedPrompt;
    String? error = '当前渠道不支持图片编辑';

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showImageEditDialog(
                context,
                imagePath: image.path,
                onEdit: (prompt, size) async {
                  submittedPrompt = prompt;
                  return error;
                },
              ),
              child: const Text('打开编辑'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认编辑'));
    await tester.pump();
    expect(find.text('请输入编辑提示词'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '改成赛博朋克夜景');
    await tester.tap(find.text('确认编辑'));
    await tester.pumpAndSettle();
    expect(submittedPrompt, '改成赛博朋克夜景');
    expect(find.text('当前渠道不支持图片编辑'), findsOneWidget);
    expect(find.text('编辑失败，请稍后重试'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '改成赛博朋克夜景',
    );

    error = null;
    await tester.tap(find.text('确认编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling image edit closes without an error', (tester) async {
    final temp = Directory.systemTemp.createTempSync(
      'simichat_image_edit_cancel_',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final image = File('${temp.path}/source.png');
    image.writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showImageEditDialog(
                context,
                imagePath: image.path,
                onEdit: (_, _) async => null,
              ),
              child: const Text('打开编辑'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('编辑失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image edit callback exception restores retryable dialog state', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync(
      'simichat_image_edit_exception_',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final image = File('${temp.path}/source.png');
    image.writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);
    var shouldThrow = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showImageEditDialog(
                context,
                imagePath: image.path,
                onEdit: (_, _) async {
                  if (shouldThrow) throw StateError('internal details');
                  return null;
                },
              ),
              child: const Text('打开编辑'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留提示词');
    await tester.tap(find.text('确认编辑'));
    await tester.pumpAndSettle();

    expect(find.text('图片编辑失败，请稍后重试'), findsOneWidget);
    expect(find.text('internal details'), findsNothing);
    expect(find.text('确认编辑'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '保留提示词',
    );
    expect(tester.takeException(), isNull);

    shouldThrow = false;
    await tester.tap(find.text('确认编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
