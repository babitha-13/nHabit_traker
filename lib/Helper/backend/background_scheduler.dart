import 'dart:async';
import 'dart:io';
import 'package:habit_tracker/Helper/backend/day_end_processor.dart';
import 'package:habit_tracker/Helper/backend/day_end_scheduler.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Background scheduler for automatic day-end processing
/// Handles running DayEndProcessor at appropriate times
class BackgroundScheduler {
  static Timer? _dayEndTimer;
  static Timer? _checkTimer;
  static DateTime? _lastProcessedDate;
  static bool _isProcessing = false;

  /// Initialize the background scheduler
  /// Should be called when the app starts
  static void initialize() async {
    print('BackgroundScheduler: Initializing background scheduler...');

    // Cancel any existing timers
    _dayEndTimer?.cancel();
    _checkTimer?.cancel();

    // Initialize the day-end scheduler (handles snooze and notifications)
    await DayEndScheduler.initialize();

    // Load last processed date from SharedPreferences
    await _loadLastProcessedDate();

    // Set up a periodic check timer (runs every 30 minutes)
    _scheduleCheckTimer();

    // Check if we need to process any missed days on startup
    _checkForMissedProcessing();
  }

  /// Schedule a periodic check timer (every 30 minutes)
  static void _scheduleCheckTimer() {
    _checkTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      _checkForMissedProcessing();
    });
  }

  /// Check if we need to process any missed days (shifted boundary)
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

      final latestProcessable = DateService.latestProcessableShiftedDate;

      // If we haven't processed any day yet, look back for oldest expired instance
      if (_lastProcessedDate == null) {
        final oldestExpiredDate = await _findOldestExpiredInstance(currentUser);
        if (oldestExpiredDate != null) {
          // Process all dates from oldest expired up to latestProcessable
          final daysToProcess = <DateTime>[];
          var cursor = oldestExpiredDate;
          while (!_isSameDay(cursor, latestProcessable)) {
            daysToProcess.add(cursor);
            cursor = cursor.add(const Duration(days: 1));
          }
          daysToProcess.add(latestProcessable);

          print(
              'BackgroundScheduler: Found ${daysToProcess.length} days to process from oldest expired ($oldestExpiredDate) to latest ($latestProcessable)');
          await _processMultipleDays(currentUser, daysToProcess);
        } else {
          // No expired instances found, just process latest
          await _processMultipleDays(currentUser, [latestProcessable]);
        }
        return;
      }

      // If last processed is already latest, nothing to do
      final last = _lastProcessedDate!;
      if (_isSameDay(last, latestProcessable)) {
        return;
      }

      // Build list of missing dates from last+1 up to latestProcessable
      final daysToCheck = <DateTime>[];
      var cursor = DateTime(last.year, last.month, last.day)
          .add(const Duration(days: 1));
      while (!_isSameDay(cursor, latestProcessable)) {
        daysToCheck.add(cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
      daysToCheck.add(latestProcessable);

      if (daysToCheck.isNotEmpty) {
        print(
            'BackgroundScheduler: Found ${daysToCheck.length} shifted days to process');
        await _processMultipleDays(currentUser, daysToCheck);
      }
    } catch (e) {
      print('BackgroundScheduler: Error in check: $e');
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

      _lastProcessedDate = DateTime(date.year, date.month, date.day);
      await _saveLastProcessedDate();
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

    // Also cancel day-end scheduler
    DayEndScheduler.cancel();

    print('BackgroundScheduler: All timers cancelled');
  }

  /// Find the oldest expired habit instance to determine how far back to process
  static Future<DateTime?> _findOldestExpiredInstance(String userId) async {
    try {
      // Query for pending habit instances with expired windows
      final query = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('status', isEqualTo: 'pending')
          .where('windowEndDate', isLessThan: DateTime.now())
          .orderBy('windowEndDate', descending: false)
          .limit(1);

      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
        final instance =
            ActivityInstanceRecord.fromSnapshot(snapshot.docs.first);
        final oldestExpiredDate = DateTime(
          instance.windowEndDate!.year,
          instance.windowEndDate!.month,
          instance.windowEndDate!.day,
        );
        print(
            'BackgroundScheduler: Found oldest expired instance with windowEndDate: $oldestExpiredDate');
        return oldestExpiredDate;
      }

      print('BackgroundScheduler: No expired instances found');
      return null;
    } catch (e) {
      print('BackgroundScheduler: Error finding oldest expired instance: $e');
      return null;
    }
  }

  /// Load last processed date from SharedPreferences
  static Future<void> _loadLastProcessedDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dateString =
          prefs.getString('background_scheduler_last_processed_date');
      if (dateString != null) {
        _lastProcessedDate = DateTime.parse(dateString);
        print(
            'BackgroundScheduler: Loaded last processed date: $_lastProcessedDate');
      } else {
        print('BackgroundScheduler: No saved last processed date found');
      }
    } catch (e) {
      print('BackgroundScheduler: Error loading last processed date: $e');
    }
  }

  /// Save last processed date to SharedPreferences
  static Future<void> _saveLastProcessedDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_lastProcessedDate != null) {
        await prefs.setString('background_scheduler_last_processed_date',
            _lastProcessedDate!.toIso8601String());
        print(
            'BackgroundScheduler: Saved last processed date: $_lastProcessedDate');
      }
    } catch (e) {
      print('BackgroundScheduler: Error saving last processed date: $e');
    }
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
