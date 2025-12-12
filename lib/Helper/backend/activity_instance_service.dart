import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/utils/instance_date_calculator.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/backend/reminder_scheduler.dart';

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
    // Calculate window fields for habits
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
      templateShowInFloatingTimer: template.showInFloatingTimer,
      templateIsRecurring: template.isRecurring,
      templateEveryXValue: template.everyXValue,
      templateEveryXPeriodType: template.everyXPeriodType,
      templateTimesPerPeriod: template.timesPerPeriod,
      templatePeriodType: template.periodType,
      templateDueTime: template.dueTime,
      // Set habit-specific fields
      dayState: template.categoryType == 'habit' ? 'open' : null,
      belongsToDate: template.categoryType == 'habit' ? normalizedDate : null,
      windowEndDate: windowEndDate,
      windowDuration: windowDuration,
    );
    final result =
        await ActivityInstanceRecord.collectionForUser(uid).add(instanceData);
    // Schedule reminder if instance has due time
    try {
      final createdInstance = ActivityInstanceRecord.fromSnapshot(
        await result.get(),
      );
      await ReminderScheduler.scheduleReminderForInstance(createdInstance);
    } catch (e) {
      // Error scheduling reminder - continue without it
    }
    return result;
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
      // Sort by due date (oldest first, nulls last)
      allInstances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
      return allInstances;
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
      // Debug: Log each instance being returned
      for (final instance in relevantInstances) {}
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
          print(
              'ActivityInstanceService: Selected latest instance for ${latestInstance.templateName}: ${latestInstance.status} (due: ${latestInstance.dueDate})');
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
      // Debug: Log each instance being returned
      for (final instance in relevantInstances) {}
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
      // Exclude non-productive/sequence_item types from normal queries
      // (sequence_item is legacy, now all are non_productive)
      // Also filter out inactive instances to match tasks page behavior
      final taskInstances = allInstances
          .where((inst) =>
              inst.templateCategoryType == 'task' &&
              inst.templateCategoryType != 'non_productive' &&
              inst.templateCategoryType != 'sequence_item' &&
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
      print(
          'ActivityInstanceService: Returning ${finalInstanceList.length} relevant instances (${earliestTasks.length} tasks + ${finalInstanceList.length - earliestTasks.length} habits).');
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
      final instanceRef = await createActivityInstance(
        templateId: templateId,
        template: template,
        userId: uid,
      );
    } catch (e) {}
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
      return [];
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
  static Future<Map<String, int>> resetAllInstancesForFreshStart({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      // Step 1: Delete ALL existing instances for the user
      final allInstancesQuery = ActivityInstanceRecord.collectionForUser(uid);
      final allInstances = await allInstancesQuery.get();

      int deletedCount = 0;
      for (final doc in allInstances.docs) {
        await doc.reference.delete();
        deletedCount++;
      }

      // Step 2: Get all active templates (both habits and tasks)
      final habitTemplates = await ActivityRecord.collectionForUser(uid)
          .where('categoryType', isEqualTo: 'habit')
          .where('isActive', isEqualTo: true)
          .get();

      final taskTemplates = await ActivityRecord.collectionForUser(uid)
          .where('categoryType', isEqualTo: 'task')
          .where('isActive', isEqualTo: true)
          .get();

      // Step 3: Create fresh instances starting tomorrow
      final tomorrow = DateTime.now().add(Duration(days: 1));
      final tomorrowStart =
          DateTime(tomorrow.year, tomorrow.month, tomorrow.day);

      int createdCount = 0;

      // Create instances for habits
      for (final doc in habitTemplates.docs) {
        final template = ActivityRecord.fromSnapshot(doc);
        await createActivityInstance(
          templateId: template.reference.id,
          dueDate: tomorrowStart,
          dueTime: template.dueTime,
          template: template,
          userId: uid,
        );
        createdCount++;
      }

      // Create instances for tasks
      for (final doc in taskTemplates.docs) {
        final template = ActivityRecord.fromSnapshot(doc);
        await createActivityInstance(
          templateId: template.reference.id,
          dueDate: tomorrowStart,
          dueTime: template.dueTime,
          template: template,
          userId: uid,
        );
        createdCount++;
      }

      return {
        'deletedInstances': deletedCount,
        'createdInstances': createdCount,
        'habitTemplates': habitTemplates.docs.length,
        'taskTemplates': taskTemplates.docs.length,
      };
    } catch (e) {
      rethrow;
    }
  }

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
      // Update current instance as completed
      await instanceRef.update({
        'status': 'completed',
        'completedAt': completionTime,
        'currentValue': finalValue ?? instance.currentValue,
        'accumulatedTime': finalAccumulatedTime ?? instance.accumulatedTime,
        'notes': notes ?? instance.notes,
        'lastUpdated': now,
      });
      // Broadcast the instance update event
      final updatedInstance =
          await getUpdatedInstance(instanceId: instanceId, userId: uid);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
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
            final nextDueDate = _calculateNextDueDate(
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
              } catch (e) {}
            }
          }
        }
      }
      // Cancel reminder for completed instance
      try {
        await ReminderScheduler.cancelReminderForInstance(instanceId);
      } catch (e) {}
    } catch (e) {
      rethrow;
    }
  }

  /// Uncomplete an activity instance (mark as pending)
  static Future<void> uncompleteInstance({
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

      // For habits, delete any pending future instances that were auto-generated
      if (instance.templateCategoryType == 'habit') {
        final futureInstancesQuery =
            ActivityInstanceRecord.collectionForUser(uid)
                .where('templateId', isEqualTo: instance.templateId)
                .where('status', isEqualTo: 'pending')
                .where('belongsToDate', isGreaterThan: instance.belongsToDate);

        final futureInstances = await futureInstancesQuery.get();
        for (final doc in futureInstances.docs) {
          await doc.reference.delete();
          print('Deleted future instance: ${doc.id}');
        }
      }

      await instanceRef.update({
        'status': 'pending',
        'completedAt': null,
        'skippedAt': null, // Add this to also clear skippedAt
        'lastUpdated': DateService.currentDate,
      });
      // Broadcast the instance update event
      final updatedInstance =
          await getUpdatedInstance(instanceId: instanceId, userId: uid);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
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
      // For windowed habits, update lastDayValue to current value for next day's calculation
      final updateData = <String, dynamic>{
        'currentValue': currentValue,
        'lastUpdated': now,
      };
      // Note: lastDayValue should be updated at day-end, not during progress updates
      // This allows differential progress calculation to work correctly
      await instanceRef.update(updateData);
      // Check if target is reached and auto-complete/uncomplete
      if (instance.templateTrackingType == 'quantitative' &&
          instance.templateTarget != null) {
        final target = instance.templateTarget as num;
        final progress = currentValue is num ? currentValue : 0;
        if (progress >= target) {
          // Auto-complete if not already completed
          if (instance.status != 'completed') {
            await completeInstance(
              instanceId: instanceId,
              finalValue: currentValue,
              userId: uid,
            );
          } else {
            // Already completed, just broadcast the progress update
            final updatedInstance =
                await getUpdatedInstance(instanceId: instanceId, userId: uid);
            InstanceEvents.broadcastInstanceUpdated(updatedInstance);
          }
        } else {
          // Auto-uncomplete if currently completed OR skipped and progress dropped below target
          if (instance.status == 'completed' || instance.status == 'skipped') {
            await uncompleteInstance(
              instanceId: instanceId,
              userId: uid,
            );
          } else {
            // Not completed, just broadcast progress update
            final updatedInstance =
                await getUpdatedInstance(instanceId: instanceId, userId: uid);
            InstanceEvents.broadcastInstanceUpdated(updatedInstance);
          }
        }
      } else {
        // Broadcast the instance update event for progress changes
        final updatedInstance =
            await getUpdatedInstance(instanceId: instanceId, userId: uid);
        InstanceEvents.broadcastInstanceUpdated(updatedInstance);
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
      await instanceRef.update({
        'snoozedUntil': snoozeUntil,
        'lastUpdated': DateService.currentDate,
      });
      // Cancel reminder for snoozed instance
      try {
        await ReminderScheduler.cancelReminderForInstance(instanceId);
      } catch (e) {}
      // Broadcast the instance update event
      final updatedInstance =
          await getUpdatedInstance(instanceId: instanceId, userId: uid);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
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
      await instanceRef.update({
        'snoozedUntil': null,
        'lastUpdated': DateService.currentDate,
      });
      // Reschedule reminder for unsnoozed instance
      try {
        final updatedInstance =
            await getUpdatedInstance(instanceId: instanceId, userId: uid);
        await ReminderScheduler.rescheduleReminderForInstance(updatedInstance);
      } catch (e) {}
      // Broadcast the instance update event
      final updatedInstance =
          await getUpdatedInstance(instanceId: instanceId, userId: uid);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
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

      await instanceRef.update({
        'isTimerActive': isActive,
        'timerStartTime': startTime ?? (isActive ? DateService.currentDate : null),
        'lastUpdated': DateService.currentDate,
      });

      // Broadcast the instance update event
      final updatedInstance =
          await getUpdatedInstance(instanceId: instanceId, userId: uid);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
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
        final updateData = <String, dynamic>{
          'isTimerActive': false, // Legacy field
          'timerStartTime': null, // Legacy field
          'isTimeLogging': false, // Session field
          'currentSessionStartTime': null, // Session field
          'timeLogSessions': existingSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime, // Keep legacy field updated
          'currentValue': totalTime,
          'lastUpdated': now,
        };
        // For windowed habits, update lastDayValue to track differential progress
        if (instance.templateCategoryType == 'habit' &&
            instance.windowDuration > 1) {
          updateData['lastDayValue'] = totalTime;
        }
        await instanceRef.update(updateData);
      } else {
        // Start timer - set session tracking fields
        await instanceRef.update({
          'isTimerActive': true, // Legacy field
          'timerStartTime': now, // Legacy field
          'isTimeLogging': true, // Session field
          'currentSessionStartTime': now, // Session field
          'lastUpdated': now,
        });
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
      print(
          'ActivityInstanceService: Skipping instance ${instance.templateName} (instanceId: $instanceId, dueDate: ${instance.dueDate}, windowEndDate: ${instance.windowEndDate}, skippedAt: $skipTime, skipAutoGeneration: $skipAutoGeneration)');
      // Update current instance as skipped
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
          print(
              'ActivityInstanceService: Generating next habit instance after skip for ${instance.templateName}');
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
              final nextDueDate = _calculateNextDueDate(
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
                } catch (e) {}
              }
            }
          }
        }
      } else {
        print(
            'ActivityInstanceService: Skipping next instance generation (skipAutoGeneration=true)');
      }
      // Cancel reminder for skipped instance
      try {
        await ReminderScheduler.cancelReminderForInstance(instanceId);
      } catch (e) {}
    } catch (e) {
      rethrow;
    }
  }

  /// Efficiently skip expired instances using batch writes
  /// Handles frequency-aware date calculation to find the "yesterday" instance
  /// Stops at yesterday (day before today) for manual user confirmation
  static Future<DocumentReference?> bulkSkipExpiredInstancesWithBatches({
    required ActivityInstanceRecord oldestInstance,
    required ActivityRecord template,
    required String userId,
  }) async {
    try {
      final yesterday = DateService.yesterdayStart;
      final now = DateService.currentDate;

      print(
          'bulkSkipExpiredInstancesWithBatches: Starting for ${template.name}');
      print('  oldestInstance dueDate: ${oldestInstance.dueDate}');
      print('  yesterday: $yesterday');

      // Calculate all due dates from oldestInstance to find which one has window ending on yesterday
      final List<DateTime> allDueDates = [];
      DateTime currentDueDate = oldestInstance.dueDate ?? DateTime.now();

      // Generate due dates based on frequency until we pass yesterday
      while (currentDueDate.isBefore(yesterday.add(const Duration(days: 30)))) {
        allDueDates.add(currentDueDate);
        final nextDate = _calculateNextDueDate(
          currentDueDate: currentDueDate,
          template: template,
        );
        if (nextDate == null) break;
        currentDueDate = nextDate;
      }

      print('  Generated ${allDueDates.length} due dates');

      // Find which instance's window would end EXACTLY on yesterday
      // We only want instances that expired yesterday, not ongoing windows
      DocumentReference? yesterdayInstanceRef;
      int yesterdayInstanceIndex = -1;

      for (int i = 0; i < allDueDates.length; i++) {
        final dueDate = allDueDates[i];
        final windowDuration = await _calculateAdaptiveWindowDuration(
          template: template,
          userId: userId,
          currentDate: dueDate,
        );

        if (windowDuration == 0) continue;

        final windowEnd = dueDate.add(Duration(days: windowDuration - 1));
        final windowEndNormalized =
            DateTime(windowEnd.year, windowEnd.month, windowEnd.day);

        // ONLY check if this window ends EXACTLY on yesterday
        // Do NOT include ongoing windows (those ending in the future)
        if (windowEndNormalized.isAtSameMomentAs(yesterday)) {
          yesterdayInstanceIndex = i;
          print(
              '  Found yesterday instance at index $i (dueDate: $dueDate, windowEnd: $windowEndNormalized)');
          break;
        }

        // Stop searching once we reach windows that end after yesterday
        // This ensures we don't touch ongoing windows
        if (windowEndNormalized.isAfter(yesterday)) {
          print(
              '  Reached future window at index $i (ends $windowEndNormalized), stopping search');
          break;
        }
      }

      if (yesterdayInstanceIndex == -1) {
        print('  No instance found for yesterday, returning null');
        return null;
      }

      // Step 1: Skip the oldest instance without auto-generation
      print(
          '  Step 1: Skipping oldest instance ${oldestInstance.reference.id}');
      await skipInstance(
        instanceId: oldestInstance.reference.id,
        skippedAt: oldestInstance.windowEndDate ?? oldestInstance.dueDate,
        skipAutoGeneration: true,
        userId: userId,
      );

      // Step 2: Batch create and skip all instances between oldest and yesterday (excluding yesterday)
      final instancesToSkip = allDueDates.sublist(1, yesterdayInstanceIndex);

      if (instancesToSkip.isNotEmpty) {
        print(
            '  Step 2: Batch creating and skipping ${instancesToSkip.length} instances');

        // Use Firestore batch writes (max 500 operations per batch)
        final firestore = FirebaseFirestore.instance;
        const batchSize =
            250; // Conservative: 2 operations per instance (create + update)

        for (int i = 0; i < instancesToSkip.length; i += batchSize) {
          final batch = firestore.batch();
          final end = (i + batchSize < instancesToSkip.length)
              ? i + batchSize
              : instancesToSkip.length;

          for (int j = i; j < end; j++) {
            final dueDate = instancesToSkip[j];
            final windowDuration = await _calculateAdaptiveWindowDuration(
              template: template,
              userId: userId,
              currentDate: dueDate,
            );

            if (windowDuration == 0) continue;

            final windowEndDate =
                dueDate.add(Duration(days: windowDuration - 1));
            final normalizedDate =
                DateTime(dueDate.year, dueDate.month, dueDate.day);

            // Create instance data
            final instanceData = createActivityInstanceRecordData(
              templateId: template.reference.id,
              dueDate: dueDate,
              dueTime: template.dueTime,
              status: 'skipped', // Create as already skipped
              skippedAt: windowEndDate,
              createdTime: now,
              lastUpdated: now,
              isActive: true,
              lastDayValue: 0,
              belongsToDate: normalizedDate,
              windowEndDate: windowEndDate,
              windowDuration: windowDuration,
              // Cache template data
              templateName: template.name,
              templateCategoryId: template.categoryId,
              templateCategoryName: template.categoryName,
              templateCategoryType: template.categoryType,
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

            final newDocRef =
                ActivityInstanceRecord.collectionForUser(userId).doc();
            batch.set(newDocRef, instanceData);
          }

          await batch.commit();
          print('    Batch committed: ${end - i} instances');
        }
      }

      // Step 3: Create yesterday instance as PENDING
      print('  Step 3: Creating yesterday instance as PENDING');
      final yesterdayDueDate = allDueDates[yesterdayInstanceIndex];
      yesterdayInstanceRef = await createActivityInstance(
        templateId: template.reference.id,
        dueDate: yesterdayDueDate,
        template: template,
        userId: userId,
      );

      print(
          '  Completed: yesterday instance created ${yesterdayInstanceRef.id}');
      return yesterdayInstanceRef;
    } catch (e) {
      print('Error in bulkSkipExpiredInstancesWithBatches: $e');
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
      await instanceRef.update({
        'dueDate': newDueDate,
        'lastUpdated': DateService.currentDate,
      });
      // Reschedule reminder for rescheduled instance
      try {
        final updatedInstance =
            await getUpdatedInstance(instanceId: instanceId, userId: uid);
        await ReminderScheduler.rescheduleReminderForInstance(updatedInstance);
      } catch (e) {}
      // Broadcast the instance update event
      final updatedInstance =
          await getUpdatedInstance(instanceId: instanceId, userId: uid);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
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
      await instanceRef.update({
        'dueDate': null,
        'lastUpdated': DateService.currentDate,
      });
      // Broadcast the instance update event
      final updatedInstance =
          await getUpdatedInstance(instanceId: instanceId, userId: uid);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
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
      final oldestInstances = await oldestQuery.get();
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
        final existingQuery = ActivityInstanceRecord.collectionForUser(uid)
            .where('templateId', isEqualTo: templateId)
            .where('dueDate', isEqualTo: currentDueDate)
            .where('status', isEqualTo: 'pending');
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
          final newInstanceQuery = ActivityInstanceRecord.collectionForUser(uid)
              .where('templateId', isEqualTo: templateId)
              .where('dueDate', isEqualTo: currentDueDate)
              .where('status', isEqualTo: 'pending');
          final newInstances = await newInstanceQuery.get();
          if (newInstances.docs.isNotEmpty) {
            await newInstances.docs.first.reference.update({
              'status': 'skipped',
              'skippedAt': now,
              'lastUpdated': now,
            });
          }
        }
        // Calculate next due date based on recurrence pattern
        final nextDueDate = _calculateNextDueDate(
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
          final nextProperDate = _calculateNextDueDate(
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
      rethrow;
    }
  }

  // ==================== HELPER METHODS ====================
  /// Calculate next due date based on template recurrence settings
  static DateTime? _calculateNextDueDate({
    required DateTime currentDueDate,
    required ActivityRecord template,
  }) {
    if (!template.isRecurring) return null;
    // Handle different frequency types
    switch (template.frequencyType) {
      case 'everyXPeriod':
        return _calculateEveryXPeriodNextDate(currentDueDate, template);
      case 'specificDays':
        return _calculateSpecificDaysNextDate(currentDueDate, template);
      case 'timesPerPeriod':
        return _calculateTimesPerPeriodNextDate(currentDueDate, template);
      default:
        return null;
    }
  }

  static DateTime? _calculateEveryXPeriodNextDate(
      DateTime currentDueDate, ActivityRecord template) {
    final everyXValue = template.everyXValue;
    final periodType = template.everyXPeriodType;
    switch (periodType) {
      case 'days':
        return currentDueDate.add(Duration(days: everyXValue));
      case 'weeks':
        return currentDueDate.add(Duration(days: everyXValue * 7));
      case 'months':
        return DateTime(
          currentDueDate.year,
          currentDueDate.month + everyXValue,
          currentDueDate.day,
        );
      case 'year':
        return DateTime(
          currentDueDate.year + everyXValue,
          currentDueDate.month,
          currentDueDate.day,
        );
      default:
        return null;
    }
  }

  static DateTime? _calculateSpecificDaysNextDate(
      DateTime currentDueDate, ActivityRecord template) {
    final specificDays = template.specificDays;
    if (specificDays.isEmpty) return null;
    // Find next occurrence of any of the specified days
    for (int i = 1; i <= 7; i++) {
      final candidate = currentDueDate.add(Duration(days: i));
      if (specificDays.contains(candidate.weekday)) {
        return candidate;
      }
    }
    return null;
  }

  static DateTime? _calculateTimesPerPeriodNextDate(
      DateTime currentDueDate, ActivityRecord template) {
    // For times per period, we need to find the next target date within the current period
    // If we're past the current period, move to the next period
    final periodType = template.periodType;
    final timesPerPeriod = template.timesPerPeriod;
    if (timesPerPeriod <= 0) return null;
    // Get the start of the current period
    DateTime periodStart;
    int periodLength;
    switch (periodType) {
      case 'days':
        periodStart = DateTime(
            currentDueDate.year, currentDueDate.month, currentDueDate.day);
        periodLength = 1;
        break;
      case 'weeks':
        // Find start of week (Sunday = 0)
        final daysSinceSunday = currentDueDate.weekday % 7;
        periodStart = DateTime(currentDueDate.year, currentDueDate.month,
            currentDueDate.day - daysSinceSunday);
        periodLength = 7;
        break;
      case 'months':
        periodStart = DateTime(currentDueDate.year, currentDueDate.month, 1);
        periodLength =
            DateTime(currentDueDate.year, currentDueDate.month + 1, 0).day;
        break;
      case 'year':
        periodStart = DateTime(currentDueDate.year, 1, 1);
        periodLength = 365;
        break;
      default:
        return null;
    }
    // Calculate target dates within the period
    final targetDates = <DateTime>[];
    for (int i = 0; i < timesPerPeriod; i++) {
      final progress = (i + 1) / timesPerPeriod; // 1/3, 2/3, 3/3
      final daysFromStart = (progress * periodLength).floor();
      final hoursFromStart = ((progress * periodLength) - daysFromStart) * 24;
      targetDates.add(DateTime(
        periodStart.year,
        periodStart.month,
        periodStart.day + daysFromStart,
        hoursFromStart.floor(),
        ((hoursFromStart - hoursFromStart.floor()) * 60).round(),
      ));
    }
    // Find the next target date after current due date
    for (final targetDate in targetDates) {
      if (targetDate.isAfter(currentDueDate)) {
        return targetDate;
      }
    }
    // If we're past all targets in this period, move to next period
    DateTime nextPeriodStart;
    switch (periodType) {
      case 'days':
        nextPeriodStart = periodStart.add(const Duration(days: 1));
        break;
      case 'weeks':
        nextPeriodStart = periodStart.add(const Duration(days: 7));
        break;
      case 'months':
        nextPeriodStart = DateTime(periodStart.year, periodStart.month + 1, 1);
        break;
      case 'year':
        nextPeriodStart = DateTime(periodStart.year + 1, 1, 1);
        break;
      default:
        return null;
    }
    // Calculate first target date in next period
    final firstProgress = 1.0 / timesPerPeriod;
    final daysFromStart = (firstProgress * periodLength).floor();
    final hoursFromStart =
        ((firstProgress * periodLength) - daysFromStart) * 24;
    return DateTime(
      nextPeriodStart.year,
      nextPeriodStart.month,
      nextPeriodStart.day + daysFromStart,
      hoursFromStart.floor(),
      ((hoursFromStart - hoursFromStart.floor()) * 60).round(),
    );
  }

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
        return periodStart.add(Duration(days: 6));
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
        print(
            'ActivityInstanceService: ERROR - Cannot generate next instance for ${instance.templateName}: windowEndDate is null');
        return;
      }

      // Get template for rate calculation
      final templateRef =
          ActivityRecord.collectionForUser(userId).doc(instance.templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) {
        print(
            'ActivityInstanceService: ERROR - Template ${instance.templateId} not found for ${instance.templateName}');
        return;
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);

      // Check if template is still active
      if (!template.isActive) {
        print(
            'ActivityInstanceService: Template ${instance.templateName} is not active, skipping instance generation');
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
          print(
              'ActivityInstanceService: Target already met for ${instance.templateName}, skipping instance generation');
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
          print(
              'ActivityInstanceService: Target already met for ${instance.templateName}, skipping instance generation');
          return;
        }
      }

      final nextWindowEndDate =
          nextBelongsToDate.add(Duration(days: nextWindowDuration - 1));

      // Check if instance already exists for this template and date
      final existingQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateId', isEqualTo: instance.templateId)
          .where('belongsToDate', isEqualTo: nextBelongsToDate)
          .where('status', isEqualTo: 'pending');
      final existingInstances = await existingQuery.get();
      if (existingInstances.docs.isNotEmpty) {
        print(
            'ActivityInstanceService: Instance already exists for ${instance.templateName} on ${nextBelongsToDate}, skipping creation');
        return; // Instance already exists, don't create duplicate
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
      );
      // Add to Firestore
      final newInstanceRef =
          await ActivityInstanceRecord.collectionForUser(userId)
              .add(nextInstanceData);
      print(
          'ActivityInstanceService: Generated next habit instance for ${instance.templateName} (${nextBelongsToDate} - ${nextWindowEndDate}), instanceId: ${newInstanceRef.id}');

      // Broadcast instance creation event for UI update
      try {
        final newInstance = await getUpdatedInstance(
          instanceId: newInstanceRef.id,
          userId: userId,
        );
        InstanceEvents.broadcastInstanceCreated(newInstance);
      } catch (e) {
        print(
            'ActivityInstanceService: Error broadcasting instance creation: $e');
      }
    } catch (e, stackTrace) {
      // Log error with stack trace for debugging
      print(
          'ActivityInstanceService: ERROR generating next habit instance for ${instance.templateName} (templateId: ${instance.templateId}): $e');
      print('Stack trace: $stackTrace');
      // Don't rethrow - we don't want to fail the completion, but log the error
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
      final nextDate = _calculateNextDueDate(
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
      int deletedCount = 0;
      for (final doc in instances.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.status == 'pending' &&
            instance.dueDate != null &&
            instance.dueDate!.isAfter(newEndDate)) {
          await doc.reference.delete();
          deletedCount++;
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
      int deletedCount = 0;
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
            deletedCount++;
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
}
