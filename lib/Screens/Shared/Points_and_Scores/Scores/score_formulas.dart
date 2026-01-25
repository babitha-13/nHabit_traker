import 'dart:math';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';

/// Pure mathematical formulas for score calculations
/// No database access, no state management, no side effects
/// All functions are pure and testable
class ScoreFormulas {
  // Configuration constants
  static const double basePointsPerDay = 10.0;
  static const double weeklyWeight = 0.6;
  static const double monthlyWeight = 0.4;
  static const double consistencyThreshold = 80.0;
  static const double decayThreshold = 50.0;
  static const double penaltyBaseMultiplier = 0.04;
  static const double categoryNeglectPenalty = 0.4;
  static const double consistencyBonusFull = 5.0;
  static const double consistencyBonusPartial = 2.0;

  /// Calculate daily score based on completion percentage and raw points earned
  static double calculateDailyScore(
    double completionPercentage,
    double rawPointsEarned,
  ) {
    // Percentage component (max 10 points)
    final percentageComponent =
        (completionPercentage / 100.0) * basePointsPerDay;

    // Raw points bonus using square root scaling divided by 2
    final rawPointsBonus = sqrt(rawPointsEarned) / 2.0;

    // Combined score (no cap)
    return percentageComponent + rawPointsBonus;
  }

  /// Calculate consistency bonus based on 7-day performance
  static double calculateConsistencyBonus(List<DailyProgressRecord> last7Days) {
    if (last7Days.length < 7) return 0.0;

    final highPerformanceDays = last7Days
        .where((day) => day.completionPercentage >= consistencyThreshold)
        .length;

    if (highPerformanceDays == 7) {
      return consistencyBonusFull;
    } else if (highPerformanceDays >= 5) {
      return consistencyBonusPartial;
    }
    return 0.0;
  }

  /// Calculate combined penalty for poor performance with diminishing returns over time
  static double calculateCombinedPenalty(
    double dailyCompletion,
    int consecutiveLowDays,
  ) {
    if (dailyCompletion >= decayThreshold) return 0.0;

    // Combined penalty with diminishing returns over time
    // Formula: (50 - completion%) * 0.04 / log(consecutiveDays + 1)
    final pointsBelowThreshold = decayThreshold - dailyCompletion;
    final penalty = pointsBelowThreshold *
        penaltyBaseMultiplier /
        log(consecutiveLowDays + 1);

    return penalty;
  }

  /// Calculate recovery bonus when breaking low-completion streak
  static double calculateRecoveryBonus(int consecutiveLowDays) {
    if (consecutiveLowDays == 0) return 0.0;

    // Recovery bonus when breaking low-completion streak
    // Capped at 5 points to ensure < 50% of typical penalties
    // Formula: min(5, sqrt(consecutiveLowDays) * 1.0)
    final bonus = sqrt(consecutiveLowDays) * 1.0;
    return min(5.0, bonus);
  }

  /// Calculate category neglect penalty for ignored habit categories
  /// Penalty: 0.4 points per category with >1 habit that has zero activity
  /// Note: habitInstances should already be filtered for the target date
  static double calculateCategoryNeglectPenalty(
    List<CategoryRecord> categories,
    List<ActivityInstanceRecord> habitInstances,
    DateTime targetDate,
  ) {
    if (categories.isEmpty || habitInstances.isEmpty) return 0.0;

    final normalizedDate = DateService.normalizeToStartOfDay(targetDate);
    double totalPenalty = 0.0;

    for (final category in categories) {
      // Only check habit categories
      if (category.categoryType != 'habit') continue;

      // Filter habits that belong to the target date
      // For habits, use completedAt for completed habits, belongsToDate/dueDate for pending habits
      final todayHabits = habitInstances.where((inst) {
        // Must be in this category
        if (inst.templateCategoryId != category.reference.id) return false;
        
        // For habits, check if belongs to target date
        if (inst.templateCategoryType == 'habit') {
          // For completed habits, use completedAt date (the day it was actually completed)
          if (inst.status == 'completed' && inst.completedAt != null) {
            final completedDate = DateService.normalizeToStartOfDay(inst.completedAt!);
            return completedDate.isAtSameMomentAs(normalizedDate);
          }
          
          // For pending/in-progress habits, use belongsToDate (or dueDate) - the day they belong to
          if (inst.belongsToDate != null) {
            final belongsDate = DateService.normalizeToStartOfDay(inst.belongsToDate!);
            return belongsDate.isAtSameMomentAs(normalizedDate);
          }
          
          // Fallback: if no belongsToDate, check dueDate
          if (inst.dueDate != null) {
            final dueDateOnly = DateService.normalizeToStartOfDay(inst.dueDate!);
            return dueDateOnly.isAtSameMomentAs(normalizedDate);
          }
          
          // Check if has current activity (currentValue or accumulatedTime) for today
          // This handles habits that are in progress today
          if (inst.currentValue != null) {
            final value = inst.currentValue;
            if (value is num && value > 0) return true;
          }
          if (inst.accumulatedTime > 0) return true;
          
          return false;
        }
        return false;
      }).toList();

      // Only apply penalty if category has more than 1 habit for today
      if (todayHabits.length <= 1) continue;

      // Check if category has any activity (completed or partial) for today
      bool hasActivity = false;
      for (final habit in todayHabits) {
        // Check if completed on target date
        if (habit.status == 'completed' && habit.completedAt != null) {
          final completedDate =
              DateService.normalizeToStartOfDay(habit.completedAt!);
          if (completedDate.isAtSameMomentAs(normalizedDate)) {
            hasActivity = true;
            break;
          }
        }
        // Check if has partial progress (currentValue > 0) - only counts if belongs to today
        if (habit.currentValue != null) {
          final value = habit.currentValue;
          if (value is num && value > 0) {
            hasActivity = true;
            break;
          }
        }
        // Check if has time logged - only counts if belongs to today
        final accumulatedTime = habit.accumulatedTime;
        if (accumulatedTime > 0) {
          hasActivity = true;
          break;
        }
      }

      // If no activity in category with >1 habit, apply penalty
      if (!hasActivity) {
        totalPenalty += categoryNeglectPenalty;
      }
    }

    return totalPenalty;
  }

  /// Calculate weighted performance score from weekly and monthly averages
  static double calculateWeightedPerformance(
    List<DailyProgressRecord> last7Days,
    List<DailyProgressRecord> last30Days,
  ) {
    final weeklyAvg = _calculateAverageCompletion(last7Days);
    final monthlyAvg = _calculateAverageCompletion(last30Days);

    return (weeklyAvg * weeklyWeight) + (monthlyAvg * monthlyWeight);
  }

  /// Calculate current streak based on recent performance
  static int calculateCurrentStreak(
    List<DailyProgressRecord> last7Days,
    double todayCompletion,
  ) {
    int streak = 0;

    // Check today's performance
    if (todayCompletion >= consistencyThreshold) {
      streak = 1;
    } else {
      return 0;
    }

    // Count backwards from yesterday
    for (int i = last7Days.length - 1; i >= 0; i--) {
      if (last7Days[i].completionPercentage >= consistencyThreshold) {
        streak++;
      } else {
        break;
      }
    }

    return streak;
  }

  /// Calculate average completion percentage from a list of progress records
  static double _calculateAverageCompletion(List<DailyProgressRecord> records) {
    if (records.isEmpty) return 0.0;
    final total =
        records.fold(0.0, (sum, record) => sum + record.completionPercentage);
    return total / records.length;
  }
}
