import 'dart:async';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/utils/timer_logic_helper.dart';
import 'package:habit_tracker/Helper/utils/TimeManager.dart';
import 'package:habit_tracker/Helper/utils/sound_helper.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';

class ItemProgressLogicHelper {

  static Future<void> toggleTimer({
    required ActivityInstanceRecord instance,
    required bool isUpdating,
    required Function(bool) setUpdating,
    required Function(bool?) setTimerOverride,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required BuildContext context,
    required Function(ActivityInstanceRecord) checkTimerCompletion,
    required bool isTimerActiveLocal,
  }) async {
    if (isUpdating) return;
    setUpdating(true);
    try {
      final wasActive = isTimerActiveLocal;
      final newTimerState = !wasActive;
      setTimerOverride(newTimerState);

      await ActivityInstanceService.toggleInstanceTimer(
        instanceId: instance.reference.id,
      );

      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );

      if (!wasActive) {
        SoundHelper().playPlayButtonSound();
        TimerManager().startInstance(updatedInstance);
      } else {
        SoundHelper().playStopButtonSound();
        TimerManager().stopInstance(updatedInstance);
        if (TimerLogicHelper.hasMetTarget(updatedInstance)) {
          await checkTimerCompletion(updatedInstance);
        }
      }
    } catch (e) {
      setTimerOverride(null);
      onInstanceUpdated(instance);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling timer: $e')),
        );
      }
    } finally {
      setUpdating(false);
    }
  }

  static Future<void> checkTimerCompletion(
      BuildContext context,
      ActivityInstanceRecord instance,
      Function(ActivityInstanceRecord) onInstanceUpdated,
      ) async {
    if (instance.templateTrackingType != 'time') return;
    final target = instance.templateTarget ?? 0;
    if (target == 0) return; // No target set
    final accumulated = instance.accumulatedTime;
    final targetMs = (target * 60000).toInt();
    if (accumulated >= targetMs) {
      try {
        await ActivityInstanceService.completeInstance(
          instanceId: instance.reference.id,
          finalAccumulatedTime: accumulated,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task completed! Target reached.')),
          );
        }
        final completedInstance = await ActivityInstanceService.getUpdatedInstance(
          instanceId: instance.reference.id,
        );
        onInstanceUpdated(completedInstance);
      } catch (e) {
        // Log error but don't fail - instance update callback is non-critical
      }
    }
  }

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

    try {
      if (completed) {
        SoundHelper().playCompletionSound();
        dynamic targetValue = 1;
        int? targetAccumulatedTime;
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
        await ActivityInstanceService.updateInstanceProgress(
          instanceId: instance.reference.id,
          currentValue: targetValue,
          referenceTime: progressReferenceTime,
        );
        await ActivityInstanceService.completeInstance(
          instanceId: instance.reference.id,
          finalAccumulatedTime: targetAccumulatedTime,
        );
      } else {
        SoundHelper().playCompletionSound();
        dynamic undoValue = 0;
        if (treatAsBinary && instance.templateTrackingType == 'quantitative') {
          undoValue = (currentProgressLocal - 1).clamp(0, double.infinity);
        }
        await ActivityInstanceService.updateInstanceProgress(
          instanceId: instance.reference.id,
          currentValue: undoValue,
          referenceTime: progressReferenceTime,
        );
        await ActivityInstanceService.uncompleteInstance(
          instanceId: instance.reference.id,
          deleteLogs: deleteLogs,
        );
      }
      if (instance.templateCategoryType == 'habit' && completed) {
        onRefresh?.call();
      }
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );
      onInstanceUpdated(updatedInstance);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
    } catch (e) {
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