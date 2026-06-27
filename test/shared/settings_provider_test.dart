import 'package:ai_chat_app/shared/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('font scale settings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('normalizes invalid and out-of-range values', () {
      expect(normalizeFontScale(double.nan), kDefaultFontScale);
      expect(normalizeFontScale(double.infinity), kDefaultFontScale);
      expect(normalizeFontScale(0.1), kMinFontScale);
      expect(normalizeFontScale(10), kMaxFontScale);
      expect(normalizeFontScale(1.2), 1.2);
    });

    test('formats font scale as percentage', () {
      expect(formatFontScale(1), '100%');
      expect(formatFontScale(1.25), '125%');
      expect(formatFontScale(10), '135%');
    });

    test('persists clamped font scale', () async {
      final notifier = FontScaleNotifier();
      addTearDown(notifier.dispose);

      await notifier.setFontScale(2.0);
      expect(notifier.state, kMaxFontScale);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('font_scale'), kMaxFontScale);
    });

    test('loads persisted font scale', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('font_scale', 1.2);

      final notifier = FontScaleNotifier();
      addTearDown(notifier.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, 1.2);
    });
  });

  group('semantic search settings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to enabled and persists changes', () async {
      final notifier = SemanticSearchEnabledNotifier();
      addTearDown(notifier.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isTrue);

      await notifier.setEnabled(false);
      expect(notifier.state, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('semantic_search_enabled'), isFalse);
    });

    test('loads persisted semantic search setting', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('semantic_search_enabled', false);

      final notifier = SemanticSearchEnabledNotifier();
      addTearDown(notifier.dispose);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state, isFalse);
    });
  });
}
