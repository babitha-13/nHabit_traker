import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/services/Activtity/activity_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/services/category_color_util.dart';
import 'package:habit_tracker/features/Essential/create_essential_item_dialog.dart';
import 'package:habit_tracker/features/activity%20editor/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';
import 'package:habit_tracker/features/Routine/Backend_data/routine_service.dart';

/// Routine Main page mixin for CreateRoutinePage that contains all business logic
/// This separates business logic from UI code
mixin CreateRoutinePageLogic<T extends StatefulWidget> on State<T> {
  // State variables
  List<ActivityRecord> allActivities = [];
  List<ActivityRecord> filteredActivities = [];
  List<ActivityRecord> selectedItems = [];
  Set<String> newlyCreatedItemIds = {};
  bool isLoading = true;
  bool isSaving = false;
  bool isSelectedItemsExpanded = true;
  bool wasKeyboardVisible = false;
  // Current routine (fetched from Firestore when editing)
  RoutineRecord? currentRoutine;
  // Reminder state
  TimeOfDay? startTime;
  List<ReminderConfig> reminders = [];
  String? reminderFrequencyType;
  int everyXValue = 1;
  String? everyXPeriodType;
  List<int> specificDays = [];
  bool remindersEnabled = false;

  /// Fetch the latest routine document and load activities in parallel
  /// Returns the routine name if successful, null otherwise
  Future<String?> fetchLatestRoutineAndLoadActivities(
      RoutineRecord? existingRoutine) async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty || existingRoutine == null) {
        loadActivities();
        return null;
      }

      // Load routine and activities in parallel for faster initialization
      final results = await Future.wait([
        RoutineRecord.collectionForUser(userId)
            .doc(existingRoutine.reference.id)
            .get()
            .then((doc) =>
                doc.exists ? RoutineRecord.fromSnapshot(doc) : existingRoutine),
        queryActivitiesRecordOnce(
          userId: userId,
          includeEssentialItems: true,
        ),
      ]);

      if (!mounted) return null;

      final latestRoutine = results[0] as RoutineRecord;
      final activities = results[1] as List<ActivityRecord>;

      // Filter activities
      final filteredActivitiesResult = activities.where((activity) {
        // Keep all habits (always recurring)
        if (activity.categoryType == 'habit') return true;
        // Keep all Essential Activities
        if (activity.categoryType == 'essential') return true;
        // For tasks: exclude completed/skipped one-time tasks
        if (activity.categoryType == 'task') {
          // Keep recurring tasks (regardless of status)
          if (activity.isRecurring) return true;
          // For one-time tasks:
          // - Exclude if inactive (completed tasks get marked inactive)
          // - Exclude if status is explicitly 'complete' or 'skipped'
          if (!activity.isActive) return false;
          return activity.status != 'complete' && activity.status != 'skipped';
        }
        // Keep everything else by default
        return true;
      }).toList();

      // Batch all state updates
      setState(() {
        currentRoutine = latestRoutine;
        allActivities = filteredActivitiesResult;
        filteredActivities = filteredActivitiesResult;
        isLoading = false;
      });

      // Initialize form from latest routine
      initializeFromRoutine(latestRoutine);
      // Load existing items from current routine
      loadExistingItems();

      // Return routine name for UI to set controller
      return latestRoutine.name;
    } catch (e) {
      // Fallback to existingRoutine if fetch fails
      if (mounted) {
        setState(() {
          currentRoutine = existingRoutine;
        });
        initializeFromRoutine(existingRoutine!);
        loadActivities();
        return existingRoutine.name;
      }
    }
    return null;
  }

  /// Initialize form state from a routine record
  void initializeFromRoutine(RoutineRecord routine) {
    // Note: _nameController is managed in UI, so we don't set it here
    // The UI will handle setting the controller text
    // Load existing reminder config
    if (routine.hasDueTime()) {
      startTime = TimeUtils.stringToTimeOfDay(routine.dueTime);
    }
    if (routine.hasReminders()) {
      reminders = ReminderConfigList.fromMapList(routine.reminders);
    }
    reminderFrequencyType = routine.reminderFrequencyType.isEmpty
        ? null
        : routine.reminderFrequencyType;
    everyXValue = routine.everyXValue;
    everyXPeriodType =
        routine.everyXPeriodType.isEmpty ? null : routine.everyXPeriodType;
    specificDays = List.from(routine.specificDays);
    remindersEnabled = routine.remindersEnabled;
  }

  Future<void> loadActivities() async {
    if (!mounted) return;
    // Only set loading state if it's not already true
    if (!isLoading) {
      setState(() {
        isLoading = true;
      });
    }
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isNotEmpty) {
        // Load all activities including Essential Activities
        final activities = await queryActivitiesRecordOnce(
          userId: userId,
          includeEssentialItems: true,
        );
        if (!mounted) return;

        // Filter out completed/skipped one-time tasks (keep recurring tasks, habits, and Essential Activities)
        final filteredActivitiesResult = activities.where((activity) {
          // Keep all habits (always recurring)
          if (activity.categoryType == 'habit') return true;
          // Keep all Essential Activities
          if (activity.categoryType == 'essential') return true;
          // For tasks: exclude completed/skipped one-time tasks
          if (activity.categoryType == 'task') {
            // Keep recurring tasks (regardless of status)
            if (activity.isRecurring) return true;
            // For one-time tasks:
            // - Exclude if inactive (completed tasks get marked inactive)
            // - Exclude if status is explicitly 'complete' or 'skipped'
            if (!activity.isActive) return false;
            return activity.status != 'complete' &&
                activity.status != 'skipped';
          }
          // Keep everything else by default
          return true;
        }).toList();

        // Batch state updates
        if (mounted) {
          setState(() {
            allActivities = filteredActivitiesResult;
            filteredActivities = filteredActivitiesResult;
            isLoading = false;
          });
          // If editing, load existing items from current routine
          if (currentRoutine != null) {
            loadExistingItems();
          }
        }
      } else {
        // Batch state updates for empty user case
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      }
    } catch (e) {
      // Batch state updates for error case
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void loadExistingItems() {
    if (currentRoutine == null) return;
    final existingItems = <ActivityRecord>[];
    final orderedIds = currentRoutine!.itemOrder.isNotEmpty
        ? currentRoutine!.itemOrder
        : currentRoutine!.itemIds;
    for (final itemId in orderedIds) {
      try {
        final activity =
            allActivities.firstWhere((a) => a.reference.id == itemId);
        existingItems.add(activity);
      } catch (e) {
        // Silently ignore missing activities - they may have been deleted
        print('Activity not found for routine item: $itemId');
      }
    }
    setState(() {
      selectedItems = existingItems;
    });
  }

  void filterActivities(String query) {
    setState(() {
      filteredActivities = allActivities.where((activity) {
        return activity.name.toLowerCase().contains(query.toLowerCase()) ||
            activity.categoryName.toLowerCase().contains(query.toLowerCase());
      }).toList();
    });
  }

  void addItem(ActivityRecord activity) {
    if (!selectedItems
        .any((item) => item.reference.id == activity.reference.id)) {
      setState(() {
        selectedItems.add(activity);
      });
    }
  }

  void removeItem(ActivityRecord activity) {
    setState(() {
      selectedItems
          .removeWhere((item) => item.reference.id == activity.reference.id);
    });
  }

  void reorderItems(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = selectedItems.removeAt(oldIndex);
      selectedItems.insert(newIndex, item);
    });
  }

  Future<void> showDeleteConfirmation(ActivityRecord activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete essential Item'),
        content: Text(
          'Are you sure you want to permanently delete "${activity.name}"?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await deleteEssentialItem(activity);
    }
  }

  Future<void> deleteEssentialItem(ActivityRecord activity) async {
    try {
      // Call business logic to delete the activity
      await ActivityService.deleteActivity(activity.reference);

      // Update local state to remove deleted item from all lists
      setState(() {
        allActivities
            .removeWhere((item) => item.reference.id == activity.reference.id);
        filteredActivities
            .removeWhere((item) => item.reference.id == activity.reference.id);
        selectedItems
            .removeWhere((item) => item.reference.id == activity.reference.id);
        newlyCreatedItemIds.remove(activity.reference.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('essential item "${activity.name}" deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting essential item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> createNewEssentialItem(
      Function(ActivityRecord) onItemCreated) async {
    showDialog(
      context: context,
      builder: (context) => CreateEssentialItemDialog(
        onItemCreated: (activity) {
          setState(() {
            allActivities.add(activity);
            filteredActivities.add(activity);
            selectedItems.add(activity);
            newlyCreatedItemIds.add(activity.reference.id);
          });
          onItemCreated(activity);
        },
      ),
    );
  }

  Future<void> saveRoutine(TextEditingController nameController) async {
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one item to the routine'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() {
      isSaving = true;
    });
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      final itemIds = selectedItems.map((item) => item.reference.id).toList();
      final itemOrder = selectedItems.map((item) => item.reference.id).toList();
      final itemNames = selectedItems.map((item) => item.name).toList();
      final itemTypes = selectedItems.map((item) => item.categoryType).toList();
      print('🔍 DEBUG: - name: ${nameController.text.trim()}');
      if (currentRoutine != null) {
        // Update existing routine using current routine's ID
        await RoutineService.updateRoutine(
          routineId: currentRoutine!.reference.id,
          name: nameController.text.trim(),
          itemIds: itemIds,
          itemOrder: itemOrder,
          userId: userId,
          dueTime: startTime != null
              ? TimeUtils.timeOfDayToString(startTime!)
              : null,
          clearDueTime: startTime == null,
          reminders: reminders.isNotEmpty
              ? ReminderConfigList.toMapList(reminders)
              : null,
          reminderFrequencyType: reminderFrequencyType,
          everyXValue: reminderFrequencyType == 'every_x' ? everyXValue : null,
          everyXPeriodType:
              reminderFrequencyType == 'every_x' ? everyXPeriodType : null,
          specificDays: reminderFrequencyType == 'specific_days' &&
                  specificDays.isNotEmpty
              ? specificDays
              : null,
          remindersEnabled: remindersEnabled,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Routine "${nameController.text.trim()}" updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(<String, dynamic>{
            'routineId': currentRoutine!.reference.id,
            'itemIds': itemIds,
            'itemOrder': itemOrder,
            'itemNames': itemNames,
            'itemTypes': itemTypes,
          });
        }
      } else {
        // Create new routine
        final ref = await RoutineService.createRoutine(
          name: nameController.text.trim(),
          itemIds: itemIds,
          itemOrder: itemOrder,
          userId: userId,
          dueTime: startTime != null
              ? TimeUtils.timeOfDayToString(startTime!)
              : null,
          reminders: reminders.isNotEmpty
              ? ReminderConfigList.toMapList(reminders)
              : null,
          reminderFrequencyType: reminderFrequencyType,
          everyXValue: reminderFrequencyType == 'every_x' ? everyXValue : null,
          everyXPeriodType:
              reminderFrequencyType == 'every_x' ? everyXPeriodType : null,
          specificDays: reminderFrequencyType == 'specific_days' &&
                  specificDays.isNotEmpty
              ? specificDays
              : null,
          remindersEnabled: remindersEnabled,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Routine "${nameController.text.trim()}" created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(<String, dynamic>{
            'routineId': ref.id,
            'itemIds': itemIds,
            'itemOrder': itemOrder,
            'itemNames': itemNames,
            'itemTypes': itemTypes,
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving routine: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Color getItemTypeColor(String categoryType) {
    switch (categoryType) {
      case 'habit':
        return Colors.green;
      case 'task':
        return const Color(0xFF2F4F4F); // Dark Slate Gray (charcoal) for tasks
      case 'essential':
        return Colors.grey.shade600; // Muted color for essential
      default:
        return Colors.grey;
    }
  }

  Color getStripeColor(ActivityRecord activity) {
    // For habits, use category color if available, otherwise use type color
    if (activity.categoryType == 'habit') {
      try {
        final hex = CategoryColorUtil.hexForName(activity.categoryName);
        return Color(int.parse(hex.replaceFirst('#', '0xFF')));
      } catch (_) {
        return getItemTypeColor(activity.categoryType);
      }
    }
    // For tasks and essential, use type color
    return getItemTypeColor(activity.categoryType);
  }
}
