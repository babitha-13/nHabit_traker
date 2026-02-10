import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'Services/activity_instance_creation_service.dart';
import 'Services/activity_instance_query_service.dart';
import 'Services/activity_instance_utility_service.dart';
import 'Services/activity_instance_completion_service.dart';
import 'Services/activity_instance_progress_service.dart';
import 'Services/activity_instance_scheduling_service.dart';
import 'Services/activity_instance_helper_service.dart';
export 'Services/activity_instance_completion_service.dart'
    show StackedSessionTimes;

class ActivityInstanceService {
  static Future<DocumentReference> createActivityInstance({
    required String templateId,
    DateTime? dueDate,
    String? dueTime,
    required ActivityRecord template,
    String? userId,
    bool skipOrderLookup = false,
  }) async {
    return ActivityInstanceCreationService.createActivityInstance(
      templateId: templateId,
      dueDate: dueDate,
      dueTime: dueTime,
      template: template,
      userId: userId,
      skipOrderLookup: skipOrderLookup,
    );
  }

  static Future<List<ActivityInstanceRecord>> getActiveTaskInstances({
    String? userId,
  }) async {
    return ActivityInstanceQueryService.getActiveTaskInstances(userId: userId);
  }

  static Future<List<ActivityInstanceRecord>> getAllTaskInstances({
    String? userId,
  }) async {
    return ActivityInstanceQueryService.getAllTaskInstances(userId: userId);
  }

  static Future<List<ActivityInstanceRecord>> getTaskInstancesHistory({
    required int daysAgo,
    required int daysToLoad,
    String? userId,
  }) async {
    return ActivityInstanceQueryService.getTaskInstancesHistory(
      daysAgo: daysAgo,
      daysToLoad: daysToLoad,
      userId: userId,
    );
  }

  static Future<List<ActivityInstanceRecord>> getCurrentHabitInstances({
    String? userId,
  }) async {
    return ActivityInstanceQueryService.getCurrentHabitInstances(
        userId: userId);
  }

  static Future<List<ActivityInstanceRecord>> getHabitInstancesForDate({
    required DateTime targetDate,
    String? userId,
  }) async {
    return ActivityInstanceQueryService.getHabitInstancesForDate(
      targetDate: targetDate,
      userId: userId,
    );
  }

  static Future<List<ActivityInstanceRecord>> getAllHabitInstances({
    String? userId,
  }) async {
    return ActivityInstanceQueryService.getAllHabitInstances(userId: userId);
  }

  static Future<List<ActivityInstanceRecord>>
      getLatestHabitInstancePerTemplate({
    String? userId,
  }) async {
    return ActivityInstanceQueryService.getLatestHabitInstancePerTemplate(
        userId: userId);
  }

  /// Get active habit instances for the user (Queue page - includes future instances)
  static Future<List<ActivityInstanceRecord>> getActiveHabitInstances({
    String? userId,
  }) async {
    return ActivityInstanceQueryService.getActiveHabitInstances(userId: userId);
  }

  /// Get all active instances for a user (tasks and habits)
  /// OPTIMIZED: Only fetches pending + completed from last 2 days to prevent OOM
  static Future<List<ActivityInstanceRecord>> getAllActiveInstances({
    String? userId,
  }) async {
    return ActivityInstanceQueryService.getAllActiveInstances(userId: userId);
  }

  static Future<List<ActivityInstanceRecord>> getRecentCompletedInstances({
    String? userId,
  }) async {
    return ActivityInstanceQueryService.getRecentCompletedInstances(
        userId: userId);
  }

  // ==================== UTILITY METHODS ====================
  /// Test method to manually create an instance (for debugging)
  static Future<void> testCreateInstance({
    required String templateId,
    String? userId,
  }) async {
    return ActivityInstanceUtilityService.testCreateInstance(
      templateId: templateId,
      userId: userId,
    );
  }

  /// Get all instances for a specific template (for debugging/testing)
  static Future<List<ActivityInstanceRecord>> getInstancesForTemplate({
    required String templateId,
    String? userId,
  }) async {
    return ActivityInstanceUtilityService.getInstancesForTemplate(
      templateId: templateId,
      userId: userId,
    );
  }

  /// Get all instances for a user (for debugging/testing)
  static Future<List<ActivityInstanceRecord>> getAllInstances({
    String? userId,
  }) async {
    return ActivityInstanceUtilityService.getAllInstances(userId: userId);
  }

  /// Delete all instances for a template (cleanup utility)
  static Future<void> deleteInstancesForTemplate({
    required String templateId,
    String? userId,
  }) async {
    return ActivityInstanceUtilityService.deleteInstancesForTemplate(
      templateId: templateId,
      userId: userId,
    );
  }

  /// Get updated instance data after changes
  static Future<ActivityInstanceRecord> getUpdatedInstance({
    required String instanceId,
    String? userId,
  }) async {
    return ActivityInstanceHelperService.getUpdatedInstance(
      instanceId: instanceId,
      userId: userId,
    );
  }

  static int calculateCompletionDuration(
    ActivityInstanceRecord instance,
    DateTime completedAt, {
    int? effectiveEstimateMinutes,
  }) {
    return ActivityInstanceCompletionService.calculateCompletionDuration(
      instance,
      completedAt,
      effectiveEstimateMinutes: effectiveEstimateMinutes,
    );
  }

  /// Find other instances completed within a time window (for backward stacking)
  static Future<List<ActivityInstanceRecord>> findSimultaneousCompletions({
    required String userId,
    required DateTime completionTime,
    required String excludeInstanceId,
    Duration window = const Duration(seconds: 15),
  }) async {
    return ActivityInstanceCompletionService.findSimultaneousCompletions(
      userId: userId,
      completionTime: completionTime,
      excludeInstanceId: excludeInstanceId,
      window: window,
    );
  }

  /// Calculate start and end times for a session, stacking backwards from completion time
  /// Returns both start and end times to ensure correct duration when stacking against simultaneous items
  static Future<StackedSessionTimes> calculateStackedStartTime({
    required String userId,
    required DateTime completionTime,
    required int durationMs,
    required String instanceId,
    int? effectiveEstimateMinutes,
  }) async {
    return ActivityInstanceCompletionService.calculateStackedStartTime(
      userId: userId,
      completionTime: completionTime,
      durationMs: durationMs,
      instanceId: instanceId,
      effectiveEstimateMinutes: effectiveEstimateMinutes,
    );
  }

  /// Complete an activity instance
  static Future<void> completeInstance({
    required String instanceId,
    dynamic finalValue,
    int? finalAccumulatedTime,
    String? notes,
    String? userId,
    bool skipOptimisticUpdate = false,
  }) async {
    return ActivityInstanceCompletionService.completeInstance(
      instanceId: instanceId,
      finalValue: finalValue,
      finalAccumulatedTime: finalAccumulatedTime,
      notes: notes,
      userId: userId,
      skipOptimisticUpdate: skipOptimisticUpdate,
    );
  }

  /// Complete an activity instance with backdated completion time
  static Future<void> completeInstanceWithBackdate({
    required String instanceId,
    dynamic finalValue,
    int? finalAccumulatedTime,
    String? notes,
    String? userId,
    DateTime? completedAt,
    bool forceSessionBackdate = false,
    bool skipOptimisticUpdate = false,
  }) async {
    return ActivityInstanceCompletionService.completeInstanceWithBackdate(
      instanceId: instanceId,
      finalValue: finalValue,
      finalAccumulatedTime: finalAccumulatedTime,
      notes: notes,
      userId: userId,
      completedAt: completedAt,
      forceSessionBackdate: forceSessionBackdate,
      skipOptimisticUpdate: skipOptimisticUpdate,
    );
  }

  /// Uncomplete an activity instance (mark as pending)
  static Future<void> uncompleteInstance({
    required String instanceId,
    String? userId,
    bool deleteLogs = false,
    bool skipOptimisticUpdate = false,
    dynamic currentValue,
  }) async {
    return ActivityInstanceCompletionService.uncompleteInstance(
      instanceId: instanceId,
      userId: userId,
      deleteLogs: deleteLogs,
      skipOptimisticUpdate: skipOptimisticUpdate,
      currentValue: currentValue,
    );
  }

  // ==================== INSTANCE PROGRESS ====================
  /// Update instance progress (for quantitative tracking)
  static Future<void> updateInstanceProgress({
    required String instanceId,
    required dynamic currentValue,
    String? userId,
    DateTime? referenceTime,
  }) async {
    return ActivityInstanceProgressService.updateInstanceProgress(
      instanceId: instanceId,
      currentValue: currentValue,
      userId: userId,
      referenceTime: referenceTime,
    );
  }

  /// Snooze an instance until a specific date
  static Future<void> snoozeInstance({
    required String instanceId,
    required DateTime snoozeUntil,
    String? userId,
  }) async {
    return ActivityInstanceProgressService.snoozeInstance(
      instanceId: instanceId,
      snoozeUntil: snoozeUntil,
      userId: userId,
    );
  }

  /// Unsnooze an instance (remove snooze)
  static Future<void> unsnoozeInstance({
    required String instanceId,
    String? userId,
  }) async {
    return ActivityInstanceProgressService.unsnoozeInstance(
      instanceId: instanceId,
      userId: userId,
    );
  }

  /// Update instance timer state
  static Future<void> updateInstanceTimer({
    required String instanceId,
    required bool isActive,
    DateTime? startTime,
    String? userId,
  }) async {
    return ActivityInstanceProgressService.updateInstanceTimer(
      instanceId: instanceId,
      isActive: isActive,
      startTime: startTime,
      userId: userId,
    );
  }

  /// Toggle timer for time tracking using session-based logic
  static Future<void> toggleInstanceTimer({
    required String instanceId,
    String? userId,
  }) async {
    return ActivityInstanceProgressService.toggleInstanceTimer(
      instanceId: instanceId,
      userId: userId,
    );
  }

  // ==================== INSTANCE SCHEDULING ====================
  /// Skip current instance and generate next if recurring
  static Future<void> skipInstance({
    required String instanceId,
    String? notes,
    String? userId,
    DateTime? skippedAt,
    bool skipAutoGeneration = false,
  }) async {
    return ActivityInstanceSchedulingService.skipInstance(
      instanceId: instanceId,
      notes: notes,
      userId: userId,
      skippedAt: skippedAt,
      skipAutoGeneration: skipAutoGeneration,
    );
  }

  /// Batch skip multiple habit instances at once
  /// Uses Firestore batch writes for efficient processing
  /// Generates next instances for all skipped habits in the same batch
  static Future<void> batchSkipInstances({
    required List<ActivityInstanceRecord> instances,
    required DateTime skippedAt,
    required String userId,
  }) async {
    return ActivityInstanceSchedulingService.batchSkipInstances(
      instances: instances,
      skippedAt: skippedAt,
      userId: userId,
    );
  }

  /// Efficiently skip expired instances using batch writes
  /// Always skips expired instances up to day before yesterday
  /// Creates yesterday instance as PENDING if it exists, otherwise creates next valid instance
  static Future<DocumentReference?> bulkSkipExpiredInstancesWithBatches({
    required ActivityInstanceRecord oldestInstance,
    required ActivityRecord template,
    required String userId,
  }) async {
    return ActivityInstanceSchedulingService
        .bulkSkipExpiredInstancesWithBatches(
      oldestInstance: oldestInstance,
      template: template,
      userId: userId,
    );
  }

  /// Reschedule instance to a new due date
  static Future<void> rescheduleInstance({
    required String instanceId,
    required DateTime newDueDate,
    String? userId,
  }) async {
    return ActivityInstanceSchedulingService.rescheduleInstance(
      instanceId: instanceId,
      newDueDate: newDueDate,
      userId: userId,
    );
  }

  /// Remove due date from an activity instance
  static Future<void> removeDueDateFromInstance({
    required String instanceId,
    String? userId,
  }) async {
    return ActivityInstanceSchedulingService.removeDueDateFromInstance(
      instanceId: instanceId,
      userId: userId,
    );
  }

  /// Skip all instances until a specific date
  static Future<void> skipInstancesUntil({
    required String templateId,
    required DateTime untilDate,
    String? userId,
  }) async {
    return ActivityInstanceSchedulingService.skipInstancesUntil(
      templateId: templateId,
      untilDate: untilDate,
      userId: userId,
    );
  }

  static int calculateMissingInstancesFromInstance({
    required ActivityInstanceRecord instance,
    required DateTime today,
  }) {
    return ActivityInstanceHelperService.calculateMissingInstancesFromInstance(
      instance: instance,
      today: today,
    );
  }

  static Future<void> cleanupInstancesBeyondEndDate({
    required String templateId,
    required DateTime newEndDate,
    String? userId,
  }) async {
    return ActivityInstanceHelperService.cleanupInstancesBeyondEndDate(
      templateId: templateId,
      newEndDate: newEndDate,
      userId: userId,
    );
  }

  static Future<void> regenerateInstancesFromStartDate({
    required String templateId,
    required ActivityRecord template,
    required DateTime newStartDate,
    String? userId,
  }) async {
    return ActivityInstanceHelperService.regenerateInstancesFromStartDate(
      templateId: templateId,
      template: template,
      newStartDate: newStartDate,
      userId: userId,
    );
  }

  static Future<void> updateActivityInstancesCascade({
    required String templateId,
    required Map<String, dynamic> updates,
    required bool updateHistorical,
    String? userId,
  }) async {
    return ActivityInstanceHelperService.updateActivityInstancesCascade(
      templateId: templateId,
      updates: updates,
      updateHistorical: updateHistorical,
      userId: userId,
    );
  }
}
