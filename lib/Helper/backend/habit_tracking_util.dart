import 'package:firebase_auth/firebase_auth.dart';
import 'schema/habit_record.dart';
import 'backend.dart';

class HabitTrackingUtil {
  /// Check if a habit should be tracked today based on its schedule
  static bool shouldTrackToday(HabitRecord habit) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Respect explicit skips
    // Note: skippedDates tracking moved to separate records

    switch (habit.schedule) {
      case 'daily':
        return true;
      case 'weekly':
        if (habit.specificDays.isNotEmpty) {
          final weekday = now.weekday;
          return habit.specificDays.contains(weekday);
        } else {
          final weekStart = today.subtract(Duration(days: today.weekday - 1));
          final weekEnd = weekStart.add(const Duration(days: 6));

          // Note: completedDates tracking moved to separate completion records
          final completedThisWeek = <DateTime>[].where((date) {
            final completionDate = DateTime(date.year, date.month, date.day);
            return completionDate
                    .isAfter(weekStart.subtract(const Duration(days: 1))) &&
                completionDate.isBefore(weekEnd.add(const Duration(days: 1)));
          }).length;
          return completedThisWeek < habit.frequency;
        }
      case 'monthly':
        // Check if we haven't completed enough times this month
        final monthStart = DateTime(now.year, now.month, 1);
        final monthEnd = DateTime(now.year, now.month + 1, 0);

        // Note: completedDates tracking moved to separate completion records
        final completedThisMonth = <DateTime>[].where((date) {
          final completionDate = DateTime(date.year, date.month, date.day);
          return completionDate
                  .isAfter(monthStart.subtract(const Duration(days: 1))) &&
              completionDate.isBefore(monthEnd.add(const Duration(days: 1)));
        }).length;

        return completedThisMonth <
            habit.frequency; // reuse as count for month for now
      default:
        return true;
    }
  }

  /// Check if progress should be reset based on day end time
  static bool shouldResetProgress(HabitRecord habit) {
    // For now, disable automatic progress reset to fix the constant reset issue
    // Progress should only be reset when explicitly starting a new day
    // TODO: Implement proper day boundary logic based on lastUpdated field
    return false;
  }

  /// Get the current day's progress for a habit
  static dynamic getCurrentProgress(HabitRecord habit) {
    if (shouldResetProgress(habit)) {
      final defaultProgress = _getDefaultProgress(habit.trackingType);
      return defaultProgress;
    }

    final currentProgress =
        habit.currentValue ?? _getDefaultProgress(habit.trackingType);
    return currentProgress;
  }

  /// Get the target value for a habit
  static dynamic getTarget(HabitRecord habit) {
    return habit.target;
  }

  /// Check if a habit is completed for today
  static bool isCompletedToday(HabitRecord habit) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

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
  static double getProgressPercentage(HabitRecord habit) {
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
  static String getProgressText(HabitRecord habit) {
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
  static String getTargetText(HabitRecord habit) {
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
    HabitRecord habit,
    dynamic newProgress,
  ) async {
    try {
      print(
          'Updating progress for habit: ${habit.name}, trackingType: ${habit.trackingType}, oldValue: ${habit.currentValue}, newValue: $newProgress');

      final updates = <String, dynamic>{
        'currentValue': newProgress,
        'lastUpdated': DateTime.now(),
      };

      await habit.reference.update(updates);
      print('Successfully updated progress for habit: ${habit.name}');
    } catch (e) {
      print('Error updating progress for habit ${habit.name}: $e');
      rethrow;
    }
  }

  /// Mark habit as completed for today
  static Future<void> markCompleted(HabitRecord habit) async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

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
  static Future<void> startTimer(HabitRecord habit) async {
    try {
      print('Starting timer for habit: ${habit.name}');

      final updates = <String, dynamic>{
        'isTimerActive': true,
        'timerStartTime': DateTime.now(),
        'showInFloatingTimer': true,
        'lastUpdated': DateTime.now(),
      };

      await habit.reference.update(updates);
      print('Timer started successfully for habit: ${habit.name}');
    } catch (e) {
      print('Error starting timer for habit ${habit.name}: $e');
      rethrow;
    }
  }

  /// Pause timer for duration tracking
  static Future<void> pauseTimer(HabitRecord habit) async {
    try {
      print(
          'Pausing timer for habit: ${habit.name}, isActive: ${habit.isTimerActive}');

      if (!habit.isTimerActive) {
        print('Timer already paused for habit: ${habit.name}');
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
        print('Failed to create work session: $e');
      }
      print(
          'Timer paused successfully for habit: ${habit.name}, accumulated: ${newAccumulated}ms');
    } catch (e) {
      print('Error pausing timer for habit ${habit.name}: $e');
      rethrow;
    }
  }

  /// Stop timer for duration tracking (same as pause but more explicit)
  static Future<void> stopTimer(HabitRecord habit) async {
    try {
      print('Stopping timer for habit: ${habit.name}');
      await pauseTimer(habit);
      // After a stop, hide from floating timer by default
      await habit.reference.update({
        'showInFloatingTimer': false,
        'lastUpdated': DateTime.now(),
      });
      print('Timer stopped successfully for habit: ${habit.name}');
    } catch (e) {
      print('Error stopping timer for habit ${habit.name}: $e');
      rethrow;
    }
  }

  /// Force stop timer (for stuck timers)
  static Future<void> forceStopTimer(HabitRecord habit) async {
    try {
      print('Force stopping timer for habit: ${habit.name}');

      final updates = <String, dynamic>{
        'isTimerActive': false,
        'timerStartTime': null,
        'showInFloatingTimer': false,
        'lastUpdated': DateTime.now(),
      };

      await habit.reference.update(updates);
      print('Timer force stopped successfully for habit: ${habit.name}');
    } catch (e) {
      print('Error force stopping timer for habit ${habit.name}: $e');
      rethrow;
    }
  }

  /// Get current timer display text with seconds
  static String getTimerDisplayTextWithSeconds(HabitRecord habit) {
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
  static String getTimerDisplayText(HabitRecord habit) {
    return getTimerDisplayTextWithSeconds(habit);
  }

  /// Format target time in concise format (public method)
  static String formatTargetTime(int minutes) {
    return _formatTargetDuration(minutes);
  }

  /// Get current timer display text without seconds
  static String getTimerDisplayTextNoSeconds(HabitRecord habit) {
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
  static Future<void> resetDailyProgress(HabitRecord habit) async {
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
  static Future<void> skipToday(HabitRecord habit) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Note: skippedDates tracking moved to separate records
    // For now, just update the snoozedUntil field
    await habit.reference.update({
      'snoozedUntil': DateTime(today.year, today.month, today.day + 1),
      'lastUpdated': DateTime.now(),
    });
  }

  static Duration getTrackedTime(HabitRecord habit) {
    return Duration(milliseconds: habit.accumulatedTime);
  }

  static Duration getTargetDuration(HabitRecord habit) {
    final targetMinutes = habit.target ?? 0;
    return Duration(minutes: targetMinutes);
  }

  /// Auto-stop timer if target duration is reached
  static Future<void> checkAndHandleCompletion(HabitRecord habit) async {
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
      print(
          'Habit ${habit.name} reached target $targetMinutes min, auto-stopped & marked completed.');
    }
  }

  static bool getIsTimerActive(HabitRecord habit) {
    return habit.isTimerActive;
  }
}
