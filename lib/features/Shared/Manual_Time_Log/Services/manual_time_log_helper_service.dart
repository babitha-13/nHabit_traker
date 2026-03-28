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
    final trackingType = state.selectedTemplate?.trackingType ?? 'binary';

    // For binary entries (including newly typed tasks with no selected
    // template yet), always honor the explicit checkbox.
    if (trackingType == 'binary' && state.markAsComplete) {
      shouldComplete = true;
    }
    return shouldComplete;
  }

  static String _normalizeType(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'essentials') return 'essential';
    if (normalized == 'tasks') return 'task';
    if (normalized == 'habits') return 'habit';
    return normalized;
  }

  static DateTime _resolveInitialStartTime(ManualTimeLogModalState state) {
    final initialStart = state.widget.initialStartTime;
    if (initialStart == null) {
      return state.startTime;
    }

    return DateTime(
      state.widget.selectedDate.year,
      state.widget.selectedDate.month,
      state.widget.selectedDate.day,
      initialStart.hour,
      initialStart.minute,
    );
  }

  static DateTime _resolveInitialEndTime(ManualTimeLogModalState state) {
    final initialEnd = state.widget.initialEndTime;
    if (initialEnd == null) {
      return state.endTime;
    }

    final endDateOnly = DateTime(
      initialEnd.year,
      initialEnd.month,
      initialEnd.day,
    );
    final selectedDateOnly = DateTime(
      state.widget.selectedDate.year,
      state.widget.selectedDate.month,
      state.widget.selectedDate.day,
    );
    final dayDelta = endDateOnly.difference(selectedDateOnly).inDays;

    if (dayDelta == 1 || dayDelta == 0) {
      return initialEnd;
    }

    return DateTime(
      state.widget.selectedDate.year,
      state.widget.selectedDate.month,
      state.widget.selectedDate.day,
      initialEnd.hour,
      initialEnd.minute,
      initialEnd.second,
    );
  }

  static bool _isSameMinute(DateTime a, DateTime b) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
  }

  static bool _hasEditModeChanges(ManualTimeLogModalState state) {
    final metadata = state.widget.editMetadata;
    if (metadata == null) return false;

    final nameChanged =
        state.activityController.text.trim() != metadata.activityName.trim();
    final typeChanged = _normalizeType(state.selectedType) !=
        _normalizeType(metadata.activityType);
    final startChanged =
        !_isSameMinute(state.startTime, _resolveInitialStartTime(state));
    final endChanged =
        !_isSameMinute(state.endTime, _resolveInitialEndTime(state));

    // A newly selected template means metadata would change on save.
    final templateChanged = state.selectedTemplate != null &&
        state.selectedTemplate!.reference.id != metadata.templateId;
    final completionChanged = state.markAsComplete || state.quantityValue > 0;

    return nameChanged ||
        typeChanged ||
        startChanged ||
        endChanged ||
        templateChanged ||
        completionChanged;
  }

  static bool _hasCreateModeChanges(ManualTimeLogModalState state) {
    final hasTypedName = state.activityController.text.trim().isNotEmpty;
    final hasTemplateSelection = state.selectedTemplate != null;
    final hasCompletionChanges =
        state.markAsComplete || state.quantityValue > 0;
    final typeChanged = _normalizeType(state.selectedType) != 'task';
    final startChanged =
        !_isSameMinute(state.startTime, _resolveInitialStartTime(state));
    final endChanged =
        !_isSameMinute(state.endTime, _resolveInitialEndTime(state));

    return hasTypedName ||
        hasTemplateSelection ||
        hasCompletionChanges ||
        typeChanged ||
        startChanged ||
        endChanged;
  }

  /// Handle back button - show warning if user has unsaved changes
  static Future<bool> onWillPop(ManualTimeLogModalState state) async {
    final hasChanges = state.widget.editMetadata != null
        ? _hasEditModeChanges(state)
        : _hasCreateModeChanges(state);

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
            child: const Text('Back'),
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
