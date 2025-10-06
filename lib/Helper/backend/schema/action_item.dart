import 'package:habit_tracker/Helper/backend/schema/task_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_instance_record.dart';

class ActionItem {
  final String id;
  final String templateId;
  final String name;
  final String type; // 'task' or 'habit'
  final DateTime dueDate;
  final int priority;
  final String categoryName;
  final String trackingType;
  final dynamic target;
  final dynamic currentValue;
  final String status;
  final String unit;

  ActionItem.fromTaskInstance(TaskInstanceRecord instance)
      : id = instance.reference.id,
        templateId = instance.templateId,
        name = instance.templateName,
        type = 'task',
        dueDate = instance.dueDate!,
        priority = instance.templatePriority,
        categoryName = instance.templateCategoryName,
        trackingType = instance.templateTrackingType,
        target = instance.templateTarget,
        currentValue = instance.currentValue,
        status = instance.status,
        unit = instance.templateUnit;

  ActionItem.fromHabitInstance(HabitInstanceRecord instance)
      : id = instance.reference.id,
        templateId = instance.templateId,
        name = instance.templateName,
        type = 'habit',
        dueDate = instance.dueDate!,
        priority = instance.templatePriority,
        categoryName = instance.templateCategoryName,
        trackingType = instance.templateTrackingType,
        target = instance.templateTarget,
        currentValue = instance.currentValue,
        status = instance.status,
        unit = instance.templateUnit;

  bool get isOverdue => dueDate.isBefore(_todayStart);
  bool get isDueToday => _isSameDay(dueDate, DateTime.now());
  bool get isDueTomorrow =>
      _isSameDay(dueDate, DateTime.now().add(Duration(days: 1)));

  static DateTime get _todayStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
