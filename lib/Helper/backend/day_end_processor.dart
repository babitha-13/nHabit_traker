import 'package:habit_tracker/Helper/backend/points_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/daily_progress_calculator.dart';
import 'package:habit_tracker/Helper/backend/cumulative_score_service.dart';
import 'package:habit_tracker/Helper/utils/score_bonus_toast_service.dart';
import 'package:habit_tracker/Helper/utils/milestone_toast_service.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';

/// Service for processing day-end operations on habits
/// Creates daily progress snapshots (status changes now require manual user confirmation)
class DayEndProcessor {
  /// Process day-end for a specific user
  /// [closeInstances] - If true, marks expired habit instances as skipped (requires user confirmation)
  /// Set to false to disable automatic status changes (automatic processing is disabled)
  static Future<void> processDayEnd({
    required String userId,
    DateTime? targetDate,
    bool closeInstances = false,
  }) async {
    // Use targetDate if provided, otherwise use yesterday's date
    final processDate = targetDate ?? DateService.yesterdayStart;
    try {
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
    // Extract breakdown data from calculation result
    final habitBreakdown =
        calculationResult['habitBreakdown'] as List<Map<String, dynamic>>? ??
            [];
    final taskBreakdown =
        calculationResult['taskBreakdown'] as List<Map<String, dynamic>>? ?? [];
    // Calculate category neglect penalty
    final categoryNeglectPenalty =
        CumulativeScoreService.calculateCategoryNeglectPenalty(
      categories,
      allForMath,
      normalizedDate,
    );

    // Calculate cumulative score
    Map<String, dynamic> cumulativeScoreData = {};
    try {
      cumulativeScoreData = await CumulativeScoreService.updateCumulativeScore(
        userId,
        completionPercentage,
        normalizedDate,
        earnedPoints,
        categoryNeglectPenalty: categoryNeglectPenalty,
      );

      // Show bonus notifications
      final bonuses = CumulativeScoreService.getBonusNotifications(
        cumulativeScoreData,
      );
      if (bonuses.isNotEmpty) {
        ScoreBonusToastService.showMultipleNotifications(bonuses);
      }

      // Show milestone achievements
      final newMilestones =
          cumulativeScoreData['newMilestones'] as List<dynamic>? ?? [];
      if (newMilestones.isNotEmpty) {
        final milestoneValues = newMilestones.map((m) => m as int).toList();
        MilestoneToastService.showMultipleMilestones(milestoneValues);
      }
    } catch (e) {
      // Continue without cumulative score if calculation fails
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
      cumulativeScoreSnapshot: cumulativeScoreData['cumulativeScore'] ?? 0.0,
      dailyScoreGain: cumulativeScoreData['dailyGain'] ?? 0.0,
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
}
