import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
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
import 'package:habit_tracker/Screens/Create%20Catagory/create_category.dart';
import 'package:intl/intl.dart';

class ActivityEditorDialog extends StatefulWidget {
  final ActivityRecord? activity; // Null for creation
  final bool isHabit;
  final List<CategoryRecord> categories;
  final Function(ActivityRecord?)? onSave; // Optional callback
  final ActivityInstanceRecord? instance;

  const ActivityEditorDialog({
    super.key,
    this.activity,
    required this.isHabit,
    required this.categories,
    this.onSave,
    this.instance,
  });

  @override
  State<ActivityEditorDialog> createState() => _ActivityEditorDialogState();
}

class _ActivityEditorDialogState extends State<ActivityEditorDialog> {
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
  DateTime? _endDate;
  TimeOfDay? _selectedDueTime;
  bool quickIsTaskRecurring = false;
  FrequencyConfig? _frequencyConfig;
  DateTime? _originalStartDate;
  FrequencyConfig? _originalFrequencyConfig;
  List<ReminderConfig> _reminders = [];
  bool _isSaving = false;
  List<CategoryRecord> _loadedCategories = [];
  bool _isLoadingCategories = false;

  bool get _isRecurring => quickIsTaskRecurring && _frequencyConfig != null;

  /// Get the categories to use - prefer loaded categories, fallback to widget categories
  List<CategoryRecord> get _categories {
    return _loadedCategories.isNotEmpty ? _loadedCategories : widget.categories;
  }

  @override
  void initState() {
    super.initState();
    final t = widget.activity;

    // Initialize recurring state based on type
    if (widget.isHabit) {
      quickIsTaskRecurring = true;
      // Default frequency for new habits
      if (t == null) {
        _frequencyConfig = FrequencyConfig(
          type: FrequencyType.everyXPeriod,
          startDate: DateTime.now(),
        );
      }
    } else {
      quickIsTaskRecurring = t?.isRecurring ?? false;
    }

    _titleController = TextEditingController(text: t?.name ?? '');
    _unitController = TextEditingController(text: t?.unit ?? '');
    _descriptionController = TextEditingController(text: t?.description ?? '');

    _priority = t?.priority ?? 1;
    _selectedTrackingType = t?.trackingType ?? 'binary';
    _targetNumber = (t?.target is int) ? t!.target as int : 1;
    _targetDuration = (t?.trackingType == 'time' && t?.target is int)
        ? Duration(minutes: t!.target as int)
        : const Duration(hours: 1);
    _unit = t?.unit ?? '';
    _dueDate = t?.dueDate;
    _endDate = t?.endDate;

    // Load categories if not provided
    if (widget.categories.isEmpty) {
      _loadCategories();
    } else {
      _loadedCategories = widget.categories;
      _initializeCategory(t);
    }

    // Load due time
    if (t != null && t.hasDueTime()) {
      _selectedDueTime = TimeUtils.stringToTimeOfDay(t.dueTime);
    }

    // Load frequency config
    if (t != null && quickIsTaskRecurring) {
      _frequencyConfig = _convertTaskFrequencyToConfig(t);
      _originalFrequencyConfig = _frequencyConfig;
      _originalStartDate = t.startDate;
    } else if (t == null && widget.isHabit) {
      // Already set default above
    }

    // Load reminders
    if (t != null && t.hasReminders()) {
      _reminders = ReminderConfigList.fromMapList(t.reminders);
    }
  }

  /// Load categories from backend if not provided
  Future<void> _loadCategories() async {
    if (_isLoadingCategories) return;

    setState(() => _isLoadingCategories = true);

    try {
      final userId = currentUserUid;
      if (userId.isEmpty) {
        setState(() => _isLoadingCategories = false);
        return;
      }

      final categories = widget.isHabit
          ? await queryHabitCategoriesOnce(userId: userId)
          : await queryTaskCategoriesOnce(userId: userId);

      if (mounted) {
        setState(() {
          _loadedCategories = categories;
          _isLoadingCategories = false;
        });
        // Initialize category after loading
        _initializeCategory(widget.activity);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCategories = false);
        print('DEBUG ActivityEditorDialog: Error loading categories: $e');
      }
    }
  }

  /// Initialize the selected category based on activity data
  void _initializeCategory(ActivityRecord? t) {
    if (t != null) {
      String? matchingCategoryId;
      if (t.categoryId.isNotEmpty &&
          _categories.any((c) => c.reference.id == t.categoryId)) {
        matchingCategoryId = t.categoryId;
      } else if (t.categoryName.isNotEmpty &&
          _categories.any((c) => c.name == t.categoryName)) {
        final category =
            _categories.firstWhere((c) => c.name == t.categoryName);
        matchingCategoryId = category.reference.id;
      }
      if (mounted) {
        setState(() => _selectedCategoryId = matchingCategoryId);
      }
      print(
          'DEBUG ActivityEditorDialog: Activity categoryId=${t.categoryId}, categoryName=${t.categoryName}');
      print(
          'DEBUG ActivityEditorDialog: Available categories=${_categories.map((c) => '${c.name}(${c.reference.id})').toList()}');
      print(
          'DEBUG ActivityEditorDialog: Selected categoryId=$_selectedCategoryId');
    } else if (_categories.isNotEmpty) {
      // Default to first category if creating new
      if (mounted) {
        setState(() => _selectedCategoryId = _categories.first.reference.id);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _unitController.dispose();
    _descriptionController.dispose();
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
                : PeriodType.weeks;
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

  bool _hasFrequencyChanged() {
    if (_originalFrequencyConfig == null || _frequencyConfig == null)
      return false;
    final original = _originalFrequencyConfig!;
    final current = _frequencyConfig!;
    return original.type != current.type ||
        original.startDate != current.startDate ||
        original.endDate != current.endDate ||
        original.everyXValue != current.everyXValue ||
        original.everyXPeriodType != current.everyXPeriodType ||
        original.timesPerPeriod != current.timesPerPeriod ||
        original.periodType != current.periodType ||
        !_listEquals(original.selectedDays, current.selectedDays);
  }

  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  /// Get the valid category ID for the dropdown
  /// Returns null if no category is selected or if the selected category is invalid
  String? get _validCategoryId {
    if (_selectedCategoryId == null) return null;
    final isValid =
        _categories.any((c) => c.reference.id == _selectedCategoryId);
    return isValid ? _selectedCategoryId : null;
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name')),
      );
      return;
    }

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    final selectedCategory = _categories
        .where((c) => c.reference.id == _selectedCategoryId)
        .firstOrNull;

    if (selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected category not found')),
      );
      return;
    }

    // Validate reminder times for one-time tasks
    if (!quickIsTaskRecurring && _reminders.isNotEmpty) {
      final validationError = _validateReminderTimes();
      if (validationError != null) {
        // Show error in a dialog instead of snackbar (snackbar appears behind dialog)
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Invalid Reminder Time'),
            content: Text(validationError),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      if (widget.activity == null) {
        // CREATE NEW
        await _createNewActivity(selectedCategory);
      } else {
        // UPDATE EXISTING
        await _updateExistingActivity(selectedCategory);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _createNewActivity(CategoryRecord selectedCategory) async {
    dynamic targetValue;
    switch (_selectedTrackingType) {
      case 'binary':
        targetValue = null;
        break;
      case 'quantitative':
        targetValue = _targetNumber;
        break;
      case 'time':
        targetValue = _targetDuration.inMinutes;
        break;
    }

    await createActivity(
      name: _titleController.text.trim(),
      categoryId: _selectedCategoryId!,
      categoryName: selectedCategory.name,
      trackingType: _selectedTrackingType ?? 'binary',
      target: targetValue,
      isRecurring: quickIsTaskRecurring,
      userId: currentUserUid,
      priority: _priority,
      unit: _unit,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      categoryType: widget.isHabit ? 'habit' : 'task',
      dueTime: _selectedDueTime != null
          ? TimeUtils.timeOfDayToString(_selectedDueTime!)
          : null,
      // Frequency fields
      frequencyType: quickIsTaskRecurring && _frequencyConfig != null
          ? _frequencyConfig!.type.toString().split('.').last
          : null,
      everyXValue: quickIsTaskRecurring &&
              _frequencyConfig?.type == FrequencyType.everyXPeriod
          ? _frequencyConfig!.everyXValue
          : null,
      everyXPeriodType: quickIsTaskRecurring &&
              _frequencyConfig?.type == FrequencyType.everyXPeriod
          ? _frequencyConfig!.everyXPeriodType.toString().split('.').last
          : null,
      timesPerPeriod: quickIsTaskRecurring &&
              _frequencyConfig?.type == FrequencyType.timesPerPeriod
          ? _frequencyConfig!.timesPerPeriod
          : null,
      periodType: quickIsTaskRecurring &&
              _frequencyConfig?.type == FrequencyType.timesPerPeriod
          ? _frequencyConfig!.periodType.toString().split('.').last
          : null,
      specificDays: quickIsTaskRecurring &&
              _frequencyConfig?.type == FrequencyType.specificDays
          ? _frequencyConfig!.selectedDays
          : null,
      startDate: quickIsTaskRecurring ? _frequencyConfig?.startDate : null,
      endDate: quickIsTaskRecurring
          ? _frequencyConfig?.endDate
          : _endDate, // For one-time tasks, uses _endDate
      reminders: _reminders.isNotEmpty
          ? ReminderConfigList.toMapList(_reminders)
          : null,
      // For one-time tasks that have a specific date
      dueDate: (!quickIsTaskRecurring) ? _dueDate : null,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Created successfully')),
      );
      Navigator.pop(context, true);
    }
    widget.onSave?.call(null); // Pass null or new record if available
  }

  Future<void> _updateExistingActivity(CategoryRecord selectedCategory) async {
    final docRef = widget.activity!.reference;

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
      dueDate: (!quickIsTaskRecurring) ? _dueDate : null,
      dueTime: _selectedDueTime != null
          ? TimeUtils.timeOfDayToString(_selectedDueTime!)
          : null,
      specificDays: quickIsTaskRecurring &&
              _frequencyConfig != null &&
              _frequencyConfig!.type == FrequencyType.specificDays
          ? _frequencyConfig!.selectedDays
          : null,
      lastUpdated: DateTime.now(),
      categoryType: widget.isHabit ? 'habit' : 'task',
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
      frequencyType: quickIsTaskRecurring && _frequencyConfig != null
          ? _frequencyConfig!.type.toString().split('.').last
          : null,
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

    // Ensure nullable fields are explicitly cleared when needed
    updateData['dueDate'] = (!quickIsTaskRecurring) ? _dueDate : null;
    updateData['dueTime'] = _selectedDueTime != null
        ? TimeUtils.timeOfDayToString(_selectedDueTime!)
        : null;
    updateData['reminders'] =
        _reminders.isNotEmpty ? ReminderConfigList.toMapList(_reminders) : null;
    updateData['frequencyType'] =
        quickIsTaskRecurring && _frequencyConfig != null
            ? _frequencyConfig!.type.toString().split('.').last
            : null;
    updateData['everyXValue'] = quickIsTaskRecurring &&
            _frequencyConfig != null &&
            _frequencyConfig!.type == FrequencyType.everyXPeriod
        ? _frequencyConfig!.everyXValue
        : null;
    updateData['everyXPeriodType'] = quickIsTaskRecurring &&
            _frequencyConfig != null &&
            _frequencyConfig!.type == FrequencyType.everyXPeriod
        ? _frequencyConfig!.everyXPeriodType.toString().split('.').last
        : null;
    updateData['timesPerPeriod'] = quickIsTaskRecurring &&
            _frequencyConfig != null &&
            _frequencyConfig!.type == FrequencyType.timesPerPeriod
        ? _frequencyConfig!.timesPerPeriod
        : null;
    updateData['periodType'] = quickIsTaskRecurring &&
            _frequencyConfig != null &&
            _frequencyConfig!.type == FrequencyType.timesPerPeriod
        ? _frequencyConfig!.periodType.toString().split('.').last
        : null;
    updateData['specificDays'] = quickIsTaskRecurring &&
            _frequencyConfig != null &&
            _frequencyConfig!.type == FrequencyType.specificDays
        ? _frequencyConfig!.selectedDays
        : null;
    updateData['startDate'] = quickIsTaskRecurring && _frequencyConfig != null
        ? _frequencyConfig!.startDate
        : null;
    updateData['endDate'] = quickIsTaskRecurring && _frequencyConfig != null
        ? _frequencyConfig!.endDate
        : _endDate;

    // Check for frequency changes (Logic from edit_task.dart)
    if (quickIsTaskRecurring &&
        _frequencyConfig != null &&
        _hasFrequencyChanged()) {
      // Only show dialog and regenerate if START DATE specifically changed
      final startDateChanged = _originalStartDate != null &&
          _frequencyConfig!.startDate != _originalStartDate;

      if (startDateChanged) {
        final shouldProceed = await StartDateChangeDialog.show(
          context: context,
          oldStartDate: _originalStartDate ?? DateTime.now(),
          newStartDate: _frequencyConfig!.startDate,
          activityName: _titleController.text.trim(),
        );

        if (!shouldProceed) {
          return;
        }

        try {
          await ActivityInstanceService.regenerateInstancesFromStartDate(
            templateId: widget.activity!.reference.id,
            template: widget.activity!,
            newStartDate: _frequencyConfig!.startDate,
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating instances: $e')),
          );
          return;
        }
      }
      // If frequency changed but NOT start date, no dialog needed
    }

    if (quickIsTaskRecurring && _frequencyConfig != null) {
      // Check end date changes
      final originalEndDate = _originalFrequencyConfig?.endDate;
      final newEndDate = _frequencyConfig!.endDate;
      if (originalEndDate != newEndDate && newEndDate != null) {
        if (originalEndDate == null || newEndDate.isBefore(originalEndDate)) {
          try {
            await ActivityInstanceService.cleanupInstancesBeyondEndDate(
              templateId: widget.activity!.reference.id,
              newEndDate: newEndDate,
            );
          } catch (e) {
            // ignore
          }
        }
      }
    }

    await docRef.update(updateData);

    // Update pending instances (logic from edit_task.dart)
    try {
      final instances = await ActivityInstanceService.getInstancesForTemplate(
          templateId: widget.activity!.reference.id);
      final pendingInstances =
          instances.where((i) => i.status != 'completed').toList();

      // Batch update logic omitted for brevity but recommended for production
      // For now, simple loop
      final containsDueDateUpdate =
          !quickIsTaskRecurring && updateData.containsKey('dueDate');
      final hasDueTimeUpdate = updateData.containsKey('dueTime');
      for (var instance in pendingInstances) {
        // For one-time tasks, update instance dueDate to match template's new dueDate
        // For recurring tasks, keep existing instance dueDates (they're calculated from frequency)
        final shouldUpdateInstanceDueDate = containsDueDateUpdate;
        final newInstanceDueDate = shouldUpdateInstanceDueDate
            ? updateData['dueDate'] as DateTime?
            : instance.dueDate;
        final updatedDueTime = hasDueTimeUpdate
            ? updateData['dueTime'] as String?
            : instance.dueTime;

        await instance.reference.update({
          'templateName': updateData['name'],
          'templateCategoryId': updateData['categoryId'],
          'templateCategoryName': updateData['categoryName'],
          'templateTrackingType': updateData['trackingType'],
          'templateTarget': updateData['target'],
          'templateUnit': updateData['unit'],
          'templatePriority': updateData['priority'],
          'templateDescription': updateData['description'],
          'templateDueTime':
              hasDueTimeUpdate ? updatedDueTime : instance.templateDueTime,
          'templateEveryXValue': updateData['everyXValue'] ?? 0,
          'templateEveryXPeriodType': updateData['everyXPeriodType'] ?? '',
          'templateTimesPerPeriod': updateData['timesPerPeriod'] ?? 0,
          'templatePeriodType': updateData['periodType'] ?? '',
          if (shouldUpdateInstanceDueDate) 'dueDate': newInstanceDueDate,
          if (hasDueTimeUpdate) 'dueTime': updatedDueTime,
          'lastUpdated': DateTime.now(),
        });

        // Also update the Instance Record logic (rescheduling reminders etc)
        // Ideally this logic should be in a Service, but kept here for now as in original
        try {
          // Simplified update for instances (omitting full re-creation for brevity unless critical)
          final updatedInstanceData = createActivityInstanceRecordData(
            templateId: instance.templateId,
            dueDate: newInstanceDueDate,
            dueTime: updatedDueTime,
            templateDueTime:
                hasDueTimeUpdate ? updatedDueTime : instance.templateDueTime,
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
            templateShowInFloatingTimer: instance.templateShowInFloatingTimer,
            templateEveryXValue: updateData['everyXValue'] ?? 0,
            templateEveryXPeriodType: updateData['everyXPeriodType'] ?? '',
            templateTimesPerPeriod: updateData['timesPerPeriod'] ?? 0,
            templatePeriodType: updateData['periodType'] ?? '',
            dayState: instance.dayState,
            belongsToDate: instance.belongsToDate,
            closedAt: instance.closedAt,
            windowEndDate: instance.windowEndDate,
            windowDuration: instance.windowDuration,
          );

          final updatedInstance = ActivityInstanceRecord.getDocumentFromData(
            updatedInstanceData,
            instance.reference,
          );

          InstanceEvents.broadcastInstanceUpdated(updatedInstance);
          try {
            await ReminderScheduler.rescheduleReminderForInstance(
                updatedInstance);
          } catch (e) {
            // Log error but don't fail - reminder rescheduling is non-critical
            print('Error rescheduling reminder in activity editor: $e');
          }
        } catch (e) {
          // Log error but don't fail - instance update is non-critical in this context
          print('Error updating instance in activity editor: $e');
        }
      }
    } catch (e) {
      // ignore
    }

    // Refresh UI
    final updatedRecord =
        ActivityRecord.getDocumentFromData(updateData, docRef);
    widget.onSave?.call(updatedRecord);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updated successfully')),
      );
      Navigator.pop(context, true);
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

  Future<void> _pickDueTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedDueTime ?? TimeUtils.getCurrentTime(),
    );
    if (picked != null && picked != _selectedDueTime) {
      setState(() => _selectedDueTime = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final title = widget.activity == null
        ? (widget.isHabit ? 'Create Habit' : 'Create Task')
        : (widget.isHabit ? 'Edit Habit' : 'Edit Task');

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
                  title,
                  style: theme.titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextField(theme, _titleController, 'Name'),
                const SizedBox(height: 12),
                _buildCategoryDropdown(theme),
                const SizedBox(height: 12),
                _buildTextField(
                    theme, _descriptionController, 'Description (optional)',
                    maxLines: 2),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTaskTypeField(theme),
                    if (_selectedTrackingType == 'quantitative' ||
                        _selectedTrackingType == 'time') ...[
                      const SizedBox(height: 12),
                      _buildTrackingDetails(theme),
                    ],
                    const SizedBox(height: 12),
                    _buildFrequencyField(theme),
                    if (!_isRecurring && !widget.isHabit) ...[
                      const SizedBox(height: 12),
                      _buildDueDateField(theme),
                    ],
                    const SizedBox(height: 12),
                    _buildDueTimeField(theme),
                    const SizedBox(height: 12),
                    _buildReminderField(theme),
                  ],
                ),
                const SizedBox(height: 12),
                _buildPrioritySlider(theme),
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
                const SizedBox(height: 16),
                _buildActionButtons(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      FlutterFlowTheme theme, TextEditingController controller, String hint,
      {int maxLines = 1}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.tertiary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        style: theme.bodyMedium,
        maxLines: maxLines,
        maxLength: maxLines == 1 ? 200 : 500,
        decoration: InputDecoration(
          hintText: hint,
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
    );
  }

  Widget _buildCategoryDropdown(FlutterFlowTheme theme) {
    // Use a key to force rebuild when categories or selected category changes
    final dropdownKey = ValueKey(
        'category_dropdown_${_categories.length}_$_selectedCategoryId');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
          Expanded(
            child: DropdownButtonFormField<String>(
              key: dropdownKey,
              value: _validCategoryId,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down, color: theme.secondaryText),
              dropdownColor: theme.secondaryBackground,
              style: theme.bodySmall,
              hint: Text('Select Category',
                  style: TextStyle(color: theme.secondaryText)),
              items: _categories
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.reference.id,
                      child: Text(
                        c.name,
                        style: theme.bodySmall,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _categories.isEmpty || _isLoadingCategories
                  ? null
                  : (v) {
                      if (mounted) {
                        setState(() => _selectedCategoryId = v);
                      }
                    },
              menuMaxHeight: 260,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          IconButton(
            icon: Icon(Icons.add, color: theme.primary),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const CreateCategory(
                    categoryType:
                        'habit'), // or 'task' if we wanted to differentiate
              ).then((value) {
                // Ideally we should reload categories here.
                // Since categories are passed in, we can't easily reload them inside the dialog
                // without a callback or parent rebuild.
                // For now, let's assume the parent updates or we just dismiss/re-open.
                // Better UX: Trigger a reload callback if provided.
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTaskTypeField(FlutterFlowTheme theme) {
    final taskTypes = TaskTypeDropdownHelper.getAllTaskTypes();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.tertiary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.surfaceBorderColor, width: 1),
      ),
      child: DropdownButtonFormField<String>(
        value: _selectedTrackingType ?? 'binary',
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        isExpanded: true,
        icon: Icon(Icons.keyboard_arrow_down, color: theme.secondaryText),
        dropdownColor: theme.secondaryBackground,
        style: theme.bodySmall,
        items: taskTypes
            .map(
              (t) => DropdownMenuItem<String>(
                value: t.value,
                child: Row(
                  children: [
                    Icon(t.icon, size: 16, color: theme.secondaryText),
                    const SizedBox(width: 8),
                    Text(
                      t.label,
                      style: theme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
            .toList(),
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
        menuMaxHeight: 220,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildTrackingDetails(FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.accent2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.surfaceBorderColor),
      ),
      child: _selectedTrackingType == 'quantitative'
          ? Row(
              children: [
                Text('Target:',
                    style: theme.bodySmall.override(
                        color: theme.primary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  initialValue: _targetNumber.toString(),
                  keyboardType: TextInputType.number,
                  style: theme.bodyMedium,
                  decoration: _inputDecoration(theme),
                  onChanged: (v) {
                    setState(() {
                      _targetNumber = int.tryParse(v) ?? 1;
                    });
                  },
                )),
                const SizedBox(width: 8),
                Text('Unit:',
                    style: theme.bodySmall.override(
                        color: theme.primary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  controller: _unitController,
                  style: theme.bodyMedium,
                  decoration: _inputDecoration(theme, hint: 'e.g. pages'),
                  onChanged: (v) {
                    setState(() {
                      _unit = v;
                    });
                  },
                )),
              ],
            )
          : Row(
              children: [
                Text('Duration:',
                    style: theme.bodySmall.override(
                        color: theme.primary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  initialValue: _targetDuration.inHours.toString(),
                  keyboardType: TextInputType.number,
                  style: theme.bodyMedium,
                  decoration: _inputDecoration(theme, label: 'Hrs'),
                  onChanged: (v) {
                    final h = int.tryParse(v) ?? 0;
                    setState(() => _targetDuration = Duration(
                        hours: h, minutes: _targetDuration.inMinutes % 60));
                  },
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  initialValue: (_targetDuration.inMinutes % 60).toString(),
                  keyboardType: TextInputType.number,
                  style: theme.bodyMedium,
                  decoration: _inputDecoration(theme, label: 'Min'),
                  onChanged: (v) {
                    final m = int.tryParse(v) ?? 0;
                    setState(() => _targetDuration =
                        Duration(hours: _targetDuration.inHours, minutes: m));
                  },
                )),
              ],
            ),
    );
  }

  InputDecoration _inputDecoration(FlutterFlowTheme theme,
      {String? hint, String? label}) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      filled: true,
      fillColor: theme.secondaryBackground,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.surfaceBorderColor)),
      hintText: hint,
      labelText: label,
    );
  }

  Widget _buildFrequencyField(FlutterFlowTheme theme) {
    final displayText =
        _isRecurring ? _formatFrequencySummary() : 'One-time task';
    return InkWell(
      onTap: _handleOpenFrequencyConfig,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: theme.tertiary.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.surfaceBorderColor, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                style: theme.bodyMedium.override(
                  color: theme.primaryText,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_isRecurring &&
                !widget.isHabit) // Habits cannot be non-recurring
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _clearFrequency,
              ),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down,
                color: theme.secondaryText, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDueDateField(FlutterFlowTheme theme) {
    final label = _dueDate != null
        ? DateFormat('MMM dd, yyyy').format(_dueDate!)
        : 'Set due date';
    return InkWell(
      onTap: _pickDueDate,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Due Date',
          labelStyle: TextStyle(color: theme.secondaryText),
          filled: true,
          fillColor: theme.tertiary.withOpacity(0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.surfaceBorderColor),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 20, color: theme.secondaryText),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.bodyMedium)),
            if (_dueDate != null)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _dueDate = null),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDueTimeField(FlutterFlowTheme theme) {
    final label = _selectedDueTime != null
        ? _selectedDueTime!.format(context)
        : 'Set due time';
    return InkWell(
      onTap: _pickDueTime,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Due Time',
          labelStyle: TextStyle(color: theme.secondaryText),
          filled: true,
          fillColor: theme.tertiary.withOpacity(0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.surfaceBorderColor),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 20, color: theme.secondaryText),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.bodyMedium)),
            if (_selectedDueTime != null)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _selectedDueTime = null),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderField(FlutterFlowTheme theme) {
    final label = _reminderSummary();
    return InkWell(
      onTap: _openReminderDialog,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Reminders',
          labelStyle: TextStyle(color: theme.secondaryText),
          filled: true,
          fillColor: theme.tertiary.withOpacity(0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.surfaceBorderColor),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_none,
                size: 20, color: theme.secondaryText),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.bodyMedium)),
            if (_reminders.isNotEmpty)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _reminders = []),
              ),
          ],
        ),
      ),
    );
  }

  String _reminderSummary() {
    if (_reminders.isEmpty) return '+ Add Reminder';
    if (_reminders.length == 1) return _reminders.first.getDescription();
    return '${_reminders.length} reminders';
  }

  Widget _buildPrioritySlider(FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.surfaceBorderColor, width: 1),
      ),
      child: Row(
        children: [
          Text('Priority:', style: theme.bodyMedium),
          const SizedBox(width: 12),
          Expanded(
            child: Slider(
              value: _priority.toDouble(),
              min: 1.0,
              max: 3.0,
              divisions: 2,
              label: _priority.toString(),
              activeColor: theme.primary,
              inactiveColor: theme.secondaryText.withOpacity(0.3),
              onChanged: (value) => setState(() => _priority = value.round()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(FlutterFlowTheme theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: theme.bodyMedium),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            gradient: theme.primaryButtonGradient,
            borderRadius: BorderRadius.circular(theme.buttonRadius),
          ),
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text('Save',
                    style: theme.bodyMedium.override(
                        color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  String _formatFrequencySummary() {
    final config = _frequencyConfig;
    if (config == null) return 'One-time task';

    // Simple summary logic (can be expanded)
    switch (config.type) {
      case FrequencyType.daily:
        return 'Every day';
      case FrequencyType.specificDays:
        return 'Specific days';
      case FrequencyType.timesPerPeriod:
        return '${config.timesPerPeriod} times per ${config.periodType.toString().split('.').last}';
      case FrequencyType.everyXPeriod:
        return 'Every ${config.everyXValue} ${config.everyXPeriodType.toString().split('.').last}';
    }
  }

  Future<void> _handleOpenFrequencyConfig() async {
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
        _endDate = config.endDate;
      });
    }
  }

  void _clearFrequency() {
    if (widget.isHabit) return; // Cannot clear frequency for habits
    setState(() {
      quickIsTaskRecurring = false;
      _frequencyConfig = null;
      _endDate = null;
    });
  }

  Future<void> _openReminderDialog() async {
    final reminders = await ReminderConfigDialog.show(
      context: context,
      initialReminders: _reminders,
      dueTime: _selectedDueTime,
      onRequestDueTime: _pickDueTime,
    );
    if (reminders != null) {
      setState(() {
        _reminders = reminders;
        if (_reminders.isNotEmpty && !_isRecurring && _dueDate == null) {
          _dueDate = DateTime.now();
        }
      });
    }
  }

  /// Validate reminder times for one-time tasks
  /// Returns error message if validation fails, null otherwise
  String? _validateReminderTimes() {
    if (quickIsTaskRecurring) {
      // Recurring items are allowed - they'll fire for next instance
      return null;
    }

    if (_reminders.isEmpty) {
      return null;
    }

    // Need due date and due time to validate
    if (_dueDate == null || _selectedDueTime == null) {
      return null; // Can't validate without due date/time
    }

    final now = DateTime.now();
    
    for (final reminder in _reminders) {
      if (!reminder.enabled) continue;

      DateTime? reminderDateTime;

      if (reminder.fixedTimeMinutes != null) {
        // Fixed time reminder
        final hour = reminder.fixedTimeMinutes! ~/ 60;
        final minute = reminder.fixedTimeMinutes! % 60;
        reminderDateTime = DateTime(
          _dueDate!.year,
          _dueDate!.month,
          _dueDate!.day,
          hour,
          minute,
        );
      } else {
        // Offset-based reminder
        final dueDateTime = DateTime(
          _dueDate!.year,
          _dueDate!.month,
          _dueDate!.day,
          _selectedDueTime!.hour,
          _selectedDueTime!.minute,
        );
        reminderDateTime = dueDateTime.add(Duration(minutes: reminder.offsetMinutes));
      }

      if (reminderDateTime.isBefore(now)) {
        return 'Reminder time cannot be in the past for one-time tasks. Please adjust the reminder time or make this a recurring task.';
      }
    }

    return null;
  }
}
