import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/Screens/Queue/queue_page.dart';
import 'package:habit_tracker/Screens/Goals/goal_dialog.dart';
import 'package:habit_tracker/Screens/Goals/goal_data_service.dart';
import 'package:habit_tracker/Helper/Helpers/constants.dart';
import 'package:habit_tracker/Screens/Alarm/alarm_ringing_page.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_instance_service.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/reminder_scheduler.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/timer_notification_service.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/TimeManager.dart';
import 'package:habit_tracker/Screens/Timer/timer_page.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/snooze_dialog.dart';
import 'package:habit_tracker/Screens/Routine/routine_detail_page.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

/// Service for managing local notifications
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _timezoneInitialized = false;
  static const int _notificationQuickSnoozeMinutes = 15;

  /// Initialize the notification service
  static Future<void> initialize() async {
    // Initialize timezone data
    tz.initializeTimeZones();
    // Set timezone to a common timezone (you can change this to your local timezone)
    // Common options: 'Asia/Kolkata', 'America/New_York', 'Europe/London', 'Asia/Tokyo'
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    _timezoneInitialized = true;
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
    // Handle routine reminders (open Routine detail page)
    else if (payload.startsWith('routine:')) {
      _handleRoutineReminderNotificationTap(payload);
    }
    // Handle timer notification (open Timer page with running timer)
    else if (payload == 'timer_notification') {
      _handleTimerNotificationTap();
    }
    // Handle reminder notifications (open Queue page)
    else if (payload.isNotEmpty && !payload.startsWith('ALARM_RINGING:')) {
      _handleReminderNotificationTap(payload);
    }
  }

  /// Handle timer notification tap: open Timer page with elapsed time running (or Home if no active timer).
  /// Waits for auth to be ready before proceeding, especially important for cold-start scenarios.
  static Future<void> _handleTimerNotificationTap() async {
    // Wait for auth to be ready (with timeout)
    final userId = await waitForCurrentUserUid(timeout: const Duration(seconds: 10));
    
    // If user is not logged in, just navigate to Home (they'll see login if needed)
    if (userId.isEmpty) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          home,
          (route) => false,
        );
      } else {
        // Cold-start: wait a bit for app to initialize, then navigate
        Future.delayed(const Duration(milliseconds: 1000), () {
          final delayedContext = navigatorKey.currentContext;
          if (delayedContext != null) {
            Navigator.of(delayedContext).pushNamedAndRemoveUntil(
              home,
              (route) => false,
            );
          }
        });
      }
      return;
    }

    // User is authenticated - proceed to open timer page
    void openTimerPage() async {
      final context = navigatorKey.currentContext;
      if (context == null) return;

      // Navigate to Home first
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );

      // Wait for Home to be ready, then load active timers and open Timer page
      Future.delayed(const Duration(milliseconds: 500), () async {
        try {
          // Load active timers from Firestore (ensures we have latest data)
          await TimerManager().loadActiveTimers();
          
          final homeContext = navigatorKey.currentContext;
          if (homeContext == null) return;
          
          final activeTimers = TimerManager().activeTimers;
          if (activeTimers.isNotEmpty) {
            // Open Timer page with the first active timer
            final instance = activeTimers.first;
            Navigator.of(homeContext).push(
              MaterialPageRoute(
                builder: (_) => TimerPage(
                  initialTimerLogRef: instance.reference,
                  taskTitle: instance.templateName,
                  fromSwipe: true,
                  fromNotification: true,
                ),
              ),
            );
          }
          // If no active timers, user stays on Home (timer may have stopped)
        } catch (e) {
          // Handle errors gracefully - user stays on Home
          debugPrint('Error opening timer page from notification: $e');
        }
      });
    }

    final context = navigatorKey.currentContext;
    if (context != null) {
      // App is already running - proceed immediately
      openTimerPage();
    } else {
      // Cold-start: wait for app to initialize before navigating
      Future.delayed(const Duration(milliseconds: 800), () {
        openTimerPage();
      });
    }
  }

  /// Handle notification action button clicks
  static void _handleNotificationAction(String actionId, String? payload) {
    // Handle timer notification actions (no context needed)
    if (actionId == 'stop_all' && payload == 'timer_notification') {
      TimerNotificationService.handleAction(actionId);
      return;
    }

    // Parse action ID format: "ACTION_TYPE:instanceId" or "SNOOZE:reminderId"
    final parts = actionId.split(':');
    if (parts.length < 2) return;

    final actionType = parts[0];
    final identifier = parts[1];

    if (actionType == 'SNOOZE') {
      _handleSnoozeAction(identifier, navigatorKey.currentContext);
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) return;

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
    }
  }

  /// Handle complete action
  static Future<void> _handleCompleteAction(
      String instanceId, BuildContext context) async {
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
  static Future<void> _handleAddAction(
      String instanceId, BuildContext context) async {
    try {
      final instance = await ActivityInstanceService.getUpdatedInstance(
          instanceId: instanceId);

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
  static void _handleSnoozeAction(String reminderId, BuildContext? context) {
    if (context != null) {
      // Show snooze dialog inside the app for richer options
      _showSnoozeDialog(context, reminderId);
      return;
    }
    // If the app is not in the foreground, fall back to a quick snooze so the action still works
    unawaited(_quickSnoozeReminder(reminderId));
  }

  /// Show snooze dialog
  static Future<void> _showSnoozeDialog(
      BuildContext context, String reminderId) async {
    try {
      await SnoozeDialog.show(context: context, reminderId: reminderId);
    } catch (e) {
      print('NotificationService: Error showing snooze dialog: $e');
      await _quickSnoozeReminder(reminderId);
      // Fallback: just navigate to Queue page
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
    }
  }

  static Future<void> _quickSnoozeReminder(String reminderId) async {
    try {
      await ReminderScheduler.snoozeReminder(
        reminderId: reminderId,
        durationMinutes: _notificationQuickSnoozeMinutes,
      );
    } catch (e) {
      print('NotificationService: Quick snooze failed: $e');
    }
  }

  /// Handle routine reminder notification tap (open Routine detail page)
  static void _handleRoutineReminderNotificationTap(String payload) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Extract routine ID from payload (format: "routine:routineId")
    final routineId = payload.substring('routine:'.length);
    if (routineId.isEmpty) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      home,
      (route) => false,
    );
    Future.delayed(const Duration(milliseconds: 500), () async {
      final homeContext = navigatorKey.currentContext;
      if (homeContext == null) return;

      try {
        final userId = await waitForCurrentUserUid();
        if (userId.isEmpty) return;
        final routineDoc = await RoutineRecord.collectionForUser(
          userId,
        ).doc(routineId).get();

        if (routineDoc.exists) {
          final routine = RoutineRecord.fromSnapshot(routineDoc);
          Navigator.of(homeContext).push(
            MaterialPageRoute(
              builder: (context) => RoutineDetailPage(routine: routine),
            ),
          );
        } else {
          Navigator.of(homeContext).push(
            MaterialPageRoute(
              builder: (context) => const QueuePage(),
            ),
          );
        }
      } catch (e) {
        Navigator.of(homeContext).push(
          MaterialPageRoute(
            builder: (context) => const QueuePage(),
          ),
        );
      }
    });
  }

  /// Handle reminder notification tap (open Queue page)
  static void _handleReminderNotificationTap(String payload) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      final templateId = _extractTemplateIdFromPayload(payload);
      final instanceId = _extractInstanceIdFromPayload(payload);
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
      Future.delayed(const Duration(milliseconds: 500), () {
        final homeContext = navigatorKey.currentContext;
        if (homeContext != null) {
          Navigator.of(homeContext).push(
            MaterialPageRoute(
              builder: (context) => QueuePage(
                focusTemplateId: templateId,
                focusInstanceId: instanceId,
              ),
            ),
          );
        }
      });
    }
  }

  /// Handle alarm ringing notification tap
  static void _handleAlarmRingingTap(String payload) {
    // Extract title and body from payload
    final parts = payload.substring('ALARM_RINGING:'.length).split('|');
    final title = parts.isNotEmpty ? parts[0] : 'Alarm';
    final body = parts.length > 1 ? parts[1] : null;
    // Extract instanceId from payload (parts[2])
    // AlarmRingingPage can handle either instanceId directly or full ALARM_RINGING format
    final instanceId = parts.length > 2 ? parts[2] : null;

    // Helper function to show alarm page
    void showAlarmPage() {
      final context = navigatorKey.currentContext;
      if (context == null) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => AlarmRingingPage(
            title: title,
            body: body,
            payload: instanceId, // Pass instanceId directly
          ),
          fullscreenDialog: true, // Show as full-screen modal
        ),
      );
    }

    // Get current context
    final context = navigatorKey.currentContext;

    if (context != null) {
      // Clear navigation stack and navigate to home first
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );

      // Wait for home to load, then show alarm page
      Future.delayed(const Duration(milliseconds: 400), () {
        showAlarmPage();
      });
    } else {
      // If context is null (app just starting), wait and retry
      Future.delayed(const Duration(milliseconds: 800), () {
        final delayedContext = navigatorKey.currentContext;
        if (delayedContext != null) {
          Navigator.of(delayedContext).pushNamedAndRemoveUntil(
            home,
            (route) => false,
          );
          Future.delayed(const Duration(milliseconds: 400), () {
            showAlarmPage();
          });
        }
      });
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

  /// Ensure timezone is initialized before use
  static void _ensureTimezoneInitialized() {
    if (!_timezoneInitialized) {
      // Timezone not initialized, initialize it now
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      _timezoneInitialized = true;
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
    // Web does not support local notifications in this app setup
    if (kIsWeb) return;
    try {
      // Ensure timezone is initialized before using tz.local
      _ensureTimezoneInitialized();

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
    if (kIsWeb) return;
    try {
      await _notificationsPlugin.cancel(id.hashCode);
    } catch (e) {
      // Log error but don't fail - notification cancellation failures are non-critical
      print('Error canceling notification $id: $e');
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    if (kIsWeb) return;
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
    if (kIsWeb) return [];
    try {
      return await _notificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      return [];
    }
  }

  /// Check if we have notification permissions
  static Future<bool> checkPermissions() async {
    if (kIsWeb) return false;
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
            importance:
                Importance.max, // Max importance for heads-up/full-screen
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            fullScreenIntent: true,
            audioAttributesUsage: AudioAttributesUsage.alarm, // Treat as alarm
            category:
                AndroidNotificationCategory.alarm, // System treats as alarm
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

  static String? _extractTemplateIdFromPayload(String payload) {
    if (payload.isEmpty) return null;
    const templatePrefix = 'template:';
    const instancePrefix = 'instance:';
    if (payload.startsWith(templatePrefix)) {
      return payload.substring(templatePrefix.length);
    }
    if (payload.startsWith(instancePrefix)) {
      return null;
    }
    return payload;
  }

  static String? _extractInstanceIdFromPayload(String payload) {
    if (payload.isEmpty) return null;
    const instancePrefix = 'instance:';
    if (payload.startsWith(instancePrefix)) {
      return payload.substring(instancePrefix.length);
    }
    return null;
  }
}
