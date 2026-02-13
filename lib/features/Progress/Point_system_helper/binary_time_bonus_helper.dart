import 'dart:math';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/app_state.dart';

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

  /// Returns true when logged time should NOT influence points for this instance.
  static bool isTimeScoringDisabled(ActivityInstanceRecord instance) {
    final raw = instance.snapshotData['disableTimeScoringForPoints'];
    return raw is bool && raw;
  }

  /// Heuristic for older one-off manual time logs that were forced to binary.
  /// Those entries should be completion-based (priority points) with no time bonus.
  static bool isForcedBinaryOneOffTimeLog({
    required ActivityInstanceRecord instance,
    required double countValue,
    required double targetValue,
  }) {
    if (instance.templateTrackingType.toLowerCase() != 'binary') return false;
    if (instance.templateCategoryType != 'task') return false;
    if (instance.templateIsRecurring) return false;
    if (countValue > 1.0) return false;
    if (targetValue <= 1.0) return false;
    return loggedTimeMinutes(instance) != null;
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

  /// Calculates the diminishing returns bonus for excess time
  /// - Each 30-minute block beyond the estimate gives 0.7x of the previous block's value
  /// - Formula: priority * Σ(0.7^i) for i=1 to blocks
  static double calculateDiminishingReturnsBonus({
    required double excessMinutes,
    required double priority,
  }) {
    // Calculate number of complete 30-minute blocks
    final blocks = (excessMinutes / 30.0).floor();
    if (blocks <= 0) return 0.0;

    double totalBonus = 0.0;
    for (int i = 1; i <= blocks; i++) {
      totalBonus += pow(0.7, i) * priority;
    }
    return totalBonus;
  }

  /// Calculates the additional target needed to align with awarded bonus points
  static double calculateTargetAdjustment({
    required ActivityInstanceRecord instance,
    required double countValue,
    required double priority,
    required bool isTimeLikeUnit,
  }) {
    if (instance.templateTrackingType.toLowerCase() != 'binary') {
      return 0.0;
    }
    final targetRaw = instance.templateTarget;
    final targetValue = targetRaw is num
        ? targetRaw.toDouble()
        : (targetRaw is String ? double.tryParse(targetRaw) ?? 0.0 : 0.0);
    if (isTimeScoringDisabled(instance) ||
        isForcedBinaryOneOffTimeLog(
          instance: instance,
          countValue: countValue,
          targetValue: targetValue,
        )) {
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
    // Baseline is templateTimeEstimateMinutes if available (and > 0), otherwise 30.0
    final baselineMinutes = (instance.templateTimeEstimateMinutes != null &&
            instance.templateTimeEstimateMinutes! > 0)
        ? instance.templateTimeEstimateMinutes!.toDouble()
        : 30.0;

    if (timeMinutes == null || timeMinutes < baselineMinutes) return 0.0;

    final excessMinutes = timeMinutes - baselineMinutes;
    final bonusPoints = calculateDiminishingReturnsBonus(
      excessMinutes: excessMinutes,
      priority: priority,
    );

    // Adjustment is bonus points (since for binary, 1 point usually = 1 target unit if priority is 1)
    // Actually, target adjustment is usually added to make the progress bar look correct?
    // In the original code: return bonusBlocks * priority;
    // So we return the calculated bonus points as the adjustment to the target/score.
    return bonusPoints;
  }
}
