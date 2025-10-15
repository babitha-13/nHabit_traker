import 'dart:async';
import 'dart:io';
import 'package:habit_tracker/Helper/backend/day_end_processor.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

/// Background scheduler for automatic day-end processing
/// Handles running DayEndProcessor at appropriate times
class BackgroundScheduler {
  static Timer? _dayEndTimer;
  static Timer? _checkTimer;
  static DateTime? _lastProcessedDate;
  static bool _isProcessing = false;

  /// Initialize the background scheduler
  /// Should be called when the app starts
  static void initialize() {
    print('BackgroundScheduler: Initializing background scheduler...');

    // Cancel any existing timers
    _dayEndTimer?.cancel();
    _checkTimer?.cancel();

    // Set up the day-end timer (runs at midnight)
    _scheduleDayEndTimer();

    // Set up a periodic check timer (runs every 30 minutes)
    _scheduleCheckTimer();

    // Check if we need to process any missed days on startup
    _checkForMissedProcessing();
  }

  /// Schedule the day-end timer to run at midnight
  static void _scheduleDayEndTimer() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    print(
        'BackgroundScheduler: Scheduling day-end timer for ${timeUntilMidnight.inHours}h ${timeUntilMidnight.inMinutes % 60}m');

    _dayEndTimer = Timer(timeUntilMidnight, () {
      _processDayEnd();
      // Reschedule for the next day
      _scheduleDayEndTimer();
    });
  }

  /// Schedule a periodic check timer (every 30 minutes)
  static void _scheduleCheckTimer() {
    _checkTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      _checkForMissedProcessing();
    });
  }

  /// Check if we need to process any missed days
  static Future<void> _checkForMissedProcessing() async {
    if (_isProcessing) {
      print('BackgroundScheduler: Already processing, skipping check');
      return;
    }

    try {
      final currentUser = currentUserUid;
      if (currentUser.isEmpty) {
        print('BackgroundScheduler: No authenticated user, skipping check');
        return;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Check if we've already processed today
      if (_lastProcessedDate != null &&
          _isSameDay(_lastProcessedDate!, today)) {
        return;
      }

      // Check if we need to process yesterday or earlier
      final yesterday = today.subtract(const Duration(days: 1));
      final daysToCheck = <DateTime>[];

      // Add yesterday if we haven't processed it
      if (_lastProcessedDate == null ||
          _lastProcessedDate!.isBefore(yesterday)) {
        daysToCheck.add(yesterday);
      }

      // Add today if it's past 1 AM (grace period)
      if (now.hour >= 1) {
        daysToCheck.add(today);
      }

      if (daysToCheck.isNotEmpty) {
        print(
            'BackgroundScheduler: Found ${daysToCheck.length} days to process');
        await _processMultipleDays(currentUser, daysToCheck);
      }
    } catch (e) {
      print('BackgroundScheduler: Error in check: $e');
    }
  }

  /// Process day-end for a specific date
  static Future<void> _processDayEnd() async {
    if (_isProcessing) {
      print('BackgroundScheduler: Already processing, skipping day-end');
      return;
    }

    try {
      final currentUser = currentUserUid;
      if (currentUser.isEmpty) {
        print(
            'BackgroundScheduler: No authenticated user for day-end processing');
        return;
      }

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await _processDayEndForUser(currentUser, yesterday);
    } catch (e) {
      print('BackgroundScheduler: Error in day-end processing: $e');
    }
  }

  /// Process multiple days for a user
  static Future<void> _processMultipleDays(
      String userId, List<DateTime> dates) async {
    _isProcessing = true;

    try {
      for (final date in dates) {
        await _processDayEndForUser(userId, date);
        await Future.delayed(
            const Duration(seconds: 1)); // Small delay between days
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Process day-end for a specific user and date
  static Future<void> _processDayEndForUser(
      String userId, DateTime date) async {
    try {
      print(
          'BackgroundScheduler: Processing day-end for user $userId on ${date.toIso8601String()}');

      await DayEndProcessor.processDayEnd(userId: userId, targetDate: date);

      _lastProcessedDate = date;
      print(
          'BackgroundScheduler: Successfully processed day-end for ${date.toIso8601String()}');
    } catch (e) {
      print(
          'BackgroundScheduler: Error processing day-end for ${date.toIso8601String()}: $e');
    }
  }

  /// Manually trigger day-end processing (for testing or manual use)
  static Future<void> triggerDayEndProcessing({DateTime? targetDate}) async {
    final currentUser = currentUserUid;
    if (currentUser.isEmpty) {
      throw Exception('No authenticated user');
    }

    final date = targetDate ?? DateTime.now().subtract(const Duration(days: 1));
    await _processDayEndForUser(currentUser, date);
  }

  /// Check if day-end processing is currently running
  static bool get isProcessing => _isProcessing;

  /// Get the last processed date
  static DateTime? get lastProcessedDate => _lastProcessedDate;

  /// Cancel all timers (useful for testing or app shutdown)
  static void cancel() {
    _dayEndTimer?.cancel();
    _checkTimer?.cancel();
    _dayEndTimer = null;
    _checkTimer = null;
    print('BackgroundScheduler: All timers cancelled');
  }

  /// Helper method to check if two dates are the same day
  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Get scheduler status for debugging
  static Map<String, dynamic> getStatus() {
    return {
      'isProcessing': _isProcessing,
      'lastProcessedDate': _lastProcessedDate?.toIso8601String(),
      'dayEndTimerActive': _dayEndTimer?.isActive ?? false,
      'checkTimerActive': _checkTimer?.isActive ?? false,
    };
  }
}

/// Platform-specific background task handler
class BackgroundTaskHandler {
  /// Initialize platform-specific background tasks
  static void initialize() {
    if (Platform.isAndroid) {
      _initializeAndroidBackgroundTasks();
    } else if (Platform.isIOS) {
      _initializeIOSBackgroundTasks();
    }
  }

  /// Initialize Android-specific background tasks
  static void _initializeAndroidBackgroundTasks() {
    // For Android, we can use WorkManager or AlarmManager
    // This is a placeholder for Android-specific implementation
    print('BackgroundTaskHandler: Android background tasks initialized');
  }

  /// Initialize iOS-specific background tasks
  static void _initializeIOSBackgroundTasks() {
    // For iOS, we can use BGAppRefreshTask
    // This is a placeholder for iOS-specific implementation
    print('BackgroundTaskHandler: iOS background tasks initialized');
  }
}
