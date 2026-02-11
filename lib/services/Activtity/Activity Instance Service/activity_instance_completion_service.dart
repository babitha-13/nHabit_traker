import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/reminder_scheduler.dart';
import 'package:habit_tracker/services/Activtity/time_estimate_resolver.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';
import 'package:habit_tracker/services/Activtity/recurrence_calculator.dart';
import 'activity_instance_helper_service.dart';
import 'activity_instance_creation_service.dart';

/// Result of calculating stacked session times
class StackedSessionTimes {
  final DateTime startTime;
  final DateTime endTime;

  StackedSessionTimes({
    required this.startTime,
    required this.endTime,
  });
}

/// Service for completing and uncompleting activity instances
class ActivityInstanceCompletionService {
  static int calculateCompletionDuration(
    ActivityInstanceRecord instance,
    DateTime completedAt, {
    int? effectiveEstimateMinutes,
  }) {
    if (instance.timeLogSessions.isNotEmpty) {
      return 0; // Signal to skip creation
    }
    if (effectiveEstimateMinutes == null) {
      return 0;
    }
    final estimateMs =
        effectiveEstimateMinutes * 60000; // Convert to milliseconds
    final trackingType = instance.templateTrackingType;
    if (trackingType == 'time') {
      final accumulatedMs = instance.accumulatedTime > 0
          ? instance.accumulatedTime
          : (instance.totalTimeLogged > 0 ? instance.totalTimeLogged : 0);
      if (accumulatedMs > 0) {
        return accumulatedMs;
      }
      return estimateMs;
    } else if (trackingType == 'quantitative') {
      return estimateMs;
    } else {
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
      if (e.toString().contains('index') || e.toString().contains('https://')) {
        print('   Click the link to create the index automatically.');
      }
      return [];
    }
  }

  static Future<StackedSessionTimes> calculateStackedStartTime({
    required String userId,
    required DateTime completionTime,
    required int durationMs,
    required String instanceId,
    int? effectiveEstimateMinutes,
  }) async {
    final simultaneous = await findSimultaneousCompletions(
      userId: userId,
      completionTime: completionTime,
      excludeInstanceId: instanceId,
    );

    if (simultaneous.isEmpty) {
      final startTime =
          completionTime.subtract(Duration(milliseconds: durationMs));
      return StackedSessionTimes(
        startTime: startTime,
        endTime: completionTime,
      );
    }
    int totalDurationMs = 0;
    for (final item in simultaneous) {
      if (item.timeLogSessions.isNotEmpty) {
        final lastSession = item.timeLogSessions.last;
        final sessionDuration =
            lastSession['durationMilliseconds'] as int? ?? 0;
        totalDurationMs += sessionDuration;
      } else {
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
            //
          }
        }
        final itemEffectiveEstimate =
            await TimeEstimateResolver.getEffectiveEstimateMinutes(
          userId: userId,
          trackingType: item.templateTrackingType,
          target: item.templateTarget,
          hasExplicitSessions: item.timeLogSessions.isNotEmpty,
          template: itemTemplate,
        );
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
    bool skipOptimisticUpdate =
        false, // Skip optimistic broadcast if caller already handled it
  }) async {
    await completeInstanceWithBackdate(
      instanceId: instanceId,
      finalValue: finalValue,
      finalAccumulatedTime: finalAccumulatedTime,
      notes: notes,
      userId: userId,
      completedAt: null, // Use current time
      skipOptimisticUpdate: skipOptimisticUpdate,
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
    bool skipOptimisticUpdate =
        false, // Skip optimistic broadcast if caller already handled it
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
      final completionTime = completedAt ?? now;
      final existingSessions =
          List<Map<String, dynamic>>.from(instance.timeLogSessions);
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
          //
        }
      }
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
      dynamic currentValueToStore = resolvedFinalValue;
      if (instance.templateTrackingType != 'time' &&
          resolvedFinalValue is num) {
        final double val = resolvedFinalValue.toDouble();
        final double accTime =
            (finalAccumulatedTime ?? instance.accumulatedTime).toDouble();
        if (val > 1000 && val == accTime) {
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
        final totalTime = existingSessions.fold<int>(
          0,
          (sum, session) =>
              sum + (session['durationMilliseconds'] as int? ?? 0),
        );
        updateData['timeLogSessions'] = existingSessions;
        updateData['totalTimeLogged'] = totalTime;
      }
      String? operationId;
      if (!skipOptimisticUpdate) {
        final optimisticTimeLogSessions =
            updateData['timeLogSessions'] as List<Map<String, dynamic>>?;
        final optimisticTotalTimeLogged = updateData['totalTimeLogged'] as int?;
        final optimisticInstance =
            InstanceEvents.createOptimisticCompletedInstance(
          instance,
          finalValue: currentValueToStore,
          finalAccumulatedTime:
              finalAccumulatedTime ?? instance.accumulatedTime,
          completedAt: completionTime,
          timeLogSessions: optimisticTimeLogSessions,
          totalTimeLogged: optimisticTotalTimeLogged,
        );
        operationId = OptimisticOperationTracker.generateOperationId();
        OptimisticOperationTracker.trackOperation(
          operationId,
          instanceId: instanceId,
          operationType: 'complete',
          optimisticInstance: optimisticInstance,
          originalInstance: instance,
        );
        InstanceEvents.broadcastInstanceUpdatedOptimistic(
            optimisticInstance, operationId);
      }
      try {
        await instanceRef.update(updateData);
        final updatedInstance =
            await ActivityInstanceHelperService.getUpdatedInstance(
                instanceId: instanceId, userId: uid);
        if (operationId != null) {
          OptimisticOperationTracker.reconcileOperation(
              operationId, updatedInstance);
        } else if (!skipOptimisticUpdate) {
          InstanceEvents.broadcastInstanceUpdated(updatedInstance);
        }
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
                'status': 'complete',
                'lastUpdated': now,
              });
            }
          }
        }
        try {
          await ReminderScheduler.cancelReminderForInstance(instanceId);
        } catch (e) {
          //
        }
      } catch (e) {
        if (operationId != null) {
          OptimisticOperationTracker.rollbackOperation(operationId);
        }
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> uncompleteInstance({
    required String instanceId,
    String? userId,
    bool deleteLogs = false, // New parameter to optionally delete calendar logs
    bool skipOptimisticUpdate =
        false, // Skip optimistic broadcast if caller already handled it
    dynamic currentValue, // Optional: Update current value while uncompleting
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
      if (instance.templateCategoryType == 'habit') {
        try {
          final futureInstancesQuery =
              ActivityInstanceRecord.collectionForUser(uid)
                  .where('templateId', isEqualTo: instance.templateId)
                  .where('status', isEqualTo: 'pending')
                  .where('belongsToDate',
                      isGreaterThan: instance.belongsToDate);

          final futureInstances = await futureInstancesQuery.get();
          final List<DocumentSnapshot> docsToDelete = [...futureInstances.docs];
          if (instance.dueDate != null) {
            try {
              final futureByDateQuery =
                  ActivityInstanceRecord.collectionForUser(uid)
                      .where('templateId', isEqualTo: instance.templateId)
                      .where('status', isEqualTo: 'pending')
                      .where('dueDate', isGreaterThan: instance.dueDate);
              final futureByDate = await futureByDateQuery.get();
              for (final doc in futureByDate.docs) {
                if (!docsToDelete.any((d) => d.id == doc.id)) {
                  docsToDelete.add(doc);
                }
              }
            } catch (e) {
              //
            }
          }
          for (final doc in docsToDelete) {
            final deletedInstance = ActivityInstanceRecord.fromSnapshot(doc);
            await doc.reference.delete();
            InstanceEvents.broadcastInstanceDeleted(deletedInstance);
          }
        } catch (e) {
          if (e.toString().contains('index') ||
              e.toString().contains('https://')) {
            print('   Click the link to create the index automatically.');
          }
          rethrow;
        }
      }
      if (instance.templateCategoryType == 'task' &&
          instance.templateIsRecurring &&
          instance.dueDate != null) {
        try {
          final futureTasksQuery = ActivityInstanceRecord.collectionForUser(uid)
              .where('templateId', isEqualTo: instance.templateId)
              .where('status', isEqualTo: 'pending')
              .where('dueDate', isGreaterThan: instance.dueDate);
          final futureTasks = await futureTasksQuery.get();
          for (final doc in futureTasks.docs) {
            final deletedInstance = ActivityInstanceRecord.fromSnapshot(doc);
            await doc.reference.delete();
            InstanceEvents.broadcastInstanceDeleted(deletedInstance);
          }
        } catch (e) {
          try {
            final allPendingTasks =
                ActivityInstanceRecord.collectionForUser(uid)
                    .where('templateId', isEqualTo: instance.templateId)
                    .where('status', isEqualTo: 'pending')
                    .get();
            final results = await allPendingTasks;
            for (final doc in results.docs) {
              final task = ActivityInstanceRecord.fromSnapshot(doc);
              if (task.dueDate != null &&
                  instance.dueDate != null &&
                  task.dueDate!.isAfter(instance.dueDate!)) {
                await doc.reference.delete();
                InstanceEvents.broadcastInstanceDeleted(task);
              }
            }
          } catch (e2) {
            print('Error in fallback cleanup for tasks: $e2');
          }
        }
      }

      String? operationId;
      if (!skipOptimisticUpdate) {
        final optimisticInstance =
            InstanceEvents.createOptimisticUncompletedInstance(instance);
        operationId = OptimisticOperationTracker.generateOperationId();
        OptimisticOperationTracker.trackOperation(
          operationId,
          instanceId: instanceId,
          operationType: 'uncomplete',
          optimisticInstance: optimisticInstance,
          originalInstance: instance,
        );
        InstanceEvents.broadcastInstanceUpdatedOptimistic(
            optimisticInstance, operationId);
      }
      final updateData = <String, dynamic>{
        'status': 'pending',
        'completedAt': null,
        'skippedAt': null,
        'lastUpdated': DateService.currentDate,
      };

      if (currentValue != null) {
        updateData['currentValue'] = currentValue;
      }
      if (deleteLogs) {
        updateData['timeLogSessions'] = [];
        updateData['totalTimeLogged'] = 0;
        updateData['accumulatedTime'] = 0;
        updateData['currentValue'] = 0;
      }
      try {
        await instanceRef.update(updateData);
        if (instance.templateCategoryType == 'task') {
          final templateRef =
              ActivityRecord.collectionForUser(uid).doc(instance.templateId);
          final templateDoc = await templateRef.get();
          if (templateDoc.exists) {
            final template = ActivityRecord.fromSnapshot(templateDoc);
            if (!template.isRecurring && !template.isActive) {
              await templateRef.update({
                'isActive': true,
                'status': 'incomplete',
                'lastUpdated': DateService.currentDate,
              });
            }
          }
        }

        final updatedInstance =
            await ActivityInstanceHelperService.getUpdatedInstance(
                instanceId: instanceId, userId: uid);
        if (operationId != null) {
          OptimisticOperationTracker.reconcileOperation(
              operationId, updatedInstance);
        } else if (!skipOptimisticUpdate) {
          InstanceEvents.broadcastInstanceUpdated(updatedInstance);
        }
      } catch (e) {
        if (operationId != null) {
          OptimisticOperationTracker.rollbackOperation(operationId);
        }
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }
}
