import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 本地通知服务 —— 回复完成时推送系统通知
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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

    await _plugin.initialize(const InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    ));

    _initialized = true;
  }

  /// 显示回复完成通知
  Future<void> showResponseComplete({
    required String sessionTitle,
    String? preview,
  }) async {
    if (!_initialized) await init();

    final body = preview != null && preview.isNotEmpty
        ? (preview.length > 80 ? '${preview.substring(0, 80)}...' : preview)
        : 'AI 已完成回复';

    const androidDetails = AndroidNotificationDetails(
      'ai_response_channel',
      'AI 回复通知',
      channelDescription: '当 AI 回复完成时通知你',
      importance: Importance.high,
      priority: Priority.high,
    );

    // Apple 平台前台也展示横幅
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const linuxDetails = LinuxNotificationDetails();
    const windowsDetails = WindowsNotificationDetails();

    try {
      await _plugin.show(
        sessionTitle.hashCode & 0x7FFFFFFF, // 每个会话独立 id，避免互相覆盖
        '回复完成 — $sessionTitle',
        body,
        const NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
          linux: linuxDetails,
          windows: windowsDetails,
        ),
      );
    } catch (_) {
      // 通知失败不能影响主聊天流程
    }
  }
}
