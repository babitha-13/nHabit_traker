import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

class CalendarOptimisticTraceLogger {
  const CalendarOptimisticTraceLogger._();

  static bool get enabled => false;

  static void log(
    String stage, {
    String? source,
    String? operationId,
    String? instanceId,
    ActivityInstanceRecord? instance,
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    // Intentionally no-op: verbose calendar optimistic tracing removed.
    return;
  }
}
