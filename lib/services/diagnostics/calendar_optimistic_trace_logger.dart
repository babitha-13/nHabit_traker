import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

class CalendarOptimisticTraceLogger {
  const CalendarOptimisticTraceLogger._();

  static const bool _enabledByDefine = bool.fromEnvironment(
    'ENABLE_CALENDAR_OPTIMISTIC_TRACE',
    defaultValue: kDebugMode,
  );

  static bool get enabled => _enabledByDefine && kDebugMode;

  static void log(
    String stage, {
    String? source,
    String? operationId,
    String? instanceId,
    ActivityInstanceRecord? instance,
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    if (!enabled) return;

    final resolvedInstanceId = instanceId ?? instance?.reference.id;
    final fields = <String, Object?>{
      if (source != null && source.isNotEmpty) 'source': source,
      if (operationId != null && operationId.isNotEmpty) 'op': operationId,
      if (resolvedInstanceId != null && resolvedInstanceId.isNotEmpty)
        'instance': resolvedInstanceId,
      if (instance != null) ..._instanceFields(instance),
      ...extras,
    };

    debugPrint('[calendar-opt][$stage] ${_formatFields(fields)}');
  }

  static Map<String, Object?> _instanceFields(ActivityInstanceRecord instance) {
    final dueDate = instance.dueDate;
    final belongsToDate = instance.belongsToDate;
    final windowEndDate = instance.windowEndDate;
    return <String, Object?>{
      'status': instance.status,
      'type': instance.templateCategoryType,
      'tracking': instance.templateTrackingType,
      'sessions': instance.timeLogSessions.length,
      'totalLoggedMs': instance.totalTimeLogged,
      'accumulatedMs': instance.accumulatedTime,
      'currentValue': instance.currentValue,
      'dueDate': _shortDate(dueDate),
      'belongsToDate': _shortDate(belongsToDate),
      'windowEndDate': _shortDate(windowEndDate),
      'dueTime': instance.dueTime,
      'lastUpdatedMs': instance.lastUpdated?.millisecondsSinceEpoch,
    };
  }

  static String _shortDate(DateTime? value) {
    if (value == null) return '-';
    final normalized = DateTime(value.year, value.month, value.day);
    return normalized.toIso8601String();
  }

  static String _formatFields(Map<String, Object?> fields) {
    if (fields.isEmpty) return '-';
    return fields.entries
        .map((entry) => '${entry.key}=${_stringify(entry.value)}')
        .join(', ');
  }

  static String _stringify(Object? value) {
    if (value == null) return 'null';
    if (value is DateTime) return value.toIso8601String();
    if (value is Iterable) return value.join('|');
    return value.toString();
  }
}
