import 'package:flutter/material.dart';
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/expansion_state_manager.dart';

/// Helper class for handling focus and highlighting in queue page
class QueueFocusHandler {
  /// Apply pending focus to an instance
  static void applyPendingFocus({
    required Map<String, List<ActivityInstanceRecord>> buckets,
    required String? targetInstanceId,
    required String? targetTemplateId,
    required Map<String, GlobalKey> itemKeys,
    required Function(String) onInstanceFound,
    required Function(String?) onSectionExpanded,
    required Function(String) onHighlight,
    required Function() onFocusApplied,
    required Function(String, GlobalKey?) scrollToItem,
    required Function(Timer) setHighlightTimer,
  }) {
    if (targetInstanceId == null && targetTemplateId == null) {
      return;
    }

    ActivityInstanceRecord? target;
    String? sectionKey;

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
      return;
    }

    final resolvedInstanceId = target.reference.id;
    onInstanceFound(resolvedInstanceId);
    onFocusApplied();

    if (sectionKey != null) {
      onSectionExpanded(sectionKey);
      // Note: The parent widget should handle calling setQueueExpandedSections
      // with the full expanded sections set, not just this single section
    }

    onHighlight(resolvedInstanceId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final highlightKey = itemKeys[resolvedInstanceId];
      if (highlightKey?.currentContext != null) {
        scrollToItem(resolvedInstanceId, highlightKey);
      }
    });
  }
}
