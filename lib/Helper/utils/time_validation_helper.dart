import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

/// Helper class for time logging validation
class TimeValidationHelper {
  static const int maxSessionHours = 24;
  static const int warnSessionHours = 8;

  /// Validate session duration
  static String? validateSessionDuration(Duration duration) {
    if (duration.inHours > maxSessionHours) {
      return 'Session cannot exceed $maxSessionHours hours';
    }
    return null;
  }

  /// Check if warning needed for long session
  static bool shouldWarnLongSession(Duration duration) {
    return duration.inHours >= warnSessionHours;
  }

  /// Check if can start timer on task
  static bool canStartTimer(ActivityInstanceRecord instance) {
    return instance.status != 'completed' && !instance.isTimeLogging;
  }

  /// Get validation message for starting timer
  static String? getStartTimerError(ActivityInstanceRecord instance) {
    if (instance.status == 'completed') {
      return 'Cannot start timer on completed task';
    }
    if (instance.isTimeLogging) {
      return 'Timer is already running on this task';
    }
    return null;
  }

  /// Validate total time logged across all sessions
  static String? validateTotalTimeLogged(int totalMilliseconds) {
    final totalHours = Duration(milliseconds: totalMilliseconds).inHours;
    if (totalHours > 24) {
      return 'Total time logged cannot exceed 24 hours per day';
    }
    return null;
  }

  /// Check for overlapping sessions (future enhancement)
  static bool hasOverlappingSessions(List<Map<String, dynamic>> sessions) {
    if (sessions.length < 2) return false;

    // Sort sessions by start time
    final sortedSessions = List<Map<String, dynamic>>.from(sessions)
      ..sort((a, b) =>
          (a['startTime'] as DateTime).compareTo(b['startTime'] as DateTime));

    // Check for overlaps
    for (int i = 0; i < sortedSessions.length - 1; i++) {
      final current = sortedSessions[i];
      final next = sortedSessions[i + 1];

      final currentEnd = current['endTime'] as DateTime?;
      final nextStart = next['startTime'] as DateTime;

      if (currentEnd != null && currentEnd.isAfter(nextStart)) {
        return true;
      }
    }

    return false;
  }

  /// Get warning message for long session
  static String? getLongSessionWarning(Duration duration) {
    if (shouldWarnLongSession(duration)) {
      return 'You\'ve been working for ${duration.inHours} hours. Consider taking a break!';
    }
    return null;
  }
}
