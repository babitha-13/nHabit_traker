import 'dart:async';

import 'package:flutter/material.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/Scores/today_score_calculator.dart';
import 'package:habit_tracker/features/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/features/Home/CatchUp/logic/morning_catchup_service.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';
import 'package:habit_tracker/core/utils/Date_time/ist_day_boundary_service.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_repository.dart';

/// Controller class for managing morning catch-up dialog business logic
/// Separates business logic from UI concerns
class MorningCatchUpDialogLogic {
  MorningCatchUpDialogLogic({
    List<ActivityInstanceRecord>? initialItems,
    required this.baselineProcessedAtOpen,
  }) {
    if (initialItems != null) {
      items = List<ActivityInstanceRecord>.from(initialItems);
      isLoading = false;
    }
  }

  final bool baselineProcessedAtOpen;

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
  bool hasUserProvidedUpdates = false;
  bool hadHabitItemsAtLaunch = false;

  Future<void> _ensureDueDateFromBelongsToDate(
      ActivityInstanceRecord instance) async {
    if (instance.dueDate != null || instance.belongsToDate == null) return;
    final normalizedBelongs = DateTime(
      instance.belongsToDate!.year,
      instance.belongsToDate!.month,
      instance.belongsToDate!.day,
    );
    try {
      await instance.reference.update({
        'dueDate': normalizedBelongs,
        'lastUpdated': DateTime.now(),
      });
    } catch (_) {
      // Best-effort normalization only; ignore failures.
    }
  }

  /// Initialize the dialog logic
  Future<void> initialize() async {
    if (isLoading) {
      await Future.wait([
        loadItems(),
        loadReminderCount(),
      ]);
    } else {
      await loadReminderCount();
    }
    hadHabitItemsAtLaunch =
        items.any((item) => item.templateCategoryType == 'habit');
    // Mark as shown immediately to prevent re-showing
    unawaited(MorningCatchUpService.markDialogAsShown());
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
      if (!hadHabitItemsAtLaunch) {
        hadHabitItemsAtLaunch =
            items.any((item) => item.templateCategoryType == 'habit');
      }
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
    final isOptimisticUpdate =
        updatedInstance.snapshotData['_optimistic'] == true;
    final hasPendingOptimisticSync =
        optimisticProcessingIds.contains(instanceId);

    // Ignore already settled updates. Allow reconciled updates for in-flight optimistic IDs.
    if (processedItemIds.contains(instanceId) && !hasPendingOptimisticSync) {
      return;
    }

    final yesterday = IstDayBoundaryService.yesterdayStartIst();
    final yesterdayEnd =
        DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    final today = IstDayBoundaryService.todayStartIst();

    // Differentiate between progress updates and status changes (completion/skip)
    final isStatusChange = updatedInstance.status == 'completed' ||
        updatedInstance.status == 'skipped';
    final isProgressUpdate =
        updatedInstance.status == 'pending' && !isStatusChange;

    // For progress updates (just incrementing value), update item in place
    if (isProgressUpdate) {
      if (!isOptimisticUpdate) {
        await _ensureDueDateFromBelongsToDate(updatedInstance);
      }
      // Update the existing item in the list with new progress value
      final index = items.indexWhere((item) => item.reference.id == instanceId);
      if (index != -1) {
        items[index] = updatedInstance;
      }
      // No need to do anything else for progress updates - item stays in list
      return;
    }

    // For optimistic updates, apply local removal and wait for reconciled backend update
    // before running catch-up specific backdating writes.
    if (isOptimisticUpdate) {
      if (!hasPendingOptimisticSync) {
        applyOptimisticState(updatedInstance);
      }
      return;
    }

    // For reconciled status changes, ensure optimistic state is active.
    if (!hasPendingOptimisticSync) {
      applyOptimisticState(updatedInstance);
    }

    if (!isOptimisticUpdate) {
      await _ensureDueDateFromBelongsToDate(updatedInstance);
    }

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
            skipOptimisticUpdate: true,
            skipNextInstanceGeneration: true,
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
      hasUserProvidedUpdates = true;

      // Only reload if we need to check for new instances (e.g., habit completion may create new instance)
      // For most cases, optimistic removal is sufficient
      if (updatedInstance.templateCategoryType == 'habit' &&
          updatedInstance.status == 'completed') {
        // Habits may generate new instances, so reload
        await loadItems();
      }

      // Recalculation is deferred to dialog close and done once.
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
    // Catch-up batch operations don't emit per-instance events.
    // Force the shared instance cache/snapshot to refresh so Habits/Queue
    // pages do not keep showing stale yesterday items.
    final userId = await waitForCurrentUserUid();
    FirestoreCacheService().invalidateInstancesCache();
    TodayInstanceRepository.instance.clearSnapshot();
    
    TodayScoreCalculator.invalidateCache();
    if (userId.isNotEmpty) {
      DailyProgressQueryService.invalidateUserCache(userId);
    }

    if (userId.isNotEmpty) {
      try {
        await TodayInstanceRepository.instance.refreshToday(userId: userId);
      } catch (_) {
        // Best-effort refresh. View loaders below will still trigger a reload.
      }
    }

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

      // Broadcast progress recalculated to refresh other parts of UI
      InstanceEvents.broadcastProgressRecalculated();

      // If user changed anything, decide cloud write mode using latest processed marker.
      if (hasUserProvidedUpdates || processedItemIds.isNotEmpty) {
        await MorningCatchUpService.finalizeAfterCatchUpEdits(
          userId: userId,
          targetDate: IstDayBoundaryService.yesterdayStartIst(),
          baselineProcessedAtOpen: baselineProcessedAtOpen,
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
    if (hasUserProvidedUpdates || processedItemIds.isNotEmpty) {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      try {
        await MorningCatchUpService.finalizeAfterCatchUpEdits(
          userId: userId,
          targetDate: IstDayBoundaryService.yesterdayStartIst(),
          baselineProcessedAtOpen: baselineProcessedAtOpen,
          suppressToasts: true,
        );
      } catch (error) {
        print('Background recalculation error on close (non-critical): $error');
      }
    }
  }

  /// Skip all remaining habits
  /// [onProgressUpdate] - Optional callback to notify UI to rebuild during processing
  Future<SkipAllResult> skipAllRemaining(
      {VoidCallback? onProgressUpdate}) async {
    final today = IstDayBoundaryService.todayStartIst();
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
      final yesterday = IstDayBoundaryService.yesterdayStartIst();
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
      hasUserProvidedUpdates = true;
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
    // Clear any pending toasts (penalties/scores) so they don't show when closing for snooze
    MorningCatchUpService.clearPendingToasts();
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
    hasUserProvidedUpdates = true;
  }

  /// Check if all habits are processed (for auto-close)
  /// Only checks habits, not tasks, since tasks cannot be skipped via the dialog
  Future<bool> checkAndAutoClose() async {
    if (getProcessingCount() > 0) {
      return false;
    }

    final remainingAfterUpdate = getRemainingItems();
    final remainingHabits = remainingAfterUpdate
        .where((item) => item.templateCategoryType == 'habit')
        .toList();
    final shouldClose = hadHabitItemsAtLaunch
        ? remainingHabits.isEmpty
        : remainingAfterUpdate.isEmpty;
    if (shouldClose) {
      // Wait a brief moment for any final state updates
      await Future.delayed(const Duration(milliseconds: 500));
      if (getProcessingCount() > 0) {
        return false;
      }
      final finalRemaining = getRemainingItems();
      final finalRemainingHabits = finalRemaining
          .where((item) => item.templateCategoryType == 'habit')
          .toList();
      final finalShouldClose = hadHabitItemsAtLaunch
          ? finalRemainingHabits.isEmpty
          : finalRemaining.isEmpty;
      if (finalShouldClose) {
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
