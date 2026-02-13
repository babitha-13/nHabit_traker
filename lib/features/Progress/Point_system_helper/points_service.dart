import 'package:habit_tracker/features/Progress/Point_system_helper/binary_time_bonus_helper.dart';
import 'package:habit_tracker/features/Progress/Point_system_helper/points_value_helper.dart';
import 'package:habit_tracker/features/Progress/backend/activity_template_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/services/app_state.dart';

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
    return calculateInstanceTargetPoints(instance);
  }

  /// Calculate daily target with template data (enhanced version)
  /// Use this when you have access to the template data
  static double calculateDailyTargetWithTemplate(
    ActivityInstanceRecord instance,
    ActivityRecord template,
  ) {
    return calculateInstanceTargetPointsWithTemplate(instance, template);
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

  /// Calculate target points for any instance (task or habit) using cached data.
  static double calculateInstanceTargetPoints(
    ActivityInstanceRecord instance,
  ) {
    if (instance.templateCategoryType == 'essential') {
      return 0.0;
    }

    final priority = instance.templatePriority.toDouble();
    final isHabit = instance.templateCategoryType == 'habit';
    final dailyFrequency = isHabit ? _calculateDailyFrequency(instance) : 1.0;
    final timeBonusEnabled = FFAppState.instance.timeBonusEnabled;
    final trackingType = instance.templateTrackingType.toLowerCase();

    switch (trackingType) {
      case 'time':
        final targetMinutes = PointsValueHelper.targetValue(instance);
        if (targetMinutes <= 0) return 0.0;
        final perInstanceTarget = timeBonusEnabled
            ? BinaryTimeBonusHelper.scoreForTargetMinutes(
                targetMinutes: targetMinutes,
                priority: priority,
                timeBonusEnabled: true,
              )
            : priority;
        return dailyFrequency * perInstanceTarget;

      case 'binary':
        if (!timeBonusEnabled || _isLegacyBinaryTimeScoringDisabled(instance)) {
          return dailyFrequency * priority;
        }
        final estimateMinutes = _binaryEstimateMinutes(instance);
        double perInstanceTarget = BinaryTimeBonusHelper.scoreForTargetMinutes(
          targetMinutes: estimateMinutes,
          priority: priority,
          timeBonusEnabled: true,
        );
        final loggedMinutes = BinaryTimeBonusHelper.loggedTimeMinutes(instance);
        if (instance.status == 'completed' &&
            loggedMinutes != null &&
            loggedMinutes > estimateMinutes) {
          perInstanceTarget = BinaryTimeBonusHelper.scoreForLoggedMinutes(
            loggedMinutes: loggedMinutes,
            targetMinutes: estimateMinutes,
            priority: priority,
            timeBonusEnabled: true,
          );
        }
        return dailyFrequency * perInstanceTarget;

      default:
        return dailyFrequency * priority;
    }
  }

  /// Calculate target points for any instance using template-backed data when available.
  static double calculateInstanceTargetPointsWithTemplate(
    ActivityInstanceRecord instance,
    ActivityRecord template,
  ) {
    if (instance.templateCategoryType == 'essential' ||
        template.categoryType == 'essential') {
      return 0.0;
    }

    final priority = instance.templatePriority.toDouble();
    final isHabit = instance.templateCategoryType == 'habit';
    final dailyFrequency =
        isHabit ? calculateDailyFrequencyFromTemplate(template) : 1.0;
    final timeBonusEnabled = FFAppState.instance.timeBonusEnabled;
    final trackingType = instance.templateTrackingType.toLowerCase();

    switch (trackingType) {
      case 'time':
        final targetMinutes = template.target?.toDouble() ?? 0.0;
        if (targetMinutes <= 0) return 0.0;
        final perInstanceTarget = timeBonusEnabled
            ? BinaryTimeBonusHelper.scoreForTargetMinutes(
                targetMinutes: targetMinutes,
                priority: priority,
                timeBonusEnabled: true,
              )
            : priority;
        return dailyFrequency * perInstanceTarget;

      case 'binary':
        if (!timeBonusEnabled || _isLegacyBinaryTimeScoringDisabled(instance)) {
          return dailyFrequency * priority;
        }
        final estimateMinutes = _binaryEstimateMinutes(instance, template);
        double perInstanceTarget = BinaryTimeBonusHelper.scoreForTargetMinutes(
          targetMinutes: estimateMinutes,
          priority: priority,
          timeBonusEnabled: true,
        );
        final loggedMinutes = BinaryTimeBonusHelper.loggedTimeMinutes(instance);
        if (instance.status == 'completed' &&
            loggedMinutes != null &&
            loggedMinutes > estimateMinutes) {
          perInstanceTarget = BinaryTimeBonusHelper.scoreForLoggedMinutes(
            loggedMinutes: loggedMinutes,
            targetMinutes: estimateMinutes,
            priority: priority,
            timeBonusEnabled: true,
          );
        }
        return dailyFrequency * perInstanceTarget;

      default:
        return dailyFrequency * priority;
    }
  }

  /// Calculate points earned for a single habit instance (SYNCHRONOUS - no Firestore queries)
  /// Uses only cached instance data for instant calculation
  /// This is the fast path for UI updates - uses templateTimeEstimateMinutes from instance
  static double calculatePointsEarnedSync(
    ActivityInstanceRecord instance,
  ) {
    if (instance.templateCategoryType == 'essential') {
      return 0.0;
    }
    return _calculatePointsEarnedCore(instance);
  }

  /// Calculate points earned for a single habit instance
  /// Returns fractional points based on completion percentage
  static Future<double> calculatePointsEarned(
    ActivityInstanceRecord instance,
    String userId,
  ) async {
    if (instance.templateCategoryType == 'essential') {
      return 0.0;
    }
    return _calculatePointsEarnedCore(instance);
  }

  static double _calculatePointsEarnedCore(
    ActivityInstanceRecord instance,
  ) {
    final priority = instance.templatePriority.toDouble();
    final trackingType = instance.templateTrackingType.toLowerCase();

    switch (trackingType) {
      case 'binary':
        return _calculateBinaryEarnedPoints(instance, priority);

      case 'quantitative':
        final currentValue = PointsValueHelper.normalizedCurrentValue(instance);
        final target = PointsValueHelper.targetValue(instance);
        if (target <= 0) return 0.0;

        if (instance.templateCategoryType == 'habit' &&
            instance.windowDuration > 1) {
          final lastDayValue = PointsValueHelper.lastDayValue(instance);
          final normalizedLastDayValue =
              PointsValueHelper.normalizeValue(instance, lastDayValue);
          final todayContribution = currentValue - normalizedLastDayValue;
          final progressFraction = todayContribution / target;
          return progressFraction * priority;
        }

        final completionFraction = currentValue / target;
        return completionFraction * priority;

      case 'time':
        final targetMinutes = PointsValueHelper.targetValue(instance);
        if (targetMinutes <= 0) return 0.0;
        final loggedMinutes = instance.accumulatedTime / 60000.0;
        return BinaryTimeBonusHelper.scoreForLoggedMinutes(
          loggedMinutes: loggedMinutes,
          targetMinutes: targetMinutes,
          priority: priority,
          timeBonusEnabled: FFAppState.instance.timeBonusEnabled,
        );

      default:
        return 0.0;
    }
  }

  static double _calculateBinaryEarnedPoints(
    ActivityInstanceRecord instance,
    double priority,
  ) {
    final countValue = PointsValueHelper.currentValue(instance);
    final rawTarget = PointsValueHelper.targetValue(instance);
    final counterTarget = rawTarget > 0 ? rawTarget : 1.0;
    final isTimeLikeUnit =
        BinaryTimeBonusHelper.isTimeLikeUnit(instance.templateUnit);

    // Some "binary" items (e.g., timer tasks) store time (milliseconds) in currentValue.
    final isTimerTaskValue = countValue > 0 &&
        (countValue == instance.accumulatedTime.toDouble() ||
            countValue == instance.totalTimeLogged.toDouble());

    final isLegacyFrozen = _isLegacyBinaryTimeScoringDisabled(
      instance,
      countValue: countValue,
      targetValue: counterTarget,
    );

    double earnedBase;
    if (!isTimeLikeUnit && !isTimerTaskValue && countValue > 0) {
      final completionFraction = (countValue / counterTarget).clamp(0.0, 1.0);
      earnedBase = isLegacyFrozen ? priority : completionFraction * priority;
    } else if (instance.status == 'completed') {
      earnedBase = priority;
    } else {
      earnedBase = 0.0;
    }

    final timeBonusEnabled = FFAppState.instance.timeBonusEnabled;
    if (!timeBonusEnabled || isLegacyFrozen || earnedBase <= 0) {
      return earnedBase;
    }

    if (instance.status != 'completed') {
      return earnedBase;
    }

    final estimateMinutes = _binaryEstimateMinutes(instance);
    final loggedMinutes = BinaryTimeBonusHelper.loggedTimeMinutes(instance);
    if (loggedMinutes != null && loggedMinutes > estimateMinutes) {
      return BinaryTimeBonusHelper.scoreForLoggedMinutes(
        loggedMinutes: loggedMinutes,
        targetMinutes: estimateMinutes,
        priority: priority,
        timeBonusEnabled: true,
      );
    }

    return BinaryTimeBonusHelper.scoreForTargetMinutes(
      targetMinutes: estimateMinutes,
      priority: priority,
      timeBonusEnabled: true,
    );
  }

  static bool _isLegacyBinaryTimeScoringDisabled(
    ActivityInstanceRecord instance, {
    double? countValue,
    double? targetValue,
  }) {
    final count = countValue ?? PointsValueHelper.currentValue(instance);
    final rawTarget = targetValue ?? PointsValueHelper.targetValue(instance);
    final target = rawTarget > 0 ? rawTarget : 1.0;
    return BinaryTimeBonusHelper.isTimeScoringDisabled(instance) ||
        BinaryTimeBonusHelper.isForcedBinaryOneOffTimeLog(
          instance: instance,
          countValue: count,
          targetValue: target,
        );
  }

  static double _binaryEstimateMinutes(
    ActivityInstanceRecord instance, [
    ActivityRecord? template,
  ]) {
    final templateEstimate = template?.timeEstimateMinutes;
    if (templateEstimate != null && templateEstimate > 0) {
      return templateEstimate.toDouble();
    }
    return BinaryTimeBonusHelper.binaryEstimateMinutes(instance);
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

  /// Calculate total points earned for all habit instances (SYNCHRONOUS - no Firestore queries)
  /// Uses only cached instance data for instant calculation
  static double calculateTotalPointsEarnedSync(
    List<ActivityInstanceRecord> instances,
  ) {
    double totalPoints = 0.0;
    for (final instance in instances) {
      if (instance.templateCategoryType != 'habit') continue;
      // Skip Essential Activities
      if (instance.templateCategoryType == 'essential') continue;
      final points = calculatePointsEarnedSync(instance);
      totalPoints += points;
    }
    return totalPoints;
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

  /// Calculate total points earned for all activity instances (SYNCHRONOUS - no Firestore queries)
  /// Works for any ActivityInstanceRecord type and includes time bonuses when enabled
  /// Uses only cached instance data for instant calculation
  static double calculatePointsFromActivityInstancesSync(
    List<ActivityInstanceRecord> instances,
  ) {
    double totalPoints = 0.0;
    for (final instance in instances) {
      // Skip Essential Activities
      if (instance.templateCategoryType == 'essential') continue;
      final points = calculatePointsEarnedSync(instance);
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

  /// Calculate extra target to match binary time bonus awards for binary activities
  static double calculateBinaryTimeBonusTargetAdjustment(
    ActivityInstanceRecord instance,
  ) {
    final habitPriority = instance.templatePriority.toDouble();
    final countValue = PointsValueHelper.currentValue(instance);
    return BinaryTimeBonusHelper.calculateTargetAdjustment(
      instance: instance,
      countValue: countValue,
      priority: habitPriority,
    );
  }
}
