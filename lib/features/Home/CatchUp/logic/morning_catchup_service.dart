import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:habit_tracker/core/utils/Date_time/date_formatter.dart';
import 'package:habit_tracker/core/utils/Date_time/ist_day_boundary_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/schema/user_progress_stats_record.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/features/toasts/bonus_notification_formatter.dart';
import 'package:habit_tracker/features/toasts/milestone_toast_service.dart';
import 'package:habit_tracker/features/Home/CatchUp/logic/day_end_processor.dart';
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';
import 'package:habit_tracker/services/diagnostics/fallback_read_logger.dart';

/// Service for managing morning catch-up dialog
/// Shows dialog on first app open after midnight for incomplete items from yesterday
class MorningCatchUpService {
  static const String _shownDateKey = 'morning_catchup_shown_date';
  static const String _snoozeUntilKey = 'morning_catchup_snooze_until';
  static const String _reminderCountKey = 'morning_catchup_reminder_count';
  static const String _reminderCountDateKey =
      'morning_catchup_reminder_count_date';
  static const String _toastsShownForDateKey =
      'morning_catchup_toasts_shown_for_date';
  static const int maxReminderCount = 3;

  static String _toastsShownForDateKeyForUser(String userId) =>
      '${_toastsShownForDateKey}_$userId';

  // Store pending toast data to show after catch-up dialog closes
  static Map<String, dynamic>? _pendingToastData;
  static Future<void> _scoreOperationQueue = Future.value();

  static Future<void> _enqueueScoreOperation(
      Future<void> Function() operation) async {
    // Prevent a failed operation from blocking subsequent queued operations.
    _scoreOperationQueue =
        _scoreOperationQueue.catchError((_) {}).then((_) => operation());
    await _scoreOperationQueue;
  }

  static HttpsCallable _callable(String name) {
    return FirebaseFunctions.instance.httpsCallable(name);
  }

  static Future<void> _finalizeDayViaCloud({
    required String userId,
    required DateTime date,
    bool overwrite = false,
  }) async {
    await _callable('finalizeDay').call({
      'userId': userId,
      'date': formatDateKeyIST(date),
      'overwrite': overwrite,
    });
  }

  static Future<void> _recalculateRangeViaCloud({
    required String userId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    await _callable('recalculateRange').call({
      'userId': userId,
      'fromDate': formatDateKeyIST(fromDate),
      'toDate': formatDateKeyIST(toDate),
    });
  }

  static Future<void> _backfillRecentViaCloud({
    required String userId,
    int days = 90,
  }) async {
    await _callable('backfillRecent').call({
      'userId': userId,
      'days': days,
    });
  }

  static Future<void> _runDayTransitionForUserViaCloud({
    required String userId,
    required DateTime date,
  }) async {
    await _callable('runDayTransitionForUser').call({
      'userId': userId,
      'date': formatDateKeyIST(date),
    });
  }

  static DateTime _normalizeDate(DateTime input) {
    return DateTime(input.year, input.month, input.day);
  }

  static bool _hasToastableScoreSignals(Map<String, dynamic> scoreData) {
    final consistencyBonus = (scoreData['consistencyBonus'] as num?) ?? 0;
    final recoveryBonus = (scoreData['recoveryBonus'] as num?) ?? 0;
    final decayPenalty = (scoreData['decayPenalty'] as num?) ?? 0;
    final categoryNeglectPenalty =
        (scoreData['categoryNeglectPenalty'] as num?) ?? 0;
    return consistencyBonus > 0 ||
        recoveryBonus > 0 ||
        decayPenalty > 0 ||
        categoryNeglectPenalty > 0;
  }

  static Future<bool> _storePendingToastsFromDailyProgress({
    required String userId,
    required DateTime targetDate,
  }) async {
    try {
      final normalizedDate = _normalizeDate(targetDate);
      final dateDocId = formatDateKeyIST(normalizedDate);
      final dailyRef =
          DailyProgressRecord.collectionForUser(userId).doc(dateDocId);
      DailyProgressRecord? dailyRecord;
      for (var attempt = 0; attempt < 3; attempt++) {
        final snapshot = await dailyRef.get();
        if (snapshot.exists) {
          dailyRecord = DailyProgressRecord.fromSnapshot(snapshot);
          break;
        }
        await Future.delayed(const Duration(milliseconds: 250));
      }
      if (dailyRecord == null) {
        _pendingToastData = null;
        return false;
      }

      var consecutiveLowDays = 0;
      try {
        final statsRef =
            UserProgressStatsRecord.collectionForUser(userId).doc('main');
        final stats = await UserProgressStatsRecord.getDocumentOnce(statsRef);
        consecutiveLowDays = stats.consecutiveLowDays;
      } catch (_) {
        // Best effort only.
      }

      final scoreData = <String, dynamic>{
        'consistencyBonus': dailyRecord.consistencyBonus,
        'recoveryBonus': dailyRecord.recoveryBonus,
        'decayPenalty': dailyRecord.decayPenalty,
        'categoryNeglectPenalty': dailyRecord.categoryNeglectPenalty,
        'dailyPoints': dailyRecord.dailyPoints,
        'dailyGain': dailyRecord.dailyScoreGain,
        'cumulativeScore': dailyRecord.cumulativeScoreSnapshot,
        'consecutiveLowDays': consecutiveLowDays,
        'newMilestones': const <dynamic>[],
      };

      _pendingToastData =
          _hasToastableScoreSignals(scoreData) ? scoreData : null;
      return true;
    } catch (_) {
      _pendingToastData = null;
      return false;
    }
  }

  static Future<bool> isDayTransitionProcessedInCloud({
    required String userId,
    required DateTime targetDateIst,
  }) async {
    try {
      final docRef =
          UserProgressStatsRecord.collectionForUser(userId).doc('main');
      final stats = await UserProgressStatsRecord.getDocumentOnce(docRef);
      final lastProcessedDate = stats.lastProcessedDate;
      if (lastProcessedDate == null) {
        return false;
      }

      final processedKey =
          IstDayBoundaryService.formatDateKeyIst(lastProcessedDate);
      final targetKey = IstDayBoundaryService.formatDateKeyIst(targetDateIst);
      return processedKey == targetKey;
    } catch (_) {
      return false;
    }
  }

  /// Pure check: Does the user have pending items from yesterday?
  /// This method has NO side effects - it only queries and returns a boolean
  /// Use this before running any processing logic
  static Future<bool> hasPendingItemsFromYesterday(String userId) async {
    try {
      return await _hasIncompleteItemsFromYesterday(userId);
    } catch (e) {
      return false; // On error, assume no pending items
    }
  }

  /// Check if the catch-up dialog should be shown
  /// Includes UI state checks (shown date, snooze)
  /// Keeps side effects minimal to avoid mixing instance handling and scoring
  static Future<bool> shouldShowDialog(String userId) async {
    final state = await getCatchUpLaunchState(userId);
    return state.shouldShow;
  }

  /// Check if there are incomplete items from yesterday ONLY (not older items)
  static Future<bool> _hasIncompleteItemsFromYesterday(String userId) async {
    try {
      final yesterday = IstDayBoundaryService.yesterdayStartIst();
      // Fast existence check with narrow equality queries.
      final results = await Future.wait([
        ActivityInstanceRecord.collectionForUser(userId)
            .where('templateCategoryType', isEqualTo: 'habit')
            .where('status', isEqualTo: 'pending')
            .where('belongsToDate', isEqualTo: yesterday)
            .limit(20)
            .get(),
        ActivityInstanceRecord.collectionForUser(userId)
            .where('templateCategoryType', isEqualTo: 'habit')
            .where('status', isEqualTo: 'pending')
            .where('windowEndDate', isEqualTo: yesterday)
            .limit(20)
            .get(),
      ]);

      final candidates = <ActivityInstanceRecord>[
        ...results[0].docs.map(ActivityInstanceRecord.fromSnapshot),
        ...results[1].docs.map(ActivityInstanceRecord.fromSnapshot),
      ];
      if (_filterYesterdayHabitItems(candidates, yesterday).isNotEmpty) {
        return true;
      }
      return false;
    } catch (e) {
      FallbackReadTelemetry.logQueryFallback(
        const FallbackReadEvent(
          scope: 'morning_catchup_service.hasIncompleteItemsFromYesterday',
          reason: 'scoped_yesterday_habit_existence_queries_failed',
          queryShape:
              'templateCategoryType=habit,status=pending,belongsToDate|windowEndDate=yesterday',
          userCountSampled: 1,
          fallbackDocsReadEstimate: 0,
        ),
      );
      return false;
    }
  }

  /// Return the launch state for catch-up.
  /// Includes whether to show dialog and whether reminder-cap auto resolve should run.
  static Future<CatchUpLaunchState> getCatchUpLaunchState(String userId) async {
    try {
      final todayKey = IstDayBoundaryService.formatDateKeyIst(DateTime.now());
      final prefs = await SharedPreferences.getInstance();
      final shownDateString = prefs.getString(_shownDateKey);
      final snoozeUntilString = prefs.getString(_snoozeUntilKey);
      final reminderCount = await getReminderCount();

      final shownToday = shownDateString != null &&
          IstDayBoundaryService.formatDateKeyIst(
                  DateTime.parse(shownDateString)) ==
              todayKey;
      final isSnoozedPending = snoozeUntilString != null;

      if (shownToday && !isSnoozedPending) {
        return const CatchUpLaunchState(
          items: [],
          reminderCount: 0,
          shouldShow: false,
          shouldAutoResolveAfterCap: false,
        );
      }

      final items = await getIncompleteItemsFromYesterday(userId);
      if (items.isEmpty) {
        await resetReminderCount();
        await clearSnooze();
        return CatchUpLaunchState(
          items: const [],
          reminderCount: reminderCount,
          shouldShow: false,
          shouldAutoResolveAfterCap: false,
        );
      }

      final shouldAutoResolveAfterCap =
          isSnoozedPending && reminderCount >= maxReminderCount;

      return CatchUpLaunchState(
        items: items,
        reminderCount: reminderCount,
        shouldShow: !shouldAutoResolveAfterCap,
        shouldAutoResolveAfterCap: shouldAutoResolveAfterCap,
      );
    } catch (e) {
      return const CatchUpLaunchState(
        items: [],
        reminderCount: 0,
        shouldShow: false,
        shouldAutoResolveAfterCap: false,
      );
    }
  }

  /// Deprecated: use getCatchUpLaunchState instead.
  /// Kept temporarily for compatibility.
  @Deprecated('Use getCatchUpLaunchState instead')
  static Future<List<ActivityInstanceRecord>> getDialogItemsIfShouldShow(
      String userId) async {
    final state = await getCatchUpLaunchState(userId);
    return state.shouldShow ? state.items : [];
  }

  /// Get incomplete items from yesterday ONLY (not older items)
  /// Optimized to run habit and task queries in parallel
  static Future<List<ActivityInstanceRecord>> getIncompleteItemsFromYesterday(
      String userId) async {
    try {
      final yesterday = IstDayBoundaryService.yesterdayStartIst();
      final today = IstDayBoundaryService.todayStartIst();
      final List<ActivityInstanceRecord> items = [];

      // Run habit and task queries in parallel for better performance
      final results = await Future.wait([
        _getHabitItemsFromYesterday(userId, yesterday),
        _getTaskItemsFromYesterday(userId, yesterday, today),
      ]);

      items.addAll(results[0]); // Habit items
      items.addAll(results[1]); // Task items

      return items;
    } catch (e) {
      return [];
    }
  }

  /// Get habit instances from yesterday (helper method for parallel execution)
  static Future<List<ActivityInstanceRecord>> _getHabitItemsFromYesterday(
      String userId, DateTime yesterday) async {
    try {
      // Narrow candidate fetch: belongs-to-yesterday OR ended-yesterday.
      final results = await Future.wait([
        ActivityInstanceRecord.collectionForUser(userId)
            .where('templateCategoryType', isEqualTo: 'habit')
            .where('status', isEqualTo: 'pending')
            .where('belongsToDate', isEqualTo: yesterday)
            .get(),
        ActivityInstanceRecord.collectionForUser(userId)
            .where('templateCategoryType', isEqualTo: 'habit')
            .where('status', isEqualTo: 'pending')
            .where('windowEndDate', isEqualTo: yesterday)
            .get(),
      ]);

      final merged = <String, ActivityInstanceRecord>{};
      for (final doc in results[0].docs) {
        final item = ActivityInstanceRecord.fromSnapshot(doc);
        merged[item.reference.id] = item;
      }
      for (final doc in results[1].docs) {
        final item = ActivityInstanceRecord.fromSnapshot(doc);
        merged[item.reference.id] = item;
      }

      return _filterYesterdayHabitItems(merged.values, yesterday);
    } catch (e) {
      logFirestoreIndexError(
        e,
        'getIncompleteItemsFromYesterday habit candidates (belongsToDate|windowEndDate = yesterday)',
        'activity_instances',
      );
      FallbackReadTelemetry.logQueryFallback(
        const FallbackReadEvent(
          scope: 'morning_catchup_service.getIncompleteItemsFromYesterday',
          reason: 'scoped_habit_yesterday_query_failed_no_broad_fallback',
          queryShape:
              'templateCategoryType=habit,status=pending,belongsToDate|windowEndDate=yesterday',
          userCountSampled: 1,
          fallbackDocsReadEstimate: 0,
        ),
      );
      return [];
    }
  }

  /// Get task instances from yesterday (helper method for parallel execution)
  static Future<List<ActivityInstanceRecord>> _getTaskItemsFromYesterday(
      String userId, DateTime yesterday, DateTime today) async {
    try {
      final taskQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'task')
          .where('status', isEqualTo: 'pending')
          .where('dueDate', isGreaterThanOrEqualTo: yesterday)
          .where('dueDate', isLessThan: today)
          .orderBy('dueDate', descending: false);
      final taskSnapshot = await taskQuery.get();
      // Filter to ONLY yesterday's tasks: dueDate is exactly yesterday
      final taskItems = taskSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((item) {
        if (item.status != 'pending' || item.skippedAt != null) {
          return false; // Exclude skipped/completed items
        }
        // Check if dueDate is exactly yesterday
        if (item.dueDate != null) {
          final dueDateOnly = DateTime(
            item.dueDate!.year,
            item.dueDate!.month,
            item.dueDate!.day,
          );
          return dueDateOnly.isAtSameMomentAs(yesterday);
        }
        return false;
      }).toList();
      return taskItems;
    } catch (e) {
      logFirestoreIndexError(
        e,
        'getIncompleteItemsFromYesterday taskQuery (templateCategoryType=task,status=pending,dueDate in [yesterday,today))',
        'activity_instances',
      );
      FallbackReadTelemetry.logQueryFallback(
        const FallbackReadEvent(
          scope: 'morning_catchup_service.getIncompleteItemsFromYesterday',
          reason: 'scoped_task_yesterday_query_failed_no_broad_fallback',
          queryShape:
              'templateCategoryType=task,status=pending,dueDate in [yesterday,today)',
          userCountSampled: 1,
          fallbackDocsReadEstimate: 0,
        ),
      );
      return [];
    }
  }

  static List<ActivityInstanceRecord> _filterYesterdayHabitItems(
      Iterable<ActivityInstanceRecord> candidates, DateTime yesterday) {
    return candidates.where((item) {
      if (item.status != 'pending' || item.skippedAt != null) return false;

      // Window must be closed by yesterday to be actionable in catch-up.
      if (item.windowEndDate != null) {
        final windowEndDateOnly = DateTime(
          item.windowEndDate!.year,
          item.windowEndDate!.month,
          item.windowEndDate!.day,
        );
        if (windowEndDateOnly.isAfter(yesterday)) return false;
      }

      if (item.belongsToDate != null) {
        final belongsToDateOnly = DateTime(
          item.belongsToDate!.year,
          item.belongsToDate!.month,
          item.belongsToDate!.day,
        );
        if (belongsToDateOnly.isAtSameMomentAs(yesterday)) return true;
      }

      if (item.windowEndDate != null) {
        final windowEndDateOnly = DateTime(
          item.windowEndDate!.year,
          item.windowEndDate!.month,
          item.windowEndDate!.day,
        );
        if (windowEndDateOnly.isAtSameMomentAs(yesterday)) return true;
      }

      return false;
    }).toList();
  }

  /// Mark dialog as shown for today
  static Future<void> markDialogAsShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setString(_shownDateKey, now.toIso8601String());
    } catch (e) {
      // Error marking dialog as shown
    }
  }

  /// Snooze the dialog to show on next app open (not 1 hour)
  /// Also increments reminder count
  static Future<void> snoozeDialog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Set snooze to a past date so it shows on next app open
      // We'll check if snoozeUntil is in the past to show dialog
      final pastDate = DateTime.now().subtract(const Duration(days: 1));
      await prefs.setString(_snoozeUntilKey, pastDate.toIso8601String());
      // Increment reminder count
      await incrementReminderCount();
    } catch (e) {
      // Error snoozing dialog
    }
  }

  /// Clear snooze (when dialog is shown after snooze expires)
  static Future<void> clearSnooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_snoozeUntilKey);
    } catch (e) {
      // Error clearing snooze
    }
  }

  /// Reset dialog state - clears shown date and snooze (for testing/debugging)
  static Future<void> resetDialogState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_shownDateKey);
      await prefs.remove(_snoozeUntilKey);
      await prefs.remove(_reminderCountKey);
      await prefs.remove(_reminderCountDateKey);
      await prefs.remove(_toastsShownForDateKey);
      final userToastKeys = prefs
          .getKeys()
          .where((k) => k.startsWith('${_toastsShownForDateKey}_'))
          .toList();
      for (final key in userToastKeys) {
        await prefs.remove(key);
      }
    } catch (e) {
      // Error resetting dialog state
    }
  }

  /// Auto-skip all items that expired before yesterday (NEW: Optimized with batch writes)
  /// This ensures everything is brought up to date before showing yesterday's items
  /// Uses frequency-aware bulk skip to efficiently handle large gaps
  static Future<void> autoSkipExpiredItemsBeforeYesterday(String userId) async {
    try {
      final yesterday = IstDayBoundaryService.yesterdayStartIst();
      final Set<DateTime> affectedDates = {};

      // For habits: Use new efficient bulk skip with batch writes
      // Find all habit instances where windowEndDate < yesterday
      final habitQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('status', isEqualTo: 'pending')
          .where('windowEndDate', isLessThan: yesterday)
          .orderBy('windowEndDate', descending: false)
          .limit(100);
      final habitSnapshot = await habitQuery.get();

      for (final doc in habitSnapshot.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.windowEndDate != null) {
          final windowEndDate = instance.windowEndDate!;
          final windowEndDateOnly = DateTime(
            windowEndDate.year,
            windowEndDate.month,
            windowEndDate.day,
          );
          // Only process if windowEndDate is before yesterday (already expired, not ongoing)
          // This ensures we don't touch active windows
          if (windowEndDateOnly.isBefore(yesterday)) {
            // Get template to calculate frequency
            try {
              final templateRef = ActivityRecord.collectionForUser(userId)
                  .doc(instance.templateId);
              final template =
                  await ActivityRecord.getDocumentOnce(templateRef);

              // Use bulk skip with batch writes - stops at yesterday for manual confirmation
              final yesterdayInstanceRef = await ActivityInstanceService
                  .bulkSkipExpiredInstancesWithBatches(
                oldestInstance: instance,
                template: template,
                userId: userId,
              );

              if (yesterdayInstanceRef != null) {
              } else {
                // Fallback: skip expired instance and generate next one normally
                // This should rarely happen as bulkSkipExpiredInstancesWithBatches now always returns a reference
                await ActivityInstanceService.skipInstance(
                  instanceId: instance.reference.id,
                  skippedAt: windowEndDateOnly,
                  skipAutoGeneration: false, // Allow normal generation
                  userId: userId,
                );
              }
            } catch (e) {
              // Fallback: skip normally if bulk skip fails
              await ActivityInstanceService.skipInstance(
                instanceId: instance.reference.id,
                skippedAt: windowEndDateOnly,
                skipAutoGeneration: true,
                userId: userId,
              );
            }

            // Track affected dates for progress recalculation
            if (instance.belongsToDate != null) {
              affectedDates.add(DateTime(
                instance.belongsToDate!.year,
                instance.belongsToDate!.month,
                instance.belongsToDate!.day,
              ));
            } else {
              affectedDates.add(windowEndDateOnly);
            }
          }
        }
      }

      // Tasks should NOT be auto-skipped - they remain pending indefinitely until user handles them
      // This is a deliberate design choice requested by user

      // Recalculate progress for all affected dates in parallel (with concurrency limit)
      if (affectedDates.isNotEmpty) {
        // Historical edit functionality removed - progress recalculation disabled
        // Process dates in batches
        // for (int i = 0; i < datesList.length; i += maxConcurrency) {
        //   final batch = datesList.skip(i).take(maxConcurrency).toList();
        //   await Future.wait(
        //     batch.map((date) async {
        //       try {
        //         await HistoricalEditService.recalculateDailyProgress(
        //           userId: userId,
        //           date: date,
        //         );
        //       } catch (e) {
        //         // Error recalculating progress for date
        //       }
        //     }),
        //   );
        // }
      }

      // After skipping expired instances with batch writes, yesterday's instances remain pending
      // for manual user confirmation via the morning catch-up dialog
    } catch (e) {
      // Error auto-skipping expired items
    }
  }

  /// Ensure all active habits have pending instances
  /// Delegates to DayEndProcessor since this is part of day-end processing
  static Future<void> ensurePendingInstancesExist(String userId) async {
    await DayEndProcessor.ensurePendingInstancesExist(userId);
  }

  /// Process all end-of-day activities for yesterday
  /// This keeps instance handling and score persistence separate
  static Future<void> processEndOfDayActivities(String userId) async {
    try {
      final yesterday = IstDayBoundaryService.yesterdayStartIst();

      await runInstanceMaintenanceForDayTransition(userId);

      // Persist scores for yesterday even if pending items exist
      await persistScoresForDate(userId: userId, targetDate: yesterday);
    } catch (e) {
      // Error processing end-of-day activities
      // Log but don't throw - this is a background operation
      print('Error processing end-of-day activities: $e');
    }
  }

  /// Get current reminder count for today's session
  static Future<int> getReminderCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey = IstDayBoundaryService.formatDateKeyIst(DateTime.now());

      // Check if reminder count is for today
      final countDateString = prefs.getString(_reminderCountDateKey);
      if (countDateString != null) {
        final countDate = DateTime.parse(countDateString);
        final countDateKey = IstDayBoundaryService.formatDateKeyIst(countDate);
        if (countDateKey == todayKey) {
          return prefs.getInt(_reminderCountKey) ?? 0;
        } else {
          // Different day - reset
          await resetReminderCount();
          return 0;
        }
      }
      return 0;
    } catch (e) {
      // Reset on error to be safe
      await resetReminderCount();
      return 0;
    }
  }

  /// Increment reminder count for today's session
  static Future<void> incrementReminderCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentCount = await getReminderCount();
      await prefs.setInt(_reminderCountKey, currentCount + 1);
      await prefs.setString(
          _reminderCountDateKey, DateTime.now().toIso8601String());
    } catch (e) {
      // Error incrementing reminder count
    }
  }

  /// Reset reminder count (when items are skipped or completed)
  static Future<void> resetReminderCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_reminderCountKey);
      await prefs.remove(_reminderCountDateKey);
    } catch (e) {
      // Error resetting reminder count
    }
  }

  /// Show pending toasts that were stored when suppressToasts was true
  /// This should be called after the catch-up dialog closes and scores are recalculated
  static void showPendingToasts() {
    if (_pendingToastData != null) {
      // Show bonus notifications
      BonusNotificationFormatter.showBonusNotifications(
        _pendingToastData!,
        dateLabel: 'yesterday',
      );

      // Show milestone achievements
      final newMilestones =
          _pendingToastData!['newMilestones'] as List<dynamic>? ?? [];
      if (newMilestones.isNotEmpty) {
        final milestoneValues = newMilestones.map((m) => m as int).toList();
        MilestoneToastService.showMultipleMilestones(milestoneValues);
      }

      // Clear pending data after showing
      _pendingToastData = null;
    }
  }

  /// Clear pending toast data (useful for cleanup)
  static void clearPendingToasts() {
    _pendingToastData = null;
  }

  static bool hasPendingToasts() {
    return _pendingToastData != null;
  }

  static Future<void> markFinalizationToastsShownForDate(
    DateTime targetDate, {
    String? userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = formatDateKeyIST(_normalizeDate(targetDate));
      await prefs.setString(_toastsShownForDateKey, key);
      if (userId != null && userId.isNotEmpty) {
        await prefs.setString(_toastsShownForDateKeyForUser(userId), key);
      }
    } catch (_) {
      // Ignore marker write failures.
    }
  }

  static Future<bool> _hasShownFinalizationToastsForDate(
    DateTime targetDate, {
    String? userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = formatDateKeyIST(_normalizeDate(targetDate));
      if (userId != null && userId.isNotEmpty) {
        final userScopedValue =
            prefs.getString(_toastsShownForDateKeyForUser(userId));
        if (userScopedValue == key) {
          return true;
        }
      }
      return prefs.getString(_toastsShownForDateKey) == key;
    } catch (_) {
      return false;
    }
  }

  /// Show finalized-day score toasts on first login when catch-up is not needed.
  static Future<void> showFinalizationToastsIfNeeded({
    required String userId,
    required DateTime targetDate,
  }) async {
    if (await _hasShownFinalizationToastsForDate(
      targetDate,
      userId: userId,
    )) {
      return;
    }

    final loaded = await _storePendingToastsFromDailyProgress(
      userId: userId,
      targetDate: targetDate,
    );
    if (!loaded) {
      return;
    }

    final hasToasts = hasPendingToasts();
    showPendingToasts();
    if (hasToasts) {
      await markFinalizationToastsShownForDate(
        targetDate,
        userId: userId,
      );
    }
  }

  /// Instance handling for day transition (no scoring/persistence)
  static Future<void> runInstanceMaintenanceForDayTransition(
      String userId) async {
    final yesterday = IstDayBoundaryService.yesterdayStartIst();
    await autoSkipExpiredItemsBeforeYesterday(userId);
    await DayEndProcessor.ensurePendingInstancesExist(userId);
    await DayEndProcessor.updateLastDayValuesOnly(userId, yesterday);
  }

  /// Persist points/scores for a specific date
  /// If [overwriteExisting] is true, existing records are recalculated
  /// [suppressToasts] - If true, toasts will be stored and shown later via showPendingToasts()
  static Future<void> persistScoresForDate({
    required String userId,
    required DateTime targetDate,
    bool overwriteExisting = false,
    bool suppressToasts = false,
  }) async {
    await _enqueueScoreOperation(() async {
      await _finalizeDayViaCloud(
        userId: userId,
        date: targetDate,
        overwrite: overwriteExisting,
      );
      if (suppressToasts) {
        await _storePendingToastsFromDailyProgress(
          userId: userId,
          targetDate: targetDate,
        );
      }
    });
  }

  /// Run cloud-maintained day transition for a specific IST day.
  /// Used as fallback when scheduled cloud processing is stale.
  static Future<void> runDayTransitionForUser({
    required String userId,
    required DateTime targetDate,
  }) async {
    await _enqueueScoreOperation(() async {
      await _runDayTransitionForUserViaCloud(
        userId: userId,
        date: targetDate,
      );
    });
  }

  /// Select scoring write mode based on cloud processed status at close time.
  /// If baseline is already processed (or becomes processed while dialog is open),
  /// use overwrite recompute. Otherwise, write first-time finalize.
  static Future<void> finalizeAfterCatchUpEdits({
    required String userId,
    required DateTime targetDate,
    required bool baselineProcessedAtOpen,
    bool suppressToasts = false,
  }) async {
    final processedNow = await isDayTransitionProcessedInCloud(
      userId: userId,
      targetDateIst: _normalizeDate(targetDate),
    );

    if (baselineProcessedAtOpen || processedNow) {
      await recalculateDailyProgressRecordForDate(
        userId: userId,
        targetDate: targetDate,
        suppressToasts: suppressToasts,
      );
      return;
    }

    await persistScoresForDate(
      userId: userId,
      targetDate: targetDate,
      overwriteExisting: false,
      suppressToasts: suppressToasts,
    );
  }

  /// Auto-resolve flow once reminder cap is reached:
  /// skip remaining habits for yesterday, keep tasks pending, and finalize scores.
  static Future<void> autoResolveAfterReminderCap({
    required String userId,
    required DateTime targetDate,
    required bool baselineProcessedAtOpen,
  }) async {
    final items = await getIncompleteItemsFromYesterday(userId);
    final remainingHabits = items
        .where((item) =>
            item.templateCategoryType == 'habit' &&
            item.status == 'pending' &&
            item.skippedAt == null)
        .toList();

    if (remainingHabits.isNotEmpty) {
      final yesterdayEnd = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        23,
        59,
        59,
      );
      await ActivityInstanceService.batchSkipInstances(
        instances: remainingHabits,
        skippedAt: yesterdayEnd,
        userId: userId,
      );
    }

    await finalizeAfterCatchUpEdits(
      userId: userId,
      targetDate: targetDate,
      baselineProcessedAtOpen: baselineProcessedAtOpen,
      suppressToasts: true,
    );

    await clearSnooze();
    await resetReminderCount();
    await markDialogAsShown();
  }

  /// Manual-only maintenance path for history repair/backfill.
  /// Not used in normal runtime day-end flow.
  static Future<void> persistScoresForMissedDaysIfNeeded(
      {required String userId}) async {
    await _enqueueScoreOperation(() async {
      await _backfillRecentViaCloud(userId: userId, days: 90);
    });
  }

  /// Recalculate and update daily progress record for a specific date
  /// This deletes the existing record (if any) and creates a new one with updated data
  /// Used when user completes items in morning catch-up dialog to ensure cumulative score is recalculated
  /// [suppressToasts] - If true, toasts will be stored and shown later via showPendingToasts()
  static Future<void> recalculateDailyProgressRecordForDate({
    required String userId,
    required DateTime targetDate,
    bool suppressToasts = false, // kept for API compatibility
  }) async {
    await _enqueueScoreOperation(() async {
      final normalizedStart = _normalizeDate(targetDate);
      await _recalculateRangeViaCloud(
        userId: userId,
        fromDate: normalizedStart,
        toDate: normalizedStart,
      );
      if (suppressToasts) {
        await _storePendingToastsFromDailyProgress(
          userId: userId,
          targetDate: normalizedStart,
        );
      }
    });
  }

  /// Finalize a specific day via cloud scorer.
  /// Optional collections are accepted for backward API compatibility but ignored.
  static Future<void> createDailyProgressRecordForDate({
    required String userId,
    required DateTime targetDate,
    bool suppressToasts = false, // kept for API compatibility
  }) async {
    await _enqueueScoreOperation(() async {
      await _finalizeDayViaCloud(
        userId: userId,
        date: targetDate,
        overwrite: true,
      );
      if (suppressToasts) {
        await _storePendingToastsFromDailyProgress(
          userId: userId,
          targetDate: targetDate,
        );
      }
    });
  }

  /// Manual-only alias for history repair/backfill.
  static Future<void> createRecordsForMissedDays({
    required String userId,
  }) async {
    await _enqueueScoreOperation(() async {
      await _backfillRecentViaCloud(userId: userId, days: 90);
    });
  }
}

class CatchUpLaunchState {
  const CatchUpLaunchState({
    required this.items,
    required this.reminderCount,
    required this.shouldShow,
    required this.shouldAutoResolveAfterCap,
  });

  final List<ActivityInstanceRecord> items;
  final int reminderCount;
  final bool shouldShow;
  final bool shouldAutoResolveAfterCap;
}
