import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Frequency_config/frequency_config_dialog.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Frequency_config/frequency_display_helper.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Activity%20Editor%20Dialog/activity_editor_dialog.dart';
import 'activity_editor_helper_service.dart';

/// Service for frequency conversion and handling
class ActivityEditorFrequencyService {
  /// Convert task frequency to config
  static FrequencyConfig convertTaskFrequencyToConfig(ActivityRecord task) {
    FrequencyType type;
    int timesPerPeriod = 1;
    PeriodType periodType = PeriodType.weeks;
    int everyXValue = 1;
    PeriodType everyXPeriodType = PeriodType.days;
    List<int> selectedDays = [];
    DateTime startDate = task.startDate ?? DateTime.now();
    DateTime? endDate = task.endDate;

    if (endDate != null && endDate.year >= 2099) {
      endDate = null;
    }

    switch (task.frequencyType) {
      case 'everyXPeriod':
        type = FrequencyType.everyXPeriod;
        everyXValue = task.everyXValue;
        everyXPeriodType = task.everyXPeriodType == 'days'
            ? PeriodType.days
            : task.everyXPeriodType == 'weeks'
                ? PeriodType.weeks
                : PeriodType.months;
        break;
      case 'timesPerPeriod':
        type = FrequencyType.timesPerPeriod;
        timesPerPeriod = task.timesPerPeriod;
        periodType = task.periodType == 'weeks'
            ? PeriodType.weeks
            : task.periodType == 'months'
                ? PeriodType.months
                : PeriodType.weeks;
        break;
      case 'specificDays':
        type = FrequencyType.specificDays;
        selectedDays = task.specificDays;
        break;
      default:
        type = FrequencyType.everyXPeriod;
        everyXValue = 1;
        everyXPeriodType = PeriodType.days;
    }

    return FrequencyConfig(
      type: type,
      timesPerPeriod: timesPerPeriod,
      periodType: periodType,
      everyXValue: everyXValue,
      everyXPeriodType: everyXPeriodType,
      selectedDays: selectedDays,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Check if frequency has changed
  static bool hasFrequencyChanged(ActivityEditorDialogState state) {
    if (state.originalFrequencyConfig == null || state.frequencyConfig == null)
      return false;
    final original = state.originalFrequencyConfig!;
    final current = state.frequencyConfig!;
    return original.type != current.type ||
        original.startDate != current.startDate ||
        original.endDate != current.endDate ||
        original.everyXValue != current.everyXValue ||
        original.everyXPeriodType != current.everyXPeriodType ||
        original.timesPerPeriod != current.timesPerPeriod ||
        original.periodType != current.periodType ||
        !ActivityEditorHelperService.listEquals(original.selectedDays, current.selectedDays);
  }

  /// Format frequency summary
  static String formatFrequencySummary(ActivityEditorDialogState state) {
    return FrequencyDisplayHelper.formatSummary(state.frequencyConfig);
  }

  /// Handle opening frequency config dialog
  static Future<void> handleOpenFrequencyConfig(ActivityEditorDialogState state) async {
    final config = await showFrequencyConfigDialog(
      context: state.context,
      initialConfig: state.frequencyConfig ??
          FrequencyConfig(
            type: FrequencyType.everyXPeriod,
            startDate: state.dueDate ?? DateTime.now(),
          ),
      // For essentials, only allow everyXPeriod and specificDays (no timesPerPeriod)
      allowedTypes: ActivityEditorHelperService.isEssential(state)
          ? const {
              FrequencyType.everyXPeriod,
              FrequencyType.specificDays,
            }
          : null,
    );
    if (config != null) {
      state.setState(() {
        state.frequencyConfig = config;
        if (ActivityEditorHelperService.isEssential(state)) {
          state.frequencyEnabled = true;
          state.quickIsTaskRecurring = true;
        } else {
          state.quickIsTaskRecurring = true;
        }
        state.endDate = config.endDate;
      });
    }
  }

  /// Clear frequency
  static void clearFrequency(ActivityEditorDialogState state) {
    if (state.widget.isHabit) return; // Cannot clear frequency for habits
    state.setState(() {
      if (ActivityEditorHelperService.isEssential(state)) {
        state.frequencyEnabled = false;
        state.quickIsTaskRecurring = false;
        state.frequencyConfig = FrequencyConfig(
          type: FrequencyType.everyXPeriod,
          startDate: DateTime.now(),
        );
      } else {
        state.quickIsTaskRecurring = false;
        state.frequencyConfig = null;
        state.endDate = null;
      }
    });
  }

  /// Create frequency payload for essentials
  static EssentialFrequencyPayload frequencyPayloadForEssential(ActivityEditorDialogState state) {
    if (!state.frequencyEnabled || state.frequencyConfig == null) {
      return EssentialFrequencyPayload(
        frequencyType: state.widget.activity != null ? '' : null,
        everyXValue: null,
        everyXPeriodType: null,
        specificDays: state.widget.activity != null ? <int>[] : null,
      );
    }
    final config = state.frequencyConfig!;
    switch (config.type) {
      case FrequencyType.specificDays:
        final days = config.selectedDays.isNotEmpty
            ? List<int>.from(config.selectedDays)
            : [1, 2, 3, 4, 5, 6, 7];
        return EssentialFrequencyPayload(
          frequencyType: 'specific_days',
          everyXValue: null,
          everyXPeriodType: null,
          specificDays: days,
        );
      case FrequencyType.everyXPeriod:
      default:
        final value = config.everyXValue > 0 ? config.everyXValue : 1;
        String periodType;
        switch (config.everyXPeriodType) {
          case PeriodType.weeks:
            periodType = 'week';
            break;
          case PeriodType.months:
            periodType = 'month';
            break;
          default:
            periodType = 'day';
        }
        return EssentialFrequencyPayload(
          frequencyType: 'every_x',
          everyXValue: value,
          everyXPeriodType: periodType,
          specificDays: null,
        );
    }
  }
}

/// Helper class for essential frequency payload
class EssentialFrequencyPayload {
  final String? frequencyType;
  final int? everyXValue;
  final String? everyXPeriodType;
  final List<int>? specificDays;

  const EssentialFrequencyPayload({
    this.frequencyType,
    this.everyXValue,
    this.everyXPeriodType,
    this.specificDays,
  });
}
