/// Centralized date service that provides the current date for the entire app
/// This allows switching between real time and test time for testing purposes
class DateService {
  static bool _isTestMode = false;
  static DateTime? _testDate;
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
  /// Latest processable date (yesterday at midnight)
  static DateTime get latestProcessableShiftedDate {
    return yesterdayStart;
  }
  /// Compute the next occurrence of midnight after 'from'
  static DateTime nextShiftedBoundary(DateTime from) {
    final todayMidnight = DateTime(from.year, from.month, from.day);
    if (from.isBefore(todayMidnight)) return todayMidnight;
    final tomorrow = from.add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
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
