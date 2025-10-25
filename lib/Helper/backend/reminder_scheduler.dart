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
      return;
    }
    try {
      // Calculate reminder time (10 minutes before due time)
      final reminderTime = _calculateReminderTime(instance);
      if (reminderTime == null) {
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
      } else {}
    } catch (e) {}
  }

  /// Cancel reminder for a specific instance
  static Future<void> cancelReminderForInstance(String instanceId) async {
    try {
      await NotificationService.cancelNotification(instanceId);
    } catch (e) {}
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
    } catch (e) {}
  }

  /// Check if a reminder should be scheduled for this instance
  static bool _shouldScheduleReminder(ActivityInstanceRecord instance) {
    // Skip if completed
    if (instance.status == 'completed') {
      return false;
    }
    // Skip if skipped
    if (instance.status == 'skipped') {
      return false;
    }
    // Skip if currently snoozed
    if (instance.snoozedUntil != null &&
        DateTime.now().isBefore(instance.snoozedUntil!)) {
      return false;
    }
    // Skip if inactive
    if (!instance.isActive) {
      return false;
    }
    // Skip if no due date or time
    if (instance.dueDate == null || !instance.hasDueTime()) {
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
      return reminderTime;
    } catch (e) {
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
          await scheduleReminderForInstance(instance);
          rescheduledCount++;
        }
      }
      if (rescheduledCount > 0) {}
    } catch (e) {}
  }
}
