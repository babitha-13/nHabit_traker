import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_instance_record.dart'
    as habit_schema;
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/timer_task_template_service.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/utils/time_validation_helper.dart';

/// Service to manage task and habit instances
/// Handles the creation, completion, and scheduling of recurring tasks/habits
/// Following Microsoft To-Do pattern: only show current instances, generate next on completion
class TaskInstanceService {
  /// Get current user ID
  static String get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return user.uid;
  }

  /// Get today's date at midnight (start of day)
  static DateTime get _todayStart {
    return DateService.todayStart;
  }

  // ==================== TASK INSTANCES ====================

  /// Get all active activity instances for today and overdue
  static Future<List<ActivityInstanceRecord>> getTodaysTaskInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('status', isEqualTo: 'pending');

      final result = await query.get();

      final instances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((instance) => instance.isActive) // Filter isActive in Dart
          .toList();

      // Sort by priority (high to low) then by due date (oldest first, nulls last)
      instances.sort((a, b) {
        final priorityCompare =
            b.templatePriority.compareTo(a.templatePriority);
        if (priorityCompare != 0) return priorityCompare;

        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });

      return instances;
    } catch (e) {
      print('Error getting today\'s task instances: $e');
      return [];
    }
  }

  /// Create a new task instance from a template
  static Future<DocumentReference> createTaskInstance({
    required String templateId,
    DateTime? dueDate,
    required ActivityRecord template,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    final instanceData = createActivityInstanceRecordData(
      templateId: templateId,
      dueDate: dueDate,
      status: 'pending',
      createdTime: DateTime.now(),
      lastUpdated: DateTime.now(),
      isActive: true,
      // Cache template data for quick access
      templateName: template.name,
      templateCategoryId: template.categoryId,
      templateCategoryName: template.categoryName,
      templatePriority: template.priority,
      templateTrackingType: template.trackingType,
      templateTarget: template.target,
      templateUnit: template.unit,
      templateDescription: template.description,
      templateShowInFloatingTimer: template.showInFloatingTimer,
    );

    return await ActivityInstanceRecord.collectionForUser(uid)
        .add(instanceData);
  }

  /// Complete a task instance and generate next occurrence if recurring
  static Future<void> completeTaskInstance({
    required String instanceId,
    dynamic finalValue,
    int? finalAccumulatedTime,
    String? notes,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Task instance not found');
      }

      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateTime.now();

      // Update current instance as completed
      await instanceRef.update({
        'status': 'completed',
        'completedAt': now,
        'currentValue': finalValue,
        'accumulatedTime': finalAccumulatedTime ?? instance.accumulatedTime,
        'notes': notes ?? instance.notes,
        'lastUpdated': now,
      });

      // Get the template to check if it's recurring
      final templateRef =
          ActivityRecord.collectionForUser(uid).doc(instance.templateId);
      final templateDoc = await templateRef.get();

      if (templateDoc.exists) {
        final template = ActivityRecord.fromSnapshot(templateDoc);

        // Generate next instance if task is recurring and still active
        if (template.isRecurring &&
            template.isActive &&
            template.frequencyType.isNotEmpty &&
            instance.dueDate != null) {
          final nextDueDate = _calculateNextDueDate(
            currentDueDate: instance.dueDate!,
            frequencyType: template.frequencyType,
            everyXValue: template.everyXValue,
            everyXPeriodType: template.everyXPeriodType,
            timesPerPeriod: template.timesPerPeriod,
            periodType: template.periodType,
            specificDays: template.specificDays,
          );

          if (nextDueDate != null) {
            await createTaskInstance(
              templateId: instance.templateId,
              dueDate: nextDueDate,
              template: template,
              userId: uid,
            );
            // Also update the template with the next due date
            await _updateTemplateDueDate(
              templateRef: templateRef,
              dueDate: nextDueDate,
            );
          } else {
            // No more occurrences, clear dueDate on template
            await _updateTemplateDueDate(
              templateRef: templateRef,
              dueDate: null,
            );
          }
        }
      }
    } catch (e) {
      print('Error completing task instance: $e');
      rethrow;
    }
  }

  /// Skip a task instance and generate next occurrence if recurring
  static Future<void> skipTaskInstance({
    required String instanceId,
    String? notes,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Task instance not found');
      }

      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateTime.now();

      // Update current instance as skipped
      await instanceRef.update({
        'status': 'skipped',
        'skippedAt': now,
        'notes': notes ?? instance.notes,
        'lastUpdated': now,
      });

      // Get the template to check if it's recurring
      final templateRef =
          ActivityRecord.collectionForUser(uid).doc(instance.templateId);
      final templateDoc = await templateRef.get();

      if (templateDoc.exists) {
        final template = ActivityRecord.fromSnapshot(templateDoc);

        // Generate next instance if task is recurring
        if (template.isRecurring &&
            template.frequencyType.isNotEmpty &&
            instance.dueDate != null) {
          final nextDueDate = _calculateNextDueDate(
            currentDueDate: instance.dueDate!,
            frequencyType: template.frequencyType,
            everyXValue: template.everyXValue,
            everyXPeriodType: template.everyXPeriodType,
            timesPerPeriod: template.timesPerPeriod,
            periodType: template.periodType,
            specificDays: template.specificDays,
          );

          if (nextDueDate != null) {
            await createTaskInstance(
              templateId: instance.templateId,
              dueDate: nextDueDate,
              template: template,
              userId: uid,
            );
            // Also update the template with the next due date
            await _updateTemplateDueDate(
              templateRef: templateRef,
              dueDate: nextDueDate,
            );
          } else {
            // No more occurrences, clear dueDate on template
            await _updateTemplateDueDate(
              templateRef: templateRef,
              dueDate: null,
            );
          }
        }
      }
    } catch (e) {
      print('Error skipping task instance: $e');
      rethrow;
    }
  }

  // ==================== HABIT INSTANCES ====================

  /// Get all active habit instances for today and overdue
  static Future<List<habit_schema.HabitInstanceRecord>>
      getTodaysHabitInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    final today = _todayStart;

    try {
      // Remove server-side date filter to allow client-side date filtering with test dates
      final query = habit_schema.HabitInstanceRecord.collectionForUser(uid)
          .where('isActive', isEqualTo: true)
          .where('status', isEqualTo: 'pending');

      final result = await query.get();
      final allInstances = result.docs
          .map((doc) => habit_schema.HabitInstanceRecord.fromSnapshot(doc))
          .toList();

      // Filter by date on client side using DateService
      // For habits, use window logic; for tasks, use due date logic
      final instances = allInstances.where((instance) {
        if (instance.dueDate == null)
          return true; // Include instances without due dates

        // For tasks, use simple due date logic
        return instance.dueDate!.isBefore(today) ||
            instance.dueDate!.isAtSameMomentAs(today);
      }).toList();

      // Filter instances based on template date boundaries
      final activeInstances = <habit_schema.HabitInstanceRecord>[];

      for (final instance in instances) {
        try {
          // Get the template to check date boundaries
          final templateRef =
              ActivityRecord.collectionForUser(uid).doc(instance.templateId);
          final templateDoc = await templateRef.get();

          if (!templateDoc.exists) {
            continue; // Skip if template doesn't exist
          }

          final template = ActivityRecord.fromSnapshot(templateDoc);

          // Check if habit is active based on date boundaries
          if (isHabitActiveByDate(template, today)) {
            activeInstances.add(instance);
          }
        } catch (e) {
          print(
              'Error checking template date boundaries for instance ${instance.reference.id}: $e');
          // Continue with other instances even if one fails
        }
      }

      // Sort by priority (high to low) then by due date (oldest first)
      activeInstances.sort((a, b) {
        final priorityCompare =
            b.templatePriority.compareTo(a.templatePriority);
        if (priorityCompare != 0) return priorityCompare;
        return a.dueDate!.compareTo(b.dueDate!);
      });

      return activeInstances;
    } catch (e) {
      print('Error getting today\'s habit instances: $e');
      return [];
    }
  }

  /// Create a new habit instance from a template
  static Future<DocumentReference> createActivityInstance({
    required String templateId,
    required DateTime dueDate,
    required ActivityRecord template,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    final instanceData = habit_schema.createActivityInstanceRecordData(
      templateId: templateId,
      dueDate: dueDate,
      status: 'pending',
      createdTime: DateTime.now(),
      lastUpdated: DateTime.now(),
      isActive: true,
      // Cache template data for quick access
      templateName: template.name,
      templateCategoryId: template.categoryId,
      templateCategoryName: template.categoryName,
      templatePriority: template.priority,
      templateTrackingType: template.trackingType,
      templateTarget: template.target,
      templateUnit: template.unit,
      templateDescription: template.description,
      templateShowInFloatingTimer: template.showInFloatingTimer,
      templateIsRecurring: template.isRecurring,
      templateEveryXValue: template.everyXValue,
      templateEveryXPeriodType: template.everyXPeriodType,
      templateTimesPerPeriod: template.timesPerPeriod,
      templatePeriodType: template.periodType,
    );

    return await habit_schema.HabitInstanceRecord.collectionForUser(uid)
        .add(instanceData);
  }

  /// Complete a habit instance and generate next occurrence
  static Future<void> completeHabitInstance({
    required String instanceId,
    dynamic finalValue,
    int? finalAccumulatedTime,
    String? notes,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          habit_schema.HabitInstanceRecord.collectionForUser(uid)
              .doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Habit instance not found');
      }

      final instance =
          habit_schema.HabitInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateTime.now();

      // Update current instance as completed
      await instanceRef.update({
        'status': 'completed',
        'completedAt': now,
        'currentValue': finalValue,
        'accumulatedTime': finalAccumulatedTime ?? instance.accumulatedTime,
        'notes': notes ?? instance.notes,
        'lastUpdated': now,
      });

      // Get the template to generate next instance (habits are always recurring)
      final templateRef =
          ActivityRecord.collectionForUser(uid).doc(instance.templateId);
      final templateDoc = await templateRef.get();

      if (templateDoc.exists) {
        final template = ActivityRecord.fromSnapshot(templateDoc);

        if (template.frequencyType.isNotEmpty && instance.dueDate != null) {
          final nextDueDate = _calculateNextDueDate(
            currentDueDate: instance.dueDate!,
            frequencyType: template.frequencyType,
            everyXValue: template.everyXValue,
            everyXPeriodType: template.everyXPeriodType,
            timesPerPeriod: template.timesPerPeriod,
            periodType: template.periodType,
            specificDays: template.specificDays,
          );

          if (nextDueDate != null) {
            await createActivityInstance(
              templateId: instance.templateId,
              dueDate: nextDueDate,
              template: template,
              userId: uid,
            );
          }
        }
      }
    } catch (e) {
      print('Error completing habit instance: $e');
      rethrow;
    }
  }

  /// Skip a habit instance and generate next occurrence
  static Future<void> skipHabitInstance({
    required String instanceId,
    String? notes,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          habit_schema.HabitInstanceRecord.collectionForUser(uid)
              .doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Habit instance not found');
      }

      final instance =
          habit_schema.HabitInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateTime.now();

      // Update current instance as skipped
      await instanceRef.update({
        'status': 'skipped',
        'skippedAt': now,
        'notes': notes ?? instance.notes,
        'lastUpdated': now,
      });

      // Get the template to generate next instance (habits are always recurring)
      final templateRef =
          ActivityRecord.collectionForUser(uid).doc(instance.templateId);
      final templateDoc = await templateRef.get();

      if (templateDoc.exists) {
        final template = ActivityRecord.fromSnapshot(templateDoc);

        if (template.frequencyType.isNotEmpty && instance.dueDate != null) {
          final nextDueDate = _calculateNextDueDate(
            currentDueDate: instance.dueDate!,
            frequencyType: template.frequencyType,
            everyXValue: template.everyXValue,
            everyXPeriodType: template.everyXPeriodType,
            timesPerPeriod: template.timesPerPeriod,
            periodType: template.periodType,
            specificDays: template.specificDays,
          );

          if (nextDueDate != null) {
            await createActivityInstance(
              templateId: instance.templateId,
              dueDate: nextDueDate,
              template: template,
              userId: uid,
            );
          }
        }
      }
    } catch (e) {
      print('Error skipping habit instance: $e');
      rethrow;
    }
  }

  // ==================== RECURRENCE LOGIC ====================

  /// Calculate the next due date based on schedule and frequency
  /// This is the core logic that handles Microsoft To-Do style recurrence
  static DateTime? _calculateNextDueDate({
    required DateTime currentDueDate,
    String? frequencyType,
    int? everyXValue,
    String? everyXPeriodType,
    int? timesPerPeriod,
    String? periodType,
    List<int>? specificDays,
  }) {
    // Handle different frequency types
    switch (frequencyType) {
      case 'everyXPeriod':
        final value = everyXValue ?? 1;
        switch (everyXPeriodType) {
          case 'days':
            return currentDueDate.add(Duration(days: value));
          case 'weeks':
            return currentDueDate.add(Duration(days: 7 * value));
          case 'months':
            return _addMonths(currentDueDate, value);
          default:
            return currentDueDate.add(Duration(days: value));
        }

      case 'timesPerPeriod':
        switch (periodType) {
          case 'weeks':
            // For times per week, calculate next occurrence
            return _getNextWeeklyOccurrence(currentDueDate, specificDays ?? []);
          case 'months':
            // For times per month, add 1 month and divide by times
            return _addMonths(currentDueDate, 1);
          case 'year':
            // For times per year, add 1 year and divide by times
            return DateTime(currentDueDate.year + 1, currentDueDate.month,
                currentDueDate.day);
          default:
            return currentDueDate.add(Duration(days: 7));
        }

      case 'specificDays':
        if (specificDays != null && specificDays.isNotEmpty) {
          return _getNextWeeklyOccurrence(currentDueDate, specificDays);
        }
        return currentDueDate.add(Duration(days: 1));

      default:
        // Default to daily
        return currentDueDate.add(Duration(days: 1));
    }
  }

  /// Add months to a date, handling edge cases
  static DateTime _addMonths(DateTime date, int months) {
    final nextMonth = DateTime(
      date.year,
      date.month + months,
      date.day,
    );

    // Handle cases where the day doesn't exist in the target month
    if (nextMonth.month != (date.month + months) % 12) {
      // Day doesn't exist in target month, use last day of month
      return DateTime(nextMonth.year, nextMonth.month, 0);
    }

    return nextMonth;
  }

  /// Get next weekly occurrence based on specific days
  static DateTime _getNextWeeklyOccurrence(
      DateTime currentDate, List<int> specificDays) {
    final currentWeekday = currentDate.weekday; // Monday = 1, Sunday = 7
    final sortedDays = List<int>.from(specificDays)..sort();

    // Find next day in the same week
    for (final day in sortedDays) {
      if (day > currentWeekday) {
        final daysToAdd = day - currentWeekday;
        return currentDate.add(Duration(days: daysToAdd));
      }
    }

    // No more days this week, go to first day of next week
    final firstDayNextWeek = sortedDays.first;
    final daysToAdd = 7 - currentWeekday + firstDayNextWeek;
    return currentDate.add(Duration(days: daysToAdd));
  }

  // ==================== INITIALIZATION ====================

  /// Generate initial instances for a new recurring task
  static Future<void> initializeTaskInstances({
    required String templateId,
    required ActivityRecord template,
    DateTime? startDate,
    String? userId,
  }) async {
    if (!template.isRecurring) {
      // For one-time tasks, create a single instance, preserving the null due date if not set.
      await createTaskInstance(
        templateId: templateId,
        dueDate: template.dueDate,
        template: template,
        userId: userId,
      );
      return;
    }

    final firstDueDate = template.dueDate ?? startDate ?? _todayStart;
    await createTaskInstance(
      templateId: templateId,
      dueDate: firstDueDate,
      template: template,
      userId: userId,
    );

    await _updateTemplateDueDate(
      templateRef: template.reference,
      dueDate: firstDueDate,
    );
  }

  /// Generate initial instances for a new habit
  static Future<void> initializeHabitInstances({
    required String templateId,
    required ActivityRecord template,
    DateTime? startDate,
    String? userId,
  }) async {
    // Habits are always recurring, create the first instance
    final firstDueDate = startDate ?? _todayStart;
    await createActivityInstance(
      templateId: templateId,
      dueDate: firstDueDate,
      template: template,
      userId: userId,
    );
  }

  // ==================== TEMPLATE SYNC METHODS ====================

  /// Update template's dueDate to keep it in sync with instances
  static Future<void> _updateTemplateDueDate({
    required DocumentReference templateRef,
    required DateTime? dueDate,
  }) async {
    try {
      await templateRef.update({'dueDate': dueDate});
    } catch (e) {
      print('Error updating template dueDate: $e');
      // Decide if we should re-throw or handle silently
    }
  }

  /// When a template is updated (e.g., schedule change), regenerate instances
  static Future<void> syncInstancesOnTemplateUpdate({
    required String templateId,
    required String templateType, // 'task' or 'habit'
    required DateTime? nextDueDate,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      if (templateType == 'task') {
        await ActivityRecord.collectionForUser(uid).doc(templateId).update({
          'nextDueDate': nextDueDate,
          'lastUpdated': DateTime.now(),
        });
      } else {
        await ActivityRecord.collectionForUser(uid).doc(templateId).update({
          'nextDueDate': nextDueDate,
          'lastUpdated': DateTime.now(),
        });
      }
    } catch (e) {
      print('Error syncing template next due date: $e');
      // Don't rethrow - this is a sync operation, shouldn't fail the main operation
    }
  }

  // ==================== UTILITY METHODS ====================

  /// Update instance progress (for quantity/duration tracking)
  static Future<void> updateInstanceProgress({
    required String instanceId,
    required String instanceType, // 'task' or 'habit'
    dynamic currentValue,
    int? accumulatedTime,
    bool? isTimerActive,
    DateTime? timerStartTime,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    final updateData = <String, dynamic>{
      'lastUpdated': DateTime.now(),
    };

    if (currentValue != null) updateData['currentValue'] = currentValue;
    if (accumulatedTime != null)
      updateData['accumulatedTime'] = accumulatedTime;
    if (isTimerActive != null) updateData['isTimerActive'] = isTimerActive;
    if (timerStartTime != null) updateData['timerStartTime'] = timerStartTime;

    if (instanceType == 'task') {
      await ActivityInstanceRecord.collectionForUser(uid)
          .doc(instanceId)
          .update(updateData);
    } else {
      await habit_schema.HabitInstanceRecord.collectionForUser(uid)
          .doc(instanceId)
          .update(updateData);
    }
  }

  /// Delete all instances for a template (when template is deleted)
  static Future<void> deleteInstancesForTemplate({
    required String templateId,
    required String templateType, // 'task' or 'habit'
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      if (templateType == 'task') {
        final query = ActivityInstanceRecord.collectionForUser(uid)
            .where('templateId', isEqualTo: templateId);
        final instances = await query.get();

        for (final doc in instances.docs) {
          await doc.reference.update({
            'isActive': false,
            'lastUpdated': DateTime.now(),
          });
        }
      } else {
        final query = habit_schema.HabitInstanceRecord.collectionForUser(uid)
            .where('templateId', isEqualTo: templateId);
        final instances = await query.get();

        for (final doc in instances.docs) {
          await doc.reference.update({
            'isActive': false,
            'lastUpdated': DateTime.now(),
          });
        }
      }
    } catch (e) {
      print('Error deleting instances for template $templateId: $e');
      rethrow;
    }
  }

  // ==================== TIMER TASK METHODS ====================

  /// Create a new timer task instance when timer starts
  static Future<DocumentReference> createTimerTaskInstance({
    String? categoryId,
    String? categoryName,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      // Get or create the Timer Task template
      final templateData =
          await TimerTaskTemplateService.getOrCreateTimerTaskTemplate();
      final template = templateData['template'] as ActivityRecord;
      final templateRef = templateData['templateRef'] as DocumentReference;

      // Use provided category or default to Inbox
      String finalCategoryId = categoryId ?? template.categoryId;
      String finalCategoryName = categoryName ?? template.categoryName;

      final instanceData = createActivityInstanceRecordData(
        templateId: templateRef.id,
        status: 'pending',
        isTimerActive: true,
        timerStartTime: DateTime.now(),
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        isActive: true,
        // Cache template data for quick access
        templateName: template.name,
        templateCategoryId: finalCategoryId,
        templateCategoryName: finalCategoryName,
        templatePriority: template.priority,
        templateTrackingType: template.trackingType,
        templateTarget: template.target,
        templateUnit: template.unit,
        templateDescription: template.description,
        templateShowInFloatingTimer: template.showInFloatingTimer,
      );

      return await ActivityInstanceRecord.collectionForUser(uid)
          .add(instanceData);
    } catch (e) {
      print('Error creating timer task instance: $e');
      rethrow;
    }
  }

  /// Update timer task instance when timer is stopped (completed)
  static Future<void> updateTimerTaskOnStop({
    required DocumentReference taskInstanceRef,
    required Duration duration,
    required String taskName,
    String? categoryId,
    String? categoryName,
    String? userId,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'status': 'completed',
        'completedAt': DateTime.now(),
        'isTimerActive': false,
        'accumulatedTime': duration.inMilliseconds,
        'currentValue': duration.inMilliseconds,
        'templateName': taskName,
        'lastUpdated': DateTime.now(),
      };

      // Update category if provided
      if (categoryId != null) {
        updateData['templateCategoryId'] = categoryId;
      }
      if (categoryName != null) {
        updateData['templateCategoryName'] = categoryName;
      }

      await taskInstanceRef.update(updateData);
    } catch (e) {
      print('Error updating timer task on stop: $e');
      rethrow;
    }
  }

  /// Update timer task instance when timer is paused (remains pending)
  static Future<void> updateTimerTaskOnPause({
    required DocumentReference taskInstanceRef,
    required Duration duration,
    required String taskName,
    String? categoryId,
    String? categoryName,
    String? userId,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'status': 'pending',
        'isTimerActive': false,
        'accumulatedTime': duration.inMilliseconds,
        'currentValue': duration.inMilliseconds,
        'templateName': taskName,
        'lastUpdated': DateTime.now(),
      };

      // Update category if provided
      if (categoryId != null) {
        updateData['templateCategoryId'] = categoryId;
      }
      if (categoryName != null) {
        updateData['templateCategoryName'] = categoryName;
      }

      await taskInstanceRef.update(updateData);
    } catch (e) {
      print('Error updating timer task on pause: $e');
      rethrow;
    }
  }

  /// Get timer task instances for calendar display
  static Future<List<ActivityInstanceRecord>> getTimerTaskInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('timerStartTime', isNull: false)
          .where('accumulatedTime', isGreaterThan: 0);

      final result = await query.get();
      return result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((instance) => instance.isActive)
          .toList();
    } catch (e) {
      print('Error getting timer task instances: $e');
      return [];
    }
  }

  // ==================== TIME LOGGING METHODS ====================

  /// Start time logging on an existing activity instance
  static Future<void> startTimeLogging({
    required DocumentReference activityInstanceRef,
    String? userId,
  }) async {
    try {
      // Validate: cannot start timer on completed tasks
      final instance =
          await ActivityInstanceRecord.getDocumentOnce(activityInstanceRef);

      final error = TimeValidationHelper.getStartTimerError(instance);
      if (error != null) {
        throw Exception(error);
      }

      await activityInstanceRef.update({
        'isTimeLogging': true,
        'currentSessionStartTime': DateTime.now(),
        'lastUpdated': DateTime.now(),
      });
    } catch (e) {
      print('Error starting time logging: $e');
      rethrow;
    }
  }

  /// Stop time logging and optionally mark task as complete
  static Future<void> stopTimeLogging({
    required DocumentReference activityInstanceRef,
    required bool markComplete,
    String? userId,
  }) async {
    try {
      final instance =
          await ActivityInstanceRecord.getDocumentOnce(activityInstanceRef);

      if (instance.currentSessionStartTime == null) {
        throw Exception('No active session to stop');
      }

      final endTime = DateTime.now();
      final duration = endTime.difference(instance.currentSessionStartTime!);

      // Validate session duration
      final validationError =
          TimeValidationHelper.validateSessionDuration(duration);
      if (validationError != null) {
        throw Exception(validationError);
      }

      // Create new session
      final newSession = {
        'startTime': instance.currentSessionStartTime,
        'endTime': endTime,
        'durationMilliseconds': duration.inMilliseconds,
      };

      // Add to existing sessions
      final sessions = List<Map<String, dynamic>>.from(instance.timeLogSessions)
        ..add(newSession);

      // Calculate total time across all sessions
      final totalTime = sessions.fold<int>(
          0, (sum, session) => sum + (session['durationMilliseconds'] as int));

      final updateData = <String, dynamic>{
        'timeLogSessions': sessions,
        'totalTimeLogged': totalTime,
        'isTimeLogging': false,
        'currentSessionStartTime': null,
        'lastUpdated': DateTime.now(),
      };

      if (markComplete) {
        updateData['status'] = 'completed';
        updateData['completedAt'] = DateTime.now();
      }

      await activityInstanceRef.update(updateData);
    } catch (e) {
      print('Error stopping time logging: $e');
      rethrow;
    }
  }

  /// Pause time logging (keeps task pending)
  static Future<void> pauseTimeLogging({
    required DocumentReference activityInstanceRef,
    String? userId,
  }) async {
    // Same as stopTimeLogging but with markComplete = false
    await stopTimeLogging(
      activityInstanceRef: activityInstanceRef,
      markComplete: false,
      userId: userId,
    );
  }

  /// Get current session duration (for displaying running time)
  static Duration getCurrentSessionDuration(ActivityInstanceRecord instance) {
    if (!instance.isTimeLogging || instance.currentSessionStartTime == null) {
      return Duration.zero;
    }
    return DateTime.now().difference(instance.currentSessionStartTime!);
  }

  /// Get aggregate time including current session
  static Duration getAggregateDuration(ActivityInstanceRecord instance) {
    final totalLogged = Duration(milliseconds: instance.totalTimeLogged);
    final currentSession = getCurrentSessionDuration(instance);
    return totalLogged + currentSession;
  }

  /// Get all activity instances with time logs for calendar display
  static Future<List<ActivityInstanceRecord>> getTimeLoggedTasks({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('totalTimeLogged', isGreaterThan: 0);

      final result = await query.get();
      final tasks = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((task) => task.isActive)
          .toList();

      // Filter by date range if provided
      if (startDate != null || endDate != null) {
        return tasks.where((task) {
          final sessions = task.timeLogSessions;
          return sessions.any((session) {
            final sessionStart = session['startTime'] as DateTime;
            if (startDate != null && sessionStart.isBefore(startDate))
              return false;
            if (endDate != null && sessionStart.isAfter(endDate)) return false;
            return true;
          });
        }).toList();
      }

      return tasks;
    } catch (e) {
      print('Error getting time logged tasks: $e');
      return [];
    }
  }
}
