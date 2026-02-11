import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';

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
  double _yesterdayCumulativeScore = 0.0;
  double _todayScore = 0.0;
  bool _hasLiveScore = false;
  DateTime _lastUpdateDate = DateService.todayStart;
  Map<String, double> _scoreBreakdown = {};

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

  double get yesterdayCumulativeScore {
    _checkDayTransition();
    return _yesterdayCumulativeScore;
  }

  double get todayScore {
    _checkDayTransition();
    return _todayScore;
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
      _todayScore = 0.0;
      _hasLiveScore = false;
      _scoreBreakdown = {};
      // Carry forward yesterday's cumulative as baseline for new day
      _yesterdayCumulativeScore = _cumulativeScore;
      _lastUpdateDate = today;
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

  void updateTodayScore({
    required double cumulativeScore,
    required double todayScore,
    required double yesterdayCumulative,
    required bool hasLiveScore,
    Map<String, double>? breakdown,
  }) {
    _checkDayTransition();
    _cumulativeScore = cumulativeScore;
    _todayScore = todayScore;
    _dailyScoreGain = todayScore; // Keep for backward compatibility
    _yesterdayCumulativeScore = yesterdayCumulative;
    _hasLiveScore = hasLiveScore;
    if (breakdown != null) {
      _scoreBreakdown = Map<String, double>.from(breakdown);
    }
    _lastUpdateDate = DateService.todayStart;
    // Notify other pages about score update
    NotificationCenter.post('cumulativeScoreUpdated');
  }

  /// Legacy method for backward compatibility
  /// Use updateTodayScore() instead
  @Deprecated('Use updateTodayScore instead')
  void updateCumulativeScore({
    required double cumulativeScore,
    required double dailyGain,
    required bool hasLiveScore,
  }) {
    updateTodayScore(
      cumulativeScore: cumulativeScore,
      todayScore: dailyGain,
      yesterdayCumulative: _yesterdayCumulativeScore,
      hasLiveScore: hasLiveScore,
    );
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
      'todayScore': _todayScore,
      'yesterdayCumulative': _yesterdayCumulativeScore,
      'hasLiveScore': _hasLiveScore,
      'breakdown': Map<String, double>.from(_scoreBreakdown),
    };
  }

  /// Get yesterday's cumulative score
  double getYesterdayCumulativeScore() {
    _checkDayTransition();
    return _yesterdayCumulativeScore;
  }
}
