import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart'
    as schema;
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/reminder_scheduler.dart';
import 'package:habit_tracker/services/Activtity/recurrence_calculator.dart';
import 'activity_instance_utility_service.dart';
import 'activity_instance_creation_service.dart';
import 'activity_instance_completion_service.dart';

/// Helper service for activity instance calculations and utilities
class ActivityInstanceHelperService {
  /// Get current user ID
  static String getCurrentUserId() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return user.uid;
  }

  /// Get period start date
  static DateTime getPeriodStart(DateTime date, String periodType) {
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
  static DateTime getPeriodEnd(DateTime date, String periodType) {
    switch (periodType) {
      case 'weeks':
        final periodStart = getPeriodStart(date, periodType);
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
  static int getDaysRemainingInPeriod(DateTime currentDate, String periodType) {
    final periodEnd = getPeriodEnd(currentDate, periodType);
    final today =
        DateTime(currentDate.year, currentDate.month, currentDate.day);
    final endDate = DateTime(periodEnd.year, periodEnd.month, periodEnd.day);
    return endDate.difference(today).inDays + 1; // +1 to include today
  }

  /// Calculate days elapsed in current period
  static int getDaysElapsedInPeriod(DateTime currentDate, String periodType) {
    final periodStart = getPeriodStart(currentDate, periodType);
    final today =
        DateTime(currentDate.year, currentDate.month, currentDate.day);
    final startDate =
        DateTime(periodStart.year, periodStart.month, periodStart.day);
    return today.difference(startDate).inDays + 1; // +1 to include today
  }

  /// Get total days in a period
  static int getPeriodDays(String periodType) {
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
  static Future<int> getCompletedCountInPeriod({
    required String templateId,
    required String userId,
    required ActivityRecord template,
    required DateTime currentDate,
  }) async {
    if (template.frequencyType != 'timesPerPeriod') {
      return 0;
    }
    final periodStart = getPeriodStart(currentDate, template.periodType);
    final periodEnd = getPeriodEnd(currentDate, template.periodType);
    final instances = await ActivityInstanceRecord.collectionForUser(userId)
        .where('templateId', isEqualTo: templateId)
        .where('belongsToDate', isGreaterThanOrEqualTo: periodStart)
        .where('belongsToDate', isLessThanOrEqualTo: periodEnd)
        .get();
    int completedCount = 0;
    for (final doc in instances.docs) {
      final instance = ActivityInstanceRecord.fromSnapshot(doc);
      if (instance.templateTrackingType == 'binary') {
        final count = instance.currentValue ?? 0;
        completedCount += (count is num ? count.toInt() : 0);
        if (count == 0 && instance.status == 'completed') {
          completedCount += 1;
        }
      } else {
        if (instance.status == 'completed') {
          completedCount += 1;
        }
      }
    }
    return completedCount;
  }

  /// Calculate adaptive window duration for a habit based on its frequency
  static Future<int> calculateAdaptiveWindowDuration({
    required ActivityRecord template,
    required String userId,
    required DateTime currentDate,
  }) async {
    switch (template.frequencyType) {
      case 'everyXPeriod':
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
        final completedCount = await getCompletedCountInPeriod(
          templateId: template.reference.id,
          userId: userId,
          template: template,
          currentDate: currentDate,
        );
        final daysElapsed =
            getDaysElapsedInPeriod(currentDate, template.periodType);
        final targetRate =
            template.timesPerPeriod / getPeriodDays(template.periodType);
        final currentRate =
            daysElapsed > 0 ? completedCount / daysElapsed : 0.0;
        final rate = currentRate - targetRate;
        if (completedCount >= template.timesPerPeriod) {
          return 0; // Period target met, no new instance needed
        }
        if (rate >= 0) {
          final periodDays = getPeriodDays(template.periodType);
          final fixedWindow = (periodDays / template.timesPerPeriod).round();
          return fixedWindow;
        } else {
          final remainingCompletions = template.timesPerPeriod - completedCount;
          final daysRemaining =
              getDaysRemainingInPeriod(currentDate, template.periodType);
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
  static Future<void> generateNextHabitInstance(
    ActivityInstanceRecord instance,
    String userId,
  ) async {
    try {
      if (instance.windowEndDate == null) {
        return;
      }
      final templateRef =
          ActivityRecord.collectionForUser(userId).doc(instance.templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) {
        return;
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);
      if (!template.isActive) {
        return;
      }

      DateTime nextBelongsToDate;
      int nextWindowDuration;
      if (template.frequencyType == 'timesPerPeriod') {
        final completedCount = await getCompletedCountInPeriod(
          templateId: instance.templateId,
          userId: userId,
          template: template,
          currentDate: DateService.currentDate,
        );
        final daysElapsed = getDaysElapsedInPeriod(
            DateService.currentDate, template.periodType);
        final targetRate =
            template.timesPerPeriod / getPeriodDays(template.periodType);
        final currentRate =
            daysElapsed > 0 ? completedCount / daysElapsed : 0.0;
        final rate = currentRate - targetRate;

        if (rate >= 0) {
          nextBelongsToDate =
              instance.windowEndDate!.add(const Duration(days: 1));
        } else {
          nextBelongsToDate =
              DateService.currentDate.add(const Duration(days: 1));
        }
        nextWindowDuration = await calculateAdaptiveWindowDuration(
          template: template,
          userId: userId,
          currentDate: nextBelongsToDate,
        );
        if (nextWindowDuration == 0) {
          return;
        }
      } else {
        nextBelongsToDate =
            instance.windowEndDate!.add(const Duration(days: 1));
        nextWindowDuration = await calculateAdaptiveWindowDuration(
          template: template,
          userId: userId,
          currentDate: nextBelongsToDate,
        );
        if (nextWindowDuration == 0) {
          return;
        }
      }

      final nextWindowEndDate =
          nextBelongsToDate.add(Duration(days: nextWindowDuration - 1));
      try {
        final existingQuery = ActivityInstanceRecord.collectionForUser(userId)
            .where('templateId', isEqualTo: instance.templateId)
            .where('belongsToDate', isEqualTo: nextBelongsToDate);
        final existingInstances = await existingQuery.get();
        if (existingInstances.docs.isNotEmpty) {
          return; // Instance already exists (any status), don't create duplicate
        }
        final today = DateService.todayStart;
        final futurePendingQuery =
            ActivityInstanceRecord.collectionForUser(userId)
                .where('templateId', isEqualTo: instance.templateId)
                .where('status', isEqualTo: 'pending');
        final futurePendingSnapshot = await futurePendingQuery.get();
        final futurePendingInstances = futurePendingSnapshot.docs
            .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
            .where((inst) {
          if (inst.belongsToDate != null) {
            final belongsToDateOnly = DateTime(
              inst.belongsToDate!.year,
              inst.belongsToDate!.month,
              inst.belongsToDate!.day,
            );
            return belongsToDateOnly.isAtSameMomentAs(today) ||
                belongsToDateOnly.isAfter(today);
          }
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
        if (futurePendingInstances.isNotEmpty) {
          return;
        }
      } catch (e) {
        //
      }
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
        //
      }
      final nextInstanceData = schema.createActivityInstanceRecordData(
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
        queueOrder: queueOrder,
        habitsOrder: habitsOrder,
        tasksOrder: tasksOrder,
      );
      final tempRef = ActivityInstanceRecord.collectionForUser(userId)
          .doc('temp_${DateTime.now().millisecondsSinceEpoch}');
      final optimisticInstance = ActivityInstanceRecord.getDocumentFromData(
        nextInstanceData,
        tempRef,
      );
      final operationId = OptimisticOperationTracker.generateOperationId();
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: optimisticInstance.reference.id, // Use actual temp ID
        operationType: 'create',
        optimisticInstance: optimisticInstance,
        originalInstance:
            optimisticInstance, // For creation, use optimistic as original since there's no existing instance
      );
      InstanceEvents.broadcastInstanceCreatedOptimistic(
          optimisticInstance, operationId);
      try {
        final newInstanceRef =
            await ActivityInstanceRecord.collectionForUser(userId)
                .add(nextInstanceData);
        final newInstance = await getUpdatedInstance(
          instanceId: newInstanceRef.id,
          userId: userId,
        );
        OptimisticOperationTracker.reconcileInstanceCreation(
            operationId, newInstance);
      } catch (e) {
        OptimisticOperationTracker.rollbackOperation(operationId);
      }
    } catch (e) {
      //
    }
  }

  static int calculateMissingInstancesCount({
    required DateTime currentDueDate,
    required DateTime today,
    required ActivityRecord template,
  }) {
    if (!template.isRecurring) return 0;
    int count = 0;
    DateTime nextDueDate = currentDueDate;
    while (nextDueDate.isBefore(today)) {
      final nextDate = RecurrenceCalculator.calculateNextDueDate(
        currentDueDate: nextDueDate,
        template: template,
      );
      if (nextDate == null) break;
      if (nextDate.isBefore(today)) {
        count++;
        nextDueDate = nextDate;
      } else {
        break;
      }
    }
    return count;
  }

  /// Determine frequency type from instance data
  static String getFrequencyTypeFromInstance(ActivityInstanceRecord instance) {
    // For now, assume 'everyXPeriod' if we have everyXValue and everyXPeriodType
    if (instance.templateEveryXValue > 0 &&
        instance.templateEveryXPeriodType.isNotEmpty) {
      return 'everyXPeriod';
    }
    return 'everyXPeriod';
  }

  /// Get updated instance data after changes
  static Future<ActivityInstanceRecord> getUpdatedInstance({
    required String instanceId,
    String? userId,
  }) async {
    final uid = userId ?? getCurrentUserId();
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      return ActivityInstanceRecord.fromSnapshot(instanceDoc);
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getUpdatedInstance ($instanceId)',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static int calculateMissingInstancesFromInstance({
    required ActivityInstanceRecord instance,
    required DateTime today,
  }) {
    if (instance.dueDate == null) return 0;
    final template = ActivityRecord.getDocumentFromData(
      {
        'isRecurring': true,
        'frequencyType': getFrequencyTypeFromInstance(instance),
        'everyXValue': instance.templateEveryXValue,
        'everyXPeriodType': instance.templateEveryXPeriodType,
        'timesPerPeriod': instance.templateTimesPerPeriod,
        'periodType': instance.templatePeriodType,
        'specificDays':
            [], // Not cached in instance, would need to fetch template
      },
      instance.reference, // Use instance reference as placeholder
    );
    return calculateMissingInstancesCount(
      currentDueDate: instance.dueDate!,
      today: today,
      template: template,
    );
  }

  static Future<void> cleanupInstancesBeyondEndDate({
    required String templateId,
    required DateTime newEndDate,
    String? userId,
  }) async {
    final uid = userId ?? getCurrentUserId();
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId);
      final instances = await query.get();
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

  static Future<void> regenerateInstancesFromStartDate({
    required String templateId,
    required ActivityRecord template,
    required DateTime newStartDate,
    String? userId,
  }) async {
    final uid = userId ?? getCurrentUserId();
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId);
      final instances = await query.get();
      for (final doc in instances.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.status == 'pending') {
          bool shouldDelete = true;
          if (template.endDate != null && instance.dueDate != null) {
            if (instance.dueDate!.isAfter(template.endDate!)) {}
          }
          if (shouldDelete) {
            await doc.reference.delete();
          }
        }
      }
      if (template.categoryType == 'habit') {
        await ActivityInstanceCreationService.createActivityInstance(
          templateId: templateId,
          dueDate: newStartDate,
          dueTime: template.dueTime,
          template: template,
          userId: uid,
        );
      } else if (template.isRecurring) {
        await ActivityInstanceCreationService.createActivityInstance(
          templateId: templateId,
          dueDate: newStartDate,
          dueTime: template.dueTime,
          template: template,
          userId: uid,
        );
      } else {
        if (template.dueDate != null) {
          await ActivityInstanceCreationService.createActivityInstance(
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

  static Future<void> updateActivityInstancesCascade({
    required String templateId,
    required Map<String, dynamic> updates,
    required bool updateHistorical,
    String? userId,
  }) async {
    final uid = userId ?? getCurrentUserId();
    if (updates.isEmpty) return;
    final operationIds = <String, String>{}; // instanceId -> operationId

    try {
      final instances =
          await ActivityInstanceUtilityService.getInstancesForTemplate(
              templateId: templateId, userId: uid);
      final now = DateTime.now();
      final oneYearAgo = now.subtract(const Duration(days: 365));
      final batches = <List<ActivityInstanceRecord>>[];
      List<ActivityInstanceRecord> currentBatch = [];

      for (final instance in instances) {
        bool shouldUpdate = false;
        if (instance.status != 'completed' && instance.status != 'skipped') {
          shouldUpdate = true;
        } else if (updateHistorical) {
          final refDate =
              instance.completedAt ?? instance.dueDate ?? instance.createdTime;
          if (refDate != null && refDate.isAfter(oneYearAgo)) {
            shouldUpdate = true;
          }
        }

        if (shouldUpdate) {
          final optimisticInstance =
              InstanceEvents.createOptimisticPropertyUpdateInstance(
            instance,
            updates,
          );
          final operationId = OptimisticOperationTracker.generateOperationId();
          OptimisticOperationTracker.trackOperation(
            operationId,
            instanceId: instance.reference.id,
            operationType: 'propertyUpdate',
            optimisticInstance: optimisticInstance,
            originalInstance: instance,
          );
          InstanceEvents.broadcastInstanceUpdatedOptimistic(
              optimisticInstance, operationId);
          operationIds[instance.reference.id] = operationId;
          currentBatch.add(instance);
          if (currentBatch.length >= 450) {
            batches.add(List.from(currentBatch));
            currentBatch.clear();
          }
        }
      }
      if (currentBatch.isNotEmpty) batches.add(currentBatch);
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
            final operationId = operationIds[instanceId]!;
            OptimisticOperationTracker.rollbackOperation(operationId);
          }
        }
        final batchList = batches.expand((element) => element).toList();
        for (final instance in batchList) {
          if (instance.status != 'completed' && instance.status != 'skipped') {
            try {
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

          // Check if we need to auto-complete/uncomplete due to target change
          // ONLY for the current live instance (today) or future instances
          // STRICTLY PRESERVE HISTORICAL INSTANCES unless updateHistorical is true
          if (updates.containsKey('templateTarget')) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            bool isHistorical = false;

            if (instance.belongsToDate != null) {
              final belongsTo = DateTime(instance.belongsToDate!.year,
                  instance.belongsToDate!.month, instance.belongsToDate!.day);
              if (belongsTo.isBefore(today)) {
                isHistorical = true;
              }
            } else if (instance.dueDate != null) {
              final due = DateTime(instance.dueDate!.year,
                  instance.dueDate!.month, instance.dueDate!.day);
              if (due.isBefore(today)) {
                isHistorical = true;
              }
            } else if (instance.createdTime != null) {
              final created = DateTime(instance.createdTime!.year,
                  instance.createdTime!.month, instance.createdTime!.day);
              if (created.isBefore(today)) {
                isHistorical = true;
              }
            }

            // Only proceed if it's NOT historical OR if user explicitly requested historical update
            if (!isHistorical || updateHistorical) {
              final newTarget = updates['templateTarget'];
              // Re-fetch latest instance data to get current progress
              //(currentValue might have changed since the initial fetch at start of function)
              try {
                final refreshedDoc = await instance.reference.get();
                if (refreshedDoc.exists) {
                  final refreshedInstance =
                      ActivityInstanceRecord.fromSnapshot(refreshedDoc);
                  final dataset =
                      refreshedInstance.currentValue; // This is the progress
                  if (dataset is num && newTarget is num) {
                    if (dataset >= newTarget &&
                        refreshedInstance.status != 'completed') {
                      // Auto-complete
                      await ActivityInstanceCompletionService.completeInstance(
                        instanceId: refreshedInstance.reference.id,
                        userId: uid,
                      );
                    } else if (dataset < newTarget &&
                        refreshedInstance.status == 'completed') {
                      // Auto-uncomplete
                      await ActivityInstanceCompletionService
                          .uncompleteInstance(
                        instanceId: refreshedInstance.reference.id,
                        userId: uid,
                      );
                    }
                  }
                }
              } catch (e) {
                print(
                    'Error auto-updating status for ${instance.reference.id}: $e');
              }
            }
          }
        }
      } catch (e) {
        for (final operationId in operationIds.values) {
          OptimisticOperationTracker.rollbackOperation(operationId);
        }
        rethrow;
      }
    } catch (e) {
      for (final operationId in operationIds.values) {
        OptimisticOperationTracker.rollbackOperation(operationId);
      }
      rethrow;
    }
  }
}
