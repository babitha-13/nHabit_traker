import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/features/Settings/default_time_estimates_service.dart';
import 'package:habit_tracker/features/activity%20editor/Frequency_config/frequency_config_model.dart';
import 'package:habit_tracker/features/activity%20editor/Frequency_config/frequency_config_dialog.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';
import 'package:habit_tracker/features/activity%20editor/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/features/activity%20editor/presentation/activity_editor_dialog.dart';
import 'activity_editor_frequency_service.dart';
import 'activity_editor_helper_service.dart';

/// Service for activity editor initialization and loading
class ActivityEditorInitializationService {
  /// Initialize the state
  static void initializeState(ActivityEditorDialogState state) {
    final t = state.widget.activity;

    // Initialize recurring state based on type
    if (ActivityEditorHelperService.isEssential(state)) {
      // Essentials: frequency can be enabled/disabled
      state.frequencyEnabled = t?.isRecurring ?? false;
      state.quickIsTaskRecurring = state.frequencyEnabled;
      if (t == null) {
        state.frequencyConfig = FrequencyConfig(
          type: FrequencyType.everyXPeriod,
          startDate: DateTime.now(),
        );
      }
    } else if (state.widget.isHabit) {
      state.quickIsTaskRecurring = true;
      // Default frequency for new habits
      if (t == null) {
        state.frequencyConfig = FrequencyConfig(
          type: FrequencyType.everyXPeriod,
          startDate: DateTime.now(),
        );
      }
    } else {
      state.quickIsTaskRecurring = t?.isRecurring ?? false;
    }

    // Controllers are late final and must be initialized in initState, not here
    // This method is called from initState after controllers are initialized

    state.priority = t?.priority ?? 1;
    state.selectedTrackingType = t?.trackingType ?? 'binary';
    state.targetNumber = (t?.target is int) ? t!.target as int : 1;
    state.targetDuration = (t?.trackingType == 'time' && t?.target is int)
        ? Duration(minutes: t!.target as int)
        : const Duration(hours: 1);
    state.unit = t?.unit ?? '';
    state.dueDate = t?.dueDate;
    // If the template doesn't have a due date but the instance was scheduled,
    // use the instance-specific due date so the editor reflects what the user set.
    if (state.dueDate == null &&
        state.widget.instance?.dueDate != null &&
        !state.quickIsTaskRecurring &&
        !state.widget.isHabit) {
      state.dueDate = state.widget.instance!.dueDate;
    }
    state.endDate = t?.endDate;

    // Load categories if not provided
    if (state.widget.categories.isEmpty) {
      loadCategories(state);
    } else {
      state.loadedCategories = state.widget.categories;
      initializeCategory(state, t);
    }

    // Load due time
    if (t != null && t.hasDueTime()) {
      state.selectedDueTime = TimeUtils.stringToTimeOfDay(t.dueTime);
    }
    // Fall back to the instance's due time (or cached template due time) if needed.
    if (state.selectedDueTime == null && state.widget.instance != null) {
      final instanceDueTime = state.widget.instance!.dueTime ??
          state.widget.instance!.templateDueTime;
      if (instanceDueTime != null && instanceDueTime.isNotEmpty) {
        state.selectedDueTime = TimeUtils.stringToTimeOfDay(instanceDueTime);
      }
    }

    // Load frequency config
    if (t != null && state.quickIsTaskRecurring) {
      state.frequencyConfig =
          ActivityEditorFrequencyService.convertTaskFrequencyToConfig(t);
      state.originalFrequencyConfig = state.frequencyConfig;
      state.originalStartDate = t.startDate;
    } else if (t == null && state.widget.isHabit) {
      // Already set default above
    } else if (t == null && ActivityEditorHelperService.isEssential(state)) {
      // Essentials: default frequency config already set, but frequency is disabled by default
      state.frequencyConfig = FrequencyConfig(
        type: FrequencyType.everyXPeriod,
        startDate: DateTime.now(),
      );
    }

    // Load reminders
    if (t != null && t.hasReminders()) {
      state.reminders = ReminderConfigList.fromMapList(t.reminders);
    }

    // Load time estimate
    if (t != null && t.hasTimeEstimateMinutes()) {
      state.timeEstimateMinutes = t.timeEstimateMinutes;
    }
    loadDefaultTimeEstimate(state);
  }

  /// Load default time estimate
  static Future<void> loadDefaultTimeEstimate(
      ActivityEditorDialogState state) async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      final minutes =
          await TimeLoggingPreferencesService.getDefaultDurationMinutes(userId);
      if (!state.mounted) return;
      state.setState(() => state.defaultTimeEstimateMinutes = minutes);
    } catch (e) {
      print(
          'DEBUG ActivityEditorDialog: Failed to load default time estimate: $e');
    }
  }

  /// Load categories from backend if not provided
  static Future<void> loadCategories(ActivityEditorDialogState state,
      {String? selectCategoryId}) async {
    if (state.isLoadingCategories) return;

    if (!state.mounted) return;
    state.setState(() => state.isLoadingCategories = true);

    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        if (state.mounted) {
          state.setState(() => state.isLoadingCategories = false);
        }
        return;
      }

      final categories = ActivityEditorHelperService.isEssential(state)
          ? await queryEssentialCategoriesOnce(
              userId: userId,
              callerTag: 'ActivityEditorDialog._loadCategories.essentials',
            )
          : state.widget.isHabit
              ? await queryHabitCategoriesOnce(
                  userId: userId,
                  callerTag: 'ActivityEditorDialog._loadCategories.habits',
                )
              : await queryTaskCategoriesOnce(
                  userId: userId,
                  callerTag: 'ActivityEditorDialog._loadCategories.tasks',
                );

      if (state.mounted) {
        state.setState(() {
          state.loadedCategories = categories;
          state.isLoadingCategories = false;
          if (selectCategoryId != null) {
            state.selectedCategoryId = selectCategoryId;
          }
        });
        // Initialize category after loading if not already selected or if we have a new ID
        if (selectCategoryId == null) {
          initializeCategory(state, state.widget.activity);
        }
      }
    } catch (e) {
      if (state.mounted) {
        state.setState(() => state.isLoadingCategories = false);
        print('DEBUG ActivityEditorDialog: Error loading categories: $e');
      }
    }
  }

  /// Initialize the selected category based on activity data
  static void initializeCategory(
      ActivityEditorDialogState state, ActivityRecord? t) {
    final categories = ActivityEditorHelperService.getCategories(state);
    if (t != null) {
      String? matchingCategoryId;
      if (t.categoryId.isNotEmpty &&
          categories.any((c) => c.reference.id == t.categoryId)) {
        matchingCategoryId = t.categoryId;
      } else if (t.categoryName.isNotEmpty &&
          categories.any((c) => c.name == t.categoryName)) {
        final category = categories.firstWhere((c) => c.name == t.categoryName);
        matchingCategoryId = category.reference.id;
      }
      if (state.mounted) {
        state.setState(() => state.selectedCategoryId = matchingCategoryId);
      }
      print(
          'DEBUG ActivityEditorDialog: Activity categoryId=${t.categoryId}, categoryName=${t.categoryName}');
      print(
          'DEBUG ActivityEditorDialog: Available categories=${categories.map((c) => '${c.name}(${c.reference.id})').toList()}');
      print(
          'DEBUG ActivityEditorDialog: Selected categoryId=${state.selectedCategoryId}');
    } else if (state.selectedCategoryId == null && categories.isNotEmpty) {
      // Default to first category if creating new and nothing selected yet
      if (state.mounted) {
        state.setState(
            () => state.selectedCategoryId = categories.first.reference.id);
      }
    }
  }

  /// Dispose controllers
  static void dispose(ActivityEditorDialogState state) {
    state.titleController.dispose();
    state.unitController.dispose();
    state.descriptionController.dispose();
  }
}
