import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/daily_points_calculator.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/Scores/old_score_formula_service.dart';
import 'package:habit_tracker/features/Progress/Point_system_helper/points_service.dart';
import 'package:habit_tracker/features/toasts/bonus_notification_formatter.dart';
import 'package:habit_tracker/features/toasts/milestone_toast_service.dart';
import 'package:habit_tracker/features/Home/CatchUp/logic/day_end_processor.dart';

/// Service for managing morning catch-up dialog
/// Shows dialog on first app open after midnight for incomplete items from yesterday
class MorningCatchUpService {
  static const String _shownDateKey = 'morning_catchup_shown_date';
  static const String _snoozeUntilKey = 'morning_catchup_snooze_until';
  static const String _reminderCountKey = 'morning_catchup_reminder_count';
  static const String _reminderCountDateKey =
      'morning_catchup_reminder_count_date';
  static const int maxReminderCount = 2;

  // Store pending toast data to show after catch-up dialog closes
  static Map<String, dynamic>? _pendingToastData;

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
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final prefs = await SharedPreferences.getInstance();

      // Check if dialog was already shown today
      final shownDateString = prefs.getString(_shownDateKey);
      final snoozeUntilString = prefs.getString(_snoozeUntilKey);

      if (shownDateString != null) {
        final shownDate = DateTime.parse(shownDateString);
        final shownDateOnly =
            DateTime(shownDate.year, shownDate.month, shownDate.day);
        if (shownDateOnly.isAtSameMomentAs(today) &&
            snoozeUntilString == null) {
          // Dialog was shown and completed - don't show again today
          return false;
        }
      }

      if (snoozeUntilString != null) {
        // "Remind me later" was clicked - show on next app open (which is now)
        await prefs.remove(_snoozeUntilKey);
      }

      // Check if there are incomplete items from yesterday (pure check)
      final hasIncompleteItems = await hasPendingItemsFromYesterday(userId);

      if (!hasIncompleteItems) {
        // Clear reminder count if there is nothing to process
        await resetReminderCount();
        return false;
      }

      return true;
    } catch (e) {
      return false; // Don't show dialog on error
    }
  }

  /// Check if there are incomplete items from yesterday ONLY (not older items)
  static Future<bool> _hasIncompleteItemsFromYesterday(String userId) async {
    try {
      final yesterday = DateService.yesterdayStart;

      // Check for habit instances that belong to yesterday specifically
      // Only include habits where window has ended (windowEndDate <= yesterday)
      final habitQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('status', isEqualTo: 'pending')
          .where('windowEndDate', isLessThanOrEqualTo: yesterday)
          .limit(50); // Get more to filter client-side
      final habitSnapshot = await habitQuery.get();
      // Filter to ONLY yesterday's items where window has ended
      final yesterdayHabits = habitSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((item) {
        if (item.skippedAt != null) return false;
        // Ensure window has ended before including
        if (item.windowEndDate != null) {
          final windowEndDateOnly = DateTime(
            item.windowEndDate!.year,
            item.windowEndDate!.month,
            item.windowEndDate!.day,
          );
          // Window must have ended (is before or equal to yesterday)
          if (windowEndDateOnly.isAfter(yesterday)) {
            return false; // Window still active, exclude
          }
        }
        // Check belongsToDate
        if (item.belongsToDate != null) {
          final belongsToDateOnly = DateTime(
            item.belongsToDate!.year,
            item.belongsToDate!.month,
            item.belongsToDate!.day,
          );
          if (belongsToDateOnly.isAtSameMomentAs(yesterday)) {
            return true; // Belongs to yesterday and window has ended
          }
        }
        // Check windowEndDate - if it's yesterday, the habit window ended yesterday
        if (item.windowEndDate != null) {
          final windowEndDateOnly = DateTime(
            item.windowEndDate!.year,
            item.windowEndDate!.month,
            item.windowEndDate!.day,
          );
          if (windowEndDateOnly.isAtSameMomentAs(yesterday)) {
            return true; // This habit's window ended yesterday
          }
        }
        return false;
      });
      if (yesterdayHabits.isNotEmpty) {
        return true;
      }

      // Tasks are not checked - dialog only shows for habits
      // Tasks cannot be skipped via the dialog, so they shouldn't trigger it
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get incomplete items from yesterday ONLY (not older items)
  /// Optimized to run habit and task queries in parallel
  static Future<List<ActivityInstanceRecord>> getIncompleteItemsFromYesterday(
      String userId) async {
    try {
      final yesterday = DateService.yesterdayStart;
      final today = DateService.todayStart;
      final List<ActivityInstanceRecord> items = [];

      // Run habit and task queries in parallel for better performance
      final results = await Future.wait([
        _getHabitItemsFromYesterday(userId, yesterday, today),
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
      String userId, DateTime yesterday, DateTime today) async {
    try {
      // Only include habits where window has ended (windowEndDate <= yesterday)
      final habitQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('status', isEqualTo: 'pending')
          .where('windowEndDate', isLessThanOrEqualTo: yesterday)
          .orderBy('windowEndDate', descending: false);
      final habitSnapshot = await habitQuery.get();
      // Filter to ONLY yesterday's items where window has ended: belongsToDate is yesterday OR windowEndDate is yesterday
      final habitItems = habitSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((item) {
        if (item.status != 'pending' || item.skippedAt != null) {
          return false; // Exclude skipped/completed items
        }
        // Ensure window has ended before including
        if (item.windowEndDate != null) {
          final windowEndDateOnly = DateTime(
            item.windowEndDate!.year,
            item.windowEndDate!.month,
            item.windowEndDate!.day,
          );
          // Window must have ended (is before or equal to yesterday)
          if (windowEndDateOnly.isAfter(yesterday)) {
            return false; // Window still active, exclude
          }
        }
        // Check if this item belongs to yesterday
        if (item.belongsToDate != null) {
          final belongsToDateOnly = DateTime(
            item.belongsToDate!.year,
            item.belongsToDate!.month,
            item.belongsToDate!.day,
          );
          if (belongsToDateOnly.isAtSameMomentAs(yesterday)) {
            return true; // Belongs to yesterday and window has ended
          }
        }
        // Also check windowEndDate - if it's yesterday, the habit window ended yesterday
        if (item.windowEndDate != null) {
          final windowEndDateOnly = DateTime(
            item.windowEndDate!.year,
            item.windowEndDate!.month,
            item.windowEndDate!.day,
          );
          if (windowEndDateOnly.isAtSameMomentAs(yesterday)) {
            return true; // This habit's window ended yesterday
          }
        }
        return false; // Not from yesterday
      }).toList();
      return habitItems;
    } catch (e) {
      print(
          '❌ MISSING INDEX: getIncompleteItemsFromYesterday habitQuery needs Index 2');
      print(
          'Required Index: templateCategoryType (ASC) + status (ASC) + windowEndDate (ASC) + dueDate (ASC)');
      print('Collection: activity_instances');
      print('Full error: $e');
      if (e.toString().contains('index') || e.toString().contains('https://')) {
        print(
            '📋 Look for the Firestore index creation link in the error message above!');
        print('   Click the link to create the index automatically.');
      }
      // Return empty list on error, continue with tasks
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
          .where('dueDate', isLessThanOrEqualTo: today)
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
      print(
          '❌ MISSING INDEX: getIncompleteItemsFromYesterday taskQuery needs Index 2');
      print(
          'Required Index: templateCategoryType (ASC) + status (ASC) + windowEndDate (ASC) + dueDate (ASC)');
      print('Collection: activity_instances');
      print('Full error: $e');
      if (e.toString().contains('index') || e.toString().contains('https://')) {
        print(
            '📋 Look for the Firestore index creation link in the error message above!');
        print('   Click the link to create the index automatically.');
      }
      // Return empty list on error
      return [];
    }
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
    } catch (e) {
      // Error resetting dialog state
    }
  }

  /// Auto-skip all items that expired before yesterday (NEW: Optimized with batch writes)
  /// This ensures everything is brought up to date before showing yesterday's items
  /// Uses frequency-aware bulk skip to efficiently handle large gaps
  static Future<void> autoSkipExpiredItemsBeforeYesterday(String userId) async {
    try {
      final yesterday = DateService.yesterdayStart;
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
      final yesterday = DateService.yesterdayStart;

      await runInstanceMaintenanceForDayTransition(userId);

      // Persist scores for yesterday even if pending items exist
      await persistScoresForDate(userId: userId, targetDate: yesterday);

      // Ensure any missed days are created (safe no-op if already present)
      await persistScoresForMissedDaysIfNeeded(userId: userId);
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
      final now = DateTime.now();
      final todayOnly = DateTime(now.year, now.month, now.day);

      // Check if reminder count is for today
      final countDateString = prefs.getString(_reminderCountDateKey);
      if (countDateString != null) {
        final countDate = DateTime.parse(countDateString);
        final countDateOnly = DateTime(
          countDate.year,
          countDate.month,
          countDate.day,
        );
        // Use isAtSameMomentAs for precise comparison
        if (countDateOnly.isAtSameMomentAs(todayOnly)) {
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
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final currentCount = await getReminderCount();
      await prefs.setInt(_reminderCountKey, currentCount + 1);
      await prefs.setString(_reminderCountDateKey, todayOnly.toIso8601String());
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

  /// Instance handling for day transition (no scoring/persistence)
  static Future<void> runInstanceMaintenanceForDayTransition(
      String userId) async {
    final yesterday = DateService.yesterdayStart;
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
    if (overwriteExisting) {
      await recalculateDailyProgressRecordForDate(
        userId: userId,
        targetDate: targetDate,
        suppressToasts: suppressToasts,
      );
      return;
    }
    await createDailyProgressRecordForDate(
      userId: userId,
      targetDate: targetDate,
      suppressToasts: suppressToasts,
    );
  }

  /// Persist points/scores for missed days up to yesterday
  static Future<void> persistScoresForMissedDaysIfNeeded(
      {required String userId}) async {
    await createRecordsForMissedDays(userId: userId);
  }

  /// Recalculate and update daily progress record for a specific date
  /// This deletes the existing record (if any) and creates a new one with updated data
  /// Used when user completes items in morning catch-up dialog to ensure cumulative score is recalculated
  /// [suppressToasts] - If true, toasts will be stored and shown later via showPendingToasts()
  static Future<void> recalculateDailyProgressRecordForDate({
    required String userId,
    required DateTime targetDate,
    bool suppressToasts = false,
  }) async {
    try {
      final normalizedDate =
          DateTime(targetDate.year, targetDate.month, targetDate.day);

      // Delete existing record if it exists
      final existingQuery = DailyProgressRecord.collectionForUser(userId)
          .where('date', isEqualTo: normalizedDate);
      final existingSnapshot = await existingQuery.get();
      if (existingSnapshot.docs.isNotEmpty) {
        // Delete all existing records for this date (should only be one, but handle multiple)
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in existingSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // Now create the record with updated data
      await createDailyProgressRecordForDate(
        userId: userId,
        targetDate: targetDate,
        suppressToasts: suppressToasts,
      );
    } catch (e) {
      // Error recalculating record - log but don't throw
      print('Error recalculating daily progress record: $e');
    }
  }

  /// Create daily progress record for a specific date using DailyProgressCalculator
  /// This ensures records include full habitBreakdown/taskBreakdown with enhanced fields
  /// Works with instances regardless of dayState (pending/completed/skipped)
  ///
  /// [allInstances] - Optional: Pre-fetched habit instances to avoid redundant queries
  /// [allTaskInstances] - Optional: Pre-fetched task instances to avoid redundant queries
  /// [categories] - Optional: Pre-fetched categories to avoid redundant queries
  /// [suppressToasts] - If true, toasts will be stored and shown later via showPendingToasts()
  static Future<void> createDailyProgressRecordForDate({
    required String userId,
    required DateTime targetDate,
    List<ActivityInstanceRecord>? allInstances,
    List<ActivityInstanceRecord>? allTaskInstances,
    List<CategoryRecord>? categories,
    bool suppressToasts = false,
  }) async {
    final normalizedDate =
        DateTime(targetDate.year, targetDate.month, targetDate.day);

    // Check if record already exists (outside retry loop)
    final existingQuery = DailyProgressRecord.collectionForUser(userId)
        .where('date', isEqualTo: normalizedDate);
    final existingSnapshot = await existingQuery.get();
    if (existingSnapshot.docs.isNotEmpty) {
      return;
    }

    // Retry logic for record creation
    int retries = 3;
    while (retries > 0) {
      try {
        // Fetch instances only if not provided
        List<ActivityInstanceRecord> habitInstances;
        if (allInstances != null) {
          habitInstances = allInstances;
        } else {
          final allInstancesQuery =
              ActivityInstanceRecord.collectionForUser(userId)
                  .where('templateCategoryType', isEqualTo: 'habit');
          final allInstancesSnapshot = await allInstancesQuery.get();
          habitInstances = allInstancesSnapshot.docs
              .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
              .toList();
        }

        // Fetch task instances only if not provided
        List<ActivityInstanceRecord> taskInstances;
        if (allTaskInstances != null) {
          taskInstances = allTaskInstances;
        } else {
          final allTaskInstancesQuery =
              ActivityInstanceRecord.collectionForUser(userId)
                  .where('templateCategoryType', isEqualTo: 'task');
          final allTaskInstancesSnapshot = await allTaskInstancesQuery.get();
          taskInstances = allTaskInstancesSnapshot.docs
              .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
              .toList();
        }

        // Fetch categories only if not provided
        List<CategoryRecord> categoryList;
        if (categories != null) {
          categoryList = categories;
        } else {
          final categoriesQuery = CategoryRecord.collectionForUser(userId)
              .where('categoryType', isEqualTo: 'habit');
          final categoriesSnapshot = await categoriesQuery.get();
          categoryList = categoriesSnapshot.docs
              .map((doc) => CategoryRecord.fromSnapshot(doc))
              .toList();
        }

        // Use DailyProgressCalculator (same as DayEndProcessor)
        final calculationResult =
            await DailyProgressCalculator.calculateDailyProgress(
          userId: userId,
          targetDate: normalizedDate,
          allInstances: habitInstances,
          categories: categoryList,
          taskInstances: taskInstances,
        );

        final targetPoints = calculationResult['target'] as double;
        final earnedPoints = calculationResult['earned'] as double;
        final completionPercentage = calculationResult['percentage'] as double;
        final displayInstances =
            calculationResult['instances'] as List<ActivityInstanceRecord>;
        final displayTaskInstances =
            calculationResult['taskInstances'] as List<ActivityInstanceRecord>;
        final allForMath =
            calculationResult['allForMath'] as List<ActivityInstanceRecord>;
        final allTasksForMath = calculationResult['allTasksForMath']
            as List<ActivityInstanceRecord>;
        final taskTarget = calculationResult['taskTarget'] as double;
        final taskEarned = calculationResult['taskEarned'] as double;
        final habitBreakdown = calculationResult['habitBreakdown']
                as List<Map<String, dynamic>>? ??
            [];
        final taskBreakdown =
            calculationResult['taskBreakdown'] as List<Map<String, dynamic>>? ??
                [];

        // Handle empty case - create record with zero values
        if (displayInstances.isEmpty && displayTaskInstances.isEmpty) {
          final emptyProgressData = createDailyProgressRecordData(
            userId: userId,
            date: normalizedDate,
            targetPoints: 0.0,
            earnedPoints: 0.0,
            completionPercentage: 0.0,
            totalHabits: 0,
            completedHabits: 0,
            partialHabits: 0,
            skippedHabits: 0,
            totalTasks: 0,
            completedTasks: 0,
            partialTasks: 0,
            skippedTasks: 0,
            taskTargetPoints: 0.0,
            taskEarnedPoints: 0.0,
            categoryBreakdown: {},
            habitBreakdown: [],
            taskBreakdown: [],
            createdAt: DateTime.now(),
          );
          await DailyProgressRecord.collectionForUser(userId)
              .add(emptyProgressData);
          return;
        }

        // Count habit statistics using allForMath and completion-on-date rule
        int totalHabits = allForMath.length;
        final completedOnDate = allForMath.where((i) {
          if (i.status != 'completed' || i.completedAt == null) return false;
          final completedDate = DateTime(
              i.completedAt!.year, i.completedAt!.month, i.completedAt!.day);
          return completedDate.isAtSameMomentAs(normalizedDate);
        }).toList();
        int completedHabits = completedOnDate.length;
        int partialHabits = allForMath
            .where((i) =>
                i.status != 'completed' &&
                (i.currentValue is num ? (i.currentValue as num) > 0 : false))
            .length;
        int skippedHabits =
            allForMath.where((i) => i.status == 'skipped').length;

        // Count task statistics using allTasksForMath and completion-on-date rule
        int totalTasks = allTasksForMath.length;
        final completedTasksOnDate = allTasksForMath.where((task) {
          if (task.status != 'completed' || task.completedAt == null)
            return false;
          final completedDate = DateTime(task.completedAt!.year,
              task.completedAt!.month, task.completedAt!.day);
          return completedDate.isAtSameMomentAs(normalizedDate);
        }).toList();
        int completedTasks = completedTasksOnDate.length;
        int partialTasks = allTasksForMath
            .where((task) =>
                task.status != 'completed' &&
                (task.currentValue is num
                    ? (task.currentValue as num) > 0
                    : false))
            .length;
        int skippedTasks =
            allTasksForMath.where((task) => task.status == 'skipped').length;

        // Create category breakdown
        final categoryBreakdown = <String, Map<String, dynamic>>{};
        for (final category in categoryList) {
          final categoryAll = allForMath
              .where((i) => i.templateCategoryId == category.reference.id)
              .toList();
          if (categoryAll.isNotEmpty) {
            final categoryCompleted = completedOnDate
                .where((i) => i.templateCategoryId == category.reference.id)
                .toList();
            final categoryTarget =
                PointsService.calculateTotalDailyTarget(categoryAll);
            final categoryEarned =
                await PointsService.calculateTotalPointsEarned(
                    categoryCompleted, userId);
            categoryBreakdown[category.reference.id] = {
              'target': categoryTarget,
              'earned': categoryEarned,
              'completed': categoryCompleted.length,
              'total': categoryAll.length,
            };
          }
        }

        // Calculate category neglect penalty
        final categoryNeglectPenalty =
            CumulativeScoreService.calculateCategoryNeglectPenalty(
          categoryList,
          allForMath,
          normalizedDate,
        );

        // Calculate cumulative score
        Map<String, dynamic> cumulativeScoreData = {};
        try {
          cumulativeScoreData =
              await CumulativeScoreService.updateCumulativeScore(
            userId,
            completionPercentage,
            normalizedDate,
            earnedPoints,
            categoryNeglectPenalty: categoryNeglectPenalty,
          );

          // Show bonus notifications or store them for later
          if (suppressToasts) {
            // Store toast data to show after catch-up dialog closes
            _pendingToastData = cumulativeScoreData;
          } else {
            // Show toasts immediately
            BonusNotificationFormatter.showBonusNotifications(
                cumulativeScoreData);

            // Show milestone achievements
            final newMilestones =
                cumulativeScoreData['newMilestones'] as List<dynamic>? ?? [];
            if (newMilestones.isNotEmpty) {
              final milestoneValues =
                  newMilestones.map((m) => m as int).toList();
              MilestoneToastService.showMultipleMilestones(milestoneValues);
            }
          }
        } catch (e) {
          // Error calculating cumulative score
          // Continue without cumulative score if calculation fails
        }

        // Create the daily progress record with full breakdown
        final progressData = createDailyProgressRecordData(
          userId: userId,
          date: normalizedDate,
          targetPoints: targetPoints,
          earnedPoints: earnedPoints,
          completionPercentage: completionPercentage,
          totalHabits: totalHabits,
          completedHabits: completedHabits,
          partialHabits: partialHabits,
          skippedHabits: skippedHabits,
          totalTasks: totalTasks,
          completedTasks: completedTasks,
          partialTasks: partialTasks,
          skippedTasks: skippedTasks,
          taskTargetPoints: taskTarget,
          taskEarnedPoints: taskEarned,
          categoryBreakdown: categoryBreakdown,
          habitBreakdown: habitBreakdown,
          taskBreakdown: taskBreakdown,
          cumulativeScoreSnapshot:
              cumulativeScoreData['cumulativeScore'] ?? 0.0,
          dailyScoreGain: cumulativeScoreData['dailyGain'] ?? 0.0,
          createdAt: DateTime.now(),
        );
        await DailyProgressRecord.collectionForUser(userId).add(progressData);
        return; // Success
      } catch (e) {
        retries--;
        if (retries == 0) {
          // Failed to create DailyProgressRecord after retries
          // Create minimal record as fallback
          try {
            final minimalData = createDailyProgressRecordData(
              userId: userId,
              date: normalizedDate,
              targetPoints: 0.0,
              earnedPoints: 0.0,
              completionPercentage: 0.0,
              totalHabits: 0,
              completedHabits: 0,
              partialHabits: 0,
              skippedHabits: 0,
              totalTasks: 0,
              completedTasks: 0,
              partialTasks: 0,
              skippedTasks: 0,
              taskTargetPoints: 0.0,
              taskEarnedPoints: 0.0,
              categoryBreakdown: {},
              habitBreakdown: [],
              taskBreakdown: [],
              createdAt: DateTime.now(),
            );
            await DailyProgressRecord.collectionForUser(userId)
                .add(minimalData);
          } catch (fallbackError) {
            // Fallback record creation also failed
            rethrow;
          }
        } else {
          // Wait before retrying with exponential backoff
          await Future.delayed(Duration(milliseconds: 500 * (3 - retries)));
        }
      }
    }
  }

  /// Create records for all missed days between last record and yesterday
  /// Ensures continuity in tracking even when user hasn't opened app for days
  static Future<void> createRecordsForMissedDays({
    required String userId,
  }) async {
    try {
      final yesterday = DateService.yesterdayStart;

      // Find the last DailyProgressRecord date
      final lastRecordQuery = DailyProgressRecord.collectionForUser(userId)
          .orderBy('date', descending: true)
          .limit(1);
      final lastRecordSnapshot = await lastRecordQuery.get();

      DateTime? lastRecordDate;
      if (lastRecordSnapshot.docs.isNotEmpty) {
        final lastRecord =
            DailyProgressRecord.fromSnapshot(lastRecordSnapshot.docs.first);
        if (lastRecord.date != null) {
          lastRecordDate = DateTime(
            lastRecord.date!.year,
            lastRecord.date!.month,
            lastRecord.date!.day,
          );
        }
      }

      // If no last record, start from reasonable limit but warn
      if (lastRecordDate == null) {
        final limitDays = 90; // Increased from 30
        lastRecordDate = yesterday.subtract(Duration(days: limitDays));
      }

      // Check if gap is very large
      final daysSinceLastRecord = yesterday.difference(lastRecordDate).inDays;
      if (daysSinceLastRecord > 90) {
        // Large gap detected, creating records for recent 90 days only
        // Cap at 90 days
        lastRecordDate = yesterday.subtract(const Duration(days: 90));
      }

      // Don't create records if last record is yesterday or later
      if (!lastRecordDate.isBefore(yesterday)) {
        return;
      }

      // Build list of all missed dates
      final missedDates = <DateTime>[];
      DateTime currentDate = lastRecordDate.add(const Duration(days: 1));
      while (currentDate.isBefore(yesterday) ||
          currentDate.isAtSameMomentAs(yesterday)) {
        missedDates.add(currentDate);
        currentDate = currentDate.add(const Duration(days: 1));
      }

      if (missedDates.isEmpty) {
        return;
      }

      // Pre-fetch instances and categories once to avoid redundant queries
      final allInstancesQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit');
      final allTaskInstancesQuery =
          ActivityInstanceRecord.collectionForUser(userId)
              .where('templateCategoryType', isEqualTo: 'task');
      final categoriesQuery = CategoryRecord.collectionForUser(userId)
          .where('categoryType', isEqualTo: 'habit');

      // Fetch all data in parallel
      final results = await Future.wait([
        allInstancesQuery.get(),
        allTaskInstancesQuery.get(),
        categoriesQuery.get(),
      ]);

      final allInstances = results[0]
          .docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      final allTaskInstances = results[1]
          .docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      final categories = results[2]
          .docs
          .map((doc) => CategoryRecord.fromSnapshot(doc))
          .toList();

      // Create records for missed days in parallel (with concurrency limit)
      const maxConcurrency = 5; // Process up to 5 dates in parallel
      int recordsCreated = 0;

      for (int i = 0; i < missedDates.length; i += maxConcurrency) {
        final batch = missedDates.skip(i).take(maxConcurrency).toList();
        final batchResults = await Future.wait(
          batch.map((date) async {
            try {
              await createDailyProgressRecordForDate(
                userId: userId,
                targetDate: date,
                allInstances: allInstances,
                allTaskInstances: allTaskInstances,
                categories: categories,
              );
              return true;
            } catch (e) {
              // Error creating record for date
              return false;
            }
          }),
        );
        recordsCreated += batchResults.where((r) => r).length;
      }

      if (recordsCreated > 0) {}
    } catch (e) {
      // Error creating records for missed days
      // Don't rethrow - this is a background operation
    }
  }
}
