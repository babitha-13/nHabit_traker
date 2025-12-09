import 'package:shared_preferences/shared_preferences.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/historical_edit_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';

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

      // Check if it's after midnight
      if (now.hour < 1) {
        return false; // Too early, not really "morning" yet
      }

      // First, auto-skip all items expired before yesterday to bring everything up to date
      await autoSkipExpiredItemsBeforeYesterday(userId);

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
      return hasIncompleteItems;
    } catch (e) {
      print('Error checking if catch-up dialog should show: $e');
      return false;
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

      // Recalculate progress for all affected dates
      for (final date in affectedDates) {
        try {
          await HistoricalEditService.recalculateDailyProgress(
            userId: userId,
            date: date,
          );
        } catch (e) {
          print('Error recalculating progress for $date: $e');
        }
      }

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
  static Future<void> _ensurePendingInstancesExist(String userId) async {
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
                await ActivityInstanceService.skipInstance(
                  instanceId: mostRecentInstance.reference.id,
                  skippedAt: mostRecentInstance.windowEndDate,
                );
                instancesGenerated++;
                print(
                    'MorningCatchUpService: Generated next instance for habit ${habit.name}');
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
        // Recalculate yesterday's progress
        await HistoricalEditService.recalculateDailyProgress(
          userId: userId,
          date: yesterday,
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
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);

      // Check if reminder count is for today
      final countDateString = prefs.getString(_reminderCountDateKey);
      if (countDateString != null) {
        final countDate = DateTime.parse(countDateString);
        final countDateOnly = DateTime(
          countDate.year,
          countDate.month,
          countDate.day,
        );
        if (countDateOnly.isAtSameMomentAs(todayOnly)) {
          // Return count for today
          return prefs.getInt(_reminderCountKey) ?? 0;
        } else {
          // Count is for a different day, reset it
          await resetReminderCount();
          return 0;
        }
      }
      return 0;
    } catch (e) {
      print('Error getting reminder count: $e');
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
}
