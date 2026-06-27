import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const kAiResponseNotificationChannelId = 'ai_response_channel';
const kDreamingNotificationChannelId = 'dreaming_digest_channel';
const kNotificationIdMask = 0x7fffffff;

/// 本地通知服务 —— 聊天回复、Dreaming 前台到期整理等本地事件完成时推送系统通知。
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'AI Chat',
      appUserModelId: 'com.aichat.ai_chat_app',
      guid: '6a5f3b6d-cd14-4aa0-9a1e-7f6c6f61f0d2',
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
        windows: windowsSettings,
      ),
    );

    _initialized = true;
  }

  /// 显示回复完成通知。
  Future<void> showResponseComplete({
    required String sessionTitle,
    String? preview,
  }) async {
    try {
      if (!_initialized) await init();

      const androidDetails = AndroidNotificationDetails(
        kAiResponseNotificationChannelId,
        'AI 回复通知',
        channelDescription: '当 AI 回复完成时通知你',
        importance: Importance.high,
        priority: Priority.high,
      );

      // Apple 平台前台也展示横幅。
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const linuxDetails = LinuxNotificationDetails();
      const windowsDetails = WindowsNotificationDetails();

      await _plugin.show(
        buildStableNotificationId('response', sessionTitle),
        '回复完成 — $sessionTitle',
        buildResponseNotificationBody(preview),
        const NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
          linux: linuxDetails,
          windows: windowsDetails,
        ),
      );
    } catch (_) {
      // 通知失败不能影响主聊天流程。
    }
  }

  /// 显示 Dreaming 前台到期整理完成通知。
  Future<void> showDreamingDigestComplete({
    required String dayKey,
    required int originalMessageCount,
    required int memoryCandidateCount,
    int profileProposalCount = 0,
  }) async {
    try {
      if (!_initialized) await init();

      const androidDetails = AndroidNotificationDetails(
        kDreamingNotificationChannelId,
        'Dreaming 夜间整理',
        channelDescription: '当本地 Dreaming 整理完成时通知你',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      );
      const linuxDetails = LinuxNotificationDetails();
      const windowsDetails = WindowsNotificationDetails();

      await _plugin.show(
        buildStableNotificationId('dreaming', dayKey),
        'Dreaming 已完成',
        buildDreamingDigestNotificationBody(
          originalMessageCount: originalMessageCount,
          memoryCandidateCount: memoryCandidateCount,
          profileProposalCount: profileProposalCount,
        ),
        const NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
          linux: linuxDetails,
          windows: windowsDetails,
        ),
      );
    } catch (_) {
      // Dreaming 通知失败不能影响聊天主链路或整理结果持久化。
    }
  }
}

String buildResponseNotificationBody(String? preview) {
  if (preview == null || preview.isEmpty) return 'AI 已完成回复';
  final normalized = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return 'AI 已完成回复';
  return normalized.length > 80
      ? '${normalized.substring(0, 80)}...'
      : normalized;
}

String buildDreamingDigestNotificationBody({
  required int originalMessageCount,
  required int memoryCandidateCount,
  int profileProposalCount = 0,
}) {
  if (originalMessageCount <= 0) return '今天暂无可整理对话';
  final parts = <String>['已整理 $originalMessageCount 条消息'];
  if (memoryCandidateCount > 0) {
    parts.add('提取 $memoryCandidateCount 条记忆候选');
  }
  if (profileProposalCount > 0) {
    parts.add('生成 $profileProposalCount 个待确认画像变更');
  }
  return parts.join('，');
}

/// 生成跨运行稳定的正整数通知 ID，避免固定 ID 覆盖和 Dart hashCode 随运行漂移。
int buildStableNotificationId(String namespace, String key) {
  const fnvPrime = 0x01000193;
  var hash = 0x811c9dc5;
  final input = '$namespace:$key';
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * fnvPrime) & 0xffffffff;
  }
  final id = hash & kNotificationIdMask;
  return id == 0 ? 1 : id;
}
