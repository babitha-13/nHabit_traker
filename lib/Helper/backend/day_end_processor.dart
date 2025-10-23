import 'package:habit_tracker/Helper/backend/points_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/daily_progress_calculator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';

/// Service for processing day-end operations on habits
/// Auto-closes pending habits and creates daily progress snapshots
class DayEndProcessor {
  static const int _gracePeriodMinutes = 0; // not used with shifted boundary

  /// Process day-end for a specific user
  /// This should be called at the shifted boundary (2 AM local) or on app start
  static Future<void> processDayEnd({
    required String userId,
    DateTime? targetDate,
  }) async {
    // Use targetDate if provided, otherwise use latest processable shifted date
    final processDate = targetDate ?? DateService.latestProcessableShiftedDate;

    print(
        'DayEndProcessor: Processing day-end for user $userId, date: $processDate');

    try {
      // Step 1: Update lastDayValue for active windowed habits
      await _updateLastDayValues(userId, processDate);

      // Step 2: Create daily progress record BEFORE closing instances
      // This preserves the exact values shown in Queue page
      await _createDailyProgressRecord(userId, processDate);

      // Step 3: Close all open habit instances for the target date
      await _closeOpenHabitInstances(userId, processDate);

      print('DayEndProcessor: Successfully processed day-end for $processDate');
    } catch (e) {
      print('DayEndProcessor: Error processing day-end: $e');
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
    final query = ActivityInstanceRecord.collectionForUser(userId)
        .where('templateCategoryType', isEqualTo: 'habit')
        .where('status', isEqualTo: 'pending')
        .where('windowEndDate', isGreaterThan: normalizedDate);

    final querySnapshot = await query.get();
    final instances = querySnapshot.docs
        .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
        .toList();

    print(
        'DayEndProcessor: Found ${instances.length} active windowed habits to update lastDayValue');

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

      print(
          'DayEndProcessor: Updated lastDayValue for ${instance.templateName} to ${instance.currentValue}');
    }

    await batch.commit();
    print(
        'DayEndProcessor: Updated lastDayValue for ${instances.length} active windowed habits');
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
    final query = ActivityInstanceRecord.collectionForUser(userId)
        .where('templateCategoryType', isEqualTo: 'habit')
        .where('status', isEqualTo: 'pending')
        .where('windowEndDate', isLessThanOrEqualTo: normalizedDate);

    final querySnapshot = await query.get();
    final instances = querySnapshot.docs
        .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
        .toList();

    print(
        'DayEndProcessor: Found ${instances.length} habit instances with expired windows for $normalizedDate');

    // Debug: Log each instance being processed
    for (final instance in instances) {
      print('DayEndProcessor: Processing instance ${instance.templateName}');
      print('  - Instance ID: ${instance.reference.id}');
      print('  - Due Date: ${instance.dueDate}');
      print('  - Window End Date: ${instance.windowEndDate}');
      print('  - Current Value: ${instance.currentValue}');
      print('  - Status: ${instance.status}');
    }

    final batch = FirebaseFirestore.instance.batch();
    // Use the targetDate being processed (normalizedDate) for skippedAt
    // With shifted boundary, Oct 15 window closes at Oct 16 2 AM
    final skippedAtDate = normalizedDate;

    for (final instance in instances) {
      // Mark as skipped (preserve currentValue for partial completions)
      final instanceRef = instance.reference;
      batch.update(instanceRef, {
        'status': 'skipped',
        'skippedAt': skippedAtDate, // Use the date being processed
        'lastUpdated': DateTime.now(), // Real time for audit trail
      });

      print(
          'DayEndProcessor: Marking instance ${instance.templateName} as skipped (window expired)');
      print('  - Final currentValue: ${instance.currentValue}');
      print('  - skippedAt will be set to: $skippedAtDate');
      print('  - Will be marked as skipped with preserved value');

      // Generate next instance for this habit
      await _generateNextInstance(instance, userId, batch);
    }

    if (instances.isNotEmpty) {
      await batch.commit();
      print(
          'DayEndProcessor: Processed ${instances.length} expired habit instances');
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
      final existingQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateId', isEqualTo: instance.templateId)
          .where('belongsToDate', isEqualTo: nextBelongsToDate)
          .where('status', isEqualTo: 'pending');

      final existingInstances = await existingQuery.get();

      if (existingInstances.docs.isNotEmpty) {
        print(
            'DayEndProcessor: Instance already exists for ${instance.templateName} on $nextBelongsToDate, skipping creation');
        return;
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
      );

      // Add to batch
      final nextInstanceRef =
          ActivityInstanceRecord.collectionForUser(userId).doc();
      batch.set(nextInstanceRef, nextInstanceData);

      print(
          'DayEndProcessor: Generated next instance for ${instance.templateName} (${nextBelongsToDate} - ${nextWindowEndDate})');
      print('  - New instance dueDate: $nextBelongsToDate');
      print('  - New instance windowEndDate: $nextWindowEndDate');
      print('  - New instance status: pending');
      print('  - New instance currentValue: null (fresh start)');
    } catch (e) {
      print(
          'DayEndProcessor: Error generating next instance for ${instance.templateName}: $e');
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
      print(
          'DayEndProcessor: Daily progress record already exists for $normalizedDate');
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
    final habitTarget = calculationResult['habitTarget'] as double;
    final habitEarned = calculationResult['habitEarned'] as double;
    final taskTarget = calculationResult['taskTarget'] as double;
    final taskEarned = calculationResult['taskEarned'] as double;

    print(
        'DayEndProcessor: Found ${instances.length} habit instances and ${taskInstances.length} task instances for $normalizedDate');

    if (instances.isEmpty && taskInstances.isEmpty) {
      // Still create a progress record with 0 values for tracking
      print(
          'DayEndProcessor: No habits or tasks for this day, creating empty progress record');
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
      print(
          'DayEndProcessor: Created empty progress record for $normalizedDate');
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
      createdAt: DateTime.now(),
    );

    await DailyProgressRecord.collectionForUser(userId).add(progressData);

    print('DayEndProcessor: Created daily progress record for $normalizedDate');
    print(
        '  - Total Target: $targetPoints points (Habits: $habitTarget, Tasks: $taskTarget)');
    print(
        '  - Total Earned: $earnedPoints points (Habits: $habitEarned, Tasks: $taskEarned)');
    print('  - Percentage: ${completionPercentage.toStringAsFixed(1)}%');
    print(
        '  - Habit Counts -> total: $totalHabits, completed: $completedHabits, partial: $partialHabits, skipped: $skippedHabits');
    print(
        '  - Task Counts -> total: $totalTasks, completed: $completedTasks, partial: $partialTasks, skipped: $skippedTasks');
  }

  /// Check if day-end processing is needed
  /// Returns true if last processing was more than 24 hours ago
  static Future<bool> shouldProcessDayEnd(String userId) async {
    try {
      // Check if we have any open habit instances from yesterday or earlier
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final normalizedYesterday =
          DateTime(yesterday.year, yesterday.month, yesterday.day);

      final query = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('dayState', isEqualTo: 'open')
          .where('belongsToDate', isLessThan: normalizedYesterday);

      final snapshot = await query.limit(1).get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('DayEndProcessor: Error checking if processing needed: $e');
      return false;
    }
  }

  /// Process day-end for all users (admin function)
  static Future<void> processDayEndForAllUsers() async {
    // This would require a different approach since we can't query all users
    // In a real implementation, this might use Cloud Functions or a scheduled job
    print(
        'DayEndProcessor: processDayEndForAllUsers not implemented - requires Cloud Functions');
  }

  /// Get the next day-end processing time for a user
  static DateTime getNextDayEndTime() {
    return DateService.nextShiftedBoundary(DateTime.now());
  }

  /// Check if we're within the grace period after midnight
  static bool isWithinGracePeriod() {
    // With shifted boundary, grace handling is no longer needed
    return false;
  }
}
