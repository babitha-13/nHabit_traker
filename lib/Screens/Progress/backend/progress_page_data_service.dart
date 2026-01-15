import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/daily_points_calculator.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/daily_progress_query_service.dart';

/// Service to fetch data needed by Progress page UI
/// Encapsulates Firestore access for progress page to maintain separation of concerns
class ProgressPageDataService {
  /// Fetch all instances needed for breakdown calculation
  /// Returns: {habits, tasks, categories}
  static Future<Map<String, dynamic>> fetchInstancesForBreakdown({
    required String userId,
  }) async {
    try {
      // Get all habit instances
      final habitQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit');
      final habitSnapshot = await habitQuery.get();
      final allHabits = habitSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      // Get all task instances
      final taskQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'task');
      final taskSnapshot = await taskQuery.get();
      final allTasks = taskSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      // Get categories
      final categoryQuery = CategoryRecord.collectionForUser(userId)
          .where('categoryType', isEqualTo: 'habit');
      final categorySnapshot = await categoryQuery.get();
      final categories = categorySnapshot.docs
          .map((doc) => CategoryRecord.fromSnapshot(doc))
          .toList();

      return {
        'habits': allHabits,
        'tasks': allTasks,
        'categories': categories,
      };
    } catch (e) {
      return {
        'habits': <ActivityInstanceRecord>[],
        'tasks': <ActivityInstanceRecord>[],
        'categories': <CategoryRecord>[],
      };
    }
  }

  /// Calculate breakdown for a specific date
  /// Returns: {habitBreakdown, taskBreakdown}
  static Future<Map<String, dynamic>> calculateBreakdownForDate({
    required String userId,
    required DateTime date,
  }) async {
    try {
      final instances = await fetchInstancesForBreakdown(userId: userId);
      final allHabits = instances['habits'] as List<ActivityInstanceRecord>;
      final allTasks = instances['tasks'] as List<ActivityInstanceRecord>;
      final categories = instances['categories'] as List<CategoryRecord>;

      // Calculate breakdown using the daily progress calculator
      final result = await DailyProgressCalculator.calculateDailyProgress(
        userId: userId,
        targetDate: date,
        allInstances: allHabits,
        categories: categories,
        taskInstances: allTasks,
      );

      return {
        'habitBreakdown':
            result['habitBreakdown'] as List<Map<String, dynamic>>? ?? [],
        'taskBreakdown':
            result['taskBreakdown'] as List<Map<String, dynamic>>? ?? [],
      };
    } catch (e) {
      return {
        'habitBreakdown': <Map<String, dynamic>>[],
        'taskBreakdown': <Map<String, dynamic>>[],
      };
    }
  }

  /// Fetch progress history for a date range
  /// Returns list of DailyProgressRecord sorted by date descending
  static Future<List<DailyProgressRecord>> fetchProgressHistory({
    required String userId,
    required int days,
  }) async {
    try {
      final endDate = DateService.currentDate;
      final startDate = endDate.subtract(Duration(days: days));
      return await DailyProgressQueryService.queryDailyProgress(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        orderDescending: true,
      );
    } catch (e) {
      return [];
    }
  }

  /// Fetch cumulative score history for the last 30 days
  /// Returns list of maps with 'date', 'score', 'gain'
  ///
  /// NOTE: Moved to `lib/Screens/Shared/cumulative_score_calculator.dart`
  /// to avoid duplication with Queue.
}
