import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_dialog.dart';

class EditTask extends StatefulWidget {
  final ActivityRecord task;
  final List<CategoryRecord> categories;
  final Function(ActivityRecord) onSave;

  const EditTask({
    super.key,
    required this.task,
    required this.categories,
    required this.onSave,
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
  bool quickIsTaskRecurring = false;
  FrequencyConfig? _frequencyConfig;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleController = TextEditingController(text: t.name);
    _unitController = TextEditingController(text: t.unit);
    _selectedCategoryId = t.categoryId;
    _selectedTrackingType = t.trackingType;
    _targetNumber = t.target is int ? t.target as int : 1;
    _targetDuration = t.trackingType == 'time'
        ? Duration(minutes: t.target as int)
        : const Duration(hours: 1);
    _unit = t.unit;
    _dueDate = t.dueDate;

    // Load existing frequency configuration
    quickIsTaskRecurring = t.isRecurring;
    if (quickIsTaskRecurring) {
      _frequencyConfig = _convertTaskFrequencyToConfig(t);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _unitController.dispose();
    super.dispose();
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
    final docRef = widget.task.reference;

    final updateData = createActivityRecordData(
      isRecurring: quickIsTaskRecurring,
      name: _titleController.text.trim(),
      categoryId: _selectedCategoryId,
      categoryName: widget.categories
          .firstWhere((c) => c.reference.id == _selectedCategoryId)
          .name,
      trackingType: _selectedTrackingType,
      unit: _unit,
      target: _selectedTrackingType == 'quantitative'
          ? _targetNumber
          : _selectedTrackingType == 'time'
              ? _targetDuration.inMinutes
              : null,
      dueDate: _dueDate,
      schedule: null, // Deprecated
      frequency: null, // Deprecated
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
          : null,

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
    try {
      await docRef.update(updateData);

      // Update all pending instances with new template data
      final instances = await ActivityInstanceService.getInstancesForTemplate(
          templateId: widget.task.reference.id);

      for (final instance in instances.where((i) => i.status != 'completed')) {
        await instance.reference.update({
          'templateName': updateData['name'],
          'templateCategoryId': updateData['categoryId'],
          'templateCategoryName': updateData['categoryName'],
          'templateTrackingType': updateData['trackingType'],
          'templateTarget': updateData['target'],
          'templateUnit': updateData['unit'],
          'lastUpdated': DateTime.now(),
        });
      }

      final updatedHabit =
          ActivityRecord.getDocumentFromData(updateData, docRef);
      widget.onSave(updatedHabit);
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
                  value: widget.categories
                          .any((c) => c.reference.id == _selectedCategoryId)
                      ? _selectedCategoryId
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  items: widget.categories
                      .map((c) => DropdownMenuItem(
                          value: c.reference.id, child: Text(c.name)))
                      .toList(),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${quickIsTaskRecurring ? "Starting Date" : "Due Date"}: ${_dueDate != null ? "${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}" : "None"}',
                      ),
                    ),
                    IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: _pickDueDate),
                  ],
                ),
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
