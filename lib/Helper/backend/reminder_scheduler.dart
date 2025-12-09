import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/utils/notification_service.dart';
import 'package:habit_tracker/Helper/utils/alarm_service.dart';
import 'package:habit_tracker/Helper/utils/reminder_config.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

/// Service for managing reminder scheduling for tasks and habits
class ReminderScheduler {
  /// Schedule reminders for a specific instance based on template reminders
  static Future<void> scheduleReminderForInstance(
      ActivityInstanceRecord instance) async {
    if (!_shouldScheduleReminder(instance)) {
      return;
    }
    try {
      // Get the template to access reminder configurations
      final userId = currentUserUid;
      if (userId.isEmpty) return;
      final templateRef = ActivityRecord.collectionForUser(userId)
          .doc(instance.templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) {
        return;
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);
      
      // Get reminders from template
      List<ReminderConfig> reminders = [];
      if (template.hasReminders()) {
        reminders = ReminderConfigList.fromMapList(template.reminders);
      }
      
      // If no reminders configured, use default (10 minutes before)
      if (reminders.isEmpty) {
        final reminderTime = _calculateReminderTime(instance);
        if (reminderTime != null && reminderTime.isAfter(DateTime.now())) {
          await NotificationService.scheduleReminder(
            id: instance.reference.id,
            title: instance.templateName,
            scheduledTime: reminderTime,
            body: 'Due in 10 minutes',
            payload: instance.reference.id,
          );
        }
        return;
      }
      
      // Schedule each configured reminder
      for (final reminder in reminders) {
        if (!reminder.enabled) continue;
        
        final reminderTime = _calculateReminderTimeFromOffset(
          instance: instance,
          offsetMinutes: reminder.offsetMinutes,
        );
        
        if (reminderTime == null || !reminderTime.isAfter(DateTime.now())) {
          continue;
        }
        
        // Generate unique ID for this reminder
        final reminderId = '${instance.reference.id}_${reminder.id}';
        
        if (reminder.type == 'alarm') {
          // Schedule as system alarm
          if (AlarmService.isSupported()) {
            await AlarmService.scheduleAlarm(
              id: reminderId.hashCode,
              scheduledTime: reminderTime,
              title: instance.templateName,
              body: _getReminderBody(reminder.offsetMinutes),
            );
          } else {
            // Fallback to notification if alarms not supported
            await NotificationService.scheduleReminder(
              id: reminderId,
              title: instance.templateName,
              scheduledTime: reminderTime,
              body: _getReminderBody(reminder.offsetMinutes),
              payload: instance.reference.id,
            );
          }
        } else {
          // Schedule as notification
          await NotificationService.scheduleReminder(
            id: reminderId,
            title: instance.templateName,
            scheduledTime: reminderTime,
            body: _getReminderBody(reminder.offsetMinutes),
            payload: instance.reference.id,
          );
        }
      }
    } catch (e) {
      print('ReminderScheduler: Error scheduling reminders: $e');
    }
  }
  
  /// Calculate reminder time based on offset from due time
  static DateTime? _calculateReminderTimeFromOffset({
    required ActivityInstanceRecord instance,
    required int offsetMinutes,
  }) {
    try {
      if (instance.dueDate == null) return null;
      
      DateTime dueDateTime;
      if (instance.hasDueTime()) {
        final timeOfDay = TimeUtils.stringToTimeOfDay(instance.dueTime);
        if (timeOfDay == null) return null;
        dueDateTime = DateTime(
          instance.dueDate!.year,
          instance.dueDate!.month,
          instance.dueDate!.day,
          timeOfDay.hour,
          timeOfDay.minute,
        );
      } else {
        // If no due time, use start of day
        dueDateTime = DateTime(
          instance.dueDate!.year,
          instance.dueDate!.month,
          instance.dueDate!.day,
        );
      }
      
      // Calculate reminder time by adding offset
      final reminderTime = dueDateTime.add(Duration(minutes: offsetMinutes));
      return reminderTime;
    } catch (e) {
      return null;
    }
  }
  
  /// Get reminder body text based on offset
  static String _getReminderBody(int offsetMinutes) {
    if (offsetMinutes == 0) {
      return 'Due now';
    } else if (offsetMinutes < 0) {
      final absMinutes = offsetMinutes.abs();
      if (absMinutes < 60) {
        return 'Due in ${absMinutes} minute${absMinutes == 1 ? '' : 's'}';
      } else if (absMinutes < 1440) {
        final hours = absMinutes ~/ 60;
        return 'Due in ${hours} hour${hours == 1 ? '' : 's'}';
      } else {
        final days = absMinutes ~/ 1440;
        return 'Due in ${days} day${days == 1 ? '' : 's'}';
      }
    } else {
      return 'Reminder';
    }
  }

  /// Cancel all reminders for a specific instance
  static Future<void> cancelReminderForInstance(String instanceId) async {
    try {
      // Cancel default notification
      await NotificationService.cancelNotification(instanceId);
      
      // Cancel all reminder-specific notifications/alarms
      // We need to get the template to know all reminder IDs
      try {
        final instances = await queryAllInstances(userId: currentUserUid);
        final instance = instances.firstWhere(
          (i) => i.reference.id == instanceId,
          orElse: () => instances.first,
        );
        
        final userId = currentUserUid;
        if (userId.isEmpty) return;
        final templateRef = ActivityRecord.collectionForUser(userId)
            .doc(instance.templateId);
        final templateDoc = await templateRef.get();
        if (templateDoc.exists) {
          final template = ActivityRecord.fromSnapshot(templateDoc);
          if (template.hasReminders()) {
            final reminders = ReminderConfigList.fromMapList(template.reminders);
            for (final reminder in reminders) {
              final reminderId = '${instanceId}_${reminder.id}';
              await NotificationService.cancelNotification(reminderId);
              if (reminder.type == 'alarm' && AlarmService.isSupported()) {
                await AlarmService.cancelAlarm(reminderId.hashCode);
              }
            }
          }
        }
      } catch (e) {
        // If we can't get template, just cancel the main notification
      }
    } catch (e) {
      print('ReminderScheduler: Error canceling reminders: $e');
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
        return;
      }
      // Get all active instances
      final instances = await queryAllInstances(userId: userId);
      for (final instance in instances) {
        if (_shouldScheduleReminder(instance)) {
          await scheduleReminderForInstance(instance);
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
    // Skip if no due date
    if (instance.dueDate == null) {
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
