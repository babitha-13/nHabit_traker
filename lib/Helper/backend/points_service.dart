import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/task_instance_record.dart';

/// Service for calculating fractional points and daily targets for habit tracking
class PointsService {
  /// Convert period type to number of days
  static int periodTypeToDays(String periodType) {
    switch (periodType.toLowerCase()) {
      case 'daily':
      case 'days':
        return 1;
      case 'weekly':
      case 'weeks':
        return 7;
      case 'monthly':
      case 'months':
        return 30;
      default:
        return 7; // Default to weekly
    }
  }

  /// Calculate the daily target points for a single habit instance
  /// Returns the expected daily points based on frequency and importance
  static double calculateDailyTarget(
    ActivityInstanceRecord instance,
    CategoryRecord category,
  ) {
    final habitPriority = instance.templatePriority.toDouble();

    // Calculate daily frequency based on template configuration
    final dailyFrequency = _calculateDailyFrequency(instance);

    return dailyFrequency * habitPriority;
  }

  /// Calculate daily target with template data (enhanced version)
  /// Use this when you have access to the template data
  static double calculateDailyTargetWithTemplate(
    ActivityInstanceRecord instance,
    CategoryRecord category,
    ActivityRecord template,
  ) {
    final habitPriority = instance.templatePriority.toDouble();

    // Calculate daily frequency from template data
    final dailyFrequency = calculateDailyFrequencyFromTemplate(template);

    return dailyFrequency * habitPriority;
  }

  /// Calculate daily frequency for a habit instance
  /// Returns the expected daily frequency (e.g., 0.5 for every 2 days)
  static double _calculateDailyFrequency(ActivityInstanceRecord instance) {
    // Handle "every X days/weeks" pattern
    if (instance.templateEveryXValue > 1 &&
        instance.templateEveryXPeriodType.isNotEmpty) {
      final periodDays = periodTypeToDays(instance.templateEveryXPeriodType);
      final frequency = (1.0 / instance.templateEveryXValue) *
          (periodDays / periodTypeToDays('daily'));
      return frequency;
    }

    // Handle "times per period" pattern
    if (instance.templateTimesPerPeriod > 0 &&
        instance.templatePeriodType.isNotEmpty) {
      final periodDays = periodTypeToDays(instance.templatePeriodType);
      final frequency = (instance.templateTimesPerPeriod / periodDays);
      return frequency;
    }

    // Default: daily habit (1 time per day)
    return 1.0;
  }

  /// Calculate daily frequency from template data
  /// This method can be used when template data is available
  static double calculateDailyFrequencyFromTemplate(ActivityRecord template) {
    // Handle "every X days" pattern
    if (template.everyXValue > 1 && template.everyXPeriodType.isNotEmpty) {
      final periodDays = periodTypeToDays(template.everyXPeriodType);
      final frequency = (1.0 / template.everyXValue) *
          (periodDays / periodTypeToDays('daily'));
      return frequency;
    }

    // Handle "times per period" pattern
    if (template.timesPerPeriod > 0 && template.periodType.isNotEmpty) {
      final periodDays = periodTypeToDays(template.periodType);
      final frequency = (template.timesPerPeriod / periodDays);
      return frequency;
    }

    // Default: daily habit (1 time per day)
    return 1.0;
  }

  /// Calculate points earned for a single habit instance
  /// Returns fractional points based on completion percentage
  static double calculatePointsEarned(
    ActivityInstanceRecord instance,
    CategoryRecord category,
  ) {
    final habitPriority = instance.templatePriority.toDouble();

    switch (instance.templateTrackingType) {
      case 'binary':
        // Binary habits: full points if completed, 0 if not
        return instance.status == 'completed' ? habitPriority : 0.0;

      case 'quantitative':
        // Quantitative habits: points based on progress percentage
        if (instance.status == 'completed') {
          return habitPriority;
        }

        final currentValue = _getCurrentValue(instance);
        final target = _getTargetValue(instance);

        if (target <= 0) return 0.0;

        // For windowed habits, use differential progress (today's contribution)
        if (instance.templateCategoryType == 'habit' &&
            instance.windowDuration > 1) {
          final lastDayValue = _getLastDayValue(instance);
          final todayContribution = currentValue - lastDayValue;

          // For windowed habits, calculate progress as fraction of total target
          // Each increment should contribute proportionally to the total target
          if (target <= 0) return 0.0;

          final progressFraction = (todayContribution / target).clamp(0.0, 1.0);
          return progressFraction * habitPriority;
        }

        // For non-windowed habits, use total progress
        final completionFraction = (currentValue / target).clamp(0.0, 1.0);
        return completionFraction * habitPriority;

      case 'time':
        // Time-based habits: points based on accumulated time vs target
        if (instance.status == 'completed') {
          return habitPriority;
        }

        final accumulatedTime = instance.accumulatedTime;
        final targetMinutes = _getTargetValue(instance);
        final targetMs =
            targetMinutes * 60000; // Convert minutes to milliseconds

        if (targetMs <= 0) return 0.0;

        // For windowed habits, use differential progress (today's contribution)
        if (instance.templateCategoryType == 'habit' &&
            instance.windowDuration > 1) {
          final lastDayValue = _getLastDayValue(instance);
          final todayContribution = accumulatedTime - lastDayValue;

          // For windowed habits, calculate progress as fraction of total target
          // Each increment should contribute proportionally to the total target
          if (targetMs <= 0) return 0.0;

          final progressFraction =
              (todayContribution / targetMs).clamp(0.0, 1.0);
          return progressFraction * habitPriority;
        }

        // For non-windowed habits, use total progress
        final completionFraction = (accumulatedTime / targetMs).clamp(0.0, 1.0);
        return completionFraction * habitPriority;

      default:
        return 0.0;
    }
  }

  /// Calculate total daily target for all habit instances
  static double calculateTotalDailyTarget(
    List<ActivityInstanceRecord> instances,
    List<CategoryRecord> categories,
  ) {
    double totalTarget = 0.0;

    for (final instance in instances) {
      if (instance.templateCategoryType != 'habit') continue;

      final category = _findCategoryForInstance(instance, categories);
      if (category == null) {
        continue;
      }

      final target = calculateDailyTarget(instance, category);
      totalTarget += target;
    }

    return totalTarget;
  }

  /// Calculate total daily target with template data (enhanced version)
  /// Use this when you have access to template data for accurate frequency calculation
  static Future<double> calculateTotalDailyTargetWithTemplates(
    List<ActivityInstanceRecord> instances,
    List<CategoryRecord> categories,
    String userId,
  ) async {
    double totalTarget = 0.0;

    for (final instance in instances) {
      if (instance.templateCategoryType != 'habit') continue;

      final category = _findCategoryForInstance(instance, categories);
      if (category == null) continue;

      try {
        // Fetch template data for accurate frequency calculation
        final templateRef =
            ActivityRecord.collectionForUser(userId).doc(instance.templateId);
        final template = await ActivityRecord.getDocumentOnce(templateRef);

        totalTarget +=
            calculateDailyTargetWithTemplate(instance, category, template);
      } catch (e) {
        // Fallback to basic calculation if template fetch fails
        totalTarget += calculateDailyTarget(instance, category);
      }
    }

    return totalTarget;
  }

  /// Calculate total points earned for all habit instances
  static double calculateTotalPointsEarned(
    List<ActivityInstanceRecord> instances,
    List<CategoryRecord> categories,
  ) {
    double totalPoints = 0.0;

    for (final instance in instances) {
      if (instance.templateCategoryType != 'habit') continue;

      final category = _findCategoryForInstance(instance, categories);
      if (category == null) {
        continue;
      }

      final points = calculatePointsEarned(instance, category);
      totalPoints += points;
    }

    return totalPoints;
  }

  /// Calculate daily performance percentage
  /// Returns percentage (0-100+) of daily target achieved
  static double calculateDailyPerformancePercent(
    double pointsEarned,
    double totalTarget,
  ) {
    if (totalTarget <= 0) return 0.0;

    final percentage = (pointsEarned / totalTarget) * 100.0;
    return percentage.clamp(
        0.0, double.infinity); // Allow >100% for overachievement
  }

  /// Helper method to get current value from instance
  static double _getCurrentValue(ActivityInstanceRecord instance) {
    final value = instance.currentValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Helper method to get target value from instance
  static double _getTargetValue(ActivityInstanceRecord instance) {
    final target = instance.templateTarget;
    if (target is num) return target.toDouble();
    if (target is String) return double.tryParse(target) ?? 0.0;
    return 0.0;
  }

  /// Helper method to get last day value from instance (for differential progress)
  static double _getLastDayValue(ActivityInstanceRecord instance) {
    final value = instance.lastDayValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
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

  // ==================== TASK POINT CALCULATIONS ====================

  /// Calculate the daily target points for a single task instance
  /// For tasks: target = priority (no category weightage)
  static double calculateTaskDailyTarget(TaskInstanceRecord instance) {
    final priority = instance.templatePriority.toDouble();

    return priority;
  }

  /// Calculate points earned for a single task instance
  /// Returns fractional points based on completion percentage
  static double calculateTaskPointsEarned(TaskInstanceRecord instance) {
    final priority = instance.templatePriority.toDouble();

    switch (instance.templateTrackingType) {
      case 'binary':
        // Binary tasks: full points if completed, 0 if not
        return instance.status == 'completed' ? priority : 0.0;

      case 'quantitative':
        // Quantitative tasks: points based on progress percentage
        if (instance.status == 'completed') {
          return priority;
        }

        final currentValue = _getTaskCurrentValue(instance);
        final target = _getTaskTargetValue(instance);

        if (target <= 0) return 0.0;

        final completionFraction = (currentValue / target).clamp(0.0, 1.0);
        return completionFraction * priority;

      case 'time':
        // Time-based tasks: points based on accumulated time vs target
        if (instance.status == 'completed') {
          return priority;
        }

        final accumulatedTime = instance.accumulatedTime;
        final targetMinutes = _getTaskTargetValue(instance);
        final targetMs =
            targetMinutes * 60000; // Convert minutes to milliseconds

        if (targetMs <= 0) return 0.0;

        final completionFraction = (accumulatedTime / targetMs).clamp(0.0, 1.0);
        return completionFraction * priority;

      default:
        return 0.0;
    }
  }

  /// Calculate total daily target for all task instances
  static double calculateTotalTaskTarget(List<TaskInstanceRecord> instances) {
    double totalTarget = 0.0;

    for (final instance in instances) {
      final target = calculateTaskDailyTarget(instance);
      totalTarget += target;
    }

    return totalTarget;
  }

  /// Calculate total points earned for all task instances
  static double calculateTotalTaskPoints(List<TaskInstanceRecord> instances) {
    double totalPoints = 0.0;

    for (final instance in instances) {
      final points = calculateTaskPointsEarned(instance);
      totalPoints += points;
    }

    return totalPoints;
  }

  /// Helper method to get current value from task instance
  static double _getTaskCurrentValue(TaskInstanceRecord instance) {
    final value = instance.currentValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Helper method to get target value from task instance
  static double _getTaskTargetValue(TaskInstanceRecord instance) {
    final target = instance.templateTarget;
    if (target is num) return target.toDouble();
    if (target is String) return double.tryParse(target) ?? 0.0;
    return 0.0;
  }
}

/// Example calculations for simplified point system:
/// 
/// Example 1: "Exercise" habit
/// - Frequency: Every 2 days
/// - Habit priority: 3 (high priority)
/// - Daily target = (1/2) * 3 = 1.5 points per day
/// 
/// Example 2: "Read" habit  
/// - Frequency: 3 times per week
/// - Habit priority: 2 (medium priority)
/// - Daily target = (3/7) * 2 = 0.86 points per day
/// 
/// Example 3: "Meditate" habit
/// - Frequency: Daily (1 time per day)
/// - Habit priority: 1 (low priority)
/// - Daily target = 1.0 * 1 = 1.0 points per day
