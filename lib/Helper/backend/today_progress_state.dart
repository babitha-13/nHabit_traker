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
  double get dailyTarget => _dailyTarget;
  double get pointsEarned => _pointsEarned;
  double get dailyPercentage => _dailyPercentage;
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
  Map<String, double> getProgressData() {
    return {
      'target': _dailyTarget,
      'earned': _pointsEarned,
      'percentage': _dailyPercentage,
    };
  }
}
