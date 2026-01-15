import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/Helpers/sound_helper.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';

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
