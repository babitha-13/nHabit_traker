import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:habit_tracker/features/Shared/Manual_Time_Log/manual_time_log_helper.dart';

/// Service for shared utility methods
class ManualTimeLogHelperService {
  /// Update default category based on selected type and template
  static void updateDefaultCategory(ManualTimeLogModalState state) {
    if (state.selectedTemplate != null) {
      state.selectedCategory = state.allCategories.firstWhereOrNull((c) =>
          c.reference.id == state.selectedTemplate?.categoryId ||
          c.name == state.selectedTemplate?.categoryName);
      return;
    }

    if (state.selectedType == 'task') {
      state.selectedCategory = state.allCategories.firstWhereOrNull(
          (c) => c.name == 'Inbox' && c.categoryType == 'task');
    } else if (state.selectedType == 'habit') {
      // For habits, set to null initially - user must select from existing habit categories
      // Or find the first habit category as a default
      state.selectedCategory = state.allCategories
          .firstWhereOrNull((c) => c.categoryType == 'habit');
    } else if (state.selectedType == 'essential') {
      state.selectedCategory = state.allCategories.firstWhereOrNull((c) =>
          (c.name == 'Others' || c.name == 'Other') &&
          c.categoryType == 'essential');

      // Fallback if "Others" not found for essential
      state.selectedCategory ??= state.allCategories.firstWhereOrNull((c) =>
          c.name == 'essential' ||
          c.name == 'Essential' ||
          c.categoryType == 'essential');
    }
  }

  /// Determine if should mark complete on save
  static bool shouldMarkCompleteOnSave(ManualTimeLogModalState state) {
    bool shouldComplete = state.widget.markCompleteOnSave;
    if (state.selectedTemplate != null &&
        state.selectedTemplate?.trackingType == 'binary' &&
        state.markAsComplete) {
      shouldComplete = true;
    }
    return shouldComplete;
  }

  /// Handle back button - show warning if user has unsaved changes
  static Future<bool> onWillPop(ManualTimeLogModalState state) async {
    // Check if user has made any changes
    final hasChanges = state.activityController.text.isNotEmpty ||
        state.selectedTemplate != null ||
        state.markAsComplete ||
        state.quantityValue > 0;

    if (!hasChanges) {
      // No changes, allow back navigation
      return true;
    }

    // Show warning dialog
    final shouldDiscard = await showDialog<bool>(
      context: state.context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text(
          'You have unsaved changes. Are you sure you want to discard them?',
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
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return shouldDiscard ?? false;
  }
}
