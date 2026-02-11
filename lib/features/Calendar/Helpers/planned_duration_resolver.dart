import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/features/Settings/default_time_estimates_service.dart';

/// Resolves planned-calendar durations for activity instances.
///
/// Rules:
/// - If instance is time-target (trackingType == 'time' and target > 0): duration = target minutes
/// - Else if global default estimates are OFF: duration = null
/// - Else if activity-wise estimates are ON and template has timeEstimateMinutes: duration = that estimate
/// - Else: duration = global default duration minutes
///
/// Returning `null` means "no duration" (render as a due-time marker line in UI).
class PlannedDurationResolver {
  static Future<Map<String, int?>> resolveDurationMinutesForInstances({
    required String userId,
    required List<ActivityInstanceRecord> instances,
  }) async {
    final prefs = await TimeLoggingPreferencesService.getPreferences(userId);

    final enableDefaultEstimates = prefs.enableDefaultEstimates;

    // Always fetch templates if default estimates are enabled (activity estimates are always checked)
    final needsTemplateLookup = enableDefaultEstimates;

    final templatesById = needsTemplateLookup
        ? await _fetchTemplatesById(
            userId: userId,
            templateIds: instances
                .map((i) => i.templateId)
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList(),
          )
        : <String, ActivityRecord>{};

    final result = <String, int?>{};

    for (final instance in instances) {
      final instanceId = instance.reference.id;

      // Time-target activities use their target duration.
      final targetMinutes = _targetMinutesForTimeTracking(
        trackingType: instance.templateTrackingType,
        target: instance.templateTarget,
      );
      if (targetMinutes != null) {
        result[instanceId] = targetMinutes;
        continue;
      }

      // Non-time-target: apply estimate rules
      if (!enableDefaultEstimates) {
        result[instanceId] = null;
        continue;
      }

      // Always check for activity-specific estimate (no longer conditional)
      final template = templatesById[instance.templateId];
      if (template != null && template.hasTimeEstimateMinutes()) {
        result[instanceId] = template.timeEstimateMinutes!.clamp(1, 600);
        continue;
      }

      result[instanceId] = prefs.defaultDurationMinutes;
    }

    return result;
  }

  static int? _targetMinutesForTimeTracking({
    required String trackingType,
    required dynamic target,
  }) {
    if (trackingType != 'time') return null;
    if (target == null) return null;
    if (target is int) return target > 0 ? target : null;
    if (target is double) return target > 0 ? target.toInt() : null;
    if (target is String) {
      final parsed = int.tryParse(target);
      return (parsed != null && parsed > 0) ? parsed : null;
    }
    return null;
  }

  static Future<Map<String, ActivityRecord>> _fetchTemplatesById({
    required String userId,
    required List<String> templateIds,
  }) async {
    if (templateIds.isEmpty) return {};

    final out = <String, ActivityRecord>{};

    // Firestore whereIn limit is 10
    for (int i = 0; i < templateIds.length; i += 10) {
      final batch = templateIds.skip(i).take(10).toList();

      final snap = await ActivityRecord.collectionForUser(userId)
          .where(FieldPath.documentId, whereIn: batch)
          .get();

      for (final doc in snap.docs) {
        final record = ActivityRecord.fromSnapshot(doc);
        out[doc.id] = record;
      }
    }

    return out;
  }
}
