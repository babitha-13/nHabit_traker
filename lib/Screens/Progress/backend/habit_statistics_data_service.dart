import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Screens/Progress/Point_system_helper/points_service.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/daily_progress_query_service.dart';

/// Service to aggregate historical habit statistics from DailyProgressRecord (primary) and ActivityInstanceRecord (for additional details)
/// Uses DailyProgressRecord as primary to minimize Firestore reads (1 doc/day vs potentially many instance docs/day)
class HabitStatisticsService {
  /// Get statistics for a specific habit
  /// PRIMARY: Uses DailyProgressRecord (already aggregated, ~1 read per day)
  /// FALLBACK: Queries ActivityInstanceRecord only for additional details not in DailyProgressRecord
  static Future<HabitStatistics> getHabitStatistics(
    String userId,
    String habitName, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // PRIMARY: Query DailyProgressRecord (already aggregated - much fewer reads!)
    // For 30 days: ~30 reads vs potentially hundreds/thousands of instance reads
    // NOTE: DailyProgressRecord is created at day-end, so today's data may not exist yet
    final records = await DailyProgressQueryService.queryDailyProgress(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      orderDescending: false,
    );

    // Normalize dates for later use
    DateTime? normalizedStart =
        startDate != null ? DateService.normalizeToStartOfDay(startDate) : null;
    DateTime? normalizedEnd =
        endDate != null ? DateService.normalizeToStartOfDay(endDate) : null;

    // Check if we need to include today's data (which may not be in DailyProgressRecord yet)
    final today = DateService.currentDate;
    final todayNormalized = DateService.normalizeToStartOfDay(today);
    bool includeToday = false;
    if (normalizedEnd != null &&
            todayNormalized.isAtSameMomentAs(normalizedEnd) ||
        normalizedEnd == null) {
      // Check if today's record exists
      final todayRecordExists = records.any((r) =>
          r.date != null &&
          DateService.normalizeToStartOfDay(r.date!)
              .isAtSameMomentAs(todayNormalized));
      includeToday = !todayRecordExists &&
          (normalizedStart == null ||
              !todayNormalized.isBefore(normalizedStart));
    }

    // Aggregate data for this habit from DailyProgressRecord
    final dailyHistory = <Map<String, dynamic>>[];
    int totalCompletions = 0;
    int totalDaysTracked = 0;
    double totalPointsEarned = 0.0;
    final statusBreakdown = <String, int>{
      'completed': 0,
      'skipped': 0,
      'pending': 0,
    };
    String? trackingType;

    for (final record in records) {
      if (record.date == null) continue;

      // Find this habit in the breakdown
      final habitDataList = record.habitBreakdown
          .where(
            (h) => (h['name'] as String?)?.trim() == habitName.trim(),
          )
          .toList();

      if (habitDataList.isEmpty) continue;

      final habitData = habitDataList.first;
      totalDaysTracked++;
      final status = habitData['status'] as String? ?? 'pending';
      final earned = (habitData['earned'] as num?)?.toDouble() ?? 0.0;
      final target = (habitData['target'] as num?)?.toDouble() ?? 0.0;

      // Extract tracking type if available
      if (trackingType == null && habitData['trackingType'] != null) {
        trackingType = habitData['trackingType'] as String?;
      }

      dailyHistory.add({
        'date': record.date,
        'status': status,
        'earned': earned,
        'target': target,
        'progress': target > 0 ? (earned / target).clamp(0.0, 1.0) : 0.0,
        'quantity': habitData['quantity'] as num?,
        'timeSpent': habitData['timeSpent'] as num?, // milliseconds
        'completedAt': habitData['completedAt'] as DateTime?,
      });

      if (status == 'completed') {
        totalCompletions++;
        statusBreakdown['completed'] = (statusBreakdown['completed'] ?? 0) + 1;
      } else if (status == 'skipped') {
        statusBreakdown['skipped'] = (statusBreakdown['skipped'] ?? 0) + 1;
      } else {
        statusBreakdown['pending'] = (statusBreakdown['pending'] ?? 0) + 1;
      }

      totalPointsEarned += earned;
    }

    // If today's data is not in DailyProgressRecord yet, calculate it on-the-fly from instances
    if (includeToday) {
      try {
        final todayData = await _getTodayDataFromInstances(
            userId, habitName, todayNormalized);
        if (todayData != null) {
          dailyHistory.add(todayData);
          totalDaysTracked++;

          final status = todayData['status'] as String? ?? 'pending';
          if (status == 'completed') {
            totalCompletions++;
            statusBreakdown['completed'] =
                (statusBreakdown['completed'] ?? 0) + 1;
          } else if (status == 'skipped') {
            statusBreakdown['skipped'] = (statusBreakdown['skipped'] ?? 0) + 1;
          } else {
            statusBreakdown['pending'] = (statusBreakdown['pending'] ?? 0) + 1;
          }

          totalPointsEarned += (todayData['earned'] as num?)?.toDouble() ?? 0.0;

          if (trackingType == null && todayData['trackingType'] != null) {
            trackingType = todayData['trackingType'] as String?;
          }
        }
      } catch (e) {
        // Continue without today's data - not critical
      }
    }

    final completionRate = totalDaysTracked > 0
        ? (totalCompletions / totalDaysTracked) * 100.0
        : 0.0;
    final averagePointsEarned =
        totalDaysTracked > 0 ? totalPointsEarned / totalDaysTracked : 0.0;

    // OPTIONAL: Query ActivityInstanceRecord ONLY for additional details not in DailyProgressRecord
    // This is a lightweight query - only for completed instances to get completion times for hour distribution
    Map<int, int> completionsByHour = {};
    Duration totalTimeSpent = const Duration();
    double totalQuantityCompleted = 0.0;
    int totalSessions = 0;

    if (trackingType == 'time' || trackingType == 'quantity') {
      // Only query instances for completed ones to get completion times and detailed stats
      // This is much more efficient than querying all instances
      try {
        final completedInstances =
            await _getCompletedInstancesForHourDistribution(
          userId,
          habitName,
          normalizedStart,
          normalizedEnd,
        );

        completionsByHour = _calculateCompletionsByHour(completedInstances);
        totalTimeSpent = _calculateTotalTimeSpent(completedInstances);
        totalSessions = _calculateTotalSessions(completedInstances);
        totalQuantityCompleted =
            _calculateTotalQuantityCompleted(completedInstances);
      } catch (e) {
        // Continue without these details - not critical
      }
    }

    // Calculate remaining statistics from dailyHistory
    final averageSessionDuration = totalSessions > 0
        ? Duration(milliseconds: totalTimeSpent.inMilliseconds ~/ totalSessions)
        : const Duration();
    final averageQuantityPerCompletion =
        totalCompletions > 0 ? totalQuantityCompleted / totalCompletions : 0.0;

    final completionsByDayOfWeek =
        _calculateCompletionsByDayOfWeekFromHistory(dailyHistory);
    final bestDayOfWeek = _calculateBestDayOfWeek(completionsByDayOfWeek);

    final weeklyBreakdown = _calculateWeeklyBreakdownFromHistory(
        dailyHistory, normalizedStart, normalizedEnd);
    final monthlyBreakdown = _calculateMonthlyBreakdownFromHistory(
        dailyHistory, normalizedStart, normalizedEnd);
    final bestWeek = _calculateBestWeek(weeklyBreakdown);
    final bestMonth = _calculateBestMonth(monthlyBreakdown);

    final completionRates = dailyHistory.map((d) {
      final progress = d['progress'] as double;
      return progress * 100.0;
    }).toList();
    final consistencyScore = _calculateConsistencyScore(completionRates);

    return HabitStatistics(
      habitName: habitName,
      completionRate: completionRate,
      totalCompletions: totalCompletions,
      totalDaysTracked: totalDaysTracked,
      averagePointsEarned: averagePointsEarned,
      dailyHistory: dailyHistory,
      statusBreakdown: statusBreakdown,
      trackingType: trackingType,
      totalTimeSpent: totalTimeSpent,
      averageSessionDuration: averageSessionDuration,
      totalSessions: totalSessions,
      totalQuantityCompleted: totalQuantityCompleted,
      averageQuantityPerCompletion: averageQuantityPerCompletion,
      bestDayOfWeek: bestDayOfWeek,
      bestWeek: bestWeek,
      bestMonth: bestMonth,
      completionsByDayOfWeek: completionsByDayOfWeek,
      completionsByHour: completionsByHour,
      weeklyBreakdown: weeklyBreakdown,
      monthlyBreakdown: monthlyBreakdown,
      consistencyScore: consistencyScore,
    );
  }

  /// Get today's data from instances (when DailyProgressRecord doesn't exist yet)
  static Future<Map<String, dynamic>?> _getTodayDataFromInstances(
    String userId,
    String habitName,
    DateTime todayDate,
  ) async {
    // Query instances for today
    final query = ActivityInstanceRecord.collectionForUser(userId)
        .where('templateName', isEqualTo: habitName)
        .where('templateCategoryType', isEqualTo: 'habit')
        .where('dueDate', isEqualTo: todayDate);

    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) return null;

    final instances = snapshot.docs
        .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
        .toList();

    if (instances.isEmpty) return null;

    // Use the first instance (or aggregate if multiple)
    final instance = instances.first;

    final target = PointsService.calculateDailyTarget(instance);
    final earned = await PointsService.calculatePointsEarned(instance, userId);
    final progress = target > 0 ? (earned / target).clamp(0.0, 1.0) : 0.0;

    dynamic quantity;
    if (instance.hasCurrentValue() && instance.currentValue is num) {
      quantity = (instance.currentValue as num).toDouble();
    }

    int? timeSpent;
    if (instance.hasTotalTimeLogged() && instance.totalTimeLogged > 0) {
      timeSpent = instance.totalTimeLogged;
    } else if (instance.hasAccumulatedTime() && instance.accumulatedTime > 0) {
      timeSpent = instance.accumulatedTime;
    }

    return {
      'date': todayDate,
      'status': instance.status,
      'earned': earned,
      'target': target,
      'progress': progress,
      'quantity': quantity,
      'timeSpent': timeSpent,
      'completedAt': instance.completedAt,
      'trackingType': instance.templateTrackingType,
    };
  }

  /// Get only completed instances for hour distribution (lightweight query)
  static Future<List<ActivityInstanceRecord>>
      _getCompletedInstancesForHourDistribution(
    String userId,
    String habitName,
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    Query query = ActivityInstanceRecord.collectionForUser(userId)
        .where('templateName', isEqualTo: habitName)
        .where('templateCategoryType', isEqualTo: 'habit')
        .where('status', isEqualTo: 'completed');

    if (startDate != null) {
      query = query.where('dueDate', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('dueDate', isLessThanOrEqualTo: endDate);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
        .toList();
  }

  /// Calculate completions by day of week from daily history
  static Map<int, int> _calculateCompletionsByDayOfWeekFromHistory(
    List<Map<String, dynamic>> dailyHistory,
  ) {
    final map = <int, int>{};
    for (int i = 1; i <= 7; i++) {
      map[i] = 0;
    }

    for (final day in dailyHistory) {
      if (day['status'] == 'completed') {
        final date = day['date'] as DateTime?;
        if (date != null) {
          final dayOfWeek = date.weekday;
          map[dayOfWeek] = (map[dayOfWeek] ?? 0) + 1;
        }
      }
    }

    return map;
  }

  /// Calculate weekly breakdown from daily history
  static List<Map<String, dynamic>> _calculateWeeklyBreakdownFromHistory(
    List<Map<String, dynamic>> dailyHistory,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    final breakdown = <DateTime, Map<String, dynamic>>{};

    for (final day in dailyHistory) {
      final date = day['date'] as DateTime?;
      if (date == null) continue;

      // Get start of week (Monday)
      final daysFromMonday = (date.weekday - 1) % 7;
      final weekStart = DateService.normalizeToStartOfDay(date)
          .subtract(Duration(days: daysFromMonday));

      if (!breakdown.containsKey(weekStart)) {
        breakdown[weekStart] = {
          'weekStart': weekStart,
          'completed': 0,
          'total': 0,
        };
      }

      final weekData = breakdown[weekStart]!;
      weekData['total'] = (weekData['total'] as int) + 1;

      if (day['status'] == 'completed') {
        weekData['completed'] = (weekData['completed'] as int) + 1;
      }
    }

    final result = breakdown.values.map((weekData) {
      final completed = weekData['completed'] as int;
      final total = weekData['total'] as int;
      final completionRate = total > 0 ? (completed / total) * 100.0 : 0.0;

      return {
        'weekStart': weekData['weekStart'],
        'completed': completed,
        'total': total,
        'completionRate': completionRate,
      };
    }).toList();

    result.sort((a, b) {
      final aDate = a['weekStart'] as DateTime;
      final bDate = b['weekStart'] as DateTime;
      return aDate.compareTo(bDate);
    });

    return result;
  }

  /// Calculate monthly breakdown from daily history
  static List<Map<String, dynamic>> _calculateMonthlyBreakdownFromHistory(
    List<Map<String, dynamic>> dailyHistory,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    final breakdown = <DateTime, Map<String, dynamic>>{};

    for (final day in dailyHistory) {
      final date = day['date'] as DateTime?;
      if (date == null) continue;

      final monthKey = DateTime(date.year, date.month, 1);

      if (!breakdown.containsKey(monthKey)) {
        breakdown[monthKey] = {
          'monthStart': monthKey,
          'completed': 0,
          'total': 0,
        };
      }

      final monthData = breakdown[monthKey]!;
      monthData['total'] = (monthData['total'] as int) + 1;

      if (day['status'] == 'completed') {
        monthData['completed'] = (monthData['completed'] as int) + 1;
      }
    }

    final result = breakdown.values.map((monthData) {
      final completed = monthData['completed'] as int;
      final total = monthData['total'] as int;
      final completionRate = total > 0 ? (completed / total) * 100.0 : 0.0;

      return {
        'monthStart': monthData['monthStart'],
        'completed': completed,
        'total': total,
        'completionRate': completionRate,
      };
    }).toList();

    result.sort((a, b) {
      final aDate = a['monthStart'] as DateTime;
      final bDate = b['monthStart'] as DateTime;
      return aDate.compareTo(bDate);
    });

    return result;
  }

  /// Get statistics for all habits
  static Future<List<HabitStatistics>> getAllHabitsStatistics(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Query daily progress records
    final records = await DailyProgressQueryService.queryDailyProgress(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      orderDescending: false,
    );

    // Collect all unique habit names
    final habitNames = <String>{};
    for (final record in records) {
      for (final habit in record.habitBreakdown) {
        final name = habit['name'] as String?;
        if (name != null && name.isNotEmpty) {
          habitNames.add(name);
        }
      }
    }

    // Get statistics for each habit
    final statistics = <HabitStatistics>[];
    for (final habitName in habitNames) {
      final stats = await getHabitStatistics(
        userId,
        habitName,
        startDate: startDate,
        endDate: endDate,
      );
      statistics.add(stats);
    }

    // Sort by completion rate descending
    statistics.sort((a, b) => b.completionRate.compareTo(a.completionRate));

    return statistics;
  }

  /// Get completion history for calendar/heatmap view
  static Future<Map<DateTime, String>> getHabitCompletionHistory(
    String userId,
    String habitName,
    int days,
  ) async {
    final endDate = DateService.currentDate;
    final startDate = endDate.subtract(Duration(days: days));

    final stats = await getHabitStatistics(
      userId,
      habitName,
      startDate: startDate,
      endDate: endDate,
    );

    final history = <DateTime, String>{};
    for (final day in stats.dailyHistory) {
      final date = day['date'] as DateTime?;
      if (date != null) {
        final normalizedDate = DateService.normalizeToStartOfDay(date);
        history[normalizedDate] = day['status'] as String? ?? 'pending';
      }
    }

    return history;
  }

  // ==================== HELPER CALCULATION METHODS ====================

  /// Calculate total time spent from completed instances
  static Duration _calculateTotalTimeSpent(
      List<ActivityInstanceRecord> instances) {
    int totalMilliseconds = 0;
    for (final instance in instances) {
      // Use totalTimeLogged if available, otherwise accumulatedTime
      if (instance.hasTotalTimeLogged() && instance.totalTimeLogged > 0) {
        totalMilliseconds += instance.totalTimeLogged;
      } else if (instance.hasAccumulatedTime() &&
          instance.accumulatedTime > 0) {
        totalMilliseconds += instance.accumulatedTime;
      } else if (instance.hasTimeLogSessions()) {
        // Sum up all session durations
        for (final session in instance.timeLogSessions) {
          final duration = session['durationMilliseconds'] as int? ?? 0;
          totalMilliseconds += duration;
        }
      }
    }
    return Duration(milliseconds: totalMilliseconds);
  }

  /// Calculate total number of sessions
  static int _calculateTotalSessions(List<ActivityInstanceRecord> instances) {
    int totalSessions = 0;
    for (final instance in instances) {
      if (instance.hasTimeLogSessions()) {
        totalSessions += instance.timeLogSessions.length;
      } else if (instance.hasTotalTimeLogged() &&
          instance.totalTimeLogged > 0) {
        // If there's logged time but no sessions, count as 1 session
        totalSessions += 1;
      } else if (instance.hasAccumulatedTime() &&
          instance.accumulatedTime > 0) {
        totalSessions += 1;
      }
    }
    return totalSessions;
  }

  /// Calculate total quantity completed
  static double _calculateTotalQuantityCompleted(
      List<ActivityInstanceRecord> instances) {
    double total = 0.0;
    for (final instance in instances) {
      if (instance.hasCurrentValue()) {
        final value = instance.currentValue;
        if (value is num) {
          total += value.toDouble();
        }
      }
    }
    return total;
  }

  /// Calculate completions by hour (0-23)
  static Map<int, int> _calculateCompletionsByHour(
      List<ActivityInstanceRecord> instances) {
    final map = <int, int>{};
    for (int i = 0; i < 24; i++) {
      map[i] = 0;
    }

    for (final instance in instances) {
      if (instance.completedAt != null) {
        final hour = instance.completedAt!.hour;
        map[hour] = (map[hour] ?? 0) + 1;
      }
    }

    return map;
  }

  /// Calculate best day of week (most completions)
  static int? _calculateBestDayOfWeek(Map<int, int> completionsByDayOfWeek) {
    if (completionsByDayOfWeek.isEmpty) return null;

    int maxCompletions = 0;
    int? bestDay;

    for (final entry in completionsByDayOfWeek.entries) {
      if (entry.value > maxCompletions) {
        maxCompletions = entry.value;
        bestDay = entry.key;
      }
    }

    return bestDay;
  }

  /// Calculate best week (highest completion rate)
  static DateTime? _calculateBestWeek(
      List<Map<String, dynamic>> weeklyBreakdown) {
    if (weeklyBreakdown.isEmpty) return null;

    double maxRate = 0.0;
    DateTime? bestWeek;

    for (final week in weeklyBreakdown) {
      final rate = week['completionRate'] as double;
      if (rate > maxRate) {
        maxRate = rate;
        bestWeek = week['weekStart'] as DateTime;
      }
    }

    return bestWeek;
  }

  /// Calculate best month (highest completion rate)
  static DateTime? _calculateBestMonth(
      List<Map<String, dynamic>> monthlyBreakdown) {
    if (monthlyBreakdown.isEmpty) return null;

    double maxRate = 0.0;
    DateTime? bestMonth;

    for (final month in monthlyBreakdown) {
      final rate = month['completionRate'] as double;
      if (rate > maxRate) {
        maxRate = rate;
        bestMonth = month['monthStart'] as DateTime;
      }
    }

    return bestMonth;
  }

  /// Calculate consistency score (inverse of variance, normalized to 0-100)
  static double _calculateConsistencyScore(List<double> completionRates) {
    if (completionRates.isEmpty) return 0.0;
    if (completionRates.length == 1) return 100.0;

    // Calculate mean
    final mean =
        completionRates.reduce((a, b) => a + b) / completionRates.length;

    // Calculate variance
    final variance = completionRates.map((rate) {
          final diff = rate - mean;
          return diff * diff;
        }).reduce((a, b) => a + b) /
        completionRates.length;

    // Calculate standard deviation
    final stdDev = math.sqrt(variance);

    // Normalize: higher consistency = lower std dev
    // Score = 100 * (1 - stdDev / maxPossibleStdDev)
    // Max possible std dev for 0-100 range is ~50
    final maxStdDev = 50.0;
    final score = 100.0 * (1.0 - (stdDev / maxStdDev).clamp(0.0, 1.0));

    return score.clamp(0.0, 100.0);
  }
}

/// Data class for habit statistics
class HabitStatistics {
  final String habitName;
  final double completionRate;
  final int totalCompletions;
  final int totalDaysTracked;
  final double averagePointsEarned;
  final List<Map<String, dynamic>> dailyHistory;
  final Map<String, int> statusBreakdown;

  // New fields
  final String? trackingType; // 'time', 'quantity', 'simple', etc.
  final Duration totalTimeSpent;
  final Duration averageSessionDuration;
  final int totalSessions;
  final double totalQuantityCompleted;
  final double averageQuantityPerCompletion;
  final int? bestDayOfWeek; // 1=Monday, 7=Sunday
  final DateTime? bestWeek;
  final DateTime? bestMonth;
  final Map<int, int> completionsByDayOfWeek;
  final Map<int, int> completionsByHour;
  final List<Map<String, dynamic>> weeklyBreakdown;
  final List<Map<String, dynamic>> monthlyBreakdown;
  final double consistencyScore;

  HabitStatistics({
    required this.habitName,
    required this.completionRate,
    required this.totalCompletions,
    required this.totalDaysTracked,
    required this.averagePointsEarned,
    required this.dailyHistory,
    required this.statusBreakdown,
    this.trackingType,
    this.totalTimeSpent = const Duration(),
    this.averageSessionDuration = const Duration(),
    this.totalSessions = 0,
    this.totalQuantityCompleted = 0.0,
    this.averageQuantityPerCompletion = 0.0,
    this.bestDayOfWeek,
    this.bestWeek,
    this.bestMonth,
    this.completionsByDayOfWeek = const {},
    this.completionsByHour = const {},
    this.weeklyBreakdown = const [],
    this.monthlyBreakdown = const [],
    this.consistencyScore = 0.0,
  });
}
