import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/app_state.dart';

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
    if (!FFAppState.instance.timeBonusEnabled) return 0.0;
    if (!hasBinaryBaseCredit(
      instance: instance,
      countValue: countValue,
      isTimeLikeUnit: isTimeLikeUnit,
    )) {
      return 0.0;
    }

    final timeMinutes = loggedTimeMinutes(instance);
    if (timeMinutes == null || timeMinutes < 30.0) return 0.0;

    final bonusBlocks = ((timeMinutes - 30.0) / 30.0).floor();
    if (bonusBlocks <= 0) return 0.0;

    return bonusBlocks * priority;
  }
}

