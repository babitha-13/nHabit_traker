import 'package:habit_tracker/Helper/backend/points_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/backend/cumulative_score_service.dart';

/// Service to calculate daily progress for a specific date
/// Used by both Queue page (for today) and DayEndProcessor (for historical dates)
/// This ensures 100% consistency between live and saved progress values
class DailyProgressCalculator {
  /// Calculate daily progress for a specific date
  /// Returns: {target, earned, percentage, instances, taskInstances}
  static Future<Map<String, dynamic>> calculateDailyProgress({
    required String userId,
    required DateTime targetDate,
    required List<ActivityInstanceRecord> allInstances,
    required List<CategoryRecord> categories,
    List<ActivityInstanceRecord> taskInstances = const [],
    bool includeSkippedForComputation = true,
  }) async {
    final normalizedDate =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    // Build instances within window for the target date (status-agnostic)
    // This set is used for target calculations and counts
    // Exclude non-productive and legacy sequence_item types
    final inWindowHabits = allInstances
        .where((inst) =>
            inst.templateCategoryType == 'habit' &&
            inst.templateCategoryType != 'non_productive' &&
            inst.templateCategoryType != 'sequence_item' &&
            _isWithinWindow(inst, normalizedDate))
        .toList();
    // For UI/display list: pending + completed-on-date (unchanged behavior)
    final pendingHabits =
        inWindowHabits.where((inst) => inst.status == 'pending').toList();
    final completedOnDate = inWindowHabits
        .where((inst) =>
            inst.status == 'completed' &&
            _wasCompletedOnDate(inst, normalizedDate))
        .toList();
    final displayHabits = [...pendingHabits, ...completedOnDate];
    // For earned math: include
    // - completed instances only if completed on the target date
    // - non-completed instances (pending/snoozed/etc.) to allow differential points
    final earnedSet = inWindowHabits.where((inst) {
      if (inst.status == 'completed') {
        return _wasCompletedOnDate(inst, normalizedDate);
      }
      return true; // include non-completed for differential contribution
    }).toList();
    // Instances used for target/percentage math
    final allForMath = inWindowHabits;
    // ==================== TASK FILTERING ====================
    // Filter tasks by completion date logic:
    // - Pending tasks due on/before targetDate (includes overdue)
    // - Completed tasks where completedAt date matches targetDate
    // - Exclude skipped/rescheduled tasks (not due on targetDate)
    final pendingTasks = taskInstances.where((task) {
      if (task.status != 'pending') return false;
      if (task.dueDate == null) return false;
      return !task.dueDate!.isAfter(normalizedDate);
    }).toList();
    final completedTasksOnDate = taskInstances.where((task) {
      if (task.status != 'completed' || task.completedAt == null) return false;
      final completedDate = DateTime(
        task.completedAt!.year,
        task.completedAt!.month,
        task.completedAt!.day,
      );
      return completedDate.isAtSameMomentAs(normalizedDate);
    }).toList();
    final displayTasks = [...pendingTasks, ...completedTasksOnDate];
    // For task target calculation: include all tasks that should be counted for this date
    // This includes pending tasks due on/before the date AND completed tasks completed on the date
    // Exclude non-productive items and legacy sequence_items
    final allTasksForMath = taskInstances.where((task) {
      // Skip non-productive items and legacy sequence_items
      if (task.templateCategoryType == 'non_productive' ||
          task.templateCategoryType == 'sequence_item') return false;
      // Include if completed on the target date
      if (task.status == 'completed' && task.completedAt != null) {
        final completedDate = DateTime(
          task.completedAt!.year,
          task.completedAt!.month,
          task.completedAt!.day,
        );
        return completedDate.isAtSameMomentAs(normalizedDate);
      }
      // Include if pending and due on/before the target date
      if (task.status == 'pending' && task.dueDate != null) {
        return !task.dueDate!.isAfter(normalizedDate);
      }
      return false;
    }).toList();

    // includeSkippedForComputation is now implicit via inWindowHabits (status-agnostic)
    if (includeSkippedForComputation) {
      final skippedCount =
          inWindowHabits.where((i) => i.status == 'skipped').length;
    }

    // Use the SAME PointsService methods as Queue page
    double habitTargetPoints;
    try {
      habitTargetPoints =
          await PointsService.calculateTotalDailyTargetWithTemplates(
              allForMath, categories, userId);
    } catch (e) {
      habitTargetPoints =
          PointsService.calculateTotalDailyTarget(allForMath, categories);
    }
    final habitEarnedPoints =
        PointsService.calculateTotalPointsEarned(earnedSet, categories);
    // Calculate task points using ActivityInstanceRecord
    final taskTargetPoints =
        _calculateTaskTargetFromActivityInstances(allTasksForMath);
    final taskEarnedPoints =
        _calculateTaskPointsFromActivityInstances(allTasksForMath);
    // Combine habit and task points
    final totalTargetPoints = habitTargetPoints + taskTargetPoints;
    final totalEarnedPoints = habitEarnedPoints + taskEarnedPoints;
    final percentage = PointsService.calculateDailyPerformancePercent(
        totalEarnedPoints, totalTargetPoints);
    // Calculate detailed breakdown for habits
    final habitBreakdown = <Map<String, dynamic>>[];
    for (final habit in allForMath) {
      final category = _findCategoryForInstance(habit, categories);
      if (category != null) {
        final target = PointsService.calculateDailyTarget(habit, category);
        final earned = PointsService.calculatePointsEarned(habit, category);
        final progress = target > 0 ? (earned / target).clamp(0.0, 1.0) : 0.0;
        
        // Extract additional data for statistics
        dynamic quantity;
        if (habit.hasCurrentValue() && habit.currentValue is num) {
          quantity = (habit.currentValue as num).toDouble();
        }
        
        int? timeSpent; // milliseconds
        if (habit.hasTotalTimeLogged() && habit.totalTimeLogged > 0) {
          timeSpent = habit.totalTimeLogged;
        } else if (habit.hasAccumulatedTime() && habit.accumulatedTime > 0) {
          timeSpent = habit.accumulatedTime;
        }
        
        habitBreakdown.add({
          'name': habit.templateName,
          'status': habit.status,
          'target': target,
          'earned': earned,
          'progress': progress,
          'trackingType': habit.templateTrackingType,
          'quantity': quantity,
          'timeSpent': timeSpent,
          'completedAt': habit.completedAt,
        });
      }
    }
    // Calculate detailed breakdown for tasks
    final taskBreakdown = <Map<String, dynamic>>[];
    for (final task in allTasksForMath) {
      final target = _calculateTaskTargetFromActivityInstances([task]);
      final earned = _calculateTaskPointsFromActivityInstances([task]);
      final progress = target > 0 ? (earned / target).clamp(0.0, 1.0) : 0.0;
      taskBreakdown.add({
        'name': task.templateName,
        'status': task.status,
        'target': target,
        'earned': earned,
        'progress': progress,
      });
    }
    return {
      'target': totalTargetPoints,
      'earned': totalEarnedPoints,
      'percentage': percentage,
      // Return the filtered instances for display (pending + completed)
      'instances': displayHabits,
      'taskInstances': displayTasks,
      // Also return the full set used for target math (status-agnostic, in-window)
      'allForMath': allForMath,
      'allTasksForMath': allTasksForMath,
      // Separate breakdown for analytics
      'habitTarget': habitTargetPoints,
      'habitEarned': habitEarnedPoints,
      'taskTarget': taskTargetPoints,
      'taskEarned': taskEarnedPoints,
      // Detailed breakdown for UI
      'habitBreakdown': habitBreakdown,
      'taskBreakdown': taskBreakdown,
    };
  }

  /// Check if targetDate is within the habit's window
  /// Matches Queue page _isTodayOrOverdue logic for habits
  static bool _isWithinWindow(
      ActivityInstanceRecord instance, DateTime targetDate) {
    if (instance.dueDate == null) return true;
    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);
    final windowEnd = instance.windowEndDate;
    if (windowEnd != null) {
      final windowEndNormalized =
          DateTime(windowEnd.year, windowEnd.month, windowEnd.day);
      // targetDate should be >= dueDate AND <= windowEnd
      return !targetDate.isBefore(dueDate) &&
          !targetDate.isAfter(windowEndNormalized);
    }
    // Fallback: check if due on targetDate
    return dueDate.isAtSameMomentAs(targetDate);
  }

  /// Check if instance was completed on targetDate
  /// Matches Queue page _wasCompletedToday logic
  static bool _wasCompletedOnDate(
      ActivityInstanceRecord instance, DateTime targetDate) {
    if (instance.completedAt == null) return false;
    final completedDate = DateTime(instance.completedAt!.year,
        instance.completedAt!.month, instance.completedAt!.day);
    return completedDate.isAtSameMomentAs(targetDate);
  }

  /// Calculate for "today" using DateService.currentDate
  /// This is what Queue page should use
  static Future<Map<String, dynamic>> calculateTodayProgress({
    required String userId,
    required List<ActivityInstanceRecord> allInstances,
    required List<CategoryRecord> categories,
    List<ActivityInstanceRecord> taskInstances = const [],
  }) async {
    final today = DateService.currentDate;
    return calculateDailyProgress(
      userId: userId,
      targetDate: today,
      allInstances: allInstances,
      categories: categories,
      taskInstances: taskInstances,
    );
  }

  /// Helper method to find category for an instance
  static CategoryRecord? _findCategoryForInstance(
    ActivityInstanceRecord instance,
    List<CategoryRecord> categories,
  ) {
    try {
      // First try to find by category ID
      if (instance.templateCategoryId.isNotEmpty) {
        return categories.firstWhere(
          (cat) => cat.reference.id == instance.templateCategoryId,
        );
      }
      // Fallback: try to find by category name
      if (instance.templateCategoryName.isNotEmpty) {
        return categories.firstWhere(
          (cat) => cat.name == instance.templateCategoryName,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Calculate task target points from ActivityInstanceRecord list
  /// For tasks: target = priority (no category weightage)
  static double _calculateTaskTargetFromActivityInstances(
      List<ActivityInstanceRecord> taskInstances) {
    double totalTarget = 0.0;
    for (final task in taskInstances) {
      final priority = task.templatePriority.toDouble();
      totalTarget += priority;
    }
    return totalTarget;
  }

  /// Calculate task earned points from ActivityInstanceRecord list
  /// Returns fractional points based on completion percentage
  static double _calculateTaskPointsFromActivityInstances(
      List<ActivityInstanceRecord> taskInstances) {
    double totalPoints = 0.0;
    for (final task in taskInstances) {
      final priority = task.templatePriority.toDouble();
      double points = 0.0;
      switch (task.templateTrackingType) {
        case 'binary':
          // Binary habits: use counter if available, otherwise status
          final count = task.currentValue ?? 0;
          final countValue = (count is num ? count.toDouble() : 0.0);
          if (countValue > 0) {
            // Has counter: calculate proportional points (counter / target)
            final target = task.templateTarget ?? 1;
            points = (countValue / target).clamp(0.0, 1.0) * priority;
          } else if (task.status == 'completed') {
            // No counter but completed: full points (backward compatibility)
            points = priority;
          } else {
            points = 0.0;
          }
          break;
        case 'quantitative':
          // Quantitative tasks: points based on progress percentage
          if (task.status == 'completed') {
            points = priority;
          } else {
            final currentValue = _getTaskCurrentValue(task);
            final target = _getTaskTargetValue(task);
            if (target > 0) {
              final completionFraction =
                  (currentValue / target).clamp(0.0, 1.0);
              points = completionFraction * priority;
            }
          }
          break;
        case 'time':
          // Time-based tasks: points based on accumulated time vs target
          if (task.status == 'completed') {
            final targetMinutes = _getTaskTargetValue(task);
            final durationMultiplier =
                _calculateDurationMultiplier(targetMinutes);
            points = priority * durationMultiplier;
          } else {
            final accumulatedTime = task.accumulatedTime;
            final targetMinutes = _getTaskTargetValue(task);
            final targetMs =
                targetMinutes * 60000; // Convert minutes to milliseconds
            if (targetMs > 0) {
              final completionFraction =
                  (accumulatedTime / targetMs).clamp(0.0, 1.0);
              final durationMultiplier =
                  _calculateDurationMultiplier(targetMinutes);
              points = completionFraction * priority * durationMultiplier;
            }
          }
          break;
        default:
          points = 0.0;
      }
      totalPoints += points;
    }
    return totalPoints;
  }

  /// Helper method to get current value from task instance
  static double _getTaskCurrentValue(ActivityInstanceRecord task) {
    final value = task.currentValue;

    // For time-based tracking, currentValue is in milliseconds but target is in minutes
    // Convert milliseconds to minutes for consistency
    if (task.templateTrackingType == 'time') {
      if (value is num) return (value.toDouble() / 60000.0);
      if (value is String) {
        final parsed = double.tryParse(value);
        return parsed != null ? (parsed / 60000.0) : 0.0;
      }
      return 0.0;
    }

    // For other tracking types, use value as-is
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Helper method to get target value from task instance
  static double _getTaskTargetValue(ActivityInstanceRecord task) {
    final target = task.templateTarget;
    if (target is num) return target.toDouble();
    if (target is String) return double.tryParse(target) ?? 0.0;
    return 0.0;
  }

  /// Calculate duration multiplier based on target minutes
  /// Returns the number of 15-minute blocks, minimum 1
  static int _calculateDurationMultiplier(double targetMinutes) {
    if (targetMinutes <= 0) return 1;
    return (targetMinutes / 15).round().clamp(1, double.infinity).toInt();
  }
}
