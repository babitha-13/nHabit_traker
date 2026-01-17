import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/today_score_calculator.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/score_state_service.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/score_history_service.dart';
import 'package:habit_tracker/Screens/Progress/Statemanagement/today_progress_state.dart';

/// Coordinator/orchestrator for score calculations and state management
/// Coordinates all score-related services to provide a unified interface
/// This is the main entry point for score updates from UI
class ScoreCoordinator {
  /// Calculates and publishes today's score + cumulative score
  ///
  /// Today's score is based on actual completion up to now (not a projection).
  /// Always updates shared state (source of truth for cross-page sync).
  ///
  /// Returns a map with:
  /// - `cumulativeScore` (double) - yesterday's cumulative + today's score (clamped >= 0)
  /// - `todayScore` (double) - today's score gain (can be negative)
  /// - `yesterdayCumulative` (double) - cumulative at end of yesterday
  /// - if [includeBreakdown] is true: `dailyScore`, `consistencyBonus`,
  ///   `recoveryBonus`, `decayPenalty`, `categoryNeglectPenalty`
  static Future<Map<String, dynamic>> updateTodayScore({
    required String userId,
    required double completionPercentage,
    required double pointsEarned,
    List<CategoryRecord>? categories,
    List<ActivityInstanceRecord>? habitInstances,
    bool includeBreakdown = false,
    bool updateSharedState = true,
  }) async {
    if (userId.isEmpty) {
      return {
        'cumulativeScore': 0.0,
        'todayScore': 0.0,
        'yesterdayCumulative': 0.0,
        if (includeBreakdown) ...{
          'dailyScore': 0.0,
          'consistencyBonus': 0.0,
          'recoveryBonus': 0.0,
          'decayPenalty': 0.0,
          'categoryNeglectPenalty': 0.0,
        },
      };
    }

    // Calculate today's score from completion
    // Always calculate breakdown to ensure shared state has complete data
    final scoreData = await TodayScoreCalculator.calculateTodayScore(
      userId: userId,
      completionPercentage: completionPercentage,
      pointsEarned: pointsEarned,
      categories: categories,
      habitInstances: habitInstances,
    );

    final todayScore = (scoreData['todayScore'] as num?)?.toDouble() ?? 0.0;

    // Get yesterday's cumulative and calculate new cumulative
    final yesterdayCumulative =
        await TodayScoreCalculator.getCumulativeScoreTillYesterday(
            userId: userId);
    final cumulativeScore = await TodayScoreCalculator.calculateCumulativeScore(
      userId: userId,
      todayScore: todayScore,
    );

    // Build breakdown map for shared state (always available for consistency)
    final breakdown = <String, double>{
      'dailyScore': (scoreData['dailyScore'] as num?)?.toDouble() ?? 0.0,
      'consistencyBonus':
          (scoreData['consistencyBonus'] as num?)?.toDouble() ?? 0.0,
      'recoveryBonus': (scoreData['recoveryBonus'] as num?)?.toDouble() ?? 0.0,
      'decayPenalty': (scoreData['decayPenalty'] as num?)?.toDouble() ?? 0.0,
      'categoryNeglectPenalty':
          (scoreData['categoryNeglectPenalty'] as num?)?.toDouble() ?? 0.0,
    };

    // Update shared state
    if (updateSharedState) {
      ScoreStateService.updateTodayScore(
        cumulativeScore: cumulativeScore,
        todayScore: todayScore,
        yesterdayCumulative: yesterdayCumulative,
        hasLiveScore: true,
        breakdown: breakdown,
      );
    }

    final result = <String, dynamic>{
      'cumulativeScore': cumulativeScore,
      'todayScore': todayScore,
      'yesterdayCumulative': yesterdayCumulative,
    };

    if (includeBreakdown) {
      result.addAll({
        'dailyScore': (scoreData['dailyScore'] as num?)?.toDouble() ?? 0.0,
        'consistencyBonus':
            (scoreData['consistencyBonus'] as num?)?.toDouble() ?? 0.0,
        'recoveryBonus':
            (scoreData['recoveryBonus'] as num?)?.toDouble() ?? 0.0,
        'decayPenalty': (scoreData['decayPenalty'] as num?)?.toDouble() ?? 0.0,
        'categoryNeglectPenalty':
            (scoreData['categoryNeglectPenalty'] as num?)?.toDouble() ?? 0.0,
      });
    }

    return result;
  }

  /// Loads cumulative score history for the last N days with today's live score
  ///
  /// If [cumulativeScore]/[todayScore] are provided, they are used for today's overlay.
  /// Otherwise we try to reuse shared state if it has a live score.
  ///
  /// [days] specifies how many days of history to load (default: 7)
  ///
  /// Returns:
  /// - `cumulativeScore` (double) : the live cumulative score (yesterday + today)
  /// - `todayScore` (double) : today's score gain
  /// - `history` (List<Map<String, dynamic>>) items: `{date, score, gain}` for last N days
  static Future<Map<String, dynamic>> loadScoreHistoryWithToday({
    required String userId,
    int days = 7,
    double? cumulativeScore,
    double? todayScore,
  }) async {
    if (userId.isEmpty) {
      return {
        'cumulativeScore': 0.0,
        'todayScore': 0.0,
        'history': <Map<String, dynamic>>[],
      };
    }

    double liveCumulative = cumulativeScore ?? 0.0;
    double liveTodayScore = todayScore ?? 0.0;

    if (cumulativeScore == null) {
      final shared = ScoreStateService.getTodayScore();
      final hasLive = shared['hasLiveScore'] as bool? ?? false;
      if (hasLive) {
        liveCumulative = (shared['cumulativeScore'] as num?)?.toDouble() ?? 0.0;
        liveTodayScore = (shared['todayScore'] as num?)?.toDouble() ?? 0.0;
      } else {
        // Compute from current progress state (best effort)
        final progress = TodayProgressState().getProgressData();
        final computed = await updateTodayScore(
          userId: userId,
          completionPercentage:
              (progress['percentage'] as num?)?.toDouble() ?? 0.0,
          pointsEarned: (progress['earned'] as num?)?.toDouble() ?? 0.0,
          includeBreakdown: false,
        );
        liveCumulative =
            (computed['cumulativeScore'] as num?)?.toDouble() ?? 0.0;
        liveTodayScore = (computed['todayScore'] as num?)?.toDouble() ?? 0.0;
      }
    }

    // Delegate to history service
    return ScoreHistoryService.loadScoreHistory(
      userId: userId,
      days: days,
      cumulativeScore: liveCumulative,
      todayScore: liveTodayScore,
    );
  }

  /// Updates or adds today's entry in history with live score values
  /// Returns true if the history list was changed
  static bool updateHistoryWithTodayScore(
    List<Map<String, dynamic>> history,
    double todayScore,
    double cumulativeScore,
  ) {
    return ScoreHistoryService.updateHistoryWithTodayScore(
      history,
      todayScore,
      cumulativeScore,
    );
  }
}

/// Legacy alias for backward compatibility
/// Use ScoreCoordinator instead
@Deprecated('Use ScoreCoordinator instead')
class CumulativeScoreCalculator {
  /// Legacy method - delegates to ScoreCoordinator
  @Deprecated('Use ScoreCoordinator.updateTodayScore instead')
  static Future<Map<String, dynamic>> updateTodayScore({
    required String userId,
    required double completionPercentage,
    required double pointsEarned,
    List<CategoryRecord>? categories,
    List<ActivityInstanceRecord>? habitInstances,
    bool includeBreakdown = false,
    bool updateSharedState = true,
  }) async {
    return ScoreCoordinator.updateTodayScore(
      userId: userId,
      completionPercentage: completionPercentage,
      pointsEarned: pointsEarned,
      categories: categories,
      habitInstances: habitInstances,
      includeBreakdown: includeBreakdown,
      updateSharedState: updateSharedState,
    );
  }

  /// Legacy method - delegates to ScoreCoordinator
  @Deprecated('Use ScoreCoordinator.loadScoreHistoryWithToday instead')
  static Future<Map<String, dynamic>> loadCumulativeScoreHistory({
    required String userId,
    int days = 7,
    double? cumulativeScore,
    double? todayScore,
  }) async {
    return ScoreCoordinator.loadScoreHistoryWithToday(
      userId: userId,
      days: days,
      cumulativeScore: cumulativeScore,
      todayScore: todayScore,
    );
  }

  /// Legacy method - delegates to ScoreCoordinator
  @Deprecated('Use ScoreCoordinator.updateHistoryWithTodayScore instead')
  static bool updateHistoryWithTodayScore(
    List<Map<String, dynamic>> history,
    double todayScore,
    double cumulativeScore,
  ) {
    return ScoreCoordinator.updateHistoryWithTodayScore(
      history,
      todayScore,
      cumulativeScore,
    );
  }

  /// Legacy method for backward compatibility
  @Deprecated('Use ScoreCoordinator.updateTodayScore instead')
  static Future<Map<String, dynamic>> updateCumulativeScoreLive({
    required String userId,
    required double dailyPercentage,
    required double pointsEarned,
    bool includeBreakdown = false,
  }) async {
    return ScoreCoordinator.updateTodayScore(
      userId: userId,
      completionPercentage: dailyPercentage,
      pointsEarned: pointsEarned,
      includeBreakdown: includeBreakdown,
    );
  }

  /// Legacy method for backward compatibility
  @Deprecated('Use ScoreCoordinator.updateHistoryWithTodayScore instead')
  static bool applyLiveScoreToHistory(
    List<Map<String, dynamic>> history,
    double score,
    double gain,
  ) {
    return ScoreCoordinator.updateHistoryWithTodayScore(history, gain, score);
  }
}
