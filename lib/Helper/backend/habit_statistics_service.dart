import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';

/// Service to aggregate historical habit statistics from DailyProgressRecord
class HabitStatisticsService {
  /// Get statistics for a specific habit
  static Future<HabitStatistics> getHabitStatistics(
    String userId,
    String habitName, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Query daily progress records
    Query query = DailyProgressRecord.collectionForUser(userId);
    
    if (startDate != null) {
      final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
      query = query.where('date', isGreaterThanOrEqualTo: normalizedStart);
    }
    
    if (endDate != null) {
      final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);
      query = query.where('date', isLessThanOrEqualTo: normalizedEnd);
    }
    
    final snapshot = await query.orderBy('date', descending: false).get();
    final records = snapshot.docs
        .map((doc) => DailyProgressRecord.fromSnapshot(doc))
        .toList();
    
    // Aggregate data for this habit
    final dailyHistory = <Map<String, dynamic>>[];
    int totalCompletions = 0;
    int totalDaysTracked = 0;
    double totalPointsEarned = 0.0;
    final statusBreakdown = <String, int>{
      'completed': 0,
      'skipped': 0,
      'pending': 0,
    };
    
    for (final record in records) {
      if (record.date == null) continue;
      
      // Find this habit in the breakdown
      final habitDataList = record.habitBreakdown.where(
        (h) => (h['name'] as String?) == habitName,
      ).toList();
      
      if (habitDataList.isEmpty) continue;
      
      final habitData = habitDataList.first;
      totalDaysTracked++;
      final status = habitData['status'] as String? ?? 'pending';
      final earned = (habitData['earned'] as num?)?.toDouble() ?? 0.0;
      final target = (habitData['target'] as num?)?.toDouble() ?? 0.0;
      
      dailyHistory.add({
        'date': record.date,
        'status': status,
        'earned': earned,
        'target': target,
        'progress': target > 0 ? (earned / target).clamp(0.0, 1.0) : 0.0,
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
    
    final completionRate = totalDaysTracked > 0
        ? (totalCompletions / totalDaysTracked) * 100.0
        : 0.0;
    final averagePointsEarned = totalDaysTracked > 0
        ? totalPointsEarned / totalDaysTracked
        : 0.0;
    
    return HabitStatistics(
      habitName: habitName,
      completionRate: completionRate,
      totalCompletions: totalCompletions,
      totalDaysTracked: totalDaysTracked,
      averagePointsEarned: averagePointsEarned,
      dailyHistory: dailyHistory,
      statusBreakdown: statusBreakdown,
    );
  }
  
  /// Get statistics for all habits
  static Future<List<HabitStatistics>> getAllHabitsStatistics(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Query daily progress records
    Query query = DailyProgressRecord.collectionForUser(userId);
    
    if (startDate != null) {
      final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
      query = query.where('date', isGreaterThanOrEqualTo: normalizedStart);
    }
    
    if (endDate != null) {
      final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);
      query = query.where('date', isLessThanOrEqualTo: normalizedEnd);
    }
    
    final snapshot = await query.orderBy('date', descending: false).get();
    final records = snapshot.docs
        .map((doc) => DailyProgressRecord.fromSnapshot(doc))
        .toList();
    
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
        final normalizedDate = DateTime(date.year, date.month, date.day);
        history[normalizedDate] = day['status'] as String? ?? 'pending';
      }
    }
    
    return history;
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
  
  HabitStatistics({
    required this.habitName,
    required this.completionRate,
    required this.totalCompletions,
    required this.totalDaysTracked,
    required this.averagePointsEarned,
    required this.dailyHistory,
    required this.statusBreakdown,
  });
}

