import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Screens/Progress/backend/daily_progress_query_service.dart';
import 'package:intl/intl.dart';

/// Service for loading and managing score history for UI
/// Handles history data loading, formatting, and updates
class ScoreHistoryService {
  /// Load cumulative score history for the last N days with today's live score
  ///
  /// If [cumulativeScore]/[todayScore] are provided, they are used for today's overlay.
  /// Otherwise falls back to calculating from progress state.
  ///
  /// Returns:
  /// - `cumulativeScore` (double) : the live cumulative score (yesterday + today)
  /// - `todayScore` (double) : today's score gain
  /// - `history` (List<Map<String, dynamic>>) items: `{date, score, gain}` for last N days
  static Future<Map<String, dynamic>> loadScoreHistory({
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

    // Load last N days (N-1 historical + today)
    final endDate = DateService.todayStart;
    final startDate = endDate.subtract(Duration(days: days - 1));

    final records = await DailyProgressQueryService.queryDailyProgress(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      orderDescending: false,
    );

    final recordMap = <String, DailyProgressRecord>{};
    for (final record in records) {
      if (record.date == null) continue;
      final key = DateFormat('yyyy-MM-dd').format(record.date!);
      recordMap[key] = record;
    }

    double lastKnownScore = 0.0;

    // Baseline: last record before startDate
    try {
      final priorRecords = await DailyProgressQueryService.queryDailyProgress(
        userId: userId,
        endDate: startDate.subtract(const Duration(days: 1)),
        orderDescending: true,
      );
      if (priorRecords.isNotEmpty) {
        final prior = priorRecords.first;
        if (prior.cumulativeScoreSnapshot > 0) {
          lastKnownScore = prior.cumulativeScoreSnapshot;
        }
      } else if (recordMap.isNotEmpty) {
        final sortedDates = recordMap.keys.toList()..sort();
        final first = recordMap[sortedDates.first]!;
        if (first.cumulativeScoreSnapshot > 0) {
          lastKnownScore = first.cumulativeScoreSnapshot - first.dailyScoreGain;
          if (lastKnownScore < 0) lastKnownScore = 0;
        }
      }
    } catch (_) {
      // ignore baseline errors
    }

    final history = <Map<String, dynamic>>[];

    // Build history for last N days (N-1 historical + today)
    for (int i = 0; i < days; i++) {
      final date = startDate.add(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(date);
      final isToday = i == days - 1; // Last day in loop is today

      if (recordMap.containsKey(key)) {
        final record = recordMap[key]!;
        if (record.cumulativeScoreSnapshot > 0) {
          lastKnownScore = record.cumulativeScoreSnapshot;
        } else if (record.hasDailyScoreGain()) {
          lastKnownScore = (lastKnownScore + record.dailyScoreGain)
              .clamp(0.0, double.infinity);
        }
        // For today, use live values; for historical days, use saved values
        if (isToday) {
          history.add({
            'date': date,
            'score': liveCumulative,
            'gain': liveTodayScore,
          });
        } else {
          history.add({
            'date': date,
            'score': lastKnownScore,
            'gain': record.dailyScoreGain,
          });
        }
      } else {
        // No record for this day
        if (isToday) {
          // Today: use live values
          history.add({
            'date': date,
            'score': liveCumulative,
            'gain': liveTodayScore,
          });
        } else {
          // Historical day: carry forward last known score
          history.add({
            'date': date,
            'score': lastKnownScore,
            'gain': 0.0,
          });
        }
      }
    }

    return {
      'cumulativeScore': liveCumulative,
      'todayScore': liveTodayScore,
      'history': history,
    };
  }

  /// Update or add today's entry in history with live score values
  /// Returns true if the history list was changed
  static bool updateHistoryWithTodayScore(
    List<Map<String, dynamic>> history,
    double todayScore,
    double cumulativeScore,
  ) {
    final todayStart = DateService.todayStart;

    bool isSameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    if (history.isEmpty) {
      history.add({
        'date': todayStart,
        'score': cumulativeScore,
        'gain': todayScore,
      });
      return true;
    }

    final lastIndex = history.length - 1;
    final lastDate = history[lastIndex]['date'] as DateTime;

    if (isSameDay(lastDate, todayStart)) {
      // Update today's entry
      final oldScore = history[lastIndex]['score'] as num?;
      final oldGain = history[lastIndex]['gain'] as num?;
      if (oldScore?.toDouble() != cumulativeScore ||
          oldGain?.toDouble() != todayScore) {
        history[lastIndex] = {
          'date': lastDate,
          'score': cumulativeScore,
          'gain': todayScore,
        };
        return true;
      }
      return false; // No change
    }

    if (lastDate.isBefore(todayStart)) {
      // Add today's entry
      history.add({
        'date': todayStart,
        'score': cumulativeScore,
        'gain': todayScore,
      });
      // Keep only last 90 days to prevent unbounded growth
      // (This allows for 30-day views while preventing memory issues)
      if (history.length > 90) {
        history.removeAt(0);
      }
      return true;
    }

    return false; // Last entry is in the future (shouldn't happen)
  }
}
