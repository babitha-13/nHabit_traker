import 'package:flutter/foundation.dart';

class InstanceCreationTraceLogger {
  const InstanceCreationTraceLogger._();

  static const bool _enabled = bool.fromEnvironment(
    'ENABLE_INSTANCE_CREATION_TRACE',
    defaultValue: true,
  );

  static void log({
    required String action,
    required String templateId,
    required String categoryType,
    required bool isRecurring,
    DateTime? dueDate,
    String? docId,
    String? sourceTag,
    String? note,
  }) {
    if (!kDebugMode || !_enabled) return;
    final due = dueDate == null
        ? 'null'
        : '${dueDate.year}-${dueDate.month}-${dueDate.day}';
    debugPrint(
      '[instance-creation-trace] action=$action '
      'source=${sourceTag ?? '-'} '
      'templateId=$templateId '
      'category=$categoryType '
      'recurring=$isRecurring '
      'dueDate=$due '
      'docId=${docId ?? '-'} '
      'note=${note ?? '-'}',
    );
  }
}
