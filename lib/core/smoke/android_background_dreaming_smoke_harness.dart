import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../shared/providers/dreaming_provider.dart';
import '../../shared/providers/reflection_provider.dart';
import '../../shared/providers/user_profile_provider.dart';
import '../background/dreaming_background_workmanager.dart';
import '../crypto/key_encryptor.dart';
import '../database/app_database.dart';
import '../memory/dreaming_schedule.dart';
import 'android_background_dreaming_model_smoke_config.dart';

const _androidBackgroundDreamingSmokeDelaySeconds = int.fromEnvironment(
  'SIMICHAT_ANDROID_BACKGROUND_DREAMING_SMOKE_DELAY_SECONDS',
  defaultValue: 600,
);
const _androidBackgroundDreamingRequiresCharging = bool.fromEnvironment(
  'SIMICHAT_ANDROID_BACKGROUND_DREAMING_REQUIRES_CHARGING',
);
const _androidBackgroundDreamingRequiresUnmeteredNetwork = bool.fromEnvironment(
  'SIMICHAT_ANDROID_BACKGROUND_DREAMING_REQUIRES_UNMETERED_NETWORK',
);
const _androidBackgroundDreamingRealModel = bool.fromEnvironment(
  'SIMICHAT_ANDROID_BACKGROUND_DREAMING_REAL_MODEL',
);
const _androidBackgroundDreamingModelChannelId =
    'android-background-smoke-remote';
const _androidBackgroundDreamingModelId =
    'android-background-smoke-remote-model';

Future<void> runAndroidBackgroundDreamingSmokeApp() async {
  final modelConfig = _androidBackgroundDreamingRealModel
      ? await loadAndroidBackgroundDreamingModelConfig()
      : null;
  final delaySeconds = _androidBackgroundDreamingSmokeDelaySeconds > 0
      ? _androidBackgroundDreamingSmokeDelaySeconds
      : 1;
  final scheduledMessageAt = DateTime.now().add(
    Duration(seconds: delaySeconds),
  );
  const schedule = DreamingScheduleConfig(
    enabled: true,
    hour: 0,
    minute: 0,
    requiresCharging: _androidBackgroundDreamingRequiresCharging,
    requiresUnmeteredNetwork:
        _androidBackgroundDreamingRequiresUnmeteredNetwork,
  );
  final prefs = await SharedPreferences.getInstance();
  for (final key in const [
    kDreamingDigestStorageKey,
    kDreamingDigestHistoryStorageKey,
    kDreamingScheduleStorageKey,
    kAssistantReflectionStorageKey,
    kAssistantReflectionHistoryStorageKey,
    kAssistantReflectionModelEnabledStorageKey,
    kAssistantReflectionPendingStorageKey,
    kUserProfileChangeProposalsStorageKey,
    kUserProfileModelEnabledStorageKey,
  ]) {
    await prefs.remove(key);
  }
  await prefs.setString(
    kDreamingScheduleStorageKey,
    jsonEncode(schedule.toJson()),
  );
  if (_androidBackgroundDreamingRealModel) {
    await prefs.setBool(kAssistantReflectionModelEnabledStorageKey, true);
    await prefs.setBool(kUserProfileModelEnabledStorageKey, true);
  }

  final db = AppDatabase();
  try {
    if (modelConfig != null) {
      await db.channelDao.createChannel(
        id: _androidBackgroundDreamingModelChannelId,
        name: 'Android background smoke remote model',
        baseUrl: modelConfig.baseUrl,
        apiKeyEncrypted: KeyEncryptor.encrypt(modelConfig.apiKey),
        protocol: modelConfig.protocol,
      );
      await db.channelDao.addModel(
        id: _androidBackgroundDreamingModelId,
        channelId: _androidBackgroundDreamingModelChannelId,
        modelName: modelConfig.model,
      );
      await db.channelDao.setDefaultModel(
        _androidBackgroundDreamingModelChannelId,
        _androidBackgroundDreamingModelId,
      );
    }
    await db.sessionDao.createSession(
      id: 'android-background-smoke',
      defaultChannelModelId: _androidBackgroundDreamingRealModel
          ? _androidBackgroundDreamingModelId
          : null,
    );
    await db.sessionDao.updateTitle(
      'android-background-smoke',
      'Android 系统后台 Dreaming',
    );
    await db.messageDao.insertMessage(
      id: 'android-background-smoke-user',
      sessionId: 'android-background-smoke',
      role: 'user',
      content: '请在 Android 系统后台完成 Dreaming，并生成本地 Reflection。',
    );
    await db.customStatement(
      'UPDATE messages SET created_at = '
      '${scheduledMessageAt.millisecondsSinceEpoch} '
      "WHERE id = 'android-background-smoke-user'",
    );
  } finally {
    await db.close();
  }

  await Workmanager().initialize(dreamingBackgroundCallbackDispatcher);
  await Workmanager().cancelByTag(kAndroidDreamingBackgroundTaskTag);
  await Workmanager().registerOneOffTask(
    'simichat.android.dreaming.background.smoke',
    kAndroidDreamingBackgroundTaskName,
    initialDelay: Duration(seconds: delaySeconds),
    constraints: buildAndroidDreamingBackgroundConstraints(schedule),
    existingWorkPolicy: ExistingWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
    tag: kAndroidDreamingBackgroundTaskTag,
  );

  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Android background Dreaming smoke ready')),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint(
      'SIMICHAT_ANDROID_BACKGROUND_DREAMING_READY '
      'requiresCharging=${schedule.requiresCharging} '
      'requiresUnmeteredNetwork=${schedule.requiresUnmeteredNetwork} '
      'realModel=$_androidBackgroundDreamingRealModel '
      'model=${modelConfig?.model ?? 'none'}',
    );
  });
}
