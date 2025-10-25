import 'dart:async';
import 'dart:io';
import 'package:habit_tracker/Helper/backend/day_end_processor.dart';
import 'package:habit_tracker/Helper/backend/day_end_scheduler.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
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
  static Future<void> initialize() async {
    try {
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
    } catch (e) {
      rethrow;
    }
  }

  /// Schedule a periodic check timer (every 30 minutes)
  static void _scheduleCheckTimer() {
    _checkTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      _checkForMissedProcessing();
    });
  }

  /// Check if we need to process any missed days (shifted boundary)
  static Future<void> _checkForMissedProcessing() async {
    print('BackgroundScheduler: _checkForMissedProcessing() called');
    if (_isProcessing) {
      return;
    }
    try {
      final currentUser = currentUserUid;
      if (currentUser.isEmpty) {
        return;
      }
      final latestProcessable = DateService.latestProcessableShiftedDate;
      print(
          'BackgroundScheduler: Checking missed processing (last: $_lastProcessedDate, latest: $latestProcessable)');
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
        // Even if dates match, check for unprocessed expired instances
        await _checkAndProcessExpiredInstances(currentUser);
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
        await _processMultipleDays(currentUser, daysToCheck);
      }
    } catch (e) {}
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
      await DayEndProcessor.processDayEnd(userId: userId, targetDate: date);
      _lastProcessedDate = DateTime(date.year, date.month, date.day);
      await _saveLastProcessedDate();
    } catch (e) {}
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

  /// Force check for missed processing (for testing)
  static Future<void> forceCheckForMissedProcessing() async {
    await _checkForMissedProcessing();
  }

  /// Check for and process any unprocessed expired instances
  /// Returns true if any were found and processed
  static Future<bool> _checkAndProcessExpiredInstances(String userId) async {
    final latestProcessable = DateService.latestProcessableShiftedDate;
    bool foundAny = false;
    int loopCount = 0;
    const maxLoops = 100; // Safety limit to prevent infinite loops
    while (loopCount < maxLoops) {
      loopCount++;
      print(
          'BackgroundScheduler: Checking for expired instances (iteration $loopCount)...');
      final query = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('status', isEqualTo: 'pending')
          .where('windowEndDate', isLessThanOrEqualTo: latestProcessable);
      final unprocessed = await query.get();
      if (unprocessed.docs.isEmpty) {
        break;
      }
      foundAny = true;
      for (final doc in unprocessed.docs) {
        final inst = ActivityInstanceRecord.fromSnapshot(doc);
      }
      // Process them by calling the day-end processor
      await _processDayEndForUser(userId, latestProcessable);
      // Add small delay to allow Firestore to update
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (loopCount >= maxLoops) {}
    // If we processed any instances, trigger UI refresh
    if (foundAny) {
      // Trigger UI refresh via NotificationCenter
      NotificationCenter.post('loadData');
    }
    return foundAny;
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
        return oldestExpiredDate;
      }
      return null;
    } catch (e) {
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
      } else {}
    } catch (e) {}
  }

  /// Save last processed date to SharedPreferences
  static Future<void> _saveLastProcessedDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_lastProcessedDate != null) {
        await prefs.setString('background_scheduler_last_processed_date',
            _lastProcessedDate!.toIso8601String());
      }
    } catch (e) {}
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
  }

  /// Initialize iOS-specific background tasks
  static void _initializeIOSBackgroundTasks() {
    // For iOS, we can use BGAppRefreshTask
    // This is a placeholder for iOS-specific implementation
  }
}
