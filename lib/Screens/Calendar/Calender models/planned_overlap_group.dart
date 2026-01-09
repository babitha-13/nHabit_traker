import 'package:calendar_view/calendar_view.dart';

class PlannedOverlapGroup {
  final DateTime start;
  final DateTime end;
  final List<CalendarEventData> events;

  const PlannedOverlapGroup({
    required this.start,
    required this.end,
    required this.events,
  });
}