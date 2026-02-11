import 'package:habit_tracker/core/utils/Date_time/duration_format_helper.dart';

/// Shared timer utilities for habits, tasks, and essentials
/// Provides common formatting, calculation, and field helper functions
class TimerUtil {
  /// Maximum duration a timer can run (24 hours in milliseconds)
  static const int maxDurationMs = 24 * 60 * 60 * 1000;
  static const int maxDurationHours = 24;
  static const int warnSessionHours = 8;
  static const String maxDurationErrorMessage =
      'Session duration exceeds maximum allowed time (24 hours)';

  /// Calculate elapsed time from start time to now, with max duration validation
  /// Returns the actual elapsed time, capped at maxDurationMs
  static int calculateElapsedTime(DateTime? startTime, {DateTime? now}) {
    if (startTime == null) return 0;
    final endTime = now ?? DateTime.now();
    final elapsed = endTime.difference(startTime).inMilliseconds;
    return elapsed > maxDurationMs ? maxDurationMs : elapsed;
  }

  /// Calculate total time including accumulated time and current session
  /// Returns total milliseconds
  static int calculateTotalTime({
    required int accumulatedTime,
    DateTime? timerStartTime,
    bool isTimerActive = false,
  }) {
    if (!isTimerActive || timerStartTime == null) {
      return accumulatedTime;
    }
    final elapsed = calculateElapsedTime(timerStartTime);
    return accumulatedTime + elapsed;
  }

  /// Format duration in milliseconds to hr:min:sec format (for running times)
  /// Examples: "1:23:45" (1 hour 23 min 45 sec), "5:30" (5 min 30 sec)
  static String formatDuration(int milliseconds) =>
      DurationFormatHelper.formatStopwatch(milliseconds);

  /// Format duration in milliseconds to minutes only (for compact display)
  /// Example: "125min"
  static String formatDurationMinutes(int milliseconds) =>
      DurationFormatHelper.formatMinutesLabel(milliseconds);

  /// Format target duration in concise format (for targets)
  /// Examples: "2hr 30min", "45min", "1hr"
  static String formatTargetTime(int minutes) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (hours > 0) {
      if (remainingMinutes > 0) {
        return '${hours}hr ${remainingMinutes}min';
      } else {
        return '${hours}hr';
      }
    } else {
      return '${minutes}min';
    }
  }

  /// Create timer start fields for Firestore update
  /// Returns a map with fields needed to start a timer
  static Map<String, dynamic> createTimerStartFields({
    bool showInFloatingTimer = true,
  }) {
    return {
      'isTimerActive': true,
      'timerStartTime': DateTime.now(),
      'lastUpdated': DateTime.now(),
      if (showInFloatingTimer) 'showInFloatingTimer': true,
    };
  }

  /// Create timer stop fields for Firestore update
  /// Returns a map with fields needed to stop a timer
  static Map<String, dynamic> createTimerStopFields({
    int? accumulatedTime,
    bool clearFloatingTimer = false,
  }) {
    final fields = <String, dynamic>{
      'isTimerActive': false,
      'timerStartTime': null,
      'lastUpdated': DateTime.now(),
    };
    if (accumulatedTime != null) {
      fields['accumulatedTime'] = accumulatedTime;
      // Convert to minutes for currentValue if needed
      fields['currentValue'] = accumulatedTime ~/ 60000;
    }
    if (clearFloatingTimer) {
      fields['showInFloatingTimer'] = false;
    }
    return fields;
  }

  /// Create timer pause fields (same as stop but keeps floating timer visible)
  /// Returns a map with fields needed to pause a timer
  static Map<String, dynamic> createTimerPauseFields({
    required int accumulatedTime,
  }) {
    return {
      'isTimerActive': false,
      'timerStartTime': null,
      'accumulatedTime': accumulatedTime,
      'currentValue': accumulatedTime ~/ 60000,
      'showInFloatingTimer': true,
      'lastUpdated': DateTime.now(),
    };
  }

  /// Create force stop fields (for stuck timers)
  /// Returns a map with fields needed to force stop a timer
  static Map<String, dynamic> createForceStopFields({
    bool clearFloatingTimer = true,
  }) {
    return {
      'isTimerActive': false,
      'timerStartTime': null,
      'lastUpdated': DateTime.now(),
      if (clearFloatingTimer) 'showInFloatingTimer': false,
    };
  }

  /// Check if target duration has been reached
  /// Returns true if total time (accumulated + current session) >= target
  static bool isTargetReached({
    required int accumulatedTime,
    DateTime? timerStartTime,
    bool isTimerActive = false,
    required int targetMinutes,
  }) {
    if (targetMinutes == 0) return false;
    final totalMs = calculateTotalTime(
      accumulatedTime: accumulatedTime,
      timerStartTime: timerStartTime,
      isTimerActive: isTimerActive,
    );
    final totalMinutes = totalMs ~/ 60000;
    return totalMinutes >= targetMinutes;
  }

  /// Validate that elapsed time doesn't exceed maximum duration
  /// Returns error message if invalid, null if valid
  static String? validateMaxDuration(Duration duration,
      {String? errorMessage}) {
    if (duration.inMilliseconds > maxDurationMs) {
      return errorMessage ?? maxDurationErrorMessage;
    }
    return null;
  }

  /// Calculate total time from time log sessions
  /// Sums up all durationMilliseconds from a list of session maps
  static int calculateTotalFromSessions(List<Map<String, dynamic>> sessions) {
    return sessions.fold<int>(
      0,
      (sum, session) => sum + (session['durationMilliseconds'] as int? ?? 0),
    );
  }

  /// Check if a long-session warning should be shown.
  static bool shouldWarnLongSession(Duration duration) =>
      duration.inHours >= warnSessionHours;

  /// Optional warning for long sessions.
  static String? getLongSessionWarning(Duration duration) {
    if (shouldWarnLongSession(duration)) {
      return 'You\'ve been working for ${duration.inHours} hours. Consider taking a break!';
    }
    return null;
  }
}
