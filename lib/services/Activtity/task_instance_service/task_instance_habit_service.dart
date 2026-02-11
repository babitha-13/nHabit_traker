import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_instance_record.dart'
    as habit_schema;
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';
import 'package:habit_tracker/services/Activtity/recurrence_calculator.dart';
import 'package:habit_tracker/services/Activtity/habit_tracking_util.dart';
import 'package:habit_tracker/Helper/backend/cache/batch_read_service.dart';
import 'task_instance_helper_service.dart';

/// Service for habit instance operations
class TaskInstanceHabitService {
  /// Get all active habit instances for today and overdue
  static Future<List<habit_schema.HabitInstanceRecord>>
      getTodaysHabitInstances({
    String? userId,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
    final today = TaskInstanceHelperService.getTodayStart();
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
      // Batch read all templates first for efficiency
      final templateIds =
          instances.map((inst) => inst.templateId).toSet().toList();
      final templates = await BatchReadService.batchGetTemplates(
        templateIds: templateIds,
        userId: uid,
        useCache: true,
      );

      final activeInstances = <habit_schema.HabitInstanceRecord>[];
      for (final instance in instances) {
        try {
          final template = templates[instance.templateId];
          if (template == null) {
            continue; // Skip if template doesn't exist
          }
          // Check if habit is active based on date boundaries
          if (HabitTrackingUtil.isHabitActiveByDate(template, today)) {
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
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getTodaysHabitInstances (HabitInstanceRecord)',
        collectionName: 'habit_instances',
        stackTrace: stackTrace,
      );
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
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
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
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
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
          final nextDueDate = RecurrenceCalculator.calculateNextDueDate(
            currentDueDate: instance.dueDate!,
            template: template,
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
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
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
          final nextDueDate = RecurrenceCalculator.calculateNextDueDate(
            currentDueDate: instance.dueDate!,
            template: template,
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
}
