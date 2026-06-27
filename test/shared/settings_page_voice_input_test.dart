import 'package:ai_chat_app/core/database/app_database.dart';
import 'package:ai_chat_app/core/crypto/key_encryptor.dart';
import 'package:ai_chat_app/core/media/audio_transcription_service.dart';
import 'package:ai_chat_app/features/settings/settings_page.dart';
import 'package:ai_chat_app/shared/providers/audio_transcription_provider.dart';
import 'package:ai_chat_app/shared/providers/database_provider.dart';
import 'package:ai_chat_app/shared/providers/text_to_speech_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings page shows voice input readiness without stt engine', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('语音与多模态'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('语音与多模态'), findsOneWidget);
    expect(find.text('语音输入'), findsOneWidget);
    expect(find.textContaining('STT 引擎未配置'), findsOneWidget);

    await tester.tap(find.text('语音输入'));
    await tester.pumpAndSettle();

    expect(find.text('语音输入与 STT 配置'), findsOneWidget);
    expect(find.text('• iOS / Android 麦克风权限声明'), findsOneWidget);
    expect(find.textContaining('当前：STT 引擎未配置'), findsOneWidget);
    expect(find.text('• OpenAI 兼容 STT 引擎配置入口'), findsOneWidget);
    expect(find.text('厂商预设'), findsOneWidget);
    expect(find.text('OpenAI 官方'), findsOneWidget);
    expect(find.text('保存配置'), findsOneWidget);
  });

  testWidgets('settings page reflects configured stt engine', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          speechToTextEngineProvider.overrideWithValue(_FakeSpeechEngine()),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('语音输入'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('STT 引擎已配置'), findsOneWidget);
  });

  testWidgets('settings page reflects persisted OpenAI compatible stt config', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kSpeechToTextEnabledStorageKey: true,
      kSpeechToTextProviderStorageKey: kSpeechToTextProviderOpenAiCompatible,
      kSpeechToTextBaseUrlStorageKey: 'https://api.openai.com',
      kSpeechToTextModelStorageKey: 'whisper-1',
      kSpeechToTextApiKeyStorageKey: KeyEncryptor.encrypt('stt-ui-key'),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('语音输入'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('OpenAI 兼容 STT 已配置'), findsOneWidget);
    expect(find.textContaining('whisper-1'), findsOneWidget);

    await tester.tap(find.text('语音输入'));
    await tester.pumpAndSettle();

    expect(find.text('API Key（留空保留已有密钥）'), findsOneWidget);
    expect(find.textContaining('不进入结构化备份'), findsOneWidget);
    expect(find.textContaining('stt-ui-key'), findsNothing);
  });

  testWidgets('settings page shows text to speech config entry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('语音播报'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('语音播报'), findsOneWidget);
    expect(find.textContaining('TTS 引擎未配置'), findsOneWidget);

    await tester.tap(find.text('语音播报'));
    await tester.pumpAndSettle();

    expect(find.text('语音播报 TTS 配置'), findsOneWidget);
    expect(find.text('• OpenAI 兼容 TTS 语音生成'), findsOneWidget);
    expect(find.text('• AI 回复卡片一键语音播报'), findsOneWidget);
    expect(find.text('• iOS / Android 原生本地音频播放通道'), findsOneWidget);
    expect(find.textContaining('当前：TTS 引擎未配置'), findsOneWidget);
    expect(find.text('音色'), findsOneWidget);
    expect(find.text('厂商预设'), findsOneWidget);
    expect(find.text('OpenAI 官方'), findsOneWidget);
    expect(find.text('保存配置'), findsOneWidget);
  });

  testWidgets('settings page can apply Groq STT preset', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('语音输入'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('语音输入'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OpenAI 官方').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groq STT').last);
    await tester.pumpAndSettle();

    expect(find.text('https://api.groq.com/openai'), findsOneWidget);
    expect(find.text('whisper-large-v3-turbo'), findsOneWidget);
  });

  testWidgets('settings page reflects persisted OpenAI compatible tts config', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kTextToSpeechEnabledStorageKey: true,
      kTextToSpeechProviderStorageKey: kTextToSpeechProviderOpenAiCompatible,
      kTextToSpeechBaseUrlStorageKey: 'https://api.openai.com',
      kTextToSpeechModelStorageKey: 'tts-1',
      kTextToSpeechVoiceStorageKey: 'alloy',
      kTextToSpeechApiKeyStorageKey: KeyEncryptor.encrypt('tts-ui-key'),
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('语音播报'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('OpenAI 兼容 TTS 已配置'), findsOneWidget);
    expect(find.textContaining('tts-1'), findsOneWidget);
    expect(find.textContaining('alloy'), findsOneWidget);

    await tester.tap(find.text('语音播报'));
    await tester.pumpAndSettle();

    expect(find.text('API Key（留空保留已有密钥）'), findsOneWidget);
    expect(find.textContaining('TTS API Key 加密保存在本机'), findsOneWidget);
    expect(find.textContaining('tts-ui-key'), findsNothing);
  });
}

class _FakeSpeechEngine implements SpeechToTextEngine {
  @override
  Future<String> transcribe(AudioTranscriptionInput input) async => 'text';
}
