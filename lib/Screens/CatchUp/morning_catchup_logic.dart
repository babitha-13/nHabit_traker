import 'package:flutter/material.dart';
import 'package:habit_tracker/Screens/CatchUp/morning_catchup_service.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';

/// Controller class for managing morning catch-up dialog business logic
/// Separates business logic from UI concerns
class MorningCatchUpDialogLogic {
  // State
  bool isLoading = true;
  bool isProcessing = false;
  List<ActivityInstanceRecord> items = [];
  final Set<String> processedItemIds = {};
  final Set<String> optimisticProcessingIds = {};
  final Map<String, ActivityInstanceRecord> optimisticSnapshots = {};
  int reminderCount = 0;
  String processingStatus = '';
  int processedCount = 0;
  int totalToProcess = 0;

  /// Initialize the dialog logic
  Future<void> initialize() async {
    await loadItems();
    await loadReminderCount();
    // Mark as shown immediately to prevent re-showing
    MorningCatchUpService.markDialogAsShown();
    await ensureRecordCreated();
    // Ensure instances exist when dialog opens (handles edge cases)
    await ensureInstancesExist();
  }

  /// Ensure instances exist for pending items
  Future<void> ensureInstancesExist() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      await MorningCatchUpService.ensurePendingInstancesExist(userId);
      // Reload items after ensuring instances exist
      await loadItems();
    } catch (e) {
      print('Error ensuring instances exist in dialog: $e');
    }
  }

  /// Ensure instances exist in background (after dialog closes)
  /// Doesn't reload items since dialog is already closed
  Future<void> ensureInstancesExistInBackground() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      await MorningCatchUpService.ensurePendingInstancesExist(userId);
    } catch (e) {
      print('Error ensuring instances exist in background: $e');
      // Silent error - don't block user
    }
  }

  /// Ensure daily progress record is created
  Future<void> ensureRecordCreated() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      final yesterday = DateService.yesterdayStart;
      // Check if record exists, create if not
      await MorningCatchUpService.createDailyProgressRecordForDate(
        userId: userId,
        targetDate: yesterday,
      );
    } catch (e) {
      print('Error ensuring record creation: $e');
      // Don't block dialog if record creation fails
    }
  }

  /// Load reminder count
  Future<void> loadReminderCount() async {
    reminderCount = await MorningCatchUpService.getReminderCount();
  }

  /// Load incomplete items from yesterday
  Future<void> loadItems() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      items =
          await MorningCatchUpService.getIncompleteItemsFromYesterday(userId);
      isLoading = false;
    } catch (e) {
      isLoading = false;
      rethrow; // Let UI handle error display
    }
  }

  /// Apply optimistic UI update - removes item from list immediately
  void applyOptimisticState(ActivityInstanceRecord instance) {
    // Save snapshot for potential rollback
    optimisticSnapshots[instance.reference.id] = instance;

    optimisticProcessingIds.add(instance.reference.id);
    processedItemIds.add(instance.reference.id);
  }

  /// Revert optimistic UI update - restores item if backend operation failed
  void revertOptimisticState(String instanceId) {
    final originalInstance = optimisticSnapshots[instanceId];
    if (originalInstance == null) return;

    optimisticProcessingIds.remove(instanceId);
    processedItemIds.remove(instanceId);
    optimisticSnapshots.remove(instanceId);

    // Restore item to list if it still exists and wasn't replaced
    final exists = items.any((item) => item.reference.id == instanceId);
    if (!exists) {
      // Item was removed, try to restore from snapshot
      items.add(originalInstance);
      // Sort by template name to maintain some order
      items.sort((a, b) => a.templateName.compareTo(b.templateName));
    }
  }

  /// Clear optimistic state after successful backend operation
  void clearOptimisticState(String instanceId) {
    optimisticProcessingIds.remove(instanceId);
    optimisticSnapshots.remove(instanceId);
  }

  /// Get remaining items (excluding processed and optimistic ones)
  List<ActivityInstanceRecord> getRemainingItems() {
    return items
        .where((item) =>
            !processedItemIds.contains(item.reference.id) &&
            !optimisticProcessingIds.contains(item.reference.id))
        .toList();
  }

  /// Get count of items currently being processed optimistically
  int getProcessingCount() {
    return optimisticProcessingIds.length;
  }

  /// Handle instance updates from ItemComponent
  /// This intercepts completions and skips to backdate them to yesterday
  /// Uses optimistic UI updates for instant feedback
  /// Differentiates between progress updates (increment) and completions/skips
  Future<void> handleInstanceUpdated(
      ActivityInstanceRecord updatedInstance) async {
    final instanceId = updatedInstance.reference.id;

    // Prevent duplicate processing
    if (processedItemIds.contains(instanceId) ||
        optimisticProcessingIds.contains(instanceId)) {
      return;
    }

    final yesterday = DateService.yesterdayStart;
    final yesterdayEnd =
        DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    final today = DateService.todayStart;

    // Differentiate between progress updates and status changes (completion/skip)
    final isStatusChange = updatedInstance.status == 'completed' ||
        updatedInstance.status == 'skipped';
    final isProgressUpdate =
        updatedInstance.status == 'pending' && !isStatusChange;

    // For progress updates (just incrementing value), update item in place
    if (isProgressUpdate) {
      // Update the existing item in the list with new progress value
      final index = items.indexWhere((item) => item.reference.id == instanceId);
      if (index != -1) {
        items[index] = updatedInstance;
      }
      // No need to do anything else for progress updates - item stays in list
      return;
    }

    // For completions and skips, apply optimistic removal
    // OPTIMISTIC UPDATE: Apply UI changes immediately (remove from list)
    applyOptimisticState(updatedInstance);

    // Process backend operations asynchronously
    try {
      // Check if item was just completed and needs backdating
      if (updatedInstance.status == 'completed' &&
          updatedInstance.completedAt != null) {
        final completedAt = updatedInstance.completedAt!;
        // If completed today, backdate to yesterday
        if (completedAt.isAfter(today)) {
          await ActivityInstanceService.completeInstanceWithBackdate(
            instanceId: instanceId,
            finalValue: updatedInstance.currentValue,
            finalAccumulatedTime: updatedInstance.accumulatedTime,
            completedAt: yesterdayEnd,
            forceSessionBackdate: true,
          );
        }
      }

      // Check if item was just skipped and needs backdating
      if (updatedInstance.status == 'skipped' &&
          updatedInstance.skippedAt != null) {
        final skippedAt = updatedInstance.skippedAt!;
        // If skipped today, backdate to yesterday
        if (skippedAt.isAfter(today)) {
          await ActivityInstanceService.skipInstance(
            instanceId: instanceId,
            skippedAt: yesterdayEnd,
            skipAutoGeneration:
                true, // prevent generating another "next" instance when backdating
          );
        }
      }

      // Reset reminder count when user completes/skips items
      await MorningCatchUpService.resetReminderCount();
      await loadReminderCount();

      // Clear optimistic state now that backend operation succeeded
      clearOptimisticState(instanceId);

      // Only reload if we need to check for new instances (e.g., habit completion may create new instance)
      // For most cases, optimistic removal is sufficient
      if (updatedInstance.templateCategoryType == 'habit' &&
          updatedInstance.status == 'completed') {
        // Habits may generate new instances, so reload
        await loadItems();
      }

      // RECALCULATE daily progress record in background after user completes/skips items
      // This ensures cumulative score includes the user's updates
      // Run in background without blocking UI - fire and forget with error handling
      Future.delayed(const Duration(milliseconds: 300)).then((_) async {
        // Background recalculation - don't await, let it run asynchronously
        final userId = await waitForCurrentUserUid();
        if (userId.isEmpty) return;
        MorningCatchUpService.recalculateDailyProgressRecordForDate(
          userId: userId,
          targetDate: yesterday,
        ).catchError((error) {
          // Silent error handling - recalculation failure shouldn't affect UI
          // The record will be recalculated when dialog closes anyway
          print('Background recalculation error (non-critical): $error');
        });
      });
    } catch (e) {
      // ROLLBACK: Revert optimistic update on error
      revertOptimisticState(instanceId);
      rethrow; // Let UI handle error display
    }
  }

  /// Check if dialog can be closed (all items processed)
  bool canCloseDialog() {
    final remaining = getRemainingItems();
    final processing = getProcessingCount();
    return remaining.isEmpty && processing == 0;
  }

  /// Prepare for dialog close - triggers refresh notifications
  Future<void> prepareForClose() async {
    // Trigger refresh of habit and queue pages
    NotificationCenter.post('loadHabits', null);
    NotificationCenter.post('loadData', null);

    // Small delay to ensure notifications are processed
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Save state on dispose - recalculates record if items were processed
  /// Recalculates with suppressToasts: true to store updated toast data
  /// Toasts will be shown after this completes via showPendingToasts()
  /// This runs in background after dialog closes
  Future<void> saveStateOnDispose() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      // Ensure all active habits have pending instances (background operation)
      await MorningCatchUpService.ensurePendingInstancesExist(userId);

      // Reload items to reflect any new instances that were generated
      await loadItems();

      // Broadcast progress recalculated to refresh other parts of UI
      InstanceEvents.broadcastProgressRecalculated();

      // If items were processed, recalculate the record to ensure cumulative score is updated
      if (processedItemIds.isNotEmpty) {
        // Recalculate with suppressToasts: true to store updated toast data
        // The updated data will overwrite the initial pending toast data
        await MorningCatchUpService.recalculateDailyProgressRecordForDate(
          userId: userId,
          targetDate: DateService.yesterdayStart,
          suppressToasts: true, // Store updated toast data, don't show yet
        );
      } else if (items.isNotEmpty) {
        // If dialog is closed without action, ensure record exists
        // Use suppressToasts: true to maintain consistency
        await MorningCatchUpService.createDailyProgressRecordForDate(
          userId: userId,
          targetDate: DateService.yesterdayStart,
          suppressToasts: true,
        );
      }
    } catch (e) {
      print('Error in background saveStateOnDispose: $e');
      // Silent error - don't affect user experience
    }
  }

  /// Recalculate daily progress record in background
  /// Uses suppressToasts: true to store updated toast data
  Future<void> recalculateProgressRecord() async {
    if (processedItemIds.isNotEmpty) {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      MorningCatchUpService.recalculateDailyProgressRecordForDate(
        userId: userId,
        targetDate: DateService.yesterdayStart,
        suppressToasts: true, // Store updated toast data, don't show yet
      ).catchError((error) {
        // Silent error handling - recalculation failure shouldn't block dialog close
        print('Background recalculation error on close (non-critical): $error');
      });
    }
  }

  /// Skip all remaining habits
  /// [onProgressUpdate] - Optional callback to notify UI to rebuild during processing
  Future<SkipAllResult> skipAllRemaining(
      {VoidCallback? onProgressUpdate}) async {
    final today = DateService.todayStart;
    // Only skip habits where window has ended (exclude habits with active windows)
    final remainingHabits = items
        .where((item) =>
            !processedItemIds.contains(item.reference.id) &&
            item.templateCategoryType == 'habit' &&
            // Only include habits where window has ended
            (item.windowEndDate == null ||
                DateTime(
                      item.windowEndDate!.year,
                      item.windowEndDate!.month,
                      item.windowEndDate!.day,
                    ).isBefore(today)))
        .toList();

    if (remainingHabits.isEmpty) {
      // If no habits to skip, just return success
      return SkipAllResult(success: true, skippedCount: 0);
    }

    isProcessing = true;
    totalToProcess = remainingHabits.length;
    processedCount = 0;
    processingStatus = 'Preparing to skip habits...';
    onProgressUpdate?.call();

    try {
      final yesterday = DateService.yesterdayStart;
      final yesterdayEnd =
          DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);

      // Batch skip all remaining habits at once
      processingStatus =
          'Skipping ${remainingHabits.length} habit${remainingHabits.length == 1 ? '' : 's'}...';
      onProgressUpdate?.call();

      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return SkipAllResult(success: false, skippedCount: 0);
      await ActivityInstanceService.batchSkipInstances(
        instances: remainingHabits,
        skippedAt: yesterdayEnd,
        userId: userId,
      );

      // Mark all as processed
      for (final item in remainingHabits) {
        processedItemIds.add(item.reference.id);
      }
      processedCount = remainingHabits.length;
      onProgressUpdate?.call();

      // Mark processing as complete - dialog can close now
      // Background operations (ensuring instances, recalculating) will happen after dialog closes
      processingStatus = 'Complete';
      onProgressUpdate?.call();

      // Reset reminder count when user skips all items
      await MorningCatchUpService.resetReminderCount();
      await MorningCatchUpService.markDialogAsShown();

      // Check if there are still remaining habits
      // Tasks are ignored for the purpose of keeping the dialog open after "Skip All"
      // because tasks are not skipped by this action and we don't want to show just tasks
      final hasRemainingHabits = items.any((item) =>
          !processedItemIds.contains(item.reference.id) &&
          item.templateCategoryType == 'habit');

      return SkipAllResult(
        success: true,
        skippedCount: remainingHabits.length,
        hasRemainingItems: hasRemainingHabits,
      );
    } catch (e) {
      return SkipAllResult(success: false, error: e.toString());
    } finally {
      isProcessing = false;
      processingStatus = '';
      processedCount = 0;
      totalToProcess = 0;
      onProgressUpdate?.call();
    }
  }

  /// Snooze the dialog
  Future<SnoozeResult> snoozeDialog() async {
    final currentReminderCount = await MorningCatchUpService.getReminderCount();
    await MorningCatchUpService.snoozeDialog();
    await MorningCatchUpService.markDialogAsShown();
    await loadReminderCount();
    return SnoozeResult(
      reminderCount: currentReminderCount,
      newReminderCount: reminderCount,
    );
  }

  /// Handle instance deleted - optimistically remove it
  void handleInstanceDeleted(ActivityInstanceRecord deletedInstance) {
    // Optimistically remove deleted item immediately
    applyOptimisticState(deletedInstance);
  }

  /// Check if all habits are processed (for auto-close)
  /// Only checks habits, not tasks, since tasks cannot be skipped via the dialog
  Future<bool> checkAndAutoClose() async {
    final remainingAfterUpdate = getRemainingItems();
    // Only check if habits are processed, ignore tasks
    final remainingHabits = remainingAfterUpdate
        .where((item) => item.templateCategoryType == 'habit')
        .toList();
    if (remainingHabits.isEmpty) {
      // Wait a brief moment for any final state updates
      await Future.delayed(const Duration(milliseconds: 500));
      final finalRemaining = getRemainingItems();
      final finalRemainingHabits = finalRemaining
          .where((item) => item.templateCategoryType == 'habit')
          .toList();
      if (finalRemainingHabits.isEmpty) {
        await MorningCatchUpService.markDialogAsShown();
        return true;
      }
    }
    return false;
  }
}

/// Result class for skip all operation
class SkipAllResult {
  final bool success;
  final int skippedCount;
  final bool hasRemainingItems;
  final String? error;

  SkipAllResult({
    required this.success,
    this.skippedCount = 0,
    this.hasRemainingItems = false,
    this.error,
  });
}

/// Result class for snooze operation
class SnoozeResult {
  final int reminderCount;
  final int newReminderCount;

  SnoozeResult({
    required this.reminderCount,
    required this.newReminderCount,
  });
}
