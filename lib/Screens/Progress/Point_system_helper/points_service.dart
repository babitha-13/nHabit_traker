import 'package:habit_tracker/Screens/Progress/Point_system_helper/binary_time_bonus_helper.dart';
import 'package:habit_tracker/Screens/Progress/Point_system_helper/points_value_helper.dart';
import 'package:habit_tracker/Screens/Progress/backend/activity_template_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/Helpers/app_state.dart';

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
  ) {
    // Skip Essential Activities - they don't earn points
    if (instance.templateCategoryType == 'essential') {
      return 0.0;
    }
    final habitPriority = instance.templatePriority.toDouble();
    // Calculate daily frequency based on template configuration
    final dailyFrequency = _calculateDailyFrequency(instance);

    // For time-based habits, apply duration multiplier
    if (instance.templateTrackingType == 'time') {
      final targetMinutes = PointsValueHelper.targetValue(instance);
      final durationMultiplier = calculateDurationMultiplier(targetMinutes);
      return dailyFrequency * habitPriority * durationMultiplier;
    }

    return dailyFrequency * habitPriority;
  }

  /// Calculate daily target with template data (enhanced version)
  /// Use this when you have access to the template data
  static double calculateDailyTargetWithTemplate(
    ActivityInstanceRecord instance,
    ActivityRecord template,
  ) {
    // Skip Essential Activities - they don't earn points
    if (instance.templateCategoryType == 'essential' ||
        template.categoryType == 'essential') {
      return 0.0;
    }
    final habitPriority = instance.templatePriority.toDouble();
    // Calculate daily frequency from template data
    final dailyFrequency = calculateDailyFrequencyFromTemplate(template);

    // For time-based habits, apply duration multiplier
    if (instance.templateTrackingType == 'time') {
      final targetMinutes = template.target?.toDouble() ?? 0.0;
      final durationMultiplier = calculateDurationMultiplier(targetMinutes);
      return dailyFrequency * habitPriority * durationMultiplier;
    }

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
  static Future<double> calculatePointsEarned(
    ActivityInstanceRecord instance,
    String userId,
  ) async {
    // Skip Essential Activities - they don't earn points
    if (instance.templateCategoryType == 'essential') {
      return 0.0;
    }
    final habitPriority = instance.templatePriority.toDouble();
    double earnedPoints = 0.0;

    switch (instance.templateTrackingType) {
      case 'binary':
        // Binary habits: use counter if available, otherwise status
        final countValue = PointsValueHelper.currentValue(instance);

        // Some "binary" items (e.g., timer tasks) store time (milliseconds) in currentValue.
        // In those cases, do NOT treat currentValue as a counter, or points will explode.
        final isTimeLikeUnit =
            BinaryTimeBonusHelper.isTimeLikeUnit(instance.templateUnit);

        // A "timer task" is one where currentValue matches the logged time (in MS)
        final isTimerTaskValue = countValue > 0 &&
            (countValue == instance.accumulatedTime.toDouble() ||
                countValue == instance.totalTimeLogged.toDouble());

        if (!isTimeLikeUnit && !isTimerTaskValue && countValue > 0) {
          // Has counter: calculate proportional points (counter / target), allowing over-completion
          final target = instance.templateTarget ?? 1;
          earnedPoints = (countValue / target) * habitPriority;
        } else if (instance.status == 'completed') {
          // No counter but completed: base points
          earnedPoints = habitPriority;
        } else {
          earnedPoints = 0.0;
        }

        // Add time bonus if enabled and time is logged
        final timeMinutes = await _getTimeMinutesForInstance(instance, userId);
        if (timeMinutes != null && earnedPoints > 0) {
          final timeBonusEnabled = FFAppState.instance.timeBonusEnabled;
          if (timeBonusEnabled && timeMinutes >= 30.0) {
            // Award bonus for every 30-minute block beyond the first 30 minutes
            final excessMinutes = timeMinutes - 30.0;
            final bonusBlocks = (excessMinutes / 30.0).floor();
            earnedPoints += bonusBlocks * habitPriority;
          }
        }

        return earnedPoints;
      case 'quantitative':
        // Quantitative habits: points based on progress, allowing over-completion
        // Use normalized value to handle cases where timers store MS in currentValue
        final currentValue = PointsValueHelper.normalizedCurrentValue(instance);
        final target = PointsValueHelper.targetValue(instance);
        if (target <= 0) {
          earnedPoints = 0.0;
        } else {
          // For windowed habits, use differential progress (today's contribution)
          if (instance.templateCategoryType == 'habit' &&
              instance.windowDuration > 1) {
            final lastDayValue = PointsValueHelper.lastDayValue(instance);
            final normalizedLastDayValue =
                PointsValueHelper.normalizeValue(instance, lastDayValue);
            final todayContribution = currentValue - normalizedLastDayValue;
            // For windowed habits, calculate progress as fraction of total target
            // Each increment should contribute proportionally to the total target, allowing over-completion
            final progressFraction = todayContribution / target;
            earnedPoints = progressFraction * habitPriority;
          } else {
            // For non-windowed habits, use total progress, allowing over-completion
            final completionFraction = currentValue / target;
            earnedPoints = completionFraction * habitPriority;
          }
        }

        return earnedPoints;
      case 'time':
        // Time-based habits: scoring depends on Time Bonus setting
        final accumulatedTime = instance.accumulatedTime;
        final accumulatedMinutes =
            accumulatedTime / 60000.0; // Convert ms to minutes

        // Check if Time Bonus (effort mode) is enabled
        final timeBonusEnabled = FFAppState.instance.timeBonusEnabled;

        if (timeBonusEnabled) {
          // Effort mode:
          // - Reward proportionally until the time target is met
          // - Once the target is met, reward in 30-minute blocks
          //
          // Example (priority=1, target=20m):
          // - 10m => 0.5 pts
          // - 20m => 1 pt
          // - 30m => 1 pt
          // - 60m => 2 pts
          if (accumulatedMinutes <= 0) {
            earnedPoints = 0.0;
          } else {
            final targetMinutes = PointsValueHelper.targetValue(instance);
            if (targetMinutes > 0 && accumulatedMinutes < targetMinutes) {
              earnedPoints =
                  (accumulatedMinutes / targetMinutes) * habitPriority;
            } else {
              final blocks = (accumulatedMinutes / 30.0).floor();
              earnedPoints = (blocks > 0 ? blocks : 1) * habitPriority;
            }
          }
        } else {
          // Goal/progress mode: Points scale proportionally with accumulated time vs target
          // If 2x time is logged, get 2x points (allowing over-completion)
          final targetMinutes = PointsValueHelper.targetValue(instance);
          final targetMs =
              targetMinutes * 60000; // Convert minutes to milliseconds
          if (targetMs <= 0) {
            earnedPoints = 0.0;
          } else {
            // For windowed habits, use differential progress (today's contribution)
            if (instance.templateCategoryType == 'habit' &&
                instance.windowDuration > 1) {
              final lastDayValue = PointsValueHelper.lastDayValue(instance);
              final todayContribution = accumulatedTime - lastDayValue;
              // For windowed habits, calculate progress as fraction of total target, allowing over-completion
              final progressFraction = todayContribution / targetMs;
              earnedPoints = progressFraction * habitPriority;
            } else {
              // For non-windowed habits, use total progress, allowing over-completion
              // Points scale proportionally: 2x time = 2x points
              final completionFraction = accumulatedTime / targetMs;
              earnedPoints = completionFraction * habitPriority;
            }
          }
        }

        return earnedPoints;
      default:
        return 0.0;
    }
  }

  /// Calculate total daily target for all habit instances
  static double calculateTotalDailyTarget(
    List<ActivityInstanceRecord> instances,
  ) {
    double totalTarget = 0.0;
    for (final instance in instances) {
      // Skip Essential Activities, only process habits
      if (instance.templateCategoryType != 'habit' ||
          instance.templateCategoryType == 'essential') continue;
      final target = calculateDailyTarget(instance);
      totalTarget += target;
    }
    return totalTarget;
  }

  /// Calculate total daily target with template data (enhanced version)
  /// Use this when you have access to template data for accurate frequency calculation
  static Future<double> calculateTotalDailyTargetWithTemplates(
    List<ActivityInstanceRecord> instances,
    String userId,
  ) async {
    double totalTarget = 0.0;
    for (final instance in instances) {
      // Skip Essential Activities, only process habits
      if (instance.templateCategoryType != 'habit' ||
          instance.templateCategoryType == 'essential') continue;
      // Fetch template data for accurate frequency calculation
      final template = await ActivityTemplateService.getTemplateById(
        userId: userId,
        templateId: instance.templateId,
      );
      if (template != null) {
        totalTarget += calculateDailyTargetWithTemplate(instance, template);
      } else {
        // Fallback to basic calculation if template fetch fails
        totalTarget += calculateDailyTarget(instance);
      }
    }
    return totalTarget;
  }

  /// Calculate total points earned for all habit instances
  static Future<double> calculateTotalPointsEarned(
    List<ActivityInstanceRecord> instances,
    String userId,
  ) async {
    double totalPoints = 0.0;
    for (final instance in instances) {
      if (instance.templateCategoryType != 'habit') continue;
      // Skip Essential Activities
      if (instance.templateCategoryType == 'essential') continue;
      final points = await calculatePointsEarned(instance, userId);
      totalPoints += points;
    }
    return totalPoints;
  }

  /// Calculate total points earned for all activity instances (habits and tasks)
  /// Works for any ActivityInstanceRecord type and includes time bonuses when enabled
  static Future<double> calculatePointsFromActivityInstances(
    List<ActivityInstanceRecord> instances,
    String userId,
  ) async {
    double totalPoints = 0.0;
    for (final instance in instances) {
      // Skip Essential Activities
      if (instance.templateCategoryType == 'essential') continue;
      final points = await calculatePointsEarned(instance, userId);
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

  /// Get time in minutes for an instance using priority order:
  /// 1. Manual/recorded time (accumulatedTime or totalTimeLogged)
  /// 2. Activity-specific estimate (template.timeEstimateMinutes)
  /// 3. Returns null if no time source found
  static Future<double?> _getTimeMinutesForInstance(
    ActivityInstanceRecord instance,
    String userId,
  ) async {
    // Priority 1: Manual/recorded time
    final loggedMinutes = BinaryTimeBonusHelper.loggedTimeMinutes(instance);
    if (loggedMinutes != null) {
      return loggedMinutes;
    }

    // Priority 2: Activity-specific estimate
    if (instance.hasTemplateId()) {
      final template = await ActivityTemplateService.getTemplateById(
        userId: userId,
        templateId: instance.templateId,
      );
      if (template != null && template.hasTimeEstimateMinutes()) {
        return template.timeEstimateMinutes!.toDouble();
      }
    }

    // Priority 3: No time source
    return null;
  }

  /// Calculate duration multiplier based on target minutes
  /// Returns the number of 30-minute blocks, minimum 1
  static int calculateDurationMultiplier(double targetMinutes) {
    if (targetMinutes <= 0) return 1;
    return (targetMinutes / 30).round().clamp(1, double.infinity).toInt();
  }

  /// Calculate extra target to match binary time bonus awards (tasks only)
  static double calculateBinaryTimeBonusTargetAdjustment(
    ActivityInstanceRecord instance,
  ) {
    final habitPriority = instance.templatePriority.toDouble();
    final countValue = PointsValueHelper.currentValue(instance);
    final isTimeLikeUnit =
        BinaryTimeBonusHelper.isTimeLikeUnit(instance.templateUnit);
    return BinaryTimeBonusHelper.calculateTargetAdjustment(
      instance: instance,
      countValue: countValue,
      priority: habitPriority,
      isTimeLikeUnit: isTimeLikeUnit,
    );
  }
}
