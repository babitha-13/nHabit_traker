import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/reminder_scheduler.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';
import 'package:habit_tracker/services/Activtity/recurrence_calculator.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart'
    as schema;
import 'activity_instance_helper_service.dart';
import 'activity_instance_creation_service.dart';

/// Service for scheduling, skipping, and rescheduling activity instances
class ActivityInstanceSchedulingService {
  /// Skip current instance and generate next if recurring
  static Future<void> skipInstance({
    required String instanceId,
    String? notes,
    String? userId,
    DateTime? skippedAt, // Optional backdated skip time
    bool skipAutoGeneration =
        false, // NEW: Prevent automatic next instance creation
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
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
      final optimisticInstance = InstanceEvents.createOptimisticSkippedInstance(
        instance,
        notes: notes,
      );
      final operationId = OptimisticOperationTracker.generateOperationId();
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'skip',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);
      try {
        await instanceRef.update({
          'status': 'skipped',
          'skippedAt': skipTime,
          'notes': notes ?? instance.notes,
          'lastUpdated': now,
        });
        if (!skipAutoGeneration) {
          if (instance.templateCategoryType == 'habit') {
            await ActivityInstanceHelperService.generateNextHabitInstance(
                instance, uid);
          } else {
            final templateRef =
                ActivityRecord.collectionForUser(uid).doc(instance.templateId);
            final templateDoc = await templateRef.get();
            if (templateDoc.exists) {
              final template = ActivityRecord.fromSnapshot(templateDoc);
              if (template.isRecurring && template.isActive) {
                final recurrenceAnchorDate =
                    instance.originalDueDate ?? instance.dueDate!;
                final nextDueDate = RecurrenceCalculator.calculateNextDueDate(
                  currentDueDate: recurrenceAnchorDate,
                  template: template,
                );
                if (nextDueDate != null) {
                  final newInstanceRef = await ActivityInstanceCreationService
                      .createActivityInstance(
                    templateId: instance.templateId,
                    dueDate: nextDueDate,
                    dueTime: template.dueTime,
                    template: template,
                    userId: uid,
                    sourceTag: 'skipInstance',
                  );
                  try {
                    final newInstance =
                        await ActivityInstanceHelperService.getUpdatedInstance(
                      instanceId: newInstanceRef.id,
                      userId: uid,
                    );
                    InstanceEvents.broadcastInstanceCreated(newInstance);
                  } catch (e) {
                    print('Error broadcasting instance created event: $e');
                  }
                }
              } else if (!template.isRecurring) {
                await templateRef.update({
                  'isActive': false,
                  'status': 'skipped',
                  'lastUpdated': now,
                });
              }
            }
          }
        }
        try {
          await ReminderScheduler.cancelReminderForInstance(instanceId);
        } catch (e) {
          print('Error canceling reminder for skipped instance: $e');
        }
        final updatedInstance =
            await ActivityInstanceHelperService.getUpdatedInstance(
                instanceId: instanceId, userId: uid);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
      } catch (e) {
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> batchSkipInstances({
    required List<ActivityInstanceRecord> instances,
    required DateTime skippedAt,
    required String userId,
  }) async {
    if (instances.isEmpty) return;

    final firestore = FirebaseFirestore.instance;
    const maxBatchSize = 500; // Firestore batch limit
    final now = DateService.currentDate;
    final templateIds = instances.map((i) => i.templateId).toSet().toList();
    final templateMap = <String, ActivityRecord>{};
    final templateFutures = templateIds.map((templateId) async {
      final templateRef =
          ActivityRecord.collectionForUser(userId).doc(templateId);
      final templateDoc = await templateRef.get();
      if (templateDoc.exists) {
        final template = ActivityRecord.fromSnapshot(templateDoc);
        return MapEntry(templateId, template);
      }
      return null;
    });

    final templateEntries = await Future.wait(templateFutures);
    for (final entry in templateEntries) {
      if (entry != null) {
        templateMap[entry.key] = entry.value;
      }
    }

    final nextInstanceDataList = <Map<String, dynamic>>[];
    final nextInstanceRefs = <DocumentReference>[];
    final nextInstanceFutures = instances
        .where((instance) =>
            instance.templateCategoryType == 'habit' &&
            instance.windowEndDate != null)
        .map((instance) async {
      try {
        final template = templateMap[instance.templateId];
        if (template == null || !template.isActive) return null;

        final nextBelongsToDateRaw =
            instance.windowEndDate!.add(const Duration(days: 1));
        final nextBelongsToDate = DateTime(
          nextBelongsToDateRaw.year,
          nextBelongsToDateRaw.month,
          nextBelongsToDateRaw.day,
        );
        final nextWindowDuration =
            await ActivityInstanceHelperService.calculateAdaptiveWindowDuration(
          template: template,
          userId: userId,
          currentDate: nextBelongsToDate,
        );
        if (nextWindowDuration <= 0) return null;
        final nextWindowEndDate =
            nextBelongsToDate.add(Duration(days: nextWindowDuration - 1));
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
          // Continue with null values if order lookup fails
        }

        final nextInstanceData = schema.createActivityInstanceRecordData(
          templateId: instance.templateId,
          dueDate: nextBelongsToDate,
          dueTime: instance.templateDueTime,
          status: 'pending',
          createdTime: now,
          lastUpdated: now,
          isActive: true,
          templateName: instance.templateName,
          templateCategoryId: instance.templateCategoryId,
          templateCategoryName: instance.templateCategoryName,
          templateCategoryType: instance.templateCategoryType,
          templatePriority: instance.templatePriority,
          templateTrackingType: instance.templateTrackingType,
          templateTarget: instance.templateTarget,
          templateUnit: instance.templateUnit,
          templateDescription: instance.templateDescription,
          templateTimeEstimateMinutes: instance.templateTimeEstimateMinutes,
          templateShowInFloatingTimer: instance.templateShowInFloatingTimer,
          templateIsRecurring: instance.templateIsRecurring,
          templateEveryXValue: instance.templateEveryXValue,
          templateEveryXPeriodType: instance.templateEveryXPeriodType,
          templateTimesPerPeriod: instance.templateTimesPerPeriod,
          templatePeriodType: instance.templatePeriodType,
          dayState: 'open',
          belongsToDate: nextBelongsToDate,
          windowEndDate: nextWindowEndDate,
          windowDuration: nextWindowDuration,
          queueOrder: queueOrder,
          habitsOrder: habitsOrder,
          tasksOrder: tasksOrder,
        );

        final nextInstanceRef = ActivityInstanceRecord.collectionForUser(userId)
            .doc(ActivityInstanceHelperService.buildHabitPendingDocId(
          templateId: instance.templateId,
          belongsToDate: nextBelongsToDate,
        ));
        return MapEntry(nextInstanceRef, nextInstanceData);
      } catch (e) {
        print('Error generating next instance for ${instance.templateId}: $e');
        return null;
      }
    });

    final nextInstanceResults = await Future.wait(nextInstanceFutures);
    final uniqueNextInstances =
        <String, MapEntry<DocumentReference, Map<String, dynamic>>>{};
    for (final result in nextInstanceResults) {
      if (result != null) {
        uniqueNextInstances[result.key.path] = result;
      }
    }
    for (final result in uniqueNextInstances.values) {
      nextInstanceRefs.add(result.key);
      nextInstanceDataList.add(result.value);
    }

    int nextInstanceIndex = 0;
    for (int batchStart = 0;
        batchStart < instances.length ||
            nextInstanceIndex < nextInstanceRefs.length;
        batchStart += maxBatchSize) {
      final batch = firestore.batch();
      int operationsInBatch = 0;
      final batchEnd = (batchStart + maxBatchSize < instances.length)
          ? batchStart + maxBatchSize
          : instances.length;

      for (int i = batchStart;
          i < batchEnd && operationsInBatch < maxBatchSize;
          i++) {
        final instance = instances[i];
        final instanceRef = instance.reference;
        batch.update(instanceRef, {
          'status': 'skipped',
          'skippedAt': skippedAt,
          'lastUpdated': now,
        });
        operationsInBatch++;
      }
      while (nextInstanceIndex < nextInstanceRefs.length &&
          operationsInBatch < maxBatchSize) {
        batch.set(nextInstanceRefs[nextInstanceIndex],
            nextInstanceDataList[nextInstanceIndex]);
        nextInstanceIndex++;
        operationsInBatch++;
      }
      if (operationsInBatch > 0) {
        await batch.commit();
      }
    }
    final reminderFutures = instances.map((instance) async {
      try {
        await ReminderScheduler.cancelReminderForInstance(
            instance.reference.id);
      } catch (e) {
        print('Error canceling reminder for ${instance.reference.id}: $e');
      }
    });
    await Future.wait(reminderFutures);
  }

  static Future<DocumentReference?> bulkSkipExpiredInstancesWithBatches({
    required ActivityInstanceRecord oldestInstance,
    required ActivityRecord template,
    required String userId,
  }) async {
    try {
      final yesterday = DateService.yesterdayStart;
      final now = DateService.currentDate;
      await skipInstance(
        instanceId: oldestInstance.reference.id,
        skippedAt: oldestInstance.windowEndDate ?? oldestInstance.dueDate,
        skipAutoGeneration: true,
        userId: userId,
      );
      final List<DateTime> allDueDates = [];
      DateTime currentDueDate = oldestInstance.originalDueDate ??
          oldestInstance.dueDate ??
          DateTime.now();
      while (currentDueDate.isBefore(yesterday.add(const Duration(days: 30)))) {
        allDueDates.add(currentDueDate);
        final nextDate = RecurrenceCalculator.calculateNextDueDate(
          currentDueDate: currentDueDate,
          template: template,
        );
        if (nextDate == null) break;
        currentDueDate = nextDate;
      }
      List<int> instancesToSkipIndices = [];
      int yesterdayInstanceIndex = -1;
      int nextValidInstanceIndex = -1;
      for (int i = 0; i < allDueDates.length; i++) {
        final dueDate = allDueDates[i];
        final windowDuration =
            await ActivityInstanceHelperService.calculateAdaptiveWindowDuration(
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
        if (windowEndNormalized.isBefore(yesterday)) {
          instancesToSkipIndices.add(i);
        } else if (windowEndNormalized.isAtSameMomentAs(yesterday)) {
          yesterdayInstanceIndex = i;
        } else if (windowEndNormalized.isAfter(yesterday) &&
            nextValidInstanceIndex == -1) {
          nextValidInstanceIndex = i;
          break; // Stop once we find the first future instance
        }
      }
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
            final windowDuration = await ActivityInstanceHelperService
                .calculateAdaptiveWindowDuration(
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

            final instanceData = schema.createActivityInstanceRecordData(
              templateId: template.reference.id,
              dueDate: dueDate,
              originalDueDate: dueDate,
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
      DocumentReference? pendingInstanceRef;
      if (yesterdayInstanceIndex >= 0) {
        final yesterdayDueDate = allDueDates[yesterdayInstanceIndex];
        pendingInstanceRef =
            await ActivityInstanceCreationService.createActivityInstance(
          templateId: template.reference.id,
          dueDate: yesterdayDueDate,
          template: template,
          userId: userId,
          sourceTag: 'bulkSkipExpiredInstancesWithBatches',
        );
      } else if (nextValidInstanceIndex >= 0) {
        final nextDueDate = allDueDates[nextValidInstanceIndex];
        pendingInstanceRef =
            await ActivityInstanceCreationService.createActivityInstance(
          templateId: template.reference.id,
          dueDate: nextDueDate,
          template: template,
          userId: userId,
          sourceTag: 'bulkSkipExpiredInstancesWithBatches',
        );
      } else {
        pendingInstanceRef =
            await ActivityInstanceCreationService.createActivityInstance(
          templateId: template.reference.id,
          template: template,
          userId: userId,
          sourceTag: 'bulkSkipExpiredInstancesWithBatches',
        );
      }
      return pendingInstanceRef;
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> rescheduleInstance({
    required String instanceId,
    required DateTime newDueDate,
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

      final optimisticInstance =
          InstanceEvents.createOptimisticRescheduledInstance(
        instance,
        newDueDate: newDueDate,
      );
      final operationId = OptimisticOperationTracker.generateOperationId();
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'reschedule',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);
      try {
        await instanceRef.update({
          'dueDate': newDueDate,
          'originalDueDate': instance.originalDueDate ?? instance.dueDate,
          'lastUpdated': DateService.currentDate,
        });
        await _syncTemplateDueDateForOneTimeTask(
          uid: uid,
          instance: instance,
          dueDate: newDueDate,
        );
        try {
          final updatedInstance =
              await ActivityInstanceHelperService.getUpdatedInstance(
                  instanceId: instanceId, userId: uid);
          await ReminderScheduler.rescheduleReminderForInstance(
              updatedInstance);
        } catch (e) {
          print('Error rescheduling reminder for rescheduled instance: $e');
        }
        final updatedInstance =
            await ActivityInstanceHelperService.getUpdatedInstance(
                instanceId: instanceId, userId: uid);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
      } catch (e) {
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
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

      final optimisticInstance =
          InstanceEvents.createOptimisticPropertyUpdateInstance(
        instance,
        {'dueDate': null},
      );
      final operationId = OptimisticOperationTracker.generateOperationId();
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'progress',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);
      try {
        await instanceRef.update({
          'dueDate': null,
          'lastUpdated': DateService.currentDate,
        });
        await _syncTemplateDueDateForOneTimeTask(
          uid: uid,
          instance: instance,
          dueDate: null,
        );
        final updatedInstance =
            await ActivityInstanceHelperService.getUpdatedInstance(
                instanceId: instanceId, userId: uid);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
      } catch (e) {
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> _syncTemplateDueDateForOneTimeTask({
    required String uid,
    required ActivityInstanceRecord instance,
    required DateTime? dueDate,
  }) async {
    final isOneTimeTask = instance.templateCategoryType == 'task' &&
        !instance.templateIsRecurring;
    if (!isOneTimeTask) return;

    try {
      final templateRef =
          ActivityRecord.collectionForUser(uid).doc(instance.templateId);
      await templateRef.update({
        'dueDate': dueDate,
        'lastUpdated': DateService.currentDate,
      });
    } catch (e) {
      // Best-effort sync; instance update already succeeded.
      print('Failed to sync template dueDate after instance reschedule: $e');
    }
  }

  /// Skip all instances until a specific date
  static Future<void> skipInstancesUntil({
    required String templateId,
    required DateTime untilDate,
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      final templateRef = ActivityRecord.collectionForUser(uid).doc(templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) {
        throw Exception('Template not found');
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);
      final now = DateService.currentDate;
      final oldestQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId)
          .where('status', isEqualTo: 'pending')
          .orderBy('dueDate', descending: false)
          .limit(1);
      final oldestInstances = await oldestQuery.get().catchError((e) {
        if (e.toString().contains('index') ||
            e.toString().contains('https://')) {
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
      while (currentDueDate.isBefore(untilDate)) {
        try {
          final existingQuery = ActivityInstanceRecord.collectionForUser(uid)
              .where('templateId', isEqualTo: templateId)
              .where('status', isEqualTo: 'pending')
              .where('dueDate', isEqualTo: currentDueDate);
          final existingInstances = await existingQuery.get();
          if (existingInstances.docs.isNotEmpty) {
            final existingInstance = existingInstances.docs.first;
            await existingInstance.reference.update({
              'status': 'skipped',
              'skippedAt': now,
              'lastUpdated': now,
            });
          } else {
            await ActivityInstanceCreationService.createActivityInstance(
              templateId: templateId,
              dueDate: currentDueDate,
              dueTime: template.dueTime,
              template: template,
              userId: uid,
              sourceTag: 'skipInstancesUntil',
            );
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
          if (e.toString().contains('index') ||
              e.toString().contains('https://')) {
            print('   Click the link to create the index automatically.');
          }
          rethrow;
        }
        final nextDueDate = RecurrenceCalculator.calculateNextDueDate(
          currentDueDate: currentDueDate,
          template: template,
        );
        if (nextDueDate == null) {
          break;
        }
        currentDueDate = nextDueDate;
      }
      try {
        final futureQuery = ActivityInstanceRecord.collectionForUser(uid)
            .where('templateId', isEqualTo: templateId)
            .where('status', isEqualTo: 'pending')
            .where('dueDate', isGreaterThanOrEqualTo: untilDate);
        final futureInstances = await futureQuery.get();
        if (futureInstances.docs.isEmpty) {
          if (currentDueDate.isAtSameMomentAs(untilDate) ||
              currentDueDate.isAfter(untilDate)) {
            await ActivityInstanceCreationService.createActivityInstance(
              templateId: templateId,
              dueDate: currentDueDate,
              dueTime: template.dueTime,
              template: template,
              userId: uid,
              sourceTag: 'skipInstancesUntil',
            );
          } else {
            final nextProperDate = RecurrenceCalculator.calculateNextDueDate(
              currentDueDate: currentDueDate,
              template: template,
            );
            if (nextProperDate != null) {
              await ActivityInstanceCreationService.createActivityInstance(
                templateId: templateId,
                dueDate: nextProperDate,
                dueTime: template.dueTime,
                template: template,
                userId: uid,
                sourceTag: 'skipInstancesUntil',
              );
            }
          }
        }
      } catch (e) {
        if (e.toString().contains('index') ||
            e.toString().contains('https://')) {
          print('   Click the link to create the index automatically.');
        }
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }
}
