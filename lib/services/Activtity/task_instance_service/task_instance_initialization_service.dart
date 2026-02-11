import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/services/Activtity/template_sync_helper.dart';
import 'task_instance_helper_service.dart';
import 'task_instance_task_service.dart';
import 'task_instance_habit_service.dart';

/// Service for initializing task and habit instances
class TaskInstanceInitializationService {
  /// Generate initial instances for a new recurring task
  static Future<void> initializeTaskInstances({
    required String templateId,
    required ActivityRecord template,
    DateTime? startDate,
    String? userId,
  }) async {
    if (!template.isRecurring) {
      // For one-time tasks, create a single instance, preserving the null due date if not set.
      await TaskInstanceTaskService.createTaskInstance(
        templateId: templateId,
        dueDate: template.dueDate,
        template: template,
        userId: userId,
      );
      return;
    }
    final firstDueDate = template.dueDate ??
        startDate ??
        TaskInstanceHelperService.getTodayStart();
    await TaskInstanceTaskService.createTaskInstance(
      templateId: templateId,
      dueDate: firstDueDate,
      template: template,
      userId: userId,
    );
    await TemplateSyncHelper.updateTemplateDueDate(
      templateRef: template.reference,
      dueDate: firstDueDate,
    );
  }

  /// Generate initial instances for a new habit
  static Future<void> initializeHabitInstances({
    required String templateId,
    required ActivityRecord template,
    DateTime? startDate,
    String? userId,
  }) async {
    // Habits are always recurring, create the first instance
    final firstDueDate = startDate ?? TaskInstanceHelperService.getTodayStart();
    await TaskInstanceHabitService.createActivityInstance(
      templateId: templateId,
      dueDate: firstDueDate,
      template: template,
      userId: userId,
    );
  }
}
