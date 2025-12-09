import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_dialog.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/start_date_change_dialog.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Helper/backend/reminder_scheduler.dart';
import 'package:habit_tracker/Helper/utils/reminder_config.dart';
import 'package:habit_tracker/Helper/utils/reminder_config_dialog.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/task_type_dropdown_helper.dart';
import 'package:intl/intl.dart';

class EditTask extends StatefulWidget {
  final ActivityRecord task;
  final List<CategoryRecord> categories;
  final Function(ActivityRecord) onSave;
  final ActivityInstanceRecord? instance;
  const EditTask({
    super.key,
    required this.task,
    required this.categories,
    required this.onSave,
    this.instance,
  });
  @override
  State<EditTask> createState() => _EditTaskState();
}

class _EditTaskState extends State<EditTask> {
  late TextEditingController _titleController;
  late TextEditingController _unitController;
  late TextEditingController _descriptionController;
  String? _selectedCategoryId;
  String? _selectedTrackingType;
  int _targetNumber = 1;
  Duration _targetDuration = const Duration(hours: 1);
  String _unit = '';
  int _priority = 1;
  DateTime? _dueDate;
  DateTime? _instanceDueDate;
  DateTime? _endDate;
  TimeOfDay? _selectedDueTime;
  TimeOfDay? _instanceDueTime;
  bool quickIsTaskRecurring = false;
  FrequencyConfig? _frequencyConfig;
  bool _isStartDateReadOnly = false;
  DateTime? _originalStartDate; // Track original start date for comparison
  FrequencyConfig?
      _originalFrequencyConfig; // Track original frequency config for comparison
  List<ReminderConfig> _reminders = [];
  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleController = TextEditingController(text: t.name);
    _unitController = TextEditingController(text: t.unit);
    _descriptionController = TextEditingController(text: t.description);
    _priority = t.priority;
    // Set the category ID - try both categoryId and categoryName matching
    String? matchingCategoryId;
    if (t.categoryId.isNotEmpty &&
        widget.categories.any((c) => c.reference.id == t.categoryId)) {
      matchingCategoryId = t.categoryId;
    } else if (t.categoryName.isNotEmpty &&
        widget.categories.any((c) => c.name == t.categoryName)) {
      // Find the category by name and use its ID
      final category =
          widget.categories.firstWhere((c) => c.name == t.categoryName);
      matchingCategoryId = category.reference.id;
    }
    _selectedCategoryId = matchingCategoryId;
    print(
        'DEBUG: Available categories: ${widget.categories.map((c) => '${c.name} (${c.reference.id})').toList()}');
    _selectedTrackingType = t.trackingType;
    _targetNumber = t.target is int ? t.target as int : 1;
    _targetDuration = t.trackingType == 'time'
        ? Duration(minutes: t.target as int)
        : const Duration(hours: 1);
    _unit = t.unit;
    _dueDate = t.dueDate;
    _endDate = t.endDate;
    // Load due time from template
    if (t.hasDueTime()) {
      _selectedDueTime = TimeUtils.stringToTimeOfDay(t.dueTime);
    }
    // Load instance data if provided
    if (widget.instance != null) {
      _instanceDueDate = widget.instance!.dueDate;
      if (widget.instance!.hasDueTime()) {
        _instanceDueTime =
            TimeUtils.stringToTimeOfDay(widget.instance!.dueTime);
      }
    }
    // Load existing frequency configuration
    quickIsTaskRecurring = t.isRecurring;
    if (quickIsTaskRecurring) {
      _frequencyConfig = _convertTaskFrequencyToConfig(t);
      // Store original frequency config for comparison
      _originalFrequencyConfig = _frequencyConfig;
    }
    // Store original start date for comparison
    _originalStartDate = t.startDate;
    // Load reminders if they exist
    if (t.hasReminders()) {
      _reminders = ReminderConfigList.fromMapList(t.reminders);
    }
    // Check if start date should be read-only
    _checkStartDateReadOnly();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _unitController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _checkStartDateReadOnly() async {
    // Only for recurring tasks
    if (!quickIsTaskRecurring) {
      setState(() => _isStartDateReadOnly = false);
      return;
    }
    // Check if start date has passed
    final startDate = widget.task.startDate;
    if (startDate == null) {
      setState(() => _isStartDateReadOnly = false);
      return;
    }
    final today = DateTime.now();
    if (!startDate.isBefore(today)) {
      setState(() => _isStartDateReadOnly = false);
      return;
    }
    // Check if any instances have been completed
    try {
      final completedInstances =
          await ActivityInstanceService.getInstancesForTemplate(
        templateId: widget.task.reference.id,
      );
      final hasCompletedInstances =
          completedInstances.any((i) => i.status == 'completed');
      setState(() => _isStartDateReadOnly = hasCompletedInstances);
    } catch (e) {
      // If we can't check, assume it's not read-only
      setState(() => _isStartDateReadOnly = false);
    }
  }

  FrequencyConfig _convertTaskFrequencyToConfig(ActivityRecord task) {
    FrequencyType type;
    int timesPerPeriod = 1;
    PeriodType periodType = PeriodType.weeks;
    int everyXValue = 1;
    PeriodType everyXPeriodType = PeriodType.days;
    List<int> selectedDays = [];
    DateTime startDate = task.startDate ?? DateTime.now();
    DateTime? endDate = task.endDate;
    // Handle endDate - if it's 2099 or later, treat as perpetual (set to null)
    if (endDate != null && endDate.year >= 2099) {
      endDate = null;
    }
    switch (task.frequencyType) {
      case 'everyXPeriod':
        type = FrequencyType.everyXPeriod;
        everyXValue = task.everyXValue;
        everyXPeriodType = task.everyXPeriodType == 'days'
            ? PeriodType.days
            : task.everyXPeriodType == 'weeks'
                ? PeriodType.weeks
                : PeriodType.months;
        break;
      case 'timesPerPeriod':
        type = FrequencyType.timesPerPeriod;
        timesPerPeriod = task.timesPerPeriod;
        periodType = task.periodType == 'weeks'
            ? PeriodType.weeks
            : task.periodType == 'months'
                ? PeriodType.months
                : PeriodType.weeks; // Default to weeks if unknown
        break;
      case 'specificDays':
        type = FrequencyType.specificDays;
        selectedDays = task.specificDays;
        break;
      default:
        type = FrequencyType.everyXPeriod;
        everyXValue = 1;
        everyXPeriodType = PeriodType.days;
    }
    return FrequencyConfig(
      type: type,
      timesPerPeriod: timesPerPeriod,
      periodType: periodType,
      everyXValue: everyXValue,
      everyXPeriodType: everyXPeriodType,
      selectedDays: selectedDays,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Check if frequency configuration has changed
  bool _hasFrequencyChanged() {
    if (_originalFrequencyConfig == null || _frequencyConfig == null)
      return false;
    final original = _originalFrequencyConfig!;
    final current = _frequencyConfig!;
    // Compare all frequency-related fields
    return original.type != current.type ||
        original.startDate != current.startDate ||
        original.endDate != current.endDate ||
        original.everyXValue != current.everyXValue ||
        original.everyXPeriodType != current.everyXPeriodType ||
        original.timesPerPeriod != current.timesPerPeriod ||
        original.periodType != current.periodType ||
        !_listEquals(original.selectedDays, current.selectedDays);
  }

  /// Helper method to compare lists
  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  void _save() async {
    // Validate required fields
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }
    final docRef = widget.task.reference;
    print(
        'DEBUG: Available categories: ${widget.categories.map((c) => '${c.name} (${c.reference.id})').toList()}');
    // Handle instance due date change if applicable
    if (widget.instance != null && _instanceDueDate != null) {
      final originalInstanceDueDate = widget.instance!.dueDate;
      if (originalInstanceDueDate != _instanceDueDate) {
        try {
          await ActivityInstanceService.rescheduleInstance(
            instanceId: widget.instance!.reference.id,
            newDueDate: _instanceDueDate!,
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating instance due date: $e')),
          );
          return;
        }
      }
    }
    // Find the selected category name
    final selectedCategory = widget.categories
        .where((c) => c.reference.id == _selectedCategoryId)
        .firstOrNull;
    if (selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected category not found')),
      );
      return;
    }
    final updateData = createActivityRecordData(
      isRecurring: quickIsTaskRecurring,
      name: _titleController.text.trim(),
      categoryId: _selectedCategoryId,
      categoryName: selectedCategory.name,
      trackingType: _selectedTrackingType,
      unit: _unit,
      target: _selectedTrackingType == 'quantitative'
          ? _targetNumber
          : _selectedTrackingType == 'time'
              ? _targetDuration.inMinutes
              : null,
      dueDate: _dueDate,
      dueTime: _selectedDueTime != null
          ? TimeUtils.timeOfDayToString(_selectedDueTime!)
          : null,
      specificDays: quickIsTaskRecurring &&
              _frequencyConfig != null &&
              _frequencyConfig!.type == FrequencyType.specificDays
          ? _frequencyConfig!.selectedDays
          : null,
      lastUpdated: DateTime.now(),
      categoryType: 'task',
      priority: _priority,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      isActive: true,
      startDate: quickIsTaskRecurring && _frequencyConfig != null
          ? _frequencyConfig!.startDate
          : DateTime.now(),
      endDate: quickIsTaskRecurring && _frequencyConfig != null
          ? _frequencyConfig!.endDate
          : _endDate,
      // New frequency fields - only store relevant fields based on frequency type
      frequencyType: quickIsTaskRecurring && _frequencyConfig != null
          ? _frequencyConfig!.type.toString().split('.').last
          : null,
      // Only store everyX fields if frequency type is everyXPeriod
      everyXValue: quickIsTaskRecurring &&
              _frequencyConfig != null &&
              _frequencyConfig!.type == FrequencyType.everyXPeriod
          ? _frequencyConfig!.everyXValue
          : null,
      everyXPeriodType: quickIsTaskRecurring &&
              _frequencyConfig != null &&
              _frequencyConfig!.type == FrequencyType.everyXPeriod
          ? _frequencyConfig!.everyXPeriodType.toString().split('.').last
          : null,
      reminders: _reminders.isNotEmpty
          ? ReminderConfigList.toMapList(_reminders)
          : null,
      // Only store timesPerPeriod fields if frequency type is timesPerPeriod
      timesPerPeriod: quickIsTaskRecurring &&
              _frequencyConfig != null &&
              _frequencyConfig!.type == FrequencyType.timesPerPeriod
          ? _frequencyConfig!.timesPerPeriod
          : null,
      periodType: quickIsTaskRecurring &&
              _frequencyConfig != null &&
              _frequencyConfig!.type == FrequencyType.timesPerPeriod
          ? _frequencyConfig!.periodType.toString().split('.').last
          : null,
    );
    // Check if frequency configuration has changed for recurring tasks
    if (quickIsTaskRecurring &&
        _frequencyConfig != null &&
        _hasFrequencyChanged()) {
      // Show confirmation dialog
      final shouldProceed = await StartDateChangeDialog.show(
        context: context,
        oldStartDate: _originalStartDate ?? DateTime.now(),
        newStartDate: _frequencyConfig!.startDate,
        activityName: _titleController.text.trim(),
      );
      if (!shouldProceed) {
        return; // Abort save operation
      }
      // Regenerate instances with new frequency configuration
      try {
        await ActivityInstanceService.regenerateInstancesFromStartDate(
          templateId: widget.task.reference.id,
          template: widget.task,
          newStartDate: _frequencyConfig!.startDate,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating instances: $e')),
        );
        return;
      }
    } else if (quickIsTaskRecurring && _frequencyConfig != null) {
      // Check if only end date has changed (without frequency changes)
      final originalEndDate = _originalFrequencyConfig?.endDate;
      final newEndDate = _frequencyConfig!.endDate;
      if (originalEndDate != newEndDate && newEndDate != null) {
        // If end date was shortened, clean up instances beyond the new end date
        if (originalEndDate == null || newEndDate.isBefore(originalEndDate)) {
          try {
            await ActivityInstanceService.cleanupInstancesBeyondEndDate(
              templateId: widget.task.reference.id,
              newEndDate: newEndDate,
            );
          } catch (e) {
            // Don't fail the save operation for this
          }
        }
      }
    }
    try {
      await docRef.update(updateData);
      // Update all pending instances with new template data (with error handling)
      try {
        final instances = await ActivityInstanceService.getInstancesForTemplate(
            templateId: widget.task.reference.id);
        final pendingInstances =
            instances.where((i) => i.status != 'completed').toList();
        // Update instances in batches to avoid timeout
        const batchSize = 10;
        int successCount = 0;
        int failureCount = 0;
        for (int i = 0; i < pendingInstances.length; i += batchSize) {
          final batch = pendingInstances.skip(i).take(batchSize);
          print(
              'DEBUG: Updating batch ${(i ~/ batchSize) + 1} with ${batch.length} instances');
          final results = await Future.wait(batch.map((instance) async {
            try {
              print(
                  'DEBUG: Old category: ${instance.templateCategoryName} (${instance.templateCategoryId})');
              print(
                  'DEBUG: New category: ${updateData['categoryName']} (${updateData['categoryId']})');
              await instance.reference.update({
                'templateName': updateData['name'],
                'templateCategoryId': updateData['categoryId'],
                'templateCategoryName': updateData['categoryName'],
                'templateTrackingType': updateData['trackingType'],
                'templateTarget': updateData['target'],
                'templateUnit': updateData['unit'],
                'templatePriority': updateData['priority'],
                'templateDescription': updateData['description'],
                'templateDueTime': updateData['dueTime'],
                'lastUpdated': DateTime.now(),
              });
              // Create updated instance record and broadcast event immediately
              final updatedInstanceData = createActivityInstanceRecordData(
                templateId: instance.templateId,
                dueDate: instance.dueDate,
                dueTime: instance.dueTime,
                templateDueTime: updateData['dueTime'],
                status: instance.status,
                completedAt: instance.completedAt,
                skippedAt: instance.skippedAt,
                currentValue: instance.currentValue,
                lastDayValue: instance.lastDayValue,
                accumulatedTime: instance.accumulatedTime,
                isTimerActive: instance.isTimerActive,
                timerStartTime: instance.timerStartTime,
                createdTime: instance.createdTime,
                lastUpdated: DateTime.now(),
                isActive: instance.isActive,
                notes: instance.notes,
                templateName: updateData['name'],
                templateCategoryId: updateData['categoryId'],
                templateCategoryName: updateData['categoryName'],
                templateCategoryType: instance.templateCategoryType,
                templatePriority: instance.templatePriority,
                templateTrackingType: updateData['trackingType'],
                templateTarget: updateData['target'],
                templateUnit: updateData['unit'],
                templateDescription: instance.templateDescription,
                templateShowInFloatingTimer:
                    instance.templateShowInFloatingTimer,
                templateEveryXValue: instance.templateEveryXValue,
                templateEveryXPeriodType: instance.templateEveryXPeriodType,
                templateTimesPerPeriod: instance.templateTimesPerPeriod,
                templatePeriodType: instance.templatePeriodType,
                dayState: instance.dayState,
                belongsToDate: instance.belongsToDate,
                closedAt: instance.closedAt,
                windowEndDate: instance.windowEndDate,
                windowDuration: instance.windowDuration,
              );
              final updatedInstance =
                  ActivityInstanceRecord.getDocumentFromData(
                updatedInstanceData,
                instance.reference,
              );
              // Broadcast the update event immediately
              InstanceEvents.broadcastInstanceUpdated(updatedInstance);
              // Reschedule reminder if due time changed
              try {
                await ReminderScheduler.rescheduleReminderForInstance(
                    updatedInstance);
              } catch (e) {}
              return true;
            } catch (e) {
              return false;
            }
          }));
          // Count successes and failures
          for (final result in results) {
            if (result) {
              successCount++;
            } else {
              failureCount++;
            }
          }
        }
      } catch (e) {
        // Don't fail the entire save operation if instance updates fail
      }
      final updatedHabit =
          ActivityRecord.getDocumentFromData(updateData, docRef);
      // Call onSave to trigger UI refresh
      widget.onSave(updatedHabit);
      if (!mounted) return;
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task updated successfully'),
          duration: Duration(seconds: 1),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating task: $e')),
      );
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickInstanceDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _instanceDueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _instanceDueDate = picked);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.task.startDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
      // Update the frequency config start date if it exists
      if (_frequencyConfig != null) {
        _frequencyConfig = _frequencyConfig!.copyWith(startDate: picked);
      }
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
      // Update the frequency config end date if it exists
      if (_frequencyConfig != null) {
        _frequencyConfig = _frequencyConfig!.copyWith(endDate: picked);
      }
    }
  }

  Future<void> _pickDueTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedDueTime ?? TimeUtils.getCurrentTime(),
    );
    if (picked != null && picked != _selectedDueTime) {
      setState(() => _selectedDueTime = picked);
    }
  }

  String _getFrequencyDescription() {
    if (_frequencyConfig == null) return '';
    switch (_frequencyConfig!.type) {
      case FrequencyType.daily:
        return 'Every day';
      case FrequencyType.specificDays:
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final selectedDayNames = _frequencyConfig!.selectedDays
            .map((day) => days[day - 1])
            .join(', ');
        return 'On $selectedDayNames';
      case FrequencyType.timesPerPeriod:
        final period = _frequencyConfig!.periodType == PeriodType.weeks
            ? 'week'
            : _frequencyConfig!.periodType == PeriodType.months
                ? 'month'
                : 'year';
        return '${_frequencyConfig!.timesPerPeriod} times per $period';
      case FrequencyType.everyXPeriod:
        // Special case: every 1 day is the same as every day
        if (_frequencyConfig!.everyXValue == 1 &&
            _frequencyConfig!.everyXPeriodType == PeriodType.days) {
          return 'Every day';
        }
        final period = _frequencyConfig!.everyXPeriodType == PeriodType.days
            ? 'days'
            : _frequencyConfig!.everyXPeriodType == PeriodType.weeks
                ? 'weeks'
                : 'months';
        return 'Every ${_frequencyConfig!.everyXValue} $period';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          gradient: theme.neumorphicGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.surfaceBorderColor,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 2),
              blurRadius: 4,
              spreadRadius: 0,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit Task',
                  style: theme.titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.tertiary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.surfaceBorderColor,
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _titleController,
                    style: theme.bodyMedium,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: 'Task name',
                      hintStyle: TextStyle(
                        color: theme.secondaryText,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.tertiary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.surfaceBorderColor,
                      width: 1,
                    ),
                  ),
                  child: DropdownButtonFormField<String>(
                    value: () {
                      if (_selectedCategoryId == null) return null;
                      final isValid = widget.categories
                          .any((c) => c.reference.id == _selectedCategoryId);
                      return isValid ? _selectedCategoryId : null;
                    }(),
                    decoration: InputDecoration(
                      labelText: 'Category',
                      labelStyle: TextStyle(color: theme.secondaryText),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    dropdownColor: theme.secondaryBackground,
                    items: () {
                      return widget.categories
                          .map((c) => DropdownMenuItem(
                              value: c.reference.id, child: Text(c.name)))
                          .toList();
                    }(),
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.tertiary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.surfaceBorderColor,
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _descriptionController,
                    style: theme.bodyMedium,
                    maxLines: 2,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'Description (optional)',
                      hintStyle: TextStyle(
                        color: theme.secondaryText,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.tertiary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.surfaceBorderColor,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Priority:',
                        style: theme.bodyMedium,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Slider(
                          value: _priority.toDouble(),
                          min: 1.0,
                          max: 3.0,
                          divisions: 2,
                          label: _priority.toString(),
                          activeColor: theme.primary,
                          onChanged: (value) {
                            setState(() => _priority = value.round());
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconTaskTypeDropdown(
                      selectedValue: _selectedTrackingType ?? 'binary',
                      onChanged: (value) {
                        setState(() {
                          _selectedTrackingType = value;
                          if (value == 'binary') {
                            _targetNumber = 1;
                            _targetDuration = const Duration(hours: 1);
                            _unitController.clear();
                          }
                        });
                      },
                      tooltip: 'Select task type',
                    ),
                    // Date icon or chip
                    if (quickIsTaskRecurring) ...[
                      // For recurring tasks, show start date chip
                      if (_frequencyConfig?.startDate == null &&
                          widget.task.startDate == null)
                        _buildDateIconChip(
                          theme: theme,
                          onTap: _isStartDateReadOnly ? null : _pickStartDate,
                        )
                      else
                        _buildDateChip(
                          theme: theme,
                          date: _frequencyConfig?.startDate ??
                              widget.task.startDate!,
                          label:
                              'Start: ${DateFormat('MMM dd').format(_frequencyConfig?.startDate ?? widget.task.startDate!)}',
                          onTap: _isStartDateReadOnly ? null : _pickStartDate,
                          onClear: null, // Start date shouldn't be cleared
                        ),
                      // End date chip
                      if (_endDate == null)
                        _buildDateIconChip(
                          theme: theme,
                          onTap: _pickEndDate,
                          icon: Icons.event_busy,
                        )
                      else
                        _buildDateChip(
                          theme: theme,
                          date: _endDate!,
                          label:
                              'End: ${DateFormat('MMM dd').format(_endDate!)}',
                          onTap: _pickEndDate,
                          onClear: () {
                            setState(() => _endDate = null);
                          },
                        ),
                    ] else ...[
                      // For one-time tasks, show due date chip
                      if (_dueDate == null)
                        _buildDateIconChip(
                          theme: theme,
                          onTap: _pickDueDate,
                        )
                      else
                        _buildDateChip(
                          theme: theme,
                          date: _dueDate!,
                          label: DateFormat('MMM dd').format(_dueDate!),
                          onTap: _pickDueDate,
                          onClear: () {
                            setState(() => _dueDate = null);
                          },
                        ),
                    ],
                    // Time icon or chip
                    if (_selectedDueTime == null)
                      _buildTimeIconChip(
                        theme: theme,
                        onTap: _pickDueTime,
                      )
                    else
                      _buildTimeChip(
                        theme: theme,
                        time: _selectedDueTime!,
                        onTap: _pickDueTime,
                        onClear: () {
                          setState(() => _selectedDueTime = null);
                        },
                      ),
                    // Reminder icon or chip
                    if (_reminders.isEmpty)
                      _buildReminderIconChip(
                        theme: theme,
                        onTap: () async {
                          final reminders = await ReminderConfigDialog.show(
                            context: context,
                            initialReminders: _reminders,
                            dueTime: _selectedDueTime,
                          );
                          if (reminders != null) {
                            setState(() => _reminders = reminders);
                          }
                        },
                      )
                    else
                      _buildReminderChip(
                        theme: theme,
                        count: _reminders.length,
                        onTap: () async {
                          final reminders = await ReminderConfigDialog.show(
                            context: context,
                            initialReminders: _reminders,
                            dueTime: _selectedDueTime,
                          );
                          if (reminders != null) {
                            setState(() => _reminders = reminders);
                          }
                        },
                        onClear: () {
                          setState(() => _reminders = []);
                        },
                      ),
                    // Recurring icon or chip
                    if (!quickIsTaskRecurring || _frequencyConfig == null)
                      _buildRecurringIconChip(
                        theme: theme,
                        onTap: () async {
                          final config = await showFrequencyConfigDialog(
                            context: context,
                            initialConfig: _frequencyConfig ??
                                FrequencyConfig(
                                  type: FrequencyType.everyXPeriod,
                                  startDate: _dueDate ?? DateTime.now(),
                                ),
                          );
                          if (config != null) {
                            setState(() {
                              _frequencyConfig = config;
                              quickIsTaskRecurring = true;
                              if (_dueDate == null) {
                                _dueDate = config.startDate;
                              }
                            });
                          }
                        },
                      )
                    else
                      _buildRecurringChip(
                        theme: theme,
                        description: _getFrequencyDescription(),
                        onTap: () async {
                          final config = await showFrequencyConfigDialog(
                            context: context,
                            initialConfig: _frequencyConfig,
                          );
                          if (config != null) {
                            setState(() {
                              _frequencyConfig = config;
                            });
                          } else {
                            final shouldDisable = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Disable Recurring?'),
                                content: const Text(
                                    'Do you want to disable recurring for this task?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Disable'),
                                  ),
                                ],
                              ),
                            );
                            if (shouldDisable == true) {
                              setState(() {
                                quickIsTaskRecurring = false;
                                _frequencyConfig = null;
                              });
                            }
                          }
                        },
                        onClear: () {
                          setState(() {
                            quickIsTaskRecurring = false;
                            _frequencyConfig = null;
                          });
                        },
                      ),
                  ],
                ),
                if (_isStartDateReadOnly)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 8),
                    child: Text(
                      'Start date cannot be changed after instances are completed',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.secondaryText,
                      ),
                    ),
                  ),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        theme.surfaceBorderColor,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                if (_selectedTrackingType == 'quantitative') ...[
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.accent2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.surfaceBorderColor),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primary.withOpacity(0.05),
                          offset: const Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.track_changes,
                            size: 16, color: theme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Target:',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: TextEditingController(
                                text: _targetNumber.toString()),
                            style: theme.bodyMedium,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.surfaceBorderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.surfaceBorderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.accent1, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              isDense: true,
                              filled: true,
                              fillColor: theme.secondaryBackground,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              _targetNumber = int.tryParse(value) ?? 1;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Unit:',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _unitController,
                            style: theme.bodyMedium,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.surfaceBorderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.surfaceBorderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.accent1, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              hintText: 'e.g., pages, reps',
                              hintStyle: TextStyle(color: theme.secondaryText),
                              isDense: true,
                              filled: true,
                              fillColor: theme.secondaryBackground,
                            ),
                            onChanged: (value) => _unit = value,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_selectedTrackingType == 'time') ...[
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.accent2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.surfaceBorderColor),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primary.withOpacity(0.05),
                          offset: const Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.timer, size: 16, color: theme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Target Duration:',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: TextEditingController(
                                text: _targetDuration.inHours.toString()),
                            style: theme.bodyMedium,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.surfaceBorderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.surfaceBorderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.accent1, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              labelText: 'Hours',
                              labelStyle: TextStyle(color: theme.secondaryText),
                              isDense: true,
                              filled: true,
                              fillColor: theme.secondaryBackground,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final hours = int.tryParse(value) ?? 1;
                              setState(() => _targetDuration = Duration(
                                    hours: hours,
                                    minutes: _targetDuration.inMinutes % 60,
                                  ));
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: TextEditingController(
                                text: (_targetDuration.inMinutes % 60)
                                    .toString()),
                            style: theme.bodyMedium,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.surfaceBorderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.surfaceBorderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: theme.accent1, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              labelText: 'Minutes',
                              labelStyle: TextStyle(color: theme.secondaryText),
                              isDense: true,
                              filled: true,
                              fillColor: theme.secondaryBackground,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final minutes = int.tryParse(value) ?? 0;
                              setState(() => _targetDuration = Duration(
                                    hours: _targetDuration.inHours,
                                    minutes: minutes,
                                  ));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.instance != null && _instanceDueDate != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.tertiary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.surfaceBorderColor,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event, size: 16, color: theme.secondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Move this instance to: ${DateFormat('MMM dd').format(_instanceDueDate!)}',
                            style: theme.bodySmall,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.calendar_today,
                              size: 18, color: theme.secondary),
                          onPressed: _pickInstanceDueDate,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      child: Text(
                        'Cancel',
                        style: theme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        gradient: theme.primaryButtonGradient,
                        borderRadius: BorderRadius.circular(theme.buttonRadius),
                        boxShadow: [
                          BoxShadow(
                            color: theme.primary.withOpacity(0.15),
                            offset: const Offset(0, 2),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(theme.buttonRadius),
                          onTap: _save,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            child: Text(
                              'Save',
                              style: theme.bodyMedium.override(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateIconChip({
    required FlutterFlowTheme theme,
    required VoidCallback? onTap,
    IconData? icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.tertiary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon ?? Icons.calendar_today_outlined,
              color: theme.secondary,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateChip({
    required FlutterFlowTheme theme,
    required DateTime date,
    required String label,
    required VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.accent1.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.accent1, width: 1),
        boxShadow: [
          BoxShadow(
            color: theme.accent1.withOpacity(0.1),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today, size: 14, color: theme.accent1),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.accent1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (onClear != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onClear,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: theme.accent1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeIconChip({
    required FlutterFlowTheme theme,
    required VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.tertiary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.access_time_outlined,
              color: theme.secondary,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeChip({
    required FlutterFlowTheme theme,
    required TimeOfDay time,
    required VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.accent1.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.accent1, width: 1),
        boxShadow: [
          BoxShadow(
            color: theme.accent1.withOpacity(0.1),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time, size: 14, color: theme.accent1),
                const SizedBox(width: 6),
                Text(
                  TimeUtils.formatTimeOfDayForDisplay(time),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.accent1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (onClear != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onClear,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: theme.accent1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReminderIconChip({
    required FlutterFlowTheme theme,
    required VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.tertiary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.notifications_outlined,
              color: theme.secondary,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReminderChip({
    required FlutterFlowTheme theme,
    required int count,
    required VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.accent1.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.accent1, width: 1),
        boxShadow: [
          BoxShadow(
            color: theme.accent1.withOpacity(0.1),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications, size: 14, color: theme.accent1),
                const SizedBox(width: 6),
                Text(
                  '$count reminder${count == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.accent1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (onClear != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onClear,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: theme.accent1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecurringIconChip({
    required FlutterFlowTheme theme,
    required VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.tertiary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.repeat_outlined,
              color: theme.secondary,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecurringChip({
    required FlutterFlowTheme theme,
    required String description,
    required VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.accent1.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.accent1, width: 1),
        boxShadow: [
          BoxShadow(
            color: theme.accent1.withOpacity(0.1),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.repeat, size: 14, color: theme.accent1),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.accent1,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onClear != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onClear,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: theme.accent1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
