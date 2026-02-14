import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_instance_record.dart'
    as habit_schema;
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'task_instance_task_service.dart';
import 'task_instance_habit_service.dart';
import 'task_instance_initialization_service.dart';
import 'task_instance_template_sync_service.dart';
import 'task_instance_utility_service.dart';
import 'task_instance_timer_task_service.dart';
import 'task_instance_time_logging_service.dart';

/// Service to manage task and habit instances
/// Handles the creation, completion, and scheduling of recurring tasks/habits
/// Following Microsoft To-Do pattern: only show current instances, generate next on completion
/// This is a facade that delegates to specialized service files
class TaskInstanceService {
  /// Get current user ID
  static String get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return user.uid;
  }

  /// Get today's date at midnight (start of day)
  static DateTime get _todayStart {
    return DateService.todayStart;
  }

  // ==================== TASK INSTANCES ====================
  /// Get all active activity instances for today and overdue
  static Future<List<ActivityInstanceRecord>> getTodaysTaskInstances({
    String? userId,
  }) async {
    return TaskInstanceTaskService.getTodaysTaskInstances(userId: userId);
  }

  /// Create a new task instance from a template
  static Future<DocumentReference> createTaskInstance({
    required String templateId,
    DateTime? dueDate,
    required ActivityRecord template,
    String? userId,
  }) async {
    return TaskInstanceTaskService.createTaskInstance(
      templateId: templateId,
      dueDate: dueDate,
      template: template,
      userId: userId,
    );
  }

  /// Complete a task instance and generate next occurrence if recurring
  static Future<void> completeTaskInstance({
    required String instanceId,
    dynamic finalValue,
    int? finalAccumulatedTime,
    String? notes,
    String? userId,
  }) async {
    return TaskInstanceTaskService.completeTaskInstance(
      instanceId: instanceId,
      finalValue: finalValue,
      finalAccumulatedTime: finalAccumulatedTime,
      notes: notes,
      userId: userId,
    );
  }

  /// Skip a task instance and generate next occurrence if recurring
  static Future<void> skipTaskInstance({
    required String instanceId,
    String? notes,
    String? userId,
  }) async {
    return TaskInstanceTaskService.skipTaskInstance(
      instanceId: instanceId,
      notes: notes,
      userId: userId,
    );
  }

  // ==================== HABIT INSTANCES ====================
  /// Get all active habit instances for today and overdue
  static Future<List<habit_schema.HabitInstanceRecord>>
      getTodaysHabitInstances({
    String? userId,
  }) async {
    return TaskInstanceHabitService.getTodaysHabitInstances(userId: userId);
  }

  /// Create a new habit instance from a template
  static Future<DocumentReference> createActivityInstance({
    required String templateId,
    required DateTime dueDate,
    required ActivityRecord template,
    String? userId,
  }) async {
    return TaskInstanceHabitService.createActivityInstance(
      templateId: templateId,
      dueDate: dueDate,
      template: template,
      userId: userId,
    );
  }

  /// Complete a habit instance and generate next occurrence
  static Future<void> completeHabitInstance({
    required String instanceId,
    dynamic finalValue,
    int? finalAccumulatedTime,
    String? notes,
    String? userId,
  }) async {
    return TaskInstanceHabitService.completeHabitInstance(
      instanceId: instanceId,
      finalValue: finalValue,
      finalAccumulatedTime: finalAccumulatedTime,
      notes: notes,
      userId: userId,
    );
  }

  /// Skip a habit instance and generate next occurrence
  static Future<void> skipHabitInstance({
    required String instanceId,
    String? notes,
    String? userId,
  }) async {
    return TaskInstanceHabitService.skipHabitInstance(
      instanceId: instanceId,
      notes: notes,
      userId: userId,
    );
  }

  // ==================== INITIALIZATION ====================
  /// Generate initial instances for a new recurring task
  static Future<void> initializeTaskInstances({
    required String templateId,
    required ActivityRecord template,
    DateTime? startDate,
    String? userId,
  }) async {
    return TaskInstanceInitializationService.initializeTaskInstances(
      templateId: templateId,
      template: template,
      startDate: startDate,
      userId: userId,
    );
  }

  /// Generate initial instances for a new habit
  static Future<void> initializeHabitInstances({
    required String templateId,
    required ActivityRecord template,
    DateTime? startDate,
    String? userId,
  }) async {
    return TaskInstanceInitializationService.initializeHabitInstances(
      templateId: templateId,
      template: template,
      startDate: startDate,
      userId: userId,
    );
  }

  // ==================== TEMPLATE SYNC METHODS ====================
  /// When a template is updated (e.g., schedule change), regenerate instances
  static Future<void> syncInstancesOnTemplateUpdate({
    required String templateId,
    required String templateType, // 'task' or 'habit'
    required DateTime? nextDueDate,
    String? userId,
  }) async {
    return TaskInstanceTemplateSyncService.syncInstancesOnTemplateUpdate(
      templateId: templateId,
      templateType: templateType,
      nextDueDate: nextDueDate,
      userId: userId,
    );
  }

  // ==================== UTILITY METHODS ====================
  /// Update instance progress (for quantity/duration tracking)
  static Future<void> updateInstanceProgress({
    required String instanceId,
    required String instanceType, // 'task' or 'habit'
    dynamic currentValue,
    int? accumulatedTime,
    bool? isTimerActive,
    DateTime? timerStartTime,
    String? userId,
  }) async {
    return TaskInstanceUtilityService.updateInstanceProgress(
      instanceId: instanceId,
      instanceType: instanceType,
      currentValue: currentValue,
      accumulatedTime: accumulatedTime,
      isTimerActive: isTimerActive,
      timerStartTime: timerStartTime,
      userId: userId,
    );
  }

  /// Delete all instances for a template (when template is deleted)
  static Future<void> deleteInstancesForTemplate({
    required String templateId,
    required String templateType, // 'task' or 'habit'
    String? userId,
  }) async {
    return TaskInstanceUtilityService.deleteInstancesForTemplate(
      templateId: templateId,
      templateType: templateType,
      userId: userId,
    );
  }

  // ==================== TIMER TASK METHODS ====================
  /// Create a new timer task instance when timer starts
  static Future<DocumentReference> createTimerTaskInstance({
    String? categoryId,
    String? categoryName,
    String? userId,
    bool startTimer = true,
    bool showInFloatingTimer = true,
  }) async {
    return TaskInstanceTimerTaskService.createTimerTaskInstance(
      categoryId: categoryId,
      categoryName: categoryName,
      userId: userId,
      startTimer: startTimer,
      showInFloatingTimer: showInFloatingTimer,
    );
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
    return TaskInstanceTimerTaskService.updateTimerTaskOnStop(
      taskInstanceRef: taskInstanceRef,
      duration: duration,
      taskName: taskName,
      categoryId: categoryId,
      categoryName: categoryName,
      activityType: activityType,
      userId: userId,
    );
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
    return TaskInstanceTimerTaskService.updateTimerTaskOnPause(
      taskInstanceRef: taskInstanceRef,
      duration: duration,
      taskName: taskName,
      categoryId: categoryId,
      categoryName: categoryName,
      activityType: activityType,
      userId: userId,
    );
  }

  /// Get timer task instances for calendar display
  static Future<List<ActivityInstanceRecord>> getTimerTaskInstances({
    String? userId,
  }) async {
    return TaskInstanceTimerTaskService.getTimerTaskInstances(userId: userId);
  }

  // ==================== TIME LOGGING METHODS ====================
  /// Start time logging on an existing activity instance
  static Future<void> startTimeLogging({
    required DocumentReference activityInstanceRef,
    String? userId,
  }) async {
    return TaskInstanceTimeLoggingService.startTimeLogging(
      activityInstanceRef: activityInstanceRef,
      userId: userId,
    );
  }

  /// Stop time logging and optionally mark task as complete
  static Future<void> stopTimeLogging({
    required DocumentReference activityInstanceRef,
    required bool markComplete,
    String? userId,
  }) async {
    return TaskInstanceTimeLoggingService.stopTimeLogging(
      activityInstanceRef: activityInstanceRef,
      markComplete: markComplete,
      userId: userId,
    );
  }

  /// Pause time logging (keeps task pending)
  static Future<void> pauseTimeLogging({
    required DocumentReference activityInstanceRef,
    String? userId,
  }) async {
    return TaskInstanceTimeLoggingService.pauseTimeLogging(
      activityInstanceRef: activityInstanceRef,
      userId: userId,
    );
  }

  /// Discard current time logging session (cancel session without saving)
  static Future<void> discardTimeLogging({
    required DocumentReference activityInstanceRef,
    String? userId,
  }) async {
    return TaskInstanceTimeLoggingService.discardTimeLogging(
      activityInstanceRef: activityInstanceRef,
      userId: userId,
    );
  }

  /// Get current session duration (for displaying running time)
  static Duration getCurrentSessionDuration(ActivityInstanceRecord instance) {
    return TaskInstanceTimeLoggingService.getCurrentSessionDuration(instance);
  }

  /// Get aggregate time including current session
  static Duration getAggregateDuration(ActivityInstanceRecord instance) {
    return TaskInstanceTimeLoggingService.getAggregateDuration(instance);
  }

  /// Get all activity instances with time logs for calendar display
  static Future<List<ActivityInstanceRecord>> getTimeLoggedTasks({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return TaskInstanceTimeLoggingService.getTimeLoggedTasks(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Get all essential instances with time logs for calendar display
  /// Optimized version that uses belongsToDate when available for better performance
  static Future<List<ActivityInstanceRecord>> getessentialInstances({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return TaskInstanceTimeLoggingService.getessentialInstances(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Optimized method to get time-logged tasks for a specific date
  /// Uses belongsToDate field when available for better query performance
  static Future<List<ActivityInstanceRecord>> getTimeLoggedTasksForDate({
    String? userId,
    required DateTime date,
  }) async {
    return TaskInstanceTimeLoggingService.getTimeLoggedTasksForDate(
      userId: userId,
      date: date,
    );
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
    return TaskInstanceTimeLoggingService.logManualTimeEntry(
      taskName: taskName,
      startTime: startTime,
      endTime: endTime,
      activityType: activityType,
      categoryId: categoryId,
      categoryName: categoryName,
      templateId: templateId,
      userId: userId,
      markComplete: markComplete,
    );
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
    return TaskInstanceTimeLoggingService.updateTimeLogSession(
      instanceId: instanceId,
      sessionIndex: sessionIndex,
      startTime: startTime,
      endTime: endTime,
      originalSessionStartTime: originalSessionStartTime,
      originalSessionEndTime: originalSessionEndTime,
      userId: userId,
    );
  }

  /// Delete a specific time log session
  /// Returns true if the instance was uncompleted due to time/quantity falling below target
  static Future<bool> deleteTimeLogSession({
    required String instanceId,
    required int sessionIndex,
    DateTime? sessionStartTime,
    DateTime? sessionEndTime,
    String? userId,
  }) async {
    return TaskInstanceTimeLoggingService.deleteTimeLogSession(
      instanceId: instanceId,
      sessionIndex: sessionIndex,
      sessionStartTime: sessionStartTime,
      sessionEndTime: sessionEndTime,
      userId: userId,
    );
  }
}
