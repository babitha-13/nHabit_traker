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
}
