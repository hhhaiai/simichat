import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_app/shared/providers/creation_mode_provider.dart';
import 'package:ai_chat_app/shared/widgets/creation_mode_switcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('voice task routes persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    await first
        .read(voiceCreationRoutePreferencesProvider.notifier)
        .setPreferred(VoiceCreationTool.synthesis, 'tts-model');
    await first
        .read(voiceCreationRoutePreferencesProvider.notifier)
        .setPreferred(VoiceCreationTool.design, 'design-model');
    await first
        .read(voiceCreationRoutePreferencesProvider.notifier)
        .setPreferred(VoiceCreationTool.clone, 'clone-model');
    await first
        .read(voiceCreationRoutePreferencesProvider.notifier)
        .setPreferred(VoiceCreationTool.recognition, 'asr-model');
    first.dispose();

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(voiceCreationRoutePreferencesProvider.notifier).ready;
    final routes = restored.read(voiceCreationRoutePreferencesProvider);
    expect(routes.modelIdFor(VoiceCreationTool.synthesis), 'tts-model');
    expect(routes.modelIdFor(VoiceCreationTool.design), 'design-model');
    expect(routes.modelIdFor(VoiceCreationTool.clone), 'clone-model');
    expect(routes.modelIdFor(VoiceCreationTool.recognition), 'asr-model');
  });

  testWidgets('shows the four product modes and changes the provider', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CreationModeSwitcher())),
      ),
    );

    expect(find.byKey(CreationModeSwitcher.switcherKey), findsOneWidget);
    expect(find.text('聊天'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('语音'), findsOneWidget);
    expect(container.read(creationModeProvider), CreationMode.chat);

    await tester.tap(find.byKey(const ValueKey('creation-mode-image')));
    await tester.pumpAndSettle();

    expect(container.read(creationModeProvider), CreationMode.image);
  });
}
