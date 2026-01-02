import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

/// Common value helpers shared across point calculations
class PointsValueHelper {
  static double currentValue(ActivityInstanceRecord instance) {
    final value = instance.currentValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static double targetValue(ActivityInstanceRecord instance) {
    final target = instance.templateTarget;
    if (target is num) return target.toDouble();
    if (target is String) return double.tryParse(target) ?? 0.0;
    return 0.0;
  }

  static double lastDayValue(ActivityInstanceRecord instance) {
    final value = instance.lastDayValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Returns the current value, normalized to minutes if it appears to be in milliseconds.
  /// This prevents "points explosion" when timer tasks store MS in currentValue.
  static double normalizedCurrentValue(ActivityInstanceRecord instance) {
    return normalizeValue(instance, currentValue(instance));
  }

  /// Normalizes a value (current or historical) based on instance state
  static double normalizeValue(ActivityInstanceRecord instance, double value) {
    if (value <= 0) return 0.0;

    // Heuristic: if value matches accumulatedTime or totalTimeLogged, it's likely MS
    // only apply if it's large enough to be MS ( > 1000)
    final isLikelyMS = (value > 1000 &&
        (value == instance.accumulatedTime.toDouble() ||
            value == instance.totalTimeLogged.toDouble()));

    if (isLikelyMS) {
      return value / 60000.0;
    }
    return value;
  }
}

