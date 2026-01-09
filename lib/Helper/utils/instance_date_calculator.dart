import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
/// Helper class for calculating instance due dates based on activity template configuration
/// Follows the principle: Due Date = Start Date, except for "specific days" where it's the next valid occurrence
class InstanceDateCalculator {
  /// Calculate the initial due date for a new activity instance
  static DateTime? calculateInitialDueDate({
    required ActivityRecord template,
    DateTime? explicitDueDate,
  }) {
    // For non-recurring tasks: use explicit due date or null
    if (!template.isRecurring) {
      return explicitDueDate ?? template.dueDate;
    }
    // For recurring tasks: calculate based on frequency type
    final baseDate = explicitDueDate ?? template.startDate ?? _todayStart;
    // Special handling for "specific days" - find next valid occurrence
    if (template.frequencyType == 'specificDays') {
      return _calculateFirstOccurrenceForSpecificDays(baseDate, template);
    }
    // For all other frequency types: start date = due date
    return baseDate;
  }
  /// Calculate the first occurrence for "specific days" frequency type
  static DateTime _calculateFirstOccurrenceForSpecificDays(
    DateTime startDate,
    ActivityRecord template,
  ) {
    if (template.specificDays.isEmpty) {
      return startDate;
    }
    // Find the next occurrence of any specified weekday (including today)
    for (int i = 0; i <= 7; i++) {
      final candidate = startDate.add(Duration(days: i));
      if (template.specificDays.contains(candidate.weekday)) {
        return candidate;
      }
    }
    // Fallback to start date if no match found (shouldn't happen)
    return startDate;
  }
  /// Get today's date at midnight (start of day)
  static DateTime get _todayStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
