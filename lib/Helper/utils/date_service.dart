/// Centralized date service that provides the current date for the entire app
/// This allows switching between real time and test time for testing purposes
class DateService {
  static bool _isTestMode = false;
  static DateTime? _testDate;
  static const int shiftMinutes = 120; // 2 AM shifted boundary

  /// Get the current date (real or test)
  static DateTime get currentDate {
    if (_isTestMode && _testDate != null) {
      return _testDate!;
    }
    return DateTime.now();
  }

  /// Get today's date at midnight (start of day)
  static DateTime get todayStart {
    final now = currentDate;
    return DateTime(now.year, now.month, now.day);
  }

  /// Get tomorrow's date at midnight
  static DateTime get tomorrowStart {
    return todayStart.add(const Duration(days: 1));
  }

  /// Get yesterday's date at midnight
  static DateTime get yesterdayStart {
    return todayStart.subtract(const Duration(days: 1));
  }

  /// Check if we're in test mode
  static bool get isTestMode => _isTestMode;

  /// Enable test mode with a specific date
  static void enableTestMode(DateTime testDate) {
    _isTestMode = true;
    _testDate = testDate;
    print(
        'DateService: Test mode enabled with date: ${testDate.toIso8601String()}');
  }

  /// Disable test mode and return to real time
  static void disableTestMode() {
    _isTestMode = false;
    _testDate = null;
    print('DateService: Test mode disabled, returning to real time');
  }

  /// Update the test date (used by SimpleDayAdvancer)
  static void updateTestDate(DateTime newTestDate) {
    if (_isTestMode) {
      _testDate = newTestDate;
      print(
          'DateService: Test date updated to: ${newTestDate.toIso8601String()}');
    }
  }

  /// Get status information for debugging
  static Map<String, dynamic> getStatus() {
    return {
      'isTestMode': _isTestMode,
      'currentDate': currentDate.toIso8601String(),
      'realDate': DateTime.now().toIso8601String(),
      'testDate': _testDate?.toIso8601String(),
    };
  }

  // ================= Shifted-day helpers (2 AM boundary) =================

  /// Start of the given day at the shifted boundary (2:00 AM local time)
  static DateTime shiftedStartOfDay(DateTime date) {
    final base = DateTime(date.year, date.month, date.day);
    return base.add(const Duration(hours: 2));
  }

  /// Start of the current shifted day (today at 2:00 AM)
  static DateTime get todayShiftedStart => shiftedStartOfDay(currentDate);

  /// Start of tomorrow's shifted day (tomorrow at 2:00 AM)
  static DateTime get tomorrowShiftedStart =>
      shiftedStartOfDay(currentDate.add(const Duration(days: 1)));

  /// Start of yesterday's shifted day (yesterday at 2:00 AM)
  static DateTime get yesterdayShiftedStart =>
      shiftedStartOfDay(currentDate.subtract(const Duration(days: 1)));

  /// Returns the calendar date (at midnight) whose 2 AM window contains dt
  static DateTime belongsToShiftedDate(DateTime dt) {
    final todayStartShifted =
        shiftedStartOfDay(DateTime(dt.year, dt.month, dt.day));
    final dateOnlyToday = DateTime(dt.year, dt.month, dt.day);
    if (dt.isBefore(todayStartShifted)) {
      final prev = dateOnlyToday.subtract(const Duration(days: 1));
      return DateTime(prev.year, prev.month, prev.day);
    }
    return dateOnlyToday;
  }

  /// Latest processable shifted date (yesterday by shifted boundary)
  /// If now is before 2 AM, latest processable is day-before-yesterday.
  static DateTime get latestProcessableShiftedDate {
    final now = currentDate;
    final boundaryToday = shiftedStartOfDay(now);
    final offsetDays = now.isBefore(boundaryToday) ? 2 : 1;
    final target = now.subtract(Duration(days: offsetDays));
    return DateTime(target.year, target.month, target.day);
  }

  /// Compute the next occurrence of the 2 AM boundary after 'from'
  static DateTime nextShiftedBoundary(DateTime from) {
    final todayBoundary = shiftedStartOfDay(from);
    if (from.isBefore(todayBoundary)) return todayBoundary;
    final tomorrow = from.add(const Duration(days: 1));
    return shiftedStartOfDay(tomorrow);
  }

  // ================= Week range helpers =================

  /// Get the start of the current week (Sunday at 00:00:00)
  static DateTime get currentWeekStart {
    final now = currentDate;
    final sunday = now.subtract(Duration(days: now.weekday % 7));
    return DateTime(sunday.year, sunday.month, sunday.day);
  }

  /// Get the end of the current week (Saturday at 23:59:59)
  static DateTime get currentWeekEnd {
    final start = currentWeekStart;
    return DateTime(start.year, start.month, start.day, 23, 59, 59)
        .add(const Duration(days: 6));
  }
}
