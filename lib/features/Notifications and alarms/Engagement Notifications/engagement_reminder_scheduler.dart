import 'dart:math';

import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/Engagement%20Notifications/engagement_tracker.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/notification_preferences_service.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/notification_service.dart';

/// Service for scheduling periodic engagement reminders when app hasn't been opened
/// All business logic for engagement reminder scheduling is centralized here (#REFACTOR_NOW compliance)
class EngagementReminderScheduler {
  /// Engagement reminder messages (varied to avoid repetition)
  static final List<String> _engagementMessages = [
    'Haven\'t seen you today. Check in on your progress.',
    'Your habits are waiting. Come back and keep the streak going.',
    'Quick check-in time. See how you are doing today.',
    'Time to check in. Your progress is waiting for you.',
    'Do not forget your goals. Come back and track your progress.',
  ];

  /// Schedule next engagement reminder if needed.
  ///
  /// This should be called when the app transitions away from foreground.
  static Future<void> scheduleNextEngagementReminder(String userId) async {
    try {
      final isEnabled =
          await NotificationPreferencesService.isEngagementReminderEnabled(
              userId);
      if (!isEnabled) {
        await cancelEngagementReminders(userId);
        return;
      }

      // Clear stale schedule and rebuild it from current state.
      await cancelEngagementReminders(userId);

      final now = DateService.currentDate;
      final thresholdHours =
          await NotificationPreferencesService.getEngagementReminderHours(
              userId);
      final prefs =
          await NotificationPreferencesService.getUserNotificationPreferences(
              userId);
      final quietStart = prefs['quiet_hours_start'] as int? ?? 22;
      final quietEnd = prefs['quiet_hours_end'] as int? ?? 6;

      final lastOpened = await EngagementTracker.getLastOpenedTime(userId);
      var scheduledTime = (lastOpened ?? now).add(
        Duration(hours: thresholdHours),
      );

      // If already overdue, send a delayed nudge instead of immediate delivery.
      if (!scheduledTime.isAfter(now)) {
        scheduledTime = now.add(const Duration(hours: 1));
      }

      // Never deliver during quiet hours.
      scheduledTime = _adjustForQuietHours(scheduledTime, quietStart, quietEnd);

      await NotificationService.scheduleReminder(
        id: 'engagement_reminder',
        title: 'We Miss You!',
        body: _getRandomMessage(),
        scheduledTime: scheduledTime,
        payload: 'engagement_reminder',
      );
    } catch (e) {
      print(
          'EngagementReminderScheduler: Error scheduling engagement reminder: $e');
    }
  }

  /// Check and schedule engagement reminder if needed
  static Future<void> checkAndScheduleEngagementReminder(String userId) async {
    try {
      await scheduleNextEngagementReminder(userId);
    } catch (e) {
      print(
          'EngagementReminderScheduler: Error checking engagement reminder: $e');
    }
  }

  /// Cancel all engagement reminders
  static Future<void> cancelEngagementReminders(String userId) async {
    try {
      await NotificationService.cancelNotification('engagement_reminder');
    } catch (e) {
      print(
          'EngagementReminderScheduler: Error canceling engagement reminders: $e');
    }
  }

  /// Get a random engagement message
  static String _getRandomMessage() {
    final random = Random();
    return _engagementMessages[random.nextInt(_engagementMessages.length)];
  }

  /// Initialize engagement reminder checking for current user
  static Future<void> initializeEngagementReminders() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        return;
      }

      // App is active during initialization; keep last-open fresh and avoid
      // foreground "we miss you" notifications.
      await EngagementTracker.recordAppOpened(userId);
      await cancelEngagementReminders(userId);
    } catch (e) {
      print(
          'EngagementReminderScheduler: Error initializing engagement reminders: $e');
    }
  }

  static DateTime _adjustForQuietHours(
    DateTime scheduledTime,
    int quietStart,
    int quietEnd,
  ) {
    if (!_isInQuietHours(scheduledTime.hour, quietStart, quietEnd)) {
      return scheduledTime;
    }

    var quietEndTime = DateTime(
      scheduledTime.year,
      scheduledTime.month,
      scheduledTime.day,
      quietEnd,
      0,
    );
    if (!quietEndTime.isAfter(scheduledTime)) {
      quietEndTime = quietEndTime.add(const Duration(days: 1));
    }
    return quietEndTime;
  }

  static bool _isInQuietHours(int hour, int quietStart, int quietEnd) {
    if (quietStart > quietEnd) {
      return hour >= quietStart || hour < quietEnd;
    }
    return hour >= quietStart && hour < quietEnd;
  }
}
