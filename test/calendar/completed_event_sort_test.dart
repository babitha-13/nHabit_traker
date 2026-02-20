import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_models.dart';
import 'package:habit_tracker/features/Calendar/Helpers/completed_event_sort.dart';

CalendarEventData _buildEvent({
  required String instanceId,
  required int sessionIndex,
  required DateTime start,
  required DateTime end,
  int? loggedAtMs,
  int? sessionEndMs,
}) {
  final metadata = CalendarEventMetadata(
    instanceId: instanceId,
    sessionIndex: sessionIndex,
    sessionStartEpochMs: start.millisecondsSinceEpoch,
    sessionEndEpochMs: sessionEndMs ?? end.millisecondsSinceEpoch,
    sessionLoggedAtEpochMs: loggedAtMs,
    activityName: 'test',
    activityType: 'task',
  );

  return CalendarEventData(
    date: DateTime(start.year, start.month, start.day),
    startTime: start,
    endTime: end,
    title: 'event-$instanceId-$sessionIndex',
    color: Colors.blue,
    event: metadata.toMap(),
  );
}

void main() {
  test('sort prefers sessionLoggedAtEpochMs descending', () {
    final base = DateTime(2026, 2, 20, 22, 0, 0);
    final olderRangeButNewerLogged = _buildEvent(
      instanceId: 'a',
      sessionIndex: 0,
      start: base.subtract(const Duration(minutes: 40)),
      end: base.subtract(const Duration(minutes: 20)),
      loggedAtMs: base.millisecondsSinceEpoch,
    );
    final newerRangeButOlderLogged = _buildEvent(
      instanceId: 'b',
      sessionIndex: 0,
      start: base.subtract(const Duration(minutes: 30)),
      end: base.subtract(const Duration(minutes: 10)),
      loggedAtMs: base.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
    );

    final events = [newerRangeButOlderLogged, olderRangeButNewerLogged]
      ..sort(compareCompletedEvents);

    final first = CalendarEventMetadata.fromMap(events.first.event);
    expect(first?.instanceId, 'a');
  });

  test('sort falls back to sessionEndEpochMs then time range', () {
    final base = DateTime(2026, 2, 20, 22, 0, 0);
    final first = _buildEvent(
      instanceId: 'a',
      sessionIndex: 0,
      start: base.subtract(const Duration(minutes: 20)),
      end: base.subtract(const Duration(minutes: 5)),
      sessionEndMs: base.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
    );
    final second = _buildEvent(
      instanceId: 'b',
      sessionIndex: 0,
      start: base.subtract(const Duration(minutes: 25)),
      end: base.subtract(const Duration(minutes: 10)),
      sessionEndMs: base.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
    );

    final events = [second, first]..sort(compareCompletedEvents);
    final firstMeta = CalendarEventMetadata.fromMap(events.first.event);
    expect(firstMeta?.instanceId, 'a');
  });

  test('sort is stable for same instance/time using sessionIndex desc', () {
    final base = DateTime(2026, 2, 20, 22, 0, 0);
    final lowerIndex = _buildEvent(
      instanceId: 'same',
      sessionIndex: 0,
      start: base.subtract(const Duration(minutes: 10)),
      end: base,
    );
    final higherIndex = _buildEvent(
      instanceId: 'same',
      sessionIndex: 1,
      start: base.subtract(const Duration(minutes: 10)),
      end: base,
    );

    final events = [lowerIndex, higherIndex]..sort(compareCompletedEvents);
    final firstMeta = CalendarEventMetadata.fromMap(events.first.event);
    expect(firstMeta?.sessionIndex, 1);
  });
}
