import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/daily_progress_calculator.dart';
import 'package:habit_tracker/Helper/backend/today_progress_state.dart';
import 'package:habit_tracker/Helper/backend/cumulative_score_service.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Screens/Queue/Logic/queue_utils.dart';
import 'package:intl/intl.dart';

/// Service class for calculating progress and cumulative scores
class QueueProgressCalculator {
  /// Calculate progress for today's habits and tasks
  /// Uses shared DailyProgressCalculator for consistency with historical data
  /// [optimistic] - If true, calculates instantly from local data without Firestore queries
  static Future<Map<String, double>> calculateProgress({
    required List<ActivityInstanceRecord> instances,
    required List<CategoryRecord> categories,
    required String userId,
    bool optimistic = false,
  }) async {
    // Separate habit and task instances
    final habitInstances = instances
        .where((inst) => inst.templateCategoryType == 'habit')
        .toList();
    final taskInstances = instances
        .where((inst) => inst.templateCategoryType == 'task')
        .toList();

    if (optimistic) {
      // INSTANT UPDATE: Calculate from local data only (no Firestore queries)
      try {
        final progressData =
            await DailyProgressCalculator.calculateTodayProgressOptimistic(
          userId: userId,
          allInstances: habitInstances,
          categories: categories,
          taskInstances: taskInstances,
        );

        // Publish to shared state for other pages
        TodayProgressState().updateProgress(
          target: progressData['target'] as double,
          earned: progressData['earned'] as double,
          percentage: progressData['percentage'] as double,
        );

        return {
          'target': progressData['target'] as double,
          'earned': progressData['earned'] as double,
          'percentage': progressData['percentage'] as double,
        };
      } catch (e) {
        // If optimistic calculation fails, fall back to full calculation
        return await calculateProgress(
          instances: instances,
          categories: categories,
          userId: userId,
          optimistic: false,
        );
      }
    } else {
      // BACKEND RECONCILIATION: Use full calculation with Firestore
      try {
        final progressData =
            await DailyProgressCalculator.calculateTodayProgress(
          userId: userId,
          allInstances: habitInstances,
          categories: categories,
          taskInstances: taskInstances,
        );

        // Publish to shared state for other pages
        TodayProgressState().updateProgress(
          target: progressData['target'] as double,
          earned: progressData['earned'] as double,
          percentage: progressData['percentage'] as double,
        );

        return {
          'target': progressData['target'] as double,
          'earned': progressData['earned'] as double,
          'percentage': progressData['percentage'] as double,
        };
      } catch (e) {
        // Error in backend calculation - non-critical, continue silently
        return {
          'target': 0.0,
          'earned': 0.0,
          'percentage': 0.0,
        };
      }
    }
  }

  /// Update cumulative score live without reloading full history
  /// This provides instant updates similar to daily progress chart
  static Future<Map<String, double>> updateCumulativeScoreLive({
    required double dailyPercentage,
    required double pointsEarned,
    required String userId,
  }) async {
    if (userId.isEmpty) {
      return {'cumulativeScore': 0.0, 'dailyGain': 0.0};
    }

    // Calculate projected score including today's progress (even if 0)
    final projectionData =
        await CumulativeScoreService.calculateProjectedDailyScore(
      userId,
      dailyPercentage,
      pointsEarned,
    );

    final currentCumulativeScore =
        projectionData['projectedCumulative'] ?? 0.0;
    final currentDailyGain = projectionData['projectedGain'] ?? 0.0;

    // Publish to shared state for other pages
    TodayProgressState().updateCumulativeScore(
      cumulativeScore: currentCumulativeScore,
      dailyGain: currentDailyGain,
      hasLiveScore: true,
    );

    return {
      'cumulativeScore': currentCumulativeScore,
      'dailyGain': currentDailyGain,
    };
  }

  /// Load cumulative score history for the last 30 days
  static Future<Map<String, dynamic>> loadCumulativeScoreHistory({
    required String userId,
    required double dailyPercentage,
    required double pointsEarned,
  }) async {
    if (userId.isEmpty) {
      return {
        'cumulativeScore': 0.0,
        'dailyGain': 0.0,
        'history': <Map<String, dynamic>>[],
      };
    }

    double currentCumulativeScore = 0.0;
    double currentDailyGain = 0.0;

    // First check if the Progress page has already calculated the live score
    final sharedData = TodayProgressState().getCumulativeScoreData();
    if (sharedData['hasLiveScore'] as bool) {
      currentCumulativeScore = sharedData['cumulativeScore'] as double;
      currentDailyGain = sharedData['dailyGain'] as double;
    } else {
      // Calculate the live cumulative score ourselves
      // Calculate projected score including today's progress (even if 0)
      final projectionData =
          await CumulativeScoreService.calculateProjectedDailyScore(
        userId,
        dailyPercentage,
        pointsEarned,
      );

      currentCumulativeScore = projectionData['projectedCumulative'] ?? 0.0;
      currentDailyGain = projectionData['projectedGain'] ?? 0.0;

      // Publish to shared state for other pages
      TodayProgressState().updateCumulativeScore(
        cumulativeScore: currentCumulativeScore,
        dailyGain: currentDailyGain,
        hasLiveScore: true,
      );
    }

    // Load cumulative score history for the last 30 days
    // Use todayStart to ensuring consistent midnight-to-midnight querying
    final endDate = DateService.todayStart;
    final startDate = endDate.subtract(const Duration(days: 30));

    final query = await DailyProgressRecord.collectionForUser(userId)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate)
        .orderBy('date', descending: false)
        .get();

    // Create a map for quick lookup of existing records
    final recordMap = <String, DailyProgressRecord>{};
    for (final doc in query.docs) {
      final record = DailyProgressRecord.fromSnapshot(doc);
      if (record.date != null) {
        final dateKey = DateFormat('yyyy-MM-dd').format(record.date!);
        recordMap[dateKey] = record;
      }
    }

    final history = <Map<String, dynamic>>[];

    double lastKnownScore = 0.0;

    // Fetch the last record BEFORE the start date to get the baseline score
    try {
      final lastPriorRecordQuery =
          await DailyProgressRecord.collectionForUser(userId)
              .where('date', isLessThan: startDate)
              .orderBy('date', descending: true)
              .limit(1)
              .get();

      if (lastPriorRecordQuery.docs.isNotEmpty) {
        final priorRec =
            DailyProgressRecord.fromSnapshot(lastPriorRecordQuery.docs.first);
        if (priorRec.cumulativeScoreSnapshot > 0) {
          lastKnownScore = priorRec.cumulativeScoreSnapshot;
        }
      } else {
        // If no prior record exists, use the first record in our current range as baseline
        // This handles new users or when history doesn't go back 30 days
        if (recordMap.isNotEmpty) {
          // Get the earliest date in our map
          final sortedDates = recordMap.keys.toList()..sort();
          final firstRecord = recordMap[sortedDates.first]!;
          if (firstRecord.cumulativeScoreSnapshot > 0) {
            // Use the score from the day BEFORE the first record
            // by subtracting that day's gain
            lastKnownScore = firstRecord.cumulativeScoreSnapshot -
                firstRecord.dailyScoreGain;
            if (lastKnownScore < 0) lastKnownScore = 0;
          }
        }
      }
    } catch (e) {
      // Error fetching prior cumulative score
    }

    // Iterate day by day from startDate to endDate
    for (int i = 0; i <= 30; i++) {
      final date = startDate.add(Duration(days: i));
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      if (recordMap.containsKey(dateKey)) {
        final record = recordMap[dateKey]!;
        // Use cumulativeScoreSnapshot if available, otherwise calculate from lastKnownScore
        // This matches Progress page logic to ensure consistent data
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
        // No record for this day, simply carry forward the last cumulative score
        // Gain is 0 for missing days
        history.add({
          'date': date,
          'score': lastKnownScore,
          'gain': 0.0,
        });
      }
    }

    // Ensure today reflects the live score (if today is the last day in loop)
    // The loop goes up to endDate (today). existing logic overrides today with live score.
    // Let's check if the last item in history is today.
    if (history.isNotEmpty) {
      final lastItem = history.last;
      final lastDate = lastItem['date'] as DateTime;
      final today = DateService.currentDate;

      if (lastDate.year == today.year &&
          lastDate.month == today.month &&
          lastDate.day == today.day) {
        // Always update today's entry with current values to match Progress page behavior
        // Use projected score if available (hasLiveScore), otherwise use base score
        history.last['score'] = currentCumulativeScore;
        history.last['gain'] = currentDailyGain;
      }
    }

    // Safeguard: Check if the new history is all zeros (invalid) while we possibly have valid data
    final bool isNewHistoryValid =
        history.any((h) => (h['score'] as double) > 0);

    if (!isNewHistoryValid) {
      // Warning: New cumulative score history is empty/zero. Returning empty history.
      return {
        'cumulativeScore': currentCumulativeScore,
        'dailyGain': currentDailyGain,
        'history': <Map<String, dynamic>>[],
      };
    }

    return {
      'cumulativeScore': currentCumulativeScore,
      'dailyGain': currentDailyGain,
      'history': history,
    };
  }

  /// Apply live score to history
  static bool applyLiveScoreToHistory(
    List<Map<String, dynamic>> cumulativeScoreHistory,
    double score,
    double gain,
  ) {
    final todayStart = DateService.todayStart;

    if (cumulativeScoreHistory.isEmpty) {
      cumulativeScoreHistory.add({
        'date': todayStart,
        'score': score,
        'gain': gain,
      });
      return true;
    }

    final lastIndex = cumulativeScoreHistory.length - 1;
    final lastEntry = cumulativeScoreHistory[lastIndex];
    final lastDate = lastEntry['date'] as DateTime;

    final updatedHistory =
        List<Map<String, dynamic>>.from(cumulativeScoreHistory);

    if (QueueUtils.isSameDay(lastDate, todayStart)) {
      updatedHistory[lastIndex] = {
        'date': lastDate,
        'score': score,
        'gain': gain,
      };
    } else if (lastDate.isBefore(todayStart)) {
      updatedHistory.add({
        'date': todayStart,
        'score': score,
        'gain': gain,
      });
      if (updatedHistory.length > 31) {
        updatedHistory.removeAt(0);
      }
    } else {
      return false;
    }

    cumulativeScoreHistory.clear();
    cumulativeScoreHistory.addAll(updatedHistory);
    return true;
  }
}
