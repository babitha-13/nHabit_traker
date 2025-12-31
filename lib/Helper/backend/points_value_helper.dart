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
}

