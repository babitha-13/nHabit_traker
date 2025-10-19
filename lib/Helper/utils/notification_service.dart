import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

/// Service for managing local notifications
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Initialize the notification service
  static Future<void> initialize() async {
    print('NotificationService: Starting initialization...');

    // Initialize timezone data
    tz.initializeTimeZones();

    // Set timezone to a common timezone (you can change this to your local timezone)
    // Common options: 'Asia/Kolkata', 'America/New_York', 'Europe/London', 'Asia/Tokyo'
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    print('NotificationService: Timezone set to: Asia/Kolkata');

    // Android initialization settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Combined initialization settings
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    print('NotificationService: Initializing plugin...');
    // Initialize the plugin
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    print('NotificationService: Plugin initialized');

    // Create notification channel for Android
    print('NotificationService: Creating notification channel...');
    await _createNotificationChannel();
    print('NotificationService: Notification channel created');

    print('NotificationService: Initialization complete');
  }

  /// Create notification channel for Android
  static Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'reminders',
      'Reminders',
      description: 'Notifications for task and habit reminders',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    // TODO: Navigate to relevant task/habit when tapped
    print('Notification tapped: ${response.payload}');
  }

  /// Schedule a reminder notification
  static Future<void> scheduleReminder({
    required String id,
    required String title,
    required DateTime scheduledTime,
    String? body,
    String? payload,
  }) async {
    try {
      // Create TZDateTime directly from the scheduled time components
      final tzDateTime = tz.TZDateTime(
        tz.local,
        scheduledTime.year,
        scheduledTime.month,
        scheduledTime.day,
        scheduledTime.hour,
        scheduledTime.minute,
        scheduledTime.second,
      );

      // Try exact scheduling first, fallback to approximate if needed
      try {
        await _notificationsPlugin.zonedSchedule(
          id.hashCode,
          title,
          body ?? 'Due in 10 minutes',
          tzDateTime,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'reminders',
              'Reminders',
              channelDescription: 'Notifications for task and habit reminders',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: payload,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (e) {
        // Fallback to approximate scheduling if exact fails
        print(
            'NotificationService: Exact scheduling failed, trying approximate: $e');
        await _notificationsPlugin.zonedSchedule(
          id.hashCode,
          title,
          body ?? 'Due in 10 minutes',
          tzDateTime,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'reminders',
              'Reminders',
              channelDescription: 'Notifications for task and habit reminders',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: payload,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exact,
        );
      }
      print(
          'NotificationService: Scheduled reminder for $title at $scheduledTime (TZDateTime: $tzDateTime) with ID: ${id.hashCode}');
    } catch (e) {
      print('NotificationService: Error scheduling reminder: $e');
    }
  }

  /// Cancel a specific notification
  static Future<void> cancelNotification(String id) async {
    try {
      await _notificationsPlugin.cancel(id.hashCode);
      print('NotificationService: Cancelled notification $id');
    } catch (e) {
      print('NotificationService: Error cancelling notification $id: $e');
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
      print('NotificationService: Cancelled all notifications');
    } catch (e) {
      print('NotificationService: Error cancelling all notifications: $e');
    }
  }

  /// Show immediate notification (for debugging)
  static Future<void> scheduleImmediateTest() async {
    try {
      await _notificationsPlugin.show(
        999998, // Test ID
        'IMMEDIATE TEST',
        'This should appear immediately',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            'Reminders',
            channelDescription: 'Notifications for task and habit reminders',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            showWhen: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'immediate_test',
      );

      print('NotificationService: IMMEDIATE test notification shown');
    } catch (e) {
      print(
          'NotificationService: Error showing IMMEDIATE test notification: $e');
    }
  }

  /// Test notification (for debugging)
  static Future<void> scheduleTestNotification() async {
    try {
      await _notificationsPlugin.show(
        999999, // Test ID
        'Test Notification',
        'This is a test notification',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            'Reminders',
            channelDescription: 'Notifications for task and habit reminders',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'test',
      );

      print('NotificationService: Test notification shown');
    } catch (e) {
      print('NotificationService: Error showing test notification: $e');
    }
  }

  /// Get pending notifications
  static Future<List<PendingNotificationRequest>>
      getPendingNotifications() async {
    try {
      return await _notificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      print('NotificationService: Error getting pending notifications: $e');
      return [];
    }
  }

  /// Check if we have notification permissions
  static Future<bool> checkPermissions() async {
    try {
      final androidPlugin =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final notificationPermission =
            await androidPlugin.areNotificationsEnabled();
        final exactAlarmPermission =
            await androidPlugin.canScheduleExactNotifications();

        print(
            'NotificationService: Notifications enabled: $notificationPermission');
        print(
            'NotificationService: Exact alarms allowed: $exactAlarmPermission');

        return (notificationPermission ?? false) &&
            (exactAlarmPermission ?? false);
      }
      return false;
    } catch (e) {
      print('NotificationService: Error checking permissions: $e');
      return false;
    }
  }

  /// Request notification permissions
  static Future<bool> requestPermissions() async {
    try {
      // Request notification permission
      final notificationResult = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      // Request exact alarm permission (Android 12+)
      final exactAlarmResult = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();

      print(
          'NotificationService: Notification permission: ${notificationResult ?? false}');
      print(
          'NotificationService: Exact alarm permission: ${exactAlarmResult ?? false}');

      return (notificationResult ?? false) && (exactAlarmResult ?? false);
    } catch (e) {
      print('NotificationService: Error requesting permissions: $e');
      return false;
    }
  }

  /// Show immediate notification (for instant notifications)
  static Future<void> showImmediate({
    required String id,
    required String title,
    String? body,
    String? payload,
  }) async {
    try {
      await _notificationsPlugin.show(
        id.hashCode,
        title,
        body ?? 'Notification',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            'Reminders',
            channelDescription: 'Notifications for task and habit reminders',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );

      print('NotificationService: Immediate notification shown: $title');
    } catch (e) {
      print('NotificationService: Error showing immediate notification: $e');
    }
  }

  /// Log all pending notifications for debugging
  static Future<void> logPendingNotifications() async {
    try {
      final pending = await getPendingNotifications();
      print('NotificationService: ${pending.length} pending notifications:');
      for (final notif in pending) {
        print(
            '  - ID: ${notif.id}, Title: ${notif.title}, Body: ${notif.body}');
      }
    } catch (e) {
      print('NotificationService: Error getting pending notifications: $e');
    }
  }
}
