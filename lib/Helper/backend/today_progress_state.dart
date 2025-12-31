import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';

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
  DateTime _lastUpdateDate = DateService.todayStart;

  double get dailyTarget {
    _checkDayTransition();
    return _dailyTarget;
  }

  double get pointsEarned {
    _checkDayTransition();
    return _pointsEarned;
  }

  double get dailyPercentage {
    _checkDayTransition();
    return _dailyPercentage;
  }

  double get cumulativeScore {
    _checkDayTransition();
    return _cumulativeScore;
  }

  double get dailyScoreGain {
    _checkDayTransition();
    return _dailyScoreGain;
  }

  bool get hasLiveScore {
    _checkDayTransition();
    return _hasLiveScore;
  }

  void _checkDayTransition() {
    final today = DateService.todayStart;
    if (!_isSameDay(_lastUpdateDate, today)) {
      // Day has changed, reset today's specific stats
      _dailyTarget = 0.0;
      _pointsEarned = 0.0;
      _dailyPercentage = 0.0;
      _dailyScoreGain = 0.0;
      _hasLiveScore = false;
      _lastUpdateDate = today;
      // Note: We don't reset _cumulativeScore as it's carried forward,
      // but we reset the gain for the new day.
    }
  }

  bool _isSameDay(DateTime d1, DateTime d2) {
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  void updateProgress({
    required double target,
    required double earned,
    required double percentage,
  }) {
    _checkDayTransition();
    _dailyTarget = target;
    _pointsEarned = earned;
    _dailyPercentage = percentage;
    _lastUpdateDate = DateService.todayStart;
    // Notify other pages about the update
    NotificationCenter.post('todayProgressUpdated');
  }

  void updateCumulativeScore({
    required double cumulativeScore,
    required double dailyGain,
    required bool hasLiveScore,
  }) {
    _checkDayTransition();
    _cumulativeScore = cumulativeScore;
    _dailyScoreGain = dailyGain;
    _hasLiveScore = hasLiveScore;
    _lastUpdateDate = DateService.todayStart;
    // Notify other pages about cumulative score update
    NotificationCenter.post('cumulativeScoreUpdated');
  }

  Map<String, double> getProgressData() {
    _checkDayTransition();
    return {
      'target': _dailyTarget,
      'earned': _pointsEarned,
      'percentage': _dailyPercentage,
    };
  }

  Map<String, dynamic> getCumulativeScoreData() {
    _checkDayTransition();
    return {
      'cumulativeScore': _cumulativeScore,
      'dailyGain': _dailyScoreGain,
      'hasLiveScore': _hasLiveScore,
    };
  }
}
