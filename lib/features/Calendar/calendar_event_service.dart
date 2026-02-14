import 'dart:async';
import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_activity_data_service.dart';
import 'package:habit_tracker/core/config/instance_repository_flags.dart';
import 'package:habit_tracker/services/Activtity/task_instance_service/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/features/Calendar/Helpers/planned_duration_resolver.dart';
import 'package:habit_tracker/features/Routine/Backend_data/routine_planned_calendar_service.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_events_result.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_models.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_formatting_utils.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_repository.dart';
import 'package:habit_tracker/services/diagnostics/instance_parity_logger.dart';

/// Service class for loading and processing calendar events
class CalendarEventService {
  static final Map<String, String> _lastOptimisticSignatureByScope = {};

  static String _dateScopeKey({
    required String userId,
    required DateTime selectedDate,
    required bool includePlanned,
  }) {
    final normalized = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final mode = includePlanned ? 'full' : 'completed_only';
    return '$userId|${normalized.year}-${normalized.month}-${normalized.day}|$mode';
  }

  static String _buildOptimisticSignature(
    Map<String, ActivityInstanceRecord> optimisticInstances,
  ) {
    if (optimisticInstances.isEmpty) {
      return '';
    }

    final entries = optimisticInstances.values.map((instance) {
      final dueDateMillis = instance.dueDate?.millisecondsSinceEpoch ?? 0;
      final belongsDateMillis =
          instance.belongsToDate?.millisecondsSinceEpoch ?? 0;
      final updatedMillis = instance.lastUpdated?.millisecondsSinceEpoch ?? 0;
      final sessionsSignature = instance.timeLogSessions.map((session) {
        final start = session['startTime'];
        final end = session['endTime'];
        final startMs = start is DateTime ? start.millisecondsSinceEpoch : 0;
        final endMs = end is DateTime ? end.millisecondsSinceEpoch : 0;
        return '$startMs-$endMs';
      }).join(',');
      return '${instance.reference.id}:${instance.status}:$updatedMillis:${instance.totalTimeLogged}:$sessionsSignature:$dueDateMillis:${instance.dueTime ?? ''}:$belongsDateMillis';
    }).toList()
      ..sort();

    return entries.join('|');
  }

  static DateTime _normalizeDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool _isSameDay(DateTime? value, DateTime targetDayStart) {
    if (value == null) return false;
    return _normalizeDate(value).isAtSameMomentAs(targetDayStart);
  }

  static bool _hasSessionOnDay(
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

  static bool _isDueOnToday(ActivityInstanceRecord instance, DateTime dayStart) {
    final due = instance.dueDate;
    if (due == null) {
      return true;
    }
    final normalizedDue = _normalizeDate(due);
    if (instance.templateCategoryType == 'habit') {
      final windowEnd = instance.windowEndDate;
      if (windowEnd != null) {
        final normalizedWindowEnd = _normalizeDate(windowEnd);
        return !dayStart.isBefore(normalizedDue) &&
            !dayStart.isAfter(normalizedWindowEnd);
      }
      return normalizedDue.isAtSameMomentAs(dayStart);
    }
    return normalizedDue.isAtSameMomentAs(dayStart) ||
        normalizedDue.isBefore(dayStart);
  }

  static bool _hasDueTime(ActivityInstanceRecord instance) {
    final dueTime = instance.dueTime;
    return dueTime != null && dueTime.isNotEmpty;
  }

  /// Load and process calendar events for a given date
  /// Uses caching to avoid redundant queries when navigating between dates
  static Future<CalendarEventsResult> loadEvents({
    required String userId,
    required DateTime selectedDate,
    required bool includePlanned,
    required Map<String, ActivityInstanceRecord> optimisticInstances,
  }) async {
    final cache = FirestoreCacheService();
    final cacheVariant = includePlanned ? 'full' : 'completed_only';
    final scopeKey = _dateScopeKey(
      userId: userId,
      selectedDate: selectedDate,
      includePlanned: includePlanned,
    );
    final optimisticSignature = _buildOptimisticSignature(optimisticInstances);

    if (optimisticSignature.isEmpty) {
      _lastOptimisticSignatureByScope.remove(scopeKey);
    } else {
      final previousSignature = _lastOptimisticSignatureByScope[scopeKey];
      if (previousSignature != optimisticSignature) {
        // Invalidate once per changed optimistic state so cache can be reused
        // across observer bursts while optimistic data remains unchanged.
        cache.invalidateCalendarDateCache(selectedDate);
        _lastOptimisticSignatureByScope[scopeKey] = optimisticSignature;
      }
    }

    // Check cache (date + mode variant)
    final cached = cache.getCachedCalendarEvents(
      selectedDate,
      variant: cacheVariant,
    );
    if (cached != null) {
      return cached;
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
    final normalizedSelectedDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final isTodaySelected =
        normalizedSelectedDate.isAtSameMomentAs(DateService.todayStart);
    if (isTodaySelected && !InstanceRepositoryFlags.useRepoCalendarToday) {
      InstanceRepositoryFlags.onLegacyPathUsed(
        'CalendarEventService.loadEvents(today)',
      );
    }

    List<ActivityInstanceRecord> completedItems = <ActivityInstanceRecord>[];
    List<ActivityInstanceRecord> timeLoggedTasks = <ActivityInstanceRecord>[];
    List<ActivityInstanceRecord> essentialInstances =
        <ActivityInstanceRecord>[];
    List<ActivityInstanceRecord> plannedItemsFromBackend =
        <ActivityInstanceRecord>[];
    List<RoutineRecord> routines = <RoutineRecord>[];

    if (isTodaySelected && InstanceRepositoryFlags.useRepoCalendarToday) {
      try {
        final repo = TodayInstanceRepository.instance;
        await repo.ensureHydratedForTasks(userId: userId);

        final dayStart = DateService.todayStart;
        final dayEnd = dayStart.add(const Duration(days: 1));
        final taskItems = repo.selectTaskItems();

        final completedById = <String, ActivityInstanceRecord>{};
        for (final item in repo.selectCalendarTodayCompleted()) {
          completedById[item.reference.id] = item;
        }
        final completedFromCalendarQuery = await CalendarQueueService
            .getCompletedItems(
          userId: userId,
          date: selectedDate,
        );
        for (final item in completedFromCalendarQuery) {
          completedById[item.reference.id] = item;
        }
        for (final item in taskItems) {
          if (!item.isActive) continue;
          final completedToday =
              item.status == 'completed' && _isSameDay(item.completedAt, dayStart);
          final sessionToday = _hasSessionOnDay(item, dayStart, dayEnd);
          if (completedToday || sessionToday) {
            completedById[item.reference.id] = item;
          }
        }
        completedItems = completedById.values.toList();

        final timeLoggedById = <String, ActivityInstanceRecord>{};
        for (final item in completedItems) {
          final isTaskOrHabit = item.templateCategoryType == 'task' ||
              item.templateCategoryType == 'habit';
          if (!isTaskOrHabit) continue;
          if (_hasSessionOnDay(item, dayStart, dayEnd)) {
            timeLoggedById[item.reference.id] = item;
          }
        }
        timeLoggedTasks = timeLoggedById.values.toList();
        essentialInstances = repo.selectEssentialTodayInstances(
          includePending: true,
          includeLogged: true,
        );

        if (includePlanned) {
          final plannedById = <String, ActivityInstanceRecord>{};
          for (final item in repo.selectCalendarTodayTaskHabitPlanned()) {
            plannedById[item.reference.id] = item;
          }
          final now = DateTime.now();
          for (final item in taskItems) {
            if (!item.isActive || item.status != 'pending') continue;
            if (item.snoozedUntil != null && now.isBefore(item.snoozedUntil!)) {
              continue;
            }
            if (_isDueOnToday(item, dayStart)) {
              plannedById[item.reference.id] = item;
            }
          }
          for (final item in essentialInstances) {
            if (!item.isActive || item.status != 'pending') continue;
            if (item.snoozedUntil != null && now.isBefore(item.snoozedUntil!)) {
              continue;
            }
            if (_isDueOnToday(item, dayStart)) {
              plannedById[item.reference.id] = item;
            }
          }
          plannedItemsFromBackend = plannedById.values.toList();
          plannedItemsFromBackend.sort((a, b) {
            if (a.dueDate == null && b.dueDate == null) return 0;
            if (a.dueDate == null) return 1;
            if (b.dueDate == null) return -1;
            return a.dueDate!.compareTo(b.dueDate!);
          });
          routines = await queryRoutineRecordOnce(userId: userId);
        }

        if (InstanceRepositoryFlags.enableParityChecks) {
          final parityResults = await Future.wait<dynamic>([
            CalendarQueueService.getPlannedItems(
              userId: userId,
              date: selectedDate,
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
          ]);
          final legacyPlanned =
              List<ActivityInstanceRecord>.from(parityResults[0] ?? []);
          final legacyCompleted = <String, ActivityInstanceRecord>{};
          for (final item
              in List<ActivityInstanceRecord>.from(parityResults[1] ?? [])) {
            legacyCompleted[item.reference.id] = item;
          }
          for (final item
              in List<ActivityInstanceRecord>.from(parityResults[2] ?? [])) {
            legacyCompleted[item.reference.id] = item;
          }
          for (final item
              in List<ActivityInstanceRecord>.from(parityResults[3] ?? [])) {
            legacyCompleted[item.reference.id] = item;
          }

          final legacyPlannedForParity =
              legacyPlanned.where(_hasDueTime).toList(growable: false);
          final legacyCompletedForParity = legacyCompleted.values
              .where((item) =>
                  item.status == 'completed' &&
                  _hasSessionOnDay(item, selectedDateStart, selectedDateEnd))
              .toList(growable: false);

          final repoPlannedForParity = plannedItemsFromBackend
              .where(_hasDueTime)
              .toList(growable: false);
          final repoCompletedForParity = <String, ActivityInstanceRecord>{};
          for (final item in completedItems) {
            if (item.status == 'completed' &&
                _hasSessionOnDay(item, selectedDateStart, selectedDateEnd)) {
              repoCompletedForParity[item.reference.id] = item;
            }
          }
          for (final item in essentialInstances) {
            if (item.status == 'completed' &&
                _hasSessionOnDay(item, selectedDateStart, selectedDateEnd)) {
              repoCompletedForParity[item.reference.id] = item;
            }
          }

          InstanceParityLogger.logCalendarParity(
            legacyPlanned: legacyPlannedForParity,
            repoPlanned: repoPlannedForParity,
            legacyCompleted: legacyCompletedForParity,
            repoCompleted: repoCompletedForParity.values.toList(),
          );
        }
      } catch (e) {
        logFirestoreIndexError(
          e,
          'CalendarEventService.loadEvents (today repository path)',
          'activity_instances',
        );
        rethrow;
      }
    } else {
      List<dynamic> results;
      try {
        final futures = <Future<dynamic>>[
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
        ];

        if (includePlanned) {
          futures.add(
            CalendarQueueService.getPlannedItems(
              userId: userId,
              date: selectedDate,
            ),
          );
          futures.add(queryRoutineRecordOnce(userId: userId));
        }

        results = await Future.wait(futures).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException(
              'CalendarEventService.loadEvents timed out after 30 seconds',
              const Duration(seconds: 30),
            );
          },
        );
      } catch (e) {
        logFirestoreIndexError(
          e,
          'CalendarEventService.loadEvents (Future.wait - multiple queries)',
          'multiple collections',
        );
        rethrow;
      }

      var resultIndex = 0;
      completedItems =
          List<ActivityInstanceRecord>.from(results[resultIndex++] ?? []);
      timeLoggedTasks =
          List<ActivityInstanceRecord>.from(results[resultIndex++] ?? []);
      essentialInstances =
          List<ActivityInstanceRecord>.from(results[resultIndex++] ?? []);
      plannedItemsFromBackend = includePlanned
          ? List<ActivityInstanceRecord>.from(results[resultIndex++] ?? [])
          : <ActivityInstanceRecord>[];
      routines = includePlanned
          ? List<RoutineRecord>.from(results[resultIndex++] ?? [])
          : <RoutineRecord>[];
    }

    final routineItemMap = <String, List<String>>{};
    for (final routine in routines) {
      routineItemMap[routine.reference.id] = routine.itemIds;
      if (routine.uid.isNotEmpty) {
        routineItemMap[routine.uid] = routine.itemIds;
      }
    }

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

    // Merge optimistic instances (overwriting backend data) to ensure immediate UI updates
    // This handles cases like deleting a time log session where backend might be slightly stale
    for (final optimisticInstance in optimisticInstances.values) {
      allItemsMap[optimisticInstance.reference.id] = optimisticInstance;
    }

    final selectedDateOnly = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final plannedItemsWithOptimistic = includePlanned
        ? List<ActivityInstanceRecord>.from(plannedItemsFromBackend)
        : <ActivityInstanceRecord>[];
    if (includePlanned) {
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
            final exists = plannedItemsWithOptimistic.any(
              (item) => item.reference.id == optimisticInstance.reference.id,
            );
            if (!exists) {
              plannedItemsWithOptimistic.add(optimisticInstance);
            }
          }
        }
      }
    }

    bool needsCategoryLookup(ActivityInstanceRecord item) {
      final isTaskOrHabit = item.templateCategoryType == 'task' ||
          item.templateCategoryType == 'habit';
      if (!isTaskOrHabit) {
        return false;
      }
      if (item.templateCategoryColor.isNotEmpty) {
        return false;
      }
      return item.templateCategoryId.isNotEmpty ||
          item.templateCategoryName.isNotEmpty;
    }

    final shouldFetchCategories = allItemsMap.values.any(needsCategoryLookup) ||
        plannedItemsWithOptimistic.any(needsCategoryLookup);

    List<CategoryRecord> habitCategories = const [];
    List<CategoryRecord> taskCategories = const [];
    if (shouldFetchCategories) {
      try {
        final categoryResults = await Future.wait<dynamic>([
          queryHabitCategoriesOnce(
            userId: userId,
            callerTag: 'CalendarPage._loadEvents.habits',
          ),
          queryTaskCategoriesOnce(
            userId: userId,
            callerTag: 'CalendarPage._loadEvents.tasks',
          ),
        ]).timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            throw TimeoutException(
              'CalendarEventService.loadEvents category lookup timed out',
              const Duration(seconds: 20),
            );
          },
        );
        habitCategories = List<CategoryRecord>.from(categoryResults[0] ?? []);
        taskCategories = List<CategoryRecord>.from(categoryResults[1] ?? []);
      } catch (e) {
        logFirestoreIndexError(
          e,
          'CalendarEventService.loadEvents (category lookup)',
          'categories',
        );
      }
    }
    final allCategories = [...habitCategories, ...taskCategories];
    // Optimize: Create category lookup maps once (O(1) lookup instead of O(n) firstWhere)
    final categoryById = <String, CategoryRecord>{};
    final categoryByName = <String, CategoryRecord>{};
    for (final category in allCategories) {
      categoryById[category.reference.id] = category;
      categoryByName[category.name] = category;
    }

    final completedEvents = <CalendarEventData>[];
    final plannedEvents = <CalendarEventData>[];

    for (final item in allItemsMap.values) {
      Color categoryColor;
      if (item.templateCategoryColor.isNotEmpty) {
        try {
          categoryColor =
              CalendarFormattingUtils.parseColor(item.templateCategoryColor);
        } catch (e) {
          categoryColor = Colors.blue;
        }
      } else {
        // Use map lookup instead of firstWhere (O(1) vs O(n))
        CategoryRecord? category = categoryById[item.templateCategoryId] ??
            categoryByName[item.templateCategoryName];
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
            int originalSessionIndex =
                item.timeLogSessions.indexWhere((fullSession) {
              final fullSessionStart = fullSession['startTime'] as DateTime?;
              final fullSessionEnd = fullSession['endTime'] as DateTime?;
              if (fullSessionStart == null || fullSessionEnd == null) {
                return false;
              }
              return fullSessionStart.isAtSameMomentAs(sessionStart) &&
                  fullSessionEnd.isAtSameMomentAs(sessionEnd);
            });
            if (originalSessionIndex < 0) {
              originalSessionIndex =
                  item.timeLogSessions.indexWhere((fullSession) {
                final fullSessionStart = fullSession['startTime'] as DateTime?;
                if (fullSessionStart == null) {
                  return false;
                }
                return fullSessionStart.isAtSameMomentAs(sessionStart);
              });
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
            final selectedDateEnd =
                selectedDateStart.add(const Duration(days: 1));
            var validStartTime = sessionStart;
            var validEndTime = actualSessionEnd;

            if (validStartTime.isBefore(selectedDateStart)) {
              validStartTime = selectedDateStart;
            } else if (validStartTime.isAfter(selectedDateEnd) ||
                validStartTime.isAtSameMomentAs(selectedDateEnd)) {
              continue;
            }

            if (validEndTime.isAfter(selectedDateEnd)) {
              validEndTime =
                  selectedDateEnd.subtract(const Duration(seconds: 1));
            }

            if (validEndTime.isBefore(validStartTime) ||
                validEndTime.isAtSameMomentAs(validStartTime)) {
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
              if (item.templateCategoryType == 'habit' ||
                  item.templateCategoryType == 'task') {
                // Use map lookup instead of firstWhere (O(1) vs O(n))
                CategoryRecord? category =
                    categoryById[item.templateCategoryId] ??
                        categoryByName[item.templateCategoryName];
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
                sessionIndex:
                    originalSessionIndex >= 0 ? originalSessionIndex : i,
                sessionStartEpochMs: sessionStart.millisecondsSinceEpoch,
                sessionEndEpochMs: sessionEnd.millisecondsSinceEpoch,
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
                description:
                    'Session: ${CalendarFormattingUtils.formatDuration(validEndTime.difference(validStartTime))}',
                event: metadata.toMap(),
              ));
            }
          }
        }
      }
    }

    // Optimize: Sort once and process cascading efficiently
    // Sort by end time descending, then start time descending
    completedEvents.sort((a, b) {
      if (a.endTime == null || b.endTime == null) return 0;
      final endCompare = b.endTime!.compareTo(a.endTime!);
      if (endCompare != 0) return endCompare;
      if (a.startTime == null || b.startTime == null) return 0;
      return b.startTime!.compareTo(a.startTime!);
    });

    // Optimize cascading calculation: filter valid events first, then process
    final validEvents = completedEvents
        .where((e) => e.startTime != null && e.endTime != null)
        .toList();

    DateTime? earliestStartTime;
    final cascadedEvents = <CalendarEventData>[];
    final selectedDayStart = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final selectedDayEnd = selectedDayStart.add(const Duration(days: 1));

    // Process events in order (latest end time first)
    // This allows cascading to work correctly by pushing earlier events back
    for (final event in validEvents) {
      DateTime startTime = event.startTime!;
      DateTime endTime = event.endTime!;
      final duration = endTime.difference(startTime);

      if (earliestStartTime != null && endTime.isAfter(earliestStartTime)) {
        endTime = earliestStartTime;
        startTime = endTime.subtract(duration);
      }

      if (startTime.isBefore(selectedDayStart)) {
        startTime = selectedDayStart;
      }
      if (!endTime.isAfter(startTime)) {
        endTime = startTime.add(const Duration(minutes: 1));
      }
      if (!endTime.isBefore(selectedDayEnd)) {
        endTime = selectedDayEnd.subtract(const Duration(seconds: 1));
      }
      if (!endTime.isAfter(startTime)) {
        continue;
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

    // Sort by start time ascending for final display order
    cascadedEvents.sort((a, b) {
      if (a.startTime == null || b.startTime == null) return 0;
      return a.startTime!.compareTo(b.startTime!);
    });

    if (includePlanned) {
      final plannedItemsWithTime = plannedItemsWithOptimistic
          .where((item) => item.dueTime != null && item.dueTime!.isNotEmpty)
          .toList();
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
            categoryColor =
                CalendarFormattingUtils.parseColor(item.templateCategoryColor);
          } catch (e) {
            categoryColor = Colors.blue;
          }
        } else {
          // Use map lookup instead of firstWhere (O(1) vs O(n))
          CategoryRecord? category = categoryById[item.templateCategoryId] ??
              categoryByName[item.templateCategoryName];
          if (category != null) {
            categoryColor = CalendarFormattingUtils.parseColor(category.color);
          } else {
            categoryColor = Colors.blue;
          }
        }
        DateTime startTime =
            CalendarFormattingUtils.parseDueTime(item.dueTime!, selectedDate);
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
              : CalendarFormattingUtils.formatDuration(
                  Duration(minutes: durationMinutes)),
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
          final startTime =
              CalendarFormattingUtils.parseDueTime(r.dueTime, selectedDate);
          final isDueMarker =
              r.durationMinutes == null || r.durationMinutes! <= 0;
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
                : CalendarFormattingUtils.formatDuration(
                    Duration(minutes: r.durationMinutes!)),
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
    }

    final result = CalendarEventsResult(
      completedEvents: cascadedEvents,
      plannedEvents: plannedEvents,
      routineItemMap: routineItemMap,
    );

    // Cache the result
    cache.cacheCalendarEvents(
      selectedDate,
      result,
      variant: cacheVariant,
    );

    return result;
  }
}
