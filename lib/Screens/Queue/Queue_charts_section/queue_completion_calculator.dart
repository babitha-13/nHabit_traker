import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/today_points_service.dart';

/// Service class for calculating today's completion points (target/earned/percentage)
/// Uses TodayCompletionPointsService for consistency
class QueueProgressCalculator {
  /// Calculate progress for today's habits and tasks
  /// Uses shared TodayCompletionPointsService for consistency with historical data
  /// [optimistic] - If true, calculates instantly from local data without Firestore queries
  static Future<Map<String, double>> calculateProgress({
    required List<ActivityInstanceRecord> instances,
    required List<CategoryRecord> categories,
    required String userId,
    bool optimistic = false,
  }) async {
    return await TodayCompletionPointsService.calculateTodayCompletionPoints(
      userId: userId,
      instances: instances,
      categories: categories,
      optimistic: optimistic,
    );
  }
}
