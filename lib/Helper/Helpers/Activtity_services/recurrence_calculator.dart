import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_period_helper.dart';

/// Utility class for calculating recurrence dates
/// Centralizes all recurrence logic to prevent duplication
class RecurrenceCalculator {
  /// Calculate the next due date based on schedule and frequency
  /// Supports both ActivityRecord template and individual parameters
  static DateTime? calculateNextDueDate({
    required DateTime currentDueDate,
    ActivityRecord? template,
    String? frequencyType,
    int? everyXValue,
    String? everyXPeriodType,
    int? timesPerPeriod,
    String? periodType,
    List<int>? specificDays,
    bool? isRecurring,
  }) {
    // If template is provided, use it; otherwise use individual parameters
    if (template != null) {
      if (!template.isRecurring) return null;
      frequencyType = template.frequencyType;
      everyXValue = template.everyXValue;
      everyXPeriodType = template.everyXPeriodType;
      timesPerPeriod = template.timesPerPeriod;
      periodType = template.periodType;
      specificDays = template.specificDays;
    } else if (isRecurring == false) {
      return null;
    }

    // Handle different frequency types
    switch (frequencyType) {
      case 'everyXPeriod':
        return _calculateEveryXPeriodNextDate(
          currentDueDate,
          everyXValue ?? 1,
          everyXPeriodType ?? '',
        );
      case 'specificDays':
        return _calculateSpecificDaysNextDate(
          currentDueDate,
          specificDays ?? [],
        );
      case 'timesPerPeriod':
        return _calculateTimesPerPeriodNextDate(
          currentDueDate,
          timesPerPeriod ?? 1,
          periodType ?? '',
          specificDays ?? [],
        );
      default:
        // Default to daily
        return currentDueDate.add(const Duration(days: 1));
    }
  }

  /// Calculate next date for "every X period" frequency
  static DateTime? _calculateEveryXPeriodNextDate(
    DateTime currentDueDate,
    int everyXValue,
    String periodType,
  ) {
    switch (periodType) {
      case 'days':
        return currentDueDate.add(Duration(days: everyXValue));
      case 'weeks':
        return currentDueDate.add(Duration(days: everyXValue * 7));
      case 'months':
        return addMonths(currentDueDate, everyXValue);
      case 'year':
        return DateTime(
          currentDueDate.year + everyXValue,
          currentDueDate.month,
          currentDueDate.day,
        );
      default:
        return currentDueDate.add(Duration(days: everyXValue));
    }
  }

  /// Calculate next date for "specific days" frequency
  static DateTime? _calculateSpecificDaysNextDate(
    DateTime currentDueDate,
    List<int> specificDays,
  ) {
    if (specificDays.isEmpty) return null;

    // Find next occurrence of any of the specified days
    for (int i = 1; i <= 7; i++) {
      final candidate = currentDueDate.add(Duration(days: i));
      if (specificDays.contains(candidate.weekday)) {
        return candidate;
      }
    }
    return null;
  }

  /// Calculate next date for "times per period" frequency
  /// This handles more complex scenarios where activities occur multiple times within a period
  static DateTime? _calculateTimesPerPeriodNextDate(
    DateTime currentDueDate,
    int timesPerPeriod,
    String periodType,
    List<int> specificDays,
  ) {
    if (timesPerPeriod <= 0) return null;

    // For weeks with specific days, use the weekly occurrence logic
    if (periodType == 'weeks' && specificDays.isNotEmpty) {
      return getNextWeeklyOccurrence(currentDueDate, specificDays);
    }

    // For other period types, calculate target dates within the period
    DateTime periodStart;
    int periodLength;
    switch (periodType) {
      case 'days':
        periodStart = DatePeriodHelper.startOfDay(currentDueDate);
        periodLength = 1;
        break;
      case 'weeks':
        periodStart = DatePeriodHelper.startOfWeekSunday(currentDueDate);
        periodLength = 7;
        break;
      case 'months':
        periodStart = DatePeriodHelper.startOfMonth(currentDueDate);
        periodLength = DatePeriodHelper.monthLength(currentDueDate);
        break;
      case 'year':
        periodStart = DatePeriodHelper.startOfYear(currentDueDate);
        periodLength = 365;
        break;
      default:
        // Fallback to simple monthly increment
        return addMonths(currentDueDate, 1);
    }

    // Calculate target dates within the period
    final targetDates = <DateTime>[];
    for (int i = 0; i < timesPerPeriod; i++) {
      final progress = (i + 1) / timesPerPeriod; // 1/3, 2/3, 3/3
      final daysFromStart = (progress * periodLength).floor();
      final hoursFromStart = ((progress * periodLength) - daysFromStart) * 24;
      targetDates.add(DateTime(
        periodStart.year,
        periodStart.month,
        periodStart.day + daysFromStart,
        hoursFromStart.floor(),
        ((hoursFromStart - hoursFromStart.floor()) * 60).round(),
      ));
    }

    // Find the next target date after current due date
    for (final targetDate in targetDates) {
      if (targetDate.isAfter(currentDueDate)) {
        return targetDate;
      }
    }

    // If we're past all targets in this period, move to next period
    DateTime nextPeriodStart;
    switch (periodType) {
      case 'days':
        nextPeriodStart = periodStart.add(const Duration(days: 1));
        break;
      case 'weeks':
        nextPeriodStart = periodStart.add(const Duration(days: 7));
        break;
      case 'months':
        nextPeriodStart = DatePeriodHelper.addMonthsSafe(
          periodStart,
          1,
        );
        break;
      case 'year':
        nextPeriodStart = DatePeriodHelper.startOfYear(
          DateTime(periodStart.year + 1, 1, 1),
        );
        break;
      default:
        return addMonths(currentDueDate, 1);
    }

    // Calculate first target date in next period
    final firstProgress = 1.0 / timesPerPeriod;
    final daysFromStart = (firstProgress * periodLength).floor();
    final hoursFromStart =
        ((firstProgress * periodLength) - daysFromStart) * 24;
    return DateTime(
      nextPeriodStart.year,
      nextPeriodStart.month,
      nextPeriodStart.day + daysFromStart,
      hoursFromStart.floor(),
      ((hoursFromStart - hoursFromStart.floor()) * 60).round(),
    );
  }

  /// Add months to a date, handling edge cases (e.g., Jan 31 + 1 month = Feb 28/29)
  static DateTime addMonths(DateTime date, int months) =>
      DatePeriodHelper.addMonthsSafe(date, months);

  /// Get next weekly occurrence based on specific days
  /// Returns the next occurrence of any day in the specificDays list
  static DateTime getNextWeeklyOccurrence(
    DateTime currentDate,
    List<int> specificDays,
  ) {
    if (specificDays.isEmpty) {
      return currentDate.add(const Duration(days: 1));
    }

    final currentWeekday = currentDate.weekday; // Monday = 1, Sunday = 7
    final sortedDays = List<int>.from(specificDays)..sort();

    // Find next day in the same week
    for (final day in sortedDays) {
      if (day > currentWeekday) {
        final daysToAdd = day - currentWeekday;
        return currentDate.add(Duration(days: daysToAdd));
      }
    }

    // No more days this week, go to first day of next week
    final firstDayNextWeek = sortedDays.first;
    final daysToAdd = 7 - currentWeekday + firstDayNextWeek;
    return currentDate.add(Duration(days: daysToAdd));
  }
}
