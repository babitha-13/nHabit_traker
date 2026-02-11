import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart'
    as schema;

/// Helper class for building instance data maps
/// Centralizes instance data creation and template data caching
class InstanceDataBuilder {
  /// Build instance data from a template with automatic field extraction
  ///
  /// This method automatically extracts common template fields and caches them
  /// in the instance data for quick access without needing to fetch the template.
  ///
  /// [template] - The activity template to extract data from
  /// [templateId] - The template ID (can be different from template.reference.id if needed)
  /// [dueDate] - Optional due date for the instance
  /// [dueTime] - Optional due time for the instance
  /// [status] - Instance status (defaults to 'pending')
  /// [categoryColor] - Optional category color (must be fetched from CategoryRecord separately)
  /// [additionalFields] - Any additional fields to include in the instance data
  ///
  /// Returns a map ready to be passed to createActivityInstanceRecordData
  static Map<String, dynamic> buildInstanceDataFromTemplate({
    required ActivityRecord template,
    String? templateId,
    DateTime? dueDate,
    String? dueTime,
    String? status,
    String? categoryColor,
    Map<String, dynamic>? additionalFields,
  }) {
    final data = <String, dynamic>{
      'templateId': templateId ?? template.reference.id,
      'dueDate': dueDate,
      'dueTime': dueTime ?? template.dueTime,
      'status': status ?? 'pending',
      'createdTime': DateTime.now(),
      'lastUpdated': DateTime.now(),
      'isActive': true,
      // Cache template data for quick access (denormalized)
      'templateName': template.name,
      'templateCategoryId': template.categoryId,
      'templateCategoryName': template.categoryName,
      'templateCategoryType': template.categoryType,
      'templateCategoryColor': categoryColor,
      'templatePriority': template.priority,
      'templateTrackingType': template.trackingType,
      'templateTarget': template.target,
      'templateUnit': template.unit,
      'templateDescription': template.description,
      'templateTimeEstimateMinutes': template.timeEstimateMinutes,
      'templateShowInFloatingTimer': template.showInFloatingTimer,
      'templateIsRecurring': template.isRecurring,
      'templateEveryXValue': template.everyXValue,
      'templateEveryXPeriodType': template.everyXPeriodType,
      'templateTimesPerPeriod': template.timesPerPeriod,
      'templatePeriodType': template.periodType,
    };

    // Add any additional fields
    if (additionalFields != null) {
      data.addAll(additionalFields);
    }

    return data;
  }

  /// Create instance data map using the schema function with template data automatically extracted
  ///
  /// This is a convenience method that combines buildInstanceDataFromTemplate
  /// with the schema's createActivityInstanceRecordData function.
  static Map<String, dynamic> createInstanceData({
    required ActivityRecord template,
    String? templateId,
    DateTime? dueDate,
    String? dueTime,
    String? status,
    DateTime? completedAt,
    DateTime? skippedAt,
    dynamic currentValue,
    dynamic lastDayValue,
    int? accumulatedTime,
    bool? isTimerActive,
    DateTime? timerStartTime,
    bool? isActive,
    String? notes,
    int? queueOrder,
    int? habitsOrder,
    int? tasksOrder,
    List<dynamic>? timeLogSessions,
    DateTime? currentSessionStartTime,
    bool? isTimeLogging,
    int? totalTimeLogged,
    String? categoryColor,
    Map<String, dynamic>? additionalFields,
  }) {
    // Build base data from template
    final baseData = buildInstanceDataFromTemplate(
      template: template,
      templateId: templateId,
      dueDate: dueDate,
      dueTime: dueTime,
      status: status,
      categoryColor: categoryColor,
      additionalFields: additionalFields,
    );

    // Add instance-specific fields
    final instanceData = <String, dynamic>{
      ...baseData,
      if (completedAt != null) 'completedAt': completedAt,
      if (skippedAt != null) 'skippedAt': skippedAt,
      if (currentValue != null) 'currentValue': currentValue,
      if (lastDayValue != null) 'lastDayValue': lastDayValue,
      if (accumulatedTime != null) 'accumulatedTime': accumulatedTime,
      if (isTimerActive != null) 'isTimerActive': isTimerActive,
      if (timerStartTime != null) 'timerStartTime': timerStartTime,
      if (isActive != null) 'isActive': isActive,
      if (notes != null) 'notes': notes,
      if (queueOrder != null) 'queueOrder': queueOrder,
      if (habitsOrder != null) 'habitsOrder': habitsOrder,
      if (tasksOrder != null) 'tasksOrder': tasksOrder,
      if (timeLogSessions != null) 'timeLogSessions': timeLogSessions,
      if (currentSessionStartTime != null)
        'currentSessionStartTime': currentSessionStartTime,
      if (isTimeLogging != null) 'isTimeLogging': isTimeLogging,
      if (totalTimeLogged != null) 'totalTimeLogged': totalTimeLogged,
    };

    // Use the schema function to create the final data map
    return schema.createActivityInstanceRecordData(
      templateId: instanceData['templateId'] as String?,
      dueDate: instanceData['dueDate'] as DateTime?,
      dueTime: instanceData['dueTime'] as String?,
      status: instanceData['status'] as String?,
      completedAt: instanceData['completedAt'] as DateTime?,
      skippedAt: instanceData['skippedAt'] as DateTime?,
      currentValue: instanceData['currentValue'],
      lastDayValue: instanceData['lastDayValue'],
      accumulatedTime: instanceData['accumulatedTime'] as int?,
      isTimerActive: instanceData['isTimerActive'] as bool?,
      timerStartTime: instanceData['timerStartTime'] as DateTime?,
      createdTime: instanceData['createdTime'] as DateTime?,
      lastUpdated: instanceData['lastUpdated'] as DateTime?,
      isActive: instanceData['isActive'] as bool?,
      notes: instanceData['notes'] as String?,
      templateName: instanceData['templateName'] as String?,
      templateCategoryId: instanceData['templateCategoryId'] as String?,
      templateCategoryName: instanceData['templateCategoryName'] as String?,
      templateCategoryType: instanceData['templateCategoryType'] as String?,
      templateCategoryColor: instanceData['templateCategoryColor'] as String?,
      templatePriority: instanceData['templatePriority'] as int?,
      templateTrackingType: instanceData['templateTrackingType'] as String?,
      templateTarget: instanceData['templateTarget'],
      templateUnit: instanceData['templateUnit'] as String?,
      templateDescription: instanceData['templateDescription'] as String?,
      templateTimeEstimateMinutes:
          instanceData['templateTimeEstimateMinutes'] as int?,
      templateShowInFloatingTimer:
          instanceData['templateShowInFloatingTimer'] as bool?,
      templateIsRecurring: instanceData['templateIsRecurring'] as bool?,
      templateEveryXValue: instanceData['templateEveryXValue'] as int?,
      templateEveryXPeriodType:
          instanceData['templateEveryXPeriodType'] as String?,
      templateTimesPerPeriod: instanceData['templateTimesPerPeriod'] as int?,
      templatePeriodType: instanceData['templatePeriodType'] as String?,
      queueOrder: instanceData['queueOrder'] as int?,
      habitsOrder: instanceData['habitsOrder'] as int?,
      tasksOrder: instanceData['tasksOrder'] as int?,
      timeLogSessions: instanceData['timeLogSessions'] as List<dynamic>?,
      currentSessionStartTime:
          instanceData['currentSessionStartTime'] as DateTime?,
      isTimeLogging: instanceData['isTimeLogging'] as bool?,
      totalTimeLogged: instanceData['totalTimeLogged'] as int?,
    );
  }
}
