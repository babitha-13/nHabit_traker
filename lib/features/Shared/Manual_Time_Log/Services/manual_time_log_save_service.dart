import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/Task%20Instance%20Service/task_instance_service.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/optimistic_operation_tracker.dart';
import 'package:collection/collection.dart';
import 'package:habit_tracker/Screens/Shared/Manual_Time_Log/manual_time_log_helper.dart';
import 'package:habit_tracker/Screens/Shared/Manual_Time_Log/Services/manual_time_log_helper_service.dart';

/// Service for save and delete operations
class ManualTimeLogSaveService {
  /// Save the time entry (create or update)
  static Future<void> saveEntry(ManualTimeLogModalState state) async {
    final name = state.activityController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(state.context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an activity name'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (state.selectedType == 'habit' && state.selectedTemplate == null) {
      // Check if user typed a name that exactly matches an existing habit
      final exactMatch = state.allActivities.firstWhereOrNull((a) =>
          a.categoryType == 'habit' &&
          a.name.toLowerCase() == name.toLowerCase());

      if (exactMatch != null) {
        state.selectedTemplate = exactMatch;
      } else {
        ScaffoldMessenger.of(state.context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please select an existing habit from the list. Creating new habits is not allowed here.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // Validate time range
    if (state.startTime.isAfter(state.endTime) ||
        state.startTime.isAtSameMomentAs(state.endTime)) {
      ScaffoldMessenger.of(state.context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Validate that times are on the selected date (within reasonable bounds)
    final startDateOnly = DateTime(
      state.startTime.year,
      state.startTime.month,
      state.startTime.day,
    );
    final endDateOnly = DateTime(
      state.endTime.year,
      state.endTime.month,
      state.endTime.day,
    );
    final selectedDateOnly = DateTime(
      state.widget.selectedDate.year,
      state.widget.selectedDate.month,
      state.widget.selectedDate.day,
    );

    // Check if start time is on the selected date
    if (!startDateOnly.isAtSameMomentAs(selectedDateOnly)) {
      ScaffoldMessenger.of(state.context).showSnackBar(
        SnackBar(
          content: Text(
              'Start time must be on the selected date (${DateFormat('MMM d, y').format(state.widget.selectedDate)}).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Check if end time is on the same day as start time (or next day if crossing midnight)
    final daysDifference = endDateOnly.difference(startDateOnly).inDays;
    if (daysDifference > 1) {
      ScaffoldMessenger.of(state.context).showSnackBar(
        const SnackBar(
          content: Text(
              'Time entry cannot span more than one day. Please adjust the end time.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Validate duration is reasonable (not too long)
    final duration = state.endTime.difference(state.startTime);
    if (duration.inHours > 24) {
      ScaffoldMessenger.of(state.context).showSnackBar(
        const SnackBar(
          content: Text(
              'Time entry cannot be longer than 24 hours. Please adjust the time range.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!state.mounted) return;
    state.setState(() => state.isLoading = true);

    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      final templateId = state.selectedTemplate?.reference.id;

      // Check if we're editing an existing entry
      if (state.widget.editMetadata != null) {
        // Update existing session time
        await TaskInstanceService.updateTimeLogSession(
          instanceId: state.widget.editMetadata!.instanceId,
          sessionIndex: state.widget.editMetadata!.sessionIndex,
          startTime: state.startTime,
          endTime: state.endTime,
        );

        // Check if name or type has changed and update instance metadata
        // Use template name if template is selected, otherwise use typed name
        final finalName = state.selectedTemplate?.name ?? name;
        final hasNameChanged =
            finalName != state.widget.editMetadata!.activityName;
        final hasTypeChanged =
            state.selectedType != state.widget.editMetadata!.activityType;

        if (hasNameChanged ||
            hasTypeChanged ||
            templateId != null ||
            state.selectedCategory != null) {
          // Get current instance for optimistic update
          final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
              .doc(state.widget.editMetadata!.instanceId);
          final currentInstance =
              await ActivityInstanceRecord.getDocumentOnce(instanceRef);

          final updateData = <String, dynamic>{
            'lastUpdated': DateTime.now(),
          };

          // Update name if changed (use template name if available, otherwise typed name)
          if (hasNameChanged) {
            updateData['templateName'] = finalName;
          }

          // Update type if changed
          if (hasTypeChanged) {
            updateData['templateCategoryType'] = state.selectedType;
          }

          // Update template ID if a template is selected
          if (templateId != null) {
            updateData['templateId'] = templateId;
          }

          // Update category if changed
          if (state.selectedCategory != null) {
            updateData['templateCategoryId'] =
                state.selectedCategory!.reference.id;
            updateData['templateCategoryName'] = state.selectedCategory!.name;
            if (state.selectedCategory!.color.isNotEmpty) {
              updateData['templateCategoryColor'] =
                  state.selectedCategory!.color;
            }
          }

          // ==================== OPTIMISTIC BROADCAST ====================
          // 1. Create optimistic instance with metadata updates
          final optimisticInstance =
              InstanceEvents.createOptimisticPropertyUpdateInstance(
            currentInstance,
            updateData,
          );

          // 2. Generate operation ID
          final operationId = OptimisticOperationTracker.generateOperationId();

          // 3. Track operation
          OptimisticOperationTracker.trackOperation(
            operationId,
            instanceId: currentInstance.reference.id,
            operationType: 'progress',
            optimisticInstance: optimisticInstance,
            originalInstance: currentInstance,
          );

          // 4. Broadcast optimistically (IMMEDIATE)
          InstanceEvents.broadcastInstanceUpdatedOptimistic(
              optimisticInstance, operationId);

          // 5. Also update the template if it exists
          if (templateId != null) {
            final templateRef =
                ActivityRecord.collectionForUser(userId).doc(templateId);
            final templateUpdateData = <String, dynamic>{
              'lastUpdated': DateTime.now(),
            };

            if (hasNameChanged) {
              templateUpdateData['name'] = finalName;
            }

            if (state.selectedCategory != null) {
              templateUpdateData['categoryId'] =
                  state.selectedCategory!.reference.id;
              templateUpdateData['categoryName'] = state.selectedCategory!.name;
            }

            try {
              await templateRef.update(templateUpdateData);
            } catch (e) {
              // Template might not exist, continue with instance update
              print('Warning: Could not update template: $e');
            }
          }

          // 6. Perform backend update
          try {
            await instanceRef.update(updateData);

            // 7. Reconcile with actual data
            final updatedInstance =
                await ActivityInstanceRecord.getDocumentOnce(instanceRef);
            OptimisticOperationTracker.reconcileOperation(
                operationId, updatedInstance);
          } catch (e) {
            // 8. Rollback on error
            OptimisticOperationTracker.rollbackOperation(operationId);
            rethrow;
          }
        }
      } else {
        // Create new entry
        final shouldMarkComplete =
            ManualTimeLogHelperService.shouldMarkCompleteOnSave(state);

        await TaskInstanceService.logManualTimeEntry(
          taskName: state.selectedTemplate?.name ?? name,
          startTime: state.startTime,
          endTime: state.endTime,
          activityType: state.selectedType, // 'task', 'habit', 'essential'
          templateId: templateId,
          markComplete: shouldMarkComplete,
          categoryId: state.selectedCategory?.reference.id,
          categoryName: state.selectedCategory?.name,
        );
      }

      // Close modal first, then call onSave
      if (state.mounted) {
        Navigator.of(state.context).pop();
        state.widget.onSave();
      }
    } catch (e) {
      // Error saving time entry

      // Get root context before closing modal
      final rootContext =
          Navigator.of(state.context, rootNavigator: true).context;

      // Close modal first, then show error
      if (state.mounted) {
        Navigator.of(state.context).pop();
        // Show error message after a short delay to ensure modal is closed
        Future.delayed(const Duration(milliseconds: 300), () {
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(
                content: Text('Failed to save entry: ${e.toString()}'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        });
      }
    } finally {
      if (state.mounted) {
        state.setState(() => state.isLoading = false);
      }
    }
  }

  /// Delete the time entry
  static Future<void> deleteEntry(ManualTimeLogModalState state) async {
    if (state.widget.editMetadata == null) return;

    if (!state.mounted) return;
    state.setState(() => state.isLoading = true);

    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      // Fetch the instance to check its status and tracking type
      final instance = await ActivityInstanceRecord.getDocumentOnce(
        ActivityInstanceRecord.collectionForUser(userId)
            .doc(state.widget.editMetadata!.instanceId),
      );

      // Check if instance is completed and not a timer type
      // For non-timer types (binary, quantitative), show dialog with options
      bool shouldUncomplete = false;
      if (instance.status == 'completed' &&
          instance.templateTrackingType != 'time' &&
          instance.templateCategoryType != 'essential') {
        // Show dialog asking user what to do
        final userChoice = await showDialog<String>(
          context: state.context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Time Entry'),
            content: const Text(
                'This task/habit is marked as completed. What would you like to do?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop('uncomplete'),
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
                child: const Text('Uncomplete'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop('keep'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Keep Completed'),
              ),
            ],
          ),
        );

        if (userChoice == null || userChoice == 'cancel') {
          if (state.mounted) {
            state.setState(() => state.isLoading = false);
          }
          return;
        }

        shouldUncomplete = userChoice == 'uncomplete';
      } else {
        // For timer types or non-completed items, show simple confirmation
        final confirmed = await showDialog<bool>(
          context: state.context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Time Entry'),
            content: const Text(
                'Are you sure you want to delete this time entry? This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );

        if (confirmed != true) {
          if (state.mounted) {
            state.setState(() => state.isLoading = false);
          }
          return;
        }
      }

      // Uncomplete if user chose to uncomplete
      if (shouldUncomplete) {
        await ActivityInstanceService.uncompleteInstance(
          instanceId: state.widget.editMetadata!.instanceId,
        );
      }

      // Delete the time log session
      // For timer types, this will auto-uncomplete if time falls below target
      await TaskInstanceService.deleteTimeLogSession(
        instanceId: state.widget.editMetadata!.instanceId,
        sessionIndex: state.widget.editMetadata!.sessionIndex,
      );

      if (state.mounted) {
        Navigator.of(state.context).pop();
        state.widget.onSave();
      }
    } catch (e) {
      final rootContext =
          Navigator.of(state.context, rootNavigator: true).context;
      if (state.mounted) {
        Navigator.of(state.context).pop();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(
                content: Text('Failed to delete entry: ${e.toString()}'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        });
      }
    } finally {
      if (state.mounted) {
        state.setState(() => state.isLoading = false);
      }
    }
  }
}
