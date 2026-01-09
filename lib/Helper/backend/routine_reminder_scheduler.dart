import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/utils/notification_service.dart';
import 'package:habit_tracker/Helper/utils/reminder_config.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing reminder scheduling for routines
class RoutineReminderScheduler {
  static const String _scheduledIdsPrefix = 'routine_reminder_ids_';
  static const int _rollingWindowSize = 30; // Schedule next 30 occurrences

  /// Schedule reminders for a specific routine
  static Future<void> scheduleForRoutine(RoutineRecord routine) async {
    // Cancel existing reminders first
    await cancelForRoutine(routine.reference.id);

    if (!routine.remindersEnabled || routine.reminders.isEmpty) {
      return;
    }

    if (!routine.hasDueTime() && _needsDueTime(routine.reminders)) {
      // Can't schedule reminders without due time when using relative offsets
      return;
    }

    try {
      final reminders = ReminderConfigList.fromMapList(routine.reminders);
      final enabledReminders = reminders.where((r) => r.enabled).toList();
      if (enabledReminders.isEmpty) {
        return;
      }

      final frequencyType = routine.reminderFrequencyType;
      final dueTime = routine.dueTime;

      // Determine scheduling strategy based on frequency type
      if (frequencyType == 'specific_days' && routine.specificDays.isNotEmpty) {
        // Use native repeating for specific days of week
        await _scheduleSpecificDaysRepeating(routine, enabledReminders, dueTime);
      } else if (frequencyType == 'every_x') {
        final periodType = routine.everyXPeriodType;
        final everyXValue = routine.everyXValue;

        if (periodType == 'day' && everyXValue == 1) {
          // Daily - use native repeating
          await _scheduleDailyRepeating(routine, enabledReminders, dueTime);
        } else if (periodType == 'week' && everyXValue == 1) {
          // Weekly - treat as specific days with all 7 days
          await _scheduleSpecificDaysRepeating(
            routine,
            enabledReminders,
            dueTime,
            days: [1, 2, 3, 4, 5, 6, 7],
          );
        } else {
          // Every X days/weeks/months (X>1 or monthly) - use rolling window
          await _scheduleRollingWindow(
            routine,
            enabledReminders,
            dueTime,
            everyXValue,
            periodType,
          );
        }
      }
    } catch (e) {
      // Error scheduling reminders
      print('RoutineReminderScheduler: Error scheduling reminders: $e');
    }
  }

  /// Check if any reminder needs due time (uses relative offsets)
  static bool _needsDueTime(List<Map<String, dynamic>> reminders) {
    final configs = ReminderConfigList.fromMapList(reminders);
    return configs.any((r) =>
        r.enabled && r.fixedTimeMinutes == null && r.offsetMinutes != 0);
  }

  /// Schedule daily repeating reminders
  static Future<void> _scheduleDailyRepeating(
    RoutineRecord routine,
    List<ReminderConfig> reminders,
    String? dueTime,
  ) async {
    if (dueTime == null) return;

    final timeOfDay = TimeUtils.stringToTimeOfDay(dueTime);
    if (timeOfDay == null) return;

    for (final reminder in reminders) {
      final reminderTime = _calculateReminderTime(
        reminder: reminder,
        dueTime: timeOfDay,
      );
      if (reminderTime == null) continue;

      final reminderId = 'routine_${routine.reference.id}_${reminder.id}_daily';
      final body = _getReminderBody(routine.name, reminderTime, reminder);

      if (reminder.type == 'alarm') {
        // For alarms, use AlarmService if available, otherwise fallback to notification
        // Note: We'll use NotificationService for now as AlarmService may need routine support
        await NotificationService.scheduleReminder(
          id: reminderId,
          title: routine.name,
          scheduledTime: reminderTime,
          body: body,
          payload: 'routine:${routine.reference.id}',
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } else {
        await NotificationService.scheduleReminder(
          id: reminderId,
          title: routine.name,
          scheduledTime: reminderTime,
          body: body,
          payload: 'routine:${routine.reference.id}',
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    }
  }

  /// Schedule specific days of week repeating reminders
  static Future<void> _scheduleSpecificDaysRepeating(
    RoutineRecord routine,
    List<ReminderConfig> reminders,
    String? dueTime, {
    List<int>? days,
  }) async {
    if (dueTime == null) return;
    final specificDays = days ?? routine.specificDays;
    if (specificDays.isEmpty) return;

    final timeOfDay = TimeUtils.stringToTimeOfDay(dueTime);
    if (timeOfDay == null) return;

    for (final reminder in reminders) {
      final reminderTime = _calculateReminderTime(
        reminder: reminder,
        dueTime: timeOfDay,
      );
      if (reminderTime == null) continue;

      // Schedule one notification per day of week
      for (final dayOfWeek in specificDays) {
        final reminderId =
            'routine_${routine.reference.id}_${reminder.id}_$dayOfWeek';
        final body = _getReminderBody(routine.name, reminderTime, reminder);

        // Calculate next occurrence on this weekday
        final nextDate = _getNextWeekday(dayOfWeek, reminderTime);

        if (reminder.type == 'alarm') {
          await NotificationService.scheduleReminder(
            id: reminderId,
            title: routine.name,
            scheduledTime: nextDate,
            body: body,
            payload: 'routine:${routine.reference.id}',
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        } else {
          await NotificationService.scheduleReminder(
            id: reminderId,
            title: routine.name,
            scheduledTime: nextDate,
            body: body,
            payload: 'routine:${routine.reference.id}',
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }
      }
    }
  }

  /// Schedule using rolling window for every X days/weeks/months
  static Future<void> _scheduleRollingWindow(
    RoutineRecord routine,
    List<ReminderConfig> reminders,
    String? dueTime,
    int everyXValue,
    String periodType,
  ) async {
    if (dueTime == null) return;

    final timeOfDay = TimeUtils.stringToTimeOfDay(dueTime);
    if (timeOfDay == null) return;

    final scheduledIds = <String>[];

    // Calculate next N occurrence dates
    final occurrenceDates = _calculateOccurrenceDates(
      everyXValue: everyXValue,
      periodType: periodType,
      dueTime: timeOfDay,
      count: _rollingWindowSize,
    );

    for (final occurrenceDate in occurrenceDates) {
      for (final reminder in reminders) {
        final reminderTime = _calculateReminderTimeForDate(
          reminder: reminder,
          occurrenceDate: occurrenceDate,
          dueTime: timeOfDay,
        );
        if (reminderTime == null) continue;

        final reminderId =
            'routine_${routine.reference.id}_${reminder.id}_${occurrenceDate.millisecondsSinceEpoch}';
        scheduledIds.add(reminderId);
        final body = _getReminderBody(routine.name, reminderTime, reminder);

        await NotificationService.scheduleReminder(
          id: reminderId,
          title: routine.name,
          scheduledTime: reminderTime,
          body: body,
          payload: 'routine:${routine.reference.id}',
          // No matchDateTimeComponents - these are one-off notifications
        );
      }
    }

    // Store scheduled IDs for later cancellation
    await _storeScheduledIds(routine.reference.id, scheduledIds);
  }

  /// Calculate reminder time from reminder config and due time
  static DateTime? _calculateReminderTime({
    required ReminderConfig reminder,
    required TimeOfDay dueTime,
  }) {
    try {
      int hour;
      int minute;

      if (reminder.fixedTimeMinutes != null) {
        hour = reminder.fixedTimeMinutes! ~/ 60;
        minute = reminder.fixedTimeMinutes! % 60;
      } else {
        // Relative to due time
        final dueMinutes = dueTime.hour * 60 + dueTime.minute;
        final reminderMinutes = dueMinutes + reminder.offsetMinutes;
        hour = (reminderMinutes ~/ 60) % 24;
        minute = reminderMinutes % 60;
      }

      // Get next occurrence from today
      final now = DateTime.now();
      var scheduledTime = DateTime(now.year, now.month, now.day, hour, minute);

      // If time has passed today, schedule for tomorrow
      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      return scheduledTime;
    } catch (e) {
      return null;
    }
  }

  /// Calculate reminder time for a specific occurrence date
  static DateTime? _calculateReminderTimeForDate({
    required ReminderConfig reminder,
    required DateTime occurrenceDate,
    required TimeOfDay dueTime,
  }) {
    try {
      int hour;
      int minute;

      if (reminder.fixedTimeMinutes != null) {
        hour = reminder.fixedTimeMinutes! ~/ 60;
        minute = reminder.fixedTimeMinutes! % 60;
      } else {
        // Relative to due time
        final dueMinutes = dueTime.hour * 60 + dueTime.minute;
        final reminderMinutes = dueMinutes + reminder.offsetMinutes;
        hour = (reminderMinutes ~/ 60) % 24;
        minute = reminderMinutes % 60;
      }

      return DateTime(
        occurrenceDate.year,
        occurrenceDate.month,
        occurrenceDate.day,
        hour,
        minute,
      );
    } catch (e) {
      return null;
    }
  }

  /// Get next occurrence date for a specific weekday
  static DateTime _getNextWeekday(int dayOfWeek, DateTime baseTime) {
    final now = DateTime.now();
    final currentWeekday = now.weekday;

    int daysUntilNext = (dayOfWeek - currentWeekday) % 7;
    if (daysUntilNext == 0) {
      // Today is the target day - check if time has passed
      final targetTime = DateTime(now.year, now.month, now.day, baseTime.hour, baseTime.minute);
      if (targetTime.isBefore(now)) {
        daysUntilNext = 7; // Next week
      }
    }

    return now.add(Duration(days: daysUntilNext));
  }

  /// Calculate occurrence dates for rolling window scheduling
  static List<DateTime> _calculateOccurrenceDates({
    required int everyXValue,
    required String periodType,
    required TimeOfDay dueTime,
    required int count,
  }) {
    final now = DateTime.now();
    final occurrences = <DateTime>[];

    // Start from today
    var currentDate = DateTime(now.year, now.month, now.day, dueTime.hour, dueTime.minute);

    // If time has passed today, start from next period
    if (currentDate.isBefore(now)) {
      currentDate = _addPeriod(currentDate, everyXValue, periodType);
    }

    for (int i = 0; i < count; i++) {
      occurrences.add(currentDate);
      currentDate = _addPeriod(currentDate, everyXValue, periodType);
    }

    return occurrences;
  }

  /// Add a period to a date
  static DateTime _addPeriod(DateTime date, int value, String periodType) {
    switch (periodType) {
      case 'day':
        return date.add(Duration(days: value));
      case 'week':
        return date.add(Duration(days: value * 7));
      case 'month':
        // Approximate month as 30 days for simplicity
        return date.add(Duration(days: value * 30));
      default:
        return date.add(Duration(days: value));
    }
  }

  /// Get reminder body text
  static String _getReminderBody(
    String routineName,
    DateTime reminderTime,
    ReminderConfig reminder,
  ) {
    final timeStr = _formatTime(reminderTime);
    return 'Time to start your routine: $routineName at $timeStr';
  }

  /// Format time for display
  static String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute;
    final period = hour >= 12 ? 'pm' : 'am';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final minuteStr = minute.toString().padLeft(2, '0');
    return '$displayHour:$minuteStr $period';
  }

  /// Store scheduled notification IDs for a routine
  static Future<void> _storeScheduledIds(
    String routineId,
    List<String> notificationIds,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_scheduledIdsPrefix$routineId';
      await prefs.setStringList(key, notificationIds);
    } catch (e) {
      // Error storing IDs
    }
  }

  /// Get stored scheduled notification IDs for a routine
  static Future<List<String>> _getScheduledIds(String routineId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_scheduledIdsPrefix$routineId';
      return prefs.getStringList(key) ?? [];
    } catch (e) {
      return [];
    }
  }

  /// Cancel all reminders for a specific routine
  static Future<void> cancelForRoutine(String routineId) async {
    try {
      // Cancel repeating notifications (daily/weekly patterns use stable IDs)
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      // Try to load routine to determine which IDs to cancel
      try {
        final routineDoc = RoutineRecord.collectionForUser(userId)
            .doc(routineId)
            .get();
        final routineSnap = await routineDoc;
        if (routineSnap.exists) {
          final routine = RoutineRecord.fromSnapshot(routineSnap);
          if (routine.hasReminders()) {
            final reminders = ReminderConfigList.fromMapList(routine.reminders);
            final frequencyType = routine.reminderFrequencyType;

            if (frequencyType == 'specific_days' && routine.specificDays.isNotEmpty) {
              // Cancel specific days notifications
              for (final reminder in reminders) {
                for (final dayOfWeek in routine.specificDays) {
                  final reminderId = 'routine_${routineId}_${reminder.id}_$dayOfWeek';
                  await NotificationService.cancelNotification(reminderId);
                }
              }
            } else if (frequencyType == 'every_x') {
              final periodType = routine.everyXPeriodType;
              final everyXValue = routine.everyXValue;

              if (periodType == 'day' && everyXValue == 1) {
                // Cancel daily notifications
                for (final reminder in reminders) {
                  final reminderId = 'routine_${routineId}_${reminder.id}_daily';
                  await NotificationService.cancelNotification(reminderId);
                }
              } else {
                // Cancel rolling window notifications
                final scheduledIds = await _getScheduledIds(routineId);
                for (final id in scheduledIds) {
                  await NotificationService.cancelNotification(id);
                }
                await _clearScheduledIds(routineId);
              }
            }
          }
        }
      } catch (e) {
        // If we can't load routine, try to cancel common IDs
      }

      // Cancel rolling window notifications (in case routine was deleted)
      final scheduledIds = await _getScheduledIds(routineId);
      for (final id in scheduledIds) {
        await NotificationService.cancelNotification(id);
      }
      await _clearScheduledIds(routineId);
    } catch (e) {
      // Error canceling reminders
      print('RoutineReminderScheduler: Error canceling reminders: $e');
    }
  }

  /// Clear stored scheduled IDs for a routine
  static Future<void> _clearScheduledIds(String routineId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_scheduledIdsPrefix$routineId';
      await prefs.remove(key);
    } catch (e) {
      // Error clearing IDs
    }
  }

  /// Schedule reminders for all active routines
  static Future<void> scheduleAllActiveRoutineReminders() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      final routinesQuery = RoutineRecord.collectionForUser(userId)
          .where('isActive', isEqualTo: true)
          .where('remindersEnabled', isEqualTo: true);

      final routinesSnapshot = await routinesQuery.get();
      for (final doc in routinesSnapshot.docs) {
        final routine = RoutineRecord.fromSnapshot(doc);
        await scheduleForRoutine(routine);
      }
    } catch (e) {
      // Error scheduling all reminders
      print('RoutineReminderScheduler: Error scheduling all reminders: $e');
    }
  }
}

