import 'package:firebase_auth/firebase_auth.dart';
import 'schema/activity_record.dart';
import 'backend.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
class HabitTrackingUtil {
  /// Check if a habit should be tracked today based on its schedule
  static bool shouldTrackToday(ActivityRecord habit) {
    final today = DateService.todayStart;
    // Date range check
    final startDate = habit.startDate;
    if (startDate != null) {
      final startDateOnly =
          DateTime(startDate.year, startDate.month, startDate.day);
      if (today.isBefore(startDateOnly)) {
        return false;
      }
    }
    final endDate = habit.endDate;
    if (endDate != null) {
      final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
      if (today.isAfter(endDateOnly)) {
        return false;
      }
    }
    // New frequency logic
    if (habit.hasFrequencyType()) {
      switch (habit.frequencyType) {
        case 'everyXPeriod':
          final period = habit.everyXPeriodType;
          final value = habit.everyXValue;
          if (startDate == null) return true; // No start date, always track
          final daysSinceStart = today.difference(startDate).inDays;
          if (daysSinceStart < 0) return false;
          if (period == 'days') {
            if (value <= 0)
              return false; // Add this check to prevent division by zero
            return daysSinceStart % value == 0;
          } else if (period == 'weeks') {
            final weeksSinceStart = (daysSinceStart / 7).floor();
            if (value <= 0) return false; // Add this check here too
            return weeksSinceStart % value == 0 &&
                today.weekday == startDate.weekday;
          } else if (period == 'months') {
            final years = today.year - startDate.year;
            final months = today.month - startDate.month;
            final totalMonths = years * 12 + months;
            if (value <= 0) return false; // And here
            return totalMonths % value == 0 && today.day == startDate.day;
          }
          break;
        case 'timesPerPeriod':
          // This requires checking completion records, which is a larger change.
          // For now, we will assume it should be tracked if the period matches.
          // TODO: Implement completion record check for timesPerPeriod.
          return true;
        case 'specificDays':
          return habit.specificDays.contains(today.weekday);
      }
    }
    // Fallback to default behavior for habits without frequency data
    return true;
  }
  /// Check if progress should be reset based on day end time
  static bool shouldResetProgress(ActivityRecord habit) {
    // For now, disable automatic progress reset to fix the constant reset issue
    // Progress should only be reset when explicitly starting a new day
    // TODO: Implement proper day boundary logic based on lastUpdated field
    return false;
  }
  /// Get the current day's progress for a habit
  static dynamic getCurrentProgress(ActivityRecord habit) {
    if (shouldResetProgress(habit)) {
      final defaultProgress = _getDefaultProgress(habit.trackingType);
      return defaultProgress;
    }
    final currentProgress =
        habit.currentValue ?? _getDefaultProgress(habit.trackingType);
    return currentProgress;
  }
  /// Get the target value for a habit
  static dynamic getTarget(ActivityRecord habit) {
    return habit.target;
  }
  /// Check if a habit is completed for today
  static bool isCompletedToday(ActivityRecord habit) {
    switch (habit.trackingType) {
      case 'binary':
        // Check if today is in completed dates
        // Note: completedDates tracking moved to separate completion records
        // For now, return false to indicate not completed
        return habit.status == 'complete' || habit.currentValue == true;
      case 'quantitative':
        final progress = getCurrentProgress(habit);
        final target = getTarget(habit);
        return progress >= target;
      case 'time':
        final progress = getCurrentProgress(habit);
        final target = getTarget(habit);
        return progress >= target;
      default:
        return false;
    }
  }
  /// Get progress percentage for UI display
  static double getProgressPercentage(ActivityRecord habit) {
    final target = getTarget(habit);
    if (target == null || target == 0) return 0.0;
    switch (habit.trackingType) {
      case 'binary':
        final progress = getCurrentProgress(habit);
        return progress == true ? 1.0 : 0.0;
      case 'quantitative':
        final progress = getCurrentProgress(habit);
        return (progress / target).clamp(0.0, 1.0);
      case 'time':
        // Compute in milliseconds to include running time
        final int targetMs = (target as int) * 60000;
        int totalMs = habit.accumulatedTime;
        if (habit.isTimerActive && habit.timerStartTime != null) {
          final elapsed =
              DateTime.now().difference(habit.timerStartTime!).inMilliseconds;
          totalMs += elapsed;
        }
        return (totalMs / targetMs).clamp(0.0, 1.0);
      default:
        return 0.0;
    }
  }
  /// Get display text for progress
  static String getProgressText(ActivityRecord habit) {
    final progress = getCurrentProgress(habit);
    final target = getTarget(habit);
    switch (habit.trackingType) {
      case 'binary':
        return progress == true ? 'Completed' : 'Not completed';
      case 'quantitative':
        return '$progress/${target} ${habit.unit}';
      case 'time':
        final progressDisplay = getTimerDisplayTextWithSeconds(habit);
        final targetDisplay = formatTargetTime(target);
        return '$progressDisplay / $targetDisplay';
      default:
        return 'Unknown';
    }
  }
  /// Get display text for target
  static String getTargetText(ActivityRecord habit) {
    final target = getTarget(habit);
    switch (habit.trackingType) {
      case 'binary':
        return 'Done/Not Done';
      case 'quantitative':
        return '${target} ${habit.unit}';
      case 'time':
        return formatTargetTime(target);
      default:
        return 'Unknown';
    }
  }
  /// Update habit progress
  static Future<void> updateProgress(
    ActivityRecord habit,
    dynamic newProgress,
  ) async {
    try {
      final updates = <String, dynamic>{
        'currentValue': newProgress,
        'lastUpdated': DateTime.now(),
      };
      await habit.reference.update(updates);
    } catch (e) {
      rethrow;
    }
  }
  /// Mark habit as completed for today
  static Future<void> markCompleted(ActivityRecord habit) async {
    final today = DateTime.now();
    final updates = <String, dynamic>{
      'lastCompletedDate': today,
      'lastUpdated': DateTime.now(),
    };
    // For binary tracking, just add to completed dates
    if (habit.trackingType == 'binary') {
      // Note: completedDates tracking moved to separate completion records
      // For now, just update the current value
      updates['currentValue'] = true;
      updates['status'] = 'complete';
    } else {
      // For other types, add to completed dates if target is reached
      final progress = getCurrentProgress(habit);
      final target = getTarget(habit);
      if (progress >= target) {
        updates['status'] = 'complete';
        // Note: completedDates tracking moved to separate completion records
        // Target reached, mark as completed for today
      }
    }
    await habit.reference.update(updates);
  }
  /// Start timer for duration tracking
  static Future<void> startTimer(ActivityRecord habit) async {
    try {
      final updates = <String, dynamic>{
        'isTimerActive': true,
        'timerStartTime': DateTime.now(),
        'showInFloatingTimer': true,
        'lastUpdated': DateTime.now(),
      };
      await habit.reference.update(updates);
    } catch (e) {
      rethrow;
    }
  }
  /// Pause timer for duration tracking
  static Future<void> pauseTimer(ActivityRecord habit) async {
    try {
      if (!habit.isTimerActive) {
        return;
      }
      final now = DateTime.now();
      DateTime startTime = habit.timerStartTime ?? now;
      // Handle case where timer was running for too long (over 24 hours)
      final elapsed = now.difference(startTime).inMilliseconds;
      final maxDuration = 24 * 60 * 60 * 1000; // 24 hours in milliseconds
      final actualElapsed = elapsed > maxDuration ? maxDuration : elapsed;
      final newAccumulated = habit.accumulatedTime + actualElapsed;
      final updates = <String, dynamic>{
        'isTimerActive': false,
        'timerStartTime': null,
        'accumulatedTime': newAccumulated,
        'currentValue': newAccumulated ~/ 60000, // Convert to minutes
        'showInFloatingTimer': true,
        'lastUpdated': DateTime.now(),
      };
      await habit.reference.update(updates);
      // Also persist a session for analytics
      final sessionStart = habit.timerStartTime ?? now;
      final sessionEnd = now;
      try {
        await createWorkSession(
          type: 'habit',
          refId: habit.reference.id,
          startTime: sessionStart,
          endTime: sessionEnd,
          userId: FirebaseAuth.instance.currentUser?.uid ?? '',
        );
      } catch (e) {
        // Non-fatal
      }
    } catch (e) {
      rethrow;
    }
  }
  /// Stop timer for duration tracking (same as pause but more explicit)
  static Future<void> stopTimer(ActivityRecord habit) async {
    try {
      await pauseTimer(habit);
      // After a stop, hide from floating timer by default
      await habit.reference.update({
        'showInFloatingTimer': false,
        'lastUpdated': DateTime.now(),
      });
    } catch (e) {
      rethrow;
    }
  }
  /// Force stop timer (for stuck timers)
  static Future<void> forceStopTimer(ActivityRecord habit) async {
    try {
      final updates = <String, dynamic>{
        'isTimerActive': false,
        'timerStartTime': null,
        'showInFloatingTimer': false,
        'lastUpdated': DateTime.now(),
      };
      await habit.reference.update(updates);
    } catch (e) {
      rethrow;
    }
  }
  /// Get current timer display text with seconds
  static String getTimerDisplayTextWithSeconds(ActivityRecord habit) {
    if (!habit.isTimerActive || habit.timerStartTime == null) {
      return _formatDuration(habit.accumulatedTime);
    }
    final now = DateTime.now();
    DateTime startTime = habit.timerStartTime ?? now;
    final elapsed = now.difference(startTime).inMilliseconds;
    // Auto-stop if running for more than 24 hours
    final maxDuration = 24 * 60 * 60 * 1000; // 24 hours
    if (elapsed > maxDuration) {
      // Auto-stop the timer
      forceStopTimer(habit);
      return _formatDuration(habit.accumulatedTime + maxDuration);
    }
    final totalMilliseconds = habit.accumulatedTime + elapsed;
    return _formatDuration(totalMilliseconds);
  }
  /// Format duration in hr:min:sec format (for running times)
  static String _formatDuration(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes}:${seconds.toString().padLeft(2, '0')}';
    }
  }
  /// Format target duration in concise format (for targets)
  static String _formatTargetDuration(int minutes) {
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
  /// Get timer display text (legacy method for compatibility)
  static String getTimerDisplayText(ActivityRecord habit) {
    return getTimerDisplayTextWithSeconds(habit);
  }
  /// Format target time in concise format (public method)
  static String formatTargetTime(int minutes) {
    return _formatTargetDuration(minutes);
  }
  /// Get current timer display text without seconds
  static String getTimerDisplayTextNoSeconds(ActivityRecord habit) {
    if (!habit.isTimerActive || habit.timerStartTime == null) {
      final totalMinutes = habit.accumulatedTime ~/ 60000;
      return '${totalMinutes}min';
    }
    final now = DateTime.now();
    final elapsed = now.difference(habit.timerStartTime!).inMilliseconds;
    final totalMilliseconds = habit.accumulatedTime + elapsed;
    final totalMinutes = totalMilliseconds ~/ 60000;
    return '${totalMinutes}min';
  }
  /// Get default progress value for a tracking type
  static dynamic _getDefaultProgress(String trackingType) {
    switch (trackingType) {
      case 'binary':
        return false;
      case 'quantitative':
        return 0;
      case 'time':
        return 0;
      default:
        return null;
    }
  }
  /// Reset daily progress
  static Future<void> resetDailyProgress(ActivityRecord habit) async {
    final updates = <String, dynamic>{
      'currentValue': _getDefaultProgress(habit.trackingType),
      'accumulatedTime': 0,
      'isTimerActive': false,
      'timerStartTime': null,
      // Clear today's skip when a new day is started explicitly
      'lastUpdated': DateTime.now(),
    };
    await habit.reference.update(updates);
  }
  /// Mark habit as skipped for today (used by Snooze/Skip)
  static Future<void> skipToday(ActivityRecord habit) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Note: skippedDates tracking moved to separate records
    // For now, just update the snoozedUntil field
    await habit.reference.update({
      'snoozedUntil': DateTime(today.year, today.month, today.day + 1),
      'lastUpdated': DateTime.now(),
    });
  }
  static Future<void> addSkippedDate(
      ActivityRecord habit, DateTime date) async {
    final dateOnly = DateTime(date.year, date.month, date.day);
    await habit.reference.update({
      'skippedDates': FieldValue.arrayUnion([dateOnly]),
      'lastUpdated': DateTime.now(),
    });
  }
  static Duration getTrackedTime(ActivityRecord habit) {
    return Duration(milliseconds: habit.accumulatedTime);
  }
  static Duration getTargetDuration(ActivityRecord habit) {
    final targetMinutes = habit.target ?? 0;
    return Duration(minutes: targetMinutes);
  }
  /// Auto-stop timer if target duration is reached
  static Future<void> checkAndHandleCompletion(ActivityRecord habit) async {
    if (habit.trackingType != 'time') return;
    final targetMinutes = habit.target ?? 0;
    if (targetMinutes == 0) return;
    // Compute elapsed time
    int totalMs = habit.accumulatedTime;
    if (habit.isTimerActive && habit.timerStartTime != null) {
      final elapsed =
          DateTime.now().difference(habit.timerStartTime!).inMilliseconds;
      totalMs += elapsed;
    }
    final totalMinutes = totalMs ~/ 60000;
    if (totalMinutes >= targetMinutes) {
      // ✅ Stop the timer and mark as completed
      await habit.reference.update({
        'isTimerActive': false,
        'timerStartTime': null,
        'currentValue': true,
        'lastUpdated': DateTime.now(),
      });
    }
  }
  static bool getIsTimerActive(ActivityRecord habit) {
    return habit.isTimerActive;
  }
}
