import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_snapshot.dart';

class TodayInstanceSelectors {
  const TodayInstanceSelectors._();

  static DateTime normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool isSameDay(DateTime? value, DateTime targetDay) {
    if (value == null) return false;
    final normalized = normalizeDate(value);
    return normalized.isAtSameMomentAs(targetDay);
  }

  static bool hasSessionOnDay(
    ActivityInstanceRecord instance,
    DateTime dayStart,
    DateTime dayEnd,
  ) {
    if (instance.timeLogSessions.isEmpty) return false;
    for (final session in instance.timeLogSessions) {
      final start = session['startTime'] as DateTime?;
      if (start == null) continue;
      if (!start.isBefore(dayStart) && start.isBefore(dayEnd)) {
        return true;
      }
    }
    return false;
  }

  static DateTime? statusTimestamp(ActivityInstanceRecord instance) {
    if (instance.completedAt != null) {
      return normalizeDate(instance.completedAt!);
    }
    if (instance.skippedAt != null) {
      return normalizeDate(instance.skippedAt!);
    }
    if (instance.lastUpdated != null) {
      return normalizeDate(instance.lastUpdated!);
    }
    if (instance.belongsToDate != null) {
      return normalizeDate(instance.belongsToDate!);
    }
    if (instance.dueDate != null) {
      return normalizeDate(instance.dueDate!);
    }
    return null;
  }

  static bool isHabitWindowLive(
    ActivityInstanceRecord instance,
    DateTime dayStart,
  ) {
    final startSource = instance.belongsToDate ?? instance.dueDate;
    final endSource = instance.windowEndDate;
    if (startSource == null || endSource == null) return false;
    final start = normalizeDate(startSource);
    final end = normalizeDate(endSource);
    return !dayStart.isBefore(start) && !dayStart.isAfter(end);
  }

  static bool isTaskDueTodayOrOverdue(
    ActivityInstanceRecord instance,
    DateTime dayStart,
  ) {
    final due = instance.dueDate;
    if (due == null) return true;
    final normalizedDue = normalizeDate(due);
    return normalizedDue.isAtSameMomentAs(dayStart) ||
        normalizedDue.isBefore(dayStart);
  }

  static int _compareDueDateAsc(
    ActivityInstanceRecord a,
    ActivityInstanceRecord b,
  ) {
    if (a.dueDate == null && b.dueDate == null) return 0;
    if (a.dueDate == null) return 1;
    if (b.dueDate == null) return -1;
    return a.dueDate!.compareTo(b.dueDate!);
  }

  static int _compareStatusTimestampDesc(
    ActivityInstanceRecord a,
    ActivityInstanceRecord b,
  ) {
    final aTs = statusTimestamp(a);
    final bTs = statusTimestamp(b);
    if (aTs == null && bTs == null) return 0;
    if (aTs == null) return 1;
    if (bTs == null) return -1;
    return bTs.compareTo(aTs);
  }

  static List<ActivityInstanceRecord> selectQueueItems(
    TodayInstanceSnapshot snapshot,
  ) {
    final items = snapshot.instances
        .where((i) =>
            i.isActive &&
            (i.templateCategoryType == 'task' ||
                i.templateCategoryType == 'habit'))
        .toList();
    return InstanceOrderService.sortInstancesByOrder(items, 'queue');
  }

  static List<ActivityInstanceRecord> selectTaskItems(
    TodayInstanceSnapshot snapshot,
  ) {
    final items = snapshot.instances
        .where((i) => i.isActive && i.templateCategoryType == 'task')
        .toList();
    return InstanceOrderService.sortInstancesByOrder(items, 'tasks');
  }

  static List<ActivityInstanceRecord> selectHabitItemsCurrentWindow(
    TodayInstanceSnapshot snapshot,
  ) {
    final items = snapshot.instances
        .where((i) =>
            i.isActive &&
            i.templateCategoryType == 'habit' &&
            isHabitWindowLive(i, snapshot.dayStart))
        .toList();
    return InstanceOrderService.sortInstancesByOrder(items, 'habits');
  }

  static List<ActivityInstanceRecord> selectHabitItemsLatestPerTemplate(
    TodayInstanceSnapshot snapshot,
  ) {
    final allHabits = snapshot.instances
        .where((i) => i.isActive && i.templateCategoryType == 'habit')
        .toList();
    final grouped = <String, List<ActivityInstanceRecord>>{};
    for (final instance in allHabits) {
      (grouped[instance.templateId] ??= []).add(instance);
    }
    final selected = <ActivityInstanceRecord>[];

    for (final instances in grouped.values) {
      instances.sort(_compareDueDateAsc);

      ActivityInstanceRecord? pick;
      for (final instance in instances) {
        if (instance.status == 'pending') {
          pick = instance;
          break;
        }
      }

      if (pick == null) {
        for (final instance in instances.reversed) {
          if (instance.status == 'completed' || instance.status == 'skipped') {
            pick = instance;
            break;
          }
        }
      }

      pick ??= instances.isNotEmpty ? instances.first : null;

      if (pick != null) {
        selected.add(pick);
      }
    }

    selected.sort(_compareDueDateAsc);
    return InstanceOrderService.sortInstancesByOrder(selected, 'habits');
  }

  static Map<String, ActivityInstanceRecord> selectRoutineItems({
    required TodayInstanceSnapshot snapshot,
    required RoutineRecord routine,
  }) {
    final mapByTemplate = <String, List<ActivityInstanceRecord>>{};
    for (final instance in snapshot.instances) {
      (mapByTemplate[instance.templateId] ??= []).add(instance);
    }

    final selected = <String, ActivityInstanceRecord>{};
    final recentThreshold = snapshot.dayStart.subtract(const Duration(days: 2));

    for (int i = 0; i < routine.itemIds.length; i++) {
      final itemId = routine.itemIds[i];
      final fallbackType =
          i < routine.itemTypes.length ? routine.itemTypes[i] : 'habit';
      final candidates =
          mapByTemplate[itemId] ?? const <ActivityInstanceRecord>[];
      if (candidates.isEmpty) {
        continue;
      }

      String itemType = fallbackType;
      for (final c in candidates) {
        if (c.templateCategoryType.isNotEmpty) {
          itemType = c.templateCategoryType;
          break;
        }
      }

      ActivityInstanceRecord? picked;
      if (itemType == 'essential') {
        picked = _pickRoutineEssential(
          candidates: candidates,
          snapshot: snapshot,
          recentThreshold: recentThreshold,
        );
      } else if (itemType == 'habit') {
        picked = _pickRoutineHabit(
          candidates: candidates,
          dayStart: snapshot.dayStart,
          recentThreshold: recentThreshold,
        );
      } else {
        picked = _pickRoutineTask(
          candidates: candidates,
          dayStart: snapshot.dayStart,
          recentThreshold: recentThreshold,
        );
      }

      if (picked != null) {
        selected[itemId] = picked;
      }
    }

    return selected;
  }

  static ActivityInstanceRecord? _pickRoutineEssential({
    required List<ActivityInstanceRecord> candidates,
    required TodayInstanceSnapshot snapshot,
    required DateTime recentThreshold,
  }) {
    final todayMatches = candidates.where((i) {
      final belongsToday = isSameDay(i.belongsToDate, snapshot.dayStart);
      final sessionToday =
          hasSessionOnDay(i, snapshot.dayStart, snapshot.dayEnd);
      return belongsToday || sessionToday;
    }).toList()
      ..sort((a, b) {
        if (a.status == 'pending' && b.status != 'pending') return -1;
        if (a.status != 'pending' && b.status == 'pending') return 1;
        return _compareStatusTimestampDesc(a, b);
      });
    if (todayMatches.isNotEmpty) {
      return todayMatches.first;
    }

    final recentCompletedOrSkipped = candidates
        .where((i) =>
            (i.status == 'completed' || i.status == 'skipped') &&
            (() {
              final ts = statusTimestamp(i);
              return ts != null && !ts.isBefore(recentThreshold);
            })())
        .toList()
      ..sort(_compareStatusTimestampDesc);
    if (recentCompletedOrSkipped.isNotEmpty) {
      return recentCompletedOrSkipped.first;
    }

    final pendingAny = candidates.where((i) => i.status == 'pending').toList()
      ..sort(_compareDueDateAsc);
    return pendingAny.isNotEmpty ? pendingAny.first : null;
  }

  static ActivityInstanceRecord? _pickRoutineHabit({
    required List<ActivityInstanceRecord> candidates,
    required DateTime dayStart,
    required DateTime recentThreshold,
  }) {
    final pendingLiveWindow = candidates
        .where((i) => i.status == 'pending' && isHabitWindowLive(i, dayStart))
        .toList()
      ..sort(_compareDueDateAsc);
    if (pendingLiveWindow.isNotEmpty) {
      return pendingLiveWindow.first;
    }

    final liveWindowAny =
        candidates.where((i) => isHabitWindowLive(i, dayStart)).toList()
          ..sort((a, b) {
            if (a.status == 'pending' && b.status != 'pending') return -1;
            if (a.status != 'pending' && b.status == 'pending') return 1;
            return _compareDueDateAsc(a, b);
          });
    if (liveWindowAny.isNotEmpty) {
      return liveWindowAny.first;
    }

    final recentCompletedOrSkipped = candidates
        .where((i) =>
            (i.status == 'completed' || i.status == 'skipped') &&
            (() {
              final ts = statusTimestamp(i);
              return ts != null && !ts.isBefore(recentThreshold);
            })())
        .toList()
      ..sort(_compareStatusTimestampDesc);
    if (recentCompletedOrSkipped.isNotEmpty) {
      return recentCompletedOrSkipped.first;
    }

    final nextPending = candidates.where((i) => i.status == 'pending').toList()
      ..sort(_compareDueDateAsc);
    return nextPending.isNotEmpty ? nextPending.first : null;
  }

  static ActivityInstanceRecord? _pickRoutineTask({
    required List<ActivityInstanceRecord> candidates,
    required DateTime dayStart,
    required DateTime recentThreshold,
  }) {
    final pendingTodayOrOverdue = candidates
        .where((i) =>
            i.status == 'pending' && isTaskDueTodayOrOverdue(i, dayStart))
        .toList()
      ..sort(_compareDueDateAsc);
    if (pendingTodayOrOverdue.isNotEmpty) {
      return pendingTodayOrOverdue.first;
    }

    final recentCompletedOrSkipped = candidates
        .where((i) =>
            (i.status == 'completed' || i.status == 'skipped') &&
            (() {
              final ts = statusTimestamp(i);
              return ts != null && !ts.isBefore(recentThreshold);
            })())
        .toList()
      ..sort(_compareStatusTimestampDesc);
    if (recentCompletedOrSkipped.isNotEmpty) {
      return recentCompletedOrSkipped.first;
    }

    final nextPending = candidates.where((i) => i.status == 'pending').toList()
      ..sort(_compareDueDateAsc);
    return nextPending.isNotEmpty ? nextPending.first : null;
  }

  static List<ActivityInstanceRecord> selectCalendarTodayTaskHabitPlanned(
    TodayInstanceSnapshot snapshot,
  ) {
    final dayStart = snapshot.dayStart;
    final now = DateTime.now();
    final planned = snapshot.instances.where((i) {
      if (!i.isActive) return false;
      if (i.status != 'pending') return false;
      final isCalendarPlannable = i.templateCategoryType == 'task' ||
          i.templateCategoryType == 'habit' ||
          i.templateCategoryType == 'essential';
      if (!isCalendarPlannable) return false;

      if (i.snoozedUntil != null && now.isBefore(i.snoozedUntil!)) {
        return false;
      }

      return _isDueOnTodayForCalendar(instance: i, dayStart: dayStart);
    }).toList();

    planned.sort(_compareDueDateAsc);
    return planned;
  }

  static bool _isDueOnTodayForCalendar({
    required ActivityInstanceRecord instance,
    required DateTime dayStart,
  }) {
    final due = instance.dueDate;
    if (due == null) {
      // Legacy calendar behavior treats undated pending instances as today.
      return true;
    }

    final normalizedDue = normalizeDate(due);
    if (instance.templateCategoryType == 'habit') {
      final windowEnd = instance.windowEndDate;
      if (windowEnd != null) {
        final normalizedWindowEnd = normalizeDate(windowEnd);
        return !dayStart.isBefore(normalizedDue) &&
            !dayStart.isAfter(normalizedWindowEnd);
      }
      // Habit without explicit window behaves as a single-day due item.
      return normalizedDue.isAtSameMomentAs(dayStart);
    }

    // Tasks/essentials include overdue items on today's planned timeline.
    return normalizedDue.isAtSameMomentAs(dayStart) ||
        normalizedDue.isBefore(dayStart);
  }

  static List<ActivityInstanceRecord> selectCalendarTodayCompleted(
    TodayInstanceSnapshot snapshot,
  ) {
    return snapshot.instances.where((i) {
      if (!i.isActive) return false;
      final completedToday = i.status == 'completed' &&
          isSameDay(i.completedAt, snapshot.dayStart);
      final sessionToday =
          hasSessionOnDay(i, snapshot.dayStart, snapshot.dayEnd);
      return completedToday || sessionToday;
    }).toList();
  }

  static List<ActivityInstanceRecord> selectEssentialTodayInstances(
    TodayInstanceSnapshot snapshot, {
    bool includePending = true,
    bool includeLogged = true,
  }) {
    if (!includePending && !includeLogged) {
      return const <ActivityInstanceRecord>[];
    }

    final essentials = snapshot.instances.where((i) {
      if (!i.isActive) return false;
      if (i.templateCategoryType != 'essential') return false;

      final pendingShape = isSameDay(i.belongsToDate, snapshot.dayStart);
      final loggedShape =
          hasSessionOnDay(i, snapshot.dayStart, snapshot.dayEnd) ||
              (i.totalTimeLogged > 0 &&
                  isSameDay(i.completedAt, snapshot.dayStart));

      if (includePending && includeLogged) {
        return pendingShape || loggedShape;
      }
      if (includePending) {
        return pendingShape;
      }
      return loggedShape;
    }).toList();

    essentials.sort((a, b) {
      if (a.status == 'pending' && b.status != 'pending') return -1;
      if (a.status != 'pending' && b.status == 'pending') return 1;
      return _compareStatusTimestampDesc(a, b);
    });

    return essentials;
  }

  static Map<String, Map<String, int>> selectEssentialTodayStatsByTemplate(
    TodayInstanceSnapshot snapshot,
  ) {
    final stats = <String, Map<String, int>>{};
    final loggedInstances = selectEssentialTodayInstances(
      snapshot,
      includePending: false,
      includeLogged: true,
    );

    for (final instance in loggedInstances) {
      final templateId = instance.templateId;
      if (templateId.isEmpty) continue;
      final current = stats.putIfAbsent(
        templateId,
        () => <String, int>{'count': 0, 'minutes': 0},
      );
      current['count'] = (current['count'] ?? 0) + 1;
      current['minutes'] =
          (current['minutes'] ?? 0) + _minutesForDay(instance, snapshot);
    }

    return stats;
  }

  static int _minutesForDay(
    ActivityInstanceRecord instance,
    TodayInstanceSnapshot snapshot,
  ) {
    var durationMs = 0;
    for (final session in instance.timeLogSessions) {
      final sessionStart = session['startTime'] as DateTime?;
      if (sessionStart == null) continue;
      if (sessionStart.isBefore(snapshot.dayStart) ||
          !sessionStart.isBefore(snapshot.dayEnd)) {
        continue;
      }
      final raw = session['durationMilliseconds'] as int?;
      if (raw != null && raw > 0) {
        durationMs += raw;
      }
    }
    if (durationMs <= 0 && instance.totalTimeLogged > 0) {
      durationMs = instance.totalTimeLogged;
    }
    return durationMs ~/ 60000;
  }
}
