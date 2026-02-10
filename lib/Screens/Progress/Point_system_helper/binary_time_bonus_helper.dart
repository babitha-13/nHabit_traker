import 'dart:math' as math;
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/app_state.dart';

/// Helper utilities for calculating binary time bonus behavior
class BinaryTimeBonusHelper {
  /// Whether the provided unit represents time (e.g., minutes, milliseconds)
  static bool isTimeLikeUnit(String? unitRaw) {
    if (unitRaw == null) return false;
    final unit = unitRaw.toLowerCase();
    return unit == 'minute' ||
        unit == 'minutes' ||
        unit == 'min' ||
        unit == 'ms' ||
        unit == 'millisecond' ||
        unit == 'milliseconds';
  }

  /// Returns logged time in minutes if available
  static double? loggedTimeMinutes(ActivityInstanceRecord instance) {
    final loggedMs = instance.accumulatedTime > 0
        ? instance.accumulatedTime
        : instance.totalTimeLogged;
    if (loggedMs > 0) {
      return loggedMs / 60000.0;
    }
    return null;
  }

  /// Determines if the binary item has earned base credit (so bonus can apply)
  static bool hasBinaryBaseCredit({
    required ActivityInstanceRecord instance,
    required double countValue,
    required bool isTimeLikeUnit,
  }) {
    // A "timer task" is one where currentValue matches the logged time (in MS).
    // In these cases, countValue is duration, not a "times completed" counter.
    final isTimerTaskValue = countValue > 0 &&
        (countValue == instance.accumulatedTime.toDouble() ||
            countValue == instance.totalTimeLogged.toDouble());

    if (!isTimeLikeUnit && !isTimerTaskValue && countValue > 0) {
      return true;
    }
    return instance.status == 'completed';
  }

  /// Get baseline minutes for binary type items
  /// Uses templateTimeEstimateMinutes if available, otherwise defaults to 30 minutes
  static double getBaselineMinutes(ActivityInstanceRecord instance) {
    if (instance.hasTemplateTimeEstimateMinutes() &&
        instance.templateTimeEstimateMinutes! > 0) {
      return instance.templateTimeEstimateMinutes!.toDouble();
    }
    return 30.0; // Default baseline
  }

  /// Calculate diminishing returns bonus for excess time
  /// Each 30-minute block beyond baseline gives 0.7x of the previous block's value
  /// Formula: priority × Σ(0.7^i) for i=1 to n blocks
  static double calculateDiminishingReturnsBonus({
    required double excessMinutes,
    required double priority,
  }) {
    if (excessMinutes <= 0) return 0.0;

    // Calculate number of complete 30-minute blocks
    final blocks = (excessMinutes / 30.0).floor();
    if (blocks <= 0) return 0.0;

    // Sum geometric series: Σ(0.7^i) for i=1 to blocks
    double totalBonus = 0.0;
    for (int i = 1; i <= blocks; i++) {
      totalBonus += math.pow(0.7, i) * priority;
    }
    return totalBonus;
  }

  /// Calculates the additional target needed to align with awarded bonus points
  ///
  /// **Important:** This adjustment is only applied to TASKS, not habits.
  ///
  /// **Design Philosophy:**
  /// - **Tasks:** Longer time = estimation error → adjust target upward
  /// - **Habits:** Longer time = over-achievement → keep target fixed, award bonus points
  ///
  /// This method calculates the adjustment, but it's only called from
  /// `PointsService.calculateBinaryTimeBonusTargetAdjustment` which is only used
  /// in task target calculations (`_calculateTaskTargetFromActivityInstances`).
  /// Habit targets never call this, allowing them to over-achieve without target inflation.
  ///
  /// **Diminishing Returns:** Uses 0.7x multiplier per 30-minute block beyond baseline
  static double calculateTargetAdjustment({
    required ActivityInstanceRecord instance,
    required double countValue,
    required double priority,
    required bool isTimeLikeUnit,
  }) {
    if (instance.templateTrackingType.toLowerCase() != 'binary') {
      return 0.0;
    }
    if (!FFAppState.instance.timeBonusEnabled) return 0.0;
    if (!hasBinaryBaseCredit(
      instance: instance,
      countValue: countValue,
      isTimeLikeUnit: isTimeLikeUnit,
    )) {
      return 0.0;
    }

    final timeMinutes = loggedTimeMinutes(instance);
    if (timeMinutes == null) return 0.0;

    final baselineMinutes = getBaselineMinutes(instance);
    if (timeMinutes < baselineMinutes) return 0.0;

    final excessMinutes = timeMinutes - baselineMinutes;
    return calculateDiminishingReturnsBonus(
      excessMinutes: excessMinutes,
      priority: priority,
    );
  }
}
