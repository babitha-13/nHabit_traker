import 'package:flutter/foundation.dart';
import 'package:habit_tracker/features/Progress/Point_system_helper/points_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';

/// Service to calculate daily progress for a specific date
/// Used by both Queue page (for today) and DayEndProcessor (for historical dates)
/// This ensures 100% consistency between live and saved progress values
class DailyProgressCalculator {
  // Temporary diagnostics to debug "missing habit in today's breakdown".
  static const bool _debugTodayBreakdown = true;

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
    // Exclude essential types
    final inWindowHabits = allInstances.where((inst) {
      if (!inst.isActive) return false;
      if (inst.templateCategoryType != 'habit') return false;
      if (inst.templateCategoryType == 'essential') return false;
      if (!_isWithinWindow(inst, normalizedDate)) return false;
      return true;
    }).toList();
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

    if (_shouldDebugForDate(normalizedDate)) {
      _logHabitDiagnostics(
        mode: 'async',
        normalizedDate: normalizedDate,
        allHabits: allInstances,
        inWindowHabits: inWindowHabits,
        earnedSet: earnedSet,
      );
    }
    // Instances used for target/percentage math
    final allForMath = inWindowHabits;
    // ==================== TASK FILTERING ====================
    // Filter tasks by completion date logic:
    // - Pending tasks due on/before targetDate (includes overdue)
    // - Completed tasks where completedAt date matches targetDate
    // - Exclude skipped/rescheduled tasks (not due on targetDate)
    final pendingTasks = taskInstances.where((task) {
      if (!task.isActive) return false;
      if (task.status != 'pending') return false;
      if (task.dueDate == null) return false;
      return !task.dueDate!.isAfter(normalizedDate);
    }).toList();
    final completedTasksOnDate = taskInstances.where((task) {
      if (!task.isActive) return false;
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
    // Exclude Essential Activities
    final allTasksForMath = taskInstances.where((task) {
      if (!task.isActive) return false;
      // Skip Essential Activities
      if (task.templateCategoryType == 'essential') return false;
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

    // Use the SAME PointsService methods as Queue page
    double habitTargetPoints;
    try {
      habitTargetPoints =
          await PointsService.calculateTotalDailyTargetWithTemplates(
              allForMath, userId);
    } catch (e) {
      habitTargetPoints = PointsService.calculateTotalDailyTarget(allForMath);
    }
    final habitEarnedPoints =
        await PointsService.calculateTotalPointsEarned(earnedSet, userId);
    // Calculate task points using unified PointsService method
    final taskTargetPoints =
        _calculateTaskTargetFromActivityInstances(allTasksForMath);
    final taskEarnedPoints =
        await PointsService.calculatePointsFromActivityInstances(
            allTasksForMath, userId);
    // Combine habit and task points
    final totalTargetPoints = habitTargetPoints + taskTargetPoints;
    final totalEarnedPoints = habitEarnedPoints + taskEarnedPoints;
    final percentage = PointsService.calculateDailyPerformancePercent(
        totalEarnedPoints, totalTargetPoints);
    // Calculate detailed breakdown for habits
    final habitBreakdown = <Map<String, dynamic>>[];
    for (final habit in allForMath) {
      final target = PointsService.calculateDailyTarget(habit);
      final earned = await _calculateHabitEarnedForDateAsync(
        habit: habit,
        userId: userId,
        targetDate: normalizedDate,
      );
      final progress = target > 0 ? (earned / target).clamp(0.0, 1.0) : 0.0;

      if (_shouldDebugForDate(normalizedDate)) {
        debugPrint('[today-breakdown-debug][async] UI_ITEM '
            'id=${habit.reference.id} name="${habit.templateName}" '
            'status=${habit.status} tracking=${habit.templateTrackingType} '
            'target=${_formatNumber(target)} earned=${_formatNumber(earned)} '
            'progress=${_formatNumber(progress)}');
      }

      dynamic quantity;
      if (habit.hasCurrentValue() && habit.currentValue is num) {
        quantity = (habit.currentValue as num).toDouble();
      }

      int? timeSpent;
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
    // Calculate detailed breakdown for tasks
    final taskBreakdown = <Map<String, dynamic>>[];
    for (final task in allTasksForMath) {
      final target = _calculateTaskTargetFromActivityInstances([task]);
      final earned = await PointsService.calculatePointsEarned(task, userId);
      final progress = target > 0 ? (earned / target).clamp(0.0, 1.0) : 0.0;
      taskBreakdown.add({
        'name': task.templateName,
        'status': task.status,
        'target': target,
        'earned': earned,
        'progress': progress,
      });
    }

    if (_shouldDebugForDate(normalizedDate)) {
      debugPrint('[today-breakdown-debug][async] SUMMARY '
          'habitBreakdown=${habitBreakdown.length} '
          'taskBreakdown=${taskBreakdown.length} '
          'habitTarget=${_formatNumber(habitTargetPoints)} '
          'habitEarned=${_formatNumber(habitEarnedPoints)} '
          'taskTarget=${_formatNumber(taskTargetPoints)} '
          'taskEarned=${_formatNumber(taskEarnedPoints)}');
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
    // Some legacy records may miss dueDate but still have belongsToDate.
    // Use belongsToDate as a safe fallback to avoid over-including items.
    final startSource = instance.dueDate ?? instance.belongsToDate;
    if (startSource == null) return false;
    final dueDate =
        DateTime(startSource.year, startSource.month, startSource.day);
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

  /// Calculate daily progress optimistically from local instances (no Firestore queries)
  /// Use this for instant UI updates after instance changes
  /// Returns: {target, earned, percentage}
  /// Calculate today's progress instantly using only cached instance data
  /// No Firestore queries - like an Excel sheet calculation
  /// Returns immediately with synchronous calculation
  static Map<String, dynamic> calculateTodayProgressOptimistic({
    required String userId,
    required List<ActivityInstanceRecord> allInstances,
    required List<CategoryRecord> categories,
    List<ActivityInstanceRecord> taskInstances = const [],
  }) {
    final today = DateService.currentDate;
    final normalizedDate = DateTime(today.year, today.month, today.day);

    // Build instances within window for today (status-agnostic)
    // Exclude essential types
    final inWindowHabits = allInstances.where((inst) {
      if (!inst.isActive) return false;
      if (inst.templateCategoryType != 'habit') return false;
      if (inst.templateCategoryType == 'essential') return false;
      if (!_isWithinWindow(inst, normalizedDate)) return false;
      return true;
    }).toList();

    // For earned math: include
    // - completed instances only if completed today
    // - non-completed instances (pending/snoozed/etc.) to allow differential points
    final earnedSet = inWindowHabits.where((inst) {
      if (inst.status == 'completed') {
        return _wasCompletedOnDate(inst, normalizedDate);
      }
      return true; // include non-completed for differential contribution
    }).toList();

    if (_shouldDebugForDate(normalizedDate)) {
      _logHabitDiagnostics(
        mode: 'optimistic',
        normalizedDate: normalizedDate,
        allHabits: allInstances,
        inWindowHabits: inWindowHabits,
        earnedSet: earnedSet,
      );
    }

    // Instances used for target/percentage math
    final allForMath = inWindowHabits;

    // ==================== TASK FILTERING ====================
    // Filter tasks by completion date logic for today
    final allTasksForMath = taskInstances.where((task) {
      if (!task.isActive) return false;
      // Skip Essential Activities
      if (task.templateCategoryType == 'essential') return false;
      // Include if completed today
      if (task.status == 'completed' && task.completedAt != null) {
        final completedDate = DateTime(
          task.completedAt!.year,
          task.completedAt!.month,
          task.completedAt!.day,
        );
        return completedDate.isAtSameMomentAs(normalizedDate);
      }
      // Include if pending and due on/before today
      if (task.status == 'pending' && task.dueDate != null) {
        return !task.dueDate!.isAfter(normalizedDate);
      }
      return false;
    }).toList();

    // INSTANT CALCULATION: Use synchronous method without ANY Firestore queries
    // This uses ONLY cached template data from instances - like an Excel sheet
    final habitTargetPoints =
        PointsService.calculateTotalDailyTarget(allForMath);
    final habitEarnedPoints =
        PointsService.calculateTotalPointsEarnedSync(earnedSet);

    // Calculate task points using unified PointsService method (synchronous)
    final taskTargetPoints =
        _calculateTaskTargetFromActivityInstances(allTasksForMath);
    final taskEarnedPoints =
        PointsService.calculatePointsFromActivityInstancesSync(allTasksForMath);

    // Combine habit and task points
    final totalTargetPoints = habitTargetPoints + taskTargetPoints;
    final totalEarnedPoints = habitEarnedPoints + taskEarnedPoints;
    final percentage = PointsService.calculateDailyPerformancePercent(
        totalEarnedPoints, totalTargetPoints);

    // Build detailed breakdown synchronously from local instance data.
    final habitBreakdown = <Map<String, dynamic>>[];
    for (final habit in allForMath) {
      final target = PointsService.calculateDailyTarget(habit);
      final earned = _calculateHabitEarnedForDateSync(
        habit: habit,
        targetDate: normalizedDate,
      );
      final progress = target > 0 ? (earned / target).clamp(0.0, 1.0) : 0.0;

      if (_shouldDebugForDate(normalizedDate)) {
        debugPrint('[today-breakdown-debug][optimistic] UI_ITEM '
            'id=${habit.reference.id} name="${habit.templateName}" '
            'status=${habit.status} tracking=${habit.templateTrackingType} '
            'target=${_formatNumber(target)} earned=${_formatNumber(earned)} '
            'progress=${_formatNumber(progress)}');
      }

      dynamic quantity;
      if (habit.hasCurrentValue() && habit.currentValue is num) {
        quantity = (habit.currentValue as num).toDouble();
      }

      int? timeSpent;
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

    final taskBreakdown = <Map<String, dynamic>>[];
    for (final task in allTasksForMath) {
      final target = _calculateTaskTargetFromActivityInstances([task]);
      final earned = PointsService.calculatePointsEarnedSync(task);
      final progress = target > 0 ? (earned / target).clamp(0.0, 1.0) : 0.0;
      taskBreakdown.add({
        'name': task.templateName,
        'status': task.status,
        'target': target,
        'earned': earned,
        'progress': progress,
      });
    }

    if (_shouldDebugForDate(normalizedDate)) {
      debugPrint('[today-breakdown-debug][optimistic] SUMMARY '
          'habitBreakdown=${habitBreakdown.length} '
          'taskBreakdown=${taskBreakdown.length} '
          'habitTarget=${_formatNumber(habitTargetPoints)} '
          'habitEarned=${_formatNumber(habitEarnedPoints)} '
          'taskTarget=${_formatNumber(taskTargetPoints)} '
          'taskEarned=${_formatNumber(taskEarnedPoints)}');
    }

    return {
      'target': totalTargetPoints,
      'earned': totalEarnedPoints,
      'percentage': percentage,
      'habitTarget': habitTargetPoints,
      'habitEarned': habitEarnedPoints,
      'taskTarget': taskTargetPoints,
      'taskEarned': taskEarnedPoints,
      'habitBreakdown': habitBreakdown,
      'taskBreakdown': taskBreakdown,
      'totalHabits': allForMath.length,
      'totalTasks': allTasksForMath.length,
    };
  }

  /// Calculate task target points from ActivityInstanceRecord list
  /// For tasks: use unified instance target calculation from PointsService.
  static double _calculateTaskTargetFromActivityInstances(
      List<ActivityInstanceRecord> taskInstances) {
    double totalTarget = 0.0;
    for (final task in taskInstances) {
      totalTarget += PointsService.calculateInstanceTargetPoints(task);
    }
    return totalTarget;
  }

  static bool _shouldDebugForDate(DateTime normalizedDate) {
    if (!kDebugMode || !_debugTodayBreakdown) return false;
    final today = DateService.todayStart;
    return normalizedDate.year == today.year &&
        normalizedDate.month == today.month &&
        normalizedDate.day == today.day;
  }

  static void _logHabitDiagnostics({
    required String mode,
    required DateTime normalizedDate,
    required List<ActivityInstanceRecord> allHabits,
    required List<ActivityInstanceRecord> inWindowHabits,
    required List<ActivityInstanceRecord> earnedSet,
  }) {
    final inWindowIds = inWindowHabits.map((e) => e.reference.id).toSet();
    final earnedIds = earnedSet.map((e) => e.reference.id).toSet();

    debugPrint('[today-breakdown-debug][$mode] INPUT '
        'date=${_formatDate(normalizedDate)} '
        'allHabits=${allHabits.where((h) => h.templateCategoryType == 'habit').length} '
        'inWindowHabits=${inWindowHabits.length} earnedSet=${earnedSet.length}');

    final habitCandidates = allHabits
        .where((h) => h.templateCategoryType == 'habit')
        .toList()
      ..sort((a, b) => a.templateName.compareTo(b.templateName));

    for (final habit in habitCandidates) {
      String reason = 'included';
      if (!habit.isActive) {
        reason = 'inactive';
      } else if (habit.templateCategoryType == 'essential') {
        reason = 'essential';
      } else if (!inWindowIds.contains(habit.reference.id)) {
        reason = 'outside_window';
      } else if (habit.status == 'completed' &&
          !_wasCompletedOnDate(habit, normalizedDate)) {
        reason = 'completed_before_date(excluded_from_earned)';
      }

      debugPrint('[today-breakdown-debug][$mode] HABIT '
          'id=${habit.reference.id} name="${habit.templateName}" '
          'status=${habit.status} tracking=${habit.templateTrackingType} '
          'windowDuration=${habit.windowDuration} '
          'due=${_formatDate(habit.dueDate)} '
          'windowEnd=${_formatDate(habit.windowEndDate)} '
          'completedAt=${_formatDate(habit.completedAt)} '
          'currentValue=${habit.currentValue} lastDayValue=${habit.lastDayValue} '
          'target=${habit.templateTarget} '
          'inWindow=${inWindowIds.contains(habit.reference.id)} '
          'inEarned=${earnedIds.contains(habit.reference.id)} '
          'reason=$reason');
    }
  }

  static String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final dt = DateTime(value.year, value.month, value.day);
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$mm-$dd';
  }

  static String _formatNumber(num value) {
    return value.toStringAsFixed(4);
  }

  static Future<double> _calculateHabitEarnedForDateAsync({
    required ActivityInstanceRecord habit,
    required String userId,
    required DateTime targetDate,
  }) async {
    if (habit.status == 'completed' && !_wasCompletedOnDate(habit, targetDate)) {
      return 0.0;
    }
    return PointsService.calculatePointsEarned(habit, userId);
  }

  static double _calculateHabitEarnedForDateSync({
    required ActivityInstanceRecord habit,
    required DateTime targetDate,
  }) {
    if (habit.status == 'completed' && !_wasCompletedOnDate(habit, targetDate)) {
      return 0.0;
    }
    return PointsService.calculatePointsEarnedSync(habit);
  }
}
