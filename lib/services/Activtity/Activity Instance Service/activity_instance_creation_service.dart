import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/services/Activtity/instance_date_calculator.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/reminder_scheduler.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart'
    as schema;
import 'activity_instance_helper_service.dart';

/// Service for creating activity instances
class ActivityInstanceCreationService {
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
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
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
      windowDuration =
          await ActivityInstanceHelperService.calculateAdaptiveWindowDuration(
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
    final instanceData = schema.createActivityInstanceRecordData(
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
      // Initialize originalDueDate with the initial due date
      originalDueDate: initialDueDate,
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

    // 3. Track operation with actual temp instance ID (not hardcoded 'temp')
    // This ensures rollback and reconciliation can find the optimistic instance
    OptimisticOperationTracker.trackOperation(
      operationId,
      instanceId: optimisticInstance.reference.id, // Use actual temp ID
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
}
