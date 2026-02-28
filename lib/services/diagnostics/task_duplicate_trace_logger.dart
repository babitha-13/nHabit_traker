import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

class TaskDuplicateTraceLogger {
  const TaskDuplicateTraceLogger._();

  static String _dateKey(DateTime? date) {
    if (date == null) return 'null';
    final normalized = DateTime(date.year, date.month, date.day);
    final y = normalized.year.toString().padLeft(4, '0');
    final m = normalized.month.toString().padLeft(2, '0');
    final d = normalized.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static void logTaskDuplicateGroups({
    required List<ActivityInstanceRecord> instances,
    required String scope,
  }) {
    if (!kDebugMode) return;

    final taskInstances =
        instances.where((i) => i.templateCategoryType == 'task').toList();
    if (taskInstances.isEmpty) return;

    final grouped = <String, List<ActivityInstanceRecord>>{};
    for (final instance in taskInstances) {
      final key = '${instance.templateId}|${_dateKey(instance.dueDate)}';
      (grouped[key] ??= <ActivityInstanceRecord>[]).add(instance);
    }

    final duplicateGroups = grouped.entries.where((e) => e.value.length > 1);
    final groups = duplicateGroups.toList();
    if (groups.isEmpty) {
      return;
    }

    debugPrint(
      '[task-duplicate-trace] scope=$scope duplicate_groups=${groups.length}',
    );
    for (final group in groups) {
      final items = group.value;
      final templateName = items.first.templateName;
      final dueDate = _dateKey(items.first.dueDate);
      final statusSummary = items.map((i) => i.status).join(',');
      debugPrint(
        '[task-duplicate-trace] template="$templateName" '
        'templateId=${items.first.templateId} dueDate=$dueDate '
        'count=${items.length} statuses=[$statusSummary]',
      );
      for (final item in items) {
        final completedAt = item.completedAt?.toIso8601String() ?? '-';
        final updatedAt = item.lastUpdated?.toIso8601String() ?? '-';
        debugPrint(
          '[task-duplicate-trace]  id=${item.reference.id} '
          'status=${item.status} due=${_dateKey(item.dueDate)} '
          'completedAt=$completedAt lastUpdated=$updatedAt',
        );
      }
    }
  }
}
