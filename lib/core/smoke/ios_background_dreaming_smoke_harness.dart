import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../shared/providers/dreaming_provider.dart';
import '../background/dreaming_background_workmanager.dart';
import '../background/ios_background_refresh_status.dart';
import '../database/app_database.dart';
import '../memory/dreaming_schedule.dart';
import 'ios_background_dreaming_smoke_result.dart';

const _kIosBackgroundDreamingSmokeSessionId =
    'ios-background-dreaming-smoke-session';
const _kIosBackgroundDreamingSmokeMessageId =
    'ios-background-dreaming-smoke-message';

Future<void> runIosBackgroundDreamingSmokeApp() async {
  final prefs = await SharedPreferences.getInstance();
  final existingResult = prefs.getString(
    kIosBackgroundDreamingSmokeResultStorageKey,
  );
  if (existingResult != null && existingResult.isNotEmpty) {
    final decoded = jsonDecode(existingResult);
    await writeIosBackgroundDreamingSmokeResult({
      'marker': 'SIMICHAT_IOS_BACKGROUND_DREAMING_VERIFIED',
      if (decoded is Map) ...decoded.cast<String, Object?>(),
    });
    debugPrint('SIMICHAT_IOS_BACKGROUND_DREAMING_VERIFIED $existingResult');
    runApp(
      const _IosBackgroundDreamingSmokeApp(
        message: 'iOS background Dreaming verified',
      ),
    );
    return;
  }

  final now = DateTime.now();
  final schedule = DreamingScheduleConfig(
    enabled: true,
    hour: now.hour,
    minute: now.minute,
  );
  await prefs.setString(
    kDreamingScheduleStorageKey,
    jsonEncode(schedule.toJson()),
  );

  final db = AppDatabase();
  try {
    if (await db.sessionDao.getSession(_kIosBackgroundDreamingSmokeSessionId) ==
        null) {
      await db.sessionDao.createSession(
        id: _kIosBackgroundDreamingSmokeSessionId,
      );
      await db.sessionDao.updateTitle(
        _kIosBackgroundDreamingSmokeSessionId,
        'iOS Background Dreaming Smoke',
      );
    }
    final messages = await db.messageDao.getMessagesBySession(
      _kIosBackgroundDreamingSmokeSessionId,
    );
    if (!messages.any(
      (message) => message.id == _kIosBackgroundDreamingSmokeMessageId,
    )) {
      await db.messageDao.insertMessage(
        id: _kIosBackgroundDreamingSmokeMessageId,
        sessionId: _kIosBackgroundDreamingSmokeSessionId,
        role: 'user',
        content: '请在 iOS BGTaskScheduler 后台完成 Dreaming 和 Reflection。',
      );
    }
  } finally {
    await db.close();
  }

  await syncDreamingBackgroundSchedule(schedule, now: now);
  final backgroundRefreshStatus = await readIosBackgroundRefreshStatus();
  final scheduledTasks = await Workmanager().printScheduledTasks();
  await writeIosBackgroundDreamingSmokeResult({
    'marker': 'SIMICHAT_IOS_BACKGROUND_DREAMING_READY',
    'status': 'ready',
    'taskIdentifier': kIosDreamingBackgroundTaskIdentifier,
    'backgroundRefreshStatus': backgroundRefreshStatus.name,
    'scheduledTasks': scheduledTasks,
  });
  debugPrint(
    'SIMICHAT_IOS_BACKGROUND_DREAMING_READY '
    'task=$kIosDreamingBackgroundTaskIdentifier '
    'backgroundRefreshStatus=${backgroundRefreshStatus.name}',
  );
  runApp(
    const _IosBackgroundDreamingSmokeApp(
      message: 'iOS background Dreaming scheduled',
    ),
  );
}

class _IosBackgroundDreamingSmokeApp extends StatelessWidget {
  const _IosBackgroundDreamingSmokeApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: Text(message, textAlign: TextAlign.center)),
      ),
    );
  }
}
