import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/notification_service.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/alarm_service.dart';
import 'package:habit_tracker/features/activity%20editor/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_repository.dart';

/// Service for managing reminder scheduling for tasks and habits
class ReminderScheduler {
  /// Schedule reminders for a specific instance based on template reminders
  static Future<void> scheduleReminderForInstance(
    ActivityInstanceRecord instance, {
    ActivityRecord? templateOverride,
  }) async {
    if (!_shouldScheduleReminder(instance)) {
      return;
    }
    try {
      ActivityRecord? template = templateOverride;
      if (template == null) {
        // Get the template to access reminder configurations
        final userId = await waitForCurrentUserUid();
        if (userId.isEmpty) return;
        final templateRef =
            ActivityRecord.collectionForUser(userId).doc(instance.templateId);
        final templateDoc = await templateRef.get();
        if (!templateDoc.exists) {
          return;
        }
        template = ActivityRecord.fromSnapshot(templateDoc);
      }

      // Get reminders from template
      List<ReminderConfig> reminders = [];
      if (template.hasReminders()) {
        reminders = ReminderConfigList.fromMapList(template.reminders);
      }

      // If no reminders configured, use default (10 minutes before)
      if (reminders.isEmpty) {
        final reminderTime = _calculateReminderTime(instance);
        // Ensure time is in future or today (for recurring checks)
        // If it's recurring daily/weekly, we can schedule even if time passed today (for next occurrence)
        bool canSchedule = false;
        if (reminderTime != null) {
          if (reminderTime.isAfter(DateService.currentDate)) {
            canSchedule = true;
          } else if (template.isRecurring) {
            // For recurring, allow past times if we use matchDateTimeComponents
            // Routine Main page below handles this better, but for default reminder:
            canSchedule = true;
          }
        }

        if (canSchedule && reminderTime != null) {
          String reminderId;
          DateTimeComponents? recurrence;

          if (template.isRecurring) {
            // Handle default reminder recurrence
            if (template.frequencyType == 'specific_days' ||
                (template.everyXPeriodType == 'week' &&
                    template.everyXValue == 1)) {
              recurrence = DateTimeComponents.dayOfWeekAndTime;
              reminderId =
                  '${template.reference.id}_default_${reminderTime.weekday}';
            } else if (template.everyXPeriodType == 'day' &&
                template.everyXValue == 1) {
              recurrence = DateTimeComponents.time;
              reminderId = '${template.reference.id}_default_daily';
            } else {
              reminderId = '${instance.reference.id}';
            }
          } else {
            reminderId = instance.reference.id;
          }

          // Only schedule if time is future OR it's recurring (which auto-handles future)
          // But local_notifications needs future time for the *first* trigger usually?
          // Actually zonedSchedule with matchDateTimeComponents handles past times by scheduling next.

          // Calculate due datetime for display
          final dueDateTime = _buildReminderBaseTime(
            instance: instance,
            fixedTimeMinutes: null, // Use due time, not fixed time
          );

          // Build notification actions
          final actions = _buildNotificationActions(instance, reminderId);

          await NotificationService.scheduleReminder(
            id: reminderId,
            title: instance.templateName,
            scheduledTime: reminderTime,
            body: _getReminderBody(
              dueDateTime: dueDateTime,
              reminderTime: reminderTime,
              offsetMinutes: -10, // Default is 10 minutes before
            ),
            payload: instance
                .templateId, // Use templateId for payload to find active instance later
            matchDateTimeComponents: recurrence,
            actions: actions,
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
          fixedTimeMinutes: reminder.fixedTimeMinutes,
        );

        if (reminderTime == null) continue;

        // Check if we should schedule
        bool shouldSchedule = reminderTime.isAfter(DateService.currentDate);

        // Determine recurrence and ID
        String reminderId;
        DateTimeComponents? recurrence;

        if (template.isRecurring) {
          if (template.frequencyType == 'specific_days' ||
              (template.everyXPeriodType == 'week' &&
                  template.everyXValue == 1)) {
            recurrence = DateTimeComponents.dayOfWeekAndTime;
            reminderId =
                '${template.reference.id}_${reminder.id}_${reminderTime.weekday}';
            shouldSchedule = true; // Always try to schedule recurring
          } else if (template.everyXPeriodType == 'day' &&
              template.everyXValue == 1) {
            recurrence = DateTimeComponents.time;
            reminderId = '${template.reference.id}_${reminder.id}_daily';
            shouldSchedule = true; // Always try to schedule recurring
          } else {
            // Complex recurrence or one-off logic fallback
            reminderId = '${instance.reference.id}_${reminder.id}';
          }
        } else {
          reminderId = '${instance.reference.id}_${reminder.id}';
        }

        if (!shouldSchedule) continue;

        // Calculate due datetime for display
        final dueDateTime = _buildReminderBaseTime(
          instance: instance,
          fixedTimeMinutes: null, // Use due time, not fixed time
        );

        // Build notification actions
        final actions = _buildNotificationActions(instance, reminderId);

        if (reminder.type == 'alarm') {
          // Schedule as system alarm
          if (AlarmService.isSupported()) {
            final alarmScheduled = await AlarmService.scheduleAlarm(
              id: reminderId.hashCode,
              scheduledTime: reminderTime,
              title: instance.templateName,
              body: _getReminderBody(
                dueDateTime: dueDateTime,
                reminderTime: reminderTime,
                offsetMinutes: reminder.offsetMinutes,
              ),
              payload: instance.reference.id,
              reminderId: reminderId,
            );
            if (!alarmScheduled) {
              await NotificationService.scheduleReminder(
                id: reminderId,
                title: instance.templateName,
                scheduledTime: reminderTime,
                body: _getReminderBody(
                  dueDateTime: dueDateTime,
                  reminderTime: reminderTime,
                  offsetMinutes: reminder.offsetMinutes,
                ),
                payload: instance.templateId,
                matchDateTimeComponents: recurrence,
                actions: actions,
              );
            }
          } else {
            // Fallback to notification if alarms not supported
            await NotificationService.scheduleReminder(
              id: reminderId,
              title: instance.templateName,
              scheduledTime: reminderTime,
              body: _getReminderBody(
                dueDateTime: dueDateTime,
                reminderTime: reminderTime,
                offsetMinutes: reminder.offsetMinutes,
              ),
              payload: instance.templateId,
              matchDateTimeComponents: recurrence,
              actions: actions,
            );
          }
        } else {
          // Schedule as notification
          await NotificationService.scheduleReminder(
            id: reminderId,
            title: instance.templateName,
            scheduledTime: reminderTime,
            body: _getReminderBody(
              dueDateTime: dueDateTime,
              reminderTime: reminderTime,
              offsetMinutes: reminder.offsetMinutes,
            ),
            payload: instance.templateId,
            matchDateTimeComponents: recurrence,
            actions: actions,
          );
        }
      }
    } catch (e) {
      // Error scheduling reminders
    }
  }

  /// Calculate reminder time based on offset from due time
  static DateTime? _calculateReminderTimeFromOffset({
    required ActivityInstanceRecord instance,
    required int offsetMinutes,
    int? fixedTimeMinutes,
  }) {
    try {
      final baseTime = _buildReminderBaseTime(
        instance: instance,
        fixedTimeMinutes: fixedTimeMinutes,
      );
      if (baseTime == null) return null;

      return baseTime.add(Duration(minutes: offsetMinutes));
    } catch (e) {
      return null;
    }
  }

  /// Build the base reminder DateTime from the instance due date/time
  static DateTime? _buildReminderBaseTime({
    required ActivityInstanceRecord instance,
    int? fixedTimeMinutes,
  }) {
    final rawDueDate = instance.dueDate;
    if (rawDueDate == null) return null;
    // Keep the user's selected calendar date in local time. Using IST
    // normalization here can shift the reminder to the wrong day/time.
    final localDueDate = rawDueDate.toLocal();
    final dueDate =
        DateTime(localDueDate.year, localDueDate.month, localDueDate.day);

    int hour;
    int minute;

    if (fixedTimeMinutes != null) {
      hour = fixedTimeMinutes ~/ 60;
      minute = fixedTimeMinutes % 60;
    } else {
      final timeOfDay = TimeUtils.stringToTimeOfDay(instance.dueTime);
      if (timeOfDay == null) {
        return null;
      }
      hour = timeOfDay.hour;
      minute = timeOfDay.minute;
    }

    return dueDate.add(Duration(hours: hour, minutes: minute));
  }

  /// Get reminder body text based on due datetime and reminder time
  static String _getReminderBody({
    required DateTime? dueDateTime,
    required DateTime reminderTime,
    int? offsetMinutes,
  }) {
    if (dueDateTime == null) {
      // Fallback to offset-based message if no due datetime
      if (offsetMinutes == null || offsetMinutes == 0) {
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

    final dueDate = DateService.normalizeToStartOfDay(dueDateTime);
    final today = DateService.todayStart;
    final tomorrow = DateService.tomorrowStart;

    // Format time string (e.g., "9:45pm")
    final hour = dueDateTime.hour;
    final minute = dueDateTime.minute;
    int displayHour = hour;
    String period = 'am';
    if (hour == 0) {
      displayHour = 12;
    } else if (hour == 12) {
      period = 'pm';
    } else if (hour > 12) {
      displayHour = hour - 12;
      period = 'pm';
    }
    final timeStr = minute == 0
        ? '$displayHour$period'
        : '$displayHour:${minute.toString().padLeft(2, '0')}$period';

    // Check if due time has passed
    final isPast = dueDateTime.isBefore(reminderTime);

    if (isPast) {
      // Due time was before reminder time
      if (dueDate.isAtSameMomentAs(today)) {
        return 'Was due at $timeStr';
      } else if (dueDate.isAtSameMomentAs(tomorrow)) {
        return 'Was due tomorrow at $timeStr';
      } else {
        // Format date (e.g., "15th Dec")
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec'
        ];
        final day = dueDateTime.day;
        final month = months[dueDateTime.month - 1];
        final daySuffix = _getDaySuffix(day);
        return 'Was due on $day$daySuffix $month at $timeStr';
      }
    } else {
      // Due time is in the future
      if (dueDate.isAtSameMomentAs(today)) {
        return 'Due at $timeStr';
      } else if (dueDate.isAtSameMomentAs(tomorrow)) {
        return 'Due tomorrow at $timeStr';
      } else {
        // Format date (e.g., "15th Dec")
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec'
        ];
        final day = dueDateTime.day;
        final month = months[dueDateTime.month - 1];
        final daySuffix = _getDaySuffix(day);
        return 'Due on $day$daySuffix $month at $timeStr';
      }
    }
  }

  /// Get day suffix (st, nd, rd, th)
  static String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) {
      return 'th';
    }
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  /// Cancel all reminders for a specific instance
  static Future<void> cancelReminderForInstance(
    String instanceId, {
    ActivityInstanceRecord? instanceOverride,
  }) async {
    try {
      // Cancel default notification
      await NotificationService.cancelNotification(instanceId);

      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        return;
      }

      // Resolve the instance record if not provided
      ActivityInstanceRecord? instance = instanceOverride;
      if (instance == null) {
        try {
          final instanceDoc =
              await ActivityInstanceRecord.collectionForUser(userId)
                  .doc(instanceId)
                  .get();
          if (!instanceDoc.exists) {
            return;
          }
          instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
        } catch (e) {
          return;
        }
      }

      // Load the template for reminder configuration lookups
      ActivityRecord? template;
      try {
        final templateDoc = await ActivityRecord.collectionForUser(userId)
            .doc(instance.templateId)
            .get();
        if (templateDoc.exists) {
          template = ActivityRecord.fromSnapshot(templateDoc);
        } else {
          return;
        }
      } catch (e) {
        return;
      }

      final reminderConfigs = template.hasReminders()
          ? ReminderConfigList.fromMapList(template.reminders)
          : <ReminderConfig>[];

      if (reminderConfigs.isEmpty) {
        // Cancel IDs used by the default reminder scheduler for recurring items
        final defaultIds = _buildDefaultReminderIds(template, instance).toSet();
        for (final reminderId in defaultIds) {
          await NotificationService.cancelNotification(reminderId);
        }
        return;
      }

      for (final reminder in reminderConfigs) {
        final reminderIds =
            _buildReminderIdsForConfig(template, instance, reminder).toSet();
        for (final reminderId in reminderIds) {
          await NotificationService.cancelNotification(reminderId);
          if (reminder.type == 'alarm' && AlarmService.isSupported()) {
            await AlarmService.cancelAlarm(reminderId.hashCode);
          }
        }
      }
    } catch (e) {
      // Error canceling reminders
    }
  }

  /// Reschedule reminder for a specific instance
  static Future<void> rescheduleReminderForInstance(
      ActivityInstanceRecord instance) async {
    // First cancel existing reminder
    await cancelReminderForInstance(
      instance.reference.id,
      instanceOverride: instance,
    );
    // Then schedule new one if conditions are met
    await scheduleReminderForInstance(instance);
  }

  /// Schedule reminders for all pending instances
  static Future<void> scheduleAllPendingReminders() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        return;
      }
      final instances = await _queryPendingReminderCandidates(userId: userId);
      if (instances.isEmpty) {
        return;
      }

      final templatesById = await _fetchTemplatesByIds(
        userId: userId,
        templateIds: instances.map((instance) => instance.templateId).toSet(),
      );

      for (final instance in instances) {
        if (_shouldScheduleReminder(instance)) {
          await scheduleReminderForInstance(
            instance,
            templateOverride: templatesById[instance.templateId],
          );
        }
      }
    } catch (e) {
      // Log error but don't fail - reminder scheduling is non-critical
      print('Error scheduling pending reminders: $e');
    }
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
        DateService.currentDate.isBefore(instance.snoozedUntil!)) {
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
      return _calculateReminderTimeFromOffset(
        instance: instance,
        offsetMinutes: -10,
      );
    } catch (e) {
      return null;
    }
  }

  /// Check for expired snoozes and reschedule reminders
  static Future<void> checkExpiredSnoozes() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      final now = DateService.currentDate;
      final instances = await _queryExpiredSnoozeCandidates(
        userId: userId,
        now: now,
      );
      if (instances.isEmpty) {
        return;
      }

      final templatesById = await _fetchTemplatesByIds(
        userId: userId,
        templateIds: instances.map((instance) => instance.templateId).toSet(),
      );

      int rescheduledCount = 0;
      for (final instance in instances) {
        // Check if snooze has expired
        if (instance.snoozedUntil != null &&
            now.isAfter(instance.snoozedUntil!) &&
            instance.status == 'pending' &&
            instance.isActive) {
          await scheduleReminderForInstance(
            instance,
            templateOverride: templatesById[instance.templateId],
          );
          rescheduledCount++;
        }
      }
      if (rescheduledCount > 0) {}
    } catch (e) {
      // Log error but don't fail - expired snooze check is non-critical
      print('Error checking expired snoozes: $e');
    }
  }

  /// Snooze a reminder by rescheduling it for a later time
  static Future<void> snoozeReminder({
    required String reminderId,
    required int durationMinutes,
  }) async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      // Parse reminderId to find instance
      // Format could be: instanceId_reminderId or templateId_reminderId_*
      String? instanceId;
      String? templateId;
      String? reminderConfigId;
      final parts = reminderId.split('_');
      if (parts.length >= 2) {
        reminderConfigId = parts[1];
      }

      ActivityInstanceRecord? instance = await _resolveInstanceForReminderId(
          userId: userId, reminderId: reminderId);

      // Fallback to repository candidates for legacy reminder IDs.
      if (instance == null) {
        final fallbackInstances =
            await _loadReminderFallbackCandidatesFromRepo(userId: userId);
        if (fallbackInstances.isEmpty) {
          return;
        }

        for (final candidate in fallbackInstances) {
          if (reminderId.startsWith(candidate.reference.id)) {
            instance = candidate;
            break;
          }
        }

        if (instance == null && parts.isNotEmpty) {
          final fallbackTemplateId = parts[0];
          for (final candidate in fallbackInstances) {
            if (candidate.templateId != fallbackTemplateId) continue;
            if (candidate.status == 'pending' && candidate.isActive) {
              instance = candidate;
              break;
            }
            instance ??= candidate;
          }
        }

        if (instance == null && parts.isNotEmpty) {
          final fallbackTemplateId = parts[0];
          final scopedCandidates = await _queryTemplateCandidates(
            userId: userId,
            templateId: fallbackTemplateId,
            pendingOnly: true,
          );
          instance = _pickBestPendingCandidate(scopedCandidates);
        }
      }

      if (instance == null) {
        // Could not find instance for reminderId
        return;
      }
      instanceId = instance.reference.id;
      templateId = instance.templateId;

      // Get template to find reminder config
      final templateRef =
          ActivityRecord.collectionForUser(userId).doc(templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) {
        // Template not found for reminderId
        return;
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);

      // Find the reminder config
      ReminderConfig? reminderConfig;
      if (template.hasReminders() && reminderConfigId != null) {
        final reminders = ReminderConfigList.fromMapList(template.reminders);
        reminderConfig = reminders.firstWhere(
          (r) => r.id == reminderConfigId,
          orElse: () => reminders.isNotEmpty
              ? reminders.first
              : ReminderConfig(
                  id: 'default',
                  type: 'notification',
                  offsetMinutes: -10,
                ),
        );
      } else {
        // Use default reminder config
        reminderConfig = ReminderConfig(
          id: 'default',
          type: 'notification',
          offsetMinutes: -10,
        );
      }

      // Cancel existing reminder only if it's the one being snoozed
      // However, since we're creating a new one with a unique ID (_snoozed),
      // we can leave the original one alone (it's likely already fired/dismissed).
      // If we call cancelReminderForInstance(instanceId), it cancels ALL reminders for that instance,
      // which we want to avoid.
      // We can specifically cancel the notification that triggered the snooze if needed,
      // but assuming the user tapped an action or opened the app, the notification is already handled.
      await NotificationService.cancelNotification(reminderId);

      // Calculate new reminder time (current time + snooze duration)
      final newReminderTime =
          DateService.currentDate.add(Duration(minutes: durationMinutes));

      // Schedule new reminder with a unique ID to avoid overwriting or conflict
      final newReminderId =
          '${instanceId}_${reminderConfig.id}_snoozed_${DateService.currentDate.millisecondsSinceEpoch}';

      if (reminderConfig.type == 'alarm' && AlarmService.isSupported()) {
        await AlarmService.scheduleAlarm(
          id: newReminderId.hashCode,
          scheduledTime: newReminderTime,
          title: instance.templateName,
          body: _getReminderBody(
            dueDateTime: _buildReminderBaseTime(
                instance: instance, fixedTimeMinutes: null),
            reminderTime: newReminderTime,
            offsetMinutes: reminderConfig.offsetMinutes,
          ),
          payload: instance.reference.id,
          reminderId: newReminderId,
        );
      } else {
        await NotificationService.scheduleReminder(
          id: newReminderId,
          title: instance.templateName,
          scheduledTime: newReminderTime,
          body: _getReminderBody(
            dueDateTime: _buildReminderBaseTime(
                instance: instance, fixedTimeMinutes: null),
            reminderTime: newReminderTime,
            offsetMinutes: reminderConfig.offsetMinutes,
          ),
          payload: instance.templateId,
          actions: _buildNotificationActions(instance, newReminderId),
        );
      }
    } catch (e) {
      // Error snoozing reminder
    }
  }

  static Future<List<ActivityInstanceRecord>> _queryPendingReminderCandidates({
    required String userId,
  }) async {
    try {
      final repoCandidates =
          await _loadReminderFallbackCandidatesFromRepo(userId: userId);
      return repoCandidates.where(_shouldScheduleReminder).toList();
    } catch (_) {
      try {
        // Scoped Firestore fallback when repository hydration fails.
        final result = await ActivityInstanceRecord.collectionForUser(userId)
            .where('status', isEqualTo: 'pending')
            .where('isActive', isEqualTo: true)
            .limit(500)
            .get();
        return result.docs
            .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
            .where((instance) => instance.dueDate != null)
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  static Future<List<ActivityInstanceRecord>> _queryExpiredSnoozeCandidates({
    required String userId,
    required DateTime now,
  }) async {
    try {
      final instances =
          await _loadReminderFallbackCandidatesFromRepo(userId: userId);
      return instances
          .where((instance) =>
              instance.status == 'pending' &&
              instance.isActive &&
              instance.snoozedUntil != null &&
              now.isAfter(instance.snoozedUntil!))
          .toList();
    } catch (_) {
      try {
        // Scoped Firestore fallback when repository hydration fails.
        final result = await ActivityInstanceRecord.collectionForUser(userId)
            .where('status', isEqualTo: 'pending')
            .where('isActive', isEqualTo: true)
            .where('snoozedUntil', isLessThanOrEqualTo: now)
            .limit(300)
            .get();
        return result.docs
            .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
            .where((instance) => instance.snoozedUntil != null)
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  static Future<List<ActivityInstanceRecord>>
      _loadReminderFallbackCandidatesFromRepo({
    required String userId,
  }) async {
    final repo = TodayInstanceRepository.instance;
    await repo.ensureHydratedForTasks(
      userId: userId,
      includeHabitItems: true,
    );

    final merged = <String, ActivityInstanceRecord>{};
    void merge(List<ActivityInstanceRecord> items) {
      for (final item in items) {
        if (!item.isActive) continue;
        merged[item.reference.id] = item;
      }
    }

    merge(repo.selectTaskItems());
    merge(repo.selectHabitItems());
    merge(
      repo.selectEssentialTodayInstances(
        includePending: true,
        includeLogged: true,
      ),
    );

    return merged.values.toList(growable: false);
  }

  static Future<List<ActivityInstanceRecord>> _queryTemplateCandidates({
    required String userId,
    required String templateId,
    required bool pendingOnly,
  }) async {
    try {
      var query = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateId', isEqualTo: templateId)
          .where('isActive', isEqualTo: true);
      if (pendingOnly) {
        query = query.where('status', isEqualTo: 'pending');
      }

      final result = await query.limit(25).get();
      return result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static ActivityInstanceRecord? _pickBestPendingCandidate(
    List<ActivityInstanceRecord> instances,
  ) {
    if (instances.isEmpty) {
      return null;
    }

    instances.sort((a, b) {
      final aDate = a.dueDate ?? a.belongsToDate ?? DateTime(2100);
      final bDate = b.dueDate ?? b.belongsToDate ?? DateTime(2100);
      return aDate.compareTo(bDate);
    });

    for (final instance in instances) {
      if (instance.status == 'pending' && instance.isActive) {
        return instance;
      }
    }
    return instances.first;
  }

  static Future<Map<String, ActivityRecord>> _fetchTemplatesByIds({
    required String userId,
    required Set<String> templateIds,
  }) async {
    if (templateIds.isEmpty) {
      return {};
    }

    final templatesById = <String, ActivityRecord>{};
    final templateIdList = templateIds.where((id) => id.isNotEmpty).toList();

    for (int i = 0; i < templateIdList.length; i += 10) {
      final batch = templateIdList.skip(i).take(10).toList();
      if (batch.isEmpty) {
        continue;
      }

      try {
        final result = await ActivityRecord.collectionForUser(userId)
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in result.docs) {
          templatesById[doc.id] = ActivityRecord.fromSnapshot(doc);
        }
      } catch (_) {
        // Fallback: fetch per-doc to avoid failing entire scheduling batch.
        for (final templateId in batch) {
          try {
            final templateDoc = await ActivityRecord.collectionForUser(userId)
                .doc(templateId)
                .get();
            if (templateDoc.exists) {
              templatesById[templateId] =
                  ActivityRecord.fromSnapshot(templateDoc);
            }
          } catch (_) {}
        }
      }
    }

    return templatesById;
  }

  static Future<ActivityInstanceRecord?> _resolveInstanceForReminderId({
    required String userId,
    required String reminderId,
  }) async {
    final parts = reminderId.split('_');
    if (parts.isEmpty) {
      return null;
    }

    final firstToken = parts[0];

    // Fast path: reminder ID starts with instance ID.
    try {
      final instanceDoc = await ActivityInstanceRecord.collectionForUser(userId)
          .doc(firstToken)
          .get();
      if (instanceDoc.exists) {
        final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
        if (instance.status == 'pending' && instance.isActive) {
          return instance;
        }
      }
    } catch (_) {}

    // Template-based recurring reminder IDs start with template ID.
    try {
      final pendingCandidates = await _queryTemplateCandidates(
        userId: userId,
        templateId: firstToken,
        pendingOnly: true,
      );
      final pendingMatch = _pickBestPendingCandidate(pendingCandidates);
      if (pendingMatch != null) {
        return pendingMatch;
      }

      final repoCandidates =
          await _loadReminderFallbackCandidatesFromRepo(userId: userId);
      final repoMatch = _pickBestPendingCandidate(
        repoCandidates
            .where((instance) => instance.templateId == firstToken)
            .toList(),
      );
      if (repoMatch != null) {
        return repoMatch;
      }

      final scopedCandidates = await _queryTemplateCandidates(
        userId: userId,
        templateId: firstToken,
        pendingOnly: false,
      );
      return _pickBestPendingCandidate(scopedCandidates);
    } catch (_) {
      return null;
    }
  }

  /// Build notification actions based on instance tracking type
  static List<AndroidNotificationAction> _buildNotificationActions(
    ActivityInstanceRecord instance,
    String reminderId,
  ) {
    final actions = <AndroidNotificationAction>[];
    final instanceId = instance.reference.id;

    // Add action based on tracking type
    switch (instance.templateTrackingType) {
      case 'binary':
        actions.add(
          AndroidNotificationAction(
            'COMPLETE:$instanceId',
            'Mark as complete',
            icon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            showsUserInterface: true,
          ),
        );
        break;
      case 'quantitative':
        actions.add(
          AndroidNotificationAction(
            'ADD:$instanceId',
            'Add 1',
            icon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            showsUserInterface: true,
          ),
        );
        break;
      case 'time':
        actions.add(
          AndroidNotificationAction(
            'TIMER:$instanceId',
            'Start timer',
            icon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            showsUserInterface: true,
          ),
        );
        break;
    }

    // Always add snooze action
    actions.add(
      AndroidNotificationAction(
        'SNOOZE:$reminderId',
        'Snooze',
        icon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      ),
    );

    return actions;
  }

  static Iterable<String> _buildReminderIdsForConfig(
    ActivityRecord template,
    ActivityInstanceRecord instance,
    ReminderConfig reminder,
  ) {
    final ids = <String>{};
    final templateId = template.reference.id;
    final instanceId = instance.reference.id;

    if (template.isRecurring) {
      if (_isSpecificDayRecurring(template)) {
        final weekday = _getInstanceWeekday(instance);
        if (weekday != null) {
          ids.add('${templateId}_${reminder.id}_$weekday');
        } else {
          for (var day = 1; day <= 7; day++) {
            ids.add('${templateId}_${reminder.id}_$day');
          }
        }
      } else if (_isDailyRecurring(template)) {
        ids.add('${templateId}_${reminder.id}_daily');
      } else {
        ids.add('${instanceId}_${reminder.id}');
      }
    } else {
      ids.add('${instanceId}_${reminder.id}');
    }

    return ids;
  }

  static Iterable<String> _buildDefaultReminderIds(
    ActivityRecord template,
    ActivityInstanceRecord instance,
  ) {
    final ids = <String>{};
    final templateId = template.reference.id;

    if (!template.isRecurring) {
      return ids;
    }

    if (_isSpecificDayRecurring(template)) {
      final weekday = _getInstanceWeekday(instance);
      if (weekday != null) {
        ids.add('${templateId}_default_$weekday');
      } else {
        for (var day = 1; day <= 7; day++) {
          ids.add('${templateId}_default_$day');
        }
      }
    } else if (_isDailyRecurring(template)) {
      ids.add('${templateId}_default_daily');
    }

    return ids;
  }

  static bool _isSpecificDayRecurring(ActivityRecord template) {
    return template.frequencyType == 'specific_days' ||
        (template.everyXPeriodType == 'week' && template.everyXValue == 1);
  }

  static bool _isDailyRecurring(ActivityRecord template) {
    return template.everyXPeriodType == 'day' && template.everyXValue == 1;
  }

  static int? _getInstanceWeekday(ActivityInstanceRecord instance) {
    if (instance.dueDate != null) {
      return instance.dueDate!.weekday;
    }
    if (instance.belongsToDate != null) {
      return instance.belongsToDate!.weekday;
    }
    return null;
  }
}
