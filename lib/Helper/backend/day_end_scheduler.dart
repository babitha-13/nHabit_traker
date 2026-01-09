import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing day-end processing with snooze functionality
/// NOTE: Automatic processing is disabled - users must manually confirm status changes via Queue page
/// Handles scheduling, notifications, and user snooze requests (currently disabled)
class DayEndScheduler {
  static const int _maxSnoozeMinutes = 60; // 1 hour max snooze
  static const int _defaultProcessHour = 0; // Midnight default
  static const String _scheduledTimeKey = 'day_end_scheduled_time';
  static const String _snoozeUsedKey = 'day_end_snooze_used';
  static const String _lastResetKey = 'day_end_last_reset';
  static DateTime? _scheduledProcessTime;
  static int _snoozeUsedMinutes = 0;
  static DateTime? _lastResetDate;
  static Timer? _dayEndTimer;

  /// Initialize the day-end scheduler
  /// Should be called when the app starts
  static Future<void> initialize() async {
    // Load state from SharedPreferences
    await _loadState();
    // Reset snooze budget if it's a new day
    await _checkAndResetSnoozeBudget();
    // Schedule the next day-end processing
    await _scheduleNextDayEnd();
  }

  /// Load scheduler state from SharedPreferences
  static Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Load scheduled process time
      final scheduledTimeString = prefs.getString(_scheduledTimeKey);
      if (scheduledTimeString != null) {
        _scheduledProcessTime = DateTime.parse(scheduledTimeString);
      }
      // Load snooze used
      _snoozeUsedMinutes = prefs.getInt(_snoozeUsedKey) ?? 0;
      // Load last reset date
      final lastResetString = prefs.getString(_lastResetKey);
      if (lastResetString != null) {
        _lastResetDate = DateTime.parse(lastResetString);
      }
    } catch (e) {
      // Log error but don't fail - SharedPreferences load failure is non-critical
      print('Error loading day end scheduler state: $e');
    }
  }

  /// Save scheduler state to SharedPreferences
  static Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_scheduledProcessTime != null) {
        await prefs.setString(
            _scheduledTimeKey, _scheduledProcessTime!.toIso8601String());
      }
      await prefs.setInt(_snoozeUsedKey, _snoozeUsedMinutes);
      if (_lastResetDate != null) {
        await prefs.setString(_lastResetKey, _lastResetDate!.toIso8601String());
      }
    } catch (e) {
      // Log error but don't fail - SharedPreferences save failure is non-critical
      print('Error saving day end scheduler state: $e');
    }
  }

  /// Check if snooze budget should be reset (new day)
  static Future<void> _checkAndResetSnoozeBudget() async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    // If no last reset date or it's a new day, reset snooze budget
    if (_lastResetDate == null || !_isSameDay(_lastResetDate!, todayDate)) {
      _snoozeUsedMinutes = 0;
      _lastResetDate = todayDate;
      await _saveState();
    }
  }

  /// Schedule the next day-end processing
  static Future<void> _scheduleNextDayEnd() async {
    // Cancel existing timer
    _dayEndTimer?.cancel();
    // Calculate the next processing time
    final now = DateTime.now();
    DateTime nextProcessTime;
    if (_scheduledProcessTime != null) {
      // Use existing scheduled time (may be snoozed)
      nextProcessTime = _scheduledProcessTime!;
    } else {
      // Calculate next midnight
      nextProcessTime = _getNextMidnight(now);
    }
    // If the scheduled time has already passed today, move to tomorrow
    if (nextProcessTime.isBefore(now)) {
      nextProcessTime = nextProcessTime.add(const Duration(days: 1));
    }
    _scheduledProcessTime = nextProcessTime;
    await _saveState();
    // NOTE: Automatic timer disabled - day-end processing now requires manual user confirmation
    // Users can process expired instances via the Queue page "Needs Processing" section
    // The timer and automatic status changes have been disabled
    // Schedule the timer (DISABLED)
    // final timeUntilProcessing = nextProcessTime.difference(now);
    // _dayEndTimer = Timer(timeUntilProcessing, () async {
    //   await _processDayEnd();
    //   // Reschedule for next day
    //   await _scheduleNextDayEnd();
    // });
    // Schedule notifications (disabled since automatic processing is disabled)
    // await _scheduleDayEndNotifications();
  }

  /// Get the next midnight from the given time
  static DateTime _getNextMidnight(DateTime from) {
    final todayMidnight =
        DateTime(from.year, from.month, from.day, _defaultProcessHour);
    if (from.isBefore(todayMidnight)) {
      return todayMidnight;
    } else {
      return todayMidnight.add(const Duration(days: 1));
    }
  }

  /// Snooze the day-end processing
  /// Returns true if snooze was successful, false if max snooze reached
  static Future<bool> snooze(int minutes) async {
    // Check if snooze would exceed max limit
    if (_snoozeUsedMinutes + minutes > _maxSnoozeMinutes) {
      return false;
    }
    // Check if we have a scheduled time to snooze
    if (_scheduledProcessTime == null) {
      return false;
    }
    // Update scheduled time
    final newScheduledTime =
        _scheduledProcessTime!.add(Duration(minutes: minutes));
    _scheduledProcessTime = newScheduledTime;
    _snoozeUsedMinutes += minutes;
    await _saveState();
    // Reschedule timer and notifications
    await _scheduleNextDayEnd();
    return true;
  }

  /// Get remaining snooze budget in minutes
  static int get remainingSnoozeMinutes {
    return _maxSnoozeMinutes - _snoozeUsedMinutes;
  }

  /// Get the currently scheduled process time
  static DateTime? get scheduledProcessTime => _scheduledProcessTime;

  /// Get snooze used so far
  static int get snoozeUsedMinutes => _snoozeUsedMinutes;

  /// Check if user can snooze for the given minutes
  static bool canSnooze(int minutes) {
    return _snoozeUsedMinutes + minutes <= _maxSnoozeMinutes;
  }

  /// Get snooze status for UI
  static Map<String, dynamic> getSnoozeStatus() {
    return {
      'scheduledTime': _scheduledProcessTime?.toIso8601String(),
      'snoozeUsed': _snoozeUsedMinutes,
      'remainingSnooze': remainingSnoozeMinutes,
      'maxSnooze': _maxSnoozeMinutes,
      'canSnooze15': canSnooze(15),
      'canSnooze30': canSnooze(30),
      'canSnooze60': canSnooze(60),
    };
  }

  /// Cancel all timers and clear state
  static void cancel() {
    _dayEndTimer?.cancel();
    _dayEndTimer = null;
  }

  /// Helper method to check if two dates are the same day
  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
