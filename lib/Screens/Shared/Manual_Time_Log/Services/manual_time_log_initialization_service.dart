import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Screens/Settings/default_time_estimates_service.dart';
import 'package:habit_tracker/Screens/Shared/Manual Time Log/manual_time_log_helper.dart';
import 'package:habit_tracker/Screens/Shared/Manual Time Log/Services/manual_time_log_helper_service.dart';
import 'package:habit_tracker/Screens/Shared/Manual Time Log/Services/manual_time_log_preview_service.dart';
import 'package:habit_tracker/Screens/Shared/Manual Time Log/Services/manual_time_log_search_service.dart';
import 'package:habit_tracker/Screens/Calendar/Helpers/calendar_models.dart';
import 'package:collection/collection.dart';

/// Service for initialization and loading operations
class ManualTimeLogInitializationService {
  /// Initialize the state
  static void initializeState(ManualTimeLogModalState state) {
    if (state.widget.initialStartTime != null) {
      // Ensure initial start time is on the selected date
      final initialStart = state.widget.initialStartTime!;
      state.startTime = DateTime(
        state.widget.selectedDate.year,
        state.widget.selectedDate.month,
        state.widget.selectedDate.day,
        initialStart.hour,
        initialStart.minute,
      );
    } else {
      final now = DateTime.now();
      state.startTime = DateTime(state.widget.selectedDate.year, state.widget.selectedDate.month,
          state.widget.selectedDate.day, now.hour, now.minute);
    }

    if (state.widget.initialEndTime != null) {
      // Use the provided end time as-is (preserves exact time from timer)
      // Only adjust date if needed for calendar display
      final initialEnd = state.widget.initialEndTime!;
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

      // If end time is on the next day (crossing midnight), keep it on next day
      // Otherwise, preserve the exact time but adjust date to match selected date
      if (endDateOnly.difference(selectedDateOnly).inDays == 1) {
        // End time is on next day - keep it as-is
        state.endTime = initialEnd;
      } else if (endDateOnly.difference(selectedDateOnly).inDays == 0) {
        // End time is on the same day - keep it as-is (preserves seconds)
        state.endTime = initialEnd;
      } else {
        // End time is on a different day - adjust date but preserve time
        state.endTime = DateTime(
          state.widget.selectedDate.year,
          state.widget.selectedDate.month,
          state.widget.selectedDate.day,
          initialEnd.hour,
          initialEnd.minute,
          initialEnd.second,
        );
      }
    } else {
      // Default to user's configured duration only when no end time provided (manual calendar entry)
      state.endTime = state.startTime.add(Duration(minutes: state.defaultDurationMinutes));
    }

    // Ensure end time is after start time
    // Only apply default if end time is invalid (shouldn't happen with timer)
    if (state.endTime.isBefore(state.startTime) ||
        state.endTime.isAtSameMomentAs(state.startTime)) {
      // This fallback should only happen for manual calendar entries
      state.endTime = state.startTime.add(Duration(minutes: state.defaultDurationMinutes));
    }
    loadDefaultDuration(state);
    loadActivities(state);
    loadCategories(state);

    // If editing, prefill the form
    if (state.widget.editMetadata != null) {
      state.selectedType = state.widget.editMetadata!.activityType;
      state.activityController.text = state.widget.editMetadata!.activityName;
      // Find and select the template if it exists
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await loadActivities(state); // Ensure activities are loaded
        await loadCategories(state); // Ensure categories are loaded
        if (state.mounted && state.widget.editMetadata!.templateId != null) {
          final template = state.allActivities.firstWhereOrNull(
            (a) => a.reference.id == state.widget.editMetadata!.templateId,
          );
          if (template != null) {
            state.setState(() {
              state.selectedTemplate = template;
              // Set category from template
              state.selectedCategory = state.allCategories.firstWhereOrNull(
                (c) =>
                    c.reference.id == template.categoryId ||
                    c.name == template.categoryName,
              );
            });
          }
        }
      });
    }

    // Initial preview update
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ManualTimeLogPreviewService.updatePreview(state);
    });

    state.activityController.addListener(() {
      ManualTimeLogSearchService.onSearchChanged(state);
    });
    state.activityFocusNode.addListener(() {
      if (!state.activityFocusNode.hasFocus) {
        // Delay hiding suggestions to allow tap
        Future.delayed(const Duration(milliseconds: 200), () {
          if (state.mounted) {
            state.setState(() => state.showSuggestions = false);
            ManualTimeLogSearchService.removeOverlay(state);
          }
        });
      } else {
        state.setState(() => state.showSuggestions = true);
        ManualTimeLogSearchService.onSearchChanged(state);
      }
    });
  }

  /// Load default duration from preferences
  static Future<void> loadDefaultDuration(ManualTimeLogModalState state) async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isNotEmpty) {
        final enableDefaultEstimates =
            await TimeLoggingPreferencesService.getEnableDefaultEstimates(
                userId);
        int durationMinutes = 10; // Default fallback
        if (enableDefaultEstimates) {
          durationMinutes =
              await TimeLoggingPreferencesService.getDefaultDurationMinutes(
                  userId);
        }
        if (state.mounted) {
          state.setState(() {
            state.defaultDurationMinutes = durationMinutes;
            // Update end time if no initial end time was provided (was set using default)
            // This ensures the end time uses the actual setting value instead of hardcoded 10
            if (state.widget.initialEndTime == null) {
              state.endTime =
                  state.startTime.add(Duration(minutes: state.defaultDurationMinutes));
            } else if (state.endTime.isBefore(state.startTime) ||
                state.endTime.isAtSameMomentAs(state.startTime)) {
              // Fallback for invalid end time even when initial was provided
              state.endTime =
                  state.startTime.add(Duration(minutes: state.defaultDurationMinutes));
            }
          });
        }
      }
    } catch (e) {
      // On error, keep default of 10 minutes
      print('Error loading default duration: $e');
    }
  }

  /// Load categories from backend
  static Future<void> loadCategories(ManualTimeLogModalState state) async {
    final uid = await waitForCurrentUserUid();
    if (uid.isEmpty) return;
    final categories = await queryCategoriesRecordOnce(
      userId: uid,
      callerTag: 'ManualTimeLogModal',
    );
    if (state.mounted) {
      state.setState(() {
        state.allCategories = categories;
        ManualTimeLogHelperService.updateDefaultCategory(state);
      });
    }
  }

  /// Load activities from backend
  static Future<void> loadActivities(ManualTimeLogModalState state) async {
    final uid = await waitForCurrentUserUid();
    if (uid.isEmpty) return;
    // Include essential items to ensure Essential Activities are fetched
    final activities = await queryActivitiesRecordOnce(
      userId: uid,
      includeEssentialItems: true,
    );
    if (state.mounted) {
      state.setState(() {
        state.allActivities = activities;
      });
    }
  }

  /// Dispose resources
  static void dispose(ManualTimeLogModalState state) {
    ManualTimeLogSearchService.removeOverlay(state);
    state.activityController.dispose();
    state.activityFocusNode.dispose();
  }
}
