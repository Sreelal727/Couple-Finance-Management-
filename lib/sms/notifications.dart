import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications. The one-tap-add flow is:
/// SMS arrives → parsed → notification "₹450 to Swiggy — Add?" → tap opens
/// the app straight into the add sheet with everything prefilled.
class Notifications {
  Notifications._();

  static final plugin = FlutterLocalNotificationsPlugin();
  static const channelId = 'sms_capture';
  static const actionAdd = 'add';
  static const actionDismiss = 'dismiss';

  static bool _initialised = false;

  /// Set by the app once its navigator exists; called on foreground taps.
  static void Function(NotificationResponse)? onTap;

  static Future<void> init({void Function(NotificationResponse)? onBackgroundTap}) async {
    if (_initialised) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (r) => onTap?.call(r),
      onDidReceiveBackgroundNotificationResponse: onBackgroundTap,
    );
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            'Detected transactions',
            description: 'Bank SMS turned into one-tap expense entries',
            importance: Importance.high,
          ),
        );
    _initialised = true;
  }

  static Future<bool> requestPermission() async {
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  static Future<void> showSmsCandidate({required String smsId, required String title, required String body}) async {
    await plugin.show(
      id: smsId.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Detected transactions',
          channelDescription: 'Bank SMS turned into one-tap expense entries',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          actions: const [
            AndroidNotificationAction(actionAdd, 'Add expense', showsUserInterface: true),
            AndroidNotificationAction(actionDismiss, 'Not an expense', cancelNotification: true),
          ],
        ),
      ),
      payload: 'sms:$smsId',
    );
  }

  static Future<void> cancelFor(String smsId) => plugin.cancel(id: smsId.hashCode & 0x7fffffff);
}
