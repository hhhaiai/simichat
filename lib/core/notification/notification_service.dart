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
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

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

    // iOS 前台也展示横幅
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.show(
      0, // 固定 id，同一条会覆盖前一条
      '回复完成 — $sessionTitle',
      body,
      const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
    );
  }
}
