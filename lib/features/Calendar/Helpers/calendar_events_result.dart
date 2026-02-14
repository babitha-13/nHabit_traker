import 'package:calendar_view/calendar_view.dart';

/// Result class for calendar events loading.
class CalendarEventsResult {
  final List<CalendarEventData> completedEvents;
  final List<CalendarEventData> plannedEvents;
  final Map<String, List<String>> routineItemMap;

  CalendarEventsResult({
    required this.completedEvents,
    required this.plannedEvents,
    this.routineItemMap = const {},
  });
}
