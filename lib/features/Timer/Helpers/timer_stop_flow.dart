import 'package:flutter/material.dart';
import 'package:habit_tracker/services/Activtity/task_instance_service/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/features/Shared/Manual_Time_Log/manual_time_log_helper.dart';

/// Shared helper for timer stop/complete flow
/// Handles showing modal, saving time entry, and cleanup
class TimerStopFlow {
  /// Handle timer stop with optional completion
  /// Returns true if the flow completed successfully, false if cancelled/errored
  static Future<bool> handleTimerStop({
    required BuildContext context,
    required ActivityInstanceRecord instance,
    required bool markComplete,
    DateTime? timerStartTime,
    Duration? localDuration,
    VoidCallback? onSaveComplete,
  }) async {
    try {
      // Calculate start and end times
      DateTime startTime;
      DateTime endTime = DateTime.now();

      // Get start time from tracked value or from instance
      if (timerStartTime != null) {
        startTime = timerStartTime;
      } else if (instance.currentSessionStartTime != null) {
        startTime = instance.currentSessionStartTime!;
      } else if (localDuration != null) {
        startTime = endTime.subtract(localDuration);
      } else {
        // Fallback: calculate from accumulated time
        final totalMs = instance.accumulatedTime;
        startTime = endTime.subtract(Duration(milliseconds: totalMs));
      }

      // Get the date from start time for the modal
      final selectedDate = DateTime(
        startTime.year,
        startTime.month,
        startTime.day,
      );

      // Use a mutable list to track save state (workaround for closure capture)
      final saveState = <bool>[false];

      // Show modal to get activity details
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          return ManualTimeLogModal(
            selectedDate: selectedDate,
            initialStartTime: startTime,
            initialEndTime: endTime,
            markCompleteOnSave: markComplete,
            fromTimer: true,
            onSave: () {
              saveState[0] = true; // Mark as saved
              // Clear the timer instance's session since time was logged to selected template
              TaskInstanceService.discardTimeLogging(
                activityInstanceRef: instance.reference,
              ).catchError((e) {
                // Ignore errors - instance might already be cleaned up
              });
              onSaveComplete?.call();
            },
          );
        },
      );

      // If modal was closed without saving, cleanup the timer instance
      if (!saveState[0]) {
        await _cleanupTimerInstance(instance);
        return false;
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping timer: $e')),
        );
      }
      return false;
    }
  }

  /// Cleanup timer instance if modal was cancelled
  static Future<void> _cleanupTimerInstance(
      ActivityInstanceRecord instance) async {
    try {
      // First, discard the active session
      try {
        await TaskInstanceService.discardTimeLogging(
          activityInstanceRef: instance.reference,
        );
      } catch (e) {
        // If discard fails, continue with cleanup
      }

      // Check if instance still exists and is a temporary timer instance
      final updatedInstance =
          await ActivityInstanceRecord.getDocumentOnce(instance.reference);

      // Only delete if it's a timer task (not from swipe)
      // Timer tasks have templateTrackingType 'binary' and templateCategoryType 'task'
      if (updatedInstance.templateTrackingType == 'binary' &&
          updatedInstance.templateCategoryType == 'task') {
        // Delete the template if templateId exists
        if (updatedInstance.hasTemplateId()) {
          final userId = await waitForCurrentUserUid();
          if (userId.isNotEmpty) {
            final templateRef = ActivityRecord.collectionForUser(userId)
                .doc(updatedInstance.templateId);
            await templateRef.delete();
          }
        }
        // Delete the instance
        await instance.reference.delete();
      }
    } catch (e) {
      // Handle error silently - cleanup is best effort
    }
  }
}
