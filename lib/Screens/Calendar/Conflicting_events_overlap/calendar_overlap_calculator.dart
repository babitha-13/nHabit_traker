import 'package:calendar_view/calendar_view.dart';
import 'package:habit_tracker/Screens/Calendar/Helpers/calendar_models.dart';

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

  /// Check if a task/habit belongs to a routine and should be excluded from clash detection
  /// Returns true if the task/habit is part of the routine and they overlap in time
  static bool _isTaskHabitInRoutine(
    CalendarEventData routineEvent,
    CalendarEventData taskHabitEvent,
    Map<String, List<String>> routineIdToItemIds,
  ) {
    // Extract routine ID from routine event
    final eventData = routineEvent.event;
    if (eventData is! Map<String, dynamic>) return false;
    final routineId = eventData['routineId'] as String?;
    if (routineId == null) return false;

    // Get itemIds for this routine
    final itemIds = routineIdToItemIds[routineId];
    if (itemIds == null || itemIds.isEmpty) return false;

    // Extract templateId from task/habit event
    final metadata = CalendarEventMetadata.fromMap(taskHabitEvent.event);
    final templateId = metadata?.templateId;
    if (templateId == null || templateId.isEmpty) return false;

    // Check if templateId is in routine's itemIds
    if (!itemIds.contains(templateId)) return false;

    // Check if they overlap in time (partial overlap is allowed)
    if (routineEvent.startTime == null ||
        routineEvent.endTime == null ||
        taskHabitEvent.startTime == null ||
        taskHabitEvent.endTime == null) {
      return false;
    }

    final routineStart = routineEvent.startTime!;
    final routineEnd = routineEvent.endTime!;
    final taskStart = taskHabitEvent.startTime!;
    final taskEnd = taskHabitEvent.endTime!;

    // Check for overlap: events overlap if one starts before the other ends
    return (taskStart.isBefore(routineEnd) && taskEnd.isAfter(routineStart)) ||
        (routineStart.isBefore(taskEnd) && routineEnd.isAfter(taskStart));
  }

  /// Incrementally update overlaps after removing an event
  /// More efficient than recalculating all overlaps when only one event is removed
  static PlannedOverlapInfo updateOverlapsAfterRemoval(
    String removedEventId,
    List<CalendarEventData> remainingEvents,
    PlannedOverlapInfo previousOverlapInfo, {
    Map<String, List<String>> routineIdToItemIds = const {},
  }) {
    // If the removed event wasn't in any overlap, just remove it from overlappedIds
    if (!previousOverlapInfo.overlappedIds.contains(removedEventId)) {
      final updatedOverlappedIds = Set<String>.from(previousOverlapInfo.overlappedIds);
      updatedOverlappedIds.remove(removedEventId);
      
      // Remove the event from overlap groups
      final updatedGroups = previousOverlapInfo.groups.map((group) {
        final filteredEvents = group.events.where((e) {
          final id = stableEventId(e);
          return id != removedEventId;
        }).toList();
        
        if (filteredEvents.length <= 1) return null;
        
        // Recalculate group bounds
        final starts = filteredEvents.map((e) => e.startTime).whereType<DateTime>().toList();
        final ends = filteredEvents.map((e) => e.endTime).whereType<DateTime>().toList();
        if (starts.isEmpty || ends.isEmpty) return null;
        
        return PlannedOverlapGroup(
          start: starts.reduce((a, b) => a.isBefore(b) ? a : b),
          end: ends.reduce((a, b) => a.isAfter(b) ? a : b),
          events: filteredEvents,
        );
      }).whereType<PlannedOverlapGroup>().toList();
      
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
    return computePlannedOverlaps(remainingEvents, routineIdToItemIds: routineIdToItemIds);
  }

  /// Incrementally update overlaps after adding a new event
  /// Checks only if the new event overlaps with existing events
  static PlannedOverlapInfo updateOverlapsAfterAdd(
    CalendarEventData newEvent,
    List<CalendarEventData> allEvents,
    PlannedOverlapInfo previousOverlapInfo, {
    Map<String, List<String>> routineIdToItemIds = const {},
  }) {
    if (newEvent.startTime == null || newEvent.endTime == null) {
      return previousOverlapInfo;
    }
    
    final newEventId = stableEventId(newEvent);
    if (newEventId == null) {
      // Fallback to full recompute if no stable ID
      return computePlannedOverlaps(allEvents, routineIdToItemIds: routineIdToItemIds);
    }
    
    final newStart = newEvent.startTime!;
    final newEnd = newEvent.endTime!;
    final overlappingEventIds = <String>{};
    
    // Extract metadata for new event to check if it's a routine or task/habit
    final newMetadata = CalendarEventMetadata.fromMap(newEvent.event);
    final newActivityType = newMetadata?.activityType ?? '';
    final isNewEventRoutine = newActivityType == 'routine';
    final isNewEventTaskHabit = newActivityType == 'task' || newActivityType == 'habit';
    
    // Check which existing events overlap with the new event
    for (final event in allEvents) {
      if (event.startTime == null || event.endTime == null) continue;
      if (event.startTime == newStart && event.endTime == newEnd) continue; // Same event
      
      final eventId = stableEventId(event);
      if (eventId == null) continue;
      
      // Extract metadata for existing event
      final eventMetadata = CalendarEventMetadata.fromMap(event.event);
      final eventActivityType = eventMetadata?.activityType ?? '';
      final isEventRoutine = eventActivityType == 'routine';
      final isEventTaskHabit = eventActivityType == 'task' || eventActivityType == 'habit';
      
      // Check overlap: events overlap if one starts before the other ends
      final hasTimeOverlap = (newStart.isBefore(event.endTime!) && newEnd.isAfter(event.startTime!)) ||
          (event.startTime!.isBefore(newEnd) && event.endTime!.isAfter(newStart));
      
      if (!hasTimeOverlap) continue;
      
      // Exclude overlap if it's a routine-task/habit relationship where task/habit belongs to routine
      if (isNewEventRoutine && isEventTaskHabit) {
        if (_isTaskHabitInRoutine(newEvent, event, routineIdToItemIds)) {
          continue; // Skip counting this overlap
        }
      } else if (isNewEventTaskHabit && isEventRoutine) {
        if (_isTaskHabitInRoutine(event, newEvent, routineIdToItemIds)) {
          continue; // Skip counting this overlap
        }
      }
      
      overlappingEventIds.add(eventId);
    }
    
    // If no overlaps, return previous info unchanged
    if (overlappingEventIds.isEmpty) {
      return previousOverlapInfo;
    }
    
    // If there are overlaps, we need to check if they're already in groups
    // For simplicity, if the new event overlaps with any overlapped event,
    // we do a full recompute (still faster than always doing full recompute)
    if (overlappingEventIds.any((id) => previousOverlapInfo.overlappedIds.contains(id))) {
      return computePlannedOverlaps(allEvents, routineIdToItemIds: routineIdToItemIds);
    }
    
    // New overlap: add to overlappedIds and increment pair count
    final updatedOverlappedIds = Set<String>.from(previousOverlapInfo.overlappedIds)
      ..add(newEventId)
      ..addAll(overlappingEventIds);
    
    final newPairCount = previousOverlapInfo.pairCount + overlappingEventIds.length;
    
    // Try to add to existing group or create new group
    final updatedGroups = List<PlannedOverlapGroup>.from(previousOverlapInfo.groups);
    bool addedToGroup = false;
    
    for (int i = 0; i < updatedGroups.length; i++) {
      final group = updatedGroups[i];
      // Check if new event overlaps with group time range
      if (newStart.isBefore(group.end) && newEnd.isAfter(group.start)) {
        // Add to this group
        final updatedEvents = List<CalendarEventData>.from(group.events)..add(newEvent);
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
        final starts = overlappingEvents.map((e) => e.startTime).whereType<DateTime>().toList();
        final ends = overlappingEvents.map((e) => e.endTime).whereType<DateTime>().toList();
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
    Map<String, List<String>> routineIdToItemIds = const {},
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
      
      // Count valid overlaps (excluding routine-task/habit pairs where task/habit belongs to routine)
      final validOverlapIds = <String>{};
      int validPairCount = 0;
      
      for (int i = 0; i < currentGroup.length; i++) {
        final e1 = currentGroup[i];
        final e1Id = stableEventId(e1);
        if (e1Id == null) continue;
        
        final e1Metadata = CalendarEventMetadata.fromMap(e1.event);
        final e1ActivityType = e1Metadata?.activityType ?? '';
        final isE1Routine = e1ActivityType == 'routine';
        final isE1TaskHabit = e1ActivityType == 'task' || e1ActivityType == 'habit';
        
        for (int j = i + 1; j < currentGroup.length; j++) {
          final e2 = currentGroup[j];
          final e2Metadata = CalendarEventMetadata.fromMap(e2.event);
          final e2ActivityType = e2Metadata?.activityType ?? '';
          final isE2Routine = e2ActivityType == 'routine';
          final isE2TaskHabit = e2ActivityType == 'task' || e2ActivityType == 'habit';
          
          // Exclude overlap if it's a routine-task/habit relationship where task/habit belongs to routine
          bool shouldExclude = false;
          if (isE1Routine && isE2TaskHabit) {
            shouldExclude = _isTaskHabitInRoutine(e1, e2, routineIdToItemIds);
          } else if (isE1TaskHabit && isE2Routine) {
            shouldExclude = _isTaskHabitInRoutine(e2, e1, routineIdToItemIds);
          }
          
          if (!shouldExclude) {
            validPairCount++;
            validOverlapIds.add(e1Id);
            final e2Id = stableEventId(e2);
            if (e2Id != null) validOverlapIds.add(e2Id);
          }
        }
      }
      
      // Only add group if there are valid overlaps (excluding routine-task/habit pairs)
      if (validPairCount > 0) {
        final start = currentGroupStart!;
        final end = currentGroupEnd!;
        groups.add(
          PlannedOverlapGroup(
            start: start,
            end: end,
            events: List.of(currentGroup), // Include all events in group for display
          ),
        );
        overlappedIds.addAll(validOverlapIds);
      }
      
      currentGroup.clear();
      currentGroupStart = null;
      currentGroupEnd = null;
    }

    for (final e in events) {
      final start = e.startTime!;
      final end = e.endTime!;
      active.removeWhere((a) => !a.endTime!.isAfter(start));
      
      // Extract metadata for current event
      final eMetadata = CalendarEventMetadata.fromMap(e.event);
      final eActivityType = eMetadata?.activityType ?? '';
      final isEventRoutine = eActivityType == 'routine';
      final isEventTaskHabit = eActivityType == 'task' || eActivityType == 'habit';
      
      if (active.isNotEmpty) {
        // Count overlaps, excluding routine-task/habit overlaps where task/habit belongs to routine
        int validOverlaps = 0;
        final validOverlapIds = <String>{};
        
        for (final a in active) {
          final aMetadata = CalendarEventMetadata.fromMap(a.event);
          final aActivityType = aMetadata?.activityType ?? '';
          final isActiveRoutine = aActivityType == 'routine';
          final isActiveTaskHabit = aActivityType == 'task' || aActivityType == 'habit';
          
          // Exclude overlap if it's a routine-task/habit relationship where task/habit belongs to routine
          bool shouldExclude = false;
          if (isEventRoutine && isActiveTaskHabit) {
            shouldExclude = _isTaskHabitInRoutine(e, a, routineIdToItemIds);
          } else if (isEventTaskHabit && isActiveRoutine) {
            shouldExclude = _isTaskHabitInRoutine(a, e, routineIdToItemIds);
          }
          
          if (!shouldExclude) {
            validOverlaps++;
            final aid = stableEventId(a);
            if (aid != null) validOverlapIds.add(aid);
          }
        }
        
        if (validOverlaps > 0) {
          overlapPairs += validOverlaps;
          final id = stableEventId(e);
          if (id != null) overlappedIds.add(id);
          overlappedIds.addAll(validOverlapIds);
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
