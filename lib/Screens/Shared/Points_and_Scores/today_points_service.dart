import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/daily_points_calculator.dart';
import 'package:habit_tracker/Screens/Progress/Statemanagement/today_progress_state.dart';

/// Service for calculating and maintaining today's completion points (target/earned/percentage)
/// Separate from scoring logic - focuses only on completion metrics
/// Updates TodayProgressState with completion data only
class TodayCompletionPointsService {
  /// Calculate today's completion points from instances
  /// Returns: {target, earned, percentage}
  /// Updates TodayProgressState automatically
  static Future<Map<String, double>> calculateTodayCompletionPoints({
    required String userId,
    required List<ActivityInstanceRecord> instances,
    required List<CategoryRecord> categories,
    bool optimistic = false,
  }) async {
    // Separate habit and task instances
    final habitInstances = instances
        .where((inst) => inst.templateCategoryType == 'habit')
        .toList();
    final taskInstances =
        instances.where((inst) => inst.templateCategoryType == 'task').toList();

    Map<String, dynamic> progressData;

    if (optimistic) {
      // INSTANT UPDATE: Calculate from local data only (no Firestore queries)
      // This is now synchronous - returns immediately like an Excel sheet
      try {
        progressData = DailyProgressCalculator.calculateTodayProgressOptimistic(
          userId: userId,
          allInstances: habitInstances,
          categories: categories,
          taskInstances: taskInstances,
        );
      } catch (e) {
        // If optimistic calculation fails, fall back to full calculation
        // But don't await it - return zeros immediately to keep UI responsive
        progressData = {
          'target': 0.0,
          'earned': 0.0,
          'percentage': 0.0,
        };
        // Run full calculation in background
        DailyProgressCalculator.calculateTodayProgress(
          userId: userId,
          allInstances: habitInstances,
          categories: categories,
          taskInstances: taskInstances,
        ).then((fullData) {
          // Update state with full data when it arrives
          final target = (fullData['target'] as num?)?.toDouble() ?? 0.0;
          final earned = (fullData['earned'] as num?)?.toDouble() ?? 0.0;
          final percentage =
              (fullData['percentage'] as num?)?.toDouble() ?? 0.0;
          TodayProgressState().updateProgress(
            target: target,
            earned: earned,
            percentage: percentage,
          );
        }).catchError((_) {
          // Ignore errors in background calculation
        });
      }
    } else {
      // BACKEND RECONCILIATION: Use full calculation with Firestore
      try {
        progressData = await DailyProgressCalculator.calculateTodayProgress(
          userId: userId,
          allInstances: habitInstances,
          categories: categories,
          taskInstances: taskInstances,
        );
      } catch (e) {
        // Error in backend calculation - return zeros
        progressData = {
          'target': 0.0,
          'earned': 0.0,
          'percentage': 0.0,
        };
      }
    }

    final target = (progressData['target'] as num?)?.toDouble() ?? 0.0;
    final earned = (progressData['earned'] as num?)?.toDouble() ?? 0.0;
    final percentage = (progressData['percentage'] as num?)?.toDouble() ?? 0.0;

    // Publish to shared state for other pages
    TodayProgressState().updateProgress(
      target: target,
      earned: earned,
      percentage: percentage,
    );

    return {
      'target': target,
      'earned': earned,
      'percentage': percentage,
    };
  }

  /// Calculate today's completion points INSTANTLY (synchronous, no Firestore)
  /// Like an Excel sheet - calculates from instances already in memory
  /// Use this for immediate UI updates
  static Map<String, double> calculateTodayCompletionPointsSync({
    required String userId,
    required List<ActivityInstanceRecord> instances,
    required List<CategoryRecord> categories,
  }) {
    // Separate habit and task instances
    final habitInstances = instances
        .where((inst) => inst.templateCategoryType == 'habit')
        .toList();
    final taskInstances =
        instances.where((inst) => inst.templateCategoryType == 'task').toList();

    // INSTANT calculation - no async, no Firestore queries
    final progressData =
        DailyProgressCalculator.calculateTodayProgressOptimistic(
      userId: userId,
      allInstances: habitInstances,
      categories: categories,
      taskInstances: taskInstances,
    );

    final target = (progressData['target'] as num?)?.toDouble() ?? 0.0;
    final earned = (progressData['earned'] as num?)?.toDouble() ?? 0.0;
    final percentage = (progressData['percentage'] as num?)?.toDouble() ?? 0.0;

    // Publish to shared state for other pages
    TodayProgressState().updateProgress(
      target: target,
      earned: earned,
      percentage: percentage,
    );

    return {
      'target': target,
      'earned': earned,
      'percentage': percentage,
    };
  }

  /// Get cached/current completion points from TodayProgressState
  /// Returns: {target, earned, percentage}
  static Map<String, double> getTodayCompletionPoints() {
    final data = TodayProgressState().getProgressData();
    return {
      'target': data['target'] ?? 0.0,
      'earned': data['earned'] ?? 0.0,
      'percentage': data['percentage'] ?? 0.0,
    };
  }
}
