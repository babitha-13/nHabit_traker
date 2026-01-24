import 'dart:async';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_instance_service.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/TimeManager.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Helper/Helpers/sound_helper.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/timer_stop_flow.dart';
import '../global_floating_timer.dart';

mixin GlobalFloatingTimerLogic on State<GlobalFloatingTimer>, SingleTickerProviderStateMixin<GlobalFloatingTimer> {
  final TimerManager timerManager = TimerManager();
  bool isExpanded = false;
  late AnimationController pulseController;
  late Animation<double> pulseAnimation;

  // Drag state
  double bottomOffset = 16.0;
  double rightOffset = 16.0;
  double initialBottomOffset = 16.0;
  double initialRightOffset = 16.0;
  Offset? initialDragPosition;

  @override
  void initState() {
    super.initState();
    timerManager.addListener(onTimerStateChanged);

    // Load existing active timers from Firestore
    timerManager.loadActiveTimers();

    // Listen to instance update events for real-time sync
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceUpdated,
      onInstanceUpdated,
    );

    // Pulse animation for active timer
    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    timerManager.removeListener(onTimerStateChanged);
    NotificationCenter.removeObserver(this, InstanceEvents.instanceUpdated);
    pulseController.dispose();
    super.dispose();
  }

  void onTimerStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Handle instance update events from NotificationCenter
  void onInstanceUpdated(Object? data) {
    if (data is ActivityInstanceRecord) {
      // Check if it's a timer instance (time type or binary with time logging) and sync with TimerManager
      final isTimeType = data.templateTrackingType == 'time';
      final isBinaryTimerSession = data.templateTrackingType == 'binary' &&
          (data.isTimeLogging || data.currentSessionStartTime != null);
      if (isTimeType || isBinaryTimerSession) {
        timerManager.updateInstance(data);
      }
    }
  }

  void handlePanStart(DragStartDetails details) {
    initialDragPosition = details.globalPosition;
    initialBottomOffset = bottomOffset;
    initialRightOffset = rightOffset;
  }

  void handlePanUpdate(DragUpdateDetails details) {
    if (initialDragPosition == null) return;

    final delta = details.globalPosition - initialDragPosition!;

    // Only start dragging if movement is significant (prevents accidental drags on taps)
    if (delta.distance < 5) return;

    // Get screen size to constrain dragging
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Calculate new position (invert Y axis since bottom is from bottom)
    double newBottom = initialBottomOffset - delta.dy;
    double newRight = initialRightOffset - delta.dx;

    // Constrain to screen bounds
    final widgetHeight = isExpanded ? 400.0 : 64.0;
    final widgetWidth = isExpanded ? 320.0 : 64.0;

    newBottom = newBottom.clamp(0.0, screenHeight - widgetHeight - 16);
    newRight = newRight.clamp(0.0, screenWidth - widgetWidth - 16);

    setState(() {
      bottomOffset = newBottom;
      rightOffset = newRight;
    });
  }

  void handlePanEnd(DragEndDetails details) {
    initialDragPosition = null;
  }

  /// Get current elapsed time for an instance
  int getCurrentTime(ActivityInstanceRecord instance) {
    int totalMilliseconds = instance.accumulatedTime;

    // For binary timer sessions, use currentSessionStartTime
    if (instance.templateTrackingType == 'binary' &&
        instance.currentSessionStartTime != null) {
      final elapsed = DateTime.now()
          .difference(instance.currentSessionStartTime!)
          .inMilliseconds;
      totalMilliseconds += elapsed;
    } else if (instance.isTimerActive && instance.timerStartTime != null) {
      // For time-tracking instances, use timerStartTime
      final elapsed =
          DateTime.now().difference(instance.timerStartTime!).inMilliseconds;
      totalMilliseconds += elapsed;
    }

    return totalMilliseconds;
  }

  /// Format duration in HH:MM:SS or MM:SS format
  String formatDuration(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Cancel timer - directly discard without showing modal
  Future<void> cancelTimer(ActivityInstanceRecord instance) async {
    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard Timer?'),
          content: const Text(
            'Are you sure you want to discard this timer session? All progress will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Discard'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return; // User cancelled
      }

      // For binary timer sessions (from timer page), discard and delete if temporary
      if (instance.templateTrackingType == 'binary' &&
          (instance.isTimeLogging ||
              instance.currentSessionStartTime != null)) {
        // Check if this is a temporary timer task (not from swipe)
        // Timer tasks have templateCategoryType 'task' and are binary
        if (instance.templateCategoryType == 'task') {
          // Discard time logging first
          try {
            await TaskInstanceService.discardTimeLogging(
              activityInstanceRef: instance.reference,
            );
          } catch (e) {
            // Ignore errors - might already be discarded
          }

          // Delete the template if it exists
          try {
            if (instance.hasTemplateId()) {
              final userId = await waitForCurrentUserUid();
              if (userId.isNotEmpty) {
                final templateRef = ActivityRecord.collectionForUser(userId)
                    .doc(instance.templateId);
                await templateRef.delete();
              }
            }
            // Delete the instance
            await instance.reference.delete();
          } catch (e) {
            // Handle error silently - cleanup is best effort
          }
        } else {
          // For swipe-started instances, just discard time logging
          await TaskInstanceService.discardTimeLogging(
            activityInstanceRef: instance.reference,
          );
        }
      } else {
        // For time-tracking instances, just discard time logging
        await TaskInstanceService.discardTimeLogging(
          activityInstanceRef: instance.reference,
        );
      }

      // Remove from TimerManager
      timerManager.stopInstance(instance);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timer discarded'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error discarding timer: $e')),
        );
      }
    }
  }

  /// Check if instance is from a swipe (has real task details, not temporary timer task)
  bool isFromSwipe(ActivityInstanceRecord instance) {
    // Timer-created instances have template name "Timer Task"
    // Swipe-started instances have the actual task name
    return instance.templateName != 'Timer Task' &&
        instance.templateName.isNotEmpty;
  }

  /// Stop timer with optional completion
  Future<void> stopTimer(ActivityInstanceRecord instance,
      {required bool markComplete}) async {
    try {
      // Play stop button sound
      SoundHelper().playStopButtonSound();

      // Check if this is from a swipe (has task details already)
      final fromSwipe = isFromSwipe(instance);

      // For binary timer sessions
      if (instance.templateTrackingType == 'binary' &&
          (instance.isTimeLogging ||
              instance.currentSessionStartTime != null)) {
        // If from swipe, save directly without showing modal (task details already available)
        if (fromSwipe) {
          try {
            // For swipe-started instances: stop time logging (with or without completion)
            await TaskInstanceService.stopTimeLogging(
              activityInstanceRef: instance.reference,
              markComplete: markComplete,
            );

            // Remove from TimerManager after save
            timerManager.stopInstance(instance);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(markComplete
                      ? 'Timer completed and saved'
                      : 'Timer stopped and saved'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error saving timer: $e')),
              );
            }
          }
        } else {
          // For timer-created instances, show modal to get task details
          final success = await TimerStopFlow.handleTimerStop(
            context: context,
            instance: instance,
            markComplete: markComplete,
            timerStartTime: instance.currentSessionStartTime,
            onSaveComplete: () {
              // Remove from TimerManager after save
              timerManager.stopInstance(instance);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(markComplete
                        ? 'Timer completed and saved'
                        : 'Timer stopped and saved'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          );

          if (!success) {
            // Modal was cancelled, refresh instance state
            final updatedInstance =
                await ActivityInstanceService.getUpdatedInstance(
              instanceId: instance.reference.id,
            );
            timerManager.updateInstance(updatedInstance);
          }
        }
      } else {
        // For time-tracking instances, use existing toggle logic
        final wasActive = instance.isTimerActive;
        if (wasActive) {
          await ActivityInstanceService.toggleInstanceTimer(
            instanceId: instance.reference.id,
          );
        }
        final updatedInstance =
            await ActivityInstanceService.getUpdatedInstance(
          instanceId: instance.reference.id,
        );
        // If timer was stopped, remove it from TimerManager
        if (wasActive && !updatedInstance.isTimerActive) {
          timerManager.stopInstance(updatedInstance);
        } else {
          timerManager.updateInstance(updatedInstance);
        }
        InstanceEvents.broadcastInstanceUpdated(updatedInstance);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping timer: $e')),
        );
      }
    }
  }
}
