import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:collection/collection.dart';

/// Handles focus management logic for queue page
class QueueFocusHandler {
  /// Find target instance and section key for focusing
  static FocusResult? findFocusTarget({
    required Map<String, List<ActivityInstanceRecord>> buckets,
    String? targetInstanceId,
    String? targetTemplateId,
  }) {
    if (targetInstanceId == null && targetTemplateId == null) {
      return null;
    }

    ActivityInstanceRecord? target;
    String? sectionKey;

    // Search by instance ID first
    if (targetInstanceId != null) {
      for (final entry in buckets.entries) {
        final match = entry.value
            .firstWhereOrNull((inst) => inst.reference.id == targetInstanceId);
        if (match != null) {
          target = match;
          sectionKey = entry.key;
          break;
        }
      }
    }

    // If not found, search by template ID
    if (target == null && targetTemplateId != null) {
      for (final entry in buckets.entries) {
        final match = entry.value
            .firstWhereOrNull((inst) => inst.templateId == targetTemplateId);
        if (match != null) {
          target = match;
          sectionKey = entry.key;
          break;
        }
      }
    }

    if (target == null) {
      return null;
    }

    return FocusResult(
      instanceId: target.reference.id,
      sectionKey: sectionKey,
    );
  }
}

/// Result of focus target search
class FocusResult {
  final String instanceId;
  final String? sectionKey;

  FocusResult({
    required this.instanceId,
    this.sectionKey,
  });
}
