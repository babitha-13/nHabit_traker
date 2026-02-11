import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/reminder_scheduler.dart';
import 'package:habit_tracker/services/Activtity/Activity Instance Service/activity_instance_helper_service.dart';
import 'package:habit_tracker/services/Activtity/Activity Instance Service/activity_instance_completion_service.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';
import 'package:habit_tracker/services/Activtity/time_estimate_resolver.dart';

/// Service for updating instance progress and timer operations
class ActivityInstanceProgressService {
  /// Update instance progress (for quantitative tracking)
  static Future<void> updateInstanceProgress({
    required String instanceId,
    required dynamic currentValue,
    String? userId,
    DateTime? referenceTime,
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
                  final stackedTimes = await ActivityInstanceCompletionService
                      .calculateStackedStartTime(
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
              await ActivityInstanceCompletionService
                  .completeInstanceWithBackdate(
                instanceId: instanceId,
                finalValue: currentValue,
                userId: uid,
                completedAt: referenceTime,
              );
              // Reconcile this progress operation (completeInstance will reconcile its own)
              OptimisticOperationTracker.reconcileOperation(
                  operationId,
                  await ActivityInstanceHelperService.getUpdatedInstance(
                      instanceId: instanceId, userId: uid));
            } else {
              // Already completed, just reconcile the progress update
              final updatedInstance =
                  await ActivityInstanceHelperService.getUpdatedInstance(
                      instanceId: instanceId, userId: uid);
              OptimisticOperationTracker.reconcileOperation(
                  operationId, updatedInstance);
            }
          } else {
            // Auto-uncomplete if currently completed OR skipped and progress dropped below target
            if (instance.status == 'completed' ||
                instance.status == 'skipped') {
              // uncompleteInstance will handle its own optimistic broadcast
              await ActivityInstanceCompletionService.uncompleteInstance(
                instanceId: instanceId,
                userId: uid,
              );
              // Reconcile this progress operation (uncompleteInstance will reconcile its own)
              OptimisticOperationTracker.reconcileOperation(
                  operationId,
                  await ActivityInstanceHelperService.getUpdatedInstance(
                      instanceId: instanceId, userId: uid));
            } else {
              // Not completed, just reconcile progress update
              final updatedInstance =
                  await ActivityInstanceHelperService.getUpdatedInstance(
                      instanceId: instanceId, userId: uid);
              OptimisticOperationTracker.reconcileOperation(
                  operationId, updatedInstance);
            }
          }
        } else {
          // Reconcile the instance update event for progress changes
          final updatedInstance =
              await ActivityInstanceHelperService.getUpdatedInstance(
                  instanceId: instanceId, userId: uid);
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
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
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
            await ActivityInstanceHelperService.getUpdatedInstance(
                instanceId: instanceId, userId: uid);
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
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
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
              await ActivityInstanceHelperService.getUpdatedInstance(
                  instanceId: instanceId, userId: uid);
          await ReminderScheduler.rescheduleReminderForInstance(
              updatedInstance);
        } catch (e) {
          // Log error but don't fail - reminder rescheduling is non-critical
          print('Error rescheduling reminder for unsnoozed instance: $e');
        }
        // 6. Reconcile with actual data
        final updatedInstance =
            await ActivityInstanceHelperService.getUpdatedInstance(
                instanceId: instanceId, userId: uid);
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
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
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
            await ActivityInstanceHelperService.getUpdatedInstance(
                instanceId: instanceId, userId: uid);
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
              await ActivityInstanceHelperService.getUpdatedInstance(
                  instanceId: instanceId, userId: uid);
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
              await ActivityInstanceHelperService.getUpdatedInstance(
                  instanceId: instanceId, userId: uid);
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
}
