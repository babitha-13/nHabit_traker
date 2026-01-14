import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Screens/Shared/daily_progress_calculator.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/daily_progress_query_service.dart';
import 'package:intl/intl.dart';

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
  static Future<List<Map<String, dynamic>>> fetchCumulativeScoreHistory({
    required String userId,
    double? projectedCumulativeScore,
    double? projectedDailyGain,
    double? cumulativeScore,
    double? dailyScoreGain,
    bool hasProjection = false,
  }) async {
    try {
      final endDate = DateService.todayStart;
      final startDate = endDate.subtract(const Duration(days: 30));

      final query = await DailyProgressQueryService.queryDailyProgress(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        orderDescending: false,
      );

      // Create a map for quick lookup of existing records
      final recordMap = <String, DailyProgressRecord>{};
      for (final record in query) {
        if (record.date != null) {
          final dateKey = DateFormat('yyyy-MM-dd').format(record.date!);
          recordMap[dateKey] = record;
        }
      }

      final history = <Map<String, dynamic>>[];
      double lastKnownScore = 0.0;

      // Fetch the last record BEFORE the start date to get the baseline score
      try {
        // Query records before startDate
        final priorRecords = await DailyProgressQueryService.queryDailyProgress(
          userId: userId,
          endDate: startDate.subtract(const Duration(days: 1)),
          orderDescending: true,
        );
        final lastPriorRecordQuery = priorRecords.isNotEmpty
            ? [priorRecords.first]
            : <DailyProgressRecord>[];

        if (lastPriorRecordQuery.isNotEmpty) {
          final priorRec = lastPriorRecordQuery.first;
          if (priorRec.cumulativeScoreSnapshot > 0) {
            lastKnownScore = priorRec.cumulativeScoreSnapshot;
          }
        } else {
          // If no prior record exists, use the first record in our current range as baseline
          if (recordMap.isNotEmpty) {
            final sortedDates = recordMap.keys.toList()..sort();
            final firstRecord = recordMap[sortedDates.first]!;
            if (firstRecord.cumulativeScoreSnapshot > 0) {
              // Use the score from the day BEFORE the first record
              lastKnownScore = firstRecord.cumulativeScoreSnapshot -
                  firstRecord.dailyScoreGain;
              if (lastKnownScore < 0) lastKnownScore = 0;
            }
          }
        }
      } catch (e) {
        // Error fetching prior cumulative score
      }

      // Iterate day by day from startDate to endDate (30 days)
      for (int i = 0; i <= 30; i++) {
        final date = startDate.add(Duration(days: i));
        final dateKey = DateFormat('yyyy-MM-dd').format(date);

        if (recordMap.containsKey(dateKey)) {
          final record = recordMap[dateKey]!;
          // Use cumulativeScoreSnapshot if available, otherwise calculate from lastKnownScore
          if (record.cumulativeScoreSnapshot > 0) {
            lastKnownScore = record.cumulativeScoreSnapshot;
          } else if (record.hasDailyScoreGain()) {
            // If no snapshot but has gain, calculate from last known score
            lastKnownScore = (lastKnownScore + record.dailyScoreGain)
                .clamp(0.0, double.infinity);
          }
          history.add({
            'date': date,
            'score': lastKnownScore,
            'gain': record.dailyScoreGain,
          });
        } else {
          // No record for this day, carry forward the last cumulative score
          history.add({
            'date': date,
            'score': lastKnownScore,
            'gain': 0.0,
          });
        }
      }

      // Update today's entry with live score if available
      if (history.isNotEmpty) {
        final lastItem = history.last;
        final lastDate = lastItem['date'] as DateTime;
        final today = DateService.currentDate;

        if (lastDate.year == today.year &&
            lastDate.month == today.month &&
            lastDate.day == today.day) {
          // Always use projected score for today if available (matches Queue page behavior)
          if (hasProjection && projectedCumulativeScore != null) {
            history[history.length - 1] = {
              'date': lastDate,
              'score': projectedCumulativeScore,
              'gain': projectedDailyGain ?? 0.0,
            };
          } else if (cumulativeScore != null && cumulativeScore > 0) {
            // Fallback to snapshot score only if projection not available
            history[history.length - 1] = {
              'date': lastDate,
              'score': cumulativeScore,
              'gain': dailyScoreGain ?? 0.0,
            };
          }
        }
      }

      return history;
    } catch (e) {
      return [];
    }
  }
}
