import 'dart:math';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/app_state.dart';

/// Helper utilities for calculating binary/time diminishing scoring behavior.
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
  /// Those entries should remain completion-based (priority points) with no time scaling.
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

  /// Baseline estimate for binary time-aware scoring.
  /// Falls back to 30m when estimate is not set.
  static double binaryEstimateMinutes(ActivityInstanceRecord instance) {
    final estimate = instance.templateTimeEstimateMinutes;
    if (estimate != null && estimate > 0) {
      return estimate.toDouble();
    }
    return 30.0;
  }

  /// Base span for the first full point block.
  /// - ON mode: min(target, 30)
  /// - OFF mode: target
  static double resolveBaseSpanMinutes({
    required double targetMinutes,
    required bool timeBonusEnabled,
  }) {
    if (targetMinutes <= 0) return 0.0;
    if (timeBonusEnabled) return min(targetMinutes, 30.0);
    return targetMinutes;
  }

  /// Bonus block size for diminishing returns.
  /// - ON mode: fixed 30m
  /// - OFF mode: target-sized blocks
  static double resolveBonusBlockMinutes({
    required double targetMinutes,
    required bool timeBonusEnabled,
  }) {
    if (targetMinutes <= 0) return 0.0;
    if (timeBonusEnabled) return 30.0;
    return targetMinutes;
  }

  /// Calculates diminishing returns bonus for configurable block size.
  static double calculateDiminishingReturnsBonusByBlock({
    required double excessMinutes,
    required double blockMinutes,
    required double priority,
  }) {
    if (excessMinutes <= 0 || blockMinutes <= 0 || priority <= 0) return 0.0;
    final blocks = (excessMinutes / blockMinutes).floor();
    if (blocks <= 0) return 0.0;

    double totalBonus = 0.0;
    for (int i = 1; i <= blocks; i++) {
      totalBonus += pow(0.7, i) * priority;
    }
    return totalBonus;
  }

  /// Calculates diminishing bonus using fixed 30-minute blocks.
  static double calculateDiminishingReturnsBonus({
    required double excessMinutes,
    required double priority,
  }) {
    return calculateDiminishingReturnsBonusByBlock(
      excessMinutes: excessMinutes,
      blockMinutes: 30.0,
      priority: priority,
    );
  }

  /// Score for a logged duration against a target duration under current mode.
  static double scoreForLoggedMinutes({
    required double loggedMinutes,
    required double targetMinutes,
    required double priority,
    required bool timeBonusEnabled,
  }) {
    if (loggedMinutes <= 0 || targetMinutes <= 0 || priority <= 0) {
      return 0.0;
    }

    final baseSpan = resolveBaseSpanMinutes(
      targetMinutes: targetMinutes,
      timeBonusEnabled: timeBonusEnabled,
    );
    if (baseSpan <= 0) return 0.0;

    if (loggedMinutes <= baseSpan) {
      return (loggedMinutes / baseSpan) * priority;
    }

    final blockMinutes = resolveBonusBlockMinutes(
      targetMinutes: targetMinutes,
      timeBonusEnabled: timeBonusEnabled,
    );
    final excessMinutes = loggedMinutes - baseSpan;
    final bonus = calculateDiminishingReturnsBonusByBlock(
      excessMinutes: excessMinutes,
      blockMinutes: blockMinutes,
      priority: priority,
    );
    return priority + bonus;
  }

  /// Target score for a configured target duration under current mode.
  static double scoreForTargetMinutes({
    required double targetMinutes,
    required double priority,
    required bool timeBonusEnabled,
  }) {
    return scoreForLoggedMinutes(
      loggedMinutes: targetMinutes,
      targetMinutes: targetMinutes,
      priority: priority,
      timeBonusEnabled: timeBonusEnabled,
    );
  }

  /// Compatibility wrapper used by legacy target-adjustment call sites.
  /// Returns "extra over base priority" for binary ON-mode target calculation.
  static double calculateTargetAdjustment({
    required ActivityInstanceRecord instance,
    required double countValue,
    required double priority,
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

    final estimateMinutes = binaryEstimateMinutes(instance);
    double targetScore = scoreForTargetMinutes(
      targetMinutes: estimateMinutes,
      priority: priority,
      timeBonusEnabled: true,
    );

    final loggedMinutes = loggedTimeMinutes(instance);
    if (instance.status == 'completed' &&
        loggedMinutes != null &&
        loggedMinutes > estimateMinutes) {
      targetScore = scoreForLoggedMinutes(
        loggedMinutes: loggedMinutes,
        targetMinutes: estimateMinutes,
        priority: priority,
        timeBonusEnabled: true,
      );
    }

    return (targetScore - priority).clamp(0.0, double.infinity);
  }
}
