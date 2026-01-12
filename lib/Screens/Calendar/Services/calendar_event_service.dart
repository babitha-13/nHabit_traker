import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/calendar_queue_service.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/utils/planned_duration_resolver.dart';
import 'package:habit_tracker/Helper/backend/routine_planned_calendar_service.dart';
import 'package:habit_tracker/Screens/Calendar/Calender%20models/calender_event_metadata.dart';
import 'package:habit_tracker/Screens/Calendar/Date%20Format/calendar_formatting_utils.dart';
import 'package:intl/intl.dart';

/// Service class for loading and processing calendar events
class CalendarEventService {
  /// Load and process calendar events for a given date
  static Future<CalendarEventsResult> loadEvents({
    required String userId,
    required DateTime selectedDate,
    required Map<String, ActivityInstanceRecord> optimisticInstances,
  }) async {
    final selectedDateStart = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      0,
      0,
      0,
    );
    final selectedDateEnd = selectedDateStart.add(const Duration(days: 1));
    final results = await Future.wait([
      queryHabitCategoriesOnce(
        userId: userId,
        callerTag: 'CalendarPage._loadEvents.habits',
      ),
      queryTaskCategoriesOnce(
        userId: userId,
        callerTag: 'CalendarPage._loadEvents.tasks',
      ),
      CalendarQueueService.getCompletedItems(
        userId: userId,
        date: selectedDate,
      ),
      TaskInstanceService.getTimeLoggedTasks(
        userId: userId,
        startDate: selectedDateStart,
        endDate: selectedDateEnd,
      ),
      TaskInstanceService.getessentialInstances(
        userId: userId,
        startDate: selectedDateStart,
        endDate: selectedDateEnd,
      ),
      CalendarQueueService.getQueueItems(
        userId: userId,
        date: selectedDate,
      ),
      queryRoutineRecordOnce(userId: userId),
    ]);

    final habitCategories = results[0] as List<CategoryRecord>;
    final taskCategories = results[1] as List<CategoryRecord>;
    final allCategories = [...habitCategories, ...taskCategories];
    final completedItems = results[2] as List<ActivityInstanceRecord>;
    final timeLoggedTasks = results[3] as List<ActivityInstanceRecord>;
    final essentialInstances = results[4] as List<ActivityInstanceRecord>;
    final queueItems = results[5] as Map<String, dynamic>;
    final routines = results[6] as List<RoutineRecord>;

    final allItemsMap = <String, ActivityInstanceRecord>{};
    for (final item in completedItems) {
      allItemsMap[item.reference.id] = item;
    }
    for (final item in timeLoggedTasks) {
      allItemsMap[item.reference.id] = item;
    }
    for (final item in essentialInstances) {
      allItemsMap[item.reference.id] = item;
    }

    final completedEvents = <CalendarEventData>[];
    final plannedEvents = <CalendarEventData>[];

    for (final item in allItemsMap.values) {
      Color categoryColor;
      if (item.templateCategoryColor.isNotEmpty) {
        try {
          categoryColor = CalendarFormattingUtils.parseColor(item.templateCategoryColor);
        } catch (e) {
          categoryColor = Colors.blue;
        }
      } else {
        CategoryRecord? category;
        try {
          category = allCategories.firstWhere(
            (c) => c.reference.id == item.templateCategoryId,
          );
        } catch (e) {
          try {
            category = allCategories.firstWhere(
              (c) => c.name == item.templateCategoryName,
            );
          } catch (e2) {
          }
        }
        if (category != null) {
          categoryColor = CalendarFormattingUtils.parseColor(category.color);
        } else {
          categoryColor = Colors.blue;
        }
      }

      if (item.timeLogSessions.isNotEmpty) {
        final sessionsOnDate = item.timeLogSessions.where((session) {
          final sessionStart = session['startTime'] as DateTime;
          final sessionDate = DateTime(
            sessionStart.year,
            sessionStart.month,
            sessionStart.day,
          );
          final selectedDateOnly = DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
          );
          return sessionDate.isAtSameMomentAs(selectedDateOnly);
        }).toList();

        if (sessionsOnDate.isNotEmpty) {
          for (int i = 0; i < sessionsOnDate.length; i++) {
            final session = sessionsOnDate[i];
            final sessionStart = session['startTime'] as DateTime;
            final sessionEnd = session['endTime'] as DateTime?;
            if (sessionEnd == null) {
              continue;
            }
            int originalSessionIndex = -1;
            for (int j = 0; j < item.timeLogSessions.length; j++) {
              final fullSession = item.timeLogSessions[j];
              final fullSessionStart = fullSession['startTime'] as DateTime;
              if (fullSessionStart.isAtSameMomentAs(sessionStart)) {
                originalSessionIndex = j;
                break;
              }
            }
            var actualSessionEnd = sessionEnd;
            if (actualSessionEnd.difference(sessionStart).inSeconds < 60) {
              actualSessionEnd = sessionStart.add(const Duration(minutes: 1));
            }
            final selectedDateStart = DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
              0,
              0,
              0,
            );
            final selectedDateEnd = selectedDateStart.add(const Duration(days: 1));
            var validStartTime = sessionStart;
            var validEndTime = actualSessionEnd;

            if (validStartTime.isBefore(selectedDateStart)) {
              validStartTime = selectedDateStart;
            } else if (validStartTime.isAfter(selectedDateEnd) || validStartTime.isAtSameMomentAs(selectedDateEnd)) {
              continue;
            }

            if (validEndTime.isAfter(selectedDateEnd)) {
              validEndTime = selectedDateEnd.subtract(const Duration(seconds: 1));
            }

            if (validEndTime.isBefore(validStartTime) || validEndTime.isAtSameMomentAs(validStartTime)) {
              validEndTime = validStartTime.add(const Duration(minutes: 1));
            }

            final startDateOnly = DateTime(
              validStartTime.year,
              validStartTime.month,
              validStartTime.day,
            );
            final selectedDateOnly = DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
            );

            if (startDateOnly.isAtSameMomentAs(selectedDateOnly)) {
              final prefix = item.status == 'completed' ? '✓ ' : '';
              String? categoryColorHex;
              if (item.templateCategoryType == 'habit' || item.templateCategoryType == 'task') {
                CategoryRecord? category;
                try {
                  category = allCategories.firstWhere(
                    (c) => c.reference.id == item.templateCategoryId,
                  );
                } catch (e) {
                  try {
                    category = allCategories.firstWhere(
                      (c) => c.name == item.templateCategoryName,
                    );
                  } catch (e2) {
                  }
                }
                if (category != null) {
                  categoryColorHex = category.color;
                } else if (item.templateCategoryColor.isNotEmpty) {
                  categoryColorHex = item.templateCategoryColor;
                }
              } else if (item.templateCategoryType == 'essential') {
                categoryColorHex = '#808080'; // Grey hex
              }

              final categoryType = item.templateCategoryType;
              final metadata = CalendarEventMetadata(
                instanceId: item.reference.id,
                sessionIndex: originalSessionIndex >= 0 ? originalSessionIndex : i,
                activityName: item.templateName,
                activityType: categoryType,
                templateId: item.templateId,
                categoryId: item.templateCategoryId.isNotEmpty
                    ? item.templateCategoryId
                    : null,
                categoryName: item.templateCategoryName.isNotEmpty
                    ? item.templateCategoryName
                    : null,
                categoryColorHex: categoryColorHex,
              );

              completedEvents.add(CalendarEventData(
                date: selectedDate,
                startTime: validStartTime,
                endTime: validEndTime,
                title: '$prefix${item.templateName}',
                color: categoryColor,
                description: 'Session: ${CalendarFormattingUtils.formatDuration(validEndTime.difference(validStartTime))}',
                event: metadata.toMap(),
              ));
            }
          }
        }
      }
    }

    completedEvents.sort((a, b) {
      if (a.endTime == null || b.endTime == null) return 0;
      final endCompare = b.endTime!.compareTo(a.endTime!);
      if (endCompare != 0) return endCompare;
      if (a.startTime == null || b.startTime == null) return 0;
      return b.startTime!.compareTo(a.startTime!);
    });

    DateTime? earliestStartTime;
    final cascadedEvents = <CalendarEventData>[];
    for (final event in completedEvents) {
      if (event.startTime == null || event.endTime == null) continue;

      DateTime startTime = event.startTime!;
      DateTime endTime = event.endTime!;
      final duration = endTime.difference(startTime);
      if (earliestStartTime != null && endTime.isAfter(earliestStartTime)) {
        endTime = earliestStartTime;
        startTime = endTime.subtract(duration);
      }
      if (earliestStartTime == null || startTime.isBefore(earliestStartTime)) {
        earliestStartTime = startTime;
      }
      cascadedEvents.add(CalendarEventData(
        date: selectedDate,
        startTime: startTime,
        endTime: endTime,
        title: event.title,
        color: event.color,
        description: event.description,
        event: event.event,
      ));
    }
    cascadedEvents.sort((a, b) => a.startTime!.compareTo(b.startTime!));

    final plannedItems = List<ActivityInstanceRecord>.from(queueItems['planned'] ?? []);
    final selectedDateOnly = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    for (final optimisticInstance in optimisticInstances.values) {
      if (optimisticInstance.dueDate != null &&
          optimisticInstance.dueTime != null &&
          optimisticInstance.dueTime!.isNotEmpty) {
        final dueDateOnly = DateTime(
          optimisticInstance.dueDate!.year,
          optimisticInstance.dueDate!.month,
          optimisticInstance.dueDate!.day,
        );
        if (dueDateOnly.isAtSameMomentAs(selectedDateOnly)) {
          final exists = plannedItems.any(
              (item) => item.reference.id == optimisticInstance.reference.id);
          if (!exists) {
            plannedItems.add(optimisticInstance);
          }
        }
      }
    }

    final plannedItemsWithTime = plannedItems.where((item) => item.dueTime != null && item.dueTime!.isNotEmpty).toList();
    final explicitlyScheduledTemplateIds = <String>{
      ...plannedItemsWithTime.map((i) => i.templateId).whereType<String>(),
    };
    final plannedDurationByInstanceId = userId.isEmpty
        ? <String, int?>{}
        : await PlannedDurationResolver.resolveDurationMinutesForInstances(
            userId: userId,
            instances: plannedItemsWithTime,
          );

    for (final item in plannedItemsWithTime) {
      Color categoryColor;
      if (item.templateCategoryColor.isNotEmpty) {
        try {
          categoryColor = CalendarFormattingUtils.parseColor(item.templateCategoryColor);
        } catch (e) {
          categoryColor = Colors.blue;
        }
      } else {
        CategoryRecord? category;
        try {
          category = allCategories.firstWhere(
            (c) => c.reference.id == item.templateCategoryId,
          );
        } catch (e) {
          try {
            category = allCategories.firstWhere(
              (c) => c.name == item.templateCategoryName,
            );
          } catch (e2) {
          }
        }
        if (category != null) {
          categoryColor = CalendarFormattingUtils.parseColor(category.color);
        } else {
          categoryColor = Colors.blue;
        }
      }
      DateTime startTime = CalendarFormattingUtils.parseDueTime(item.dueTime!, selectedDate);
      final instanceId = item.reference.id;
      final durationMinutes = plannedDurationByInstanceId[instanceId];

      final metadata = CalendarEventMetadata(
        instanceId: instanceId,
        sessionIndex: -1,
        activityName: item.templateName,
        activityType: item.templateCategoryType,
        templateId: item.templateId,
        categoryId: item.templateCategoryId.isNotEmpty
            ? item.templateCategoryId
            : null,
        categoryName: item.templateCategoryName.isNotEmpty
            ? item.templateCategoryName
            : null,
        categoryColorHex: item.templateCategoryColor.isNotEmpty
            ? item.templateCategoryColor
            : null,
      );
      final isDueMarker = durationMinutes == null || durationMinutes <= 0;
      final endTime = isDueMarker
          ? startTime.add(const Duration(minutes: 1))
          : startTime.add(Duration(minutes: durationMinutes));

      plannedEvents.add(CalendarEventData(
        date: selectedDate,
        startTime: startTime,
        endTime: endTime,
        title: item.templateName,
        color: categoryColor,
        description: isDueMarker
            ? null
            : CalendarFormattingUtils.formatDuration(Duration(minutes: durationMinutes)),
        event: {
          ...metadata.toMap(),
          'isDueMarker': isDueMarker,
        },
      ));
    }

    if (userId.isNotEmpty) {
      final routinePlanned =
          await RoutinePlannedCalendarService.getPlannedRoutineEvents(
        userId: userId,
        date: selectedDate,
        routines: routines,
        excludedTemplateIds: explicitlyScheduledTemplateIds,
      );

      for (final r in routinePlanned) {
        final startTime = CalendarFormattingUtils.parseDueTime(r.dueTime, selectedDate);
        final isDueMarker = r.durationMinutes == null || r.durationMinutes! <= 0;
        final endTime = isDueMarker
            ? startTime.add(const Duration(minutes: 1))
            : startTime.add(Duration(minutes: r.durationMinutes!));

        final metadata = CalendarEventMetadata(
          instanceId: r.routineId != null
              ? 'routine:${r.routineId}'
              : 'activity:${r.activityId}',
          sessionIndex: -1,
          activityName: r.name,
          activityType: r.routineId != null ? 'routine' : 'essential',
          templateId: r.activityId,
          categoryId: null,
          categoryName: null,
          categoryColorHex: null,
        );

        plannedEvents.add(CalendarEventData(
          date: selectedDate,
          startTime: startTime,
          endTime: endTime,
          title: r.routineId != null ? 'Routine: ${r.name}' : r.name,
          color: r.routineId != null ? Colors.deepPurple : Colors.blueGrey,
          description: isDueMarker
              ? null
              : CalendarFormattingUtils.formatDuration(Duration(minutes: r.durationMinutes!)),
          event: {
            ...metadata.toMap(),
            if (r.routineId != null) 'routineId': r.routineId,
            if (r.activityId != null) 'activityId': r.activityId,
            'isDueMarker': isDueMarker,
          },
        ));
      }
    }

    plannedEvents.sort((a, b) {
      if (a.startTime == null || b.startTime == null) return 0;
      return a.startTime!.compareTo(b.startTime!);
    });

    return CalendarEventsResult(
      completedEvents: cascadedEvents,
      plannedEvents: plannedEvents,
    );
  }
}

/// Result class for calendar events loading
class CalendarEventsResult {
  final List<CalendarEventData> completedEvents;
  final List<CalendarEventData> plannedEvents;

  CalendarEventsResult({
    required this.completedEvents,
    required this.plannedEvents,
  });
}
