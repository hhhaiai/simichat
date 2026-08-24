import 'package:ai_chat_app/shared/widgets/html_artifact_card.dart';
import 'package:ai_chat_app/shared/widgets/latex_markdown_widget.dart';
import 'package:ai_chat_app/shared/widgets/code_block_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes complete HTML documents only', () {
    expect(
      HtmlArtifactCard.looksLikeHtmlDocument('<!doctype html><html></html>'),
      isTrue,
    );
    expect(
      HtmlArtifactCard.looksLikeHtmlDocument('<div>fragment</div>'),
      isFalse,
    );
  });

  testWidgets(
    'HTML result is a compact artifact card without source expansion',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HtmlArtifactCard(
              name: 'world_art_gallery.html',
              code: '<!doctype html><html><body><h1>Gallery</h1></body></html>',
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('artifact-card-world_art_gallery.html')),
        findsOneWidget,
      );
      expect(find.text('world_art_gallery.html'), findsOneWidget);
      expect(find.text('查看效果'), findsOneWidget);
      expect(find.text('源码'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('artifact-edit-world_art_gallery.html')),
        findsOneWidget,
      );
      expect(find.textContaining('<!doctype html>'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Markdown result exposes preview, source and edit actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownArtifactCard(
            name: 'product_requirement.md',
            markdown: '# Product\n\nA compact artifact.',
          ),
        ),
      ),
    );

    expect(find.text('product_requirement.md'), findsOneWidget);
    expect(find.text('Markdown · 30 B · 阅读视图'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('complete HTML returned without a fence becomes an artifact', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LatexMarkdownWidget(
            data: '<!doctype html><html><body><h1>Gallery</h1></body></html>',
          ),
        ),
      ),
    );

    expect(find.byType(HtmlArtifactCard), findsOneWidget);
    expect(find.byType(CodeBlockWidget), findsNothing);
    expect(find.text('Gallery'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
