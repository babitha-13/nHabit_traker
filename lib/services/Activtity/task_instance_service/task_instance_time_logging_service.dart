import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/features/Essential/essential_data_service.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/core/utils/Date_time/time_validation_helper.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';
import 'package:habit_tracker/services/Activtity/timer_activities_util.dart';
import 'package:habit_tracker/services/diagnostics/fallback_read_logger.dart';
import 'task_instance_helper_service.dart';
import 'task_instance_task_service.dart';
import 'task_instance_timer_task_service.dart';

/// Service for time logging operations
class TaskInstanceTimeLoggingService {
  static Future<ActivityInstanceRecord> _getInstanceServerFirst(
    DocumentReference instanceRef,
  ) async {
    try {
      final serverDoc = await instanceRef.get(
        const GetOptions(source: Source.server),
      );
      if (serverDoc.exists) {
        return ActivityInstanceRecord.fromSnapshot(serverDoc);
      }
    } catch (_) {
      // Fallback to cache when server read is temporarily unavailable.
    }

    final cacheDoc = await instanceRef.get(
      const GetOptions(source: Source.cache),
    );
    if (!cacheDoc.exists) {
      throw Exception('Instance not found');
    }
    return ActivityInstanceRecord.fromSnapshot(cacheDoc);
  }

  static Future<void> startTimeLogging({
    required DocumentReference activityInstanceRef,
    String? userId,
  }) async {
    try {
      final instance = await _getInstanceServerFirst(activityInstanceRef);
      final error = TimeValidationHelper.getStartTimerError(instance);
      if (error != null) {
        throw Exception(error);
      }
      await activityInstanceRef.update({
        'isTimeLogging': true,
        'currentSessionStartTime': DateTime.now(),
        'lastUpdated': DateTime.now(),
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Stop time logging and optionally mark task as complete
  static Future<void> stopTimeLogging({
    required DocumentReference activityInstanceRef,
    required bool markComplete,
    String? userId,
  }) async {
    try {
      final instance = await _getInstanceServerFirst(activityInstanceRef);
      if (instance.currentSessionStartTime == null) {
        throw Exception('No active session to stop');
      }
      final endTime = DateTime.now();
      final duration = endTime.difference(instance.currentSessionStartTime!);
      final validationError = TimerUtil.validateMaxDuration(duration) ??
          TimeValidationHelper.validateSessionDuration(duration);
      if (validationError != null) {
        throw Exception(validationError);
      }
      final newSession = {
        'startTime': instance.currentSessionStartTime,
        'endTime': endTime,
        'durationMilliseconds': duration.inMilliseconds,
      };
      final sessions = List<Map<String, dynamic>>.from(instance.timeLogSessions)
        ..add(newSession);
      final totalTime = TimerUtil.calculateTotalFromSessions(sessions);
      final now = DateTime.now();
      final updateData = <String, dynamic>{
        'timeLogSessions': sessions,
        'totalTimeLogged': totalTime,
        'accumulatedTime': totalTime,
        'isTimeLogging': false,
        'currentSessionStartTime': null,
        'lastUpdated': now,
      };
      if (instance.templateTrackingType == 'time') {
        updateData['currentValue'] = totalTime;
      }
      if (markComplete) {
        updateData['status'] = 'completed';
        updateData['completedAt'] = now;
      }

      final optimisticData = Map<String, dynamic>.from(instance.snapshotData)
        ..['timeLogSessions'] = sessions
        ..['totalTimeLogged'] = totalTime
        ..['accumulatedTime'] = totalTime
        ..['currentValue'] = instance.templateTrackingType == 'time'
            ? totalTime
            : instance.currentValue
        ..['isTimeLogging'] = false
        ..['currentSessionStartTime'] = null
        ..['lastUpdated'] = now;
      if (markComplete) {
        optimisticData['status'] = 'completed';
        optimisticData['completedAt'] = now;
      }
      var optimisticInstance = ActivityInstanceRecord.getDocumentFromData(
        optimisticData,
        instance.reference,
      );
      final operationId = OptimisticOperationTracker.generateOperationId();
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instance.reference.id,
        operationType: markComplete ? 'complete' : 'progress',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
        optimisticInstance,
        operationId,
      );

      try {
        await activityInstanceRef.update(updateData);
        final updatedInstance =
            await _getInstanceServerFirst(activityInstanceRef);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
      } catch (e) {
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Pause time logging (keeps task pending)
  static Future<void> pauseTimeLogging({
    required DocumentReference activityInstanceRef,
    String? userId,
  }) async {
    await stopTimeLogging(
      activityInstanceRef: activityInstanceRef,
      markComplete: false,
      userId: userId,
    );
  }

  /// Discard current time logging session (cancel session without saving)
  static Future<void> discardTimeLogging({
    required DocumentReference activityInstanceRef,
    String? userId,
  }) async {
    try {
      await activityInstanceRef.update({
        'isTimeLogging': false,
        'isTimerActive': false,
        'currentSessionStartTime': FieldValue.delete(),
        'lastUpdated': DateTime.now(),
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Get current session duration (for displaying running time)
  static Duration getCurrentSessionDuration(ActivityInstanceRecord instance) {
    if (!instance.isTimeLogging || instance.currentSessionStartTime == null) {
      return Duration.zero;
    }
    return DateTime.now().difference(instance.currentSessionStartTime!);
  }

  /// Get aggregate time including current session
  static Duration getAggregateDuration(ActivityInstanceRecord instance) {
    final totalLogged = Duration(milliseconds: instance.totalTimeLogged);
    final currentSession = getCurrentSessionDuration(instance);
    return totalLogged + currentSession;
  }

  /// Get all activity instances with time logs for calendar display
  static Future<List<ActivityInstanceRecord>> getTimeLoggedTasks({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
    try {
      if (startDate != null && endDate != null) {
        final normalizedStartDate =
            DateService.normalizeToStartOfDay(startDate);
        final normalizedEndDate = DateService.normalizeToStartOfDay(endDate);
        if (normalizedStartDate
            .add(const Duration(days: 1))
            .isAtSameMomentAs(normalizedEndDate)) {
          return getTimeLoggedTasksForDate(
              userId: uid, date: normalizedStartDate);
        }
      }
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('totalTimeLogged', isGreaterThan: 0);
      final result = await query.get();
      final tasks = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((task) => task.isActive)
          .toList();
      if (startDate != null || endDate != null) {
        final normalizedStartDate = startDate != null
            ? DateService.normalizeToStartOfDay(startDate)
            : null;
        final normalizedEndDate =
            endDate != null ? DateService.normalizeToStartOfDay(endDate) : null;
        return tasks.where((task) {
          final sessions = task.timeLogSessions;
          return sessions.any((session) {
            final sessionStart = session['startTime'] as DateTime;
            final normalizedSessionStart =
                DateService.normalizeToStartOfDay(sessionStart);
            if (normalizedStartDate != null &&
                normalizedSessionStart.isBefore(normalizedStartDate)) {
              return false;
            }
            if (normalizedEndDate != null &&
                !normalizedSessionStart.isBefore(normalizedEndDate)) {
              return false;
            }
            return true;
          });
        }).toList();
      }
      return tasks;
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getTimeLoggedTasks',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  static Future<List<ActivityInstanceRecord>> getessentialInstances({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
    try {
      Query query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'essential')
          .where('totalTimeLogged', isGreaterThan: 0);
      if (startDate != null && endDate != null) {
        final normalizedStartDate =
            DateService.normalizeToStartOfDay(startDate);
        final normalizedEndDate = DateService.normalizeToStartOfDay(endDate);
        if (normalizedStartDate
            .add(const Duration(days: 1))
            .isAtSameMomentAs(normalizedEndDate)) {
          try {
            final dateQuery = ActivityInstanceRecord.collectionForUser(uid)
                .where('templateCategoryType', isEqualTo: 'essential')
                .where('totalTimeLogged', isGreaterThan: 0)
                .where('belongsToDate', isEqualTo: normalizedStartDate);
            final dateResult = await dateQuery.get();
            final dateInstances = dateResult.docs
                .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
                .where((instance) =>
                    instance.isActive && instance.timeLogSessions.isNotEmpty)
                .toList();
            return dateInstances.where((instance) {
              final sessions = instance.timeLogSessions;
              return sessions.any((session) {
                final sessionStart = session['startTime'] as DateTime;
                final normalizedSessionStart =
                    DateService.normalizeToStartOfDay(sessionStart);
                return normalizedSessionStart
                    .isAtSameMomentAs(normalizedStartDate);
              });
            }).toList();
          } catch (e) {
            logFirestoreIndexError(
              e,
              'Get essential instances by belongsToDate (templateCategoryType + totalTimeLogged + belongsToDate)',
              'activity_instances',
            );
            return [];
          }
        }
      }
      final result = await query.get();
      final instances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((instance) =>
              instance.isActive && instance.timeLogSessions.isNotEmpty)
          .toList();
      if (startDate != null || endDate != null) {
        final normalizedStartDate = startDate != null
            ? DateService.normalizeToStartOfDay(startDate)
            : null;
        final normalizedEndDate =
            endDate != null ? DateService.normalizeToStartOfDay(endDate) : null;
        return instances.where((instance) {
          final sessions = instance.timeLogSessions;
          return sessions.any((session) {
            final sessionStart = session['startTime'] as DateTime;
            final normalizedSessionStart =
                DateService.normalizeToStartOfDay(sessionStart);
            if (normalizedStartDate != null &&
                normalizedSessionStart.isBefore(normalizedStartDate)) {
              return false;
            }
            if (normalizedEndDate != null &&
                !normalizedSessionStart.isBefore(normalizedEndDate)) {
              return false;
            }
            return true;
          });
        }).toList();
      }
      return instances;
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getessentialInstances',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  static Future<List<ActivityInstanceRecord>> getTodayEssentialInstances({
    required String userId,
    required DateTime dayStart,
    bool includePending = true,
    bool includeLogged = true,
  }) async {
    if (!includePending && !includeLogged) {
      return [];
    }

    final normalizedDayStart = DateService.normalizeToStartOfDay(dayStart);
    final dayEnd = normalizedDayStart.add(const Duration(days: 1));
    final mergedById = <String, ActivityInstanceRecord>{};

    bool isSameDay(DateTime? value) {
      if (value == null) return false;
      final normalized = DateService.normalizeToStartOfDay(value);
      return normalized.isAtSameMomentAs(normalizedDayStart);
    }

    bool hasSessionOnDay(ActivityInstanceRecord instance) {
      if (instance.timeLogSessions.isEmpty) return false;
      for (final session in instance.timeLogSessions) {
        final start = session['startTime'] as DateTime?;
        if (start == null) continue;
        if (!start.isBefore(normalizedDayStart) && start.isBefore(dayEnd)) {
          return true;
        }
      }
      return false;
    }

    void mergeInstances(Iterable<ActivityInstanceRecord> instances) {
      for (final instance in instances) {
        if (!instance.isActive) continue;
        mergedById[instance.reference.id] = instance;
      }
    }

    Future<void> collectFromQuery({
      required Future<dynamic> Function() runQuery,
      required String queryDescription,
      bool filterByDay = false,
    }) async {
      try {
        final result = await runQuery();
        final instances = result.docs
            .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
            .where((instance) {
          if (!instance.isActive) return false;
          if (instance.templateCategoryType != 'essential') return false;
          if (!filterByDay) return true;
          final belongsToday = isSameDay(instance.belongsToDate);
          final completedToday = isSameDay(instance.completedAt);
          final sessionToday = hasSessionOnDay(instance);
          return belongsToday || completedToday || sessionToday;
        });
        mergeInstances(instances);
      } catch (e) {
        logFirestoreIndexError(
          e,
          queryDescription,
          'activity_instances',
        );
      }
    }

    if (includePending) {
      await collectFromQuery(
        runQuery: () => ActivityInstanceRecord.collectionForUser(userId)
            .where('templateCategoryType', isEqualTo: 'essential')
            .where('belongsToDate', isEqualTo: normalizedDayStart)
            .limit(500)
            .get(),
        queryDescription:
            'Get today essential instances by belongsToDate (essential + belongsToDate)',
      );
    }

    if (includeLogged) {
      final sessionLogged = await getessentialInstances(
        userId: userId,
        startDate: normalizedDayStart,
        endDate: dayEnd,
      );
      mergeInstances(sessionLogged);

      await collectFromQuery(
        runQuery: () => ActivityInstanceRecord.collectionForUser(userId)
            .where('templateCategoryType', isEqualTo: 'essential')
            .where('totalTimeLogged', isGreaterThan: 0)
            .where('completedAt', isGreaterThanOrEqualTo: normalizedDayStart)
            .where('completedAt', isLessThan: dayEnd)
            .limit(300)
            .get(),
        queryDescription:
            'Get today essential logged by completedAt range (essential + totalTimeLogged + completedAt)',
        filterByDay: true,
      );
    }

    final instances = mergedById.values.where((instance) {
      final pendingShape = isSameDay(instance.belongsToDate);
      final loggedShape = hasSessionOnDay(instance) ||
          (instance.totalTimeLogged > 0 && isSameDay(instance.completedAt));

      if (includePending && includeLogged) {
        return pendingShape || loggedShape;
      }
      if (includePending) {
        return pendingShape;
      }
      return loggedShape;
    }).toList();

    instances.sort((a, b) {
      if (a.status == 'pending' && b.status != 'pending') return -1;
      if (a.status != 'pending' && b.status == 'pending') return 1;
      final aUpdated = a.lastUpdated ?? DateTime(1970);
      final bUpdated = b.lastUpdated ?? DateTime(1970);
      return bUpdated.compareTo(aUpdated);
    });

    return instances;
  }

  static Future<List<ActivityInstanceRecord>> getTimeLoggedTasksForDate({
    String? userId,
    required DateTime date,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
    try {
      final normalizedDate = DateService.normalizeToStartOfDay(date);
      final mergedById = <String, ActivityInstanceRecord>{};

      void mergeInstances(Iterable<ActivityInstanceRecord> instances) {
        for (final instance in instances) {
          mergedById[instance.reference.id] = instance;
        }
      }

      Future<void> collectFromQuery({
        required Future<dynamic> Function() runQuery,
        required String queryDescription,
        bool countAsFallback = false,
        String? fallbackReason,
        String? queryShape,
      }) async {
        try {
          final result = await runQuery();
          final docs = result.docs;
          final instances = docs
              .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
              .where(
                (instance) =>
                    instance.isActive && instance.timeLogSessions.isNotEmpty,
              );
          mergeInstances(instances);
          if (countAsFallback) {
            FallbackReadTelemetry.logQueryFallback(
              FallbackReadEvent(
                scope:
                    'task_instance_time_logging_service.getTimeLoggedTasksForDate',
                reason: fallbackReason ?? 'fallback_query_executed',
                queryShape: queryShape ?? queryDescription,
                userCountSampled: 1,
                fallbackDocsReadEstimate: docs.length,
              ),
            );
          }
        } catch (e) {
          logFirestoreIndexError(
            e,
            queryDescription,
            'activity_instances',
          );
          if (countAsFallback) {
            FallbackReadTelemetry.logQueryFallback(
              FallbackReadEvent(
                scope:
                    'task_instance_time_logging_service.getTimeLoggedTasksForDate',
                reason: '${fallbackReason ?? 'fallback_query'}_failed',
                queryShape: queryShape ?? queryDescription,
                userCountSampled: 1,
                fallbackDocsReadEstimate: 0,
              ),
            );
          }
        }
      }

      await collectFromQuery(
        runQuery: () => ActivityInstanceRecord.collectionForUser(uid)
            .where('totalTimeLogged', isGreaterThan: 0)
            .where('belongsToDate', isEqualTo: normalizedDate)
            .limit(500)
            .get(),
        queryDescription:
            'Get time logged tasks by belongsToDate (totalTimeLogged + belongsToDate)',
      );

      // Only run additional fallbacks when the primary date-scoped query returns nothing.
      if (mergedById.isEmpty) {
        final nextDate = normalizedDate.add(const Duration(days: 1));

        await collectFromQuery(
          runQuery: () => ActivityInstanceRecord.collectionForUser(uid)
              .where('totalTimeLogged', isGreaterThan: 0)
              .where('completedAt', isGreaterThanOrEqualTo: normalizedDate)
              .where('completedAt', isLessThan: nextDate)
              .limit(300)
              .get(),
          queryDescription:
              'Get time logged tasks fallback by completedAt range',
          countAsFallback: true,
          fallbackReason: 'completed_at_range_fallback',
          queryShape:
              'totalTimeLogged>0,completedAt in [date,nextDate),limit=300',
        );

        await collectFromQuery(
          runQuery: () => ActivityInstanceRecord.collectionForUser(uid)
              .where('totalTimeLogged', isGreaterThan: 0)
              .where('dueDate', isEqualTo: normalizedDate)
              .limit(300)
              .get(),
          queryDescription:
              'Get time logged tasks fallback by dueDate equality',
          countAsFallback: true,
          fallbackReason: 'due_date_equality_fallback',
          queryShape: 'totalTimeLogged>0,dueDate=date,limit=300',
        );
      }

      // Final fallback: bounded broad scan instead of unbounded historical scan.
      if (mergedById.isEmpty) {
        await collectFromQuery(
          runQuery: () => ActivityInstanceRecord.collectionForUser(uid)
              .where('totalTimeLogged', isGreaterThan: 0)
              .limit(250)
              .get(),
          queryDescription:
              'Get time logged tasks final fallback (bounded totalTimeLogged scan)',
          countAsFallback: true,
          fallbackReason: 'bounded_total_time_logged_scan_fallback',
          queryShape: 'totalTimeLogged>0,limit=250',
        );
      }

      return mergedById.values.where((instance) {
        final sessions = instance.timeLogSessions;
        return sessions.any((session) {
          final sessionStart = session['startTime'] as DateTime;
          final normalizedSessionStart =
              DateService.normalizeToStartOfDay(sessionStart);
          return normalizedSessionStart.isAtSameMomentAs(normalizedDate);
        });
      }).toList();
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getTimeLoggedTasksForDate',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  static Future<void> logManualTimeEntry({
    required String taskName,
    required DateTime startTime,
    required DateTime endTime,
    required String activityType, // 'task', 'habit', or 'essential'
    String? categoryId,
    String? categoryName,
    String? templateId, // Optional: if selecting an existing activity
    String? userId,
    bool markComplete = true,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();

    if (startTime.isAfter(endTime)) {
      throw Exception("Start time cannot be after end time.");
    }

    final duration = endTime.difference(startTime);
    final totalTime = duration.inMilliseconds;
    final newSession = <String, dynamic>{
      'startTime': startTime,
      'endTime': endTime,
      'durationMilliseconds': totalTime,
    };
    try {
      if (templateId != null) {
        DocumentReference? targetInstanceRef;
        dynamic existingInstance;
        if (activityType == 'habit') {
          try {
            final targetDate =
                DateTime(startTime.year, startTime.month, startTime.day);
            final habitInstances =
                await ActivityInstanceService.getHabitInstancesForDate(
                    targetDate: targetDate, userId: uid);
            ActivityInstanceRecord? habitMatch;
            for (final instance in habitInstances) {
              if (instance.templateId == templateId) {
                habitMatch = instance;
                break; // Use the first matching instance (should only be one per template)
              }
            }
            if (habitMatch != null) {
              targetInstanceRef = habitMatch.reference;
              existingInstance = habitMatch;
            }
          } catch (e) {
            throw Exception(
                'Failed to find habit instance for template $templateId. Please ensure the habit is active and appears in your habits list.');
          }
        } else if (activityType == 'task') {
          final tasks =
              await TaskInstanceTaskService.getTodaysTaskInstances(userId: uid);
          var match = tasks.firstWhereOrNull((t) => t.templateId == templateId);
          if (match != null) {
            targetInstanceRef = match.reference;
            existingInstance = match;
          }
          if (targetInstanceRef == null) {
            try {
              final allInstancesQuery =
                  ActivityInstanceRecord.collectionForUser(uid)
                      .where('templateId', isEqualTo: templateId)
                      .where('isActive', isEqualTo: true)
                      .orderBy('lastUpdated', descending: true)
                      .limit(1);
              final allInstancesResult =
                  await allInstancesQuery.get().catchError((e) {
                logFirestoreIndexError(
                  e,
                  'Find instance by templateId (isActive + templateId + lastUpdated)',
                  'activity_instances',
                );
                throw e;
              });
              if (allInstancesResult.docs.isNotEmpty) {
                final instanceDoc = allInstancesResult.docs.first;
                final instance =
                    ActivityInstanceRecord.fromSnapshot(instanceDoc);
                final instanceDate = instance.dueDate ?? instance.createdTime;
                if (instanceDate != null) {
                  final startDate =
                      DateTime(startTime.year, startTime.month, startTime.day);
                  final instanceDateOnly = DateTime(
                      instanceDate.year, instanceDate.month, instanceDate.day);
                  if (instanceDateOnly.isAtSameMomentAs(startDate) ||
                      instance.dueDate == null) {
                    targetInstanceRef = instance.reference;
                    existingInstance = instance;
                  }
                } else {
                  targetInstanceRef = instance.reference;
                  existingInstance = instance;
                }
              }
            } catch (e) {
              //
            }
          }
        }
        if (targetInstanceRef != null && existingInstance != null) {
          final currentSessions =
              List<Map<String, dynamic>>.from(existingInstance.timeLogSessions);
          currentSessions.add(newSession);
          final currentTotalLogged = existingInstance.totalTimeLogged;
          final newTotalLogged = currentTotalLogged + totalTime;
          dynamic newCurrentValue;
          if (existingInstance.templateTrackingType == 'time') {
            newCurrentValue = newTotalLogged;
          } else {
            newCurrentValue = existingInstance.currentValue;
          }
          final optimisticInstance =
              InstanceEvents.createOptimisticProgressInstance(
            existingInstance,
            accumulatedTime: newTotalLogged,
            currentValue: newCurrentValue,
            timeLogSessions: currentSessions,
            totalTimeLogged: newTotalLogged,
          );
          final operationId = OptimisticOperationTracker.generateOperationId();
          OptimisticOperationTracker.trackOperation(
            operationId,
            instanceId: existingInstance.reference.id,
            operationType: 'progress',
            optimisticInstance: optimisticInstance,
            originalInstance: existingInstance,
          );
          InstanceEvents.broadcastInstanceUpdatedOptimistic(
              optimisticInstance, operationId);
          final updateData = <String, dynamic>{
            'timeLogSessions': currentSessions,
            'totalTimeLogged': newTotalLogged,
            'accumulatedTime': newTotalLogged,
            'currentValue': newCurrentValue,
            'lastUpdated': DateTime.now(),
          };

          if (activityType.toLowerCase() == 'essential') {
            updateData['templateCategoryType'] = 'essential';
            updateData['templateCategoryName'] = 'Essentials';
          }
          try {
            await targetInstanceRef.update(updateData);
            final updatedInstance =
                await _getInstanceServerFirst(targetInstanceRef);
            OptimisticOperationTracker.reconcileOperation(
                operationId, updatedInstance);

            // Handle completion after saving the time so the completion
            // logic sees the updated totalTimeLogged
            bool shouldComplete = markComplete;
            if (!shouldComplete &&
                existingInstance.status != 'completed' &&
                existingInstance.templateTrackingType == 'time' &&
                existingInstance.templateTarget != null) {
              final target = existingInstance.templateTarget;
              if (target is num && target > 0) {
                final targetMs = (target.toInt()) * 60000;
                if (newTotalLogged >= targetMs) {
                  shouldComplete = true;
                }
              }
            }

            if (shouldComplete) {
              await TaskInstanceTaskService.completeTaskInstance(
                instanceId: targetInstanceRef.id,
                finalValue: newCurrentValue ?? newTotalLogged,
                finalAccumulatedTime: newTotalLogged,
                userId: uid,
              );
            }
            return; // Done
          } catch (e) {
            OptimisticOperationTracker.rollbackOperation(operationId);
            rethrow; // Re-throw to surface the error
          }
        }
        if (activityType == 'habit') {
          throw Exception(
              'Habit instance not found for the selected date. Please ensure the habit is active and appears in your habits list. New habit instances cannot be created from the time log.');
        }
        final templateRef =
            ActivityRecord.collectionForUser(uid).doc(templateId);
        final templateDoc = await templateRef.get();
        if (templateDoc.exists) {
          final template = ActivityRecord.fromSnapshot(templateDoc);
          final instanceDueDate = template.dueDate == null ? null : startTime;
          final instanceRef =
              await ActivityInstanceService.createActivityInstance(
                  templateId: templateId,
                  dueDate:
                      instanceDueDate, // Preserve no due date if template doesn't have one
                  template: template,
                  userId: uid);
          final createdInstance = await _getInstanceServerFirst(instanceRef);
          final sessions = [newSession];
          final newCurrentValue =
              template.trackingType == 'time' ? totalTime : null;
          final optimisticInstance =
              InstanceEvents.createOptimisticProgressInstance(
            createdInstance,
            accumulatedTime: totalTime,
            currentValue: newCurrentValue ?? createdInstance.currentValue,
            timeLogSessions: sessions,
            totalTimeLogged: totalTime,
          );
          ActivityInstanceRecord finalOptimisticInstance;
          if (markComplete) {
            final optimisticData =
                Map<String, dynamic>.from(optimisticInstance.snapshotData);
            optimisticData['status'] = 'completed';
            optimisticData['completedAt'] = endTime;
            if (template.trackingType == 'binary') {
              optimisticData['currentValue'] = 1;
            }
            optimisticData['_optimistic'] = true;
            finalOptimisticInstance =
                ActivityInstanceRecord.getDocumentFromData(
              optimisticData,
              optimisticInstance.reference,
            );
          } else {
            finalOptimisticInstance = optimisticInstance;
          }
          final operationId = OptimisticOperationTracker.generateOperationId();
          OptimisticOperationTracker.trackOperation(
            operationId,
            instanceId: createdInstance.reference.id,
            operationType: 'progress',
            optimisticInstance: finalOptimisticInstance,
            originalInstance: createdInstance,
          );
          InstanceEvents.broadcastInstanceUpdatedOptimistic(
              finalOptimisticInstance, operationId);
          final updateData = <String, dynamic>{
            'timeLogSessions': sessions,
            'totalTimeLogged': totalTime,
            'accumulatedTime': totalTime,
            'lastUpdated': DateTime.now(),
          };
          if (newCurrentValue != null) {
            updateData['currentValue'] = newCurrentValue;
          }

          try {
            await instanceRef.update(updateData);
            final updatedInstance = await _getInstanceServerFirst(instanceRef);
            OptimisticOperationTracker.reconcileOperation(
                operationId, updatedInstance);

            bool shouldComplete = markComplete;
            if (!shouldComplete &&
                activityType == 'task' &&
                template.trackingType == 'time' &&
                template.target != null) {
              final target = template.target;
              if (target is num && target > 0) {
                final targetMs = (target.toInt()) * 60000;
                if (totalTime >= targetMs) {
                  shouldComplete = true;
                }
              }
            }

            if (shouldComplete) {
              await TaskInstanceTaskService.completeTaskInstance(
                  instanceId: instanceRef.id,
                  finalValue: newCurrentValue ?? totalTime,
                  finalAccumulatedTime: totalTime,
                  userId: uid);
            }
          } catch (e) {
            OptimisticOperationTracker.rollbackOperation(operationId);
            rethrow;
          }
          return;
        }
      }

      final taskInstanceRef =
          await TaskInstanceTimerTaskService.createTimerTaskInstance(
        userId: uid,
        startTimer: false,
        showInFloatingTimer: false,
      );
      final now = DateTime.now();
      final currentInstance = await _getInstanceServerFirst(taskInstanceRef);
      final isessential = activityType.toLowerCase() == 'essential';
      final timeLogSessions = [newSession];
      if (isessential) {
        final templates =
            await essentialService.getessentialTemplates(userId: uid);
        ActivityRecord? matchingTemplate;
        try {
          matchingTemplate = templates.firstWhere(
            (t) => t.name.toLowerCase() == taskName.toLowerCase(),
          );
        } catch (e) {
          matchingTemplate = null;
        }

        DocumentReference templateRef;
        if (matchingTemplate == null) {
          templateRef = await essentialService.createessentialTemplate(
            name: taskName,
            trackingType: 'binary',
            userId: uid,
          );
        } else {
          templateRef = matchingTemplate.reference;
        }
        final optimisticData =
            Map<String, dynamic>.from(currentInstance.snapshotData);
        optimisticData['status'] = markComplete ? 'completed' : 'pending';
        optimisticData['completedAt'] = markComplete ? endTime : null;
        optimisticData['isTimerActive'] = false;
        optimisticData['timeLogSessions'] = timeLogSessions;
        optimisticData['totalTimeLogged'] = totalTime;
        optimisticData['accumulatedTime'] = totalTime;
        optimisticData['currentValue'] = totalTime;
        optimisticData['templateId'] = templateRef.id;
        optimisticData['templateName'] = taskName;
        optimisticData['templateCategoryType'] = 'essential';
        optimisticData['templateCategoryName'] = 'Essentials';
        optimisticData['templateTrackingType'] =
            matchingTemplate?.trackingType ?? 'binary';
        optimisticData['currentSessionStartTime'] = null;
        optimisticData['lastUpdated'] = now;
        optimisticData['_optimistic'] = true;
        final optimisticInstance = ActivityInstanceRecord.getDocumentFromData(
          optimisticData,
          currentInstance.reference,
        );
        final operationId = OptimisticOperationTracker.generateOperationId();
        OptimisticOperationTracker.trackOperation(
          operationId,
          instanceId: currentInstance.reference.id,
          operationType: 'progress',
          optimisticInstance: optimisticInstance,
          originalInstance: currentInstance,
        );
        InstanceEvents.broadcastInstanceUpdatedOptimistic(
            optimisticInstance, operationId);
        final updateData = <String, dynamic>{
          'status': markComplete ? 'completed' : 'pending',
          'completedAt': markComplete ? endTime : FieldValue.delete(),
          'isTimerActive': false,
          'timeLogSessions': timeLogSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': totalTime,
          'templateId': templateRef.id,
          'templateName': taskName,
          'templateCategoryType': 'essential',
          'templateCategoryName': 'Essentials',
          'templateTrackingType': matchingTemplate?.trackingType ?? 'binary',
          'currentSessionStartTime': null,
          'lastUpdated': now,
        };

        try {
          await taskInstanceRef.update(updateData);
          final updatedInstance =
              await _getInstanceServerFirst(taskInstanceRef);
          OptimisticOperationTracker.reconcileOperation(
              operationId, updatedInstance);
        } catch (e) {
          OptimisticOperationTracker.rollbackOperation(operationId);
          rethrow;
        }
      } else {
        final templateRef = ActivityRecord.collectionForUser(uid)
            .doc(currentInstance.templateId);
        final optimisticData =
            Map<String, dynamic>.from(currentInstance.snapshotData);
        optimisticData['status'] = 'pending';
        optimisticData['isTimerActive'] = false;
        optimisticData['timeLogSessions'] = timeLogSessions;
        optimisticData['totalTimeLogged'] = totalTime;
        optimisticData['accumulatedTime'] = totalTime;
        optimisticData['currentValue'] = 0;
        // Keep target as binary completion target; ON/OFF time-aware scoring is
        // resolved at calculation time from logged duration + estimates.
        optimisticData['templateTarget'] = 1;
        optimisticData['templateName'] = taskName;
        optimisticData['templateCategoryType'] = 'task';
        optimisticData['templateTrackingType'] =
            'binary'; // Force binary for one-offs per previous request
        optimisticData['lastUpdated'] = now;
        optimisticData['currentSessionStartTime'] = null;
        if (categoryId != null)
          optimisticData['templateCategoryId'] = categoryId;
        if (categoryName != null) {
          optimisticData['templateCategoryName'] = categoryName;
        }
        optimisticData['_optimistic'] = true;

        // Add pending optimism logic
        final optimisticInstance = ActivityInstanceRecord.getDocumentFromData(
          optimisticData,
          currentInstance.reference,
        );
        final operationId = OptimisticOperationTracker.generateOperationId();
        OptimisticOperationTracker.trackOperation(
          operationId,
          instanceId: currentInstance.reference.id,
          operationType: 'progress',
          optimisticInstance: optimisticInstance,
          originalInstance: currentInstance,
        );
        InstanceEvents.broadcastInstanceUpdatedOptimistic(
            optimisticInstance, operationId);

        final updateData = <String, dynamic>{
          'status': 'pending',
          'isTimerActive': false,
          'timeLogSessions': timeLogSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': 0,
          // Keep target as binary completion target; ON/OFF time-aware scoring is
          // resolved at calculation time from logged duration + estimates.
          'templateTarget': 1,
          'templateName': taskName,
          'templateCategoryType': 'task',
          'templateTrackingType': 'binary',
          'lastUpdated': now,
          'currentSessionStartTime': null,
        };

        if (categoryId != null) updateData['templateCategoryId'] = categoryId;
        if (categoryName != null) {
          updateData['templateCategoryName'] = categoryName;
        }

        try {
          await taskInstanceRef.update(updateData);
          final updatedInstance =
              await _getInstanceServerFirst(taskInstanceRef);
          OptimisticOperationTracker.reconcileOperation(
              operationId, updatedInstance);

          if (markComplete) {
            await TaskInstanceTaskService.completeTaskInstance(
                instanceId: taskInstanceRef.id,
                finalValue: totalTime,
                finalAccumulatedTime: totalTime,
                userId: uid);
          }
        } catch (e) {
          OptimisticOperationTracker.rollbackOperation(operationId);
          rethrow;
        }

        final templateUpdateData = <String, dynamic>{
          'name': taskName,
          'lastUpdated': now,
          'isActive': markComplete ? false : true,
          'trackingType': 'binary',
        };
        if (categoryId != null) templateUpdateData['categoryId'] = categoryId;
        if (categoryName != null) {
          templateUpdateData['categoryName'] = categoryName;
        }
        await templateRef.update(templateUpdateData);
      }
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'logManualTimeEntry',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static int _resolveSessionIndex({
    required List<Map<String, dynamic>> sessions,
    required int requestedIndex,
    DateTime? sessionStartTime,
    DateTime? sessionEndTime,
  }) {
    if (sessionStartTime != null) {
      final exactIndex = sessions.indexWhere((session) {
        final start = session['startTime'] as DateTime?;
        final end = session['endTime'] as DateTime?;
        if (start == null || end == null) {
          return false;
        }
        if (!start.isAtSameMomentAs(sessionStartTime)) {
          return false;
        }
        if (sessionEndTime == null) {
          return true;
        }
        return end.isAtSameMomentAs(sessionEndTime);
      });
      if (exactIndex >= 0) {
        return exactIndex;
      }

      final startOnlyIndex = sessions.indexWhere((session) {
        final start = session['startTime'] as DateTime?;
        if (start == null) {
          return false;
        }
        return start.isAtSameMomentAs(sessionStartTime);
      });
      if (startOnlyIndex >= 0) {
        return startOnlyIndex;
      }
    }

    if (requestedIndex >= 0 && requestedIndex < sessions.length) {
      return requestedIndex;
    }

    return -1;
  }

  /// Update a specific time log session
  static Future<void> updateTimeLogSession({
    required String instanceId,
    required int sessionIndex,
    required DateTime startTime,
    required DateTime endTime,
    DateTime? originalSessionStartTime,
    DateTime? originalSessionEndTime,
    String? userId,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instance = await _getInstanceServerFirst(instanceRef);

      final sessions =
          List<Map<String, dynamic>>.from(instance.timeLogSessions);
      final resolvedSessionIndex = _resolveSessionIndex(
        sessions: sessions,
        requestedIndex: sessionIndex,
        sessionStartTime: originalSessionStartTime,
        sessionEndTime: originalSessionEndTime,
      );
      if (resolvedSessionIndex < 0 || resolvedSessionIndex >= sessions.length) {
        throw Exception('Session index out of range');
      }
      if (startTime.isAfter(endTime)) {
        throw Exception('Start time cannot be after end time');
      }
      final duration = endTime.difference(startTime);
      final durationMs = duration.inMilliseconds;
      sessions[resolvedSessionIndex] = {
        'startTime': startTime,
        'endTime': endTime,
        'durationMilliseconds': durationMs,
      };
      final totalTime = TimerUtil.calculateTotalFromSessions(sessions);
      dynamic newCurrentValue;
      if (instance.templateTrackingType == 'time') {
        newCurrentValue = totalTime;
      } else {
        newCurrentValue = instance.currentValue;
      }
      final optimisticInstance =
          InstanceEvents.createOptimisticProgressInstance(
        instance,
        accumulatedTime: totalTime,
        currentValue: newCurrentValue,
        timeLogSessions: sessions,
        totalTimeLogged: totalTime,
      );
      final operationId = OptimisticOperationTracker.generateOperationId();
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'progress',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);
      try {
        await instanceRef.update({
          'timeLogSessions': sessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue':
              newCurrentValue, // Only update for time tracking, preserve for quantitative/binary
          'lastUpdated': DateTime.now(),
        });
        final updatedInstance = await _getInstanceServerFirst(instanceRef);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
        if (instance.templateTrackingType == 'time' &&
            instance.templateTarget != null) {
          final target = instance.templateTarget;
          if (target is num && target > 0) {
            final targetMs =
                (target.toInt()) * 60000; // Convert minutes to milliseconds
            if (instance.status != 'completed' && totalTime >= targetMs) {
              await TaskInstanceTaskService.completeTaskInstance(
                instanceId: instanceId,
                finalValue: totalTime,
                finalAccumulatedTime: totalTime,
                userId: uid,
              );
            } else if (instance.status == 'completed' && totalTime < targetMs) {
              await ActivityInstanceService.uncompleteInstance(
                instanceId: instanceId,
                userId: uid,
              );
            }
          }
        }
      } catch (e) {
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<bool> deleteTimeLogSession({
    required String instanceId,
    required int sessionIndex,
    DateTime? sessionStartTime,
    DateTime? sessionEndTime,
    String? userId,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instance = await _getInstanceServerFirst(instanceRef);
      final sessions =
          List<Map<String, dynamic>>.from(instance.timeLogSessions);
      final resolvedSessionIndex = _resolveSessionIndex(
        sessions: sessions,
        requestedIndex: sessionIndex,
        sessionStartTime: sessionStartTime,
        sessionEndTime: sessionEndTime,
      );
      if (resolvedSessionIndex < 0 || resolvedSessionIndex >= sessions.length) {
        throw Exception('Session index out of range');
      }
      sessions.removeAt(resolvedSessionIndex);
      final totalTime = TimerUtil.calculateTotalFromSessions(sessions);
      dynamic newCurrentValue;
      if (instance.templateTrackingType == 'quantitative') {
        final currentQty = (instance.currentValue is num)
            ? (instance.currentValue as num).toDouble()
            : 0.0;
        newCurrentValue = (currentQty - 1).clamp(0.0, double.infinity);
      } else {
        newCurrentValue = totalTime;
      }
      final optimisticInstance =
          InstanceEvents.createOptimisticProgressInstance(
        instance,
        accumulatedTime: totalTime,
        currentValue: newCurrentValue,
        timeLogSessions: sessions,
        totalTimeLogged: totalTime,
      );
      final operationId = OptimisticOperationTracker.generateOperationId();
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instanceId,
        operationType: 'progress',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
          optimisticInstance, operationId);
      try {
        await instanceRef.update({
          'timeLogSessions': sessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': newCurrentValue,
          'lastUpdated': DateTime.now(),
        });
        final updatedInstance = await _getInstanceServerFirst(instanceRef);
        OptimisticOperationTracker.reconcileOperation(
            operationId, updatedInstance);
        bool wasUncompleted = false;
        if (instance.status == 'completed' &&
            instance.templateTrackingType == 'time' &&
            instance.templateTarget != null) {
          final target = instance.templateTarget;
          if (target is num && target > 0) {
            final targetMs =
                (target.toInt()) * 60000; // Convert minutes to milliseconds
            if (totalTime < targetMs) {
              await ActivityInstanceService.uncompleteInstance(
                instanceId: instanceId,
                userId: uid,
              );
              wasUncompleted = true;
            }
          }
        }
        if (instance.status == 'completed' &&
            instance.templateTrackingType == 'quantitative' &&
            instance.templateTarget != null) {
          final target = instance.templateTarget;
          if (target is num && target > 0) {
            final currentQty =
                (newCurrentValue is num) ? newCurrentValue.toDouble() : 0.0;
            if (currentQty < target.toDouble()) {
              await ActivityInstanceService.uncompleteInstance(
                instanceId: instanceId,
                userId: uid,
              );
              wasUncompleted = true;
            }
          }
        }
        return wasUncompleted;
      } catch (e) {
        OptimisticOperationTracker.rollbackOperation(operationId);
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }
}
