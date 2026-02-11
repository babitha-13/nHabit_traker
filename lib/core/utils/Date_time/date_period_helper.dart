/// Shared helpers for computing date period boundaries and lengths.
class DatePeriodHelper {
  /// Midnight (00:00) of the provided date.
  static DateTime startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Start of week assuming Sunday as the first day.
  static DateTime startOfWeekSunday(DateTime date) {
    final daysSinceSunday = date.weekday % 7;
    return DateTime(date.year, date.month, date.day - daysSinceSunday);
  }

  /// Start of the month (day 1 at midnight).
  static DateTime startOfMonth(DateTime date) =>
      DateTime(date.year, date.month, 1);

  /// Start of the year (Jan 1 at midnight).
  static DateTime startOfYear(DateTime date) => DateTime(date.year, 1, 1);

  /// Length of the current month in days.
  static int monthLength(DateTime date) =>
      DateTime(date.year, date.month + 1, 0).day;

  /// Safe month addition that clamps end-of-month overflow (e.g., Jan 31 + 1 -> Feb 28/29).
  static DateTime addMonthsSafe(DateTime date, int months) {
    final nextMonth = DateTime(date.year, date.month + months, date.day);
    if (nextMonth.month != (date.month + months) % 12) {
      // Day overflowed; use last day of the computed month.
      return DateTime(nextMonth.year, nextMonth.month, 0);
    }
    return nextMonth;
  }
}
