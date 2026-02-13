import 'dart:async';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';
import 'activity_instance_helper_service.dart';

/// Service for querying and retrieving activity instances
class ActivityInstanceQueryService {
  /// Safely query instances without triggering composite index errors
  /// Fetches broad datasets (all pending, recent completed) and relies on in-memory filtering
  static Future<List<ActivityInstanceRecord>> querySafeInstances({
    required String uid,
    bool includePending = true,
    bool includeRecentCompleted = false,
    bool includeRecentSkipped = false,
    bool includeLiveWindowSkippedHabits = false,
  }) async {
    final List<ActivityInstanceRecord> allInstances = [];

    // Add distinct try-catch blocks for each query to identify which one fails/hangs
    if (includePending) {
      try {
        final pendingQuery = ActivityInstanceRecord.collectionForUser(uid)
            .where('status', isEqualTo: 'pending')
            .limit(500); // Increased limit to ensure we catch everything

        // Add timeout to prevent infinite hang
        final pendingResult = await pendingQuery.get().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Pending query timed out');
          },
        );

        final docs = pendingResult.docs;
        allInstances.addAll(
            docs.map((doc) => ActivityInstanceRecord.fromSnapshot(doc)));
      } catch (e) {
        // Continue even if this fails, so we might at least get completed ones
      }
    }

    if (includeRecentCompleted) {
      try {
        final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
        final completedQuery = ActivityInstanceRecord.collectionForUser(uid)
            .where('completedAt', isGreaterThanOrEqualTo: twoDaysAgo)
            .orderBy('completedAt', descending: true)
            .limit(200);

        // Add timeout
        final completedResult = await completedQuery.get().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Completed query timed out');
          },
        );

        final docs = completedResult.docs;

        // Filter strictly for completed (query is inclusive of greaterThanOrEqualTo)
        // and ensure status is explicitly completed
        final completedInstances = docs
            .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
            .where((inst) => inst.status == 'completed')
            .toList();
        allInstances.addAll(completedInstances);
      } catch (e) {
        // Continue silently
      }
    }

    if (includeRecentSkipped) {
      try {
        final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
        final skippedQuery = ActivityInstanceRecord.collectionForUser(uid)
            .where('skippedAt', isGreaterThanOrEqualTo: twoDaysAgo)
            .orderBy('skippedAt', descending: true)
            .limit(200);

        final skippedResult = await skippedQuery.get().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Skipped query timed out');
          },
        );

        final skippedInstances = skippedResult.docs
            .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
            .where((inst) => inst.status == 'skipped')
            .toList();
        allInstances.addAll(skippedInstances);
      } catch (e) {
        // Continue silently
      }
    }

    if (includeLiveWindowSkippedHabits) {
      try {
        final today = DateService.todayStart;
        final liveWindowQuery = ActivityInstanceRecord.collectionForUser(uid)
            .where('windowEndDate', isGreaterThanOrEqualTo: today)
            .limit(500);

        final liveWindowResult = await liveWindowQuery.get().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Live skipped habits query timed out');
          },
        );

        final liveSkippedHabits = liveWindowResult.docs
            .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
            .where((inst) {
          if (inst.templateCategoryType != 'habit') return false;
          if (inst.status != 'skipped') return false;

          final startSource = inst.belongsToDate ?? inst.dueDate;
          final endSource = inst.windowEndDate;
          if (startSource == null || endSource == null) return false;

          final startDateOnly = DateTime(
              startSource.year, startSource.month, startSource.day);
          final endDateOnly =
              DateTime(endSource.year, endSource.month, endSource.day);
          return !today.isBefore(startDateOnly) && !today.isAfter(endDateOnly);
        }).toList();

        allInstances.addAll(liveSkippedHabits);
      } catch (e) {
        // Continue silently
      }
    }

    return allInstances.cast<ActivityInstanceRecord>();
  }

  /// Get recent completed instances (for Weekly View)
  /// Fetches completed instances from the last 7 days
  static Future<List<ActivityInstanceRecord>> getRecentCompletedInstances({
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: sevenDaysAgo)
          .orderBy('completedAt', descending: true);

      final result = await query.get();
      return result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getRecentCompletedInstances',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get active task instances for the user
  /// This is the core method for Phase 2 - displaying instances
  /// It returns only the earliest pending instance for each task template
  static Future<List<ActivityInstanceRecord>> getActiveTaskInstances({
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
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
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getActiveTaskInstances',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get all task instances (active and completed) for Tasks page
  /// Fetches:
  /// - All PENDING instances (to show in tasks list)
  /// - COMPLETED instances from last 2 days only (for recent completions)
  /// For older history, use `getTaskInstancesHistory()` when user requests it
  static Future<List<ActivityInstanceRecord>> getAllTaskInstances({
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      // Use safe query to avoid missing index errors
      final allRawInstances = await querySafeInstances(
        uid: uid,
        includePending: true,
        includeRecentCompleted: true,
      );
      // Filter for tasks in memory
      final allInstances = allRawInstances.where((inst) {
        final isTask = inst.templateCategoryType == 'task';
        return isTask;
      }).toList();

      final sorted =
          InstanceOrderService.sortInstancesByOrder(allInstances, 'tasks');
      return sorted;
    } catch (e, stackTrace) {
      print('🔴 ActivityInstanceService.getAllTaskInstances: ERROR - $e');
      print(
          '🔴 ActivityInstanceService.getAllTaskInstances: StackTrace: $stackTrace');
      logFirestoreQueryError(
        e,
        queryDescription: 'getAllTaskInstances',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get older task instances history (for "Load More" functionality)
  /// Fetches completed instances from specified number of days ago
  static Future<List<ActivityInstanceRecord>> getTaskInstancesHistory({
    required int daysAgo,
    required int daysToLoad,
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      final startDate =
          DateTime.now().subtract(Duration(days: daysAgo + daysToLoad));
      final endDate = DateTime.now().subtract(Duration(days: daysAgo));

      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'task')
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: startDate)
          .where('completedAt', isLessThan: endDate)
          .orderBy('completedAt', descending: true)
          .limit(100); // Safety limit per load

      final result = await query.get();
      return result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get current active habit instances for the user (Habits page)
  /// Only returns instances whose window includes today - no future instances
  static Future<List<ActivityInstanceRecord>> getCurrentHabitInstances({
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
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
  /// OPTIMIZED: Uses belongsToDate to fetch only relevant instances
  static Future<List<ActivityInstanceRecord>> getHabitInstancesForDate({
    required DateTime targetDate,
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      // Normalize target date to start of day for comparison
      final targetDateStart =
          DateTime(targetDate.year, targetDate.month, targetDate.day);

      // OPTIMIZED: Fetch ONLY habits whose window includes the target date
      // Instead of fetching ALL habits (~1,800 docs), fetch only those whose window ends on or after target
      // This captures all active habits (including multi-day) while excluding historical ones
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('windowEndDate', isGreaterThanOrEqualTo: targetDateStart);
      final result = await query.get();
      final habitInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      // Sort: instances with due dates first (oldest first), then nulls last
      habitInstances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1; // a goes after b
        if (b.dueDate == null) return -1; // a goes before b
        return a.dueDate!.compareTo(b.dueDate!);
      });

      return habitInstances;
    } catch (e) {
      return [];
    }
  }

  /// Get all habit instances for the Habits page
  /// ONLY fetches PENDING instances to prevent OOM (completed history not needed)
  static Future<List<ActivityInstanceRecord>> getAllHabitInstances({
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      // Use safe query (pending only for habits page)
      final allRawInstances = await querySafeInstances(
        uid: uid,
        includePending: true,
        includeRecentCompleted: false,
      );

      // Filter for habits
      final allHabitInstances = allRawInstances
          .where((inst) => inst.templateCategoryType == 'habit')
          .toList();

      // Sort by lastUpdated descending (in-memory)
      allHabitInstances.sort((a, b) {
        return (b.lastUpdated ?? DateTime(0))
            .compareTo(a.lastUpdated ?? DateTime(0));
      });

      return allHabitInstances;
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getAllHabitInstances',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get latest habit instance per template for the Habits page
  /// Returns one instance per habit template - the next upcoming/actionable instance
  /// ONLY fetches PENDING instances to prevent OOM
  static Future<List<ActivityInstanceRecord>>
      getLatestHabitInstancePerTemplate({
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      // Use safe query (pending only)
      final allRawInstances = await querySafeInstances(
        uid: uid,
        includePending: true,
        includeRecentCompleted: false,
      );

      // Filter for habits
      final allHabitInstances = allRawInstances
          .where((inst) => inst.templateCategoryType == 'habit')
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
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getLatestHabitInstancePerTemplate',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get active habit instances for the user (Queue page - includes future instances)
  static Future<List<ActivityInstanceRecord>> getActiveHabitInstances({
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
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
  /// OPTIMIZED: Only fetches pending + completed from last 2 days to prevent OOM
  static Future<List<ActivityInstanceRecord>> getAllActiveInstances({
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      // CRITICAL: Fetch only pending instances and recent completions (last 2 days)
      // This prevents OOM from loading thousands of old completed instances

      // Use safe query
      final allInstances = await querySafeInstances(
        uid: uid,
        includePending: true,
        includeRecentCompleted: true,
        includeRecentSkipped: true,
        includeLiveWindowSkippedHabits: true,
      );

      // Separate tasks and habits for different filtering logic
      // Exclude essentials from normal queries
      // Also filter out inactive instances to match tasks page behavior
      final taskInstances = allInstances.where((inst) {
        final isTask = inst.templateCategoryType == 'task';
        final isEssential = inst.templateCategoryType == 'essential';
        final isActive = inst.isActive;
        return isTask && !isEssential && isActive;
      }).toList();

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
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getAllActiveInstances',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      return [];
    }
  }
}
