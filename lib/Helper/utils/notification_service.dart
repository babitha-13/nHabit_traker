import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/material.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/Screens/Queue/queue_page.dart';
import 'package:habit_tracker/Screens/Goals/goal_dialog.dart';
import 'package:habit_tracker/Helper/backend/goal_service.dart';
import 'package:habit_tracker/Helper/utils/constants.dart';

/// Service for managing local notifications
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Initialize the notification service
  static Future<void> initialize() async {
    // Initialize timezone data
    tz.initializeTimeZones();
    // Set timezone to a common timezone (you can change this to your local timezone)
    // Common options: 'Asia/Kolkata', 'America/New_York', 'Europe/London', 'Asia/Tokyo'
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
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
    // Initialize the plugin
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    // Create notification channel for Android
    await _createNotificationChannel();
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
    final payload = response.payload;
    if (payload == null) return;

    // Handle day-end notifications
    if (payload == 'day_end_notification') {
      _handleDayEndNotificationTap();
    }
    // Handle morning reminder
    else if (payload == 'morning_reminder') {
      _handleMorningReminderTap();
    }
    // Handle evening reminder
    else if (payload == 'evening_reminder') {
      _handleEveningReminderTap();
    }
    // Handle engagement reminder
    else if (payload == 'engagement_reminder') {
      _handleEngagementReminderTap();
    }
  }

  /// Handle day-end notification tap
  static void _handleDayEndNotificationTap() {
    // Show goal dialog first, then navigate to Queue page
    final context = navigatorKey.currentContext;
    if (context != null) {
      // Show goal dialog first
      _showGoalDialogFromNotification(context);

      // Then navigate to Queue page
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const QueuePage(),
        ),
      );
    } else {}
  }

  /// Show goal dialog from notification tap
  static void _showGoalDialogFromNotification(BuildContext context) async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }
      // Check if goal should be shown (bypass time check for notification)
      final shouldShow =
          await GoalService.shouldShowGoalFromNotification(userId);
      if (shouldShow) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const GoalDialog(),
        );
      }
    } catch (e) {
      // Silently handle error
    }
  }

  /// Handle morning reminder notification tap
  static void _handleMorningReminderTap() {
    final context = navigatorKey.currentContext;
    if (context != null) {
      // Navigate to Queue page
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
      // Then navigate to Queue page after a short delay to ensure Home is loaded
      Future.delayed(const Duration(milliseconds: 500), () {
        final homeContext = navigatorKey.currentContext;
        if (homeContext != null) {
          Navigator.of(homeContext).push(
            MaterialPageRoute(
              builder: (context) => const QueuePage(),
            ),
          );
        }
      });
    }
  }

  /// Handle evening reminder notification tap
  static void _handleEveningReminderTap() {
    final context = navigatorKey.currentContext;
    if (context != null) {
      // Navigate to Queue page
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
      // Then navigate to Queue page after a short delay to ensure Home is loaded
      Future.delayed(const Duration(milliseconds: 500), () {
        final homeContext = navigatorKey.currentContext;
        if (homeContext != null) {
          Navigator.of(homeContext).push(
            MaterialPageRoute(
              builder: (context) => const QueuePage(),
            ),
          );
        }
      });
    }
  }

  /// Handle engagement reminder notification tap
  static void _handleEngagementReminderTap() {
    final context = navigatorKey.currentContext;
    if (context != null) {
      // Navigate to Home page
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
    }
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
    } catch (e) {}
  }

  /// Cancel a specific notification
  static Future<void> cancelNotification(String id) async {
    try {
      await _notificationsPlugin.cancel(id.hashCode);
    } catch (e) {}
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch (e) {}
  }

  /// Get pending notifications
  static Future<List<PendingNotificationRequest>>
      getPendingNotifications() async {
    try {
      return await _notificationsPlugin.pendingNotificationRequests();
    } catch (e) {
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
        return (notificationPermission ?? false) &&
            (exactAlarmPermission ?? false);
      }
      return false;
    } catch (e) {
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
      return (notificationResult ?? false) && (exactAlarmResult ?? false);
    } catch (e) {
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
    } catch (e) {}
  }

  /// Log all pending notifications for debugging
  static Future<void> logPendingNotifications() async {
    try {
      final pending = await getPendingNotifications();
      for (final notification in pending) {
        // Log notification details if needed
        print('Pending notification: ${notification.id}');
      }
    } catch (e) {}
  }

  /// Cancel all day-end notifications
  static Future<void> cancelDayEndNotifications() async {
    try {
      // Cancel the 3 day-end notifications
      await cancelNotification('day_end_1hr');
      await cancelNotification('day_end_30min');
      await cancelNotification('day_end_15min');
    } catch (e) {}
  }

  /// Schedule day-end notifications (1hr, 30min, 15min before processing)
  static Future<void> scheduleDayEndNotifications({
    required DateTime processTime,
  }) async {
    try {
      // Cancel existing day-end notifications first
      await cancelDayEndNotifications();
      // Schedule 3 notifications
      final notifications = [
        {
          'time': processTime.subtract(const Duration(hours: 1)),
          'message':
              'You\'re almost there! 1 hour left to crush today\'s goals 💪 Check your progress!',
          'id': 'day_end_1hr'
        },
        {
          'time': processTime.subtract(const Duration(minutes: 30)),
          'message':
              'You\'re almost there! 30 minutes left to crush today\'s goals 💪 Check your progress!',
          'id': 'day_end_30min'
        },
        {
          'time': processTime.subtract(const Duration(minutes: 15)),
          'message':
              'You\'re almost there! 15 minutes left to crush today\'s goals 💪 Check your progress!',
          'id': 'day_end_15min'
        },
      ];
      for (final notification in notifications) {
        final notificationTime = notification['time'] as DateTime;
        final message = notification['message'] as String;
        final id = notification['id'] as String;
        // Only schedule if the notification time is in the future
        if (notificationTime.isAfter(DateTime.now())) {
          await scheduleReminder(
            id: id,
            title: 'Day Ending Soon',
            body: message,
            scheduledTime: notificationTime,
            payload: 'day_end_notification',
          );
        }
      }
    } catch (e) {}
  }

  /// Reschedule day-end notifications after snooze
  static Future<void> rescheduleDayEndNotifications({
    required DateTime newProcessTime,
  }) async {
    await scheduleDayEndNotifications(processTime: newProcessTime);
  }
}
