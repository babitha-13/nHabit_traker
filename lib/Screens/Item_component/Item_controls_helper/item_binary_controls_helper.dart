import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/Helpers/sound_helper.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/optimistic_operation_tracker.dart';

class ItemBinaryControlsHelper {
  static Future<void> handleBinaryCompletion({
    required bool completed,
    required ActivityInstanceRecord instance,
    required bool isUpdating,
    required bool treatAsBinary,
    required DateTime? progressReferenceTime,
    required Function(bool) setUpdating,
    required Function(bool?) setBinaryOverride,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required Future<void> Function()? onRefresh,
    required BuildContext context,
    required Future<String?> Function() showUncompleteDialog,
    required num currentProgressLocal,
    required bool Function() isMounted,
    required void Function(VoidCallback) setState,
  }) async {
    if (isUpdating) return;
    bool deleteLogs = false;
    if (!completed && instance.timeLogSessions.isNotEmpty) {
      final userChoice = await showUncompleteDialog();
      if (userChoice == null || userChoice == 'cancel') {
        return;
      }
      deleteLogs = userChoice == 'delete';
    }
    if (isMounted()) {
      setState(() {
        setUpdating(true);
        setBinaryOverride(completed);
      });
    }

    // Calculate target values before creating optimistic instance
    dynamic targetValue = 1;
    int? targetAccumulatedTime;
    dynamic undoValue = 0;

    if (completed) {
      if (instance.templateTrackingType == 'quantitative') {
        if (treatAsBinary) {
          targetValue = currentProgressLocal + 1;
        } else {
          targetValue = instance.templateTarget ?? 1;
        }
      } else if (instance.templateTrackingType == 'time') {
        final targetMinutes = instance.templateTarget ?? 1;
        targetAccumulatedTime = (targetMinutes * 60000).toInt();
        targetValue = targetAccumulatedTime;
      }
    } else {
      if (treatAsBinary && instance.templateTrackingType == 'quantitative') {
        undoValue = (currentProgressLocal - 1).clamp(0, double.infinity);
      }
    }

    // Generate operation ID for tracking
    final operationId = OptimisticOperationTracker.generateOperationId();

    // Create optimistic instance IMMEDIATELY for instant UI update
    ActivityInstanceRecord optimisticInstance;
    if (completed) {
      optimisticInstance = InstanceEvents.createOptimisticCompletedInstance(
        instance,
        finalValue: targetValue,
        finalAccumulatedTime: targetAccumulatedTime,
      );
    } else {
      optimisticInstance = InstanceEvents.createOptimisticUncompletedInstance(
        instance,
      );
      // For uncompletion, also update progress if needed
      if (treatAsBinary && instance.templateTrackingType == 'quantitative') {
        optimisticInstance = InstanceEvents.createOptimisticProgressInstance(
          optimisticInstance,
          currentValue: undoValue,
        );
      }
    }

    // Track the optimistic operation
    OptimisticOperationTracker.trackOperation(
      operationId,
      instanceId: instance.reference.id,
      operationType: completed ? 'complete' : 'uncomplete',
      optimisticInstance: optimisticInstance,
      originalInstance: instance,
    );

    // IMMEDIATE UI UPDATE: Broadcast optimistic update and update local state
    InstanceEvents.broadcastInstanceUpdatedOptimistic(
      optimisticInstance,
      operationId,
    );
    // Update queue page immediately
    onInstanceUpdated(optimisticInstance);

    try {
      // Play sound
      SoundHelper().playCompletionSound();

      // Perform backend operations (non-blocking for UI)
      if (completed) {
        // For non-quantitative tasks, we can combine update and complete into a single call
        // to prevent status flicker (pending -> completed) caused by the intermediate updateInstanceProgress
        if (instance.templateTrackingType != 'quantitative') {
          await ActivityInstanceService.completeInstance(
            instanceId: instance.reference.id,
            finalValue: targetValue,
            finalAccumulatedTime: targetAccumulatedTime,
            skipOptimisticUpdate: true,
          );
        } else {
          await ActivityInstanceService.updateInstanceProgress(
            instanceId: instance.reference.id,
            currentValue: targetValue,
            referenceTime: progressReferenceTime,
          );
          await ActivityInstanceService.completeInstance(
            instanceId: instance.reference.id,
            finalAccumulatedTime: targetAccumulatedTime,
            skipOptimisticUpdate:
                true, // Skip - we already broadcasted optimistically above
          );
        }
      } else {
        // For non-quantitative tasks, combine update and uncomplete to prevent flicker
        if (instance.templateTrackingType != 'quantitative') {
          await ActivityInstanceService.uncompleteInstance(
            instanceId: instance.reference.id,
            deleteLogs: deleteLogs,
            skipOptimisticUpdate: true,
            currentValue: undoValue,
          );
        } else {
          await ActivityInstanceService.updateInstanceProgress(
            instanceId: instance.reference.id,
            currentValue: undoValue,
            referenceTime: progressReferenceTime,
          );
          await ActivityInstanceService.uncompleteInstance(
            instanceId: instance.reference.id,
            deleteLogs: deleteLogs,
            skipOptimisticUpdate:
                true, // Skip - we already broadcasted optimistically above
          );
        }
      }

      // Get actual instance from backend and reconcile
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );

      // Reconcile optimistic update with actual backend data
      OptimisticOperationTracker.reconcileOperation(
        operationId,
        updatedInstance,
      );

      // Update with actual instance (in case there are any differences)
      onInstanceUpdated(updatedInstance);

      if (instance.templateCategoryType == 'habit' && completed) {
        onRefresh?.call();
      }
    } catch (e) {
      // Rollback optimistic update on error
      OptimisticOperationTracker.rollbackOperation(operationId);

      // Restore original instance
      onInstanceUpdated(instance);
      if (isMounted()) {
        setState(() {
          setBinaryOverride(null);
        });
      }
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating completion: $e')),
        );
      }
    } finally {
      if (isMounted()) {
        setState(() {
          setUpdating(false);
        });
      }
    }
  }
}
