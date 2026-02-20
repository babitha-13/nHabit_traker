import 'package:calendar_view/calendar_view.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_models.dart';

int _loggedOrderValue(CalendarEventData event) {
  final metadata = CalendarEventMetadata.fromMap(event.event);
  if (metadata?.sessionLoggedAtEpochMs != null) {
    return metadata!.sessionLoggedAtEpochMs!;
  }
  if (metadata?.sessionEndEpochMs != null) {
    return metadata!.sessionEndEpochMs!;
  }
  return event.endTime?.millisecondsSinceEpoch ?? -1;
}

int compareCompletedEvents(CalendarEventData a, CalendarEventData b) {
  final loggedCompare = _loggedOrderValue(b).compareTo(_loggedOrderValue(a));
  if (loggedCompare != 0) {
    return loggedCompare;
  }

  final aEnd = a.endTime?.millisecondsSinceEpoch ?? -1;
  final bEnd = b.endTime?.millisecondsSinceEpoch ?? -1;
  final endCompare = bEnd.compareTo(aEnd);
  if (endCompare != 0) {
    return endCompare;
  }

  final aStart = a.startTime?.millisecondsSinceEpoch ?? -1;
  final bStart = b.startTime?.millisecondsSinceEpoch ?? -1;
  final startCompare = bStart.compareTo(aStart);
  if (startCompare != 0) {
    return startCompare;
  }

  final aMetadata = CalendarEventMetadata.fromMap(a.event);
  final bMetadata = CalendarEventMetadata.fromMap(b.event);
  final aInstanceId = aMetadata?.instanceId ?? '';
  final bInstanceId = bMetadata?.instanceId ?? '';
  final instanceCompare = aInstanceId.compareTo(bInstanceId);
  if (instanceCompare != 0) {
    return instanceCompare;
  }

  final aSessionIndex = aMetadata?.sessionIndex ?? -1;
  final bSessionIndex = bMetadata?.sessionIndex ?? -1;
  return bSessionIndex.compareTo(aSessionIndex);
}
