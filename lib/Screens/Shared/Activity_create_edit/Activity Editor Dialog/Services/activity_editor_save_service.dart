import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/start_date_change_dialog.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/activity_update_broadcast.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/time_utils.dart';
import 'package:habit_tracker/Screens/Essential/essential_data_service.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Frequency_config/frequency_config_dialog.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Activity%20Editor%20Dialog/activity_editor_dialog.dart';
import 'activity_editor_helper_service.dart';
import 'activity_editor_frequency_service.dart';
import 'activity_editor_reminder_service.dart';

/// Service for activity editor save operations
class ActivityEditorSaveService {
  /// Save the activity (create or update)
  static Future<void> save(ActivityEditorDialogState state) async {
    if (state.titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(state.context).showSnackBar(
        const SnackBar(content: Text('Please enter a name')),
      );
      return;
    }

    if (state.selectedCategoryId == null) {
      ScaffoldMessenger.of(state.context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    final categories = ActivityEditorHelperService.getCategories(state);
    final selectedCategory = categories
        .where((c) => c.reference.id == state.selectedCategoryId)
        .firstOrNull;

    if (selectedCategory == null) {
      ScaffoldMessenger.of(state.context).showSnackBar(
        const SnackBar(content: Text('Selected category not found')),
      );
      return;
    }

    // Validate reminder times for one-time tasks
    if (!state.quickIsTaskRecurring && state.reminders.isNotEmpty) {
      final validationError = ActivityEditorReminderService.validateReminderTimes(state);
      if (validationError != null) {
        // Show error in a dialog instead of snackbar (snackbar appears behind dialog)
        await showDialog(
          context: state.context,
          builder: (context) => AlertDialog(
            title: const Text('Invalid Reminder Time'),
            content: Text(validationError),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }

    state.setState(() => state.isSaving = true);

    try {
      if (ActivityEditorHelperService.isEssential(state)) {
        // Use essential service
        if (state.widget.activity == null) {
          await createNewEssential(state, selectedCategory);
        } else {
          await updateExistingEssential(state, selectedCategory);
        }
      } else {
        // Use regular activity service
        if (state.widget.activity == null) {
          // CREATE NEW
          await createNewActivity(state, selectedCategory);
        } else {
          // UPDATE EXISTING
          await updateExistingActivity(state, selectedCategory);
        }
      }
    } catch (e) {
      if (!state.mounted) return;
      ScaffoldMessenger.of(state.context).showSnackBar(
        SnackBar(content: Text('Error saving: $e')),
      );
    } finally {
      if (state.mounted) state.setState(() => state.isSaving = false);
    }
  }

  /// Create a new activity
  static Future<void> createNewActivity(ActivityEditorDialogState state, CategoryRecord selectedCategory) async {
    final userId = await waitForCurrentUserUid();
    if (userId.isEmpty) return;
    dynamic targetValue;
    switch (state.selectedTrackingType) {
      case 'binary':
        targetValue = null;
        break;
      case 'quantitative':
        targetValue = state.targetNumber;
        break;
      case 'time':
        targetValue = state.targetDuration.inMinutes;
        break;
    }

    await createActivity(
      name: state.titleController.text.trim(),
      categoryId: state.selectedCategoryId!,
      categoryName: selectedCategory.name,
      trackingType: state.selectedTrackingType ?? 'binary',
      target: targetValue,
      isRecurring: state.quickIsTaskRecurring,
      userId: userId,
      priority: state.priority,
      unit: state.unit,
      description: state.descriptionController.text.trim().isNotEmpty
          ? state.descriptionController.text.trim()
          : null,
      categoryType: state.widget.isHabit ? 'habit' : 'task',
      dueTime: state.selectedDueTime != null
          ? TimeUtils.timeOfDayToString(state.selectedDueTime!)
          : null,
      // Frequency fields
      frequencyType: state.quickIsTaskRecurring && state.frequencyConfig != null
          ? state.frequencyConfig!.type.toString().split('.').last
          : null,
      everyXValue: state.quickIsTaskRecurring &&
              state.frequencyConfig?.type == FrequencyType.everyXPeriod
          ? state.frequencyConfig!.everyXValue
          : null,
      everyXPeriodType: state.quickIsTaskRecurring &&
              state.frequencyConfig?.type == FrequencyType.everyXPeriod
          ? state.frequencyConfig!.everyXPeriodType.toString().split('.').last
          : null,
      timesPerPeriod: state.quickIsTaskRecurring &&
              state.frequencyConfig?.type == FrequencyType.timesPerPeriod
          ? state.frequencyConfig!.timesPerPeriod
          : null,
      periodType: state.quickIsTaskRecurring &&
              state.frequencyConfig?.type == FrequencyType.timesPerPeriod
          ? state.frequencyConfig!.periodType.toString().split('.').last
          : null,
      specificDays: state.quickIsTaskRecurring &&
              state.frequencyConfig?.type == FrequencyType.specificDays
          ? state.frequencyConfig!.selectedDays
          : null,
      startDate: state.quickIsTaskRecurring ? state.frequencyConfig?.startDate : null,
      endDate: state.quickIsTaskRecurring
          ? state.frequencyConfig?.endDate
          : state.endDate, // For one-time tasks, uses _endDate
      reminders: state.reminders.isNotEmpty
          ? ReminderConfigList.toMapList(state.reminders)
          : null,
      // For one-time tasks that have a specific date
      dueDate: (!state.quickIsTaskRecurring) ? state.dueDate : null,
      timeEstimateMinutes: state.timeEstimateMinutes != null
          ? state.timeEstimateMinutes!.clamp(1, 600)
          : null,
    );

    if (state.mounted) {
      Navigator.pop(state.context, true);
    }
    state.widget.onSave?.call(null); // Pass null or new record if available
  }

  /// Create a new essential
  static Future<void> createNewEssential(ActivityEditorDialogState state, CategoryRecord selectedCategory) async {
    final userId = await waitForCurrentUserUid();
    if (userId.isEmpty) return;
    final freqPayload = ActivityEditorFrequencyService.frequencyPayloadForEssential(state);
    final templateRef = await essentialService.createessentialTemplate(
      name: state.titleController.text.trim(),
      description: state.descriptionController.text.trim().isNotEmpty
          ? state.descriptionController.text.trim()
          : null,
      categoryId: state.selectedCategoryId,
      categoryName: selectedCategory.name,
      trackingType: 'binary', // Essentials are always binary
      target: null,
      unit: null,
      userId: userId,
      timeEstimateMinutes: state.timeEstimateMinutes != null
          ? state.timeEstimateMinutes!.clamp(1, 600)
          : null,
      dueTime: state.selectedDueTime != null
          ? TimeUtils.timeOfDayToString(state.selectedDueTime!)
          : null,
      frequencyType: freqPayload.frequencyType,
      everyXValue: freqPayload.everyXValue,
      everyXPeriodType: freqPayload.everyXPeriodType,
      specificDays: freqPayload.specificDays,
    );

    // Fetch created template
    ActivityRecord? created;
    final createdDoc = await templateRef.get();
    if (createdDoc.exists) {
      created = ActivityRecord.fromSnapshot(createdDoc);
    }

    ActivityTemplateEvents.broadcastTemplateUpdated(
      templateId: templateRef.id,
      context: {
        'action': 'created',
        'source': 'ActivityEditorDialog',
        'categoryType': 'essential',
        if (state.timeEstimateMinutes != null)
          'timeEstimateMinutes': state.timeEstimateMinutes,
      },
    );

    if (state.mounted) {
      Navigator.of(state.context).pop(created);
      // Show snackbar after pop to avoid Navigator lock conflicts
      ScaffoldMessenger.of(state.context).showSnackBar(
        const SnackBar(
          content: Text('Essential template created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
    state.widget.onSave?.call(created);
  }

  /// Update existing essential
  static Future<void> updateExistingEssential(ActivityEditorDialogState state, CategoryRecord selectedCategory) async {
    final userId = await waitForCurrentUserUid();
    if (userId.isEmpty) return;
    final docRef = state.widget.activity!.reference;
    final freqPayload = ActivityEditorFrequencyService.frequencyPayloadForEssential(state);

    await essentialService.updateessentialTemplate(
      templateId: docRef.id,
      name: state.titleController.text.trim(),
      description: state.descriptionController.text.trim().isNotEmpty
          ? state.descriptionController.text.trim()
          : null,
      categoryId: state.selectedCategoryId,
      categoryName: selectedCategory.name,
      trackingType: 'binary', // Essentials are always binary
      target: null,
      unit: null,
      userId: userId,
      timeEstimateMinutes: state.timeEstimateMinutes != null
          ? state.timeEstimateMinutes!.clamp(1, 600)
          : null,
      dueTime: state.selectedDueTime != null
          ? TimeUtils.timeOfDayToString(state.selectedDueTime!)
          : null,
      frequencyType: freqPayload.frequencyType,
      everyXValue: freqPayload.everyXValue,
      everyXPeriodType: freqPayload.everyXPeriodType,
      specificDays: freqPayload.specificDays,
    );

    // Fetch updated template
    final updatedDoc = await docRef.get();
    ActivityRecord? updated;
    if (updatedDoc.exists && state.mounted) {
      updated = ActivityRecord.fromSnapshot(updatedDoc);
    }

    ActivityTemplateEvents.broadcastTemplateUpdated(
      templateId: docRef.id,
      context: {
        'action': 'updated',
        'source': 'ActivityEditorDialog',
        'categoryType': 'essential',
        if (state.timeEstimateMinutes != null)
          'timeEstimateMinutes': state.timeEstimateMinutes,
      },
    );

    if (state.mounted) {
      Navigator.of(state.context).pop(updated);
      // Show snackbar after pop to avoid Navigator lock conflicts
      ScaffoldMessenger.of(state.context).showSnackBar(
        const SnackBar(
          content: Text('Essential template updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
    state.widget.onSave?.call(updated);
  }

  /// Update existing activity
  static Future<void> updateExistingActivity(ActivityEditorDialogState state, CategoryRecord selectedCategory) async {
    final docRef = state.widget.activity!.reference;

    final updateData = createActivityRecordData(
      isRecurring: state.quickIsTaskRecurring,
      name: state.titleController.text.trim(),
      categoryId: state.selectedCategoryId,
      categoryName: selectedCategory.name,
      trackingType: state.selectedTrackingType,
      unit: state.unit,
      target: state.selectedTrackingType == 'quantitative'
          ? state.targetNumber
          : state.selectedTrackingType == 'time'
              ? state.targetDuration.inMinutes
              : null,
      timeEstimateMinutes: state.timeEstimateMinutes != null
          ? state.timeEstimateMinutes!.clamp(1, 600)
          : null,
      dueDate: (!state.quickIsTaskRecurring) ? state.dueDate : null,
      dueTime: state.selectedDueTime != null
          ? TimeUtils.timeOfDayToString(state.selectedDueTime!)
          : null,
      specificDays: state.quickIsTaskRecurring &&
              state.frequencyConfig != null &&
              state.frequencyConfig!.type == FrequencyType.specificDays
          ? state.frequencyConfig!.selectedDays
          : null,
      lastUpdated: DateTime.now(),
      categoryType: state.widget.isHabit ? 'habit' : 'task',
      priority: state.priority,
      description: state.descriptionController.text.trim().isNotEmpty
          ? state.descriptionController.text.trim()
          : null,
      isActive: true,
      startDate: state.quickIsTaskRecurring && state.frequencyConfig != null
          ? state.frequencyConfig!.startDate
          : DateTime.now(),
      endDate: state.quickIsTaskRecurring && state.frequencyConfig != null
          ? state.frequencyConfig!.endDate
          : state.endDate,
      frequencyType: state.quickIsTaskRecurring && state.frequencyConfig != null
          ? state.frequencyConfig!.type.toString().split('.').last
          : null,
      everyXValue: state.quickIsTaskRecurring &&
              state.frequencyConfig != null &&
              state.frequencyConfig!.type == FrequencyType.everyXPeriod
          ? state.frequencyConfig!.everyXValue
          : null,
      everyXPeriodType: state.quickIsTaskRecurring &&
              state.frequencyConfig != null &&
              state.frequencyConfig!.type == FrequencyType.everyXPeriod
          ? state.frequencyConfig!.everyXPeriodType.toString().split('.').last
          : null,
      reminders: state.reminders.isNotEmpty
          ? ReminderConfigList.toMapList(state.reminders)
          : null,
      timesPerPeriod: state.quickIsTaskRecurring &&
              state.frequencyConfig != null &&
              state.frequencyConfig!.type == FrequencyType.timesPerPeriod
          ? state.frequencyConfig!.timesPerPeriod
          : null,
      periodType: state.quickIsTaskRecurring &&
              state.frequencyConfig != null &&
              state.frequencyConfig!.type == FrequencyType.timesPerPeriod
          ? state.frequencyConfig!.periodType.toString().split('.').last
          : null,
    );

    // Ensure nullable fields are explicitly cleared when needed
    updateData['dueDate'] = (!state.quickIsTaskRecurring) ? state.dueDate : null;
    updateData['dueTime'] = state.selectedDueTime != null
        ? TimeUtils.timeOfDayToString(state.selectedDueTime!)
        : null;
    updateData['reminders'] =
        state.reminders.isNotEmpty ? ReminderConfigList.toMapList(state.reminders) : null;
    updateData['frequencyType'] =
        state.quickIsTaskRecurring && state.frequencyConfig != null
            ? state.frequencyConfig!.type.toString().split('.').last
            : null;
    updateData['everyXValue'] = state.quickIsTaskRecurring &&
            state.frequencyConfig != null &&
            state.frequencyConfig!.type == FrequencyType.everyXPeriod
        ? state.frequencyConfig!.everyXValue
        : null;
    updateData['everyXPeriodType'] = state.quickIsTaskRecurring &&
            state.frequencyConfig != null &&
            state.frequencyConfig!.type == FrequencyType.everyXPeriod
        ? state.frequencyConfig!.everyXPeriodType.toString().split('.').last
        : null;
    updateData['timesPerPeriod'] = state.quickIsTaskRecurring &&
            state.frequencyConfig != null &&
            state.frequencyConfig!.type == FrequencyType.timesPerPeriod
        ? state.frequencyConfig!.timesPerPeriod
        : null;
    updateData['periodType'] = state.quickIsTaskRecurring &&
            state.frequencyConfig != null &&
            state.frequencyConfig!.type == FrequencyType.timesPerPeriod
        ? state.frequencyConfig!.periodType.toString().split('.').last
        : null;
    updateData['specificDays'] = state.quickIsTaskRecurring &&
            state.frequencyConfig != null &&
            state.frequencyConfig!.type == FrequencyType.specificDays
        ? state.frequencyConfig!.selectedDays
        : null;
    updateData['startDate'] = state.quickIsTaskRecurring && state.frequencyConfig != null
        ? state.frequencyConfig!.startDate
        : null;
    updateData['endDate'] = state.quickIsTaskRecurring && state.frequencyConfig != null
        ? state.frequencyConfig!.endDate
        : state.endDate;

    // Check for frequency changes (Routine Main page from edit_task.dart)
    if (state.quickIsTaskRecurring &&
        state.frequencyConfig != null &&
        ActivityEditorFrequencyService.hasFrequencyChanged(state)) {
      // Only show dialog and regenerate if START DATE specifically changed
      final startDateChanged = state.originalStartDate != null &&
          state.frequencyConfig!.startDate != state.originalStartDate;

      if (startDateChanged) {
        final shouldProceed = await StartDateChangeDialog.show(
          context: state.context,
          oldStartDate: state.originalStartDate ?? DateTime.now(),
          newStartDate: state.frequencyConfig!.startDate,
          activityName: state.titleController.text.trim(),
        );

        if (!shouldProceed) {
          return;
        }

        try {
          await ActivityInstanceService.regenerateInstancesFromStartDate(
            templateId: state.widget.activity!.reference.id,
            template: state.widget.activity!,
            newStartDate: state.frequencyConfig!.startDate,
          );
        } catch (e) {
          if (!state.mounted) return;
          ScaffoldMessenger.of(state.context).showSnackBar(
            SnackBar(content: Text('Error updating instances: $e')),
          );
          return;
        }
      }
      // If frequency changed but NOT start date, no dialog needed
    }

    if (state.quickIsTaskRecurring && state.frequencyConfig != null) {
      // Check end date changes
      final originalEndDate = state.originalFrequencyConfig?.endDate;
      final newEndDate = state.frequencyConfig!.endDate;
      if (originalEndDate != newEndDate && newEndDate != null) {
        if (originalEndDate == null || newEndDate.isBefore(originalEndDate)) {
          try {
            await ActivityInstanceService.cleanupInstancesBeyondEndDate(
              templateId: state.widget.activity!.reference.id,
              newEndDate: newEndDate,
            );
          } catch (e) {
            // ignore
          }
        }
      }
    }

    await docRef.update(updateData);
    ActivityTemplateEvents.broadcastTemplateUpdated(
      templateId: docRef.id,
      context: {
        'updatedFields': updateData.keys.toList(),
        if (updateData.containsKey('timeEstimateMinutes'))
          'timeEstimateMinutes': updateData['timeEstimateMinutes'],
      },
    );

    // Check for category change for history update option
    // Only show dialog for habits - tasks always use current & future only
    // One-time tasks also don't need the dialog (only one instance)
    bool updateHistorical = false;
    if (state.widget.activity!.categoryId != state.selectedCategoryId) {
      // For tasks (including one-time tasks), always use current & future only
      // For habits, show dialog to ask about historical instances
      if (state.widget.isHabit) {
        // Show dialog only for habits
        final userChoice = await showDialog<bool>(
          context: state.context,
          builder: (context) => AlertDialog(
            title: const Text('Update Category'),
            content: const Text(
                'You changed the category. Do you want to apply this change to past history as well?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Current & Future Only'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Include History (1 Year)'),
              ),
            ],
          ),
        );
        // If user dismisses dialog (null), default to false (Current only)
        updateHistorical = userChoice ?? false;
      } else {
        // For tasks, always use current & future only (no historical tracking)
        updateHistorical = false;
      }
    }

    // Update instances (Batch)
    try {
      final containsDueDateUpdate =
          !state.quickIsTaskRecurring && updateData.containsKey('dueDate');
      final hasDueTimeUpdate = updateData.containsKey('dueTime');

      final instanceUpdates = <String, dynamic>{
        'templateName': updateData['name'],
        'templateCategoryId': updateData['categoryId'],
        'templateCategoryName': updateData['categoryName'],
        'templateTrackingType': updateData['trackingType'],
        'templateTarget': updateData['target'],
        'templateUnit': updateData['unit'],
        'templatePriority': updateData['priority'],
        'templateDescription': updateData['description'],
        'templateEveryXValue': updateData['everyXValue'] ?? 0,
        'templateEveryXPeriodType': updateData['everyXPeriodType'] ?? '',
        'templateTimesPerPeriod': updateData['timesPerPeriod'] ?? 0,
        'templatePeriodType': updateData['periodType'] ?? '',
        'templateTimeEstimateMinutes': state.timeEstimateMinutes != null
            ? state.timeEstimateMinutes!.clamp(1, 600)
            : null,
      };

      if (containsDueDateUpdate) {
        instanceUpdates['dueDate'] = updateData['dueDate'];
      }
      if (hasDueTimeUpdate) {
        instanceUpdates['dueTime'] = updateData['dueTime'];
        instanceUpdates['templateDueTime'] = updateData['dueTime'];
      }

      await ActivityInstanceService.updateActivityInstancesCascade(
        templateId: state.widget.activity!.reference.id,
        updates: instanceUpdates,
        updateHistorical: updateHistorical,
      );
    } catch (e) {
      print('❌ Error updating instances: $e');
      if (state.mounted) {
        ScaffoldMessenger.of(state.context).showSnackBar(
          SnackBar(content: Text('Warning: Instances update failed: $e')),
        );
      }
    }

    // Refresh UI
    final updatedRecord =
        ActivityRecord.getDocumentFromData(updateData, docRef);
    state.widget.onSave?.call(updatedRecord);

    if (state.mounted) {
      Navigator.pop(state.context, true);
    }
  }
}
