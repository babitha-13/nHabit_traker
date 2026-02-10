import 'dart:async';

import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/optimistic_operation_tracker.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/sound_helper.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

class ItemQuantitativeControlsHelper {
  // EXACT copy of your _showQuantControlsMenu logic
  static Future<void> showQuantControlsMenu({
    required BuildContext context,
    required BuildContext anchorContext,
    required ActivityInstanceRecord instance,
    required bool canDecrement,
    required num Function() currentProgressLocal,
    required num Function() getTargetValue,
    required Future<void> Function() resetQuantity,
    required Future<void> Function(int) updateProgress,
  }) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    final current = currentProgressLocal();
    final target = getTargetValue();
    final remaining = target - current;
    final canMarkComplete = remaining > 0;
    final selected = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        overlay.size.width - position.dx - size.width,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'reset',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 8),
              Text('Reset to Zero')
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        const PopupMenuItem<String>(
          value: 'inc',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 8),
              Text('Increase by 1')
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'dec',
          enabled: canDecrement,
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.remove, size: 18),
              SizedBox(width: 8),
              Text('Decrease by 1')
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
          value: 'complete',
          enabled: canMarkComplete,
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 18),
              const SizedBox(width: 8),
              Text('Mark as Complete${canMarkComplete ? ' (+$remaining)' : ''}')
            ],
          ),
        ),
      ],
    );
    if (selected == null) return;
    if (selected == 'reset') {
      await resetQuantity();
    } else if (selected == 'inc') {
      await updateProgress(1);
    } else if (selected == 'dec' && canDecrement) {
      await updateProgress(-1);
    } else if (selected == 'complete' && canMarkComplete) {
      await updateProgress(remaining.toInt());
    }
  }

  // EXACT copy of your _resetQuantity logic
  static Future<void> resetQuantity({
    required ActivityInstanceRecord instance,
    required bool isUpdating,
    required DateTime? progressReferenceTime,
    required Function(bool) setUpdating,
    required Function(int?) setQuantProgressOverride,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required Future<void> Function()? onRefresh,
    required BuildContext context,
    required bool Function() isMounted,
    required void Function(VoidCallback) setState,
    required Future<String?> Function() showUncompleteDialog,
  }) async {
    if (isUpdating) return;
    setState(() {
      setUpdating(true);
      setQuantProgressOverride(null);
    });
    try {
      await ActivityInstanceService.updateInstanceProgress(
        instanceId: instance.reference.id,
        currentValue: 0,
        referenceTime: progressReferenceTime,
      );
      if (instance.status == 'completed' || instance.status == 'skipped') {
        if (instance.templateTrackingType == 'quantitative') {
          bool deleteLogs = false;
          if (instance.timeLogSessions.isNotEmpty) {
            final userChoice = await showUncompleteDialog();
            if (userChoice == null || userChoice == 'cancel') {
              if (isMounted()) {
                setState(() {
                  setUpdating(false);
                });
              }
              return;
            }
            deleteLogs = userChoice == 'delete';
          }
          await ActivityInstanceService.uncompleteInstance(
            instanceId: instance.reference.id,
            deleteLogs: deleteLogs,
          );
        }
      }
    } catch (e) {
      onInstanceUpdated(instance);
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting quantity: $e')),
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

  // EXACT copy of your _updateProgress logic
  static Future<void> updateProgress({
    required int delta,
    required ActivityInstanceRecord instance,
    required bool isUpdating,
    required DateTime? progressReferenceTime,
    required Function(bool) setUpdating,
    required num Function() currentProgressLocal,
    required num Function() getTargetValue,
    required Function(int?) setQuantProgressOverride,
    required Function(bool?) setBinaryCompletionOverride,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required Future<void> Function()? onRefresh,
    required BuildContext context,
    required bool Function() isMounted,
    required void Function(VoidCallback) setState,
    required int Function() getPendingQuantIncrement,
    required Function(int) setPendingQuantIncrement,
    required Timer? Function() getQuantUpdateTimer,
    required Function(Timer?) setQuantUpdateTimer,
    required Future<void> Function() processPendingQuantUpdate,
  }) async {
    if (instance.templateTrackingType == 'binary' &&
        instance.templateCategoryType == 'habit') {
      if (isUpdating) return;
      setState(() {
        setUpdating(true);
      });
      try {
        final currentValue = currentProgressLocal();
        final target = getTargetValue();
        final newValue = (currentValue + delta).clamp(0, double.infinity);
        final maxCompletions = (target * 10).toInt();
        if (newValue > maxCompletions) {
          if (isMounted()) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text('Maximum completions reached (${maxCompletions}x)')),
            );
          }
          setState(() => setUpdating(false));
          return;
        }
        setState(() => setQuantProgressOverride(newValue.toInt()));
        await ActivityInstanceService.updateInstanceProgress(
          instanceId: instance.reference.id,
          currentValue: newValue,
          referenceTime: progressReferenceTime,
        );
      } catch (e) {
        setState(() => setQuantProgressOverride(null));
        onInstanceUpdated(instance);
        if (isMounted()) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating progress: $e')),
          );
        }
      } finally {
        if (isMounted()) {
          setState(() {
            setUpdating(false);
          });
        }
      }
      return;
    }
    // Check if new value reaches target
    final currentValue = currentProgressLocal();
    final newValue = currentValue + delta;
    final targetValue = getTargetValue();
    final willComplete = targetValue > 0 && newValue >= targetValue;

    if (willComplete) {
      // Atomic completion: skip updateInstanceProgress and go straight to completion
      // This prevents race conditions and ensures immediate UI update
      setState(() {
        setUpdating(true);
        setQuantProgressOverride(newValue.toInt());
        setBinaryCompletionOverride(true);
      });
      SoundHelper().playCompletionSound();

      try {
        // Create optimistic instance for immediate UI update
        final optimisticInstance =
            InstanceEvents.createOptimisticCompletedInstance(
          instance,
          finalValue: newValue,
        );
        final operationId = OptimisticOperationTracker.generateOperationId();

        OptimisticOperationTracker.trackOperation(
          operationId,
          instanceId: instance.reference.id,
          operationType: 'complete',
          optimisticInstance: optimisticInstance,
          originalInstance: instance,
        );

        InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance,
          operationId,
        );
        onInstanceUpdated(optimisticInstance);

        await ActivityInstanceService.completeInstance(
          instanceId: instance.reference.id,
          finalValue: newValue,
          skipOptimisticUpdate: true,
        );

        final completedInstance =
            await ActivityInstanceService.getUpdatedInstance(
          instanceId: instance.reference.id,
        );

        OptimisticOperationTracker.reconcileOperation(
          operationId,
          completedInstance,
        );

        onInstanceUpdated(completedInstance);
        if (instance.templateCategoryType == 'habit') {
          onRefresh?.call();
        }
      } catch (e) {
        setState(() {
          setUpdating(false);
          setQuantProgressOverride(null);
          setBinaryCompletionOverride(false);
        });
        if (isMounted()) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error completing task: $e')),
          );
        }
      } finally {
        if (isMounted()) {
          setState(() => setUpdating(false));
        }
      }
      return;
    }

    final currentPending = getPendingQuantIncrement();
    setPendingQuantIncrement(currentPending + delta);
    final currentVal = currentProgressLocal();
    final newOptimisticValue =
        (currentVal + getPendingQuantIncrement()).clamp(0, double.infinity);
    final targetVal = getTargetValue();
    setState(() {
      setQuantProgressOverride(newOptimisticValue.toInt());
      if (targetVal > 0) {
        if (newOptimisticValue >= targetVal) {
          setBinaryCompletionOverride(true);
        } else {
          setBinaryCompletionOverride(false);
        }
      }
    });
    SoundHelper().playStepCounterSound();
    if (targetVal > 0 && newOptimisticValue >= targetVal) {
      SoundHelper().playCompletionSound();
    }
    getQuantUpdateTimer()?.cancel();
    setQuantUpdateTimer(Timer(const Duration(milliseconds: 300), () {
      processPendingQuantUpdate();
    }));
  }

  // EXACT copy of your _processPendingQuantUpdate logic
  static Future<void> processPendingQuantUpdate({
    required ActivityInstanceRecord instance,
    required DateTime? progressReferenceTime,
    required bool isUpdating,
    required Function(bool) setUpdating,
    required num Function() currentProgressLocal,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required Future<void> Function()? onRefresh,
    required BuildContext context,
    required bool Function() isMounted,
    required void Function(VoidCallback) setState,
    required int Function() getPendingQuantIncrement,
    required Function(int) setPendingQuantIncrement,
    required Function(int?) setQuantProgressOverride,
    required Timer? Function() getQuantUpdateTimer,
    required Function(Timer?) setQuantUpdateTimer,
    required Future<void> Function() processPendingQuantUpdateCallback,
  }) async {
    if (getPendingQuantIncrement() == 0) return;
    if (isUpdating) {
      setQuantUpdateTimer(Timer(const Duration(milliseconds: 300), () {
        processPendingQuantUpdateCallback();
      }));
      return;
    }

    final incrementToProcess = getPendingQuantIncrement();
    final currentValue = currentProgressLocal();
    setPendingQuantIncrement(0); // Reset before processing

    setState(() {
      setUpdating(true);
    });

    try {
      await ActivityInstanceService.updateInstanceProgress(
        instanceId: instance.reference.id,
        currentValue: currentValue,
        referenceTime: progressReferenceTime,
      );
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );
      onInstanceUpdated(updatedInstance);
      // Remove handleQuantCompletion call since we handle atomic completion above
      // But we still need to handle auto-uncompletion if value drops below target
      await ItemQuantitativeControlsHelper.handleQuantUncompletion(
        instance: instance,
        updatedInstance: updatedInstance,
        onInstanceUpdated: onInstanceUpdated,
        onRefresh: onRefresh,
        context: context,
        isMounted: isMounted,
        shouldAutoUncompleteQuant: (inst) =>
            ItemQuantitativeControlsHelper.shouldAutoUncompleteQuant(
                inst, ItemQuantitativeControlsHelper.valueToNum),
      );
    } catch (e) {
      setState(() {
        setQuantProgressOverride((currentValue - incrementToProcess)
            .clamp(0, double.infinity)
            .toInt());
      });
      setPendingQuantIncrement(getPendingQuantIncrement() + incrementToProcess);
      onInstanceUpdated(instance);
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating progress: $e')),
        );
      }
    } finally {
      if (isMounted()) {
        setState(() {
          setUpdating(false);
        });
      }
      if (getPendingQuantIncrement() != 0) {
        setQuantUpdateTimer(Timer(const Duration(milliseconds: 300), () {
          processPendingQuantUpdateCallback();
        }));
      }
    }
  }

  // EXACT copy of your _handleQuantCompletion logic
  static Future<void> handleQuantCompletion({
    required ActivityInstanceRecord instance,
    required ActivityInstanceRecord updatedInstance,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required Future<void> Function()? onRefresh,
    required BuildContext context,
    required bool Function() isMounted,
    required bool Function(ActivityInstanceRecord) shouldAutoCompleteQuant,
  }) async {
    if (!shouldAutoCompleteQuant(updatedInstance)) return;
    try {
      await ActivityInstanceService.completeInstance(
        instanceId: instance.reference.id,
        finalValue: updatedInstance.currentValue,
      );
      final completedInstance =
          await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );
      onInstanceUpdated(completedInstance);
      if (instance.templateCategoryType == 'habit') {
        onRefresh?.call();
      }
    } catch (e) {
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing task: $e')),
        );
      }
    }
  }

  // EXACT copy of your _handleQuantUncompletion logic
  static Future<void> handleQuantUncompletion({
    required ActivityInstanceRecord instance,
    required ActivityInstanceRecord updatedInstance,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required Future<void> Function()? onRefresh,
    required BuildContext context,
    required bool Function() isMounted,
    required bool Function(ActivityInstanceRecord) shouldAutoUncompleteQuant,
  }) async {
    if (!shouldAutoUncompleteQuant(updatedInstance)) return;

    // Generate operation ID for tracking
    final operationId = OptimisticOperationTracker.generateOperationId();

    // Create optimistic uncompleted instance IMMEDIATELY for instant UI update
    final optimisticInstance =
        InstanceEvents.createOptimisticUncompletedInstance(
      updatedInstance,
    );

    // Track the optimistic operation
    OptimisticOperationTracker.trackOperation(
      operationId,
      instanceId: instance.reference.id,
      operationType: 'uncomplete',
      optimisticInstance: optimisticInstance,
      originalInstance: instance,
    );

    // IMMEDIATE UI UPDATE: Broadcast optimistic update and update local state
    InstanceEvents.broadcastInstanceUpdatedOptimistic(
      optimisticInstance,
      operationId,
    );
    // Update page immediately
    onInstanceUpdated(optimisticInstance);

    try {
      await ActivityInstanceService.uncompleteInstance(
        instanceId: instance.reference.id,
      );

      // Get actual instance from backend and reconcile
      final uncompletedInstance =
          await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );

      // Reconcile optimistic update with actual backend data
      OptimisticOperationTracker.reconcileOperation(
        operationId,
        uncompletedInstance,
      );

      // Update with actual instance (in case there are any differences)
      onInstanceUpdated(uncompletedInstance);

      if (instance.templateCategoryType == 'habit') {
        onRefresh?.call();
      }
    } catch (e) {
      // Rollback optimistic update on error
      OptimisticOperationTracker.rollbackOperation(operationId);

      // Restore original instance
      onInstanceUpdated(instance);
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uncompleting task: $e')),
        );
      }
    }
  }

  // EXACT copy of your _shouldAutoCompleteQuant logic
  static bool shouldAutoCompleteQuant(
    ActivityInstanceRecord instance,
    num Function(dynamic) valueToNum,
  ) {
    final target = valueToNum(instance.templateTarget);
    if (target <= 0) return false;
    if (instance.status == 'completed' || instance.status == 'skipped') {
      return false;
    }
    final current = valueToNum(instance.currentValue);
    return current >= target;
  }

  // EXACT copy of your _shouldAutoUncompleteQuant logic
  static bool shouldAutoUncompleteQuant(
    ActivityInstanceRecord instance,
    num Function(dynamic) valueToNum,
  ) {
    final target = valueToNum(instance.templateTarget);
    if (target <= 0) return false;
    if (instance.status != 'completed' && instance.status != 'skipped') {
      return false;
    }
    final current = valueToNum(instance.currentValue);
    return current < target;
  }

  // EXACT copy of your _valueToNum logic
  static num valueToNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }
}
