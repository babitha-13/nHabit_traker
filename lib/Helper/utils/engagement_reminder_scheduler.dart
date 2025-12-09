import 'package:habit_tracker/Helper/utils/notification_service.dart';
import 'package:habit_tracker/Helper/utils/engagement_tracker.dart';
import 'package:habit_tracker/Helper/backend/notification_preferences_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'dart:math';

/// Service for scheduling periodic engagement reminders when app hasn't been opened
/// All business logic for engagement reminder scheduling is centralized here (#REFACTOR_NOW compliance)
class EngagementReminderScheduler {
  // Track last engagement reminder sent date to limit frequency
  static DateTime? _lastEngagementReminderDate;

  /// Engagement reminder messages (varied to avoid repetition)
  static final List<String> _engagementMessages = [
    'Haven\'t seen you today! Check in on your progress 📊',
    'Your habits are waiting! Come back and keep the streak going 🔥',
    'Quick check-in time! See how you\'re doing today ✨',
    'Time to check in! Your progress is waiting for you 📈',
    'Don\'t forget your goals! Come back and track your progress 💪',
  ];

  /// Schedule next engagement reminder if needed
  static Future<void> scheduleNextEngagementReminder(String userId) async {
    try {
      // Check if engagement reminders are enabled
      final isEnabled =
          await NotificationPreferencesService.isEngagementReminderEnabled(
              userId);
      if (!isEnabled) {
        await cancelEngagementReminders(userId);
        return;
      }

      // Check if we should send a reminder
      final shouldSend = await EngagementTracker.shouldSendEngagementReminder(
          userId);
      if (!shouldSend) {
        await cancelEngagementReminders(userId);
        return;
      }

      // Check if we've already sent a reminder today
      final now = DateTime.now();
      if (_lastEngagementReminderDate != null) {
        final lastDate = _lastEngagementReminderDate!;
        if (lastDate.year == now.year &&
            lastDate.month == now.month &&
            lastDate.day == now.day) {
          // Already sent today, don't send another
          return;
        }
      }

      // Check if we're in quiet hours
      final inQuietHours = await EngagementTracker.isInQuietHours(userId);
      if (inQuietHours) {
        // Schedule for after quiet hours end
        final prefs = await NotificationPreferencesService
            .getUserNotificationPreferences(userId);
        final quietEnd = prefs['quiet_hours_end'] as int? ?? 6; // 6 AM

        var scheduledTime = DateTime(
          now.year,
          now.month,
          now.day,
          quietEnd,
          0,
        );

        // If quiet hours end has passed today, schedule for tomorrow
        if (scheduledTime.isBefore(now)) {
          scheduledTime = scheduledTime.add(const Duration(days: 1));
        }

        await NotificationService.scheduleReminder(
          id: 'engagement_reminder',
          title: 'We Miss You!',
          body: _getRandomMessage(),
          scheduledTime: scheduledTime,
          payload: 'engagement_reminder',
        );
        _lastEngagementReminderDate = scheduledTime;
        return;
      }

      // Schedule for a few hours from now (but not too soon)
      final thresholdHours =
          await NotificationPreferencesService.getEngagementReminderHours(
              userId);

      // Schedule for threshold hours from last opened, or 2 hours from now, whichever is later
      final lastOpened = await EngagementTracker.getLastOpenedTime(userId);
      DateTime scheduledTime;
      if (lastOpened != null) {
        scheduledTime = lastOpened.add(Duration(hours: thresholdHours));
        // If that time has passed, schedule for 2 hours from now
        if (scheduledTime.isBefore(now)) {
          scheduledTime = now.add(const Duration(hours: 2));
        }
      } else {
        scheduledTime = now.add(const Duration(hours: 2));
      }

      // Make sure it's not too soon (at least 1 hour from now)
      if (scheduledTime.difference(now).inHours < 1) {
        scheduledTime = now.add(const Duration(hours: 1));
      }

      await NotificationService.scheduleReminder(
        id: 'engagement_reminder',
        title: 'We Miss You!',
        body: _getRandomMessage(),
        scheduledTime: scheduledTime,
        payload: 'engagement_reminder',
      );
      _lastEngagementReminderDate = scheduledTime;
    } catch (e) {
      print(
          'EngagementReminderScheduler: Error scheduling engagement reminder: $e');
    }
  }

  /// Check and schedule engagement reminder if needed
  static Future<void> checkAndScheduleEngagementReminder(
      String userId) async {
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
      _lastEngagementReminderDate = null;
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
      final userId = currentUserUid;
      if (userId.isEmpty) {
        return;
      }
      await checkAndScheduleEngagementReminder(userId);
    } catch (e) {
      print(
          'EngagementReminderScheduler: Error initializing engagement reminders: $e');
    }
  }
}

