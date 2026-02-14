import 'package:calendar_view/calendar_view.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_models.dart';

/// Utility class for calculating calendar event overlaps
class CalendarOverlapCalculator {
  /// Generate stable event ID from event data
  static String? stableEventId(CalendarEventData event) {
    final metadata = CalendarEventMetadata.fromMap(event.event);
    final instanceId = metadata?.instanceId;
    if (instanceId != null && instanceId.isNotEmpty) {
      final sessionIndex = metadata?.sessionIndex ?? -1;
      if (sessionIndex >= 0) {
        return '$instanceId#session:$sessionIndex';
      }
      return instanceId;
    }
    if (event.startTime == null || event.endTime == null) return null;
    return '${event.title}_${event.startTime!.millisecondsSinceEpoch}_${event.endTime!.millisecondsSinceEpoch}';
  }

  /// Incrementally update overlaps after removing an event
  /// More efficient than recalculating all overlaps when only one event is removed
  static PlannedOverlapInfo updateOverlapsAfterRemoval(
    String removedEventId,
    List<CalendarEventData> remainingEvents,
    PlannedOverlapInfo previousOverlapInfo, {
    Map<String, List<String>>? routineItemMap,
  }) {
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
    return computePlannedOverlaps(remainingEvents,
        routineItemMap: routineItemMap);
  }

  /// Incrementally update overlaps after adding a new event
  /// Checks only if the new event overlaps with existing events
  static PlannedOverlapInfo updateOverlapsAfterAdd(
    CalendarEventData newEvent,
    List<CalendarEventData> allEvents,
    PlannedOverlapInfo previousOverlapInfo, {
    Map<String, List<String>>? routineItemMap,
  }) {
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
        if (!_isTaskHabitInRoutine(newEvent, event, routineItemMap)) {
          overlappingEventIds.add(eventId);
        }
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
    List<CalendarEventData> planned, {
    Map<String, List<String>>? routineItemMap,
  }) {
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
        for (final a in active) {
          if (_isTaskHabitInRoutine(e, a, routineItemMap)) continue;

          overlapPairs++; // Count overlap only if not excluded
          final aid = stableEventId(a);
          if (aid != null) overlappedIds.add(aid);
          // Also add current event ID if it wasn't added yet (it's added outside the loop too, but good to be consistent with logic)
        }
        // If we found any valid overlaps (not excluded), we need to ensure the current event ID is added
        // The original logic matched any overlap. Here we filter.
        // We need to re-verify if 'e' overlaps with ANY 'a' that is NOT excluded.
        bool hasValidOverlap = false;

        for (final a in active) {
          if (!_isTaskHabitInRoutine(e, a, routineItemMap)) {
            hasValidOverlap = true;
            break;
          }
        }

        if (hasValidOverlap) {
          final id = stableEventId(e);
          if (id != null) overlappedIds.add(id);
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

  /// Check if one event is a routine and the other is a task/habit belonging to that routine
  static bool _isTaskHabitInRoutine(
    CalendarEventData event1,
    CalendarEventData event2,
    Map<String, List<String>>? routineItemMap,
  ) {
    if (routineItemMap == null || routineItemMap.isEmpty) return false;

    // Helper to get type and IDs
    // We expect event.event to be populated with metadata
    if (event1.event is! Map<String, dynamic> ||
        event2.event is! Map<String, dynamic>) {
      return false;
    }
    final meta1 = event1.event as Map<String, dynamic>;
    final meta2 = event2.event as Map<String, dynamic>;

    if (meta1 == null || meta2 == null) return false;

    // Check 1 is routine, 2 is task
    if (_checkRoutineTaskPair(meta1, meta2, routineItemMap)) return true;

    // Check 2 is routine, 1 is task
    if (_checkRoutineTaskPair(meta2, meta1, routineItemMap)) return true;

    return false;
  }

  static bool _checkRoutineTaskPair(
    Map<String, dynamic> routineMeta,
    Map<String, dynamic> itemMeta,
    Map<String, List<String>> routineItemMap,
  ) {
    // Check if first is routine
    // 'activityType' for routine is 'routine' based on CalendarEventService
    if (routineMeta['activityType'] != 'routine') return false;

    // Check if second is task/habit/essential
    // Tasks usually have 'task', 'habit', or 'essential'
    final itemType = itemMeta['activityType'];
    if (itemType == 'routine')
      return false; // Both are routines (or conflicting routines)

    // Get routineId
    // In CalendarEventService: if (r.routineId != null) 'routineId': r.routineId
    final routineId = routineMeta['routineId'] as String?;
    if (routineId == null) return false;

    // Get item templateId
    // In CalendarEventService: templateId: item.templateId
    final templateId = itemMeta['templateId'] as String?;
    if (templateId == null) return false;

    // Check if templateId is in the routine's items
    final routineItems = routineItemMap[routineId];
    if (routineItems != null && routineItems.contains(templateId)) {
      return true;
    }

    return false;
  }
}
