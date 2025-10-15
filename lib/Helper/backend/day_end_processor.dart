import 'package:habit_tracker/Helper/backend/points_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for processing day-end operations on habits
/// Auto-closes pending habits and creates daily progress snapshots
class DayEndProcessor {
  static const int _gracePeriodMinutes = 5; // 5 minutes after midnight

  /// Process day-end for a specific user
  /// This should be called at midnight (user's local time) or on app start
  static Future<void> processDayEnd({
    required String userId,
    DateTime? targetDate,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // Use targetDate if provided, otherwise use yesterday
    final processDate = targetDate ?? yesterday;

    print(
        'DayEndProcessor: Processing day-end for user $userId, date: $processDate');

    try {
      // Step 1: Close all open habit instances for the target date
      await _closeOpenHabitInstances(userId, processDate);

      // Step 2: Create daily progress record for the target date
      await _createDailyProgressRecord(userId, processDate);

      print('DayEndProcessor: Successfully processed day-end for $processDate');
    } catch (e) {
      print('DayEndProcessor: Error processing day-end: $e');
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
    final now = DateTime.now();

    for (final instance in instances) {
      // Mark as skipped (preserve currentValue for partial completions)
      final instanceRef = instance.reference;
      batch.update(instanceRef, {
        'status': 'skipped',
        'skippedAt': now,
        'lastUpdated': now,
      });

      print(
          'DayEndProcessor: Marking instance ${instance.templateName} as skipped (window expired)');
      print('  - Final currentValue: ${instance.currentValue}');
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

      // Create next instance data
      final nextInstanceData = createActivityInstanceRecordData(
        templateId: instance.templateId,
        dueDate: nextBelongsToDate, // dueDate = start of window
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
        templateEveryXValue: instance.templateEveryXValue,
        templateEveryXPeriodType: instance.templateEveryXPeriodType,
        templateTimesPerPeriod: instance.templateTimesPerPeriod,
        templatePeriodType: instance.templatePeriodType,
        completionStatus: 'pending',
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

    // Get all habit instances that were completed or skipped on the target date
    // This includes both instances that belonged to that date and were completed then,
    // and instances that were completed on that date regardless of their window
    final completedInstancesQuery =
        ActivityInstanceRecord.collectionForUser(userId)
            .where('templateCategoryType', isEqualTo: 'habit')
            .where('status', isEqualTo: 'completed')
            .where('completedAt', isGreaterThanOrEqualTo: normalizedDate)
            .where('completedAt',
                isLessThan: normalizedDate.add(const Duration(days: 1)));

    final skippedInstancesQuery =
        ActivityInstanceRecord.collectionForUser(userId)
            .where('templateCategoryType', isEqualTo: 'habit')
            .where('status', isEqualTo: 'skipped')
            .where('skippedAt', isGreaterThanOrEqualTo: normalizedDate)
            .where('skippedAt',
                isLessThan: normalizedDate.add(const Duration(days: 1)));

    final completedSnapshot = await completedInstancesQuery.get();
    final skippedSnapshot = await skippedInstancesQuery.get();

    final completedInstances = completedSnapshot.docs
        .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
        .toList();
    final skippedInstances = skippedSnapshot.docs
        .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
        .toList();

    final instances = [...completedInstances, ...skippedInstances];

    if (instances.isEmpty) {
      print('DayEndProcessor: No habit instances found for $normalizedDate');
      return;
    }

    // Get categories for point calculation
    final categoriesQuery = CategoryRecord.collectionForUser(userId)
        .where('categoryType', isEqualTo: 'habit');

    final categoriesSnapshot = await categoriesQuery.get();
    final categories = categoriesSnapshot.docs
        .map((doc) => CategoryRecord.fromSnapshot(doc))
        .toList();

    // Calculate daily progress using PointsService
    final targetPoints =
        PointsService.calculateTotalDailyTarget(instances, categories);
    final earnedPoints =
        PointsService.calculateTotalPointsEarned(instances, categories);
    final completionPercentage = PointsService.calculateDailyPerformancePercent(
        earnedPoints, targetPoints);

    // Count habit statistics
    int totalHabits = instances.length;
    int completedHabits =
        instances.where((i) => i.completionStatus == 'completed').length;
    int partialHabits = instances
        .where((i) =>
            i.completionStatus == 'skipped' &&
            i.currentValue != null &&
            (i.currentValue is num ? (i.currentValue as num) > 0 : false))
        .length;
    int skippedHabits = instances
        .where((i) =>
            i.completionStatus == 'skipped' &&
            (i.currentValue == null ||
                (i.currentValue is num ? (i.currentValue as num) == 0 : true)))
        .length;

    // Create category breakdown
    final categoryBreakdown = <String, Map<String, dynamic>>{};
    for (final category in categories) {
      final categoryInstances =
          instances.where((i) => i.templateCategoryId == category.reference.id);
      if (categoryInstances.isNotEmpty) {
        final categoryTarget = PointsService.calculateTotalDailyTarget(
            categoryInstances.toList(), [category]);
        final categoryEarned = PointsService.calculateTotalPointsEarned(
            categoryInstances.toList(), [category]);

        categoryBreakdown[category.reference.id] = {
          'target': categoryTarget,
          'earned': categoryEarned,
          'completed': categoryInstances
              .where((i) => i.completionStatus == 'completed')
              .length,
          'total': categoryInstances.length,
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
      categoryBreakdown: categoryBreakdown,
      createdAt: DateTime.now(),
    );

    await DailyProgressRecord.collectionForUser(userId).add(progressData);

    print('DayEndProcessor: Created daily progress record for $normalizedDate');
    print('  - Target: $targetPoints points');
    print('  - Earned: $earnedPoints points');
    print('  - Percentage: ${completionPercentage.toStringAsFixed(1)}%');
    print(
        '  - Habits: $completedHabits/$totalHabits completed, $partialHabits partial, $skippedHabits skipped');
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
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return tomorrow.add(Duration(minutes: _gracePeriodMinutes));
  }

  /// Check if we're within the grace period after midnight
  static bool isWithinGracePeriod() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final gracePeriodEnd = midnight.add(Duration(minutes: _gracePeriodMinutes));

    return now.isBefore(gracePeriodEnd);
  }
}
