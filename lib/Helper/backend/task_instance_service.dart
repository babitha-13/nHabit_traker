import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_instance_record.dart'
    as habit_schema;
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/timer_task_template_service.dart';
import 'package:habit_tracker/Helper/backend/non_productive_service.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/utils/time_validation_helper.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';

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
    // Inherit order from previous instance of the same template
    int? queueOrder;
    int? habitsOrder;
    int? tasksOrder;
    try {
      queueOrder = await InstanceOrderService.getOrderFromPreviousInstance(
          templateId, 'queue', uid);
      habitsOrder = await InstanceOrderService.getOrderFromPreviousInstance(
          templateId, 'habits', uid);
      tasksOrder = await InstanceOrderService.getOrderFromPreviousInstance(
          templateId, 'tasks', uid);
    } catch (e) {
      // If order lookup fails, continue with null values (will use default sorting)
    }
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
      // Inherit order from previous instance
      queueOrder: queueOrder,
      habitsOrder: habitsOrder,
      tasksOrder: tasksOrder,
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
      
      // Check if this is a habit - habits should use ActivityInstanceService completion logic
      // which handles next instance generation correctly
      if (instance.templateCategoryType == 'habit') {
        // For habits, use ActivityInstanceService.completeInstance which handles habit logic correctly
        await ActivityInstanceService.completeInstance(
          instanceId: instanceId,
          finalValue: finalValue,
          finalAccumulatedTime: finalAccumulatedTime,
          notes: notes,
          userId: uid,
        );
        return; // Exit early - habit completion handled
      }
      
      // For tasks, proceed with task completion logic
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

      // Broadcast the instance update event for real-time UI updates
      final updatedInstance =
          await ActivityInstanceRecord.getDocumentOnce(instanceRef);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);

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
        } else if (!template.isRecurring) {
          // Mark one-time task template as inactive after completion
          await templateRef.update({
            'isActive': false,
            'status': 'complete',
            'lastUpdated': now,
          });
        }
      }
    } catch (e) {
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
        } else if (!template.isRecurring) {
          // Mark one-time task template as inactive after skipping
          await templateRef.update({
            'isActive': false,
            'status': 'skipped',
            'lastUpdated': now,
          });
        }
      }
    } catch (e) {
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
      // Create a new timer task template for this session
      final templateData =
          await TimerTaskTemplateService.createTimerTaskTemplate();
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
        templateCategoryType:
            'task', // CRITICAL: Required for task page filtering
        templatePriority: template.priority,
        templateTrackingType: 'time', // Force time tracking for timer tasks
        templateTarget: template.target,
        templateUnit: template.unit,
        templateDescription: template.description,
        templateShowInFloatingTimer: template.showInFloatingTimer,
        // Session tracking fields
        currentSessionStartTime: DateTime.now(),
        isTimeLogging: true,
      );
      return await ActivityInstanceRecord.collectionForUser(uid)
          .add(instanceData);
    } catch (e) {
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
    String? activityType, // 'task' or 'non_productive'
    String? userId,
  }) async {
    try {
      final uid = userId ?? _currentUserId;
      final isNonProductive = activityType == 'non_productive';

      // Get current instance to check for existing sessions
      final currentInstance =
          await ActivityInstanceRecord.getDocumentOnce(taskInstanceRef);
      // Create new session
      final newSession = {
        'startTime': currentInstance.currentSessionStartTime ??
            DateTime.now().subtract(duration),
        'endTime': DateTime.now(),
        'durationMilliseconds': duration.inMilliseconds,
      };
      // Get existing sessions and add new one
      final existingSessions =
          List<Map<String, dynamic>>.from(currentInstance.timeLogSessions);
      existingSessions.add(newSession);
      // Calculate total cumulative time
      final totalTime = existingSessions.fold<int>(
          0, (sum, session) => sum + (session['durationMilliseconds'] as int));

      // Handle non-productive vs productive differently
      if (isNonProductive) {
        // For non-productive: find or create template, then update instance
        final templates = await NonProductiveService.getNonProductiveTemplates(
          userId: uid,
        );
        ActivityRecord? matchingTemplate;
        for (final template in templates) {
          if (template.name.toLowerCase() == taskName.toLowerCase()) {
            matchingTemplate = template;
            break;
          }
        }

        // Create template if it doesn't exist
        DocumentReference templateRef;
        if (matchingTemplate == null) {
          templateRef = await NonProductiveService.createNonProductiveTemplate(
            name: taskName,
            trackingType: 'time',
            userId: uid,
          );
        } else {
          templateRef = matchingTemplate.reference;
        }

        // Update instance with non-productive data
        final updateData = <String, dynamic>{
          'status': 'completed',
          'completedAt': DateTime.now(),
          'isTimerActive': false,
          'timeLogSessions': existingSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': totalTime,
          'templateId': templateRef.id,
          'templateName': taskName,
          'templateCategoryType': 'non_productive',
          'templateCategoryName': 'Non-Productive',
          'templateTrackingType': 'time',
          'currentSessionStartTime': null,
          'lastUpdated': DateTime.now(),
        };
        await taskInstanceRef.update(updateData);

        // Delete the old timer task template (cleanup)
        try {
          final oldTemplateRef = ActivityRecord.collectionForUser(uid)
              .doc(currentInstance.templateId);
          await oldTemplateRef.delete();
        } catch (e) {
          // Best effort cleanup, don't fail if it doesn't exist
        }
      } else {
        // For productive tasks: existing logic
        final updateData = <String, dynamic>{
          'status': 'completed',
          'completedAt': DateTime.now(),
          'isTimerActive': false,
          'timeLogSessions': existingSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': totalTime,
          'templateTarget':
              totalTime / 60000.0, // Convert milliseconds to minutes
          'templateName': taskName,
          'templateCategoryType': 'task', // Ensure it's marked as task
          'currentSessionStartTime': null,
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

        // Update the template name as well
        final templateRef = ActivityRecord.collectionForUser(uid)
            .doc(currentInstance.templateId);
        final templateUpdateData = <String, dynamic>{
          'name': taskName,
          'lastUpdated': DateTime.now(),
        };

        // Update template category if provided
        if (categoryId != null) {
          templateUpdateData['categoryId'] = categoryId;
        }
        if (categoryName != null) {
          templateUpdateData['categoryName'] = categoryName;
        }

        await templateRef.update(templateUpdateData);

        // Mark template as inactive - timer tasks are one-time use only
        // Keep template for editing purposes but prevent it from appearing in task lists
        await templateRef.update({'isActive': false});
      }
    } catch (e) {
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
    String? activityType, // 'task' or 'non_productive'
    String? userId,
  }) async {
    try {
      final uid = userId ?? _currentUserId;
      final isNonProductive = activityType == 'non_productive';

      // Get current instance to check for existing sessions
      final currentInstance =
          await ActivityInstanceRecord.getDocumentOnce(taskInstanceRef);
      // Create new session
      final newSession = {
        'startTime': currentInstance.currentSessionStartTime ??
            DateTime.now().subtract(duration),
        'endTime': DateTime.now(),
        'durationMilliseconds': duration.inMilliseconds,
      };
      // Get existing sessions and add new one
      final existingSessions =
          List<Map<String, dynamic>>.from(currentInstance.timeLogSessions);
      existingSessions.add(newSession);
      // Calculate total cumulative time
      final totalTime = existingSessions.fold<int>(
          0, (sum, session) => sum + (session['durationMilliseconds'] as int));

      // Handle non-productive vs productive differently
      if (isNonProductive) {
        // For non-productive: find or create template, then update instance
        final templates = await NonProductiveService.getNonProductiveTemplates(
          userId: uid,
        );
        ActivityRecord? matchingTemplate;
        for (final template in templates) {
          if (template.name.toLowerCase() == taskName.toLowerCase()) {
            matchingTemplate = template;
            break;
          }
        }

        // Create template if it doesn't exist
        DocumentReference templateRef;
        if (matchingTemplate == null) {
          templateRef = await NonProductiveService.createNonProductiveTemplate(
            name: taskName,
            trackingType: 'time',
            userId: uid,
          );
        } else {
          templateRef = matchingTemplate.reference;
        }

        // Update instance with non-productive data (status remains pending)
        final updateData = <String, dynamic>{
          'status': 'pending',
          'isTimerActive': false,
          'isTimeLogging': false, // Stop time logging session
          'timeLogSessions': existingSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': totalTime,
          'templateId': templateRef.id,
          'templateName': taskName,
          'templateCategoryType': 'non_productive',
          'templateCategoryName': 'Non-Productive',
          'templateTrackingType': 'time',
          'currentSessionStartTime': null,
          'lastUpdated': DateTime.now(),
        };
        await taskInstanceRef.update(updateData);

        // Delete the old timer task template (cleanup)
        try {
          final oldTemplateRef = ActivityRecord.collectionForUser(uid)
              .doc(currentInstance.templateId);
          await oldTemplateRef.delete();
        } catch (e) {
          // Best effort cleanup, don't fail if it doesn't exist
        }
      } else {
        // For productive tasks: existing logic
        final updateData = <String, dynamic>{
          'status': 'pending',
          'isTimerActive': false,
          'isTimeLogging': false, // Stop time logging session
          'timeLogSessions': existingSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': totalTime,
          'templateName': taskName,
          'templateCategoryType': 'task', // Ensure it's marked as task
          'currentSessionStartTime': null,
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

        // Update the template name as well
        final templateRef = ActivityRecord.collectionForUser(uid)
            .doc(currentInstance.templateId);
        final templateUpdateData = <String, dynamic>{
          'name': taskName,
          'lastUpdated': DateTime.now(),
        };

        // Update template category if provided
        if (categoryId != null) {
          templateUpdateData['categoryId'] = categoryId;
        }
        if (categoryName != null) {
          templateUpdateData['categoryName'] = categoryName;
        }

        await templateRef.update(templateUpdateData);

        // Mark template as inactive - timer tasks are one-time use only
        // Keep template for editing purposes but prevent it from appearing in task lists
        await templateRef.update({'isActive': false});
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get timer task instances for calendar display
  static Future<List<ActivityInstanceRecord>> getTimerTaskInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      // Get tasks with traditional timer fields
      final timerQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('timerStartTime', isNull: false)
          .where('accumulatedTime', isGreaterThan: 0);
      // Get tasks with timeLogSessions
      final sessionQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('timeLogSessions', isNull: false);
      // Get tasks with time logged data (for paused timer tasks)
      final timeLoggedQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('totalTimeLogged', isGreaterThan: 0);
      final timerResult = await timerQuery.get();
      final sessionResult = await sessionQuery.get();
      final timeLoggedResult = await timeLoggedQuery.get();
      // Combine and deduplicate results
      final allInstances = <String, ActivityInstanceRecord>{};
      for (final doc in timerResult.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.isActive) {
          allInstances[instance.reference.id] = instance;
        }
      }
      for (final doc in sessionResult.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.isActive && instance.timeLogSessions.isNotEmpty) {
          allInstances[instance.reference.id] = instance;
        }
      }
      for (final doc in timeLoggedResult.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.isActive) {
          allInstances[instance.reference.id] = instance;
        }
      }
      return allInstances.values.toList();
    } catch (e) {
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

  /// Discard current time logging session (cancel session without saving)
  static Future<void> discardTimeLogging({
    required DocumentReference activityInstanceRef,
    String? userId,
  }) async {
    try {
      await activityInstanceRef.update({
        'isTimeLogging': false,
        'isTimerActive': false,
        'currentSessionStartTime': FieldValue.delete(),
        'lastUpdated': DateTime.now(),
      });
    } catch (e) {
      rethrow;
    }
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
            // endDate is exclusive (start of next day), so exclude sessions at or after endDate
            if (endDate != null && !sessionStart.isBefore(endDate)) return false;
            return true;
          });
        }).toList();
      }
      return tasks;
    } catch (e) {
      return [];
    }
  }

  /// Get all non-productive instances with time logs for calendar display
  static Future<List<ActivityInstanceRecord>> getNonProductiveInstances({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'non_productive')
          .where('totalTimeLogged', isGreaterThan: 0);
      final result = await query.get();
      final instances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((instance) =>
              instance.isActive && instance.timeLogSessions.isNotEmpty)
          .toList();
      // Filter by date range if provided
      if (startDate != null || endDate != null) {
        return instances.where((instance) {
          final sessions = instance.timeLogSessions;
          return sessions.any((session) {
            final sessionStart = session['startTime'] as DateTime;
            if (startDate != null && sessionStart.isBefore(startDate))
              return false;
            // endDate is exclusive (start of next day), so exclude sessions at or after endDate
            if (endDate != null && !sessionStart.isBefore(endDate)) return false;
            return true;
          });
        }).toList();
      }
      return instances;
    } catch (e) {
      return [];
    }
  }

  static Future<void> logManualTimeEntry({
    required String taskName,
    required DateTime startTime,
    required DateTime endTime,
    required String activityType, // 'task', 'habit', or 'non_productive'
    String? categoryId,
    String? categoryName,
    String? templateId, // Optional: if selecting an existing activity
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    if (startTime.isAfter(endTime)) {
      throw Exception("Start time cannot be after end time.");
    }

    final duration = endTime.difference(startTime);
    final totalTime = duration.inMilliseconds;

    // Create the session object
    final newSession = <String, dynamic>{
      'startTime': startTime,
      'endTime': endTime,
      'durationMilliseconds': totalTime,
    };

    try {
      // SMART INSTANCE LOOKUP LOGIC
      if (templateId != null) {
        DocumentReference? targetInstanceRef;
        dynamic existingInstance;
        bool isHabitInstanceRecord =
            false; // Track if instance is from HabitInstanceRecord collection

        // 1. Try to find an instance for this template (including completed ones)
        // First check pending/active instances
        if (activityType == 'habit') {
          // For Habits: Use date-aware lookup based on startTime (selected calendar date)
          // This ensures we find the same instance that's displayed in the queue for that date
          try {
            // Extract date from startTime (the selected calendar date)
            final targetDate =
                DateTime(startTime.year, startTime.month, startTime.day);

            final habitInstances =
                await ActivityInstanceService.getHabitInstancesForDate(
                    targetDate: targetDate, userId: uid);

            // Find the instance for this template
            ActivityInstanceRecord? habitMatch;
            for (final instance in habitInstances) {
              if (instance.templateId == templateId) {
                habitMatch = instance;
                break; // Use the first matching instance (should only be one per template)
              }
            }

            if (habitMatch != null) {
              targetInstanceRef = habitMatch.reference;
              existingInstance = habitMatch;
              isHabitInstanceRecord =
                  false; // ActivityInstanceRecord from getHabitInstancesForDate
            }
          } catch (e) {
            // Don't continue to create new instance - throw error instead
            throw Exception(
                'Failed to find habit instance for template $templateId. Please ensure the habit is active and appears in your habits list.');
          }
        } else if (activityType == 'task') {
          // For Tasks: Check Pending instances
          final tasks = await getTodaysTaskInstances(userId: uid);
          var match = tasks.firstWhereOrNull((t) => t.templateId == templateId);
          if (match != null) {
            targetInstanceRef = match.reference;
            existingInstance = match;
            isHabitInstanceRecord =
                false; // ActivityInstanceRecord from getTodaysTaskInstances
          }

          // 2. If not found in pending, check ALL instances (including completed) for this template
          // This handles cases where the instance was already completed but we want to add more time
          if (targetInstanceRef == null) {
            try {
              final allInstancesQuery =
                  ActivityInstanceRecord.collectionForUser(uid)
                      .where('templateId', isEqualTo: templateId)
                      .where('isActive', isEqualTo: true)
                      .orderBy('lastUpdated', descending: true)
                      .limit(1);
              final allInstancesResult =
                  await allInstancesQuery.get().catchError((e) {
                print(
                    '❌ MISSING INDEX: addTimeLogSession allInstancesQuery needs Index 4');
                print(
                    'Required Index: isActive (ASC) + templateId (ASC) + lastUpdated (DESC)');
                print('Collection: activity_instances');
                print('Full error: $e');
                if (e.toString().contains('index') ||
                    e.toString().contains('https://')) {
                  print(
                      '📋 Look for the Firestore index creation link in the error message above!');
                  print('   Click the link to create the index automatically.');
                }
                throw e;
              });
              if (allInstancesResult.docs.isNotEmpty) {
                final instanceDoc = allInstancesResult.docs.first;
                final instance =
                    ActivityInstanceRecord.fromSnapshot(instanceDoc);
                // Check if the instance's date matches the start time's date (same day)
                final instanceDate = instance.dueDate ?? instance.createdTime;
                if (instanceDate != null) {
                  final startDate =
                      DateTime(startTime.year, startTime.month, startTime.day);
                  final instanceDateOnly = DateTime(
                      instanceDate.year, instanceDate.month, instanceDate.day);

                  // Use this instance if it's for the same day, or if no dueDate (flexible)
                  if (instanceDateOnly.isAtSameMomentAs(startDate) ||
                      instance.dueDate == null) {
                    targetInstanceRef = instance.reference;
                    existingInstance = instance;
                    isHabitInstanceRecord =
                        false; // ActivityInstanceRecord from this query
                  }
                } else {
                  // If no date info, use the instance anyway (flexible matching)
                  targetInstanceRef = instance.reference;
                  existingInstance = instance;
                  isHabitInstanceRecord =
                      false; // ActivityInstanceRecord from this query
                }
              }
            } catch (e) {
              // If query fails, continue to create new instance
              // Error is logged but doesn't block the flow
            }
          }
        }

        // 3. If found, add session to it
        if (targetInstanceRef != null && existingInstance != null) {
          final currentSessions =
              List<Map<String, dynamic>>.from(existingInstance.timeLogSessions);
          currentSessions.add(newSession);

          final currentTotalLogged = existingInstance.totalTimeLogged;
          final newTotalLogged = currentTotalLogged + totalTime;

          // Prepare update data
          final updateData = <String, dynamic>{
            'timeLogSessions': currentSessions,
            'totalTimeLogged': newTotalLogged,
            'accumulatedTime': newTotalLogged,
            'currentValue': newTotalLogged, // Update current value for progress
            'lastUpdated': DateTime.now(),
          };

          // Fix: Ensure templateCategoryType is correct for non-productive items
          if (activityType == 'non_productive') {
            updateData['templateCategoryType'] = 'non_productive';
            updateData['templateCategoryName'] = 'Non-Productive';
          }

          // Use the correct collection reference based on where we found the instance
          // targetInstanceRef already points to the correct collection, so we can use it directly
          try {
            await targetInstanceRef.update(updateData);

            // Broadcast the instance update event for real-time UI updates
            final updatedInstance =
                await ActivityInstanceRecord.getDocumentOnce(targetInstanceRef);
            InstanceEvents.broadcastInstanceUpdated(updatedInstance);

            // Handle auto-completion for time-target tasks/habits
            // Check if adding this time log now meets or exceeds the target
            if (existingInstance.status != 'completed' &&
                existingInstance.templateTrackingType == 'time' &&
                existingInstance.templateTarget != null) {
              final target = existingInstance.templateTarget;
              if (target is num && target > 0) {
                final targetMs =
                    (target.toInt()) * 60000; // Convert minutes to milliseconds
                if (newTotalLogged >= targetMs) {
                  // Auto-complete when time meets/exceeds target
                  // Note: completeTaskInstance will broadcast again with completion status
                  await completeTaskInstance(
                    instanceId: targetInstanceRef.id,
                    finalValue: newTotalLogged,
                    finalAccumulatedTime: newTotalLogged,
                    userId: uid,
                  );
                }
              }
            }

            return; // Done
          } catch (e) {
            // Error updating instance
            rethrow; // Re-throw to surface the error
          }
        }

        // 4. If NOT found, handle based on activity type
        if (activityType == 'habit') {
          // For habits: Never create new instances - they must exist and be in the window
          // If we reach here, the habit instance was not found in the window
          throw Exception(
              'Habit instance not found for the selected date. Please ensure the habit is active and appears in your habits list. New habit instances cannot be created from the time log.');
        }

        // For tasks: Create NEW linked instance if template exists
        final templateRef =
            ActivityRecord.collectionForUser(uid).doc(templateId);
        final templateDoc = await templateRef.get();
        if (templateDoc.exists) {
          final template = ActivityRecord.fromSnapshot(templateDoc);
          // Create instance - preserve "no due date" if template doesn't have one
          // For tasks without due dates, use null; for others, use start time
          final instanceDueDate = template.dueDate == null ? null : startTime;
          final instanceRef =
              await ActivityInstanceService.createActivityInstance(
                  templateId: templateId,
                  dueDate:
                      instanceDueDate, // Preserve no due date if template doesn't have one
                  template: template,
                  userId: uid);

          // Now update it with the session
          // Recurse or just update? Update is safer
          final sessions = [newSession];
          await instanceRef.update({
            'timeLogSessions': sessions,
            'totalTimeLogged': totalTime,
            'accumulatedTime': totalTime,
            'currentValue': totalTime,
            'lastUpdated': DateTime.now(),
          });

          // Only auto-complete tasks if:
          // 1. It's a task (not habit/non-productive)
          // 2. Template has time tracking
          // 3. Template has a target set (> 0)
          // 4. Logged time meets or exceeds the target
          if (activityType == 'task' &&
              template.trackingType == 'time' &&
              template.target != null) {
            final target = template.target;
            if (target is num && target > 0) {
              final targetMs =
                  (target.toInt()) * 60000; // Convert minutes to milliseconds
              if (totalTime >= targetMs) {
                // Only complete if time meets/exceeds target
                await completeTaskInstance(
                    instanceId: instanceRef.id,
                    finalValue: totalTime,
                    finalAccumulatedTime: totalTime,
                    userId: uid);
              }
            }
          }
          return;
        }
      }

      // FALLBACK / NEW ONE-OFF LOGIC (Current Behavior + enhancements)

      // Create a temporary task instance to log this manual entry against.
      final taskInstanceRef = await createTimerTaskInstance(userId: uid);

      final isNonProductive = activityType == 'non_productive';
      final timeLogSessions = [newSession];

      if (isNonProductive) {
        // Find or create a template for the non-productive activity.
        final templates =
            await NonProductiveService.getNonProductiveTemplates(userId: uid);
        ActivityRecord? matchingTemplate;
        try {
          matchingTemplate = templates.firstWhere(
            (t) => t.name.toLowerCase() == taskName.toLowerCase(),
          );
        } catch (e) {
          matchingTemplate = null;
        }

        DocumentReference templateRef;
        if (matchingTemplate == null) {
          templateRef = await NonProductiveService.createNonProductiveTemplate(
            name: taskName,
            trackingType: 'time',
            userId: uid,
          );
        } else {
          templateRef = matchingTemplate.reference;
        }

        // Update the instance with non-productive data
        final updateData = <String, dynamic>{
          'status': 'completed',
          'completedAt': endTime,
          'isTimerActive': false,
          'timeLogSessions': timeLogSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': totalTime,
          'templateId': templateRef.id,
          'templateName': taskName,
          'templateCategoryType': 'non_productive',
          'templateCategoryName': 'Non-Productive',
          'templateTrackingType': 'time',
          'lastUpdated': DateTime.now(),
        };
        await taskInstanceRef.update(updateData);
      } else {
        // Handle productive tasks (New One-Off)
        final currentInstance =
            await ActivityInstanceRecord.getDocumentOnce(taskInstanceRef);
        final templateRef = ActivityRecord.collectionForUser(uid)
            .doc(currentInstance.templateId);

        // Update the instance with the manual log data.
        final updateData = <String, dynamic>{
          'status': 'completed',
          'completedAt': endTime,
          'isTimerActive': false,
          'timeLogSessions': timeLogSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': totalTime,
          'templateTarget': totalTime / 60000.0, // Minutes
          'templateName': taskName,
          'templateCategoryType': 'task',
          'templateTrackingType':
              'binary', // Force binary for one-offs per previous request
          'lastUpdated': DateTime.now(),
        };

        if (categoryId != null) updateData['templateCategoryId'] = categoryId;
        if (categoryName != null)
          updateData['templateCategoryName'] = categoryName;

        await taskInstanceRef.update(updateData);

        // Update the underlying template as well.
        final templateUpdateData = <String, dynamic>{
          'name': taskName,
          'lastUpdated': DateTime.now(),
          'isActive': false, // Mark one-off templates as inactive.
          'trackingType': 'binary',
        };

        if (categoryId != null) templateUpdateData['categoryId'] = categoryId;
        if (categoryName != null)
          templateUpdateData['categoryName'] = categoryName;

        await templateRef.update(templateUpdateData);
      }
    } catch (e) {
      // Re-throw to be handled by UI
      rethrow;
    }
  }

  /// Update a specific time log session
  static Future<void> updateTimeLogSession({
    required String instanceId,
    required int sessionIndex,
    required DateTime startTime,
    required DateTime endTime,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

      if (sessionIndex < 0 || sessionIndex >= instance.timeLogSessions.length) {
        throw Exception('Session index out of range');
      }

      // Validate time range
      if (startTime.isAfter(endTime)) {
        throw Exception('Start time cannot be after end time');
      }

      final duration = endTime.difference(startTime);
      final durationMs = duration.inMilliseconds;

      // Update the session
      final sessions =
          List<Map<String, dynamic>>.from(instance.timeLogSessions);
      sessions[sessionIndex] = {
        'startTime': startTime,
        'endTime': endTime,
        'durationMilliseconds': durationMs,
      };

      // Recalculate total time
      final totalTime = sessions.fold<int>(
          0, (sum, session) => sum + (session['durationMilliseconds'] as int));

      // Update the instance
      await instanceRef.update({
        'timeLogSessions': sessions,
        'totalTimeLogged': totalTime,
        'accumulatedTime': totalTime,
        'currentValue': totalTime,
        'lastUpdated': DateTime.now(),
      });

      // Broadcast the instance update event immediately for time changes
      final updatedInstance =
          await ActivityInstanceRecord.getDocumentOnce(instanceRef);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);

      // Handle auto-completion/uncompletion for time-target tasks/habits
      if (instance.templateTrackingType == 'time' &&
          instance.templateTarget != null) {
        final target = instance.templateTarget;
        if (target is num && target > 0) {
          final targetMs =
              (target.toInt()) * 60000; // Convert minutes to milliseconds

          // Auto-complete if not completed and time meets/exceeds target
          if (instance.status != 'completed' && totalTime >= targetMs) {
            await completeTaskInstance(
              instanceId: instanceId,
              finalValue: totalTime,
              finalAccumulatedTime: totalTime,
              userId: uid,
            );
          }
          // Auto-uncomplete if completed but time is now below target
          else if (instance.status == 'completed' && totalTime < targetMs) {
            await ActivityInstanceService.uncompleteInstance(
              instanceId: instanceId,
              userId: uid,
            );
          }
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a specific time log session
  /// Returns true if the instance was uncompleted due to time falling below target
  static Future<bool> deleteTimeLogSession({
    required String instanceId,
    required int sessionIndex,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

      if (sessionIndex < 0 || sessionIndex >= instance.timeLogSessions.length) {
        throw Exception('Session index out of range');
      }

      // Remove the session
      final sessions =
          List<Map<String, dynamic>>.from(instance.timeLogSessions);
      sessions.removeAt(sessionIndex);

      // Recalculate total time
      final totalTime = sessions.fold<int>(
          0, (sum, session) => sum + (session['durationMilliseconds'] as int));

      // Update the instance
      await instanceRef.update({
        'timeLogSessions': sessions,
        'totalTimeLogged': totalTime,
        'accumulatedTime': totalTime,
        'currentValue': totalTime,
        'lastUpdated': DateTime.now(),
      });

      // Handle auto-uncompletion for timer-type tasks/habits
      // If instance is completed and has time tracking with a target (> 0),
      // and the new total time is below the target, uncomplete it
      bool wasUncompleted = false;
      if (instance.status == 'completed' &&
          instance.templateTrackingType == 'time' &&
          instance.templateTarget != null) {
        final target = instance.templateTarget;
        if (target is num && target > 0) {
          final targetMs =
              (target.toInt()) * 60000; // Convert minutes to milliseconds
          if (totalTime < targetMs) {
            // Auto-uncomplete for timer types when time falls below target
            await ActivityInstanceService.uncompleteInstance(
              instanceId: instanceId,
              userId: uid,
            );
            wasUncompleted = true;
          }
        }
      }

      return wasUncompleted;
    } catch (e) {
      rethrow;
    }
  }
}
