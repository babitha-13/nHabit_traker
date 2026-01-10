import 'package:calendar_view/calendar_view.dart';
import 'package:habit_tracker/Screens/Calendar/Calender%20models/calender_event_metadata.dart';
import 'package:habit_tracker/Screens/Calendar/Calender%20models/planned_overlap_group.dart';
import 'package:habit_tracker/Screens/Calendar/Calender%20models/planned_overlap_info.dart';

/// Utility class for calculating calendar event overlaps
class CalendarOverlapCalculator {
  /// Generate stable event ID from event data
  static String? stableEventId(CalendarEventData event) {
    final metadata = CalendarEventMetadata.fromMap(event.event);
    final id = metadata?.instanceId;
    if (id != null && id.isNotEmpty) return id;
    if (event.startTime == null || event.endTime == null) return null;
    return '${event.title}_${event.startTime!.millisecondsSinceEpoch}_${event.endTime!.millisecondsSinceEpoch}';
  }

  /// Compute planned event overlaps
  static PlannedOverlapInfo computePlannedOverlaps(
    List<CalendarEventData> planned,
  ) {
    final events = planned
        .where((e) => e.startTime != null && e.endTime != null)
        .toList()
      ..sort((a, b) => a.startTime!.compareTo(b.startTime!));

    int overlapPairs = 0;
    final overlappedIds = <String>{};
    final groups = <PlannedOverlapGroup>[];
    final active = <CalendarEventData>[];
    final currentGroup = <CalendarEventData>[];
    DateTime? currentGroupStart;
    DateTime? currentGroupEnd;

    void finalizeGroupIfNeeded() {
      if (currentGroup.length <= 1) {
        currentGroup.clear();
        currentGroupStart = null;
        currentGroupEnd = null;
        return;
      }
      final start = currentGroupStart!;
      final end = currentGroupEnd!;
      groups.add(
        PlannedOverlapGroup(
          start: start,
          end: end,
          events: List.of(currentGroup),
        ),
      );
      for (final e in currentGroup) {
        final id = stableEventId(e);
        if (id != null) overlappedIds.add(id);
      }
      currentGroup.clear();
      currentGroupStart = null;
      currentGroupEnd = null;
    }

    for (final e in events) {
      final start = e.startTime!;
      final end = e.endTime!;
      active.removeWhere((a) => !a.endTime!.isAfter(start));
      if (active.isNotEmpty) {
        overlapPairs += active.length;
        final id = stableEventId(e);
        if (id != null) overlappedIds.add(id);
        for (final a in active) {
          final aid = stableEventId(a);
          if (aid != null) overlappedIds.add(aid);
        }
      }
      active.add(e);
      if (currentGroup.isEmpty) {
        currentGroup.add(e);
        currentGroupStart = start;
        currentGroupEnd = end;
      } else {
        final groupEnd = currentGroupEnd!;
        if (start.isBefore(groupEnd)) {
          currentGroup.add(e);
          if (end.isAfter(groupEnd)) currentGroupEnd = end;
        } else {
          finalizeGroupIfNeeded();
          currentGroup.add(e);
          currentGroupStart = start;
          currentGroupEnd = end;
        }
      }
    }
    finalizeGroupIfNeeded();

    return PlannedOverlapInfo(
      pairCount: overlapPairs,
      overlappedIds: overlappedIds,
      groups: groups,
    );
  }
}
