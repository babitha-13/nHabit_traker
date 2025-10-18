import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_dialog.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/start_date_change_dialog.dart';

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
  String? _selectedCategoryId;
  String? _selectedTrackingType;
  int _targetNumber = 1;
  Duration _targetDuration = const Duration(hours: 1);
  String _unit = '';
  DateTime? _dueDate;
  DateTime? _instanceDueDate;
  DateTime? _endDate;
  bool quickIsTaskRecurring = false;
  FrequencyConfig? _frequencyConfig;
  bool _isStartDateReadOnly = false;
  DateTime? _originalStartDate; // Track original start date for comparison

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleController = TextEditingController(text: t.name);
    _unitController = TextEditingController(text: t.unit);

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

    print('DEBUG: Task category ID: ${t.categoryId}');
    print('DEBUG: Task category Name: ${t.categoryName}');
    print(
        'DEBUG: Available categories: ${widget.categories.map((c) => '${c.name} (${c.reference.id})').toList()}');
    print('DEBUG: Selected category ID: $_selectedCategoryId');

    _selectedTrackingType = t.trackingType;
    _targetNumber = t.target is int ? t.target as int : 1;
    _targetDuration = t.trackingType == 'time'
        ? Duration(minutes: t.target as int)
        : const Duration(hours: 1);
    _unit = t.unit;
    _dueDate = t.dueDate;
    _endDate = t.endDate;

    // Load instance data if provided
    if (widget.instance != null) {
      _instanceDueDate = widget.instance!.dueDate;
    }

    // Load existing frequency configuration
    quickIsTaskRecurring = t.isRecurring;
    if (quickIsTaskRecurring) {
      _frequencyConfig = _convertTaskFrequencyToConfig(t);
    }

    // Store original start date for comparison
    _originalStartDate = t.startDate;

    // Check if start date should be read-only
    _checkStartDateReadOnly();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _unitController.dispose();
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

  void _save() async {
    // Validate required fields
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    final docRef = widget.task.reference;

    print('DEBUG: Starting save operation');
    print('DEBUG: quickIsTaskRecurring: $quickIsTaskRecurring');
    print('DEBUG: _frequencyConfig: $_frequencyConfig');
    print('DEBUG: _endDate: $_endDate');
    print('DEBUG: _selectedCategoryId: $_selectedCategoryId');
    print(
        'DEBUG: Available categories: ${widget.categories.map((c) => '${c.name} (${c.reference.id})').toList()}');

    // Handle instance due date change if applicable
    if (widget.instance != null && _instanceDueDate != null) {
      final originalInstanceDueDate = widget.instance!.dueDate;
      if (originalInstanceDueDate != _instanceDueDate) {
        try {
          print(
              'DEBUG: Moving instance from $originalInstanceDueDate to $_instanceDueDate');
          await ActivityInstanceService.rescheduleInstance(
            instanceId: widget.instance!.reference.id,
            newDueDate: _instanceDueDate!,
          );
          print('DEBUG: Instance due date updated successfully');
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
    print('DEBUG: Looking for category with ID: $_selectedCategoryId');
    final selectedCategory = widget.categories
        .where((c) => c.reference.id == _selectedCategoryId)
        .firstOrNull;

    print('DEBUG: Found category: ${selectedCategory?.name}');

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
      specificDays: quickIsTaskRecurring &&
              _frequencyConfig != null &&
              _frequencyConfig!.type == FrequencyType.specificDays
          ? _frequencyConfig!.selectedDays
          : null,
      lastUpdated: DateTime.now(),
      categoryType: 'task',
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

    print('DEBUG: About to update template with data: $updateData');

    // Check if start date has changed for recurring tasks
    if (quickIsTaskRecurring && _frequencyConfig != null) {
      final newStartDate = _frequencyConfig!.startDate;
      if (_originalStartDate != newStartDate) {
        print(
            'DEBUG: Start date changed from $_originalStartDate to $newStartDate');

        // Show confirmation dialog
        final shouldProceed = await StartDateChangeDialog.show(
          context: context,
          oldStartDate: _originalStartDate ?? DateTime.now(),
          newStartDate: newStartDate,
          activityName: _titleController.text.trim(),
        );

        if (!shouldProceed) {
          print('DEBUG: User cancelled start date change');
          return; // Abort save operation
        }

        // Regenerate instances with new start date
        try {
          await ActivityInstanceService.regenerateInstancesFromStartDate(
            templateId: widget.task.reference.id,
            template: widget.task,
            newStartDate: newStartDate,
          );
          print('DEBUG: Instances regenerated successfully');
        } catch (e) {
          print('ERROR: Failed to regenerate instances: $e');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating instances: $e')),
          );
          return;
        }
      }
    }

    try {
      await docRef.update(updateData);
      print('DEBUG: Template updated successfully');

      // Update all pending instances with new template data (with error handling)
      try {
        print('DEBUG: Fetching instances for template');
        final instances = await ActivityInstanceService.getInstancesForTemplate(
            templateId: widget.task.reference.id);

        final pendingInstances =
            instances.where((i) => i.status != 'completed').toList();
        print(
            'DEBUG: Found ${pendingInstances.length} pending instances to update');

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
              print('DEBUG: Updating instance ${instance.reference.id}');
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
                'lastUpdated': DateTime.now(),
              });

              // Create updated instance record and broadcast event immediately
              final updatedInstanceData = createActivityInstanceRecordData(
                templateId: instance.templateId,
                dueDate: instance.dueDate,
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

              print(
                  'DEBUG: Instance ${instance.reference.id} updated and event broadcasted successfully');
              return true;
            } catch (e) {
              print(
                  'ERROR: Failed to update instance ${instance.reference.id}: $e');
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

        print(
            'DEBUG: Instance update summary: $successCount successful, $failureCount failed');
        print('DEBUG: All instance updates and events completed');
      } catch (e) {
        print('Error updating instances: $e');
        // Don't fail the entire save operation if instance updates fail
      }

      final updatedHabit =
          ActivityRecord.getDocumentFromData(updateData, docRef);
      print('DEBUG: Save completed successfully');
      print(
          'DEBUG: Updated habit category: ${updatedHabit.categoryId} - ${updatedHabit.categoryName}');

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
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
      ),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Edit Task',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Task name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: () {
                    if (_selectedCategoryId == null) return null;
                    final isValid = widget.categories
                        .any((c) => c.reference.id == _selectedCategoryId);
                    print(
                        'DEBUG: Dropdown value check - selectedId: $_selectedCategoryId, isValid: $isValid');
                    return isValid ? _selectedCategoryId : null;
                  }(),
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  items: () {
                    // Debug: Check for duplicate IDs
                    final categoryIds =
                        widget.categories.map((c) => c.reference.id).toList();
                    final duplicateIds = categoryIds
                        .where((id) =>
                            categoryIds.indexOf(id) !=
                            categoryIds.lastIndexOf(id))
                        .toList();
                    if (duplicateIds.isNotEmpty) {
                      print(
                          'DEBUG: Duplicate category IDs found: $duplicateIds');
                    }
                    print(
                        'DEBUG: Category dropdown items: ${widget.categories.map((c) => '${c.name} -> ${c.reference.id}').toList()}');
                    return widget.categories
                        .map((c) => DropdownMenuItem(
                            value: c.reference.id, child: Text(c.name)))
                        .toList();
                  }(),
                  onChanged: (v) => setState(() => _selectedCategoryId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedTrackingType,
                  decoration: InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'binary', child: Text('To-do')),
                    DropdownMenuItem(value: 'quantitative', child: Text('Qty')),
                    DropdownMenuItem(value: 'time', child: Text('Time')),
                  ],
                  onChanged: (v) => setState(() => _selectedTrackingType = v),
                ),
                const SizedBox(height: 12),
                if (_selectedTrackingType == 'quantitative') ...[
                  TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Target',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    controller:
                        TextEditingController(text: _targetNumber.toString()),
                    onChanged: (v) => _targetNumber = int.tryParse(v) ?? 1,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _unitController,
                    decoration: InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onChanged: (v) => _unit = v,
                  ),
                ],
                if (_selectedTrackingType == 'time') ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Hours',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          controller: TextEditingController(
                              text: _targetDuration.inHours.toString()),
                          onChanged: (v) {
                            final h = int.tryParse(v) ?? 1;
                            setState(() => _targetDuration = Duration(
                                hours: h,
                                minutes: _targetDuration.inMinutes % 60));
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Minutes',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          controller: TextEditingController(
                              text:
                                  (_targetDuration.inMinutes % 60).toString()),
                          onChanged: (v) {
                            final m = int.tryParse(v) ?? 0;
                            setState(() => _targetDuration = Duration(
                                hours: _targetDuration.inHours, minutes: m));
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Date fields - different layout for recurring vs one-time tasks
                if (quickIsTaskRecurring) ...[
                  // Recurring tasks: Show start date, end date, and next due date
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Start Date: ${widget.task.startDate != null ? "${widget.task.startDate!.day}/${widget.task.startDate!.month}/${widget.task.startDate!.year}" : "None"}',
                          style: TextStyle(
                            color: _isStartDateReadOnly ? Colors.grey : null,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: _isStartDateReadOnly ? null : _pickStartDate,
                      ),
                    ],
                  ),
                  if (_isStartDateReadOnly)
                    const Padding(
                      padding: EdgeInsets.only(left: 16, bottom: 8),
                      child: Text(
                        'Start date cannot be changed after instances are completed',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'End Date: ${_endDate != null ? "${_endDate!.day}/${_endDate!.month}/${_endDate!.year}" : "Perpetual"}',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: _pickEndDate,
                      ),
                    ],
                  ),
                  if (widget.instance != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Move this instance to: ${_instanceDueDate != null ? "${_instanceDueDate!.day}/${_instanceDueDate!.month}/${_instanceDueDate!.year}" : "None"}',
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: _pickInstanceDueDate,
                        ),
                      ],
                    ),
                  ],
                ] else ...[
                  // One-time tasks: Show simple due date
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Due Date: ${_dueDate != null ? "${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}" : "None"}',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: _pickDueDate,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recurring: ${quickIsTaskRecurring ? "Yes" : "No"}',
                      ),
                    ),
                    Transform.scale(
                      scale: 0.7,
                      child: Switch(
                        value: quickIsTaskRecurring,
                        onChanged: (val) async {
                          if (val) {
                            // Opening recurring - show frequency config
                            final config = await showFrequencyConfigDialog(
                              context: context,
                              initialConfig: _frequencyConfig,
                            );
                            if (config != null) {
                              setState(() {
                                _frequencyConfig = config;
                                quickIsTaskRecurring = true;
                              });
                            }
                          } else {
                            // Closing recurring - clear config
                            setState(() {
                              quickIsTaskRecurring = false;
                              _frequencyConfig = null;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (quickIsTaskRecurring && _frequencyConfig != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      // Reopen frequency config dialog to edit
                      final config = await showFrequencyConfigDialog(
                        context: context,
                        initialConfig: _frequencyConfig,
                      );
                      if (config != null) {
                        setState(() {
                          _frequencyConfig = config;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.repeat,
                              size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _getFrequencyDescription(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: _save, child: const Text('Save')),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
