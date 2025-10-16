import 'package:habit_tracker/Helper/backend/points_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';

/// Service for editing historical habit data
/// Allows users to correct past day entries within a limited time window
class HistoricalEditService {
  static const int _editWindowDays = 30; // Can edit past 30 days

  /// Get all habit instances for a specific date
  static Future<List<ActivityInstanceRecord>> getHabitInstancesForDate({
    required String userId,
    required DateTime date,
  }) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);

    final query = ActivityInstanceRecord.collectionForUser(userId)
        .where('templateCategoryType', isEqualTo: 'habit')
        .where('belongsToDate', isEqualTo: normalizedDate)
        .where('dayState',
            isEqualTo: 'closed'); // Only closed (historical) instances

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
        .toList();
  }

  /// Check if a date is within the edit window
  static bool canEditDate(DateTime date) {
    final now = DateTime.now();
    final daysDifference = now.difference(date).inDays;
    return daysDifference <= _editWindowDays;
  }

  /// Update a habit instance's completion status and progress
  static Future<void> updateHabitInstance({
    required String instanceId,
    required String userId,
    String? newStatus,
    dynamic newCurrentValue,
  }) async {
    // Validate status
    if (newStatus != null &&
        !['pending', 'completed', 'skipped'].contains(newStatus)) {
      throw ArgumentError('Invalid status: $newStatus');
    }

    final instanceRef =
        ActivityInstanceRecord.collectionForUser(userId).doc(instanceId);
    final instanceDoc = await instanceRef.get();

    if (!instanceDoc.exists) {
      throw Exception('Habit instance not found');
    }

    final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

    // Validate that this is a closed habit instance
    if (instance.templateCategoryType != 'habit' ||
        instance.dayState != 'closed') {
      throw Exception('Can only edit closed habit instances');
    }

    // Validate that the date is within edit window
    if (instance.belongsToDate != null &&
        !canEditDate(instance.belongsToDate!)) {
      throw Exception('Cannot edit instances older than $_editWindowDays days');
    }

    // Prepare update data
    final updateData = <String, dynamic>{
      'lastUpdated': DateTime.now(),
    };

    if (newStatus != null) {
      updateData['status'] = newStatus;
    }

    if (newCurrentValue != null) {
      updateData['currentValue'] = newCurrentValue;
    }

    // Update the instance
    await instanceRef.update(updateData);

    print('HistoricalEditService: Updated instance $instanceId');
    print('  - New status: ${newStatus ?? instance.status}');
    print('  - New value: ${newCurrentValue ?? instance.currentValue}');
  }

  /// Recalculate and update daily progress record for a specific date
  static Future<void> recalculateDailyProgress({
    required String userId,
    required DateTime date,
  }) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);

    // Get all habit instances for the date
    final instances = await getHabitInstancesForDate(
      userId: userId,
      date: normalizedDate,
    );

    if (instances.isEmpty) {
      print(
          'HistoricalEditService: No habit instances found for $normalizedDate');
      return;
    }

    // Get categories for point calculation
    final categoriesQuery = CategoryRecord.collectionForUser(userId)
        .where('categoryType', isEqualTo: 'habit');

    final categoriesSnapshot = await categoriesQuery.get();
    final categories = categoriesSnapshot.docs
        .map((doc) => CategoryRecord.fromSnapshot(doc))
        .toList();

    // Recalculate daily progress using PointsService
    final targetPoints =
        PointsService.calculateTotalDailyTarget(instances, categories);
    final earnedPoints =
        PointsService.calculateTotalPointsEarned(instances, categories);
    final completionPercentage = PointsService.calculateDailyPerformancePercent(
        earnedPoints, targetPoints);

    // Recalculate habit statistics
    int totalHabits = instances.length;
    int completedHabits =
        instances.where((i) => i.status == 'completed').length;
    int partialHabits = instances
        .where((i) =>
            i.status == 'skipped' &&
            i.currentValue != null &&
            (i.currentValue is num ? (i.currentValue as num) > 0 : false))
        .length;
    int skippedHabits = instances
        .where((i) =>
            i.status == 'skipped' &&
            (i.currentValue == null ||
                (i.currentValue is num ? (i.currentValue as num) == 0 : true)))
        .length;

    // Recalculate category breakdown
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
          'completed':
              categoryInstances.where((i) => i.status == 'completed').length,
          'total': categoryInstances.length,
        };
      }
    }

    // Find existing daily progress record
    final progressQuery = DailyProgressRecord.collectionForUser(userId)
        .where('date', isEqualTo: normalizedDate);

    final progressSnapshot = await progressQuery.get();

    if (progressSnapshot.docs.isEmpty) {
      // Create new record if it doesn't exist
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
        lastEditedAt: DateTime.now(),
      );

      await DailyProgressRecord.collectionForUser(userId).add(progressData);
      print(
          'HistoricalEditService: Created new daily progress record for $normalizedDate');
    } else {
      // Update existing record
      final progressDoc = progressSnapshot.docs.first;
      await progressDoc.reference.update({
        'targetPoints': targetPoints,
        'earnedPoints': earnedPoints,
        'completionPercentage': completionPercentage,
        'totalHabits': totalHabits,
        'completedHabits': completedHabits,
        'partialHabits': partialHabits,
        'skippedHabits': skippedHabits,
        'categoryBreakdown': categoryBreakdown,
        'lastEditedAt': DateTime.now(),
      });
      print(
          'HistoricalEditService: Updated daily progress record for $normalizedDate');
    }

    print(
        'HistoricalEditService: Recalculated daily progress for $normalizedDate');
    print('  - Target: $targetPoints points');
    print('  - Earned: $earnedPoints points');
    print('  - Percentage: ${completionPercentage.toStringAsFixed(1)}%');
    print(
        '  - Habits: $completedHabits/$totalHabits completed, $partialHabits partial, $skippedHabits skipped');
  }

  /// Get daily progress record for a specific date
  static Future<DailyProgressRecord?> getDailyProgress({
    required String userId,
    required DateTime date,
  }) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);

    final query = DailyProgressRecord.collectionForUser(userId)
        .where('date', isEqualTo: normalizedDate);

    final snapshot = await query.get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    return DailyProgressRecord.fromSnapshot(snapshot.docs.first);
  }

  /// Get available dates for editing (last 30 days with habit data)
  static Future<List<DateTime>> getEditableDates({
    required String userId,
  }) async {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: _editWindowDays));

    // Query for daily progress records in the last 30 days
    final query = DailyProgressRecord.collectionForUser(userId)
        .where('date', isGreaterThanOrEqualTo: thirtyDaysAgo)
        .orderBy('date', descending: true);

    final snapshot = await query.get();

    return snapshot.docs
        .map((doc) {
          final record = DailyProgressRecord.fromSnapshot(doc);
          return record.date;
        })
        .where((date) => date != null)
        .cast<DateTime>()
        .toList();
  }

  /// Validate that an instance can be edited
  static Future<bool> canEditInstance({
    required String instanceId,
    required String userId,
  }) async {
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(userId).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        return false;
      }

      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

      // Must be a habit instance
      if (instance.templateCategoryType != 'habit') {
        return false;
      }

      // Must be closed (historical)
      if (instance.dayState != 'closed') {
        return false;
      }

      // Must be within edit window
      if (instance.belongsToDate != null &&
          !canEditDate(instance.belongsToDate!)) {
        return false;
      }

      return true;
    } catch (e) {
      print(
          'HistoricalEditService: Error checking if instance can be edited: $e');
      return false;
    }
  }
}
