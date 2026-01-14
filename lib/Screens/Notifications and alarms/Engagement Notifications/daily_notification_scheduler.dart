import 'package:habit_tracker/Screens/Notifications%20and%20alarms/notification_service.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/notification_preferences_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

/// Service for scheduling daily recurring notifications (morning and evening reminders)
/// All business logic for daily notification scheduling is centralized here (#REFACTOR_NOW compliance)
class DailyNotificationScheduler {
  /// Schedule morning reminder for today or tomorrow if time has passed
  static Future<void> scheduleMorningReminder(String userId) async {
    try {
      // Check if morning reminder is enabled
      final isEnabled =
          await NotificationPreferencesService.isMorningReminderEnabled(userId);
      if (!isEnabled) {
        await cancelMorningReminder();
        return;
      }

      // Get morning notification time
      final morningTime =
          await NotificationPreferencesService.getMorningNotificationTime(
              userId);
      if (morningTime == null) {
        return;
      }

      // Calculate next notification time
      final now = DateTime.now();
      var scheduledTime = DateTime(
        now.year,
        now.month,
        now.day,
        morningTime.hour,
        morningTime.minute,
      );

      // If time has passed today, schedule for tomorrow
      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      // Cancel existing morning reminder
      await cancelMorningReminder();

      // Schedule the notification
      await NotificationService.scheduleReminder(
        id: 'daily_morning_reminder',
        title: 'Good Morning! 🌅',
        body:
            'Time to review your day and plan your habits. Let\'s make today count!',
        scheduledTime: scheduledTime,
        payload: 'morning_reminder',
      );
    } catch (e) {
      print(
          'DailyNotificationScheduler: Error scheduling morning reminder: $e');
    }
  }

  /// Schedule evening reminder for today or tomorrow if time has passed
  static Future<void> scheduleEveningReminder(String userId) async {
    try {
      // Check if evening reminder is enabled
      final isEnabled =
          await NotificationPreferencesService.isEveningReminderEnabled(userId);
      if (!isEnabled) {
        await cancelEveningReminder();
        return;
      }

      // Get evening notification time
      final eveningTime =
          await NotificationPreferencesService.getEveningNotificationTime(
              userId);
      if (eveningTime == null) {
        return;
      }

      // Calculate next notification time
      final now = DateTime.now();
      var scheduledTime = DateTime(
        now.year,
        now.month,
        now.day,
        eveningTime.hour,
        eveningTime.minute,
      );

      // If time has passed today, schedule for tomorrow
      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      // Cancel existing evening reminder
      await cancelEveningReminder();

      // Schedule the notification
      await NotificationService.scheduleReminder(
        id: 'daily_evening_reminder',
        title: 'Evening Check-in! 🌙',
        body:
            'Finish up any pending tasks before the day ends. You\'ve got this!',
        scheduledTime: scheduledTime,
        payload: 'evening_reminder',
      );
    } catch (e) {
      print(
          'DailyNotificationScheduler: Error scheduling evening reminder: $e');
    }
  }

  /// Cancel morning reminder
  static Future<void> cancelMorningReminder() async {
    try {
      await NotificationService.cancelNotification('daily_morning_reminder');
    } catch (e) {
      print('DailyNotificationScheduler: Error canceling morning reminder: $e');
    }
  }

  /// Cancel evening reminder
  static Future<void> cancelEveningReminder() async {
    try {
      await NotificationService.cancelNotification('daily_evening_reminder');
    } catch (e) {
      print('DailyNotificationScheduler: Error canceling evening reminder: $e');
    }
  }

  /// Reschedule all daily notifications based on user preferences
  static Future<void> rescheduleAllDailyNotifications(String userId) async {
    try {
      await scheduleMorningReminder(userId);
      await scheduleEveningReminder(userId);
    } catch (e) {
      print(
          'DailyNotificationScheduler: Error rescheduling daily notifications: $e');
    }
  }

  /// Initialize daily notifications for current user
  static Future<void> initializeDailyNotifications() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) {
        return;
      }
      await rescheduleAllDailyNotifications(userId);
    } catch (e) {
      print(
          'DailyNotificationScheduler: Error initializing daily notifications: $e');
    }
  }
}
