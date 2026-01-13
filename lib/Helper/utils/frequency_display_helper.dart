import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_dialog.dart';

/// Shared utility for formatting frequency display strings
/// Handles both ActivityInstanceRecord (for display) and FrequencyConfig (for editing)
class FrequencyDisplayHelper {
  /// Format frequency display from ActivityInstanceRecord
  /// Used for displaying frequency in item components
  static String formatFromInstance(ActivityInstanceRecord instance) {
    if (!_isRecurringInstance(instance)) return '';

    // Handle "every X period" pattern
    if (instance.templateEveryXValue > 0 &&
        instance.templateEveryXPeriodType.isNotEmpty) {
      return _formatEveryXPeriod(
        value: instance.templateEveryXValue,
        periodType: instance.templateEveryXPeriodType,
      );
    }

    // Handle "times per period" pattern
    if (instance.templateTimesPerPeriod > 0 &&
        instance.templatePeriodType.isNotEmpty) {
      return _formatTimesPerPeriod(
        times: instance.templateTimesPerPeriod,
        periodType: instance.templatePeriodType,
      );
    }

    return '';
  }

  /// Format frequency display from FrequencyConfig
  /// Used for displaying frequency in editor dialogs and task pages
  static String formatFromConfig(FrequencyConfig config) {
    switch (config.type) {
      case FrequencyType.daily:
        return 'Every day';
      case FrequencyType.specificDays:
        return 'Specific days';
      case FrequencyType.timesPerPeriod:
        return _formatTimesPerPeriod(
          times: config.timesPerPeriod,
          periodType: _periodTypeToString(config.periodType),
        );
      case FrequencyType.everyXPeriod:
        // Special case: every 1 day is the same as every day
        if (config.everyXValue == 1 &&
            config.everyXPeriodType == PeriodType.days) {
          return 'Every day';
        }
        return _formatEveryXPeriod(
          value: config.everyXValue,
          periodType: _periodTypeToString(config.everyXPeriodType),
        );
    }
  }

  /// Format "Every X period" pattern (e.g., "Every day", "Every 2 weeks")
  static String _formatEveryXPeriod({
    required int value,
    required String periodType,
  }) {
    if (value == 1) {
      switch (periodType) {
        case 'days':
          return 'Every day';
        case 'weeks':
          return 'Every week';
        case 'months':
          return 'Every month';
        default:
          return 'Every $value $periodType';
      }
    } else {
      final periodName = periodType == 'days'
          ? 'days'
          : periodType == 'weeks'
              ? 'weeks'
              : 'months';
      return 'Every $value $periodName';
    }
  }

  /// Format "X times per period" pattern (e.g., "3 times per week")
  static String _formatTimesPerPeriod({
    required int times,
    required String periodType,
  }) {
    final periodName = periodType == 'weeks'
        ? (times == 1 ? 'week' : 'weeks')
        : periodType == 'months'
            ? (times == 1 ? 'month' : 'months')
            : periodType == 'year'
                ? (times == 1 ? 'year' : 'years')
                : periodType == 'days'
                    ? (times == 1 ? 'day' : 'days')
                    : periodType;

    return '$times time${times == 1 ? '' : 's'} per $periodName';
  }

  /// Convert PeriodType enum to string
  static String _periodTypeToString(PeriodType periodType) {
    switch (periodType) {
      case PeriodType.days:
        return 'days';
      case PeriodType.weeks:
        return 'weeks';
      case PeriodType.months:
        return 'months';
      case PeriodType.year:
        return 'year';
    }
  }

  /// Check if an ActivityInstanceRecord is recurring
  static bool _isRecurringInstance(ActivityInstanceRecord instance) {
    if (instance.templateCategoryType == 'habit') {
      return true; // Habits are always recurring
    } else {
      return instance.templateCategoryType == 'task' &&
          (instance.templateEveryXPeriodType.isNotEmpty ||
              instance.templatePeriodType.isNotEmpty);
    }
  }

  /// Format frequency with "Recurring" prefix (used in task page)
  static String formatWithRecurringPrefix(FrequencyConfig config) {
    final base = formatFromConfig(config);
    if (base.isEmpty || base == 'Specific days') {
      return base.isEmpty ? 'Recurring' : base;
    }
    // Lowercase the first letter of the base string and add "Recurring" prefix
    final lowercased = base[0].toLowerCase() + base.substring(1);
    return 'Recurring $lowercased';
  }

  /// Format frequency summary for editor dialogs (simplified version)
  static String formatSummary(FrequencyConfig? config) {
    if (config == null) return 'One-time task';
    return formatFromConfig(config);
  }
}
