import 'package:habit_tracker/Helper/utils/notification_center.dart';
/// Shared state service for today's progress data
/// Allows Queue page to publish progress and Progress page to subscribe to updates
class TodayProgressState {
  static final TodayProgressState _instance = TodayProgressState._internal();
  factory TodayProgressState() => _instance;
  TodayProgressState._internal();
  double _dailyTarget = 0.0;
  double _pointsEarned = 0.0;
  double _dailyPercentage = 0.0;
  double _cumulativeScore = 0.0;
  double _dailyScoreGain = 0.0;
  bool _hasLiveScore = false;
  double get dailyTarget => _dailyTarget;
  double get pointsEarned => _pointsEarned;
  double get dailyPercentage => _dailyPercentage;
  double get cumulativeScore => _cumulativeScore;
  double get dailyScoreGain => _dailyScoreGain;
  bool get hasLiveScore => _hasLiveScore;
  void updateProgress({
    required double target,
    required double earned,
    required double percentage,
  }) {
    _dailyTarget = target;
    _pointsEarned = earned;
    _dailyPercentage = percentage;
    // Notify other pages about the update
    NotificationCenter.post('todayProgressUpdated');
  }
  void updateCumulativeScore({
    required double cumulativeScore,
    required double dailyGain,
    required bool hasLiveScore,
  }) {
    _cumulativeScore = cumulativeScore;
    _dailyScoreGain = dailyGain;
    _hasLiveScore = hasLiveScore;
    // Notify other pages about cumulative score update
    NotificationCenter.post('cumulativeScoreUpdated');
  }
  Map<String, double> getProgressData() {
    return {
      'target': _dailyTarget,
      'earned': _pointsEarned,
      'percentage': _dailyPercentage,
    };
  }
  Map<String, dynamic> getCumulativeScoreData() {
    return {
      'cumulativeScore': _cumulativeScore,
      'dailyGain': _dailyScoreGain,
      'hasLiveScore': _hasLiveScore,
    };
  }
}
