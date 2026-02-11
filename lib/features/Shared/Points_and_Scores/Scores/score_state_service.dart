import 'package:habit_tracker/Screens/Progress/Statemanagement/today_progress_state.dart';

/// Service for managing shared score state (TodayProgressState)
/// Handles synchronization of score data across pages
class ScoreStateService {
  /// Update today's score in shared state
  /// This is the source of truth for cross-page score synchronization
  static void updateTodayScore({
    required double cumulativeScore,
    required double todayScore,
    required double yesterdayCumulative,
    required bool hasLiveScore,
    Map<String, double>? breakdown,
  }) {
    TodayProgressState().updateTodayScore(
      cumulativeScore: cumulativeScore,
      todayScore: todayScore,
      yesterdayCumulative: yesterdayCumulative,
      hasLiveScore: hasLiveScore,
      breakdown: breakdown,
    );
  }

  /// Get today's score data from shared state
  static Map<String, dynamic> getTodayScore() {
    return TodayProgressState().getCumulativeScoreData();
  }

  /// Check if shared state has live score data
  static bool hasLiveScore() {
    final data = getTodayScore();
    return data['hasLiveScore'] as bool? ?? false;
  }
}
