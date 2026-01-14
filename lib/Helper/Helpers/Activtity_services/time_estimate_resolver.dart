import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Screens/Settings/default_time_estimates_service.dart';

/// Helper utility to resolve the effective time estimate for an activity instance
/// This is business logic that should be testable independently (#TEST_SEPARATELY)
class TimeEstimateResolver {
  /// Determine if an activity is a time-target activity
  /// Time-target = trackingType is 'time' AND has a target > 0
  static bool isTimeTargetActivity({
    required String trackingType,
    required dynamic target,
  }) {
    if (trackingType != 'time') return false;
    if (target == null) return false;
    final targetNum = target is num ? target : 0;
    return targetNum > 0;
  }

  /// Get the effective time estimate minutes for an activity instance
  /// Returns null if estimates should not be applied
  /// Priority: per-activity estimate > global default > null (if disabled)
  static Future<int?> getEffectiveEstimateMinutes({
    required String userId,
    required String trackingType,
    required dynamic target,
    required bool hasExplicitSessions,
    ActivityRecord? template,
  }) async {
    // Never apply estimates if user already logged explicit time
    if (hasExplicitSessions) return null;

    // Never apply estimates for time-target activities
    if (isTimeTargetActivity(trackingType: trackingType, target: target)) {
      return null;
    }

    // Check if default estimates are enabled
    final enableDefaultEstimates =
        await TimeLoggingPreferencesService.getEnableDefaultEstimates(userId);
    if (!enableDefaultEstimates) {
      return null;
    }

    // Always check for per-activity estimate (no longer conditional)
    if (template != null && template.hasTimeEstimateMinutes()) {
      final activityEstimate = template.timeEstimateMinutes!;
      // Clamp to reasonable range (1-600 minutes)
      return activityEstimate.clamp(1, 600);
    }

    // Fall back to global default
    final defaultMinutes =
        await TimeLoggingPreferencesService.getDefaultDurationMinutes(userId);
    return defaultMinutes;
  }
}
