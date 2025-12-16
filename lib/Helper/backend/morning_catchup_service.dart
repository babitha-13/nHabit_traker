import 'package:shared_preferences/shared_preferences.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/historical_edit_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/daily_progress_calculator.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/cumulative_score_service.dart';
import 'package:habit_tracker/Helper/backend/points_service.dart';

/// Service for managing morning catch-up dialog
/// Shows dialog on first app open after midnight for incomplete items from yesterday
class MorningCatchUpService {
  static const String _shownDateKey = 'morning_catchup_shown_date';
  static const String _snoozeUntilKey = 'morning_catchup_snooze_until';
  static const String _reminderCountKey = 'morning_catchup_reminder_count';
  static const String _reminderCountDateKey =
      'morning_catchup_reminder_count_date';
  static const int maxReminderCount = 3;

  /// Check if the catch-up dialog should be shown
  static Future<bool> shouldShowDialog(String userId) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Check if it's after midnight - but allow dialog if there are incomplete items
      // This handles cases where user opens app in first hour but has items to handle
      if (now.hour == 0) {
        // Still in first hour - check if there are incomplete items
        final hasIncompleteItems = await _hasIncompleteItemsFromYesterday(userId);
        if (!hasIncompleteItems) {
          return false; // No items, don't show
        }
        // Has items, show dialog even in first hour
      } else if (now.hour < 1) {
        // This shouldn't happen, but handle it gracefully
        return false;
      }

      // First, auto-skip all items expired before yesterday to bring everything up to date
      await autoSkipExpiredItemsBeforeYesterday(userId);

      // Ensure all active habits have pending instances (fixes stuck instances from the past)
      // This must happen BEFORE checking for incomplete items, so missing instances are generated
      await ensurePendingInstancesExist(userId);

      final prefs = await SharedPreferences.getInstance();

      // Check if dialog was already shown today
      final shownDateString = prefs.getString(_shownDateKey);
      final snoozeUntilString = prefs.getString(_snoozeUntilKey);

      if (shownDateString != null) {
        final shownDate = DateTime.parse(shownDateString);
        final shownDateOnly =
            DateTime(shownDate.year, shownDate.month, shownDate.day);
        if (shownDateOnly.isAtSameMomentAs(today)) {
          // Dialog was shown today
          if (snoozeUntilString != null) {
            // User clicked "remind me later" - don't show again today
            return false;
          }
          // Dialog was shown and dismissed/completed - don't show again today
          return false;
        }
      }

      // If snooze key exists and we're on a new day, clear it and show dialog
      if (snoozeUntilString != null) {
        // "Remind me later" was clicked - show on next app open (which is now)
        await prefs.remove(_snoozeUntilKey);
      }

      // Check reminder count - if >= 3, force skip all remaining items
      final reminderCount = await getReminderCount();
      if (reminderCount >= maxReminderCount) {
        // Force skip all remaining items from yesterday
        await _forceSkipAllRemainingItems(userId);
        // Reset reminder count after forcing skip
        await resetReminderCount();
        return false; // Don't show dialog after forcing skip
      }

      // Check if there are incomplete items from yesterday
      final hasIncompleteItems = await _hasIncompleteItemsFromYesterday(userId);
      
      // Ensure record exists even if dialog will be shown
      if (hasIncompleteItems) {
        // Create record proactively when dialog will be shown
        try {
          await createDailyProgressRecordForDate(
            userId: userId,
            targetDate: DateService.yesterdayStart,
          );
        } catch (e) {
          print('Error creating record in shouldShowDialog: $e');
          // Continue even if record creation fails
        }
      }
      
      return hasIncompleteItems;
    } catch (e, stackTrace) {
      print('Error checking if catch-up dialog should show: $e');
      print('Stack trace: $stackTrace');
      // Attempt to create record anyway as fallback
      try {
        await createDailyProgressRecordForDate(
          userId: userId,
          targetDate: DateService.yesterdayStart,
        );
      } catch (recordError) {
        print('Failed to create record in error handler: $recordError');
      }
      return false; // Don't show dialog on error
    }
  }

  /// Check if there are incomplete items from yesterday ONLY (not older items)
  static Future<bool> _hasIncompleteItemsFromYesterday(String userId) async {
    try {
      final yesterday = DateService.yesterdayStart;
      final today = DateService.todayStart;

      // Check for habit instances that belong to yesterday specifically
      final habitQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('status', isEqualTo: 'pending')
          .where('windowEndDate', isLessThan: today)
          .limit(50); // Get more to filter client-side
      final habitSnapshot = await habitQuery.get();
      // Filter to ONLY yesterday's items
      final yesterdayHabits = habitSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((item) {
        if (item.skippedAt != null) return false;
        // Check belongsToDate
        if (item.belongsToDate != null) {
          final belongsToDateOnly = DateTime(
            item.belongsToDate!.year,
            item.belongsToDate!.month,
            item.belongsToDate!.day,
          );
          if (belongsToDateOnly.isAtSameMomentAs(yesterday)) {
            return true;
          }
        }
        // Check windowEndDate
        if (item.windowEndDate != null) {
          final windowEndDateOnly = DateTime(
            item.windowEndDate!.year,
            item.windowEndDate!.month,
            item.windowEndDate!.day,
          );
          if (windowEndDateOnly.isAtSameMomentAs(yesterday)) {
            return true;
          }
        }
        return false;
      });
      if (yesterdayHabits.isNotEmpty) {
        return true;
      }

      // Check for task instances due specifically on yesterday (not older)
      final taskQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'task')
          .where('status', isEqualTo: 'pending')
          .where('dueDate', isGreaterThanOrEqualTo: yesterday)
          .where('dueDate', isLessThan: today)
          .limit(50); // Get more to filter client-side
      final taskSnapshot = await taskQuery.get();
      // Filter to ONLY yesterday's tasks
      final yesterdayTasks = taskSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((item) {
        if (item.skippedAt != null) return false;
        if (item.dueDate != null) {
          final dueDateOnly = DateTime(
            item.dueDate!.year,
            item.dueDate!.month,
            item.dueDate!.day,
          );
          return dueDateOnly.isAtSameMomentAs(yesterday);
        }
        return false;
      });
      if (yesterdayTasks.isNotEmpty) {
        return true;
      }

      return false;
    } catch (e) {
      print('Error checking incomplete items: $e');
      return false;
    }
  }

  /// Get incomplete items from yesterday ONLY (not older items)
  static Future<List<ActivityInstanceRecord>> getIncompleteItemsFromYesterday(
      String userId) async {
    try {
      final yesterday = DateService.yesterdayStart;
      final today = DateService.todayStart;
      final List<ActivityInstanceRecord> items = [];

      // Get habit instances that belong to yesterday specifically
      // For habits, check if belongsToDate is yesterday OR windowEndDate is yesterday
      final habitQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('status', isEqualTo: 'pending')
          .where('windowEndDate', isLessThan: today)
          .orderBy('windowEndDate', descending: false);
      final habitSnapshot = await habitQuery.get();
      // Filter to ONLY yesterday's items: belongsToDate is yesterday OR windowEndDate is yesterday
      final habitItems = habitSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((item) {
        if (item.status != 'pending' || item.skippedAt != null) {
          return false; // Exclude skipped/completed items
        }
        // Check if this item belongs to yesterday
        if (item.belongsToDate != null) {
          final belongsToDateOnly = DateTime(
            item.belongsToDate!.year,
            item.belongsToDate!.month,
            item.belongsToDate!.day,
          );
          if (belongsToDateOnly.isAtSameMomentAs(yesterday)) {
            return true; // This habit belongs to yesterday
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
      items.addAll(habitItems);

      // Get task instances that are due specifically on yesterday (not older)
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
      items.addAll(taskItems);

      return items;
    } catch (e) {
      print('Error getting incomplete items: $e');
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
      print('Error marking dialog as shown: $e');
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
      print('Error snoozing dialog: $e');
    }
  }

  /// Clear snooze (when dialog is shown after snooze expires)
  static Future<void> clearSnooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_snoozeUntilKey);
    } catch (e) {
      print('Error clearing snooze: $e');
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
      print('Morning catch-up dialog state reset');
    } catch (e) {
      print('Error resetting dialog state: $e');
    }
  }

  /// Auto-skip all items that expired before yesterday (NEW: Optimized with batch writes)
  /// This ensures everything is brought up to date before showing yesterday's items
  /// Uses frequency-aware bulk skip to efficiently handle large gaps
  static Future<void> autoSkipExpiredItemsBeforeYesterday(String userId) async {
    try {
      final yesterday = DateService.yesterdayStart;
      final Set<DateTime> affectedDates = {};
      int totalSkipped = 0;
      int habitSkipped = 0;

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
            print(
                'MorningCatchUpService: Processing expired habit ${instance.templateName} (windowEndDate: $windowEndDateOnly, yesterday: $yesterday)');

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
                habitSkipped++;
                totalSkipped++;
                print(
                    'MorningCatchUpService: Created yesterday instance ${yesterdayInstanceRef.id} for ${instance.templateName}');
              }
            } catch (e) {
              print('Error processing habit ${instance.templateName}: $e');
              // Fallback: skip normally if bulk skip fails
              await ActivityInstanceService.skipInstance(
                instanceId: instance.reference.id,
                skippedAt: windowEndDateOnly,
                skipAutoGeneration: true,
                userId: userId,
              );
              habitSkipped++;
              totalSkipped++;
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
        const maxConcurrency = 5; // Process up to 5 dates in parallel
        final datesList = affectedDates.toList();
        
        // Process dates in batches
        for (int i = 0; i < datesList.length; i += maxConcurrency) {
          final batch = datesList.skip(i).take(maxConcurrency).toList();
          await Future.wait(
            batch.map((date) async {
              try {
                await HistoricalEditService.recalculateDailyProgress(
                  userId: userId,
                  date: date,
                );
              } catch (e) {
                print('Error recalculating progress for $date: $e');
              }
            }),
          );
        }
      }

      // Create records for all missed days between last record and yesterday
      // This ensures continuity even when user hasn't opened app for days
      await createRecordsForMissedDays(userId: userId);

      // After skipping expired instances with batch writes, yesterday's instances remain pending
      // for manual user confirmation via the morning catch-up dialog

      if (totalSkipped > 0) {
        print(
            'Efficiently processed $totalSkipped expired habits before yesterday ($habitSkipped habits) using batch writes');
      }
    } catch (e) {
      print('Error auto-skipping expired items: $e');
    }
  }

  /// Ensure all active habits have at least one pending instance
  /// This handles cases where instance generation failed or instances are missing
  /// Also fixes stuck instances where completed instances from the past don't have subsequent instances
  static Future<void> ensurePendingInstancesExist(String userId) async {
    try {
      // Get all active habit templates
      final habitsQuery = ActivityRecord.collectionForUser(userId)
          .where('categoryType', isEqualTo: 'habit')
          .where('isActive', isEqualTo: true);
      final habitsSnapshot = await habitsQuery.get();
      final activeHabits = habitsSnapshot.docs
          .map((doc) => ActivityRecord.fromSnapshot(doc))
          .toList();

      int instancesGenerated = 0;
      for (final habit in activeHabits) {
        // Check if there's at least one pending instance for this habit
        final pendingQuery = ActivityInstanceRecord.collectionForUser(userId)
            .where('templateId', isEqualTo: habit.reference.id)
            .where('status', isEqualTo: 'pending')
            .limit(1);
        final pendingSnapshot = await pendingQuery.get();

        if (pendingSnapshot.docs.isEmpty) {
          // No pending instance found - need to generate one
          print(
              'MorningCatchUpService: No pending instance found for habit ${habit.name}, attempting to generate one');

          // Find the most recent instance (completed or skipped) to generate from
          final allInstancesQuery =
              ActivityInstanceRecord.collectionForUser(userId)
                  .where('templateId', isEqualTo: habit.reference.id);
          final allInstancesSnapshot = await allInstancesQuery.get();
          final allInstances = allInstancesSnapshot.docs
              .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
              .toList();

          if (allInstances.isNotEmpty) {
            // Sort by windowEndDate descending to get the most recent
            allInstances.sort((a, b) {
              if (a.windowEndDate == null && b.windowEndDate == null) return 0;
              if (a.windowEndDate == null) return 1;
              if (b.windowEndDate == null) return -1;
              return b.windowEndDate!.compareTo(a.windowEndDate!);
            });
            final mostRecentInstance = allInstances.first;

            // Only generate if the most recent instance has a windowEndDate
            if (mostRecentInstance.windowEndDate != null) {
              try {
                final windowEndDate = mostRecentInstance.windowEndDate!;
                final windowEndDateOnly = DateTime(
                  windowEndDate.year,
                  windowEndDate.month,
                  windowEndDate.day,
                );
                final yesterday = DateService.yesterdayStart;
                
                // If the window ended before yesterday, use bulk skip to fill the gap
                if (windowEndDateOnly.isBefore(yesterday)) {
                  // Get template for bulk skip
                  final templateRef = ActivityRecord.collectionForUser(userId)
                      .doc(habit.reference.id);
                  final template = await ActivityRecord.getDocumentOnce(templateRef);
                  
                  // Use bulk skip to efficiently fill gap up to yesterday
                  final yesterdayInstanceRef = await ActivityInstanceService
                      .bulkSkipExpiredInstancesWithBatches(
                    oldestInstance: mostRecentInstance,
                    template: template,
                    userId: userId,
                  );
                  if (yesterdayInstanceRef != null) {
                    instancesGenerated++;
                    print(
                        'MorningCatchUpService: Filled gap and generated instances up to yesterday for habit ${habit.name}');
                  }
                } else {
                  // Window ended recently, just generate next instance normally
                  await ActivityInstanceService.skipInstance(
                    instanceId: mostRecentInstance.reference.id,
                    skippedAt: windowEndDate,
                  );
                  instancesGenerated++;
                  print(
                      'MorningCatchUpService: Generated next instance for habit ${habit.name}');
                }
              } catch (e) {
                print(
                    'MorningCatchUpService: Error generating instance for habit ${habit.name}: $e');
              }
            } else {
              // No windowEndDate - create initial instance
              try {
                await ActivityInstanceService.createActivityInstance(
                  templateId: habit.reference.id,
                  template: habit,
                  userId: userId,
                );
                instancesGenerated++;
                print(
                    'MorningCatchUpService: Created initial instance for habit ${habit.name}');
              } catch (e) {
                print(
                    'MorningCatchUpService: Error creating initial instance for habit ${habit.name}: $e');
              }
            }
          } else {
            // No instances at all - create initial instance
            try {
              await ActivityInstanceService.createActivityInstance(
                templateId: habit.reference.id,
                template: habit,
                userId: userId,
              );
              instancesGenerated++;
              print(
                  'MorningCatchUpService: Created initial instance for habit ${habit.name} (no existing instances)');
            } catch (e) {
              print(
                  'MorningCatchUpService: Error creating initial instance for habit ${habit.name}: $e');
            }
          }
        }
      }

      if (instancesGenerated > 0) {
        print(
            'MorningCatchUpService: Generated $instancesGenerated missing instances for active habits');
      }
    } catch (e) {
      print(
          'MorningCatchUpService: Error ensuring pending instances exist: $e');
    }
  }

  /// Force skip all remaining items from yesterday (when reminder count >= 3)
  static Future<void> _forceSkipAllRemainingItems(String userId) async {
    try {
      final yesterday = DateService.yesterdayStart;
      final yesterdayEnd =
          DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
      final items = await getIncompleteItemsFromYesterday(userId);

      for (final item in items) {
        await ActivityInstanceService.skipInstance(
          instanceId: item.reference.id,
          skippedAt: yesterdayEnd,
        );
      }

      if (items.isNotEmpty) {
        // Wait a moment to ensure all database updates are committed
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Create daily progress record for yesterday using new method with full breakdown
        await createDailyProgressRecordForDate(
          userId: userId,
          targetDate: yesterday,
        );
        print(
            'Force skipped ${items.length} items after max reminders reached');
      }
    } catch (e) {
      print('Error force skipping remaining items: $e');
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
      print('Error getting reminder count: $e');
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
      print('Error incrementing reminder count: $e');
    }
  }

  /// Reset reminder count (when items are skipped or completed)
  static Future<void> resetReminderCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_reminderCountKey);
      await prefs.remove(_reminderCountDateKey);
    } catch (e) {
      print('Error resetting reminder count: $e');
    }
  }

  /// Create daily progress record for a specific date using DailyProgressCalculator
  /// This ensures records include full habitBreakdown/taskBreakdown with enhanced fields
  /// Works with instances regardless of dayState (pending/completed/skipped)
  /// 
  /// [allInstances] - Optional: Pre-fetched habit instances to avoid redundant queries
  /// [allTaskInstances] - Optional: Pre-fetched task instances to avoid redundant queries
  /// [categories] - Optional: Pre-fetched categories to avoid redundant queries
  static Future<void> createDailyProgressRecordForDate({
    required String userId,
    required DateTime targetDate,
    List<ActivityInstanceRecord>? allInstances,
    List<ActivityInstanceRecord>? allTaskInstances,
    List<CategoryRecord>? categories,
  }) async {
    final normalizedDate =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    
    // Check if record already exists (outside retry loop)
    final existingQuery = DailyProgressRecord.collectionForUser(userId)
        .where('date', isEqualTo: normalizedDate);
    final existingSnapshot = await existingQuery.get();
    if (existingSnapshot.docs.isNotEmpty) {
      print('DailyProgressRecord already exists for $normalizedDate');
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
        final allInstancesQuery = ActivityInstanceRecord.collectionForUser(userId)
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
      final allTasksForMath =
          calculationResult['allTasksForMath'] as List<ActivityInstanceRecord>;
      final taskTarget = calculationResult['taskTarget'] as double;
      final taskEarned = calculationResult['taskEarned'] as double;
      final habitBreakdown =
          calculationResult['habitBreakdown'] as List<Map<String, dynamic>>? ??
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
        print('Created empty DailyProgressRecord for $normalizedDate');
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
      int skippedHabits = allForMath.where((i) => i.status == 'skipped').length;

      // Count task statistics using allTasksForMath and completion-on-date rule
      int totalTasks = allTasksForMath.length;
      final completedTasksOnDate = allTasksForMath.where((task) {
        if (task.status != 'completed' || task.completedAt == null) return false;
        final completedDate = DateTime(task.completedAt!.year,
            task.completedAt!.month, task.completedAt!.day);
        return completedDate.isAtSameMomentAs(normalizedDate);
      }).toList();
      int completedTasks = completedTasksOnDate.length;
      int partialTasks = allTasksForMath
          .where((task) =>
              task.status != 'completed' &&
              (task.currentValue is num ? (task.currentValue as num) > 0 : false))
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
              PointsService.calculateTotalDailyTarget(categoryAll, [category]);
          final categoryEarned = PointsService.calculateTotalPointsEarned(
              categoryCompleted, [category]);
          categoryBreakdown[category.reference.id] = {
            'target': categoryTarget,
            'earned': categoryEarned,
            'completed': categoryCompleted.length,
            'total': categoryAll.length,
          };
        }
      }

      // Calculate cumulative score
      Map<String, dynamic> cumulativeScoreData = {};
      try {
        cumulativeScoreData = await CumulativeScoreService.updateCumulativeScore(
          userId,
          completionPercentage,
          normalizedDate,
        );
      } catch (e) {
        print('Error calculating cumulative score: $e');
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
        cumulativeScoreSnapshot: cumulativeScoreData['cumulativeScore'] ?? 0.0,
        dailyScoreGain: cumulativeScoreData['dailyGain'] ?? 0.0,
        createdAt: DateTime.now(),
      );
        await DailyProgressRecord.collectionForUser(userId).add(progressData);
        print('Created DailyProgressRecord for $normalizedDate with ${habitBreakdown.length} habits');
        return; // Success
      } catch (e) {
        retries--;
        if (retries == 0) {
          print('Failed to create DailyProgressRecord after retries: $e');
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
            await DailyProgressRecord.collectionForUser(userId).add(minimalData);
            print('Created minimal DailyProgressRecord as fallback for $normalizedDate');
          } catch (fallbackError) {
            print('Fallback record creation also failed: $fallbackError');
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
        final lastRecord = DailyProgressRecord.fromSnapshot(lastRecordSnapshot.docs.first);
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
        print('No previous record found, creating records for last $limitDays days');
      }

      // Check if gap is very large
      final daysSinceLastRecord = yesterday.difference(lastRecordDate).inDays;
      if (daysSinceLastRecord > 90) {
        print('Warning: Large gap detected ($daysSinceLastRecord days). Creating records for recent 90 days only.');
        // Cap at 90 days
        lastRecordDate = yesterday.subtract(const Duration(days: 90));
      }

      // Don't create records if last record is yesterday or later
      if (!lastRecordDate.isBefore(yesterday)) {
        print('No missed days to create records for');
        return;
      }

      // Build list of all missed dates
      final missedDates = <DateTime>[];
      DateTime currentDate = lastRecordDate.add(const Duration(days: 1));
      while (currentDate.isBefore(yesterday) || currentDate.isAtSameMomentAs(yesterday)) {
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

      final allInstances = results[0].docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      final allTaskInstances = results[1].docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      final categories = results[2].docs
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
              print('Error creating record for $date: $e');
              return false;
            }
          }),
        );
        recordsCreated += batchResults.where((r) => r).length;
      }

      if (recordsCreated > 0) {
        print('Created $recordsCreated DailyProgressRecords for missed days');
      }
    } catch (e) {
      print('Error creating records for missed days: $e');
      // Don't rethrow - this is a background operation
    }
  }
}
