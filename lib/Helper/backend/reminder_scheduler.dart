import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/notification_service.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

/// Service for managing reminder scheduling for tasks and habits
class ReminderScheduler {
  /// Schedule a reminder for a specific instance
  static Future<void> scheduleReminderForInstance(
      ActivityInstanceRecord instance) async {
    if (!_shouldScheduleReminder(instance)) {
      print(
          'ReminderScheduler: Skipping reminder for ${instance.templateName} - conditions not met');
      return;
    }

    try {
      // Calculate reminder time (10 minutes before due time)
      final reminderTime = _calculateReminderTime(instance);

      if (reminderTime == null) {
        print(
            'ReminderScheduler: Could not calculate reminder time for ${instance.templateName}');
        return;
      }

      // Only schedule if in the future
      if (reminderTime.isAfter(DateTime.now())) {
        await NotificationService.scheduleReminder(
          id: instance.reference.id,
          title: instance.templateName,
          scheduledTime: reminderTime,
          body: 'Due in 10 minutes',
          payload: instance.reference.id,
        );
        print(
            'ReminderScheduler: Scheduled reminder for ${instance.templateName} at $reminderTime');
      } else {
        print(
            'ReminderScheduler: Skipping past reminder time for ${instance.templateName}');
      }
    } catch (e) {
      print(
          'ReminderScheduler: Error scheduling reminder for ${instance.templateName}: $e');
    }
  }

  /// Cancel reminder for a specific instance
  static Future<void> cancelReminderForInstance(String instanceId) async {
    try {
      await NotificationService.cancelNotification(instanceId);
      print('ReminderScheduler: Cancelled reminder for instance $instanceId');
    } catch (e) {
      print(
          'ReminderScheduler: Error cancelling reminder for instance $instanceId: $e');
    }
  }

  /// Reschedule reminder for a specific instance
  static Future<void> rescheduleReminderForInstance(
      ActivityInstanceRecord instance) async {
    // First cancel existing reminder
    await cancelReminderForInstance(instance.reference.id);

    // Then schedule new one if conditions are met
    await scheduleReminderForInstance(instance);
  }

  /// Schedule reminders for all pending instances
  static Future<void> scheduleAllPendingReminders() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) {
        print(
            'ReminderScheduler: No user ID available for scheduling reminders');
        return;
      }

      // Get all active instances
      final instances = await queryAllInstances(userId: userId);

      int scheduledCount = 0;
      for (final instance in instances) {
        if (_shouldScheduleReminder(instance)) {
          await scheduleReminderForInstance(instance);
          scheduledCount++;
        }
      }

      print(
          'ReminderScheduler: Scheduled $scheduledCount reminders for pending instances');
    } catch (e) {
      print('ReminderScheduler: Error scheduling all pending reminders: $e');
    }
  }

  /// Check if a reminder should be scheduled for this instance
  static bool _shouldScheduleReminder(ActivityInstanceRecord instance) {
    // Skip if completed
    if (instance.status == 'completed') {
      print(
          'ReminderScheduler: Skipping completed instance ${instance.templateName}');
      return false;
    }

    // Skip if skipped
    if (instance.status == 'skipped') {
      print(
          'ReminderScheduler: Skipping skipped instance ${instance.templateName}');
      return false;
    }

    // Skip if currently snoozed
    if (instance.snoozedUntil != null &&
        DateTime.now().isBefore(instance.snoozedUntil!)) {
      print(
          'ReminderScheduler: Skipping snoozed instance ${instance.templateName} until ${instance.snoozedUntil}');
      return false;
    }

    // Skip if inactive
    if (!instance.isActive) {
      print(
          'ReminderScheduler: Skipping inactive instance ${instance.templateName}');
      return false;
    }

    // Skip if no due date or time
    if (instance.dueDate == null || !instance.hasDueTime()) {
      print(
          'ReminderScheduler: Skipping instance ${instance.templateName} - no due date/time');
      return false;
    }

    return true;
  }

  /// Calculate reminder time (10 minutes before due time)
  static DateTime? _calculateReminderTime(ActivityInstanceRecord instance) {
    try {
      // Parse the due time string to TimeOfDay
      final timeOfDay = TimeUtils.stringToTimeOfDay(instance.dueTime);
      if (timeOfDay == null) {
        print(
            'ReminderScheduler: Could not parse due time ${instance.dueTime}');
        return null;
      }

      // Combine date and time in local timezone
      final dueDateTime = DateTime(
        instance.dueDate!.year,
        instance.dueDate!.month,
        instance.dueDate!.day,
        timeOfDay.hour,
        timeOfDay.minute,
      );

      // Calculate reminder time (10 minutes before)
      final reminderTime = dueDateTime.subtract(const Duration(minutes: 10));

      print(
          'ReminderScheduler: Due time: $dueDateTime, Reminder time: $reminderTime, Current time: ${DateTime.now()}');
      print(
          'ReminderScheduler: Time difference: ${reminderTime.difference(DateTime.now()).inMinutes} minutes');

      return reminderTime;
    } catch (e) {
      print('ReminderScheduler: Error calculating reminder time: $e');
      return null;
    }
  }

  /// Check for expired snoozes and reschedule reminders
  static Future<void> checkExpiredSnoozes() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      final instances = await queryAllInstances(userId: userId);
      final now = DateTime.now();

      int rescheduledCount = 0;
      for (final instance in instances) {
        // Check if snooze has expired
        if (instance.snoozedUntil != null &&
            now.isAfter(instance.snoozedUntil!) &&
            instance.status == 'pending' &&
            instance.isActive) {
          print(
              'ReminderScheduler: Snooze expired for ${instance.templateName}, rescheduling reminder');
          await scheduleReminderForInstance(instance);
          rescheduledCount++;
        }
      }

      if (rescheduledCount > 0) {
        print(
            'ReminderScheduler: Rescheduled $rescheduledCount reminders for expired snoozes');
      }
    } catch (e) {
      print('ReminderScheduler: Error checking expired snoozes: $e');
    }
  }
}
