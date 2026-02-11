import 'package:calendar_view/calendar_view.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_models.dart';

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

  /// Incrementally update overlaps after removing an event
  /// More efficient than recalculating all overlaps when only one event is removed
  static PlannedOverlapInfo updateOverlapsAfterRemoval(
    String removedEventId,
    List<CalendarEventData> remainingEvents,
    PlannedOverlapInfo previousOverlapInfo,
  ) {
    // If the removed event wasn't in any overlap, just remove it from overlappedIds
    if (!previousOverlapInfo.overlappedIds.contains(removedEventId)) {
      final updatedOverlappedIds =
          Set<String>.from(previousOverlapInfo.overlappedIds);
      updatedOverlappedIds.remove(removedEventId);

      // Remove the event from overlap groups
      final updatedGroups = previousOverlapInfo.groups
          .map((group) {
            final filteredEvents = group.events.where((e) {
              final id = stableEventId(e);
              return id != removedEventId;
            }).toList();

            if (filteredEvents.length <= 1) return null;

            // Recalculate group bounds
            final starts = filteredEvents
                .map((e) => e.startTime)
                .whereType<DateTime>()
                .toList();
            final ends = filteredEvents
                .map((e) => e.endTime)
                .whereType<DateTime>()
                .toList();
            if (starts.isEmpty || ends.isEmpty) return null;

            return PlannedOverlapGroup(
              start: starts.reduce((a, b) => a.isBefore(b) ? a : b),
              end: ends.reduce((a, b) => a.isAfter(b) ? a : b),
              events: filteredEvents,
            );
          })
          .whereType<PlannedOverlapGroup>()
          .toList();

      // Recalculate pair count from updated groups
      int newPairCount = 0;
      for (final group in updatedGroups) {
        final n = group.events.length;
        newPairCount += (n * (n - 1)) ~/ 2;
      }

      return PlannedOverlapInfo(
        pairCount: newPairCount,
        overlappedIds: updatedOverlappedIds,
        groups: updatedGroups,
      );
    }

    // If the removed event was in overlaps, recalculate (still faster than full recompute)
    // because we're working with a smaller list
    return computePlannedOverlaps(remainingEvents);
  }

  /// Incrementally update overlaps after adding a new event
  /// Checks only if the new event overlaps with existing events
  static PlannedOverlapInfo updateOverlapsAfterAdd(
    CalendarEventData newEvent,
    List<CalendarEventData> allEvents,
    PlannedOverlapInfo previousOverlapInfo,
  ) {
    if (newEvent.startTime == null || newEvent.endTime == null) {
      return previousOverlapInfo;
    }

    final newEventId = stableEventId(newEvent);
    if (newEventId == null) {
      // Fallback to full recompute if no stable ID
      return computePlannedOverlaps(allEvents);
    }

    final newStart = newEvent.startTime!;
    final newEnd = newEvent.endTime!;
    final overlappingEventIds = <String>{};

    // Check which existing events overlap with the new event
    for (final event in allEvents) {
      if (event.startTime == null || event.endTime == null) continue;
      if (event.startTime == newStart && event.endTime == newEnd)
        continue; // Same event

      final eventId = stableEventId(event);
      if (eventId == null) continue;

      // Check overlap: events overlap if one starts before the other ends
      if ((newStart.isBefore(event.endTime!) &&
              newEnd.isAfter(event.startTime!)) ||
          (event.startTime!.isBefore(newEnd) &&
              event.endTime!.isAfter(newStart))) {
        overlappingEventIds.add(eventId);
      }
    }

    // If no overlaps, return previous info unchanged
    if (overlappingEventIds.isEmpty) {
      return previousOverlapInfo;
    }

    // If there are overlaps, we need to check if they're already in groups
    // For simplicity, if the new event overlaps with any overlapped event,
    // we do a full recompute (still faster than always doing full recompute)
    if (overlappingEventIds
        .any((id) => previousOverlapInfo.overlappedIds.contains(id))) {
      return computePlannedOverlaps(allEvents);
    }

    // New overlap: add to overlappedIds and increment pair count
    final updatedOverlappedIds =
        Set<String>.from(previousOverlapInfo.overlappedIds)
          ..add(newEventId)
          ..addAll(overlappingEventIds);

    final newPairCount =
        previousOverlapInfo.pairCount + overlappingEventIds.length;

    // Try to add to existing group or create new group
    final updatedGroups =
        List<PlannedOverlapGroup>.from(previousOverlapInfo.groups);
    bool addedToGroup = false;

    for (int i = 0; i < updatedGroups.length; i++) {
      final group = updatedGroups[i];
      // Check if new event overlaps with group time range
      if (newStart.isBefore(group.end) && newEnd.isAfter(group.start)) {
        // Add to this group
        final updatedEvents = List<CalendarEventData>.from(group.events)
          ..add(newEvent);
        updatedGroups[i] = PlannedOverlapGroup(
          start: newStart.isBefore(group.start) ? newStart : group.start,
          end: newEnd.isAfter(group.end) ? newEnd : group.end,
          events: updatedEvents,
        );
        addedToGroup = true;
        break;
      }
    }

    if (!addedToGroup) {
      // Create new group with overlapping events
      final overlappingEvents = allEvents.where((e) {
        final id = stableEventId(e);
        return id != null && overlappingEventIds.contains(id);
      }).toList();
      if (overlappingEvents.length > 1) {
        overlappingEvents.add(newEvent);
        final starts = overlappingEvents
            .map((e) => e.startTime)
            .whereType<DateTime>()
            .toList();
        final ends = overlappingEvents
            .map((e) => e.endTime)
            .whereType<DateTime>()
            .toList();
        if (starts.isNotEmpty && ends.isNotEmpty) {
          updatedGroups.add(PlannedOverlapGroup(
            start: starts.reduce((a, b) => a.isBefore(b) ? a : b),
            end: ends.reduce((a, b) => a.isAfter(b) ? a : b),
            events: overlappingEvents,
          ));
        }
      }
    }

    return PlannedOverlapInfo(
      pairCount: newPairCount,
      overlappedIds: updatedOverlappedIds,
      groups: updatedGroups,
    );
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
