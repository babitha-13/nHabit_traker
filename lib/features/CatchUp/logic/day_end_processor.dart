import 'package:habit_tracker/features/Progress/Point_system_helper/points_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/daily_points_calculator.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/Scores/score_finalization_service.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/Scores/today_score_calculator.dart';
import 'package:habit_tracker/features/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/features/toasts/bonus_notification_formatter.dart';
import 'package:habit_tracker/features/toasts/milestone_toast_service.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/Scores/score_history_service.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';

/// Service for processing day-end operations on habits
/// Creates daily progress snapshots (status changes now require manual user confirmation)
class DayEndProcessor {
  /// Process day-end for a specific user
  /// [closeInstances] - If true, marks expired habit instances as skipped (requires user confirmation)
  /// Set to false to disable automatic status changes (automatic processing is disabled)
  /// [ensureInstances] - If true, ensures all active habits have pending instances (default true)
  static Future<void> processDayEnd({
    required String userId,
    DateTime? targetDate,
    bool closeInstances = false,
    bool ensureInstances = true,
  }) async {
    // Use targetDate if provided, otherwise use yesterday's date
    final processDate = targetDate ?? DateService.yesterdayStart;
    try {
      // Step 0: Ensure all active habits have pending instances (if enabled)
      // This should always run as part of day-end processing
      if (ensureInstances) {
        await ensurePendingInstancesExist(userId);
      }

      // Step 1: Update lastDayValue for active windowed habits
      await _updateLastDayValues(userId, processDate);
      // Step 2: Create daily progress record BEFORE closing instances
      // This preserves the exact values shown in Queue page
      await _createDailyProgressRecord(userId, processDate);
      // Step 3: Close all open habit instances for the target date (only if explicitly requested)
      // NOTE: Automatic status changes disabled - instances are now only marked as skipped
      // when user manually confirms via the Queue page "Needs Processing" section
      if (closeInstances) {
        await _closeOpenHabitInstances(userId, processDate);
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Update lastDayValue for active windowed habits without creating daily progress record
  /// Used when there are pending items and finalization should be deferred to the dialog
  static Future<void> updateLastDayValuesOnly(
      String userId, DateTime targetDate) async {
    await _updateLastDayValues(userId, targetDate);
  }

  /// Update lastDayValue for active windowed habits at day-end
  static Future<void> _updateLastDayValues(
    String userId,
    DateTime targetDate,
  ) async {
    final normalizedDate =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    // Query active habit instances with windows that are still open
    try {
      final query = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('status', isEqualTo: 'pending')
          .where('windowEndDate', isGreaterThan: normalizedDate);
      final querySnapshot = await query.get();
      final instances = querySnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      if (instances.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      final now = DateTime.now();
      for (final instance in instances) {
        // Update lastDayValue to current value for next day's differential calculation
        final instanceRef = instance.reference;
        batch.update(instanceRef, {
          'lastDayValue': instance.currentValue,
          'lastUpdated': now,
        });
      }
      await batch.commit();
    } catch (e) {
      print('❌ MISSING INDEX: _updateLastDayValues needs Index 2');
      print(
          'Required Index: templateCategoryType (ASC) + status (ASC) + windowEndDate (ASC) + dueDate (ASC)');
      print('Collection: activity_instances');
      print('Full error: $e');
      if (e.toString().contains('index') || e.toString().contains('https://')) {
        print(
            '📋 Look for the Firestore index creation link in the error message above!');
        print('   Click the link to create the index automatically.');
      }
      rethrow;
    }
  }

  /// Close habit instances whose windows have expired
  static Future<void> _closeOpenHabitInstances(
    String userId,
    DateTime targetDate,
  ) async {
    final normalizedDate =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    // Query habit instances where window has expired (windowEndDate <= targetDate) AND status is pending
    // For a daily habit: windowEndDate = 15th, should be closed when processing day-end on 15th (going into 16th)
    try {
      final query = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('status', isEqualTo: 'pending')
          .where('windowEndDate', isLessThanOrEqualTo: normalizedDate);
      final querySnapshot = await query.get();
      final instances = querySnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      final batch = FirebaseFirestore.instance.batch();
      // Use the targetDate being processed (normalizedDate) for skippedAt
      // Oct 15 window closes at Oct 16 midnight
      final skippedAtDate = normalizedDate;
      for (final instance in instances) {
        // Mark as skipped (preserve currentValue for partial completions)
        final instanceRef = instance.reference;
        batch.update(instanceRef, {
          'status': 'skipped',
          'skippedAt': skippedAtDate, // Use the date being processed
          'lastUpdated': DateTime.now(), // Real time for audit trail
        });
        // Generate next instance for this habit
        await _generateNextInstance(instance, userId, batch);
      }
      if (instances.isNotEmpty) {
        await batch.commit();
      }
    } catch (e) {
      print('❌ MISSING INDEX: _closeOpenHabitInstances needs Index 2');
      print(
          'Required Index: templateCategoryType (ASC) + status (ASC) + windowEndDate (ASC) + dueDate (ASC)');
      print('Collection: activity_instances');
      print('Full error: $e');
      if (e.toString().contains('index') || e.toString().contains('https://')) {
        print(
            '📋 Look for the Firestore index creation link in the error message above!');
        print('   Click the link to create the index automatically.');
      }
      rethrow;
    }
  }

  /// Generate next instance for a habit after completion or skip
  static Future<void> _generateNextInstance(
    ActivityInstanceRecord instance,
    String userId,
    WriteBatch batch,
  ) async {
    try {
      // Calculate next window start = current windowEndDate + 1
      final nextBelongsToDate =
          instance.windowEndDate!.add(const Duration(days: 1));
      final nextWindowEndDate =
          nextBelongsToDate.add(Duration(days: instance.windowDuration - 1));
      // Check if instance already exists for this template and date
      try {
        final existingQuery = ActivityInstanceRecord.collectionForUser(userId)
            .where('templateId', isEqualTo: instance.templateId)
            .where('belongsToDate', isEqualTo: nextBelongsToDate)
            .where('status', isEqualTo: 'pending');
        final existingInstances = await existingQuery.get();
        if (existingInstances.docs.isNotEmpty) {
          return;
        }
      } catch (e) {
        print('❌ MISSING INDEX: _generateNextInstance needs Index 1');
        print(
            'Required Index: templateId (ASC) + status (ASC) + belongsToDate (ASC) + dueDate (ASC)');
        print('Collection: activity_instances');
        print('Full error: $e');
        if (e.toString().contains('index') ||
            e.toString().contains('https://')) {
          print(
              '📋 Look for the Firestore index creation link in the error message above!');
          print('   Click the link to create the index automatically.');
        }
        // Don't rethrow - we don't want to fail the entire batch
        return;
      }
      // Inherit order from previous instance of the same template
      int? queueOrder;
      int? habitsOrder;
      int? tasksOrder;
      try {
        queueOrder = await InstanceOrderService.getOrderFromPreviousInstance(
            instance.templateId, 'queue', userId);
        habitsOrder = await InstanceOrderService.getOrderFromPreviousInstance(
            instance.templateId, 'habits', userId);
        tasksOrder = await InstanceOrderService.getOrderFromPreviousInstance(
            instance.templateId, 'tasks', userId);
      } catch (e) {
        // If order lookup fails, continue with null values (will use default sorting)
      }
      // Create next instance data
      final nextInstanceData = createActivityInstanceRecordData(
        templateId: instance.templateId,
        dueDate: nextBelongsToDate, // dueDate = start of window
        dueTime: instance.templateDueTime,
        status: 'pending',
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        isActive: true,
        templateName: instance.templateName,
        templateCategoryId: instance.templateCategoryId,
        templateCategoryName: instance.templateCategoryName,
        templateCategoryType: instance.templateCategoryType,
        templatePriority: instance.templatePriority,
        templateTrackingType: instance.templateTrackingType,
        templateTarget: instance.templateTarget,
        templateUnit: instance.templateUnit,
        templateDescription: instance.templateDescription,
        templateTimeEstimateMinutes: instance.templateTimeEstimateMinutes,
        templateShowInFloatingTimer: instance.templateShowInFloatingTimer,
        templateIsRecurring: instance.templateIsRecurring,
        templateEveryXValue: instance.templateEveryXValue,
        templateEveryXPeriodType: instance.templateEveryXPeriodType,
        templateTimesPerPeriod: instance.templateTimesPerPeriod,
        templatePeriodType: instance.templatePeriodType,
        dayState: 'open',
        belongsToDate: nextBelongsToDate,
        windowEndDate: nextWindowEndDate,
        windowDuration: instance.windowDuration,
        // Inherit order from previous instance
        queueOrder: queueOrder,
        habitsOrder: habitsOrder,
        tasksOrder: tasksOrder,
      );
      // Add to batch
      final nextInstanceRef =
          ActivityInstanceRecord.collectionForUser(userId).doc();
      batch.set(nextInstanceRef, nextInstanceData);
    } catch (e) {
      // Don't rethrow - we don't want to fail the entire batch
    }
  }

  /// Create daily progress record for a specific date
  static Future<void> _createDailyProgressRecord(
    String userId,
    DateTime targetDate,
  ) async {
    final normalizedDate =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    // Check if record already exists
    final existingQuery = DailyProgressRecord.collectionForUser(userId)
        .where('date', isEqualTo: normalizedDate);
    final existingSnapshot = await existingQuery.get();
    if (existingSnapshot.docs.isNotEmpty) {
      return;
    }
    // Get all habit instances (we'll filter them using the shared calculator)
    final allInstancesQuery = ActivityInstanceRecord.collectionForUser(userId)
        .where('templateCategoryType', isEqualTo: 'habit');
    final allInstancesSnapshot = await allInstancesQuery.get();
    final allInstances = allInstancesSnapshot.docs
        .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
        .toList();
    // Get all task instances for the target date (using ActivityInstanceRecord)
    final allTaskInstancesQuery =
        ActivityInstanceRecord.collectionForUser(userId)
            .where('templateCategoryType', isEqualTo: 'task');
    final allTaskInstancesSnapshot = await allTaskInstancesQuery.get();
    final allTaskInstances = allTaskInstancesSnapshot.docs
        .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
        .toList();
    // Get categories for calculation
    final categoriesQuery = CategoryRecord.collectionForUser(userId)
        .where('categoryType', isEqualTo: 'habit');
    final categoriesSnapshot = await categoriesQuery.get();
    final categories = categoriesSnapshot.docs
        .map((doc) => CategoryRecord.fromSnapshot(doc))
        .toList();
    // Use the SAME calculation as Queue page via shared DailyProgressCalculator
    // No need for includeSkippedForComputation since instances are still pending
    final calculationResult =
        await DailyProgressCalculator.calculateDailyProgress(
      userId: userId,
      targetDate: normalizedDate,
      allInstances: allInstances,
      categories: categories,
      taskInstances: allTaskInstances,
    );
    final targetPoints = calculationResult['target'] as double;
    final earnedPoints = calculationResult['earned'] as double;
    final completionPercentage = calculationResult['percentage'] as double;
    final instances =
        calculationResult['instances'] as List<ActivityInstanceRecord>;
    final taskInstances =
        calculationResult['taskInstances'] as List<ActivityInstanceRecord>;
    // Use the full math set for totals and category breakdowns
    final allForMath =
        calculationResult['allForMath'] as List<ActivityInstanceRecord>;
    final allTasksForMath =
        calculationResult['allTasksForMath'] as List<ActivityInstanceRecord>;
    // Extract separate breakdowns for analytics
    final taskTarget = calculationResult['taskTarget'] as double;
    final taskEarned = calculationResult['taskEarned'] as double;
    if (instances.isEmpty && taskInstances.isEmpty) {
      // Still create a progress record with 0 values for tracking
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
    for (final category in categories) {
      final categoryAll = allForMath
          .where((i) => i.templateCategoryId == category.reference.id)
          .toList();
      if (categoryAll.isNotEmpty) {
        final categoryCompleted = completedOnDate
            .where((i) => i.templateCategoryId == category.reference.id)
            .toList();
        final categoryTarget =
            PointsService.calculateTotalDailyTarget(categoryAll);
        final categoryEarned = await PointsService.calculateTotalPointsEarned(
            categoryCompleted, userId);
        categoryBreakdown[category.reference.id] = {
          'target': categoryTarget,
          'earned': categoryEarned,
          'completed': categoryCompleted.length,
          'total': categoryAll.length,
        };
      }
    }
    // Extract breakdown data from calculation result
    final habitBreakdown =
        calculationResult['habitBreakdown'] as List<Map<String, dynamic>>? ??
            [];
    final taskBreakdown =
        calculationResult['taskBreakdown'] as List<Map<String, dynamic>>? ?? [];
    // Calculate score for the target date (yesterday) and cumulative at end of day
    double dailyScoreGain = 0.0;
    double cumulativeScoreAtEndOfDay = 0.0;
    Map<String, dynamic> cumulativeScoreData = {};

    try {
      // Calculate score for target date using TodayScoreCalculator
      final scoreData = await TodayScoreCalculator.calculateTodayScore(
        userId: userId,
        completionPercentage: completionPercentage,
        pointsEarned: earnedPoints,
        categories: categories,
        habitInstances: allForMath,
      );
      dailyScoreGain = (scoreData['todayScore'] as num?)?.toDouble() ?? 0.0;

      // Get cumulative score at START of target day (end of day before)
      final dayBeforeTarget = normalizedDate.subtract(const Duration(days: 1));
      final dayBeforeRecords =
          await DailyProgressQueryService.queryDailyProgress(
        userId: userId,
        startDate: dayBeforeTarget,
        endDate: dayBeforeTarget,
        orderDescending: false,
      );
      double cumulativeAtStartOfTargetDay = 0.0;
      if (dayBeforeRecords.isNotEmpty) {
        final dayBeforeRecord = dayBeforeRecords.first;
        if (dayBeforeRecord.cumulativeScoreSnapshot > 0) {
          cumulativeAtStartOfTargetDay =
              dayBeforeRecord.cumulativeScoreSnapshot;
        } else if (dayBeforeRecord.hasDailyScoreGain()) {
          // Calculate backwards if no snapshot
          final dayBeforeThat =
              dayBeforeTarget.subtract(const Duration(days: 1));
          final dayBeforeThatRecords =
              await DailyProgressQueryService.queryDailyProgress(
            userId: userId,
            startDate: dayBeforeThat,
            endDate: dayBeforeThat,
            orderDescending: false,
          );
          if (dayBeforeThatRecords.isNotEmpty) {
            final dayBeforeThatRecord = dayBeforeThatRecords.first;
            if (dayBeforeThatRecord.cumulativeScoreSnapshot > 0) {
              cumulativeAtStartOfTargetDay =
                  dayBeforeThatRecord.cumulativeScoreSnapshot +
                      dayBeforeRecord.dailyScoreGain;
            }
          }
        }
      }

      // If still zero, try UserProgressStats as fallback
      if (cumulativeAtStartOfTargetDay == 0.0) {
        final userStats =
            await CumulativeScoreService.getCumulativeScore(userId);
        if (userStats != null && userStats.cumulativeScore > 0) {
          // Subtract today's gain to get baseline
          cumulativeAtStartOfTargetDay =
              (userStats.cumulativeScore - userStats.lastDailyGain)
                  .clamp(0.0, double.infinity);
        }
      }

      // Calculate cumulative at end of target day
      cumulativeScoreAtEndOfDay =
          (cumulativeAtStartOfTargetDay + dailyScoreGain)
              .clamp(0.0, double.infinity);

      // Also update UserProgressStatsRecord for consistency
      cumulativeScoreData = await CumulativeScoreService.updateCumulativeScore(
        userId,
        completionPercentage,
        normalizedDate,
        earnedPoints,
        categoryNeglectPenalty:
            (scoreData['categoryNeglectPenalty'] as num?)?.toDouble() ?? 0.0,
      );

      // Show bonus notifications
      BonusNotificationFormatter.showBonusNotifications(cumulativeScoreData);

      // Show milestone achievements
      final newMilestones =
          cumulativeScoreData['newMilestones'] as List<dynamic>? ?? [];
      if (newMilestones.isNotEmpty) {
        final milestoneValues = newMilestones.map((m) => m as int).toList();
        MilestoneToastService.showMultipleMilestones(milestoneValues);
      }
    } catch (e) {
      // Continue without cumulative score if calculation fails
      // Use fallback: calculate from UserProgressStats if available
      try {
        final userStats =
            await CumulativeScoreService.getCumulativeScore(userId);
        if (userStats != null) {
          cumulativeScoreAtEndOfDay = userStats.cumulativeScore;
          dailyScoreGain = userStats.lastDailyGain;
        }
      } catch (_) {
        // If all fails, use zeros
      }
    }

    // Update single-document score history to ensure graph continuity
    try {
      await ScoreHistoryService.updateScoreHistoryDocument(
        userId: userId,
        cumulativeScore: cumulativeScoreAtEndOfDay,
        todayScore: dailyScoreGain,
      );
    } catch (e) {
      // Continue even if history update fails
    }

    // Create the daily progress record
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
      cumulativeScoreSnapshot: cumulativeScoreAtEndOfDay,
      dailyScoreGain: dailyScoreGain,
      createdAt: DateTime.now(),
    );
    await DailyProgressRecord.collectionForUser(userId).add(progressData);
  }

  /// Check if day-end processing is needed
  /// Returns true if last processing was more than 24 hours ago
  /// Simplified version - no longer uses Index 3 query
  static Future<bool> shouldProcessDayEnd(String userId) async {
    try {
      // Simplified check: query all habit instances and filter in memory
      // This avoids needing Index 3 for historical edit functionality
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final normalizedYesterday =
          DateTime(yesterday.year, yesterday.month, yesterday.day);
      try {
        final query = ActivityInstanceRecord.collectionForUser(userId)
            .where('templateCategoryType', isEqualTo: 'habit');
        final snapshot = await query.limit(50).get(); // Get a reasonable sample
        // Filter in memory for open instances from yesterday or earlier
        final hasOpenInstance = snapshot.docs.any((doc) {
          final instance = ActivityInstanceRecord.fromSnapshot(doc);
          if (instance.dayState != 'open') return false;
          if (instance.belongsToDate == null) return false;
          final belongsToDateOnly = DateTime(
            instance.belongsToDate!.year,
            instance.belongsToDate!.month,
            instance.belongsToDate!.day,
          );
          return belongsToDateOnly.isBefore(normalizedYesterday) ||
              belongsToDateOnly.isAtSameMomentAs(normalizedYesterday);
        });
        return hasOpenInstance;
      } catch (e) {
        // If query fails, return false (don't process day-end)
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Process day-end for all users (admin function)
  static Future<void> processDayEndForAllUsers() async {
    // This would require a different approach since we can't query all users
    // In a real implementation, this might use Cloud Functions or a scheduled job
  }

  /// Get the next day-end processing time for a user
  static DateTime getNextDayEndTime() {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    if (now.isBefore(todayMidnight)) {
      return todayMidnight;
    } else {
      final tomorrow = now.add(const Duration(days: 1));
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    }
  }

  /// Check if we're within the grace period after midnight
  static bool isWithinGracePeriod() {
    // Grace handling is no longer needed
    return false;
  }

  /// Ensure all active habits have at least one pending instance
  /// This handles cases where instance generation failed or instances are missing
  /// Also fixes stuck instances where completed instances from the past don't have subsequent instances
  /// This is part of day-end processing and should always run
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

      final today = DateService.todayStart;
      final yesterday = DateService.yesterdayStart;

      for (final habit in activeHabits) {
        // Check if there's at least one pending instance for this habit
        final pendingQuery = ActivityInstanceRecord.collectionForUser(userId)
            .where('templateId', isEqualTo: habit.reference.id)
            .where('status', isEqualTo: 'pending')
            .orderBy('belongsToDate', descending: true)
            .limit(50); // Get more to filter client-side
        final pendingSnapshot = await pendingQuery.get();
        final pendingInstances = pendingSnapshot.docs
            .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
            .toList();

        // CRITICAL: Check if there's a pending instance for yesterday
        // If yes, do NOT auto-skip it or generate today's instance
        // User must confirm yesterday's status first
        final yesterdayPending = pendingInstances.where((inst) {
          if (inst.belongsToDate != null) {
            final belongsToDateOnly = DateTime(
              inst.belongsToDate!.year,
              inst.belongsToDate!.month,
              inst.belongsToDate!.day,
            );
            if (belongsToDateOnly.isAtSameMomentAs(yesterday)) {
              return true;
            }
          }
          // Also check windowEndDate - if window ended yesterday, it belongs to yesterday
          if (inst.windowEndDate != null) {
            final windowEndDateOnly = DateTime(
              inst.windowEndDate!.year,
              inst.windowEndDate!.month,
              inst.windowEndDate!.day,
            );
            if (windowEndDateOnly.isAtSameMomentAs(yesterday)) {
              return true;
            }
          }
          return false;
        }).toList();

        // If there's a pending instance for yesterday, do NOT generate today's instance
        // This preserves the rule: new instances are generated only on completion/skip
        if (yesterdayPending.isNotEmpty) {
          // Still clean up instances that are strictly before yesterday (not yesterday itself)
          final pastPendingInstances = pendingInstances.where((inst) {
            if (inst.belongsToDate != null) {
              final belongsToDateOnly = DateTime(
                inst.belongsToDate!.year,
                inst.belongsToDate!.month,
                inst.belongsToDate!.day,
              );
              return belongsToDateOnly.isBefore(yesterday);
            }
            if (inst.windowEndDate != null) {
              final windowEndDateOnly = DateTime(
                inst.windowEndDate!.year,
                inst.windowEndDate!.month,
                inst.windowEndDate!.day,
              );
              return windowEndDateOnly.isBefore(yesterday);
            }
            return false;
          }).toList();

          // Skip only instances strictly before yesterday (not yesterday itself)
          for (final pastInstance in pastPendingInstances) {
            try {
              final windowEndDate = pastInstance.windowEndDate;
              if (windowEndDate != null) {
                final windowEndDateOnly = DateTime(
                  windowEndDate.year,
                  windowEndDate.month,
                  windowEndDate.day,
                );
                if (windowEndDateOnly.isBefore(yesterday)) {
                  // Past instance that should be skipped
                  await ActivityInstanceService.skipInstance(
                    instanceId: pastInstance.reference.id,
                    skippedAt: windowEndDateOnly,
                  );
                }
              }
            } catch (e) {
              // Error cleaning up past instance
            }
          }
          continue; // Do NOT generate today's instance - wait for user to handle yesterday
        }

        // Check if there's already a pending instance for today or future dates
        final todayOrFuturePending = pendingInstances.where((inst) {
          if (inst.belongsToDate != null) {
            final belongsToDateOnly = DateTime(
              inst.belongsToDate!.year,
              inst.belongsToDate!.month,
              inst.belongsToDate!.day,
            );
            return belongsToDateOnly.isAtSameMomentAs(today) ||
                belongsToDateOnly.isAfter(today);
          }
          // Also check windowEndDate
          if (inst.windowEndDate != null) {
            final windowEndDateOnly = DateTime(
              inst.windowEndDate!.year,
              inst.windowEndDate!.month,
              inst.windowEndDate!.day,
            );
            return windowEndDateOnly.isAtSameMomentAs(today) ||
                windowEndDateOnly.isAfter(today);
          }
          return false;
        }).toList();

        // If there's already a pending instance for today or future, skip creation
        if (todayOrFuturePending.isNotEmpty) {
          // Clean up duplicate past pending instances if found (strictly before yesterday)
          final pastPendingInstances = pendingInstances.where((inst) {
            if (inst.belongsToDate != null) {
              final belongsToDateOnly = DateTime(
                inst.belongsToDate!.year,
                inst.belongsToDate!.month,
                inst.belongsToDate!.day,
              );
              return belongsToDateOnly.isBefore(yesterday);
            }
            if (inst.windowEndDate != null) {
              final windowEndDateOnly = DateTime(
                inst.windowEndDate!.year,
                inst.windowEndDate!.month,
                inst.windowEndDate!.day,
              );
              return windowEndDateOnly.isBefore(yesterday);
            }
            return false;
          }).toList();

          // Skip past pending instances that should have been auto-skipped
          for (final pastInstance in pastPendingInstances) {
            try {
              final windowEndDate = pastInstance.windowEndDate;
              if (windowEndDate != null) {
                final windowEndDateOnly = DateTime(
                  windowEndDate.year,
                  windowEndDate.month,
                  windowEndDate.day,
                );
                if (windowEndDateOnly.isBefore(yesterday)) {
                  // Past instance that should be skipped
                  await ActivityInstanceService.skipInstance(
                    instanceId: pastInstance.reference.id,
                    skippedAt: windowEndDateOnly,
                  );
                }
              }
            } catch (e) {
              // Error cleaning up past instance
            }
          }
          continue; // Skip creating new instance
        }

        // No pending instance for today/future/yesterday found - need to generate one
        // This only happens when there are NO pending instances at all for this template

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

              // If the window ended before yesterday, use bulk skip to fill the gap
              if (windowEndDateOnly.isBefore(yesterday)) {
                // Get template for bulk skip
                final templateRef = ActivityRecord.collectionForUser(userId)
                    .doc(habit.reference.id);
                final template =
                    await ActivityRecord.getDocumentOnce(templateRef);

                // Use bulk skip to efficiently fill gap up to yesterday
                await ActivityInstanceService
                    .bulkSkipExpiredInstancesWithBatches(
                  oldestInstance: mostRecentInstance,
                  template: template,
                  userId: userId,
                );
                // Instance generated via bulk skip
              } else {
                // Window ended recently (yesterday or later), but no pending instance exists
                // This should be rare - only if instance was deleted or status changed externally
                // Generate next instance normally
                await ActivityInstanceService.skipInstance(
                  instanceId: mostRecentInstance.reference.id,
                  skippedAt: windowEndDate,
                );
              }
            } catch (e) {
              // Error generating instance for habit
            }
          } else {
            // No windowEndDate - create initial instance
            try {
              await ActivityInstanceService.createActivityInstance(
                templateId: habit.reference.id,
                template: habit,
                userId: userId,
              );
            } catch (e) {
              // Error creating initial instance for habit
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
          } catch (e) {
            // Error creating initial instance for habit
          }
        }
      }
    } catch (e) {
      // Error ensuring pending instances exist
    }
  }
}
