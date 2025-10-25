import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter/material.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/Screens/Queue/queue_page.dart';
import 'package:habit_tracker/Screens/Goals/goal_dialog.dart';
import 'package:habit_tracker/Helper/backend/day_end_scheduler.dart';
import 'package:habit_tracker/Helper/backend/goal_service.dart';

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
    // Handle day-end notifications
    if (response.payload == 'day_end_notification') {
      _handleDayEndNotificationTap();
    }
  }

  /// Handle day-end notification tap
  static void _handleDayEndNotificationTap() {
    // Show goal dialog first, then navigate to Queue page
    final context = navigatorKey.currentContext;
    if (context != null) {
      // Show goal dialog first
      _showGoalDialogFromNotification(context);

      // Then navigate to Queue page and show snooze bottom sheet
      Navigator.of(context)
          .push(
        MaterialPageRoute(
          builder: (context) => const QueuePage(),
        ),
      )
          .then((_) {
        // Show snooze bottom sheet after a short delay to ensure the page is loaded
        Future.delayed(const Duration(milliseconds: 500), () {
          final currentContext = navigatorKey.currentContext;
          if (currentContext != null) {
            _showSnoozeBottomSheet(currentContext);
          }
        });
      });
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

  /// Show snooze bottom sheet
  static void _showSnoozeBottomSheet(BuildContext context) {
    // Show the snooze bottom sheet directly
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SnoozeBottomSheet(),
    );
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

/// Snooze bottom sheet widget for notification service
class _SnoozeBottomSheet extends StatefulWidget {
  @override
  _SnoozeBottomSheetState createState() => _SnoozeBottomSheetState();
}

class _SnoozeBottomSheetState extends State<_SnoozeBottomSheet> {
  bool _isLoading = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snoozeStatus = DayEndScheduler.getSnoozeStatus();
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Title
          Text(
            'Day Ending Soon',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // Description
          Text(
            'You have ${snoozeStatus['remainingSnooze']} minutes of snooze time remaining. Extend your day to finish more tasks!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          // Current processing time
          if (snoozeStatus['scheduledTime'] != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Processing Time',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        Text(
                          _formatTime(
                              DateTime.parse(snoozeStatus['scheduledTime'])),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          // Snooze buttons
          Text(
            'Snooze Options',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SnoozeButton(
                  minutes: 15,
                  label: '15 min',
                  enabled: snoozeStatus['canSnooze15'],
                  onPressed: () => _handleSnooze(15),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SnoozeButton(
                  minutes: 30,
                  label: '30 min',
                  enabled: snoozeStatus['canSnooze30'],
                  onPressed: () => _handleSnooze(30),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SnoozeButton(
                  minutes: 60,
                  label: '1 hr',
                  enabled: snoozeStatus['canSnooze60'],
                  onPressed: () => _handleSnooze(60),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // View Tasks button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'View Tasks',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _handleSnooze(int minutes) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final success = await DayEndScheduler.snooze(minutes);
      if (success) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Day-end processing snoozed for $minutes minutes'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot snooze - maximum time limit reached'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error snoozing: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

/// Snooze button widget for notification service
class _SnoozeButton extends StatelessWidget {
  final int minutes;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  const _SnoozeButton({
    required this.minutes,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceVariant,
        foregroundColor: enabled
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface.withOpacity(0.5),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: enabled ? 2 : 0,
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
