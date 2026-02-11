import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';
import 'package:habit_tracker/features/Testing/timer_task_template_service.dart';
import 'package:habit_tracker/features/Essential/essential_data_service.dart';
import 'package:habit_tracker/services/Activtity/timer_activities_util.dart';
import 'task_instance_helper_service.dart';

/// Service for timer task operations
class TaskInstanceTimerTaskService {
  static Future<DocumentReference> createTimerTaskInstance({
    String? categoryId,
    String? categoryName,
    String? userId,
    bool startTimer = true,
    bool showInFloatingTimer = true,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
    try {
      // Create a new timer task template for this session
      final templateData =
          await TimerTaskTemplateService.createTimerTaskTemplate();
      final template = templateData['template'] as ActivityRecord;
      final templateRef = templateData['templateRef'] as DocumentReference;
      // Use provided category or default to Inbox
      String finalCategoryId = categoryId ?? template.categoryId;
      String finalCategoryName = categoryName ?? template.categoryName;
      final now = DateTime.now();
      final instanceData = createActivityInstanceRecordData(
        templateId: templateRef.id,
        status: 'pending',
        isTimerActive: startTimer,
        timerStartTime: startTimer ? now : null,
        createdTime: now,
        lastUpdated: now,
        isActive: true,
        // Cache template data for quick access
        templateName: template.name,
        templateCategoryId: finalCategoryId,
        templateCategoryName: finalCategoryName,
        templateCategoryType:
            'task', // CRITICAL: Required for task page filtering
        templatePriority: template.priority,
        templateTrackingType: 'binary', // Timer tasks are binary by default
        templateTarget: template.target,
        templateUnit: template.unit,
        templateDescription: template.description,
        templateTimeEstimateMinutes: template.timeEstimateMinutes,
        templateShowInFloatingTimer:
            showInFloatingTimer, // allow caller to suppress floating timer linkage
        // Session tracking fields
        currentSessionStartTime: startTimer ? now : null,
        isTimeLogging: startTimer,
      );
      return await ActivityInstanceRecord.collectionForUser(uid)
          .add(instanceData);
    } catch (e) {
      rethrow;
    }
  }

  /// Update timer task instance when timer is stopped (completed)
  static Future<void> updateTimerTaskOnStop({
    required DocumentReference taskInstanceRef,
    required Duration duration,
    required String taskName,
    String? categoryId,
    String? categoryName,
    String? activityType, // 'task' or 'essential'
    String? userId,
  }) async {
    try {
      final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
      final isessential = activityType == 'essential';

      // Get current instance to check for existing sessions
      final currentInstance =
          await ActivityInstanceRecord.getDocumentOnce(taskInstanceRef);
      // Create new session
      final newSession = {
        'startTime': currentInstance.currentSessionStartTime ??
            DateTime.now().subtract(duration),
        'endTime': DateTime.now(),
        'durationMilliseconds': duration.inMilliseconds,
      };
      // Get existing sessions and add new one
      final existingSessions =
          List<Map<String, dynamic>>.from(currentInstance.timeLogSessions);
      existingSessions.add(newSession);
      // Calculate total cumulative time
      final totalTime = TimerUtil.calculateTotalFromSessions(existingSessions);

      // Handle essential vs productive differently
      if (isessential) {
        // For essential: find or create template, then update instance
        final templates = await essentialService.getessentialTemplates(
          userId: uid,
        );
        ActivityRecord? matchingTemplate;
        for (final template in templates) {
          if (template.name.toLowerCase() == taskName.toLowerCase()) {
            matchingTemplate = template;
            break;
          }
        }

        // Create template if it doesn't exist
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

        // Update instance with essential data
        final updateData = <String, dynamic>{
          'status': 'completed',
          'completedAt': DateTime.now(),
          'isTimerActive': false,
          'timeLogSessions': existingSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue':
              matchingTemplate?.trackingType == 'time' ? totalTime : 1,
          'templateId': templateRef.id,
          'templateName': taskName,
          'templateCategoryType': 'essential',
          'templateCategoryName': 'essential',
          'templateTrackingType': matchingTemplate?.trackingType ?? 'binary',
          'currentSessionStartTime': null,
          'lastUpdated': DateTime.now(),
        };
        await taskInstanceRef.update(updateData);

        // Delete the old timer task template (cleanup)
        try {
          final oldTemplateRef = ActivityRecord.collectionForUser(uid)
              .doc(currentInstance.templateId);
          await oldTemplateRef.delete();
        } catch (e) {
          // Best effort cleanup, don't fail if it doesn't exist
        }
      } else {
        // For productive tasks: existing logic
        final updateData = <String, dynamic>{
          'status': 'completed',
          'completedAt': DateTime.now(),
          'isTimerActive': false,
          'timeLogSessions': existingSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': 1, // Productive timer tasks are binary (1 = complete)
          'templateTarget':
              totalTime / 60000.0, // Convert milliseconds to minutes
          'templateName': taskName,
          'templateCategoryType': 'task', // Ensure it's marked as task
          'currentSessionStartTime': null,
          'lastUpdated': DateTime.now(),
        };
        // Update category if provided
        if (categoryId != null) {
          updateData['templateCategoryId'] = categoryId;
        }
        if (categoryName != null) {
          updateData['templateCategoryName'] = categoryName;
        }
        await taskInstanceRef.update(updateData);

        // Update the template name as well
        final templateRef = ActivityRecord.collectionForUser(uid)
            .doc(currentInstance.templateId);
        final templateUpdateData = <String, dynamic>{
          'name': taskName,
          'lastUpdated': DateTime.now(),
        };

        // Update template category if provided
        if (categoryId != null) {
          templateUpdateData['categoryId'] = categoryId;
        }
        if (categoryName != null) {
          templateUpdateData['categoryName'] = categoryName;
        }

        await templateRef.update(templateUpdateData);

        // Mark template as inactive - timer tasks are one-time use only
        // Keep template for editing purposes but prevent it from appearing in task lists
        await templateRef.update({'isActive': false});
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Update timer task instance when timer is paused (remains pending)
  static Future<void> updateTimerTaskOnPause({
    required DocumentReference taskInstanceRef,
    required Duration duration,
    required String taskName,
    String? categoryId,
    String? categoryName,
    String? activityType, // 'task' or 'essential'
    String? userId,
  }) async {
    try {
      final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
      final isessential = activityType == 'essential';

      // Get current instance to check for existing sessions
      final currentInstance =
          await ActivityInstanceRecord.getDocumentOnce(taskInstanceRef);
      // Create new session
      final newSession = {
        'startTime': currentInstance.currentSessionStartTime ??
            DateTime.now().subtract(duration),
        'endTime': DateTime.now(),
        'durationMilliseconds': duration.inMilliseconds,
      };
      // Get existing sessions and add new one
      final existingSessions =
          List<Map<String, dynamic>>.from(currentInstance.timeLogSessions);
      existingSessions.add(newSession);
      // Calculate total cumulative time
      final totalTime = TimerUtil.calculateTotalFromSessions(existingSessions);

      // Handle essential vs productive differently
      if (isessential) {
        // For essential: find or create template, then update instance
        final templates = await essentialService.getessentialTemplates(
          userId: uid,
        );
        ActivityRecord? matchingTemplate;
        for (final template in templates) {
          if (template.name.toLowerCase() == taskName.toLowerCase()) {
            matchingTemplate = template;
            break;
          }
        }

        // Create template if it doesn't exist
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

        // Update instance with essential data (status remains pending)
        final updateData = <String, dynamic>{
          'status': 'pending',
          'isTimerActive': false,
          'isTimeLogging': false, // Stop time logging session
          'timeLogSessions': existingSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': totalTime,
          'templateId': templateRef.id,
          'templateName': taskName,
          'templateCategoryType': 'essential',
          'templateCategoryName': 'essential',
          'templateTrackingType': matchingTemplate?.trackingType ?? 'binary',
          'currentSessionStartTime': null,
          'lastUpdated': DateTime.now(),
        };
        await taskInstanceRef.update(updateData);

        // Delete the old timer task template (cleanup)
        try {
          final oldTemplateRef = ActivityRecord.collectionForUser(uid)
              .doc(currentInstance.templateId);
          await oldTemplateRef.delete();
        } catch (e) {
          // Best effort cleanup, don't fail if it doesn't exist
        }
      } else {
        // For productive tasks: existing logic
        final updateData = <String, dynamic>{
          'status': 'pending',
          'isTimerActive': false,
          'isTimeLogging': false, // Stop time logging session
          'timeLogSessions': existingSessions,
          'totalTimeLogged': totalTime,
          'accumulatedTime': totalTime,
          'currentValue': totalTime,
          'templateName': taskName,
          'templateCategoryType': 'task', // Ensure it's marked as task
          'currentSessionStartTime': null,
          'lastUpdated': DateTime.now(),
        };
        // Update category if provided
        if (categoryId != null) {
          updateData['templateCategoryId'] = categoryId;
        }
        if (categoryName != null) {
          updateData['templateCategoryName'] = categoryName;
        }
        await taskInstanceRef.update(updateData);

        // Update the template name as well
        final templateRef = ActivityRecord.collectionForUser(uid)
            .doc(currentInstance.templateId);
        final templateUpdateData = <String, dynamic>{
          'name': taskName,
          'lastUpdated': DateTime.now(),
        };

        // Update template category if provided
        if (categoryId != null) {
          templateUpdateData['categoryId'] = categoryId;
        }
        if (categoryName != null) {
          templateUpdateData['categoryName'] = categoryName;
        }

        await templateRef.update(templateUpdateData);

        // Mark template as inactive - timer tasks are one-time use only
        // Keep template for editing purposes but prevent it from appearing in task lists
        await templateRef.update({'isActive': false});
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get timer task instances for calendar display
  static Future<List<ActivityInstanceRecord>> getTimerTaskInstances({
    String? userId,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
    try {
      // Get tasks with traditional timer fields
      final timerQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('timerStartTime', isNull: false)
          .where('accumulatedTime', isGreaterThan: 0);
      // Get tasks with timeLogSessions
      final sessionQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('timeLogSessions', isNull: false);
      // Get tasks with time logged data (for paused timer tasks)
      final timeLoggedQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('totalTimeLogged', isGreaterThan: 0);
      final timerResult = await timerQuery.get();
      final sessionResult = await sessionQuery.get();
      final timeLoggedResult = await timeLoggedQuery.get();
      // Combine and deduplicate results
      final allInstances = <String, ActivityInstanceRecord>{};
      for (final doc in timerResult.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.isActive) {
          allInstances[instance.reference.id] = instance;
        }
      }
      for (final doc in sessionResult.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.isActive && instance.timeLogSessions.isNotEmpty) {
          allInstances[instance.reference.id] = instance;
        }
      }
      for (final doc in timeLoggedResult.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.isActive) {
          allInstances[instance.reference.id] = instance;
        }
      }
      return allInstances.values.toList();
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getTimerTaskInstances',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      return [];
    }
  }
}
