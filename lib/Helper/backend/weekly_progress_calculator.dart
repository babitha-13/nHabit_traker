import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';

/// Service to calculate weekly progress for a specific week (Sunday-Saturday)
/// Converts all targets to weekly equivalents and aggregates completion across the week
class WeeklyProgressCalculator {
  /// Calculate weekly progress for a specific week
  /// Returns: {tasks, habits, weekStart, weekEnd}
  static Future<Map<String, dynamic>> calculateWeeklyProgress({
    required String userId,
    required DateTime weekStart, // Sunday
    required List<ActivityInstanceRecord> allInstances,
    required List<CategoryRecord> categories,
  }) async {
    final weekEnd = weekStart.add(const Duration(days: 6));

    print(
        'WeeklyProgressCalculator: Calculating for week ${weekStart} to ${weekEnd}');

    // Filter instances that fall within the week range
    final weekInstances =
        _filterInstancesForWeek(allInstances, weekStart, weekEnd);

    // Separate tasks and habits
    final taskInstances = weekInstances
        .where((inst) => inst.templateCategoryType == 'task')
        .toList();
    final habitInstances = weekInstances
        .where((inst) => inst.templateCategoryType == 'habit')
        .toList();

    print(
        'WeeklyProgressCalculator: Found ${taskInstances.length} task instances, ${habitInstances.length} habit instances');

    // Process tasks - group by template and calculate weekly progress
    final processedTasks =
        _processTaskTemplates(taskInstances, weekStart, weekEnd);

    // Process habits - group by template and calculate weekly progress
    final processedHabits =
        _processHabitTemplates(habitInstances, weekStart, weekEnd);

    // Sort by completion percentage (lowest first)
    processedTasks.sort((a, b) =>
        a['completionPercentage'].compareTo(b['completionPercentage']));
    processedHabits.sort((a, b) =>
        a['completionPercentage'].compareTo(b['completionPercentage']));

    return {
      'tasks': processedTasks,
      'habits': processedHabits,
      'weekStart': weekStart,
      'weekEnd': weekEnd,
    };
  }

  /// Filter instances that are relevant for the given week
  /// For weekly view, we need to show ALL instances that are relevant to the week,
  /// including completed, skipped, and snoozed items so users can see their progress
  static List<ActivityInstanceRecord> _filterInstancesForWeek(
    List<ActivityInstanceRecord> allInstances,
    DateTime weekStart,
    DateTime weekEnd,
  ) {
    final weekInstances = <ActivityInstanceRecord>[];

    for (final instance in allInstances) {
      // For tasks: include if due date is within the week OR if it was completed/skipped during the week
      if (instance.templateCategoryType == 'task') {
        bool shouldInclude = false;

        // Include if due date is within the week
        if (instance.dueDate != null) {
          final dueDate = DateTime(instance.dueDate!.year,
              instance.dueDate!.month, instance.dueDate!.day);
          if (!dueDate.isBefore(weekStart) && !dueDate.isAfter(weekEnd)) {
            shouldInclude = true;
          }
        }

        // Also include if it was completed or skipped during the week
        if (!shouldInclude &&
            instance.status == 'completed' &&
            instance.completedAt != null) {
          final completedDate = DateTime(instance.completedAt!.year,
              instance.completedAt!.month, instance.completedAt!.day);
          if (!completedDate.isBefore(weekStart) &&
              !completedDate.isAfter(weekEnd)) {
            shouldInclude = true;
          }
        }

        if (!shouldInclude &&
            instance.status == 'skipped' &&
            instance.skippedAt != null) {
          final skippedDate = DateTime(instance.skippedAt!.year,
              instance.skippedAt!.month, instance.skippedAt!.day);
          if (!skippedDate.isBefore(weekStart) &&
              !skippedDate.isAfter(weekEnd)) {
            shouldInclude = true;
          }
        }

        if (shouldInclude) {
          weekInstances.add(instance);
        }
      }
      // For habits: include if the week overlaps with the instance window OR if it was completed/skipped during the week
      else if (instance.templateCategoryType == 'habit') {
        bool shouldInclude = false;

        // Include if the week overlaps with the instance window
        if (instance.dueDate != null && instance.windowEndDate != null) {
          final dueDate = DateTime(instance.dueDate!.year,
              instance.dueDate!.month, instance.dueDate!.day);
          final windowEnd = DateTime(instance.windowEndDate!.year,
              instance.windowEndDate!.month, instance.windowEndDate!.day);

          // Check if week overlaps with instance window
          if (!dueDate.isAfter(weekEnd) && !windowEnd.isBefore(weekStart)) {
            shouldInclude = true;
          }
        }

        // Also include if it was completed or skipped during the week
        if (!shouldInclude &&
            instance.status == 'completed' &&
            instance.completedAt != null) {
          final completedDate = DateTime(instance.completedAt!.year,
              instance.completedAt!.month, instance.completedAt!.day);
          if (!completedDate.isBefore(weekStart) &&
              !completedDate.isAfter(weekEnd)) {
            shouldInclude = true;
          }
        }

        if (!shouldInclude &&
            instance.status == 'skipped' &&
            instance.skippedAt != null) {
          final skippedDate = DateTime(instance.skippedAt!.year,
              instance.skippedAt!.month, instance.skippedAt!.day);
          if (!skippedDate.isBefore(weekStart) &&
              !skippedDate.isAfter(weekEnd)) {
            shouldInclude = true;
          }
        }

        // Include snoozed items if they were snoozed during the week
        if (!shouldInclude && instance.snoozedUntil != null) {
          final snoozedDate = DateTime(instance.snoozedUntil!.year,
              instance.snoozedUntil!.month, instance.snoozedUntil!.day);
          if (!snoozedDate.isBefore(weekStart) &&
              !snoozedDate.isAfter(weekEnd)) {
            shouldInclude = true;
          }
        }

        if (shouldInclude) {
          weekInstances.add(instance);
        }
      }
    }

    return weekInstances;
  }

  /// Process task templates and calculate weekly progress
  static List<Map<String, dynamic>> _processTaskTemplates(
    List<ActivityInstanceRecord> taskInstances,
    DateTime weekStart,
    DateTime weekEnd,
  ) {
    // Group by template ID
    final Map<String, List<ActivityInstanceRecord>> tasksByTemplate = {};
    for (final instance in taskInstances) {
      (tasksByTemplate[instance.templateId] ??= []).add(instance);
    }

    final processedTasks = <Map<String, dynamic>>[];

    for (final templateId in tasksByTemplate.keys) {
      final instances = tasksByTemplate[templateId]!;
      final firstInstance = instances.first;

      // Check if task is recurring using the cached template field
      final isRecurring = firstInstance.templateIsRecurring;

      // Convert to weekly target based on whether it's recurring
      final weeklyTarget = isRecurring
          ? _convertTaskToWeeklyTarget(firstInstance)
          : _getTargetValue(
              firstInstance); // For one-off tasks, use original target

      // Aggregate completion across the week
      final weeklyCompletion = _aggregateTaskCompletion(instances);

      // Calculate completion percentage
      final completionPercentage = weeklyTarget > 0
          ? (weeklyCompletion / weeklyTarget).clamp(0.0, 1.0)
          : 0.0;

      // Check if any task is overdue
      final isOverdue = instances.any((inst) =>
          inst.dueDate != null &&
          DateTime(inst.dueDate!.year, inst.dueDate!.month, inst.dueDate!.day)
              .isBefore(DateTime.now()));

      // Get next due date for recurring tasks
      String nextDueSubtitle = '';
      // Check if task is recurring using the template field
      if (isRecurring) {
        final nextDue = instances
            .where((inst) => inst.dueDate != null)
            .map((inst) => inst.dueDate!)
            .where((date) => date.isAfter(DateTime.now()))
            .fold<DateTime?>(
                null,
                (earliest, date) => earliest == null || date.isBefore(earliest)
                    ? date
                    : earliest);

        if (nextDue != null) {
          nextDueSubtitle = 'Next due: ${nextDue.day}/${nextDue.month}';
        }
      }

      // For binary items, convert to quantitative for weekly view (only for recurring tasks)
      final displayTrackingType =
          (firstInstance.templateTrackingType == 'binary' && isRecurring)
              ? 'quantitative'
              : firstInstance.templateTrackingType;

      final displayUnit =
          (firstInstance.templateTrackingType == 'binary' && isRecurring)
              ? 'times'
              : firstInstance.templateUnit;

      processedTasks.add({
        'templateId': templateId,
        'templateName': firstInstance.templateName,
        'templateCategoryName': firstInstance.templateCategoryName,
        'templateCategoryId': firstInstance.templateCategoryId,
        'templatePriority': firstInstance.templatePriority,
        'templateTrackingType': firstInstance.templateTrackingType,
        'templateTarget': firstInstance.templateTarget,
        'templateUnit': firstInstance.templateUnit,
        'templateIsRecurring': isRecurring,
        'displayTrackingType': displayTrackingType, // Use this in weekly view
        'displayUnit': displayUnit, // Use this in weekly view
        'weeklyTarget': weeklyTarget,
        'weeklyCompletion': weeklyCompletion,
        'completionPercentage': completionPercentage,
        'isOverdue': isOverdue,
        'nextDueSubtitle': nextDueSubtitle,
        'instances': instances,
        'currentInstance': _getRepresentativeInstance(instances),
      });
    }

    return processedTasks;
  }

  /// Process habit templates and calculate weekly progress
  static List<Map<String, dynamic>> _processHabitTemplates(
    List<ActivityInstanceRecord> habitInstances,
    DateTime weekStart,
    DateTime weekEnd,
  ) {
    // Group by template ID
    final Map<String, List<ActivityInstanceRecord>> habitsByTemplate = {};
    for (final instance in habitInstances) {
      (habitsByTemplate[instance.templateId] ??= []).add(instance);
    }

    final processedHabits = <Map<String, dynamic>>[];

    for (final templateId in habitsByTemplate.keys) {
      final instances = habitsByTemplate[templateId]!;
      final firstInstance = instances.first;

      // Convert to weekly target
      final weeklyTarget = _convertHabitToWeeklyTarget(firstInstance);

      // Aggregate completion across the week
      final weeklyCompletion = _aggregateHabitCompletion(instances);

      // Calculate completion percentage
      final completionPercentage = weeklyTarget > 0
          ? (weeklyCompletion / weeklyTarget).clamp(0.0, 1.0)
          : 0.0;

      // Create subtitle showing weekly target/progress
      String weeklySubtitle = '';
      if (firstInstance.templateTrackingType == 'quantitative') {
        weeklySubtitle =
            '${weeklyCompletion.toInt()}/${weeklyTarget.toInt()} ${firstInstance.templateUnit}';
      } else if (firstInstance.templateTrackingType == 'time') {
        final hours = (weeklyCompletion / 60).toStringAsFixed(1);
        final targetHours = (weeklyTarget / 60).toStringAsFixed(1);
        weeklySubtitle = '${hours}h/${targetHours}h';
      } else {
        // Binary converted to quantity
        weeklySubtitle =
            '${weeklyCompletion.toInt()}/${weeklyTarget.toInt()} times';
      }

      // For binary items, convert to quantitative for weekly view
      final displayTrackingType = firstInstance.templateTrackingType == 'binary'
          ? 'quantitative'
          : firstInstance.templateTrackingType;

      final displayUnit = firstInstance.templateTrackingType == 'binary'
          ? 'times'
          : firstInstance.templateUnit;

      processedHabits.add({
        'templateId': templateId,
        'templateName': firstInstance.templateName,
        'templateCategoryName': firstInstance.templateCategoryName,
        'templateCategoryId': firstInstance.templateCategoryId,
        'templatePriority': firstInstance.templatePriority,
        'templateTrackingType': firstInstance.templateTrackingType,
        'templateTarget': firstInstance.templateTarget,
        'templateUnit': firstInstance.templateUnit,
        'displayTrackingType': displayTrackingType, // Use this in weekly view
        'displayUnit': displayUnit, // Use this in weekly view
        'weeklyTarget': weeklyTarget,
        'weeklyCompletion': weeklyCompletion,
        'completionPercentage': completionPercentage,
        'weeklySubtitle': weeklySubtitle,
        'instances': instances,
        'currentInstance': _getRepresentativeInstance(instances),
      });
    }

    return processedHabits;
  }

  /// Convert task target to weekly equivalent
  static double _convertTaskToWeeklyTarget(ActivityInstanceRecord instance) {
    final trackingType = instance.templateTrackingType;
    final target = _getTargetValue(instance);

    // Calculate weekly frequency based on period type
    double weeklyFrequency = _calculateWeeklyFrequency(instance);

    switch (trackingType) {
      case 'binary':
        // Binary tasks: convert to quantity based on weekly frequency
        return weeklyFrequency;

      case 'quantitative':
        // Quantitative tasks: multiply target by weekly frequency
        return target * weeklyFrequency;

      case 'time':
        // Time-based tasks: multiply target by weekly frequency
        return target * weeklyFrequency;

      default:
        return target;
    }
  }

  /// Convert habit target to weekly equivalent
  static double _convertHabitToWeeklyTarget(ActivityInstanceRecord instance) {
    final trackingType = instance.templateTrackingType;
    final target = _getTargetValue(instance);

    // Calculate weekly frequency based on period type
    double weeklyFrequency = _calculateWeeklyFrequency(instance);

    switch (trackingType) {
      case 'binary':
        // Binary habits: convert to quantity based on weekly frequency
        return weeklyFrequency;

      case 'quantitative':
        // Quantitative habits: multiply target by weekly frequency
        return target * weeklyFrequency;

      case 'time':
        // Time-based habits: multiply target by weekly frequency
        return target * weeklyFrequency;

      default:
        return target;
    }
  }

  /// Aggregate task completion across the week
  static double _aggregateTaskCompletion(
      List<ActivityInstanceRecord> instances) {
    double totalCompletion = 0.0;

    for (final instance in instances) {
      // For binary tracking, count number of completed instances
      if (instance.templateTrackingType == 'binary') {
        if (instance.status == 'completed') {
          totalCompletion += 1.0; // Each completion counts as 1
        }
      } else {
        // For quantitative/time tracking, use existing logic
        if (instance.status == 'completed') {
          totalCompletion += _getTargetValue(instance);
        } else {
          // For incomplete tasks, add partial progress
          final currentValue = _getCurrentValue(instance);
          totalCompletion += currentValue;
        }
      }
    }

    return totalCompletion;
  }

  /// Aggregate habit completion across the week
  static double _aggregateHabitCompletion(
      List<ActivityInstanceRecord> instances) {
    double totalCompletion = 0.0;

    for (final instance in instances) {
      // For binary tracking, count number of completed instances
      if (instance.templateTrackingType == 'binary') {
        if (instance.status == 'completed') {
          totalCompletion += 1.0; // Each completion counts as 1
        }
      } else {
        // For quantitative/time tracking, use existing logic
        if (instance.status == 'completed') {
          totalCompletion += _getTargetValue(instance);
        } else {
          // For incomplete habits, add current progress
          final currentValue = _getCurrentValue(instance);
          totalCompletion += currentValue;
        }
      }
    }

    return totalCompletion;
  }

  /// Get a representative instance from the week for display purposes
  /// For weekly view, we don't need specifically today's instance -
  /// any instance from the week will work since we're showing aggregated data
  static ActivityInstanceRecord? _getRepresentativeInstance(
      List<ActivityInstanceRecord> instances) {
    if (instances.isEmpty) return null;

    final today = DateService.currentDate;

    // Prioritize: 1) today's instance, 2) pending instance, 3) any instance

    // First, try to find today's instance
    for (final instance in instances) {
      if (instance.dueDate != null && instance.windowEndDate != null) {
        final dueDate = DateTime(instance.dueDate!.year,
            instance.dueDate!.month, instance.dueDate!.day);
        final windowEnd = DateTime(instance.windowEndDate!.year,
            instance.windowEndDate!.month, instance.windowEndDate!.day);

        if (!today.isBefore(dueDate) && !today.isAfter(windowEnd)) {
          return instance;
        }
      }
    }

    // If no instance for today, find any pending instance
    final pendingInstance = instances.firstWhere(
      (inst) => inst.status == 'pending',
      orElse: () => instances.first,
    );

    return pendingInstance;
  }

  /// Helper to get target value from instance
  static double _getTargetValue(ActivityInstanceRecord instance) {
    final target = instance.templateTarget;
    if (target is int) return target.toDouble();
    if (target is double) return target;
    return 0.0;
  }

  /// Helper to get current value from instance
  static double _getCurrentValue(ActivityInstanceRecord instance) {
    final currentValue = instance.currentValue;
    if (currentValue is int) return currentValue.toDouble();
    if (currentValue is double) return currentValue;
    return 0.0;
  }

  /// Calculate weekly frequency based on instance period settings
  static double _calculateWeeklyFrequency(ActivityInstanceRecord instance) {
    // Handle "every X days" pattern: calculate weekly frequency as 7/X
    if (instance.templateEveryXPeriodType == 'days' &&
        instance.templateEveryXValue > 0) {
      return 7.0 /
          instance
              .templateEveryXValue; // e.g., every 2 days = 7/2 = 3.5 times/week
    }

    // Handle "every X weeks" pattern: calculate weekly frequency as 1/X
    if (instance.templateEveryXPeriodType == 'weeks' &&
        instance.templateEveryXValue > 0) {
      return 1.0 /
          instance
              .templateEveryXValue; // e.g., every 2 weeks = 1/2 = 0.5 times/week
    }

    // Handle "times per period" pattern
    if (instance.templateTimesPerPeriod > 0 &&
        instance.templatePeriodType.isNotEmpty) {
      switch (instance.templatePeriodType.toLowerCase()) {
        case 'day':
        case 'days':
          return instance.templateTimesPerPeriod.toDouble() *
              7; // X times per day = 7X per week
        case 'week':
        case 'weeks':
          return instance.templateTimesPerPeriod.toDouble(); // X times per week
        case 'month':
        case 'months':
          return instance.templateTimesPerPeriod.toDouble() /
              4.33; // X times per month ≈ X/4.33 per week
        default:
          return instance.templateTimesPerPeriod.toDouble();
      }
    }

    // Default: daily habit (1 time per day = 7 times per week)
    return 7.0;
  }
}
