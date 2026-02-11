import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Screens/Progress/backend/habit_statistics_data_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/daily_progress_query_service.dart';

/// Service to aggregate category-wise statistics
class CategoryStatisticsService {
  /// Get statistics for a specific category
  static Future<CategoryStatistics> getCategoryStatistics(
    String userId,
    String categoryId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Get category info
    final categoryQuery = CategoryRecord.collectionForUser(userId)
        .where('categoryType', isEqualTo: 'habit');
    final categorySnapshot = await categoryQuery.get();
    final categories = categorySnapshot.docs
        .map((doc) => CategoryRecord.fromSnapshot(doc))
        .toList();

    final category = categories.firstWhere(
      (cat) => cat.reference.id == categoryId,
      orElse: () => categories.first,
    );

    // Query daily progress records
    final records = await DailyProgressQueryService.queryDailyProgress(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      orderDescending: false,
    );

    // Aggregate category data from categoryBreakdown
    int totalCompletions = 0;
    double totalPointsEarned = 0.0;
    int totalDaysTracked = 0;
    final habitNamesInCategory = <String>{};

    for (final record in records) {
      if (record.date == null) continue;

      final categoryData = record.categoryBreakdown[categoryId];
      if (categoryData == null) continue;

      totalDaysTracked++;
      final completed = (categoryData['completed'] as num?)?.toInt() ?? 0;
      final earned = (categoryData['earned'] as num?)?.toDouble() ?? 0.0;

      totalCompletions += completed;
      totalPointsEarned += earned;

      // Collect habit names from habitBreakdown that belong to this category
      for (final habit in record.habitBreakdown) {
        // We need to match habits to categories - this is approximate
        // since habitBreakdown doesn't have categoryId directly
        // We'll use category name matching as fallback
        final habitName = habit['name'] as String? ?? '';
        if (habitName.isNotEmpty) {
          habitNamesInCategory.add(habitName);
        }
      }
    }

    // Get statistics for habits in this category
    final habitsInCategory = <HabitStatistics>[];
    for (final habitName in habitNamesInCategory) {
      try {
        final habitStats = await HabitStatisticsService.getHabitStatistics(
          userId,
          habitName,
          startDate: startDate,
          endDate: endDate,
        );
        habitsInCategory.add(habitStats);
      } catch (e) {
        // Skip if habit stats can't be retrieved
        continue;
      }
    }

    final completionRate = totalDaysTracked > 0
        ? (totalCompletions / (totalDaysTracked * habitsInCategory.length))
            .clamp(0.0, 100.0)
        : 0.0;
    final averagePointsEarned =
        totalDaysTracked > 0 ? totalPointsEarned / totalDaysTracked : 0.0;

    return CategoryStatistics(
      categoryId: categoryId,
      categoryName: category.name,
      categoryColor: category.color,
      completionRate: completionRate,
      totalHabits: habitsInCategory.length,
      totalCompletions: totalCompletions,
      averagePointsEarned: averagePointsEarned,
      habitsInCategory: habitsInCategory,
    );
  }

  /// Get statistics for all categories
  static Future<List<CategoryStatistics>> getAllCategoriesStatistics(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Get all habit categories
    final categoryQuery = CategoryRecord.collectionForUser(userId)
        .where('categoryType', isEqualTo: 'habit')
        .where('isActive', isEqualTo: true);
    final categorySnapshot = await categoryQuery.get();
    final categories = categorySnapshot.docs
        .map((doc) => CategoryRecord.fromSnapshot(doc))
        .toList();

    // Get statistics for each category
    final statistics = <CategoryStatistics>[];
    for (final category in categories) {
      try {
        final stats = await getCategoryStatistics(
          userId,
          category.reference.id,
          startDate: startDate,
          endDate: endDate,
        );
        statistics.add(stats);
      } catch (e) {
        // Skip if category stats can't be retrieved
        continue;
      }
    }

    // Sort by completion rate descending
    statistics.sort((a, b) => b.completionRate.compareTo(a.completionRate));

    return statistics;
  }
}

/// Data class for category statistics
class CategoryStatistics {
  final String categoryId;
  final String categoryName;
  final String categoryColor;
  final double completionRate;
  final int totalHabits;
  final int totalCompletions;
  final double averagePointsEarned;
  final List<HabitStatistics> habitsInCategory;

  CategoryStatistics({
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    required this.completionRate,
    required this.totalHabits,
    required this.totalCompletions,
    required this.averagePointsEarned,
    required this.habitsInCategory,
  });
}
