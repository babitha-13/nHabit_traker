import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/Task%20Instance%20Service/task_instance_service.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/timer_logic_helper.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/TimeManager.dart';
import 'package:habit_tracker/Helper/Helpers/sound_helper.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/optimistic_operation_tracker.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

class ItemTimeControlsHelper {
  static Future<void> showTimeControlsMenu({
    required BuildContext context,
    required BuildContext anchorContext,
    required ActivityInstanceRecord instance,
    required bool isUpdating,
    required Function(bool) setUpdating,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required Future<void> Function() resetTimer,
    required Future<void> Function() showCustomTimeDialog,
    required Future<void> Function() markTimerComplete,
  }) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    final realTimeAccumulated =
        TimerLogicHelper.getRealTimeAccumulated(instance);
    final target = instance.templateTarget ?? 0;
    final targetMs = target * 60000; // Convert minutes to milliseconds
    final remainingMs = targetMs - realTimeAccumulated;
    final canMarkComplete = (target > 0 && remainingMs > 0) ||
        (target == 0 && realTimeAccumulated > 0);
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
              Text('Reset Timer')
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        const PopupMenuItem<String>(
          value: 'custom',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.edit, size: 18),
              SizedBox(width: 8),
              Text('Set Custom Time')
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
              Text(
                  'Mark as Complete${canMarkComplete ? (target > 0 ? ' (+${formatRemainingTime(remainingMs)})' : ' (${formatTimeFromMs(realTimeAccumulated)})') : ''}')
            ],
          ),
        ),
      ],
    );
    if (selected == null) return;
    if (selected == 'reset') {
      await resetTimer();
    } else if (selected == 'custom') {
      await showCustomTimeDialog();
    } else if (selected == 'complete' && canMarkComplete) {
      await markTimerComplete();
    }
  }

  static String formatRemainingTime(int remainingMs) {
    final totalSeconds = remainingMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  static String formatTimeFromMs(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      return '${seconds}s';
    }
  }

  static Future<void> resetTimer({
    required ActivityInstanceRecord instance,
    required bool isUpdating,
    required Function(bool) setUpdating,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required BuildContext context,
    required bool Function() isMounted,
    required void Function(VoidCallback) setState,
  }) async {
    if (isUpdating) return;
    setState(() {
      setUpdating(true);
    });
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
          .doc(instance.reference.id);
      await instanceRef.update({
        'accumulatedTime': 0,
        'totalTimeLogged': 0,
        'timeLogSessions': [],
        'currentSessionStartTime': null,
        'isTimerActive': false,
        'timerStartTime': null,
        'lastUpdated': DateTime.now(),
      });
      if (instance.status == 'completed' || instance.status == 'skipped') {
        if (instance.templateTrackingType == 'time') {
          await ActivityInstanceService.uncompleteInstance(
            instanceId: instance.reference.id,
            deleteLogs: true, // Automatically delete logs when timer is reset
          );
        }
      }
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timer reset to 0')),
        );
      }
    } catch (e) {
      onInstanceUpdated(instance);
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting timer: $e')),
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

  static Future<void> markTimerComplete({
    required ActivityInstanceRecord instance,
    required bool isUpdating,
    required Function(bool) setUpdating,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required BuildContext context,
    required bool Function() isMounted,
    required void Function(VoidCallback) setState,
  }) async {
    if (isUpdating) return;
    setState(() {
      setUpdating(true);
    });
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      if (instance.isTimeLogging && instance.currentSessionStartTime != null) {
        await TaskInstanceService.stopTimeLogging(
          activityInstanceRef: instance.reference,
          markComplete: false, // Don't mark complete yet, just stop the session
        );
      }
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );
      final target = updatedInstance.templateTarget ?? 0;
      int newAccumulatedTime;
      if (target == 0) {
        final realTimeAccumulated =
            TimerLogicHelper.getRealTimeAccumulated(updatedInstance);
        if (realTimeAccumulated <= 0) {
          throw Exception('No time recorded to complete task');
        }
        newAccumulatedTime = realTimeAccumulated;
        final targetInMinutes = realTimeAccumulated ~/ 60000;
        final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
            .doc(updatedInstance.reference.id);
        await instanceRef.update({
          'templateTarget': targetInMinutes,
          'lastUpdated': DateTime.now(),
        });

        final templateRef = ActivityRecord.collectionForUser(userId)
            .doc(updatedInstance.templateId);
        await templateRef.update({
          'target': targetInMinutes,
          'lastUpdated': DateTime.now(),
        });
      } else {
        final targetMs = target * 60000; // Convert minutes to milliseconds
        newAccumulatedTime = targetMs.toInt();
      }

      final completionTime = DateTime.now();
      final stackedTimes =
          await ActivityInstanceService.calculateStackedStartTime(
        userId: userId,
        completionTime: completionTime,
        durationMs: newAccumulatedTime,
        instanceId: updatedInstance.reference.id,
      );

      final instanceBeforeSession =
          await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );

      final newSession = {
        'startTime': stackedTimes.startTime,
        'endTime': stackedTimes.endTime,
        'durationMilliseconds': newAccumulatedTime,
      };

      final existingSessions = List<Map<String, dynamic>>.from(
          instanceBeforeSession.timeLogSessions);

      existingSessions.add(newSession);
      final totalTime = existingSessions.fold<int>(
        0,
        (sum, session) => sum + (session['durationMilliseconds'] as int? ?? 0),
      );

      final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
          .doc(updatedInstance.reference.id);

      final Map<String, dynamic> updateData = {
        'timeLogSessions': existingSessions,
        'totalTimeLogged': totalTime,
        'accumulatedTime': newAccumulatedTime,
        'lastUpdated': DateTime.now(),
      };

      if (updatedInstance.templateTrackingType == 'time') {
        updateData['currentValue'] = newAccumulatedTime;
      } else if (updatedInstance.templateTrackingType == 'binary') {
        updateData['currentValue'] = 1;
      }

      // Use updateInstanceProgress AND completeInstance in separate steps if not atomic
      // But we prefer atomic if we can.
      // Since completeInstance with finalAccumulatedTime sets everything needed, we can just call that.
      // However, we need to update timeLogSessions first.

      // OPTIMISTIC UPDATE START
      final operationId = OptimisticOperationTracker.generateOperationId();
      final optimisticInstance =
          InstanceEvents.createOptimisticCompletedInstance(
        updatedInstance,
        finalAccumulatedTime: newAccumulatedTime,
        timeLogSessions: existingSessions,
        totalTimeLogged: totalTime,
        finalValue: updatedInstance.templateTrackingType == 'time'
            ? newAccumulatedTime
            : (updatedInstance.templateTrackingType == 'binary'
                ? 1
                : updatedInstance.currentValue),
      );

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
      // OPTIMISTIC UPDATE END

      await instanceRef.update(updateData);

      await ActivityInstanceService.completeInstance(
        instanceId: instance.reference.id,
        finalValue: updatedInstance.templateTrackingType == 'time'
            ? newAccumulatedTime
            : (updatedInstance.templateTrackingType == 'binary'
                ? 1
                : updatedInstance.currentValue),
        finalAccumulatedTime: newAccumulatedTime,
        skipOptimisticUpdate: true, // We already did it
      );

      final finalInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );

      OptimisticOperationTracker.reconcileOperation(
        operationId,
        finalInstance,
      );

      onInstanceUpdated(finalInstance);

      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Task completed! Remaining time added.')),
        );
      }
    } catch (e) {
      // Rollback logic would go here if needed, but setState handles UI reset
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing task: $e')),
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

  static Future<void> showCustomTimeDialog({
    required ActivityInstanceRecord instance,
    required BuildContext context,
    required Function(int, int) setCustomTime,
    required String Function(int) formatTimeFromMs,
  }) async {
    final realTimeAccumulated =
        TimerLogicHelper.getRealTimeAccumulated(instance);
    final currentHours = realTimeAccumulated ~/ 3600000;
    final currentMinutes = (realTimeAccumulated % 3600000) ~/ 60000;
    final target = instance.templateTarget ?? 0;
    final targetHours = target ~/ 60;
    final targetMinutes = (target % 60).toInt();
    final hoursController = TextEditingController(
        text: currentHours > 0 ? currentHours.toString() : '');
    final minutesController = TextEditingController(
        text: currentMinutes > 0 ? currentMinutes.toString() : '0');

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Custom Time'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (target > 0) ...[
              Text(
                'Target: ${targetHours > 0 ? '${targetHours}h ' : ''}${targetMinutes}m',
                style: FlutterFlowTheme.of(context).bodySmall,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Current: ${formatTimeFromMs(realTimeAccumulated)}',
              style: FlutterFlowTheme.of(context).bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: hoursController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Hours',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: minutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final hours = int.tryParse(hoursController.text) ?? 0;
              final minutes = int.tryParse(minutesController.text) ?? 0;
              if (hours < 0 || minutes < 0 || minutes >= 60) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Invalid input. Hours must be >= 0, minutes must be 0-59')),
                );
                return;
              }
              Navigator.of(context).pop({'hours': hours, 'minutes': minutes});
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );

    hoursController.dispose();
    minutesController.dispose();

    if (result != null) {
      await setCustomTime(result['hours'] ?? 0, result['minutes'] ?? 0);
    }
  }

  static Future<void> setCustomTime({
    required int hours,
    required int minutes,
    required ActivityInstanceRecord instance,
    required bool isUpdating,
    required Function(bool) setUpdating,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required BuildContext context,
    required bool Function() isMounted,
    required void Function(VoidCallback) setState,
    required Future<String?> Function() showUncompleteDialog,
  }) async {
    if (isUpdating) return;
    setState(() {
      setUpdating(true);
    });
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      if (instance.isTimeLogging && instance.currentSessionStartTime != null) {
        await TaskInstanceService.stopTimeLogging(
          activityInstanceRef: instance.reference,
          markComplete: false, // Don't mark complete yet, just stop the session
        );
      }
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );
      final customTimeMs = (hours * 3600000) + (minutes * 60000);
      final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
          .doc(instance.reference.id);

      final Map<String, dynamic> updateData = {
        'accumulatedTime': customTimeMs,
        'totalTimeLogged': customTimeMs,
        'lastUpdated': DateTime.now(),
      };
      if (updatedInstance.templateTrackingType == 'time') {
        updateData['currentValue'] = customTimeMs;
      }
      await instanceRef.update(updateData);
      final target = updatedInstance.templateTarget ?? 0;
      final targetMs = target * 60000;
      final shouldComplete = target > 0 && customTimeMs >= targetMs;

      if (shouldComplete && updatedInstance.status != 'completed') {
        // OPTIMISTIC UPDATE START
        final operationId = OptimisticOperationTracker.generateOperationId();
        final optimisticInstance =
            InstanceEvents.createOptimisticCompletedInstance(
          updatedInstance,
          finalAccumulatedTime: customTimeMs,
          finalValue: updatedInstance.templateTrackingType == 'time'
              ? customTimeMs
              : (updatedInstance.templateTrackingType == 'binary'
                  ? 1
                  : updatedInstance.currentValue),
        );

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
        // OPTIMISTIC UPDATE END

        await ActivityInstanceService.completeInstance(
          instanceId: instance.reference.id,
          finalValue: updatedInstance.templateTrackingType == 'time'
              ? customTimeMs
              : (updatedInstance.templateTrackingType == 'binary'
                  ? 1
                  : updatedInstance.currentValue),
          finalAccumulatedTime: customTimeMs,
          skipOptimisticUpdate: true,
        );

        final completedInstance =
            await ActivityInstanceService.getUpdatedInstance(
          instanceId: instance.reference.id,
        );
        OptimisticOperationTracker.reconcileOperation(
            operationId, completedInstance);
        // Ensure onInstanceUpdated is called with the final reconciled instance
        onInstanceUpdated(completedInstance);
      } else if (!shouldComplete &&
          (updatedInstance.status == 'completed' ||
              updatedInstance.status == 'skipped')) {
        bool deleteLogs = false;
        if (updatedInstance.timeLogSessions.isNotEmpty) {
          final userChoice = await showUncompleteDialog();
          if (userChoice == null || userChoice == 'cancel') {
            await instanceRef.update({
              'accumulatedTime': updatedInstance.accumulatedTime,
              'currentValue': updatedInstance.currentValue,
              'totalTimeLogged': updatedInstance.totalTimeLogged,
              'lastUpdated': DateTime.now(),
            });
            if (isMounted()) {
              setState(() {
                setUpdating(false);
              });
            }
            return;
          }
          deleteLogs = userChoice == 'delete';
        }

        // OPTIMISTIC UPDATE FOR UNCOMPLETE
        final operationId = OptimisticOperationTracker.generateOperationId();
        final optimisticInstance =
            InstanceEvents.createOptimisticUncompletedInstance(
          updatedInstance,
          deleteLogs: deleteLogs,
        );
        // Apply custom time to optimistic instance
        final optimisticWithTime =
            InstanceEvents.createOptimisticProgressInstance(optimisticInstance,
                currentValue: updatedInstance.templateTrackingType == 'time'
                    ? customTimeMs
                    : optimisticInstance.currentValue);

        OptimisticOperationTracker.trackOperation(
          operationId,
          instanceId: instance.reference.id,
          operationType: 'uncomplete',
          optimisticInstance: optimisticWithTime,
          originalInstance: instance,
        );

        InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticWithTime,
          operationId,
        );
        onInstanceUpdated(optimisticWithTime);

        await ActivityInstanceService.uncompleteInstance(
          instanceId: instance.reference.id,
          deleteLogs: deleteLogs,
          skipOptimisticUpdate: true,
          currentValue: updatedInstance.templateTrackingType == 'time'
              ? customTimeMs
              : null,
        );

        final uncompletedInstance =
            await ActivityInstanceService.getUpdatedInstance(
          instanceId: instance.reference.id,
        );
        OptimisticOperationTracker.reconcileOperation(
            operationId, uncompletedInstance);
        onInstanceUpdated(uncompletedInstance);
        InstanceEvents.broadcastInstanceUpdatedReconciled(
          uncompletedInstance,
          operationId,
        );
      } else {
        // Just a regular update without status change
        final finalInstance = await ActivityInstanceService.getUpdatedInstance(
          instanceId: instance.reference.id,
        );
        onInstanceUpdated(finalInstance);
        InstanceEvents.broadcastInstanceUpdated(finalInstance);
      }
      if (isMounted()) {
        final timeDisplay = hours > 0
            ? '${hours}h ${minutes}m'
            : minutes > 0
                ? '${minutes}m'
                : '0m';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Time set to $timeDisplay')),
        );
      }
    } catch (e) {
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error setting custom time: $e')),
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
      // Generate operation ID for tracking
      final operationId = OptimisticOperationTracker.generateOperationId();

      // Create optimistic completed instance IMMEDIATELY for instant UI update
      final optimisticInstance =
          InstanceEvents.createOptimisticCompletedInstance(
        instance,
        finalAccumulatedTime: accumulated,
      );

      // Track the optimistic operation
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instance.reference.id,
        operationType: 'complete',
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
        await ActivityInstanceService.completeInstance(
          instanceId: instance.reference.id,
          finalAccumulatedTime: accumulated,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task completed! Target reached.')),
          );
        }

        // Get actual instance from backend and reconcile
        final completedInstance =
            await ActivityInstanceService.getUpdatedInstance(
          instanceId: instance.reference.id,
        );

        // Reconcile optimistic update with actual backend data
        OptimisticOperationTracker.reconcileOperation(
          operationId,
          completedInstance,
        );

        // Update with actual instance (in case there are any differences)
        onInstanceUpdated(completedInstance);
      } catch (e) {
        // Rollback optimistic update on error
        OptimisticOperationTracker.rollbackOperation(operationId);

        // Restore original instance
        onInstanceUpdated(instance);
        // Log error but don't fail - instance update callback is non-critical
      }
    }
  }
}
