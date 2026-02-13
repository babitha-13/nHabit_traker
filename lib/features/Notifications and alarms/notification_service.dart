import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/features/Queue/queue_page.dart';
import 'package:habit_tracker/features/Goals/goal_dialog.dart';
import 'package:habit_tracker/features/Goals/goal_data_service.dart';
import 'package:habit_tracker/core/constants.dart';
import 'package:habit_tracker/features/Alarm/alarm_ringing_page.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/reminder_scheduler.dart';
import 'package:habit_tracker/features/Timer/Helpers/timer_notification_service.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/snooze_dialog.dart';
import 'package:habit_tracker/features/Routine/routine_detail_page.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:vibration/vibration.dart';

class ActiveAlarmContext {
  const ActiveAlarmContext({
    required this.rawPayload,
    required this.title,
    this.body,
    this.instanceId,
    this.reminderId,
    this.templateName,
    this.trackingType,
    this.dueDate,
    this.dueTime,
  });

  final String rawPayload;
  final String title;
  final String? body;
  final String? instanceId;
  final String? reminderId;
  final String? templateName;
  final String? trackingType;
  final DateTime? dueDate;
  final String? dueTime;

  String get displayTitle =>
      (templateName != null && templateName!.trim().isNotEmpty)
          ? templateName!
          : title;

  String get primaryActionLabel {
    switch (trackingType) {
      case 'quantitative':
        return 'Add 1';
      case 'time':
        return 'Start timer';
      case 'binary':
      default:
        return 'Mark complete';
    }
  }

  ActiveAlarmContext copyWith({
    String? rawPayload,
    String? title,
    String? body,
    String? instanceId,
    String? reminderId,
    String? templateName,
    String? trackingType,
    DateTime? dueDate,
    String? dueTime,
  }) {
    return ActiveAlarmContext(
      rawPayload: rawPayload ?? this.rawPayload,
      title: title ?? this.title,
      body: body ?? this.body,
      instanceId: instanceId ?? this.instanceId,
      reminderId: reminderId ?? this.reminderId,
      templateName: templateName ?? this.templateName,
      trackingType: trackingType ?? this.trackingType,
      dueDate: dueDate ?? this.dueDate,
      dueTime: dueTime ?? this.dueTime,
    );
  }
}

/// Service for managing local notifications
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _timezoneInitialized = false;
  static const int _notificationQuickSnoozeMinutes = 15;
  static const Duration _pendingResponseRetryInterval =
      Duration(milliseconds: 250);
  static const int _maxPendingResponseRetries = 40;
  static const Duration _navigatorWaitTimeout = Duration(seconds: 8);
  static final List<NotificationResponse> _pendingResponses =
      <NotificationResponse>[];
  static bool _isDrainingPendingResponses = false;
  static bool _didCaptureLaunchDetails = false;
  static final ValueNotifier<ActiveAlarmContext?> _activeAlarmContextNotifier =
      ValueNotifier<ActiveAlarmContext?>(null);

  static ValueListenable<ActiveAlarmContext?> get activeAlarmListenable =>
      _activeAlarmContextNotifier;
  static ActiveAlarmContext? get activeAlarmContext =>
      _activeAlarmContextNotifier.value;

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
    await _captureLaunchNotificationResponse();
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
    unawaited(_processNotificationResponse(response, allowQueue: true));
  }

  /// Handle notification action button clicks
  static Future<bool> _handleNotificationAction(
    String actionId,
    String? payload,
  ) async {
    // Handle timer notification actions (no context needed)
    if (actionId == 'stop_all' && payload == 'timer_notification') {
      TimerNotificationService.handleAction(actionId);
      return true;
    }

    // Parse action ID format: "ACTION_TYPE:instanceId" or "SNOOZE:reminderId"
    final parts = actionId.split(':');
    if (parts.length < 2) return true;

    final actionType = parts[0];
    final identifier = parts[1];

    if (actionType == 'ALARM_DISMISS') {
      if (_activeAlarmContextNotifier.value == null && identifier.isNotEmpty) {
        _activeAlarmContextNotifier.value = ActiveAlarmContext(
          rawPayload: payload ?? '',
          title: 'Alarm',
          reminderId: identifier,
        );
      }
      await dismissActiveAlarm();
      return true;
    }

    if (actionType == 'ALARM_SNOOZE_10') {
      if (payload != null && payload.startsWith('ALARM_RINGING:')) {
        await _activateAlarmFromPayload(payload);
      }
      if (_activeAlarmContextNotifier.value == null && identifier.isNotEmpty) {
        _activeAlarmContextNotifier.value = ActiveAlarmContext(
          rawPayload: payload ?? '',
          title: 'Alarm',
          reminderId: identifier,
        );
      }
      await snoozeActiveAlarm(minutes: 10);
      return true;
    }

    if (actionType == 'ALARM_OPEN') {
      if (payload != null && payload.startsWith('ALARM_RINGING:')) {
        await _activateAlarmFromPayload(payload);
      } else if (identifier.isNotEmpty) {
        _activeAlarmContextNotifier.value = ActiveAlarmContext(
          rawPayload: payload ?? '',
          title: 'Alarm',
          instanceId: identifier,
        );
      }
      return await openActiveAlarmTask();
    }

    if (actionType == 'SNOOZE') {
      _handleSnoozeAction(identifier, navigatorKey.currentContext);
      return true;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      return false;
    }

    switch (actionType) {
      case 'COMPLETE':
        await _handleCompleteAction(identifier, context);
        break;
      case 'ADD':
        await _handleAddAction(identifier, context);
        break;
      case 'TIMER':
        await _handleTimerAction(identifier, context);
        break;
    }

    return true;
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
  static Future<void> _handleTimerAction(
      String instanceId, BuildContext context) async {
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
  static bool _handleRoutineReminderNotificationTap(String payload) {
    final context = navigatorKey.currentContext;
    if (context == null) return false;

    // Extract routine ID from payload (format: "routine:routineId")
    final routineId = payload.substring('routine:'.length);
    if (routineId.isEmpty) return true;

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

    return true;
  }

  /// Handle reminder notification tap (open Queue page)
  static bool _handleReminderNotificationTap(String payload) {
    final context = navigatorKey.currentContext;
    if (context == null) return false;
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
    return true;
  }

  /// Handle alarm ringing notification tap
  static Future<bool> _handleAlarmRingingTap(String payload) async {
    await _activateAlarmFromPayload(payload);

    // Extract title and body from payload
    final parts = payload.substring('ALARM_RINGING:'.length).split('|');
    final title = parts.isNotEmpty ? parts[0] : 'Alarm';
    final body = parts.length > 1 ? parts[1] : null;

    final navigator = await _waitForNavigatorState();
    if (navigator == null) {
      return await _fallbackToQueueForAlarm(payload);
    }

    try {
      await _stopAlarmFeedback();
      navigator.pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );

      final latestNavigator = await _waitForNavigatorState();
      if (latestNavigator == null) {
        return false;
      }

      latestNavigator.push(
        MaterialPageRoute(
          builder: (context) => AlarmRingingPage(
            title: title,
            body: body,
            payload: payload, // Preserve full payload for instance + reminder IDs
          ),
          fullscreenDialog: true, // Show as full-screen modal
        ),
      );
      return true;
    } catch (e) {
      return await _fallbackToQueueForAlarm(payload);
    }
  }

  /// Handle day-end notification tap
  static bool _handleDayEndNotificationTap() {
    // Show goal dialog first, then navigate to Queue page
    final context = navigatorKey.currentContext;
    if (context == null) return false;
    // Show goal dialog first
    _showGoalDialogFromNotification(context);

    // Then navigate to Queue page
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const QueuePage(),
      ),
    );
    return true;
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
  static bool _handleMorningReminderTap() {
    final context = navigatorKey.currentContext;
    if (context == null) return false;
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
    return true;
  }

  /// Handle evening reminder notification tap
  static bool _handleEveningReminderTap() {
    final context = navigatorKey.currentContext;
    if (context == null) return false;
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
    return true;
  }

  /// Handle engagement reminder notification tap
  static bool _handleEngagementReminderTap() {
    final context = navigatorKey.currentContext;
    if (context == null) return false;
    // Navigate to Home page
    Navigator.of(context).pushNamedAndRemoveUntil(
      home,
      (route) => false,
    );
    return true;
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

  static void clearActiveAlarm() {
    _activeAlarmContextNotifier.value = null;
  }

  static Future<void> dismissActiveAlarm() async {
    await _cancelActiveAlarmNotification();
    await _stopAlarmFeedback();
    clearActiveAlarm();
  }

  static Future<void> snoozeActiveAlarm({int minutes = 10}) async {
    final alarm = _activeAlarmContextNotifier.value;
    final reminderId = alarm?.reminderId;
    if (reminderId == null || reminderId.isEmpty) {
      await dismissActiveAlarm();
      return;
    }

    try {
      await ReminderScheduler.snoozeReminder(
        reminderId: reminderId,
        durationMinutes: minutes,
      );
    } catch (e) {
      print('NotificationService: Active alarm snooze failed: $e');
    }

    await dismissActiveAlarm();
  }

  static Future<bool> openActiveAlarmTask() async {
    final alarm = _activeAlarmContextNotifier.value;
    if (alarm == null) return false;
    await _stopAlarmFeedback();
    return await _navigateToQueue(
      focusInstanceId: alarm.instanceId,
      focusTemplateId: null,
    );
  }

  static Future<bool> performPrimaryActionForActiveAlarm() async {
    final alarm = _activeAlarmContextNotifier.value;
    final instanceId = alarm?.instanceId;
    if (alarm == null || instanceId == null || instanceId.isEmpty) {
      return false;
    }

    String trackingType = alarm.trackingType ?? 'binary';
    try {
      final instance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instanceId,
      );
      trackingType = instance.templateTrackingType;

      if (trackingType == 'quantitative') {
        final currentValue = instance.currentValue ?? 0;
        final newValue = (currentValue is num) ? (currentValue + 1) : 1;
        await ActivityInstanceService.updateInstanceProgress(
          instanceId: instanceId,
          currentValue: newValue,
        );
      } else if (trackingType == 'time') {
        await ActivityInstanceService.toggleInstanceTimer(instanceId: instanceId);
      } else {
        await ActivityInstanceService.completeInstance(instanceId: instanceId);
      }
    } catch (e) {
      print('NotificationService: Active alarm primary action failed: $e');
      return false;
    }

    await dismissActiveAlarm();
    await _navigateToQueue(
      focusInstanceId: instanceId,
      focusTemplateId: null,
    );
    return true;
  }

  static Future<void> _activateAlarmFromPayload(String payload) async {
    if (!payload.startsWith('ALARM_RINGING:')) return;
    try {
      var alarm = _parseAlarmPayload(payload);
      final instanceId = alarm.instanceId;
      if (instanceId != null && instanceId.isNotEmpty) {
        try {
          final instance = await ActivityInstanceService.getUpdatedInstance(
            instanceId: instanceId,
          );
          alarm = alarm.copyWith(
            templateName: instance.templateName,
            trackingType: instance.templateTrackingType,
            dueDate: instance.dueDate,
            dueTime: instance.dueTime,
          );
        } catch (_) {}
      }
      _activeAlarmContextNotifier.value = alarm;
    } catch (e) {
      print('NotificationService: Failed to activate alarm context: $e');
    }
  }

  static ActiveAlarmContext _parseAlarmPayload(String payload) {
    final parts = payload.substring('ALARM_RINGING:'.length).split('|');
    final title = parts.isNotEmpty ? parts[0] : 'Alarm';
    final body = parts.length > 1 ? parts[1] : null;
    final instanceId = parts.length > 2 ? _normalizeAlarmField(parts[2]) : null;
    final reminderId = parts.length > 3 ? _normalizeAlarmField(parts[3]) : null;
    return ActiveAlarmContext(
      rawPayload: payload,
      title: title,
      body: body,
      instanceId: instanceId,
      reminderId: reminderId,
    );
  }

  static String? _normalizeAlarmField(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty || value == 'null') return null;
    return value;
  }

  static Future<bool> _fallbackToQueueForAlarm(String payload) async {
    await _activateAlarmFromPayload(payload);
    final alarm = _activeAlarmContextNotifier.value;
    if (alarm == null) return false;
    return await _navigateToQueue(
      focusInstanceId: alarm.instanceId,
      focusTemplateId: null,
    );
  }

  static Future<bool> _navigateToQueue({
    String? focusInstanceId,
    String? focusTemplateId,
  }) async {
    final navigator = await _waitForNavigatorState();
    if (navigator == null) return false;

    try {
      navigator.pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
      await Future.delayed(const Duration(milliseconds: 350));
      final latestNavigator = await _waitForNavigatorState();
      if (latestNavigator == null) return false;

      latestNavigator.push(
        MaterialPageRoute(
          builder: (context) => QueuePage(
            focusTemplateId: focusTemplateId,
            focusInstanceId: focusInstanceId,
          ),
        ),
      );
      return true;
    } catch (e) {
      print('NotificationService: Queue navigation failed: $e');
      return false;
    }
  }

  static Future<void> _cancelActiveAlarmNotification() async {
    final reminderId = _activeAlarmContextNotifier.value?.reminderId;
    if (reminderId == null || reminderId.isEmpty) return;
    await cancelNotification('alarm_$reminderId');
  }

  static Future<void> processPendingNotificationResponses() async {
    if (_isDrainingPendingResponses) return;
    _isDrainingPendingResponses = true;
    try {
      int retryCount = 0;
      while (_pendingResponses.isNotEmpty &&
          retryCount < _maxPendingResponseRetries) {
        final context = navigatorKey.currentContext;
        if (context == null) {
          retryCount++;
          await Future.delayed(_pendingResponseRetryInterval);
          continue;
        }

        final responses = List<NotificationResponse>.from(_pendingResponses);
        _pendingResponses.clear();

        for (final response in responses) {
          final handled =
              await _processNotificationResponse(response, allowQueue: false);
          if (!handled) {
            _pendingResponses.add(response);
          }
        }

        retryCount++;
      }

      if (_pendingResponses.any(
          (response) => (response.payload ?? '').startsWith('ALARM_RINGING:'))) {
        await _stopAlarmFeedback();
      }
    } finally {
      _isDrainingPendingResponses = false;
    }
  }

  static Future<void> _captureLaunchNotificationResponse() async {
    if (_didCaptureLaunchDetails) return;
    _didCaptureLaunchDetails = true;
    try {
      final launchDetails =
          await _notificationsPlugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp != true) return;
      final response = launchDetails?.notificationResponse;
      if (response == null) return;
      _enqueuePendingResponse(response);
    } catch (e) {
      print('NotificationService: Failed to capture launch details: $e');
    }
  }

  static void _enqueuePendingResponse(NotificationResponse response) {
    _pendingResponses.add(response);
    if (navigatorKey.currentContext != null) {
      unawaited(processPendingNotificationResponses());
    }
  }

  static Future<bool> _processNotificationResponse(
    NotificationResponse response, {
    required bool allowQueue,
  }) async {
    // Handle action button clicks
    if (response.notificationResponseType ==
            NotificationResponseType.selectedNotificationAction &&
        response.actionId != null &&
        response.actionId!.isNotEmpty) {
      final handled = await _handleNotificationAction(
        response.actionId!,
        response.payload,
      );
      if (!handled && allowQueue) {
        _enqueuePendingResponse(response);
      }
      return handled;
    }

    // Handle notification tap
    final payload = response.payload;
    if (payload == null) return true;

    bool handled = true;

    // Handle day-end notifications
    if (payload == 'day_end_notification') {
      handled = _handleDayEndNotificationTap();
    }
    // Handle morning reminder
    else if (payload == 'morning_reminder') {
      handled = _handleMorningReminderTap();
    }
    // Handle evening reminder
    else if (payload == 'evening_reminder') {
      handled = _handleEveningReminderTap();
    }
    // Handle engagement reminder
    else if (payload == 'engagement_reminder') {
      handled = _handleEngagementReminderTap();
    }
    // Handle alarm ringing
    else if (payload.startsWith('ALARM_RINGING:')) {
      handled = await _handleAlarmRingingTap(payload);
    }
    // Handle routine reminders (open Routine detail page)
    else if (payload.startsWith('routine:')) {
      handled = _handleRoutineReminderNotificationTap(payload);
    }
    // Handle reminder notifications (open Queue page)
    else if (payload.isNotEmpty && !payload.startsWith('ALARM_RINGING:')) {
      handled = _handleReminderNotificationTap(payload);
    }

    if (!handled && allowQueue) {
      _enqueuePendingResponse(response);
    }

    return handled;
  }

  static Future<NavigatorState?> _waitForNavigatorState() async {
    final deadline = DateTime.now().add(_navigatorWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final navigator = navigatorKey.currentState;
      if (navigator != null && navigator.mounted) {
        return navigator;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  static Future<void> _stopAlarmFeedback() async {
    try {
      await Vibration.cancel();
    } catch (_) {}
  }
}
