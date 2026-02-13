import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/schema/cumulative_score_history_record.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/features/Progress/backend/daily_progress_query_service.dart';
import 'package:intl/intl.dart';

/// Service for loading and managing score history for UI
/// Handles history data loading, formatting, and updates
class ScoreHistoryService {
  static double _entryClosingScore(Map<String, dynamic> entry) {
    return (entry['closingScore'] as num?)?.toDouble() ??
        (entry['score'] as num?)?.toDouble() ??
        0.0;
  }

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
        if (prior.hasCumulativeScoreSnapshot()) {
          lastKnownScore = prior.cumulativeScoreSnapshot;
        }
      } else if (recordMap.isNotEmpty) {
        final sortedDates = recordMap.keys.toList()..sort();
        final first = recordMap[sortedDates.first]!;
        if (first.hasCumulativeScoreSnapshot()) {
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
        if (record.hasCumulativeScoreSnapshot()) {
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
    final lastDate = safeDateTime(history[lastIndex]['date']);
    if (lastDate == null) return false;

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

  /// Load score history from single document (optimized - 1 read instead of 30+)
  /// Falls back to old method if document doesn't exist (for migration)
  static Future<Map<String, dynamic>> loadScoreHistoryFromSingleDoc({
    required String userId,
    int days = 30,
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

    try {
      final doc = await CumulativeScoreHistoryRecord.getDocument(userId);

      if (!doc.exists) {
        return {
          'cumulativeScore': cumulativeScore ?? 0.0,
          'todayScore': todayScore ?? 0.0,
          'history': <Map<String, dynamic>>[],
        };
      }

      final data = doc.data() as Map<String, dynamic>?;
      final scores =
          (data?['scores'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (scores.isEmpty) {
        return {
          'cumulativeScore': cumulativeScore ?? 0.0,
          'todayScore': todayScore ?? 0.0,
          'history': <Map<String, dynamic>>[],
        };
      }

      // Get last N days
      final lastNDays =
          scores.length > days ? scores.sublist(scores.length - days) : scores;

      // Get latest score values
      final latestScore = scores.isNotEmpty ? _entryClosingScore(scores.last) : 0.0;
      final latestGain = scores.isNotEmpty
          ? (scores.last['gain'] as num?)?.toDouble() ?? 0.0
          : 0.0;

      // Use provided live values if available, otherwise use latest from history
      final finalCumulativeScore = cumulativeScore ?? latestScore;
      final finalTodayScore = todayScore ?? latestGain;

      // Update today's entry in the returned history if live values provided
      final history = List<Map<String, dynamic>>.from(lastNDays);
      final todayStart = DateService.todayStart;
      if (history.isNotEmpty) {
        final lastEntry = history.last;
        final lastDate = safeDateTime(lastEntry['date']);
        if (lastDate != null) {
          final isToday = lastDate.year == todayStart.year &&
              lastDate.month == todayStart.month &&
              lastDate.day == todayStart.day;
          if (isToday && (cumulativeScore != null || todayScore != null)) {
            // Update today's entry with live values
            history[history.length - 1] = {
              'date': lastDate,
              'score': finalCumulativeScore,
              'closingScore': finalCumulativeScore,
              'gain': finalTodayScore,
            };
          }
        }
      }

      return {
        'cumulativeScore': finalCumulativeScore,
        'todayScore': finalTodayScore,
        'history': history,
      };
    } catch (e) {
      // On error, return empty instead of fallback
      return {
        'cumulativeScore': cumulativeScore ?? 0.0,
        'todayScore': todayScore ?? 0.0,
        'history': <Map<String, dynamic>>[],
      };
    }
  }

  /// Update the single document with today's score
  /// Appends or updates today's entry and keeps only last 100 days
  static Future<void> updateScoreHistoryDocument({
    required String userId,
    required double cumulativeScore,
    required double todayScore,
    double? effectiveGain,
    DateTime? targetDate, // Optional date, defaults to yesterday
  }) async {
    if (userId.isEmpty) return;

    try {
      final date = targetDate ?? DateService.yesterdayStart;
      final today = DateService.todayStart;

      // GUARD: Don't persist today's score (it's live-only)
      // This prevents write amplification and ensures history only contains finalized days
      if (date.year == today.year &&
          date.month == today.month &&
          date.day == today.day) {
        return;
      }

      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      // Get current document
      final doc = await CumulativeScoreHistoryRecord.getDocument(userId);
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final scores =
          (data['scores'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      // Remove entry for this date if it exists
      scores.removeWhere((s) {
        final sDate = safeDateTime(s['date']);
        if (sDate != null) {
          return sDate.year == date.year &&
              sDate.month == date.month &&
              sDate.day == date.day;
        } else if (s['date'] is String) {
          return s['date'] == dateKey;
        }
        return false;
      });

      // Add entry (include effectiveGain for schema consistency with cloud function)
      final openingScore =
          (cumulativeScore - (effectiveGain ?? todayScore)).clamp(0.0, double.infinity);
      final entry = <String, dynamic>{
        'date': date,
        'score': cumulativeScore,
        'openingScore': openingScore,
        'closingScore': cumulativeScore,
        'gain': todayScore,
      };
      if (effectiveGain != null) {
        entry['effectiveGain'] = effectiveGain;
      }
      scores.add(entry);

      // Keep only last 100 days
      if (scores.length > 100) {
        scores.removeRange(0, scores.length - 100);
      }

      // Update document
      await CumulativeScoreHistoryRecord.setDocument(
        userId: userId,
        scores: scores,
      );
    } catch (e) {
      // Silently fail - non-critical operation
      // History will be rebuilt on next load if needed
    }
  }
}
