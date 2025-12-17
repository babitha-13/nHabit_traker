import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/material.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/Screens/Queue/queue_page.dart';
import 'package:habit_tracker/Screens/Goals/goal_dialog.dart';
import 'package:habit_tracker/Helper/backend/goal_service.dart';
import 'package:habit_tracker/Helper/utils/constants.dart';
import 'package:habit_tracker/Screens/Alarm/alarm_ringing_page.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/utils/timer_notification_service.dart';
import 'package:habit_tracker/Screens/Components/snooze_dialog.dart';

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
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapped,
    );
    // Create notification channel for Android
    await _createNotificationChannel();
  }

  /// Create notification channel for Android
  static Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'habit_alarms_v1', // Updated ID
      'Alarms',
      description: 'Full screen alarms for habits',
      importance: Importance.max, // Max importance
      playSound: true,
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Handle notification tap or action
  @pragma('vm:entry-point')
  static void _onNotificationTapped(NotificationResponse response) {
    // Handle action button clicks
    if (response.actionId != null && response.actionId!.isNotEmpty) {
      _handleNotificationAction(response.actionId!, response.payload);
      return;
    }

    // Handle notification tap
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
    // Handle alarm ringing
    else if (payload.startsWith('ALARM_RINGING:')) {
      _handleAlarmRingingTap(payload);
    }
    // Handle reminder notifications (open Queue page)
    else if (payload.isNotEmpty && !payload.startsWith('ALARM_RINGING:')) {
      _handleReminderNotificationTap(payload);
    }
  }

  /// Handle notification action button clicks
  static void _handleNotificationAction(String actionId, String? payload) {
    // Handle timer notification actions (no context needed)
    if (actionId == 'stop_all' && payload == 'timer_notification') {
      TimerNotificationService.handleAction(actionId);
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Parse action ID format: "ACTION_TYPE:instanceId" or "SNOOZE:reminderId"
    final parts = actionId.split(':');
    if (parts.length < 2) return;

    final actionType = parts[0];
    final identifier = parts[1];

    switch (actionType) {
      case 'COMPLETE':
        _handleCompleteAction(identifier, context);
        break;
      case 'ADD':
        _handleAddAction(identifier, context);
        break;
      case 'TIMER':
        _handleTimerAction(identifier, context);
        break;
      case 'SNOOZE':
        _handleSnoozeAction(identifier, context);
        break;
    }
  }

  /// Handle complete action
  static Future<void> _handleCompleteAction(String instanceId, BuildContext context) async {
    try {
      await ActivityInstanceService.completeInstance(instanceId: instanceId);
      
      // Navigate to Queue page
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
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
    } catch (e) {
      print('NotificationService: Error completing instance: $e');
    }
  }

  /// Handle add action (increment quantitative value)
  static Future<void> _handleAddAction(String instanceId, BuildContext context) async {
    try {
      final instance = await ActivityInstanceService.getUpdatedInstance(instanceId: instanceId);
      
      // Increment current value by 1
      final currentValue = instance.currentValue ?? 0;
      final newValue = (currentValue is num) ? (currentValue + 1) : 1;
      
      await ActivityInstanceService.updateInstanceProgress(
        instanceId: instanceId,
        currentValue: newValue,
      );
      
      // Navigate to Queue page
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
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
    } catch (e) {
      print('NotificationService: Error adding to instance: $e');
    }
  }

  /// Handle timer action
  static void _handleTimerAction(String instanceId, BuildContext context) {
    // Navigate to Queue page - timer logic will be handled there
    Navigator.of(context).pushNamedAndRemoveUntil(
      home,
      (route) => false,
    );
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

  /// Handle snooze action
  static void _handleSnoozeAction(String reminderId, BuildContext context) {
    // Show snooze dialog - will be imported when SnoozeDialog is created
    _showSnoozeDialog(context, reminderId);
  }

  /// Show snooze dialog
  static Future<void> _showSnoozeDialog(BuildContext context, String reminderId) async {
    try {
      await SnoozeDialog.show(context: context, reminderId: reminderId);
    } catch (e) {
      print('NotificationService: Error showing snooze dialog: $e');
      // Fallback: just navigate to Queue page
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
    }
  }

  /// Handle reminder notification tap (open Queue page)
  static void _handleReminderNotificationTap(String payload) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
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

  /// Handle alarm ringing notification tap
  static void _handleAlarmRingingTap(String payload) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      final parts = payload.substring('ALARM_RINGING:'.length).split('|');
      final title = parts.isNotEmpty ? parts[0] : 'Alarm';
      final body = parts.length > 1 ? parts[1] : null;
      final originalPayload = parts.length > 2 ? parts[2] : null;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => AlarmRingingPage(
            title: title,
            body: body,
            payload: originalPayload,
          ),
        ),
      );
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
    DateTimeComponents? matchDateTimeComponents,
    List<AndroidNotificationAction>? actions,
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
          NotificationDetails(
            android: AndroidNotificationDetails(
              'reminders',
              'Reminders',
              channelDescription: 'Notifications for task and habit reminders',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              actions: actions,
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
          matchDateTimeComponents: matchDateTimeComponents,
        );
      } catch (e) {
        // Fallback to approximate scheduling if exact fails
        await _notificationsPlugin.zonedSchedule(
          id.hashCode,
          title,
          body ?? 'Due in 10 minutes',
          tzDateTime,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'reminders',
              'Reminders',
              channelDescription: 'Notifications for task and habit reminders',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              actions: actions,
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
          matchDateTimeComponents: matchDateTimeComponents,
        );
      }
      print(
          'NotificationService: Scheduled reminder for $title at $scheduledTime (TZDateTime: $tzDateTime) with ID: ${id.hashCode}');
    } catch (e) {
      // Log error but don't fail - notification scheduling failures are non-critical
      print('Error scheduling notification: $e');
    }
  }

  /// Cancel a specific notification
  static Future<void> cancelNotification(String id) async {
    try {
      await _notificationsPlugin.cancel(id.hashCode);
    } catch (e) {
      // Log error but don't fail - notification cancellation failures are non-critical
      print('Error canceling notification $id: $e');
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch (e) {
      // Log error but don't fail - notification cancellation failures are non-critical
      print('Error canceling all notifications: $e');
    }
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
    List<AndroidNotificationAction>? actions,
  }) async {
    try {
      await _notificationsPlugin.show(
        id.hashCode,
        title,
        body ?? 'Notification',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'habit_alarms_v1', // CHANGED ID to force update
            'Alarms',
            channelDescription: 'Full screen alarms for habits',
            importance: Importance.max, // Max importance for heads-up/full-screen
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            fullScreenIntent: true,
            audioAttributesUsage: AudioAttributesUsage.alarm, // Treat as alarm
            category: AndroidNotificationCategory.alarm, // System treats as alarm
            actions: actions,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      // Log error but don't fail - immediate notification failures are non-critical
      print('Error showing immediate notification: $e');
    }
  }

  /// Log all pending notifications for debugging
  static Future<void> logPendingNotifications() async {
    try {
      final pending = await getPendingNotifications();
      for (final notification in pending) {
        // Log notification details if needed
        print('Pending notification: ${notification.id}');
      }
    } catch (e) {
      // Log error but don't fail - logging pending notifications is non-critical
      print('Error logging pending notifications: $e');
    }
  }

  /// Cancel all day-end notifications
  static Future<void> cancelDayEndNotifications() async {
    try {
      // Cancel the 3 day-end notifications
      await cancelNotification('day_end_1hr');
      await cancelNotification('day_end_30min');
      await cancelNotification('day_end_15min');
    } catch (e) {
      // Log error but don't fail - day-end notification cancellation is non-critical
      print('Error canceling day-end notifications: $e');
    }
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
    } catch (e) {
      // Log error but don't fail - day-end notification scheduling is non-critical
      print('Error scheduling day-end notifications: $e');
    }
  }

  /// Reschedule day-end notifications after snooze
  static Future<void> rescheduleDayEndNotifications({
    required DateTime newProcessTime,
  }) async {
    await scheduleDayEndNotifications(processTime: newProcessTime);
  }
}
