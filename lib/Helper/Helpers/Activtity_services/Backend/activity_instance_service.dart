import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_date_calculator.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/reminder_scheduler.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/instance_order_service.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/time_estimate_resolver.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/optimistic_operation_tracker.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/recurrence_calculator.dart';

/// Result of calculating stacked session times
class StackedSessionTimes {
  final DateTime startTime;
  final DateTime endTime;

  StackedSessionTimes({
    required this.startTime,
    required this.endTime,
  });
}

/// Service to manage activity instances
/// Handles the creation, completion, and scheduling of recurring activities
/// Following Microsoft To-Do pattern: only show current instances, generate next on completion
class ActivityInstanceService {
  /// Get current user ID
  static String get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return user.uid;
  }

  // ==================== INSTANCE CREATION ====================
  /// Create a new activity instance from a template
  /// This is the core method for Phase 1 - instance creation
  static Future<DocumentReference> createActivityInstance({
    required String templateId,
    DateTime? dueDate,
    String? dueTime,
    required ActivityRecord template,
    String? userId,
    bool skipOrderLookup = false, // Skip order lookup for faster task creation
  }) async {
    final uid = userId ?? _currentUserId;
    final now = DateService.currentDate;
    // Calculate initial due date using the helper
    final DateTime? initialDueDate = dueDate ??
        InstanceDateCalculator.calculateInitialDueDate(
          template: template,
          explicitDueDate: null,
        );
    // For habits, set belongsToDate to the actual due date
    final normalizedDate = initialDueDate != null
        ? DateTime(
            initialDueDate.year, initialDueDate.month, initialDueDate.day)
        : DateService.todayStart;
    // Calculate window fields for habits only (skip for tasks to speed up)
    DateTime? windowEndDate;
    int? windowDuration;
    if (template.categoryType == 'habit') {
      windowDuration = await _calculateAdaptiveWindowDuration(
        template: template,
        userId: uid,
        currentDate: initialDueDate ?? DateService.currentDate,
      );
      // Handle case where target is already met
      if (windowDuration == 0) {
        // Return a dummy reference since we're not creating an instance
        return ActivityInstanceRecord.collectionForUser(uid).doc('dummy');
      }
      windowEndDate = normalizedDate.add(Duration(days: windowDuration - 1));
    }
    // Fetch category color for the instance
    // Note: For quick add tasks, we could pass this from UI, but for now we still fetch it
    // as it's needed for the instance. This is a small cost compared to order lookups.
    String? categoryColor;
    try {
      if (template.categoryId.isNotEmpty) {
        final categoryDoc = await CategoryRecord.collectionForUser(uid)
            .doc(template.categoryId)
            .get();
        if (categoryDoc.exists) {
          final category = CategoryRecord.fromSnapshot(categoryDoc);
          categoryColor = category.color;
        }
      }
    } catch (e) {
      // If category fetch fails, continue without color
    }
    // Inherit order from previous instance of the same template
    // Skip for tasks to speed up quick add - order will be set on next load if needed
    int? queueOrder;
    int? habitsOrder;
    int? tasksOrder;
    if (!skipOrderLookup) {
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
    } else if (template.categoryType == 'task') {
      // For quick-add tasks, set a very negative order value so they appear at the top
      // This ensures newly created tasks are always visible immediately
      tasksOrder = -999999;
    }
    final instanceData = createActivityInstanceRecordData(
      templateId: templateId,
      dueDate: initialDueDate,
      dueTime: dueTime ?? template.dueTime,
      status: 'pending',
      createdTime: now,
      lastUpdated: now,
      isActive: true,
      lastDayValue: 0, // Initialize for differential tracking
      // Cache template data for quick access (denormalized)
      templateName: template.name,
      templateCategoryId: template.categoryId,
      templateCategoryName: template.categoryName,
      templateCategoryType: template.categoryType,
      templateCategoryColor: categoryColor,
      templatePriority: template.priority,
      templateTrackingType: template.trackingType,
      templateTarget: template.target,
      templateUnit: template.unit,
      templateDescription: template.description,
      templateTimeEstimateMinutes: template.timeEstimateMinutes,
      templateShowInFloatingTimer: template.showInFloatingTimer,
      templateIsRecurring: template.isRecurring,
      templateEveryXValue: template.everyXValue,
      templateEveryXPeriodType: template.everyXPeriodType,
      templateTimesPerPeriod: template.timesPerPeriod,
      templatePeriodType: template.periodType,
      templateDueTime: template.dueTime,
      // Set habit-specific fields
      dayState: template.categoryType == 'habit' ? 'open' : null,
      belongsToDate: template.categoryType == 'habit' ||
              template.categoryType == 'essential'
          ? normalizedDate
          : null,
      windowEndDate: windowEndDate,
      windowDuration: windowDuration,
      // Inherit order from previous instance
      queueOrder: queueOrder,
      habitsOrder: habitsOrder,
      tasksOrder: tasksOrder,
    );

    // ==================== OPTIMISTIC BROADCAST ====================
    // 1. Create optimistic instance with temporary reference
    final tempRef = ActivityInstanceRecord.collectionForUser(uid)
        .doc('temp_${DateTime.now().millisecondsSinceEpoch}');
    final optimisticInstance = ActivityInstanceRecord.getDocumentFromData(
      instanceData,
      tempRef,
    );

    // 2. Generate operation ID
    final operationId = OptimisticOperationTracker.generateOperationId();

    // 3. Track operation
    OptimisticOperationTracker.trackOperation(
      operationId,
      instanceId: 'temp', // Will be updated on reconciliation
      operationType: 'create',
      optimisticInstance: optimisticInstance,
      originalInstance:
          optimisticInstance, // For creation, use optimistic as original since there's no existing instance
    );

    // 4. Broadcast optimistically (IMMEDIATE)
    InstanceEvents.broadcastInstanceCreatedOptimistic(
        optimisticInstance, operationId);

    // 5. Perform backend creation
    try {
      final result =
          await ActivityInstanceRecord.collectionForUser(uid).add(instanceData);

      // 6. Reconcile with actual instance
      final actualInstance = ActivityInstanceRecord.fromSnapshot(
        await result.get(),
      );
      OptimisticOperationTracker.reconcileInstanceCreation(
          operationId, actualInstance);

      // Schedule reminder if instance has due time
      try {
        await ReminderScheduler.scheduleReminderForInstance(actualInstance);
      } catch (e) {
        // Error scheduling reminder - continue without it
      }

      return result;
    } catch (e) {
      // 7. Rollback on error
      OptimisticOperationTracker.rollbackOperation(operationId);
      rethrow;
    }
  }

  // ==================== INSTANCE QUERYING ====================
  /// Get active task instances for the user
  /// This is the core method for Phase 2 - displaying instances
  /// It returns only the earliest pending instance for each task template
  static Future<List<ActivityInstanceRecord>> getActiveTaskInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'task')
          .where('status', isEqualTo: 'pending');
      final result = await query.get();
      final allPendingInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      // Group instances by templateId and keep only the one with the earliest due date
      final Map<String, ActivityInstanceRecord> earliestInstances = {};
      for (final instance in allPendingInstances) {
        final templateId = instance.templateId;
        if (!earliestInstances.containsKey(templateId)) {
          earliestInstances[templateId] = instance;
        } else {
          final existing = earliestInstances[templateId]!;
          // Handle null due dates: nulls go last
          if (existing.dueDate == null) {
            // Keep existing (null), unless new also has a date
            if (instance.dueDate != null) {
              earliestInstances[templateId] = instance;
            }
          } else if (instance.dueDate == null) {
            // Keep existing (has date)
            continue;
          } else {
            // Both have dates, compare normally
            if (instance.dueDate!.isBefore(existing.dueDate!)) {
              earliestInstances[templateId] = instance;
            }
          }
        }
      }
      final finalInstanceList = earliestInstances.values.toList();
      // Sort: instances with due dates first (oldest first), then nulls last
      finalInstanceList.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1; // a goes after b
        if (b.dueDate == null) return -1; // a goes before b
        return a.dueDate!.compareTo(b.dueDate!);
      });
      return finalInstanceList;
    } catch (e) {
      return [];
    }
  }

  /// Get all task instances (active and completed) for Recent Completions
  static Future<List<ActivityInstanceRecord>> getAllTaskInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'task');
      final result = await query.get();
      final allInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      return InstanceOrderService.sortInstancesByOrder(allInstances, 'tasks');
    } catch (e) {
      return [];
    }
  }

  /// Get current active habit instances for the user (Habits page)
  /// Only returns instances whose window includes today - no future instances
  static Future<List<ActivityInstanceRecord>> getCurrentHabitInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      // Fetch ALL habit instances regardless of status to include completed/skipped/snoozed
      // The calculator and UI will filter appropriately
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'habit');
      final result = await query.get();
      final allHabitInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      // Group instances by templateId and apply window-based filtering
      final Map<String, List<ActivityInstanceRecord>> instancesByTemplate = {};
      for (final instance in allHabitInstances) {
        final templateId = instance.templateId;
        (instancesByTemplate[templateId] ??= []).add(instance);
      }
      final List<ActivityInstanceRecord> relevantInstances = [];
      final today = DateService.todayStart;
      for (final templateId in instancesByTemplate.keys) {
        final instances = instancesByTemplate[templateId]!;
        // Sort instances by due date (earliest first)
        instances.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        // Find instances to include for this template
        final instancesToInclude = <ActivityInstanceRecord>[];
        for (final instance in instances) {
          // Include instance if today falls within its window [dueDate, windowEndDate]
          if (instance.dueDate != null && instance.windowEndDate != null) {
            final windowStart = DateTime(instance.dueDate!.year,
                instance.dueDate!.month, instance.dueDate!.day);
            final windowEnd = DateTime(instance.windowEndDate!.year,
                instance.windowEndDate!.month, instance.windowEndDate!.day);
            if (!today.isBefore(windowStart) && !today.isAfter(windowEnd)) {
              instancesToInclude.add(instance);
            }
          }
        }
        // For Habits page: Only include current instances, NOT future instances
        // This prevents showing "Tomorrow" instances in the Habits page
        relevantInstances.addAll(instancesToInclude);
      }
      // Sort: instances with due dates first (oldest first), then nulls last
      relevantInstances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1; // a goes after b
        if (b.dueDate == null) return -1; // a goes before b
        return a.dueDate!.compareTo(b.dueDate!);
      });
      return relevantInstances;
    } catch (e) {
      return [];
    }
  }

  /// Get habit instances whose window includes a specific date
  /// Used for calendar time logging to find instances for past/future dates
  /// Similar to getCurrentHabitInstances but uses targetDate instead of today
  static Future<List<ActivityInstanceRecord>> getHabitInstancesForDate({
    required DateTime targetDate,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      // Normalize target date to start of day for comparison
      final targetDateStart =
          DateTime(targetDate.year, targetDate.month, targetDate.day);

      // Fetch ALL habit instances regardless of status to include completed/skipped/snoozed
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'habit');
      final result = await query.get();
      final allHabitInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      // Group instances by templateId and apply window-based filtering
      final Map<String, List<ActivityInstanceRecord>> instancesByTemplate = {};
      for (final instance in allHabitInstances) {
        final templateId = instance.templateId;
        (instancesByTemplate[templateId] ??= []).add(instance);
      }
      final List<ActivityInstanceRecord> relevantInstances = [];

      for (final templateId in instancesByTemplate.keys) {
        final instances = instancesByTemplate[templateId]!;
        // Sort instances by due date (earliest first)
        instances.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        // Find instances to include for this template
        final instancesToInclude = <ActivityInstanceRecord>[];
        for (final instance in instances) {
          // Include instance if targetDate falls within its window [dueDate, windowEndDate]
          if (instance.dueDate != null && instance.windowEndDate != null) {
            final windowStart = DateTime(instance.dueDate!.year,
                instance.dueDate!.month, instance.dueDate!.day);
            final windowEnd = DateTime(instance.windowEndDate!.year,
                instance.windowEndDate!.month, instance.windowEndDate!.day);
            if (!targetDateStart.isBefore(windowStart) &&
                !targetDateStart.isAfter(windowEnd)) {
              instancesToInclude.add(instance);
            }
          }
        }
        relevantInstances.addAll(instancesToInclude);
      }
      // Sort: instances with due dates first (oldest first), then nulls last
      relevantInstances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1; // a goes after b
        if (b.dueDate == null) return -1; // a goes before b
        return a.dueDate!.compareTo(b.dueDate!);
      });

      return relevantInstances;
    } catch (e) {
      return [];
    }
  }

  /// Get all habit instances for the Habits page (no date/status filtering)
  /// Shows all instances regardless of window dates or status
  static Future<List<ActivityInstanceRecord>> getAllHabitInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'habit');
      final result = await query.get();
      final allHabitInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      // Sort by due date (earliest first, nulls last)
      allHabitInstances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
      return allHabitInstances;
    } catch (e) {
      return [];
    }
  }

  /// Get latest habit instance per template for the Habits page
  /// Returns one instance per habit template - the next upcoming/actionable instance
  /// No date filtering - shows even future instances
  static Future<List<ActivityInstanceRecord>>
      getLatestHabitInstancePerTemplate({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'habit');
      final result = await query.get();
      final allHabitInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      // Group instances by templateId
      final Map<String, List<ActivityInstanceRecord>> instancesByTemplate = {};
      for (final instance in allHabitInstances) {
        final templateId = instance.templateId;
        (instancesByTemplate[templateId] ??= []).add(instance);
      }
      final List<ActivityInstanceRecord> latestInstances = [];
      for (final templateId in instancesByTemplate.keys) {
        final instances = instancesByTemplate[templateId]!;
        // Sort instances by due date (earliest first, nulls last)
        instances.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        // Find the latest instance for this template
        ActivityInstanceRecord? latestInstance;
        // First, try to find the earliest pending instance (next upcoming)
        for (final instance in instances) {
          if (instance.status == 'pending') {
            latestInstance = instance;
            break;
          }
        }
        // If no pending instance found, use the latest completed instance
        if (latestInstance == null) {
          // Find the most recent completed/skipped instance
          for (final instance in instances.reversed) {
            if (instance.status == 'completed' ||
                instance.status == 'skipped') {
              latestInstance = instance;
              break;
            }
          }
        }
        // If still no instance found, use the first one (fallback)
        if (latestInstance == null && instances.isNotEmpty) {
          latestInstance = instances.first;
        }
        if (latestInstance != null) {
          latestInstances.add(latestInstance);
        }
      }
      // Sort final list by due date (earliest first, nulls last)
      latestInstances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });

      return latestInstances;
    } catch (e) {
      return [];
    }
  }

  /// Get active habit instances for the user (Queue page - includes future instances)
  static Future<List<ActivityInstanceRecord>> getActiveHabitInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      // Fetch ALL habit instances regardless of status to include completed/skipped/snoozed
      // The calculator and UI will filter appropriately
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'habit');
      final result = await query.get();
      final allHabitInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      // Group instances by templateId and apply window-based filtering
      final Map<String, List<ActivityInstanceRecord>> instancesByTemplate = {};
      for (final instance in allHabitInstances) {
        final templateId = instance.templateId;
        (instancesByTemplate[templateId] ??= []).add(instance);
      }
      final List<ActivityInstanceRecord> relevantInstances = [];
      final today = DateService.todayStart;
      for (final templateId in instancesByTemplate.keys) {
        final instances = instancesByTemplate[templateId]!;
        // Sort instances by due date (earliest first)
        instances.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        // Find instances to include for this template
        final instancesToInclude = <ActivityInstanceRecord>[];
        for (final instance in instances) {
          // Include instance if today falls within its window [dueDate, windowEndDate]
          if (instance.dueDate != null && instance.windowEndDate != null) {
            final windowStart = DateTime(instance.dueDate!.year,
                instance.dueDate!.month, instance.dueDate!.day);
            final windowEnd = DateTime(instance.windowEndDate!.year,
                instance.windowEndDate!.month, instance.windowEndDate!.day);
            if (!today.isBefore(windowStart) && !today.isAfter(windowEnd)) {
              instancesToInclude.add(instance);
            }
          }
        }
        // ALWAYS include the next pending instance (for future planning)
        final nextPending = instances.firstWhere(
          (instance) => instance.status == 'pending',
          orElse: () => instances.first,
        );
        if (!instancesToInclude.contains(nextPending)) {
          instancesToInclude.add(nextPending);
        }
        relevantInstances.addAll(instancesToInclude);
      }
      // Sort: instances with due dates first (oldest first), then nulls last
      relevantInstances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1; // a goes after b
        if (b.dueDate == null) return -1; // a goes before b
        return a.dueDate!.compareTo(b.dueDate!);
      });
      return relevantInstances;
    } catch (e) {
      return [];
    }
  }

  /// Get all active instances for a user (tasks and habits)
  static Future<List<ActivityInstanceRecord>> getAllActiveInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      // Fetch ALL instances regardless of status to include completed/skipped/snoozed
      // The calculator and UI will filter appropriately
      final query = ActivityInstanceRecord.collectionForUser(uid);
      final result = await query.get();
      final allInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      // Debug: Log status breakdown
      final statusCounts = <String, int>{};
      for (final inst in allInstances) {
        statusCounts[inst.status] = (statusCounts[inst.status] ?? 0) + 1;
      }
      // Separate tasks and habits for different filtering logic
      // Exclude essentials from normal queries
      // Also filter out inactive instances to match tasks page behavior
      final taskInstances = allInstances
          .where((inst) =>
              inst.templateCategoryType == 'task' &&
              inst.templateCategoryType != 'essential' &&
              inst.isActive) // Filter inactive instances
          .toList();
      final habitInstances = allInstances
          .where((inst) =>
              inst.templateCategoryType == 'habit' &&
              inst.isActive) // Filter inactive instances
          .toList();
      final List<ActivityInstanceRecord> finalInstanceList = [];
      // For tasks: use earliest-only logic with status priority
      final Map<String, ActivityInstanceRecord> earliestTasks = {};
      for (final instance in taskInstances) {
        // Skip inactive instances (should already be filtered, but double-check)
        if (!instance.isActive) continue;
        final templateId = instance.templateId;
        if (!earliestTasks.containsKey(templateId)) {
          earliestTasks[templateId] = instance;
        } else {
          final existing = earliestTasks[templateId]!;
          // Prioritize pending instances
          if (existing.status != 'pending' && instance.status == 'pending') {
            earliestTasks[templateId] = instance;
          } else if (existing.status == 'pending' &&
              instance.status != 'pending') {
            continue;
          } else if (existing.status == instance.status) {
            // Same status: compare by due date
            if (existing.dueDate == null) {
              if (instance.dueDate != null) {
                earliestTasks[templateId] = instance;
              }
            } else if (instance.dueDate == null) {
              continue;
            } else {
              if (instance.dueDate!.isBefore(existing.dueDate!)) {
                earliestTasks[templateId] = instance;
              }
            }
          }
        }
      }
      finalInstanceList.addAll(earliestTasks.values);
      // For habits: use window-based filtering (new behavior)
      final Map<String, List<ActivityInstanceRecord>> habitInstancesByTemplate =
          {};
      for (final instance in habitInstances) {
        final templateId = instance.templateId;
        (habitInstancesByTemplate[templateId] ??= []).add(instance);
      }
      final today = DateService.todayStart;
      for (final templateId in habitInstancesByTemplate.keys) {
        final instances = habitInstancesByTemplate[templateId]!;
        // Sort instances by due date (earliest first)
        instances.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        // Find instances to include for this template
        final instancesToInclude = <ActivityInstanceRecord>[];
        for (final instance in instances) {
          // Include instance if today falls within its window [dueDate, windowEndDate]
          if (instance.dueDate != null && instance.windowEndDate != null) {
            final windowStart = DateTime(instance.dueDate!.year,
                instance.dueDate!.month, instance.dueDate!.day);
            final windowEnd = DateTime(instance.windowEndDate!.year,
                instance.windowEndDate!.month, instance.windowEndDate!.day);
            if (!today.isBefore(windowStart) && !today.isAfter(windowEnd)) {
              instancesToInclude.add(instance);
            }
          }
        }
        // Find the next pending instance (for future planning)
        final pendingInstances = instances
            .where((instance) => instance.status == 'pending')
            .toList();

        if (pendingInstances.isNotEmpty) {
          // Include the earliest pending instance if not already included
          final nextPending = pendingInstances.first;
          if (!instancesToInclude.contains(nextPending)) {
            instancesToInclude.add(nextPending);
          }
        }
        // Note: If no pending instances exist, MorningCatchUpService will handle
        // generating them at the appropriate time. Queries should not have side effects.
        finalInstanceList.addAll(instancesToInclude);
      }
      // Sort: instances with due dates first (oldest first), then nulls last
      finalInstanceList.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1; // a goes after b
        if (b.dueDate == null) return -1; // a goes before b
        return a.dueDate!.compareTo(b.dueDate!);
      });
      return finalInstanceList;
    } catch (e) {
      return [];
    }
  }

  // ==================== UTILITY METHODS ====================
  /// Test method to manually create an instance (for debugging)
  static Future<void> testCreateInstance({
    required String templateId,
    String? userId,
  }) async {
    try {
      // Get the template
      final uid = userId ?? _currentUserId;
      final templateRef = ActivityRecord.collectionForUser(uid).doc(templateId);
      final template = await ActivityRecord.getDocumentOnce(templateRef);
      // Create instance
      await createActivityInstance(
        templateId: templateId,
        template: template,
        userId: uid,
      );
    } catch (e) {
      // Log error in test method - this is for debugging only
      print('Error in testCreateInstance: $e');
    }
  }

  /// Get all instances for a specific template (for debugging/testing)
  static Future<List<ActivityInstanceRecord>> getInstancesForTemplate({
    required String templateId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId)
          .orderBy('dueDate', descending: false);
      final result = await query.get();
      return result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
    } catch (e) {
      print('❌ Error in getInstancesForTemplate: $e');
      if (e.toString().contains('index')) {
        print('📋 This query requires an index. Check the link above!');
      }
      rethrow; // Re-throw to let the caller handle/log it excessively if needed
    }
  }

  /// Get all instances for a user (for debugging/testing)
  static Future<List<ActivityInstanceRecord>> getAllInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .orderBy('dueDate', descending: false);
      final result = await query.get();
      return result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Delete all instances for a template (cleanup utility)
  static Future<void> deleteInstancesForTemplate({
    required String templateId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId);
      final instances = await query.get();
      for (final doc in instances.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Reset all instances for a fresh start - deletes all instances and creates new ones starting tomorrow

  /// Get updated instance data after changes
  static Future<ActivityInstanceRecord> getUpdatedInstance({
    required String instanceId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      return ActivityInstanceRecord.fromSnapshot(instanceDoc);
    } catch (e) {
      rethrow;
    }
  }

  // ==================== INSTANCE COMPLETION ====================
  /// Calculate duration for time log session based on tracking type and user preferences
  /// Returns 0 if no session should be created (estimates disabled, time-target, or already has sessions)
  /// [effectiveEstimateMinutes] should be resolved via TimeEstimateResolver.getEffectiveEstimateMinutes
  static int calculateCompletionDuration(
    ActivityInstanceRecord instance,
    DateTime completedAt, {
    int? effectiveEstimateMinutes,
  }) {
    // If already has sessions, don't create default
    if (instance.timeLogSessions.isNotEmpty) {
      return 0; // Signal to skip creation
    }

    // If no effective estimate (disabled or time-target), return 0
    if (effectiveEstimateMinutes == null) {
      return 0;
    }

    final estimateMs =
        effectiveEstimateMinutes * 60000; // Convert to milliseconds
    final trackingType = instance.templateTrackingType;

    if (trackingType == 'time') {
      // For time-target items: use actual accumulated time if available
      final accumulatedMs = instance.accumulatedTime > 0
          ? instance.accumulatedTime
          : (instance.totalTimeLogged > 0 ? instance.totalTimeLogged : 0);
      if (accumulatedMs > 0) {
        return accumulatedMs;
      }
      // If we reach here, it's a non-time-target time tracking activity
      // Use the effective estimate
      return estimateMs;
    } else if (trackingType == 'quantitative') {
      // Quantity items: use the effective estimate as-is (per completion)
      // The estimate represents the total time for the full target
      return estimateMs;
    } else {
      // Binary items: use effective estimate
      return estimateMs;
    }
  }

  /// Find other instances completed within a time window (for backward stacking)
  static Future<List<ActivityInstanceRecord>> findSimultaneousCompletions({
    required String userId,
    required DateTime completionTime,
    required String excludeInstanceId,
    Duration window = const Duration(seconds: 15),
  }) async {
    try {
      final windowStart = completionTime.subtract(window);
      final windowEnd = completionTime.add(window);

      final query = ActivityInstanceRecord.collectionForUser(userId)
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: windowStart)
          .where('completedAt', isLessThanOrEqualTo: windowEnd);

      final results = await query.get();
      return results.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((instance) => instance.reference.id != excludeInstanceId)
          .toList();
    } catch (e) {
      print('❌ MISSING INDEX: findSimultaneousCompletions needs Index 4');
      print('Required Index: status (ASC) + completedAt (ASC)');
      print('Collection: activity_instances');
      print('Full error: $e');
      if (e.toString().contains('index') || e.toString().contains('https://')) {
        print(
            '📋 Look for the Firestore index creation link in the error message above!');
        print('   Click the link to create the index automatically.');
      }
      return [];
    }
  }

  /// Calculate start and end times for a session, stacking backwards from completion time
  /// Returns both start and end times to ensure correct duration when stacking against simultaneous items
  static Future<StackedSessionTimes> calculateStackedStartTime({
    required String userId,
    required DateTime completionTime,
    required int durationMs,
    required String instanceId,
    int? effectiveEstimateMinutes,
  }) async {
    // Find other items completed at the same time (excludes same instance)
    // For quantitative increments, subsequent blocks in the same batch stack directly,
    // so we only need to check for other instances here
    final simultaneous = await findSimultaneousCompletions(
      userId: userId,
      completionTime: completionTime,
      excludeInstanceId: instanceId,
    );

    if (simultaneous.isEmpty) {
      // No other items, just stack backwards from completion time
      final startTime =
          completionTime.subtract(Duration(milliseconds: durationMs));
      return StackedSessionTimes(
        startTime: startTime,
        endTime: completionTime,
      );
    }

    // Calculate total duration of simultaneous items
    // Use actual session durations if they exist, otherwise calculate duration using estimates
    int totalDurationMs = 0;
    for (final item in simultaneous) {
      if (item.timeLogSessions.isNotEmpty) {
        // Use actual session duration (most recent session)
        final lastSession = item.timeLogSessions.last;
        final sessionDuration =
            lastSession['durationMilliseconds'] as int? ?? 0;
        totalDurationMs += sessionDuration;
      } else {
        // Load template for this item to resolve effective estimate
        ActivityRecord? itemTemplate;
        if (item.hasTemplateId()) {
          try {
            final itemTemplateRef =
                ActivityRecord.collectionForUser(userId).doc(item.templateId);
            final itemTemplateDoc = await itemTemplateRef.get();
            if (itemTemplateDoc.exists) {
              itemTemplate = ActivityRecord.fromSnapshot(itemTemplateDoc);
            }
          } catch (e) {
            // Continue without template (will use global default)
          }
        }

        // Resolve effective estimate for this simultaneous item
        final itemEffectiveEstimate =
            await TimeEstimateResolver.getEffectiveEstimateMinutes(
          userId: userId,
          trackingType: item.templateTrackingType,
          target: item.templateTarget,
          hasExplicitSessions: item.timeLogSessions.isNotEmpty,
          template: itemTemplate,
        );

        // Calculate duration for this item
        final itemDuration = calculateCompletionDuration(
          item,
          item.completedAt ?? completionTime,
          effectiveEstimateMinutes: itemEffectiveEstimate,
        );
        if (itemDuration > 0) {
          totalDurationMs += itemDuration;
        }
      }
    }

    // Stack this new item BEFORE all simultaneous items
    // Start time = completion time - (total duration of simultaneous items + this item's duration)
    // End time = completion time - total duration of simultaneous items
    // This ensures the new item appears first in the backward stack with correct duration
    final stackedStartTime = completionTime.subtract(
      Duration(milliseconds: totalDurationMs + durationMs),
    );
    final stackedEndTime = completionTime.subtract(
      Duration(milliseconds: totalDurationMs),
    );

    return StackedSessionTimes(
      startTime: stackedStartTime,
      endTime: stackedEndTime,
    );
  }

  /// Complete an activity instance
  static Future<void> completeInstance({
    required String instanceId,
    dynamic finalValue,
    int? finalAccumulatedTime,
    String? notes,
    String? userId,
  }) async {
    await completeInstanceWithBackdate(
      instanceId: instanceId,
      finalValue: finalValue,
      finalAccumulatedTime: finalAccumulatedTime,
      notes: notes,
      userId: userId,
      completedAt: null, // Use current time
    );
  }

  /// Complete an activity instance with backdated completion time
  static Future<void> completeInstanceWithBackdate({
    required String instanceId,
    dynamic finalValue,
    int? finalAccumulatedTime,
    String? notes,
    String? userId,
    DateTime? completedAt, // If null, uses current time
    bool forceSessionBackdate = false,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateService.currentDate;
      final completionTime = completedAt ?? now;

      // Auto-create time log session if none exists
      final existingSessions =
          List<Map<String, dynamic>>.from(instance.timeLogSessions);

      // Load template to check for per-activity estimate
      ActivityRecord? template;
      if (instance.hasTemplateId()) {
        try {
          final templateRef =
              ActivityRecord.collectionForUser(uid).doc(instance.templateId);
          final templateDoc = await templateRef.get();
          if (templateDoc.exists) {
            template = ActivityRecord.fromSnapshot(templateDoc);
          }
        } catch (e) {
          // If template load fails, continue without it (will use global default)
        }
      }

      // Resolve effective estimate minutes
      final effectiveEstimateMinutes =
          await TimeEstimateResolver.getEffectiveEstimateMinutes(
        userId: uid,
        trackingType: instance.templateTrackingType,
        target: instance.templateTarget,
        hasExplicitSessions: existingSessions.isNotEmpty,
        template: template,
      );

      final durationMs = calculateCompletionDuration(
        instance,
        completionTime,
        effectiveEstimateMinutes: effectiveEstimateMinutes,
      );
      final resolvedFinalValue = finalValue ?? instance.currentValue;
      // Heuristic to prevent "points explosion": if not time tracking, but value looks like MS,
      // don't store it in currentValue. This ensures points stay consistent.
      dynamic currentValueToStore = resolvedFinalValue;
      if (instance.templateTrackingType != 'time' &&
          resolvedFinalValue is num) {
        final double val = resolvedFinalValue.toDouble();
        final double accTime =
            (finalAccumulatedTime ?? instance.accumulatedTime).toDouble();
        if (val > 1000 && val == accTime) {
          // This is duration, not progress.
          if (instance.templateCategoryType == 'essential') {
            currentValueToStore = 1; // Essentials are binary
          } else if (instance.templateTrackingType == 'binary') {
            currentValueToStore = 1;
          } else {
            currentValueToStore = instance.currentValue;
          }
        }
      }

      final updateData = <String, dynamic>{
        'status': 'completed',
        'completedAt': completionTime,
        'currentValue': currentValueToStore,
        'accumulatedTime': finalAccumulatedTime ?? instance.accumulatedTime,
        'notes': notes ?? instance.notes,
        'lastUpdated': now,
      };

      int? forcedDurationMs;
      if (forceSessionBackdate) {
        final int recordedDuration =
            finalAccumulatedTime ?? instance.accumulatedTime;
        final int totalLogged = instance.totalTimeLogged;
        final int candidateDuration = recordedDuration > 0
            ? recordedDuration
            : (totalLogged > 0 ? totalLogged : 0);
        if (candidateDuration > 0) {
          forcedDurationMs = candidateDuration;
        } else if (durationMs > 0) {
          forcedDurationMs = durationMs;
        }
      }

      if (forceSessionBackdate && (forcedDurationMs ?? 0) > 0) {
        final stackedTimes = await calculateStackedStartTime(
          userId: uid,
          completionTime: completionTime,
          durationMs: forcedDurationMs!,
          instanceId: instanceId,
          effectiveEstimateMinutes: effectiveEstimateMinutes,
        );

        final forcedSession = {
          'startTime': stackedTimes.startTime,
          'endTime': stackedTimes.endTime,
          'durationMilliseconds': forcedDurationMs,
        };

        existingSessions
          ..clear()
          ..add(forcedSession);

        updateData['timeLogSessions'] = existingSessions;
        updateData['totalTimeLogged'] = forcedDurationMs;
        updateData['accumulatedTime'] =
            finalAccumulatedTime ?? forcedDurationMs;
      } else if (durationMs > 0 && existingSessions.isEmpty) {
        // Calculate stacked start and end times (backwards from completion time)
        final stackedTimes = await calculateStackedStartTime(
          userId: uid,
          completionTime: completionTime,
          durationMs: durationMs,
          instanceId: instanceId,
          effectiveEstimateMinutes: effectiveEstimateMinutes,
        );

        final newSession = {
          'startTime': stackedTimes.startTime,
          'endTime': stackedTimes.endTime,
          'durationMilliseconds': durationMs,
        };
        existingSessions.add(newSession);

        // Update totalTimeLogged
        final totalTime = existingSessions.fold<int>(
          0,
          (sum, session) =>
              sum + (session['durationMilliseconds'] as int? ?? 0),
        );

        // Include in update data
        updateData['timeLogSessions'] = existingSessions;
        updateData['totalTimeLogged'] = totalTime;
      }

      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Extract time log sessions and total time for optimistic instance
      final optimisticTimeLogSessions =
          updateData['timeLogSessions'] as List<Map<String, dynamic>>?;
      final optimisticTotalTimeLogged = updateData['totalTimeLogged'] as int?;

      // 2. Create optimistic instance with time log sessions included
      final optimisticInstance =
          InstanceEvents.createOptimisticCompletedInstance(
        instance,
        finalValue: currentValueToStore,
        finalAccumulatedTime: finalAccumulatedTime ?? instance.accumulatedTime,
        completedAt: completionTime,
        timeLogSessions: optimisticTimeLogSessions,
        totalTimeLogged: optimisticTotalTimeLogged,
      );

      // 3. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      // 4. Track operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'complete',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );

      // 5. Broadcast optimistically (IMMEDIATE)
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);

      // 6. Perform backend update
      try {
        await instanceRef.update(updateData);
        final updatedInstance =
            await getUpdatedInstance(instanceId: instanceId, userId: uid);

        // 7. Reconcile with actual data
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);

        // For habits, generate next instance immediately using window system
        if (instance.templateCategoryType == 'habit') {
          await _generateNextHabitInstance(instance, uid);
        } else {
          // For tasks, use the existing recurring logic
          final templateRef =
              ActivityRecord.collectionForUser(uid).doc(instance.templateId);
          final templateDoc = await templateRef.get();
          if (templateDoc.exists) {
            final template = ActivityRecord.fromSnapshot(templateDoc);
            // Generate next instance if template is recurring and still active
            if (template.isRecurring && template.isActive) {
              final nextDueDate = RecurrenceCalculator.calculateNextDueDate(
                currentDueDate: instance.dueDate!,
                template: template,
              );
              if (nextDueDate != null) {
                final newInstanceRef = await createActivityInstance(
                  templateId: instance.templateId,
                  dueDate: nextDueDate,
                  dueTime: template.dueTime,
                  template: template,
                  userId: uid,
                );
                // Broadcast the instance creation event for UI update
                try {
                  final newInstance = await getUpdatedInstance(
                    instanceId: newInstanceRef.id,
                    userId: uid,
                  );
                  InstanceEvents.broadcastInstanceCreated(newInstance);
                } catch (e) {
                  // Log error but don't fail - event broadcasting is non-critical
                  print('Error broadcasting instance created event: $e');
                }
              }
            } else if (!template.isRecurring) {
              // For one-time tasks, mark template as inactive and complete
              await templateRef.update({
                'isActive': false,
                'status': 'complete',
                'lastUpdated': now,
              });
            }
          }
        }
        // Cancel reminder for completed instance
        try {
          await ReminderScheduler.cancelReminderForInstance(instanceId);
        } catch (e) {
          // Log error but don't fail - reminder cancellation is non-critical
          print('Error canceling reminder for completed instance: $e');
        }
      } catch (e) {
        // 8. Rollback on error
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Uncomplete an activity instance (mark as pending)
  static Future<void> uncompleteInstance({
    required String instanceId,
    String? userId,
    bool deleteLogs = false, // New parameter to optionally delete calendar logs
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }

      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

      // For habits, delete any pending future instances that were auto-generated
      if (instance.templateCategoryType == 'habit') {
        try {
          final futureInstancesQuery =
              ActivityInstanceRecord.collectionForUser(uid)
                  .where('templateId', isEqualTo: instance.templateId)
                  .where('status', isEqualTo: 'pending')
                  .where('belongsToDate',
                      isGreaterThan: instance.belongsToDate);

          final futureInstances = await futureInstancesQuery.get();
          for (final doc in futureInstances.docs) {
            // IMPORTANT: uncompleting a habit can delete auto-generated future
            // pending instances. Broadcast deletions so any mounted screens
            // can remove stale references and avoid writing to deleted docs.
            final deletedInstance = ActivityInstanceRecord.fromSnapshot(doc);
            await doc.reference.delete();
            InstanceEvents.broadcastInstanceDeleted(deletedInstance);
          }
        } catch (e) {
          print('❌ MISSING INDEX: uncompleteInstance needs Index 1');
          print(
              'Required Index: templateId (ASC) + status (ASC) + belongsToDate (ASC) + dueDate (ASC)');
          print('Collection: activity_instances');
          print('Full error: $e');
          if (e.toString().contains('index') ||
              e.toString().contains('https://')) {
            print(
                '📋 Look for the Firestore index creation link in the error message above!');
            print('   Click the link to create the index automatically.');
          }
          rethrow;
        }
      }

      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Create optimistic instance
      final optimisticInstance =
          InstanceEvents.createOptimisticUncompletedInstance(instance);

      // 2. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      // 3. Track operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'uncomplete',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );

      // 4. Broadcast optimistically (IMMEDIATE)
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);

      final updateData = <String, dynamic>{
        'status': 'pending',
        'completedAt': null,
        'skippedAt': null, // Add this to also clear skippedAt
        'lastUpdated': DateService.currentDate,
      };

      // If deleteLogs is true, clear all calendar logs and reset time-related fields
      if (deleteLogs) {
        updateData['timeLogSessions'] = [];
        updateData['totalTimeLogged'] = 0;
        updateData['accumulatedTime'] = 0;
        updateData['currentValue'] = 0;
      }

      // 5. Perform backend update
      try {
        await instanceRef.update(updateData);

        // For one-time tasks, reactivate the template if it was marked inactive
        if (instance.templateCategoryType == 'task') {
          final templateRef =
              ActivityRecord.collectionForUser(uid).doc(instance.templateId);
          final templateDoc = await templateRef.get();
          if (templateDoc.exists) {
            final template = ActivityRecord.fromSnapshot(templateDoc);
            // Reactivate one-time task templates
            if (!template.isRecurring && !template.isActive) {
              await templateRef.update({
                'isActive': true,
                'status': 'incomplete',
                'lastUpdated': DateService.currentDate,
              });
            }
          }
        }

        // 6. Reconcile with actual data
        final updatedInstance =
            await getUpdatedInstance(instanceId: instanceId, userId: uid);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
      } catch (e) {
        // 7. Rollback on error
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  // ==================== INSTANCE PROGRESS ====================
  /// Update instance progress (for quantitative tracking)
  static Future<void> updateInstanceProgress({
    required String instanceId,
    required dynamic currentValue,
    String? userId,
    DateTime? referenceTime,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateService.currentDate;
      final effectiveReferenceTime = referenceTime ?? now;

      // For windowed habits, update lastDayValue to current value for next day's calculation
      final updateData = <String, dynamic>{
        'currentValue': currentValue,
        'lastUpdated': now,
      };

      // Handle quantitative incremental time estimates
      if (instance.templateTrackingType == 'quantitative' &&
          instance.templateTarget != null) {
        // Load template to check for per-activity estimate
        ActivityRecord? template;
        if (instance.hasTemplateId()) {
          try {
            final templateRef =
                ActivityRecord.collectionForUser(uid).doc(instance.templateId);
            final templateDoc = await templateRef.get();
            if (templateDoc.exists) {
              template = ActivityRecord.fromSnapshot(templateDoc);
            }
          } catch (e) {
            // Continue without template
          }
        }

        // Refresh instance to get latest state (including sessions from concurrent updates)
        // This must happen BEFORE calculating delta to ensure we use the latest value
        final latestInstanceDoc = await instanceRef.get();
        final latestInstance = latestInstanceDoc.exists
            ? ActivityInstanceRecord.fromSnapshot(latestInstanceDoc)
            : instance;

        // Calculate delta using the refreshed instance's current value
        // This ensures correct delta calculation even when batches overlap
        final oldValue = latestInstance.currentValue;
        final oldValueNum = oldValue is num ? oldValue.toDouble() : 0.0;
        final newValueNum = currentValue is num ? currentValue.toDouble() : 0.0;
        final delta = newValueNum - oldValueNum;

        // Only create time blocks if there's an actual increment (delta > 0)
        if (delta > 0) {
          // Resolve effective estimate using latest instance state
          // Always pass hasExplicitSessions=false for quantitative increments
          // to allow creating estimate-based blocks for each increment
          final effectiveEstimateMinutes =
              await TimeEstimateResolver.getEffectiveEstimateMinutes(
            userId: uid,
            trackingType: latestInstance.templateTrackingType,
            target: latestInstance.templateTarget,
            hasExplicitSessions:
                false, // Always allow estimate-based blocks for quantitative increments
            template: template,
          );

          if (effectiveEstimateMinutes != null) {
            // Calculate per-unit time: estimateMinutes / targetQty
            final targetQty = latestInstance.templateTarget is num
                ? (latestInstance.templateTarget as num).toDouble()
                : 1.0;
            if (targetQty > 0) {
              final perUnitMinutes =
                  (effectiveEstimateMinutes / targetQty).clamp(1.0, 600.0);
              final perUnitMs = (perUnitMinutes * 60000).toInt();

              final existingSessions = List<Map<String, dynamic>>.from(
                  latestInstance.timeLogSessions);

              // Create one time block per increment
              final newSessions = <Map<String, dynamic>>[];
              DateTime currentEndTime =
                  effectiveReferenceTime; // Start from the desired reference time

              // Loop through each increment to create separate time blocks
              for (int i = 0; i < delta.toInt(); i++) {
                DateTime sessionStartTime;

                DateTime sessionEndTime;
                if (i == 0) {
                  // First block: use calculateStackedStartTime to account for simultaneous items
                  final stackedTimes = await calculateStackedStartTime(
                    userId: uid,
                    completionTime: currentEndTime,
                    durationMs: perUnitMs,
                    instanceId: instanceId,
                    effectiveEstimateMinutes: effectiveEstimateMinutes.toInt(),
                  );
                  sessionStartTime = stackedTimes.startTime;
                  sessionEndTime = stackedTimes.endTime;
                } else {
                  // Subsequent blocks: stack directly before the previous block
                  sessionStartTime = currentEndTime
                      .subtract(Duration(milliseconds: perUnitMs));
                  sessionEndTime = currentEndTime;
                }

                final newSession = {
                  'startTime': sessionStartTime,
                  'endTime': sessionEndTime,
                  'durationMilliseconds': perUnitMs,
                };

                newSessions.add(newSession);
                currentEndTime =
                    sessionStartTime; // Next block ends where this one starts
              }

              // Add all new sessions to existing sessions
              existingSessions.addAll(newSessions);

              final totalTime = existingSessions.fold<int>(
                0,
                (sum, session) =>
                    sum + (session['durationMilliseconds'] as int? ?? 0),
              );

              updateData['timeLogSessions'] = existingSessions;
              updateData['totalTimeLogged'] = totalTime;
            }
          }
        }
      }

      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Create optimistic instance
      final optimisticInstance =
          InstanceEvents.createOptimisticProgressInstance(
        instance,
        currentValue: currentValue,
      );

      // 2. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      // 3. Track operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'progress',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );

      // 4. Broadcast optimistically (IMMEDIATE)
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);

      // Note: lastDayValue should be updated at day-end, not during progress updates
      // This allows differential progress calculation to work correctly

      // 5. Perform backend update
      try {
        await instanceRef.update(updateData);

        // Check if target is reached and auto-complete/uncomplete
        if (instance.templateTrackingType == 'quantitative' &&
            instance.templateTarget != null) {
          final target = instance.templateTarget as num;
          final progress = currentValue is num ? currentValue : 0;
          if (progress >= target) {
            // Auto-complete if not already completed
            if (instance.status != 'completed') {
              // completeInstance will handle its own optimistic broadcast
              await completeInstanceWithBackdate(
                instanceId: instanceId,
                finalValue: currentValue,
                userId: uid,
                completedAt: referenceTime,
              );
              // Reconcile this progress operation (completeInstance will reconcile its own)
              OptimisticOperationTracker.reconcileOperation(
                  operationId,
                  await getUpdatedInstance(
                      instanceId: instanceId, userId: uid));
            } else {
              // Already completed, just reconcile the progress update
              final updatedInstance =
                  await getUpdatedInstance(instanceId: instanceId, userId: uid);
              OptimisticOperationTracker.reconcileOperation(
                  operationId, updatedInstance);
            }
          } else {
            // Auto-uncomplete if currently completed OR skipped and progress dropped below target
            if (instance.status == 'completed' ||
                instance.status == 'skipped') {
              // uncompleteInstance will handle its own optimistic broadcast
              await uncompleteInstance(
                instanceId: instanceId,
                userId: uid,
              );
              // Reconcile this progress operation (uncompleteInstance will reconcile its own)
              OptimisticOperationTracker.reconcileOperation(
                  operationId,
                  await getUpdatedInstance(
                      instanceId: instanceId, userId: uid));
            } else {
              // Not completed, just reconcile progress update
              final updatedInstance =
                  await getUpdatedInstance(instanceId: instanceId, userId: uid);
              OptimisticOperationTracker.reconcileOperation(
                  operationId, updatedInstance);
            }
          }
        } else {
          // Reconcile the instance update event for progress changes
          final updatedInstance =
              await getUpdatedInstance(instanceId: instanceId, userId: uid);
          OptimisticOperationTracker.reconcileOperation(
              operationId, updatedInstance);
        }
      } catch (e) {
        // 6. Rollback on error
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Snooze an instance until a specific date
  static Future<void> snoozeInstance({
    required String instanceId,
    required DateTime snoozeUntil,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      // Validate snooze date is not beyond window end
      if (instance.windowEndDate != null &&
          snoozeUntil.isAfter(instance.windowEndDate!)) {
        throw Exception('Cannot snooze beyond window end date');
      }

      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Create optimistic instance
      final optimisticInstance = InstanceEvents.createOptimisticSnoozedInstance(
        instance,
        snoozedUntil: snoozeUntil,
      );

      // 2. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      // 3. Track operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'snooze',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );

      // 4. Broadcast optimistically (IMMEDIATE)
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);

      // 5. Perform backend update
      try {
        await instanceRef.update({
          'snoozedUntil': snoozeUntil,
          'lastUpdated': DateService.currentDate,
        });
        // Cancel reminder for snoozed instance
        try {
          await ReminderScheduler.cancelReminderForInstance(instanceId);
        } catch (e) {
          // Log error but don't fail - reminder cancellation is non-critical
          print('Error canceling reminder for snoozed instance: $e');
        }
        // 6. Reconcile with actual data
        final updatedInstance =
            await getUpdatedInstance(instanceId: instanceId, userId: uid);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
      } catch (e) {
        // 7. Rollback on error
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Unsnooze an instance (remove snooze)
  static Future<void> unsnoozeInstance({
    required String instanceId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Create optimistic instance
      final optimisticInstance =
          InstanceEvents.createOptimisticUnsnoozedInstance(instance);

      // 2. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      // 3. Track operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'unsnooze',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );

      // 4. Broadcast optimistically (IMMEDIATE)
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);

      // 5. Perform backend update
      try {
        await instanceRef.update({
          'snoozedUntil': null,
          'lastUpdated': DateService.currentDate,
        });
        // Reschedule reminder for unsnoozed instance
        try {
          final updatedInstance =
              await getUpdatedInstance(instanceId: instanceId, userId: uid);
          await ReminderScheduler.rescheduleReminderForInstance(
              updatedInstance);
        } catch (e) {
          // Log error but don't fail - reminder rescheduling is non-critical
          print('Error rescheduling reminder for unsnoozed instance: $e');
        }
        // 6. Reconcile with actual data
        final updatedInstance =
            await getUpdatedInstance(instanceId: instanceId, userId: uid);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
      } catch (e) {
        // 7. Rollback on error
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Update instance timer state
  static Future<void> updateInstanceTimer({
    required String instanceId,
    required bool isActive,
    DateTime? startTime,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Create optimistic instance
      final optimisticInstance =
          InstanceEvents.createOptimisticProgressInstance(
        instance,
        isTimerActive: isActive,
        timerStartTime:
            startTime ?? (isActive ? DateService.currentDate : null),
      );

      // 2. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      // 3. Track operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'progress',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );

      // 4. Broadcast optimistically (IMMEDIATE)
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);

      // 5. Perform backend update
      try {
        await instanceRef.update({
          'isTimerActive': isActive,
          'timerStartTime':
              startTime ?? (isActive ? DateService.currentDate : null),
          'lastUpdated': DateService.currentDate,
        });

        // 6. Reconcile with actual data
        final updatedInstance =
            await getUpdatedInstance(instanceId: instanceId, userId: uid);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
      } catch (e) {
        // 7. Rollback on error
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Toggle timer for time tracking using session-based logic
  static Future<void> toggleInstanceTimer({
    required String instanceId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateService.currentDate;

      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      ActivityInstanceRecord optimisticInstance;

      if (instance.isTimeLogging && instance.currentSessionStartTime != null) {
        // Stop timer - create session and add to timeLogSessions
        final elapsed =
            now.difference(instance.currentSessionStartTime!).inMilliseconds;
        // Create new session
        final newSession = {
          'startTime': instance.currentSessionStartTime!,
          'endTime': now,
          'durationMilliseconds': elapsed,
        };
        // Get existing sessions and add new one
        final existingSessions =
            List<Map<String, dynamic>>.from(instance.timeLogSessions);
        existingSessions.add(newSession);
        // Calculate total cumulative time
        final totalTime = existingSessions.fold<int>(0,
            (sum, session) => sum + (session['durationMilliseconds'] as int));

        // Calculate new currentValue based on tracking type
        // Only update currentValue with time for time-based tracking
        // For quantitative/binary, preserve the existing quantity/counter
        dynamic newCurrentValue;
        if (instance.templateTrackingType == 'time') {
          newCurrentValue = totalTime;
        } else {
          // Preserve existing quantity/counter for quantitative/binary tracking
          newCurrentValue = instance.currentValue;
        }

        // 2. Create optimistic instance for stopping timer
        final updateData = <String, dynamic>{
          'isTimerActive': false, // Legacy field
          'timerStartTime': null, // Legacy field
          'isTimeLogging': false, // Session field
          'currentSessionStartTime': null, // Session field
          'timeLogSessions': existingSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime, // Keep legacy field updated
          'currentValue':
              newCurrentValue, // Only update for time tracking, preserve for quantitative/binary
        };
        // For windowed habits, update lastDayValue to track differential progress
        if (instance.templateCategoryType == 'habit' &&
            instance.windowDuration > 1) {
          updateData['lastDayValue'] = totalTime;
        }
        optimisticInstance =
            InstanceEvents.createOptimisticPropertyUpdateInstance(
          instance,
          updateData,
        );

        // 3. Track operation
        OptimisticOperationTracker.trackOperation(
          operationId,
          instanceId: instanceId,
          operationType: 'progress',
          optimisticInstance: optimisticInstance,
          originalInstance: instance,
        );

        // 4. Broadcast optimistically (IMMEDIATE)
        InstanceEvents.broadcastInstanceUpdatedOptimistic(
            optimisticInstance, operationId);

        // 5. Perform backend update
        try {
          // Add lastUpdated for backend update
          updateData['lastUpdated'] = now;
          await instanceRef.update(updateData);

          // 6. Reconcile with actual data
          final updatedInstance =
              await getUpdatedInstance(instanceId: instanceId, userId: uid);
          OptimisticOperationTracker.reconcileOperation(
              operationId, updatedInstance);
        } catch (e) {
          // 7. Rollback on error
          OptimisticOperationTracker.rollbackOperation(operationId);
          rethrow;
        }
      } else {
        // Start timer - set session tracking fields
        // 2. Create optimistic instance for starting timer
        optimisticInstance = InstanceEvents.createOptimisticProgressInstance(
          instance,
          isTimerActive: true,
          timerStartTime: now,
        );

        // 3. Track operation
        OptimisticOperationTracker.trackOperation(
          operationId,
          instanceId: instanceId,
          operationType: 'progress',
          optimisticInstance: optimisticInstance,
          originalInstance: instance,
        );

        // 4. Broadcast optimistically (IMMEDIATE)
        InstanceEvents.broadcastInstanceUpdatedOptimistic(
            optimisticInstance, operationId);

        // 5. Perform backend update
        try {
          await instanceRef.update({
            'isTimerActive': true, // Legacy field
            'timerStartTime': now, // Legacy field
            'isTimeLogging': true, // Session field
            'currentSessionStartTime': now, // Session field
            'lastUpdated': now,
          });

          // 6. Reconcile with actual data
          final updatedInstance =
              await getUpdatedInstance(instanceId: instanceId, userId: uid);
          OptimisticOperationTracker.reconcileOperation(
              operationId, updatedInstance);
        } catch (e) {
          // 7. Rollback on error
          OptimisticOperationTracker.rollbackOperation(operationId);
          rethrow;
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  // ==================== INSTANCE SCHEDULING ====================
  /// Skip current instance and generate next if recurring
  static Future<void> skipInstance({
    required String instanceId,
    String? notes,
    String? userId,
    DateTime? skippedAt, // Optional backdated skip time
    bool skipAutoGeneration =
        false, // NEW: Prevent automatic next instance creation
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateService.currentDate;
      final skipTime = skippedAt ?? now;

      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Create optimistic instance
      final optimisticInstance = InstanceEvents.createOptimisticSkippedInstance(
        instance,
        notes: notes,
      );

      // 2. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      // 3. Track operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'skip',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );

      // 4. Broadcast optimistically (IMMEDIATE)
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);

      // 5. Perform backend update
      try {
        await instanceRef.update({
          'status': 'skipped',
          'skippedAt': skipTime,
          'notes': notes ?? instance.notes,
          'lastUpdated': now,
        });
        // Only generate next instance if skipAutoGeneration is false
        if (!skipAutoGeneration) {
          // For habits, generate next instance immediately using window system
          if (instance.templateCategoryType == 'habit') {
            await _generateNextHabitInstance(instance, uid);
          } else {
            // For tasks, use the existing recurring logic
            final templateRef =
                ActivityRecord.collectionForUser(uid).doc(instance.templateId);
            final templateDoc = await templateRef.get();
            if (templateDoc.exists) {
              final template = ActivityRecord.fromSnapshot(templateDoc);
              // Generate next instance if template is recurring and still active
              if (template.isRecurring && template.isActive) {
                final nextDueDate = RecurrenceCalculator.calculateNextDueDate(
                  currentDueDate: instance.dueDate!,
                  template: template,
                );
                if (nextDueDate != null) {
                  final newInstanceRef = await createActivityInstance(
                    templateId: instance.templateId,
                    dueDate: nextDueDate,
                    dueTime: template.dueTime,
                    template: template,
                    userId: uid,
                  );
                  // Broadcast the instance creation event for UI update
                  try {
                    final newInstance = await getUpdatedInstance(
                      instanceId: newInstanceRef.id,
                      userId: uid,
                    );
                    InstanceEvents.broadcastInstanceCreated(newInstance);
                  } catch (e) {
                    // Log error but don't fail - event broadcasting is non-critical
                    print('Error broadcasting instance created event: $e');
                  }
                }
              } else if (!template.isRecurring) {
                // For one-time tasks, mark template as inactive and skipped
                await templateRef.update({
                  'isActive': false,
                  'status': 'skipped',
                  'lastUpdated': now,
                });
              }
            }
          }
        }
        // Cancel reminder for skipped instance
        try {
          await ReminderScheduler.cancelReminderForInstance(instanceId);
        } catch (e) {
          // Log error but don't fail - reminder cancellation is non-critical
          print('Error canceling reminder for skipped instance: $e');
        }

        // 6. Reconcile with actual data
        final updatedInstance =
            await getUpdatedInstance(instanceId: instanceId, userId: uid);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
      } catch (e) {
        // 7. Rollback on error
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Efficiently skip expired instances using batch writes
  /// Always skips expired instances up to day before yesterday
  /// Creates yesterday instance as PENDING if it exists, otherwise creates next valid instance
  static Future<DocumentReference?> bulkSkipExpiredInstancesWithBatches({
    required ActivityInstanceRecord oldestInstance,
    required ActivityRecord template,
    required String userId,
  }) async {
    try {
      final yesterday = DateService.yesterdayStart;
      final now = DateService.currentDate;

      // Step 1: Always skip the oldest expired instance
      await skipInstance(
        instanceId: oldestInstance.reference.id,
        skippedAt: oldestInstance.windowEndDate ?? oldestInstance.dueDate,
        skipAutoGeneration: true,
        userId: userId,
      );

      // Step 2: Generate all due dates from oldestInstance forward
      final List<DateTime> allDueDates = [];
      DateTime currentDueDate = oldestInstance.dueDate ?? DateTime.now();

      // Generate due dates until we pass yesterday
      while (currentDueDate.isBefore(yesterday.add(const Duration(days: 30)))) {
        allDueDates.add(currentDueDate);
        final nextDate = RecurrenceCalculator.calculateNextDueDate(
          currentDueDate: currentDueDate,
          template: template,
        );
        if (nextDate == null) break;
        currentDueDate = nextDate;
      }

      // Step 3: Find instances to skip (windows end BEFORE yesterday)
      // and find yesterday's instance (window ends EXACTLY on yesterday)
      List<int> instancesToSkipIndices = [];
      int yesterdayInstanceIndex = -1;
      int nextValidInstanceIndex = -1;

      for (int i = 0; i < allDueDates.length; i++) {
        final dueDate = allDueDates[i];
        final windowDuration = await _calculateAdaptiveWindowDuration(
          template: template,
          userId: userId,
          currentDate: dueDate,
        );

        if (windowDuration == 0) continue;

        final windowEnd = dueDate.add(Duration(days: windowDuration - 1));
        final windowEndNormalized = DateTime(
          windowEnd.year,
          windowEnd.month,
          windowEnd.day,
        );

        // Collect instances whose windows end BEFORE yesterday (to skip)
        if (windowEndNormalized.isBefore(yesterday)) {
          instancesToSkipIndices.add(i);
        }
        // Find yesterday instance (window ends exactly on yesterday)
        else if (windowEndNormalized.isAtSameMomentAs(yesterday)) {
          yesterdayInstanceIndex = i;
          // Continue to find next valid instance in case yesterday doesn't exist
        }
        // Find first instance after yesterday (for fallback)
        else if (windowEndNormalized.isAfter(yesterday) &&
            nextValidInstanceIndex == -1) {
          nextValidInstanceIndex = i;
          break; // Stop once we find the first future instance
        }
      }

      // Step 4: Batch create and skip all instances whose windows ended before yesterday
      if (instancesToSkipIndices.isNotEmpty) {
        final firestore = FirebaseFirestore.instance;
        const batchSize = 250;

        for (int batchStart = 0;
            batchStart < instancesToSkipIndices.length;
            batchStart += batchSize) {
          final batch = firestore.batch();
          final end = (batchStart + batchSize < instancesToSkipIndices.length)
              ? batchStart + batchSize
              : instancesToSkipIndices.length;

          for (int j = batchStart; j < end; j++) {
            final index = instancesToSkipIndices[j];
            final dueDate = allDueDates[index];
            final windowDuration = await _calculateAdaptiveWindowDuration(
              template: template,
              userId: userId,
              currentDate: dueDate,
            );

            if (windowDuration == 0) continue;

            final windowEndDate =
                dueDate.add(Duration(days: windowDuration - 1));
            final normalizedDate = DateTime(
              dueDate.year,
              dueDate.month,
              dueDate.day,
            );

            final instanceData = createActivityInstanceRecordData(
              templateId: template.reference.id,
              dueDate: dueDate,
              dueTime: template.dueTime,
              status: 'skipped',
              skippedAt: windowEndDate,
              createdTime: now,
              lastUpdated: now,
              isActive: true,
              lastDayValue: 0,
              belongsToDate: normalizedDate,
              windowEndDate: windowEndDate,
              windowDuration: windowDuration,
              templateName: template.name,
              templateCategoryId: template.categoryId,
              templateCategoryName: template.categoryName,
              templateCategoryType: template.categoryType,
              templatePriority: template.priority,
              templateTrackingType: template.trackingType,
              templateTarget: template.target,
              templateUnit: template.unit,
              templateDescription: template.description,
              templateTimeEstimateMinutes: template.timeEstimateMinutes,
              templateShowInFloatingTimer: template.showInFloatingTimer,
              templateIsRecurring: template.isRecurring,
              templateEveryXValue: template.everyXValue,
              templateEveryXPeriodType: template.everyXPeriodType,
              templateTimesPerPeriod: template.timesPerPeriod,
              templatePeriodType: template.periodType,
            );

            final newDocRef =
                ActivityInstanceRecord.collectionForUser(userId).doc();
            batch.set(newDocRef, instanceData);
          }

          await batch.commit();
        }
      }

      // Step 5: Create pending instance (yesterday if exists, otherwise next valid)
      DocumentReference? pendingInstanceRef;
      if (yesterdayInstanceIndex >= 0) {
        // Create yesterday instance as PENDING
        final yesterdayDueDate = allDueDates[yesterdayInstanceIndex];
        pendingInstanceRef = await createActivityInstance(
          templateId: template.reference.id,
          dueDate: yesterdayDueDate,
          template: template,
          userId: userId,
        );
      } else if (nextValidInstanceIndex >= 0) {
        // No yesterday instance, create next valid instance as PENDING
        final nextDueDate = allDueDates[nextValidInstanceIndex];
        pendingInstanceRef = await createActivityInstance(
          templateId: template.reference.id,
          dueDate: nextDueDate,
          template: template,
          userId: userId,
        );
      } else {
        // Fallback: generate next instance normally
        pendingInstanceRef = await createActivityInstance(
          templateId: template.reference.id,
          template: template,
          userId: userId,
        );
      }

      return pendingInstanceRef;
    } catch (e) {
      rethrow;
    }
  }

  /// Reschedule instance to a new due date
  static Future<void> rescheduleInstance({
    required String instanceId,
    required DateTime newDueDate,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Create optimistic instance
      final optimisticInstance =
          InstanceEvents.createOptimisticRescheduledInstance(
        instance,
        newDueDate: newDueDate,
      );

      // 2. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      // 3. Track operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'reschedule',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );

      // 4. Broadcast optimistically (IMMEDIATE)
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);

      // 5. Perform backend update
      try {
        await instanceRef.update({
          'dueDate': newDueDate,
          'lastUpdated': DateService.currentDate,
        });
        // Reschedule reminder for rescheduled instance
        try {
          final updatedInstance =
              await getUpdatedInstance(instanceId: instanceId, userId: uid);
          await ReminderScheduler.rescheduleReminderForInstance(
              updatedInstance);
        } catch (e) {
          // Log error but don't fail - reminder rescheduling is non-critical
          print('Error rescheduling reminder for rescheduled instance: $e');
        }
        // 6. Reconcile with actual data
        final updatedInstance =
            await getUpdatedInstance(instanceId: instanceId, userId: uid);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
      } catch (e) {
        // 7. Rollback on error
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Remove due date from an activity instance
  static Future<void> removeDueDateFromInstance({
    required String instanceId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Create optimistic instance
      final optimisticInstance =
          InstanceEvents.createOptimisticPropertyUpdateInstance(
        instance,
        {'dueDate': null},
      );

      // 2. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      // 3. Track operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'progress',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );

      // 4. Broadcast optimistically (IMMEDIATE)
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);

      // 5. Perform backend update
      try {
        await instanceRef.update({
          'dueDate': null,
          'lastUpdated': DateService.currentDate,
        });

        // 6. Reconcile with actual data
        final updatedInstance =
            await getUpdatedInstance(instanceId: instanceId, userId: uid);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
      } catch (e) {
        // 7. Rollback on error
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Skip all instances until a specific date
  static Future<void> skipInstancesUntil({
    required String templateId,
    required DateTime untilDate,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      // Get the template to understand the recurrence pattern
      final templateRef = ActivityRecord.collectionForUser(uid).doc(templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) {
        throw Exception('Template not found');
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);
      final now = DateService.currentDate;
      // Get the oldest pending instance to start from
      final oldestQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId)
          .where('status', isEqualTo: 'pending')
          .orderBy('dueDate', descending: false)
          .limit(1);
      final oldestInstances = await oldestQuery.get().catchError((e) {
        print('❌ MISSING INDEX: skipUntilDate oldestQuery needs Index 1');
        print(
            'Required Index: templateId (ASC) + status (ASC) + belongsToDate (ASC) + dueDate (ASC)');
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
      if (oldestInstances.docs.isEmpty) {
        return;
      }
      final oldestInstance =
          ActivityInstanceRecord.fromSnapshot(oldestInstances.docs.first);
      DateTime currentDueDate = oldestInstance.dueDate!;
      // Step 1: Create and mark all interim instances as skipped
      // This maintains the recurrence pattern by creating instances at the correct intervals
      while (currentDueDate.isBefore(untilDate)) {
        // Check if instance already exists
        try {
          final existingQuery = ActivityInstanceRecord.collectionForUser(uid)
              .where('templateId', isEqualTo: templateId)
              .where('status', isEqualTo: 'pending')
              .where('dueDate', isEqualTo: currentDueDate);
          final existingInstances = await existingQuery.get();
          if (existingInstances.docs.isNotEmpty) {
            // Instance already exists, just mark as skipped
            final existingInstance = existingInstances.docs.first;
            await existingInstance.reference.update({
              'status': 'skipped',
              'skippedAt': now,
              'lastUpdated': now,
            });
          } else {
            // Create new instance and mark as skipped
            await createActivityInstance(
              templateId: templateId,
              dueDate: currentDueDate,
              dueTime: template.dueTime,
              template: template,
              userId: uid,
            );
            // Mark the newly created instance as skipped
            final newInstanceQuery =
                ActivityInstanceRecord.collectionForUser(uid)
                    .where('templateId', isEqualTo: templateId)
                    .where('status', isEqualTo: 'pending')
                    .where('dueDate', isEqualTo: currentDueDate);
            final newInstances = await newInstanceQuery.get();
            if (newInstances.docs.isNotEmpty) {
              await newInstances.docs.first.reference.update({
                'status': 'skipped',
                'skippedAt': now,
                'lastUpdated': now,
              });
            }
          }
        } catch (e) {
          print(
              '❌ MISSING INDEX: skipUntilDate existingQuery/newInstanceQuery needs Index 1');
          print(
              'Required Index: templateId (ASC) + status (ASC) + belongsToDate (ASC) + dueDate (ASC)');
          print('Collection: activity_instances');
          print('Full error: $e');
          if (e.toString().contains('index') ||
              e.toString().contains('https://')) {
            print(
                '📋 Look for the Firestore index creation link in the error message above!');
            print('   Click the link to create the index automatically.');
          }
          rethrow;
        }
        // Calculate next due date based on recurrence pattern
        final nextDueDate = RecurrenceCalculator.calculateNextDueDate(
          currentDueDate: currentDueDate,
          template: template,
        );
        if (nextDueDate == null) {
          break;
        }
        currentDueDate = nextDueDate;
      }
      // Step 2: Ensure there's a properly-scheduled instance after untilDate
      // This respects the original recurrence pattern, not the untilDate
      try {
        final futureQuery = ActivityInstanceRecord.collectionForUser(uid)
            .where('templateId', isEqualTo: templateId)
            .where('status', isEqualTo: 'pending')
            .where('dueDate', isGreaterThanOrEqualTo: untilDate);
        final futureInstances = await futureQuery.get();
        if (futureInstances.docs.isEmpty) {
          // Create the next properly-scheduled instance
          // Use the last calculated due date (which respects the pattern)
          if (currentDueDate.isAtSameMomentAs(untilDate) ||
              currentDueDate.isAfter(untilDate)) {
            // The last calculated date is already at or after untilDate, use it
            await createActivityInstance(
              templateId: templateId,
              dueDate: currentDueDate,
              dueTime: template.dueTime,
              template: template,
              userId: uid,
            );
          } else {
            // Need to calculate one more step to get past untilDate
            final nextProperDate = RecurrenceCalculator.calculateNextDueDate(
              currentDueDate: currentDueDate,
              template: template,
            );
            if (nextProperDate != null) {
              await createActivityInstance(
                templateId: templateId,
                dueDate: nextProperDate,
                dueTime: template.dueTime,
                template: template,
                userId: uid,
              );
            }
          }
        }
      } catch (e) {
        print('❌ MISSING INDEX: skipUntilDate futureQuery needs Index 1');
        print(
            'Required Index: templateId (ASC) + status (ASC) + belongsToDate (ASC) + dueDate (ASC)');
        print('Collection: activity_instances');
        print('Full error: $e');
        if (e.toString().contains('index') ||
            e.toString().contains('https://')) {
          print(
              '📋 Look for the Firestore index creation link in the error message above!');
          print('   Click the link to create the index automatically.');
        }
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  // ==================== HELPER METHODS ====================
  /// Get period start date
  static DateTime _getPeriodStart(DateTime date, String periodType) {
    switch (periodType) {
      case 'weeks':
        final daysSinceSunday = date.weekday % 7;
        return DateTime(date.year, date.month, date.day - daysSinceSunday);
      case 'months':
        return DateTime(date.year, date.month, 1);
      case 'year':
        return DateTime(date.year, 1, 1);
      default:
        return DateTime(date.year, date.month, date.day);
    }
  }

  /// Get period end date
  static DateTime _getPeriodEnd(DateTime date, String periodType) {
    switch (periodType) {
      case 'weeks':
        final periodStart = _getPeriodStart(date, periodType);
        return periodStart.add(const Duration(days: 6));
      case 'months':
        return DateTime(date.year, date.month + 1, 0);
      case 'year':
        return DateTime(date.year, 12, 31);
      default:
        return date;
    }
  }

  /// Calculate days remaining in current period
  static int _getDaysRemainingInPeriod(
      DateTime currentDate, String periodType) {
    final periodEnd = _getPeriodEnd(currentDate, periodType);
    final today =
        DateTime(currentDate.year, currentDate.month, currentDate.day);
    final endDate = DateTime(periodEnd.year, periodEnd.month, periodEnd.day);
    return endDate.difference(today).inDays + 1; // +1 to include today
  }

  /// Calculate days elapsed in current period
  static int _getDaysElapsedInPeriod(DateTime currentDate, String periodType) {
    final periodStart = _getPeriodStart(currentDate, periodType);
    final today =
        DateTime(currentDate.year, currentDate.month, currentDate.day);
    final startDate =
        DateTime(periodStart.year, periodStart.month, periodStart.day);
    return today.difference(startDate).inDays + 1; // +1 to include today
  }

  /// Get total days in a period
  static int _getPeriodDays(String periodType) {
    switch (periodType) {
      case 'weeks':
        return 7;
      case 'months':
        return 30; // Approximate
      case 'year':
        return 365; // Approximate
      default:
        return 1;
    }
  }

  /// Get completed count in current period (includes bonus completions)
  static Future<int> _getCompletedCountInPeriod({
    required String templateId,
    required String userId,
    required ActivityRecord template,
    required DateTime currentDate,
  }) async {
    if (template.frequencyType != 'timesPerPeriod') {
      return 0;
    }
    final periodStart = _getPeriodStart(currentDate, template.periodType);
    final periodEnd = _getPeriodEnd(currentDate, template.periodType);
    // Query all instances for this template in the current period
    final instances = await ActivityInstanceRecord.collectionForUser(userId)
        .where('templateId', isEqualTo: templateId)
        .where('belongsToDate', isGreaterThanOrEqualTo: periodStart)
        .where('belongsToDate', isLessThanOrEqualTo: periodEnd)
        .get();
    // For binary habits, sum up currentValue (counter) from all instances
    // This includes bonus completions from "+" button
    int completedCount = 0;
    for (final doc in instances.docs) {
      final instance = ActivityInstanceRecord.fromSnapshot(doc);
      if (instance.templateTrackingType == 'binary') {
        // Use currentValue as counter (includes bonus completions)
        final count = instance.currentValue ?? 0;
        completedCount += (count is num ? count.toInt() : 0);
        // Also count if marked as completed but no counter (backward compatibility)
        if (count == 0 && instance.status == 'completed') {
          completedCount += 1;
        }
      } else {
        // Non-binary habits: just count completed instances
        if (instance.status == 'completed') {
          completedCount += 1;
        }
      }
    }
    return completedCount;
  }

  /// Calculate adaptive window duration for a habit based on its frequency
  static Future<int> _calculateAdaptiveWindowDuration({
    required ActivityRecord template,
    required String userId,
    required DateTime currentDate,
  }) async {
    switch (template.frequencyType) {
      case 'everyXPeriod':
        // Keep existing logic - no changes needed
        final everyXValue = template.everyXValue;
        final periodType = template.everyXPeriodType;
        switch (periodType) {
          case 'days':
            return everyXValue;
          case 'weeks':
            return everyXValue * 7;
          case 'months':
            return everyXValue * 30;
          case 'year':
            return everyXValue * 365;
          default:
            return 1;
        }
      case 'timesPerPeriod':
        // NEW: Rate-based adaptive window calculation
        final completedCount = await _getCompletedCountInPeriod(
          templateId: template.reference.id,
          userId: userId,
          template: template,
          currentDate: currentDate,
        );
        final daysElapsed =
            _getDaysElapsedInPeriod(currentDate, template.periodType);
        final targetRate =
            template.timesPerPeriod / _getPeriodDays(template.periodType);
        final currentRate =
            daysElapsed > 0 ? completedCount / daysElapsed : 0.0;
        final rate = currentRate - targetRate;
        if (completedCount >= template.timesPerPeriod) {
          return 0; // Period target met, no new instance needed
        }
        if (rate >= 0) {
          // User is on track → Use fixed windows (original logic)
          final periodDays = _getPeriodDays(template.periodType);
          final fixedWindow = (periodDays / template.timesPerPeriod).round();
          return fixedWindow;
        } else {
          // User is behind → Use dynamic windows
          final remainingCompletions = template.timesPerPeriod - completedCount;
          final daysRemaining =
              _getDaysRemainingInPeriod(currentDate, template.periodType);
          final adaptiveWindow = (daysRemaining / remainingCompletions)
              .ceil()
              .clamp(1, daysRemaining);
          return adaptiveWindow;
        }
      case 'specificDays':
        return 1;
      default:
        return 1;
    }
  }

  /// Generate next habit instance using frequency-type-specific logic
  static Future<void> _generateNextHabitInstance(
    ActivityInstanceRecord instance,
    String userId,
  ) async {
    try {
      // Validate required fields
      if (instance.windowEndDate == null) {
        return;
      }

      // Get template for rate calculation
      final templateRef =
          ActivityRecord.collectionForUser(userId).doc(instance.templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) {
        return;
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);

      // Check if template is still active
      if (!template.isActive) {
        return;
      }

      DateTime nextBelongsToDate;
      int nextWindowDuration;

      // Branch based on frequency type
      if (template.frequencyType == 'timesPerPeriod') {
        // ONLY apply rate-based logic for timesPerPeriod
        final completedCount = await _getCompletedCountInPeriod(
          templateId: instance.templateId,
          userId: userId,
          template: template,
          currentDate: DateService.currentDate,
        );
        final daysElapsed = _getDaysElapsedInPeriod(
            DateService.currentDate, template.periodType);
        final targetRate =
            template.timesPerPeriod / _getPeriodDays(template.periodType);
        final currentRate =
            daysElapsed > 0 ? completedCount / daysElapsed : 0.0;
        final rate = currentRate - targetRate;

        if (rate >= 0) {
          // User is on track → Wait for current window to end
          nextBelongsToDate =
              instance.windowEndDate!.add(const Duration(days: 1));
        } else {
          // User is behind → Generate for next day (minimum 1-day gap)
          nextBelongsToDate =
              DateService.currentDate.add(const Duration(days: 1));
        }

        nextWindowDuration = await _calculateAdaptiveWindowDuration(
          template: template,
          userId: userId,
          currentDate: nextBelongsToDate,
        );
        // Handle case where target is already met
        if (nextWindowDuration == 0) {
          return;
        }
      } else {
        // For everyXPeriod, specificDays, and others: use FIXED window logic
        nextBelongsToDate =
            instance.windowEndDate!.add(const Duration(days: 1));
        nextWindowDuration = await _calculateAdaptiveWindowDuration(
          template: template,
          userId: userId,
          currentDate: nextBelongsToDate,
        );
        // Handle case where target is already met
        if (nextWindowDuration == 0) {
          return;
        }
      }

      final nextWindowEndDate =
          nextBelongsToDate.add(Duration(days: nextWindowDuration - 1));

      // Check if instance already exists for this template and date
      // Check ALL statuses (not just pending) to prevent duplicates
      try {
        final existingQuery = ActivityInstanceRecord.collectionForUser(userId)
            .where('templateId', isEqualTo: instance.templateId)
            .where('belongsToDate', isEqualTo: nextBelongsToDate);
        final existingInstances = await existingQuery.get();
        if (existingInstances.docs.isNotEmpty) {
          return; // Instance already exists (any status), don't create duplicate
        }

        // Also check if there's already a pending instance for today or future dates
        // This prevents creating duplicates when instances exist for different dates
        final today = DateService.todayStart;
        final futurePendingQuery =
            ActivityInstanceRecord.collectionForUser(userId)
                .where('templateId', isEqualTo: instance.templateId)
                .where('status', isEqualTo: 'pending');
        final futurePendingSnapshot = await futurePendingQuery.get();
        final futurePendingInstances = futurePendingSnapshot.docs
            .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
            .where((inst) {
          // Check if belongsToDate is today or in the future
          if (inst.belongsToDate != null) {
            final belongsToDateOnly = DateTime(
              inst.belongsToDate!.year,
              inst.belongsToDate!.month,
              inst.belongsToDate!.day,
            );
            return belongsToDateOnly.isAtSameMomentAs(today) ||
                belongsToDateOnly.isAfter(today);
          }
          // Also check windowEndDate if belongsToDate is null
          if (inst.windowEndDate != null) {
            final windowEndDateOnly = DateTime(
              inst.windowEndDate!.year,
              inst.windowEndDate!.month,
              inst.windowEndDate!.day,
            );
            return windowEndDateOnly.isAtSameMomentAs(today) ||
                windowEndDateOnly.isAfter(today);
          }
          return false;
        }).toList();

        // If there's already a pending instance for today or future, don't create duplicate
        if (futurePendingInstances.isNotEmpty) {
          return;
        }
      } catch (e) {
        // If query fails, continue with instance creation (better to create than miss)
        print('Error checking for existing instances: $e');
      }

      // Inherit order from previous instance of the same template
      int? queueOrder;
      int? habitsOrder;
      int? tasksOrder;
      try {
        queueOrder = await InstanceOrderService.getOrderFromPreviousInstance(
            instance.templateId, 'queue', userId);
        habitsOrder = await InstanceOrderService.getOrderFromPreviousInstance(
            instance.templateId, 'habits', userId);
        tasksOrder = await InstanceOrderService.getOrderFromPreviousInstance(
            instance.templateId, 'tasks', userId);
      } catch (e) {
        // If order lookup fails, continue with null values (will use default sorting)
      }

      // Create next instance data
      final nextInstanceData = createActivityInstanceRecordData(
        templateId: instance.templateId,
        dueDate: nextBelongsToDate, // dueDate = start of window
        dueTime: instance.templateDueTime,
        status: 'pending',
        createdTime: DateService.currentDate,
        lastUpdated: DateService.currentDate,
        isActive: true,
        lastDayValue: 0, // Initialize for differential tracking
        templateName: template.name,
        templateCategoryId: template.categoryId,
        templateCategoryName: template.categoryName,
        templateCategoryType: template.categoryType,
        templatePriority: template.priority,
        templateTrackingType: template.trackingType,
        templateTarget: template.target,
        templateUnit: template.unit,
        templateDescription: template.description,
        templateTimeEstimateMinutes: template.timeEstimateMinutes,
        templateShowInFloatingTimer: template.showInFloatingTimer,
        templateIsRecurring: template.isRecurring,
        templateEveryXValue: template.everyXValue,
        templateEveryXPeriodType: template.everyXPeriodType,
        templateTimesPerPeriod: template.timesPerPeriod,
        templatePeriodType: template.periodType,
        dayState: 'open',
        belongsToDate: nextBelongsToDate,
        windowEndDate: nextWindowEndDate,
        windowDuration: nextWindowDuration,
        // Inherit order from previous instance
        queueOrder: queueOrder,
        habitsOrder: habitsOrder,
        tasksOrder: tasksOrder,
      );
      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Create optimistic instance with temporary reference
      // We'll use a placeholder reference that will be replaced on reconciliation
      final tempRef = ActivityInstanceRecord.collectionForUser(userId)
          .doc('temp_${DateTime.now().millisecondsSinceEpoch}');
      final optimisticInstance = ActivityInstanceRecord.getDocumentFromData(
        nextInstanceData,
        tempRef,
      );

      // 2. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      // 3. Track operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: 'temp', // Will be updated on reconciliation
        operationType: 'create',
        optimisticInstance: optimisticInstance,
        originalInstance:
            optimisticInstance, // For creation, use optimistic as original since there's no existing instance
      );

      // 4. Broadcast optimistically (IMMEDIATE)
      InstanceEvents.broadcastInstanceCreatedOptimistic(
          optimisticInstance, operationId);

      // 5. Add to Firestore
      try {
        final newInstanceRef =
            await ActivityInstanceRecord.collectionForUser(userId)
                .add(nextInstanceData);

        // 6. Reconcile with actual instance
        final newInstance = await getUpdatedInstance(
          instanceId: newInstanceRef.id,
          userId: userId,
        );
        OptimisticOperationTracker.reconcileInstanceCreation(
            operationId, newInstance);
      } catch (e) {
        // 7. Rollback on error
        OptimisticOperationTracker.rollbackOperation(operationId);
        // Log error but don't fail - instance creation is non-critical for completion
        print('Error creating next habit instance: $e');
      }
    } catch (e) {
      // Don't rethrow - we don't want to fail the completion
    }
  }

  /// Calculate how many instances should exist between a due date and today
  /// based on the recurrence pattern. Used to determine if "Skip all past occurrences"
  /// option should be shown.
  static int _calculateMissingInstancesCount({
    required DateTime currentDueDate,
    required DateTime today,
    required ActivityRecord template,
  }) {
    if (!template.isRecurring) return 0;
    int count = 0;
    DateTime nextDueDate = currentDueDate;
    // Keep calculating next due dates until we reach or pass today
    while (nextDueDate.isBefore(today)) {
      final nextDate = RecurrenceCalculator.calculateNextDueDate(
        currentDueDate: nextDueDate,
        template: template,
      );
      if (nextDate == null) break;
      // Only count if the next date is before today
      if (nextDate.isBefore(today)) {
        count++;
        nextDueDate = nextDate;
      } else {
        break;
      }
    }
    return count;
  }

  /// Calculate missing instances count from instance data (for UI menu logic)
  static int calculateMissingInstancesFromInstance({
    required ActivityInstanceRecord instance,
    required DateTime today,
  }) {
    if (instance.dueDate == null) return 0;
    // Create a minimal template object from instance data
    final template = ActivityRecord.getDocumentFromData(
      {
        'isRecurring': true,
        'frequencyType': _getFrequencyTypeFromInstance(instance),
        'everyXValue': instance.templateEveryXValue,
        'everyXPeriodType': instance.templateEveryXPeriodType,
        'timesPerPeriod': instance.templateTimesPerPeriod,
        'periodType': instance.templatePeriodType,
        'specificDays':
            [], // Not cached in instance, would need to fetch template
      },
      instance.reference, // Use instance reference as placeholder
    );
    return _calculateMissingInstancesCount(
      currentDueDate: instance.dueDate!,
      today: today,
      template: template,
    );
  }

  /// Determine frequency type from instance data
  static String _getFrequencyTypeFromInstance(ActivityInstanceRecord instance) {
    // For now, assume 'everyXPeriod' if we have everyXValue and everyXPeriodType
    if (instance.templateEveryXValue > 0 &&
        instance.templateEveryXPeriodType.isNotEmpty) {
      return 'everyXPeriod';
    }
    // Could add logic for other frequency types based on available fields
    return 'everyXPeriod';
  }

  /// Clean up instances beyond a shortened end date
  /// Deletes pending instances that are beyond the new end date
  static Future<void> cleanupInstancesBeyondEndDate({
    required String templateId,
    required DateTime newEndDate,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      // Get all instances for this template
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId);
      final instances = await query.get();
      // Delete pending instances beyond the end date
      for (final doc in instances.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.status == 'pending' &&
            instance.dueDate != null &&
            instance.dueDate!.isAfter(newEndDate)) {
          await doc.reference.delete();
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Regenerate instances from a new start date
  /// Deletes all pending instances and creates new ones based on the updated start date
  /// Preserves all completed instances
  static Future<void> regenerateInstancesFromStartDate({
    required String templateId,
    required ActivityRecord template,
    required DateTime newStartDate,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      // Get all instances for this template
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId);
      final instances = await query.get();
      // Delete all pending instances (preserve completed ones)
      for (final doc in instances.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.status == 'pending') {
          // Also check if instance is beyond the new end date
          bool shouldDelete = true;
          if (template.endDate != null && instance.dueDate != null) {
            // If template has an end date and instance is beyond it, delete it
            if (instance.dueDate!.isAfter(template.endDate!)) {}
          }
          if (shouldDelete) {
            await doc.reference.delete();
          }
        }
      }
      // Create new first instance based on the new start date
      if (template.categoryType == 'habit') {
        // For habits, create instance using the window system
        await createActivityInstance(
          templateId: templateId,
          dueDate: newStartDate,
          dueTime: template.dueTime,
          template: template,
          userId: uid,
        );
      } else if (template.isRecurring) {
        // For recurring tasks, create the first instance
        await createActivityInstance(
          templateId: templateId,
          dueDate: newStartDate,
          dueTime: template.dueTime,
          template: template,
          userId: uid,
        );
      } else {
        // For one-time tasks, create instance if due date is set
        if (template.dueDate != null) {
          await createActivityInstance(
            templateId: templateId,
            dueDate: template.dueDate!,
            dueTime: template.dueTime,
            template: template,
            userId: uid,
          );
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Cascade updates to instances (Category, Name, etc.) with Batching
  /// [updates] - Map of fields to update (e.g. {'templateCategoryName': 'New Name'})
  /// [updateHistorical] - If true, updates history (capped at 365 days). If false, pending only.
  static Future<void> updateActivityInstancesCascade({
    required String templateId,
    required Map<String, dynamic> updates,
    required bool updateHistorical,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    if (updates.isEmpty) return;

    // Track all optimistic operations for this cascade update
    final operationIds = <String, String>{}; // instanceId -> operationId

    try {
      final instances =
          await getInstancesForTemplate(templateId: templateId, userId: uid);
      final now = DateTime.now();
      final oneYearAgo = now.subtract(const Duration(days: 365));

      // Batching (limit 500 ops per batch)
      final batches = <List<ActivityInstanceRecord>>[];
      List<ActivityInstanceRecord> currentBatch = [];

      for (final instance in instances) {
        bool shouldUpdate = false;

        // 1. Pending/Future instances: ALWAYS update
        if (instance.status != 'completed' && instance.status != 'skipped') {
          shouldUpdate = true;
        }
        // 2. Historical instances: Check flag and date limit
        else if (updateHistorical) {
          final refDate =
              instance.completedAt ?? instance.dueDate ?? instance.createdTime;
          if (refDate != null && refDate.isAfter(oneYearAgo)) {
            shouldUpdate = true;
          }
        }

        if (shouldUpdate) {
          // ==================== OPTIMISTIC BROADCAST ====================
          // 1. Create optimistic instance
          final optimisticInstance =
              InstanceEvents.createOptimisticPropertyUpdateInstance(
            instance,
            updates,
          );

          // 2. Generate operation ID
          final operationId = OptimisticOperationTracker.generateOperationId();

          // 3. Track operation
          OptimisticOperationTracker.trackOperation(
            operationId,
            instanceId: instance.reference.id,
            operationType: 'propertyUpdate',
            optimisticInstance: optimisticInstance,
            originalInstance: instance,
          );

          // 4. Broadcast optimistically (IMMEDIATE)
          InstanceEvents.broadcastInstanceUpdatedOptimistic(
              optimisticInstance, operationId);

          // Store operation ID for reconciliation
          operationIds[instance.reference.id] = operationId;

          currentBatch.add(instance);
          if (currentBatch.length >= 450) {
            // Safety buffer below 500
            batches.add(List.from(currentBatch));
            currentBatch.clear();
          }
        }
      }
      if (currentBatch.isNotEmpty) batches.add(currentBatch);

      // Execute batches
      try {
        for (final batchList in batches) {
          final writeBatch = FirebaseFirestore.instance.batch();
          for (final instance in batchList) {
            writeBatch.update(instance.reference, {
              ...updates,
              'lastUpdated': DateTime.now(),
            });
          }
          await writeBatch.commit();
        }

        print(
            '✅ Batched update complete: Updated ${batches.fold<int>(0, (sum, b) => sum + b.length)} instances.');

        // ==================== RECONCILE ====================
        // Reconcile all updated instances
        for (final instanceId in operationIds.keys) {
          try {
            final updatedInstance = await getUpdatedInstance(
              instanceId: instanceId,
              userId: uid,
            );
            final operationId = operationIds[instanceId]!;
            OptimisticOperationTracker.reconcileOperation(
                operationId, updatedInstance);
          } catch (e) {
            print('Error reconciling instance $instanceId: $e');
            // Rollback this specific instance
            final operationId = operationIds[instanceId]!;
            OptimisticOperationTracker.rollbackOperation(operationId);
          }
        }

        // Post-commit: Update reminders for pending instances
        final batchList = batches.expand((element) => element).toList();
        for (final instance in batchList) {
          if (instance.status != 'completed' && instance.status != 'skipped') {
            try {
              // Re-fetch to get updated data for reminder scheduling
              final refreshedDoc = await instance.reference.get();
              if (refreshedDoc.exists) {
                final refreshedInstance =
                    ActivityInstanceRecord.fromSnapshot(refreshedDoc);
                await ReminderScheduler.rescheduleReminderForInstance(
                    refreshedInstance);
              }
            } catch (e) {
              print('Error updating reminder for ${instance.reference.id}: $e');
            }
          }
        }
      } catch (e) {
        // ==================== ROLLBACK ====================
        // Rollback all optimistic operations on batch failure
        print(
            '❌ Error in batch update, rolling back optimistic operations: $e');
        for (final operationId in operationIds.values) {
          OptimisticOperationTracker.rollbackOperation(operationId);
        }
        rethrow;
      }
    } catch (e) {
      print('❌ Error in updateActivityInstancesCascade: $e');
      // Rollback any remaining operations
      for (final operationId in operationIds.values) {
        OptimisticOperationTracker.rollbackOperation(operationId);
      }
      rethrow;
    }
  }
}
