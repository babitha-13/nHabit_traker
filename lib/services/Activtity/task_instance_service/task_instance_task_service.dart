import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';
import 'package:habit_tracker/services/Activtity/recurrence_calculator.dart';
import 'package:habit_tracker/services/Activtity/template_sync_helper.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';
import 'task_instance_helper_service.dart';

/// Service for task instance operations
class TaskInstanceTaskService {
  static Future<ActivityInstanceRecord> _getInstanceServerFirst(
    DocumentReference instanceRef,
  ) async {
    try {
      final serverDoc = await instanceRef.get(
        const GetOptions(source: Source.server),
      );
      if (serverDoc.exists) {
        return ActivityInstanceRecord.fromSnapshot(serverDoc);
      }
    } catch (_) {
      // Fallback to cache when server read is temporarily unavailable.
    }

    final cacheDoc = await instanceRef.get(
      const GetOptions(source: Source.cache),
    );
    if (!cacheDoc.exists) {
      throw Exception('Task instance not found');
    }
    return ActivityInstanceRecord.fromSnapshot(cacheDoc);
  }

  /// Get all active activity instances for today and overdue
  static Future<List<ActivityInstanceRecord>> getTodaysTaskInstances({
    String? userId,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
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
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
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
      templateTimeEstimateMinutes: template.timeEstimateMinutes,
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
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
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

      // Resolve finalValue to prevent time storage in non-time tasks
      dynamic currentValueToStore = finalValue;
      if (instance.templateTrackingType != 'time' && finalValue is num) {
        final double val = finalValue.toDouble();
        final double accTime =
            (finalAccumulatedTime ?? instance.accumulatedTime).toDouble();
        if (val > 1000 && val == accTime) {
          if (instance.templateCategoryType == 'essential') {
            currentValueToStore = 1;
          } else if (instance.templateTrackingType == 'binary') {
            currentValueToStore = 1;
          } else {
            currentValueToStore = instance.currentValue;
          }
        }
      }

      // ==================== OPTIMISTIC BROADCAST ====================
      // 1. Create optimistic instance
      final optimisticInstance =
          InstanceEvents.createOptimisticCompletedInstance(
        instance,
        finalValue: currentValueToStore,
        finalAccumulatedTime: finalAccumulatedTime ?? instance.accumulatedTime,
        completedAt: now,
      );

      // 2. Generate operation ID
      final operationId = OptimisticOperationTracker.generateOperationId();

      // 3. Track operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'complete',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );

      // 4. Broadcast optimistically (IMMEDIATE)
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);

      // 5. Perform backend update
      try {
        await instanceRef.update({
          'status': 'completed',
          'completedAt': now,
          'currentValue': currentValueToStore,
          'accumulatedTime': finalAccumulatedTime ?? instance.accumulatedTime,
          'notes': notes ?? instance.notes,
          'lastUpdated': now,
        });

        // 6. Reconcile with actual data
        final updatedInstance = await _getInstanceServerFirst(instanceRef);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);

        // Get the template to check if it's recurring - check cache first
        final cache = FirestoreCacheService();
        ActivityRecord? template = cache.getCachedTemplate(instance.templateId);
        if (template == null) {
          final templateRef =
              ActivityRecord.collectionForUser(uid).doc(instance.templateId);
          final templateDoc = await templateRef.get();
          if (templateDoc.exists) {
            template = ActivityRecord.fromSnapshot(templateDoc);
            cache.cacheTemplate(instance.templateId, template);
          }
        }
        if (template != null) {
          final templateRef = template.reference;
          // Generate next instance if task is recurring and still active
          if (template.isRecurring &&
              template.isActive &&
              template.frequencyType.isNotEmpty &&
              instance.dueDate != null) {
            final nextDueDate = RecurrenceCalculator.calculateNextDueDate(
              currentDueDate: instance.dueDate!,
              template: template,
            );
            if (nextDueDate != null) {
              await createTaskInstance(
                templateId: instance.templateId,
                dueDate: nextDueDate,
                template: template,
                userId: uid,
              );
              // Also update the template with the next due date
              await TemplateSyncHelper.updateTemplateDueDate(
                templateRef: templateRef,
                dueDate: nextDueDate,
              );
            } else {
              // No more occurrences, clear dueDate on template
              await TemplateSyncHelper.updateTemplateDueDate(
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
        // 7. Rollback on error
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
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
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
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
      // Get the template to check if it's recurring - check cache first
      final cache = FirestoreCacheService();
      ActivityRecord? template = cache.getCachedTemplate(instance.templateId);
      if (template == null) {
        final templateRef =
            ActivityRecord.collectionForUser(uid).doc(instance.templateId);
        final templateDoc = await templateRef.get();
        if (templateDoc.exists) {
          template = ActivityRecord.fromSnapshot(templateDoc);
          cache.cacheTemplate(instance.templateId, template);
        }
      }
      if (template != null) {
        final templateRef = template.reference;
        // Generate next instance if task is recurring
        if (template.isRecurring &&
            template.frequencyType.isNotEmpty &&
            instance.dueDate != null) {
          final nextDueDate = RecurrenceCalculator.calculateNextDueDate(
            currentDueDate: instance.dueDate!,
            template: template,
          );
          if (nextDueDate != null) {
            await createTaskInstance(
              templateId: instance.templateId,
              dueDate: nextDueDate,
              template: template,
              userId: uid,
            );
            // Also update the template with the next due date
            await TemplateSyncHelper.updateTemplateDueDate(
              templateRef: templateRef,
              dueDate: nextDueDate,
            );
          } else {
            // No more occurrences, clear dueDate on template
            await TemplateSyncHelper.updateTemplateDueDate(
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
}
