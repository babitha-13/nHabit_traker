import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

class TimerLogicHelper {
  /// Calculate real-time progress including elapsed time
  static int getRealTimeAccumulated(ActivityInstanceRecord instance) {
    // For session-based tasks, use totalTimeLogged as base
    int totalMilliseconds = instance.totalTimeLogged > 0
        ? instance.totalTimeLogged
        : instance.accumulatedTime;

    // Add current session time if actively logging
    if (instance.isTimeLogging && instance.currentSessionStartTime != null) {
      final elapsed = DateTime.now()
          .difference(instance.currentSessionStartTime!)
          .inMilliseconds;
      totalMilliseconds += elapsed;
    }
    // Fallback to legacy timer logic for non-session tasks
    else if (instance.isTimerActive && instance.timerStartTime != null) {
      final elapsed =
          DateTime.now().difference(instance.timerStartTime!).inMilliseconds;
      totalMilliseconds += elapsed;
    }

    return totalMilliseconds;
  }

  /// Calculate progress percentage including real-time elapsed
  static double getProgressPercent(ActivityInstanceRecord instance) {
    if (instance.templateTrackingType != 'time') return 0.0;

    final target = instance.templateTarget ?? 0;
    if (target == 0) return 0.0;

    final realTimeAccumulated = getRealTimeAccumulated(instance);
    // Convert target from minutes to milliseconds for comparison
    final targetMs = target * 60000;
    final pct = (realTimeAccumulated / targetMs);

    if (pct.isNaN) return 0.0;
    // Don't clamp - allow > 100% to show overtime
    return pct;
  }

  /// Check if target is met or exceeded
  static bool hasMetTarget(ActivityInstanceRecord instance) {
    if (instance.templateTrackingType != 'time') return false;

    final target = instance.templateTarget ?? 0;
    if (target == 0) return false;

    final realTimeAccumulated = getRealTimeAccumulated(instance);
    // Convert target from minutes to milliseconds for comparison
    final targetMs = target * 60000;
    return realTimeAccumulated >= targetMs;
  }

  /// Format time display with context-dependent format
  static String formatTimeDisplay(ActivityInstanceRecord instance) {
    final totalMilliseconds = getRealTimeAccumulated(instance);
    final totalSeconds = totalMilliseconds ~/ 1000;

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    // Show MM:SS when under 1 hour, HH:MM:SS when 1+ hour
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Format target time
  static String formatTargetTime(int targetMinutes) {
    final hours = targetMinutes ~/ 60;
    final minutes = targetMinutes % 60;

    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
    return '${minutes}m';
  }
}
