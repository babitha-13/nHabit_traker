import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_dialog.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_widget.dart';
import 'package:habit_tracker/Helper/utils/start_date_change_dialog.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Helper/utils/reminder_config.dart';
import 'package:habit_tracker/Helper/utils/reminder_config_dialog.dart';
import 'package:habit_tracker/Screens/Create%20Catagory/create_category.dart';

class createActivityPage extends StatefulWidget {
  final ActivityRecord? habitToEdit;
  const createActivityPage({super.key, this.habitToEdit});
  @override
  State<createActivityPage> createState() => _createActivityPageState();
}

class _createActivityPageState extends State<createActivityPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _unitController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _selectedCategoryId;
  String? _selectedTrackingType;
  List<CategoryRecord> _categories = [];
  bool _isLoading = true;
  bool _isSaving = false;
  int weight = 1;
  int _targetNumber = 1;
  Duration _targetDuration = const Duration(hours: 1);
  late FrequencyConfig _frequencyConfig;
  // Date range fields
  DateTime _startDate = DateTime.now();
  DateTime? _endDate; // null means perpetual (will be set to 2099 in backend)
  DateTime? _originalStartDate; // Track original start date for comparison
  // Due time field
  TimeOfDay? _selectedDueTime;
  List<ReminderConfig> _reminders = [];
  FrequencyConfig?
      _originalFrequencyConfig; // Track original frequency config for comparison
  @override
  void initState() {
    super.initState();
    _loadCategories();
    _frequencyConfig = FrequencyConfig(type: FrequencyType.everyXPeriod);
    if (widget.habitToEdit != null) {
      final habit = widget.habitToEdit!;
      _nameController.text = habit.name;
      _unitController.text = habit.unit;
      _descriptionController.text = habit.description;
      _selectedCategoryId = habit.categoryId;
      _selectedTrackingType = habit.trackingType;
      weight = habit.priority;
      if (habit.trackingType == 'quantitative') {
        _targetNumber = habit.target ?? 1;
      } else if (habit.trackingType == 'time') {
        final minutes = habit.target ?? 60;
        _targetDuration = Duration(minutes: minutes);
      }
      // Load date fields if editing existing habit
      _startDate = habit.startDate ?? DateTime.now();
      _originalStartDate =
          habit.startDate; // Store original start date for comparison
      _endDate = habit.endDate;
      // If endDate is 2099 or later, treat as perpetual (set to null)
      if (_endDate != null && _endDate!.year >= 2099) {
        _endDate = null;
      }
      // Load due time if editing existing habit
      if (habit.hasDueTime()) {
        _selectedDueTime = TimeUtils.stringToTimeOfDay(habit.dueTime);
      }
      // Convert legacy schedule to FrequencyConfig
      _frequencyConfig =
          _convertLegacyScheduleToFrequencyConfig(habit, _startDate, _endDate);
      // Store original frequency config for comparison
      _originalFrequencyConfig = _frequencyConfig;
      // Load reminders if they exist
      if (habit.hasReminders()) {
        _reminders = ReminderConfigList.fromMapList(habit.reminders);
      }
    }
  }

  FrequencyConfig _convertLegacyScheduleToFrequencyConfig(
      ActivityRecord habit, DateTime startDate, DateTime? endDate) {
    // For existing habits, try to use the new frequency fields first
    if (habit.hasFrequencyType()) {
      FrequencyType type;
      switch (habit.frequencyType) {
        case 'everyXPeriod':
          type = FrequencyType.everyXPeriod;
          break;
        case 'timesPerPeriod':
          type = FrequencyType.timesPerPeriod;
          break;
        case 'specificDays':
          type = FrequencyType.specificDays;
          break;
        default:
          type = FrequencyType.everyXPeriod;
      }
      return FrequencyConfig(
        type: type,
        timesPerPeriod: habit.hasTimesPerPeriod() ? habit.timesPerPeriod : 1,
        periodType: habit.hasPeriodType()
            ? (habit.periodType == 'weeks'
                ? PeriodType.weeks
                : habit.periodType == 'months'
                    ? PeriodType.months
                    : PeriodType.year)
            : PeriodType.weeks,
        everyXValue: habit.hasEveryXValue() ? habit.everyXValue : 1,
        everyXPeriodType: habit.hasEveryXPeriodType()
            ? (habit.everyXPeriodType == 'days'
                ? PeriodType.days
                : habit.everyXPeriodType == 'weeks'
                    ? PeriodType.weeks
                    : PeriodType.months)
            : PeriodType.days,
        selectedDays: habit.hasSpecificDays() ? habit.specificDays : [],
        startDate: startDate,
        endDate: endDate,
      );
    }
    // Fallback to default configuration for habits without frequency data
    return FrequencyConfig(
      type: FrequencyType.everyXPeriod,
      everyXValue: 1,
      everyXPeriodType: PeriodType.days,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;
      final categories = await queryHabitCategoriesOnce(userId: userId);
      if (mounted) {
        setState(() {
          _categories = categories;
          _isLoading = false;
          // Apply the same category matching logic as task page
          if (widget.habitToEdit != null) {
            final habit = widget.habitToEdit!;
            String? matchingCategoryId;
            // Try categoryId first
            if (habit.categoryId.isNotEmpty &&
                categories.any((c) => c.reference.id == habit.categoryId)) {
              matchingCategoryId = habit.categoryId;
            }
            // Try categoryName as fallback (exact match)
            else if (habit.categoryName.isNotEmpty &&
                categories.any((c) => c.name == habit.categoryName)) {
              final category =
                  categories.firstWhere((c) => c.name == habit.categoryName);
              matchingCategoryId = category.reference.id;
            }
            _selectedCategoryId = matchingCategoryId;
            print(
                'DEBUG: Available categories: ${categories.map((c) => '${c.name} (${c.reference.id})').toList()}');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading categories: $e')),
        );
      }
    }
  }

  bool _canSave() {
    if (_nameController.text.trim().isEmpty) return false;
    if (_selectedCategoryId == null) return false;
    if (_selectedTrackingType == null) return false;
    if (_selectedTrackingType == 'quantitative' && _targetNumber <= 0)
      return false;
    if (_selectedTrackingType == 'time' && _targetDuration.inMinutes <= 0)
      return false;
    // Date validation
    if (_frequencyConfig.endDate != null &&
        _frequencyConfig.endDate!.isBefore(_frequencyConfig.startDate)) {
      return false;
    }
    return true;
  }

  /// Check if frequency configuration has changed
  bool _hasFrequencyChanged() {
    if (_originalFrequencyConfig == null) return false;
    final original = _originalFrequencyConfig!;
    final current = _frequencyConfig;
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

  Future<void> _showCategoryMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final String? selectedId = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      color: FlutterFlowTheme.of(context).secondaryBackground,
      items: _categories.map((c) {
        return PopupMenuItem<String>(
          value: c.reference.id,
          child: Text(
            c.name,
            style: FlutterFlowTheme.of(context).bodyMedium,
          ),
        );
      }).toList(),
    );

    if (selectedId != null) {
      setState(() {
        _selectedCategoryId = selectedId;
      });
    }
  }

  Future<void> _showTrackingTypeMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final String? selected = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      color: FlutterFlowTheme.of(context).secondaryBackground,
      items: [
        PopupMenuItem<String>(
          value: 'binary',
          child: Row(
            children: [
              Icon(Icons.check_circle_outline,
                  color: FlutterFlowTheme.of(context).primaryText, size: 20),
              const SizedBox(width: 12),
              Text('Yes/No', style: FlutterFlowTheme.of(context).bodyMedium),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'quantitative',
          child: Row(
            children: [
              Icon(Icons.numbers,
                  color: FlutterFlowTheme.of(context).primaryText, size: 20),
              const SizedBox(width: 12),
              Text('Numeric', style: FlutterFlowTheme.of(context).bodyMedium),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'time',
          child: Row(
            children: [
              Icon(Icons.timer_outlined,
                  color: FlutterFlowTheme.of(context).primaryText, size: 20),
              const SizedBox(width: 12),
              Text('Timer', style: FlutterFlowTheme.of(context).bodyMedium),
            ],
          ),
        ),
      ],
    );

    if (selected != null) {
      setState(() {
        _selectedTrackingType = selected;
        if (selected == 'binary') {
          _targetNumber = 1;
          _targetDuration = const Duration(hours: 1);
          _unitController.clear();
        }
      });
    }
  }

  Future<void> _saveHabit() async {
    if (!_formKey.currentState!.validate() || !_canSave()) return;
    setState(() => _isSaving = true);
    try {
      final userId = currentUserUid;
      final selectedCategory = _categories.firstWhere(
        (cat) => cat.reference.id == _selectedCategoryId,
      );
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
      final recordData = createActivityRecordData(
        priority: weight,
        name: _nameController.text.trim(),
        categoryId: selectedCategory.reference.id,
        categoryName: selectedCategory.name,
        trackingType: _selectedTrackingType,
        target: targetValue,
        unit: _unitController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        dayEndTime: 0,
        specificDays: _frequencyConfig.type == FrequencyType.specificDays
            ? _frequencyConfig.selectedDays
            : null,
        isRecurring: true,
        isActive: true,
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        categoryType: 'habit',
        startDate: _frequencyConfig.startDate,
        endDate: _frequencyConfig.endDate,
        dueTime: _selectedDueTime != null
            ? TimeUtils.timeOfDayToString(_selectedDueTime!)
            : null,
        // New frequency fields - only store relevant fields based on frequency type
        frequencyType: _frequencyConfig.type.toString().split('.').last,
        // Only store everyX fields if frequency type is everyXPeriod
        everyXValue: _frequencyConfig.type == FrequencyType.everyXPeriod
            ? _frequencyConfig.everyXValue
            : null,
        everyXPeriodType: _frequencyConfig.type == FrequencyType.everyXPeriod
            ? _frequencyConfig.everyXPeriodType.toString().split('.').last
            : null,
        // Only store timesPerPeriod fields if frequency type is timesPerPeriod
        timesPerPeriod: _frequencyConfig.type == FrequencyType.timesPerPeriod
            ? _frequencyConfig.timesPerPeriod
            : null,
        periodType: _frequencyConfig.type == FrequencyType.timesPerPeriod
            ? _frequencyConfig.periodType.toString().split('.').last
            : null,
        reminders: _reminders.isNotEmpty
            ? ReminderConfigList.toMapList(_reminders)
            : null,
      );
      if (widget.habitToEdit != null) {
        // Check if frequency configuration has changed for existing habits
        if (_hasFrequencyChanged()) {
          // Show confirmation dialog
          final shouldProceed = await StartDateChangeDialog.show(
            context: context,
            oldStartDate: _originalStartDate ?? DateTime.now(),
            newStartDate: _frequencyConfig.startDate,
            activityName: _nameController.text.trim(),
          );
          if (!shouldProceed) {
            setState(() => _isSaving = false);
            return; // Abort save operation
          }
          // Regenerate instances with new frequency configuration
          try {
            await ActivityInstanceService.regenerateInstancesFromStartDate(
              templateId: widget.habitToEdit!.reference.id,
              template: widget.habitToEdit!,
              newStartDate: _frequencyConfig.startDate,
            );
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error updating instances: $e')),
              );
            }
            setState(() => _isSaving = false);
            return;
          }
        } else {
          // Check if only end date has changed (without frequency changes)
          final originalEndDate = _originalFrequencyConfig?.endDate;
          final newEndDate = _frequencyConfig.endDate;
          if (originalEndDate != newEndDate && newEndDate != null) {
            // If end date was shortened, clean up instances beyond the new end date
            if (originalEndDate == null ||
                newEndDate.isBefore(originalEndDate)) {
              try {
                await ActivityInstanceService.cleanupInstancesBeyondEndDate(
                  templateId: widget.habitToEdit!.reference.id,
                  newEndDate: newEndDate,
                );
              } catch (e) {
                // Don't fail the save operation for this
              }
            }
          }
        }
        // Update the template
        await widget.habitToEdit!.reference.update(recordData);
        // Update all pending instances with new template data
        try {
          final instances =
              await ActivityInstanceService.getInstancesForTemplate(
                  templateId: widget.habitToEdit!.reference.id);
          final pendingInstances =
              instances.where((i) => i.status != 'completed').toList();
          // Update instances in batches to avoid timeout
          const batchSize = 10;
          int successCount = 0;
          for (int i = 0; i < pendingInstances.length; i += batchSize) {
            final batch = pendingInstances.skip(i).take(batchSize);
            print(
                'DEBUG: Updating batch ${(i ~/ batchSize) + 1} with ${batch.length} instances');
            final results = await Future.wait(batch.map((instance) async {
              try {
                print(
                    'DEBUG: Old category: ${instance.templateCategoryName} (${instance.templateCategoryId})');
                print(
                    'DEBUG: New category: ${recordData['categoryName']} (${recordData['categoryId']})');
                await instance.reference.update({
                  'templateName': recordData['name'],
                  'templateCategoryId': recordData['categoryId'],
                  'templateCategoryName': recordData['categoryName'],
                  'templateTrackingType': recordData['trackingType'],
                  'templateTarget': recordData['target'],
                  'templateUnit': recordData['unit'],
                  'templatePriority': recordData['priority'],
                  'templateDescription': recordData['description'],
                  'lastUpdated': DateTime.now(),
                });
                return true;
              } catch (e) {
                return false;
              }
            }));
            // Count successes and failures
            for (final result in results) {
              if (result) {
                successCount++;
              }
            }
          }
          // Verify the updates by re-fetching a few instances
          if (successCount > 0) {
            try {
              final verifyInstances =
                  await ActivityInstanceService.getInstancesForTemplate(
                      templateId: widget.habitToEdit!.reference.id);
              final sampleInstance = verifyInstances.firstWhere(
                (i) => i.status != 'completed',
                orElse: () => verifyInstances.first,
              );
              print(
                  'DEBUG: Verification - Sample instance category: ${sampleInstance.templateCategoryName} (${sampleInstance.templateCategoryId})');
            } catch (e) {}
          }
        } catch (e) {
          // Don't fail the entire save operation if instance updates fail
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Habit updated successfully!')),
          );
          Navigator.pop(context, true);
        }
      } else {
        print(
            '--- create_habit.dart: Habit Name: ${_nameController.text.trim()}');
        print('--- create_habit.dart: calling createActivity (habit) ...');
        await createActivity(
          name: _nameController.text.trim(),
          categoryId: selectedCategory.reference.id,
          categoryName: selectedCategory.name,
          trackingType: _selectedTrackingType!,
          target: targetValue,
          isRecurring: true, // Habits are always recurring
          userId: userId,
          priority: weight,
          unit: _unitController.text.trim(),
          description: _descriptionController.text.trim().isNotEmpty
              ? _descriptionController.text.trim()
              : null,
          categoryType: 'habit',
          dueTime: _selectedDueTime != null
              ? TimeUtils.timeOfDayToString(_selectedDueTime!)
              : null,
          // Pass new frequency fields
          frequencyType: _frequencyConfig.type.toString().split('.').last,
          everyXValue: _frequencyConfig.type == FrequencyType.everyXPeriod
              ? _frequencyConfig.everyXValue
              : null,
          everyXPeriodType: _frequencyConfig.type == FrequencyType.everyXPeriod
              ? _frequencyConfig.everyXPeriodType.toString().split('.').last
              : null,
          timesPerPeriod: _frequencyConfig.type == FrequencyType.timesPerPeriod
              ? _frequencyConfig.timesPerPeriod
              : null,
          periodType: _frequencyConfig.type == FrequencyType.timesPerPeriod
              ? _frequencyConfig.periodType.toString().split('.').last
              : null,
          specificDays: _frequencyConfig.type == FrequencyType.specificDays
              ? _frequencyConfig.selectedDays
              : null,
          startDate: _frequencyConfig.startDate,
          endDate: _frequencyConfig.endDate,
          reminders: _reminders.isNotEmpty
              ? ReminderConfigList.toMapList(_reminders)
              : null,
        );
        print('--- create_habit.dart: createActivity completed successfully');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('New Habit Created successfully!')),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      print('--- create_habit.dart: createActivity failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving habit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context, false);
          },
        ),
        title: Text(
          widget.habitToEdit != null ? 'Edit Habit' : 'Create Habit',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context)
                                .tertiary
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: FlutterFlowTheme.of(context)
                                  .surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: TextFormField(
                            controller: _nameController,
                            style: FlutterFlowTheme.of(context).bodyMedium,
                            maxLength: 200,
                            decoration: InputDecoration(
                              hintText: 'Habit name',
                              hintStyle: TextStyle(
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              counterText: '',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Enter a name'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context)
                                .tertiary
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: FlutterFlowTheme.of(context)
                                  .surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: TextFormField(
                            controller: _descriptionController,
                            style: FlutterFlowTheme.of(context).bodyMedium,
                            maxLines: 2,
                            maxLength: 500,
                            decoration: InputDecoration(
                              hintText: 'Description (optional)',
                              hintStyle: TextStyle(
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  return GestureDetector(
                                    onTap: () => _showCategoryMenu(context),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: FlutterFlowTheme.of(context)
                                            .tertiary
                                            .withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: FlutterFlowTheme.of(context)
                                              .surfaceBorderColor,
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _selectedCategoryId != null
                                                ? _categories
                                                    .firstWhere(
                                                        (c) =>
                                                            c.reference.id ==
                                                            _selectedCategoryId,
                                                        orElse: () =>
                                                            _categories.first)
                                                    .name
                                                : 'Category',
                                            style: _selectedCategoryId != null
                                                ? FlutterFlowTheme.of(context)
                                                    .bodyMedium
                                                : TextStyle(
                                                    color: FlutterFlowTheme.of(
                                                            context)
                                                        .secondaryText,
                                                    fontSize: 14,
                                                  ),
                                          ),
                                          Icon(
                                            Icons.arrow_drop_down,
                                            color: FlutterFlowTheme.of(context)
                                                .secondaryText,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                gradient: FlutterFlowTheme.of(context)
                                    .primaryButtonGradient,
                                borderRadius: BorderRadius.circular(
                                    FlutterFlowTheme.of(context).buttonRadius),
                                boxShadow: [
                                  BoxShadow(
                                    color: FlutterFlowTheme.of(context)
                                        .primary
                                        .withOpacity(0.15),
                                    offset: const Offset(0, 2),
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                      FlutterFlowTheme.of(context)
                                          .buttonRadius),
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) =>
                                          const CreateCategory(
                                              categoryType: 'habit'),
                                    ).then((value) {
                                      _loadCategories();
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    child: const Icon(
                                      Icons.add,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 1,
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                FlutterFlowTheme.of(context).surfaceBorderColor,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        Builder(
                          builder: (context) {
                            return GestureDetector(
                              onTap: () => _showTrackingTypeMenu(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context)
                                      .tertiary
                                      .withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: FlutterFlowTheme.of(context)
                                        .surfaceBorderColor,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          _selectedTrackingType == 'binary'
                                              ? 'Yes/No'
                                              : _selectedTrackingType ==
                                                      'quantitative'
                                                  ? 'Numeric'
                                                  : _selectedTrackingType ==
                                                          'time'
                                                      ? 'Timer'
                                                      : 'Tracking Type',
                                          style: _selectedTrackingType != null
                                              ? FlutterFlowTheme.of(context)
                                                  .bodyMedium
                                              : TextStyle(
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryText,
                                                  fontSize: 14,
                                                ),
                                        ),
                                      ],
                                    ),
                                    Icon(
                                      Icons.arrow_drop_down,
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        if (_selectedTrackingType == 'quantitative') ...[
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: FlutterFlowTheme.of(context).accent2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: FlutterFlowTheme.of(context)
                                      .surfaceBorderColor),
                              boxShadow: [
                                BoxShadow(
                                  color: FlutterFlowTheme.of(context)
                                      .primary
                                      .withOpacity(0.05),
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.track_changes,
                                    size: 16,
                                    color:
                                        FlutterFlowTheme.of(context).primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Target:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: FlutterFlowTheme.of(context).primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: _targetNumber.toString(),
                                    style:
                                        FlutterFlowTheme.of(context).bodyMedium,
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .surfaceBorderColor),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .surfaceBorderColor),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .accent1,
                                            width: 2),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                      isDense: true,
                                      filled: true,
                                      fillColor: FlutterFlowTheme.of(context)
                                          .secondaryBackground,
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) => setState(() =>
                                        _targetNumber = int.tryParse(v) ?? 1),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Unit:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: FlutterFlowTheme.of(context).primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextFormField(
                                    controller: _unitController,
                                    style:
                                        FlutterFlowTheme.of(context).bodyMedium,
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .surfaceBorderColor),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .surfaceBorderColor),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .accent1,
                                            width: 2),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                      hintText: 'e.g., pages, reps',
                                      hintStyle: TextStyle(
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryText),
                                      isDense: true,
                                      filled: true,
                                      fillColor: FlutterFlowTheme.of(context)
                                          .secondaryBackground,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                        ] else if (_selectedTrackingType == 'time') ...[
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: FlutterFlowTheme.of(context).accent2,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: FlutterFlowTheme.of(context)
                                      .surfaceBorderColor),
                              boxShadow: [
                                BoxShadow(
                                  color: FlutterFlowTheme.of(context)
                                      .primary
                                      .withOpacity(0.05),
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.timer,
                                    size: 16,
                                    color:
                                        FlutterFlowTheme.of(context).primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Target Duration:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: FlutterFlowTheme.of(context).primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextFormField(
                                    initialValue:
                                        _targetDuration.inHours.toString(),
                                    style:
                                        FlutterFlowTheme.of(context).bodyMedium,
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .surfaceBorderColor),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .surfaceBorderColor),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .accent1,
                                            width: 2),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                      labelText: 'Hours',
                                      labelStyle: TextStyle(
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryText),
                                      isDense: true,
                                      filled: true,
                                      fillColor: FlutterFlowTheme.of(context)
                                          .secondaryBackground,
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) {
                                      final hours = int.tryParse(v) ?? 1;
                                      setState(() => _targetDuration = Duration(
                                            hours: hours,
                                            minutes:
                                                _targetDuration.inMinutes % 60,
                                          ));
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextFormField(
                                    initialValue:
                                        (_targetDuration.inMinutes % 60)
                                            .toString(),
                                    style:
                                        FlutterFlowTheme.of(context).bodyMedium,
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .surfaceBorderColor),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .surfaceBorderColor),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                            color: FlutterFlowTheme.of(context)
                                                .accent1,
                                            width: 2),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                      labelText: 'Minutes',
                                      labelStyle: TextStyle(
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryText),
                                      isDense: true,
                                      filled: true,
                                      fillColor: FlutterFlowTheme.of(context)
                                          .secondaryBackground,
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) {
                                      final mins = int.tryParse(v) ?? 0;
                                      setState(() => _targetDuration = Duration(
                                            hours: _targetDuration.inHours,
                                            minutes: mins,
                                          ));
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        const SizedBox(height: 8),
                        _buildSectionHeader('Frequency'),
                        FrequencyConfigWidget(
                          initialConfig: _frequencyConfig,
                          onChanged: (newConfig) {
                            setState(() {
                              _frequencyConfig = newConfig;
                              _startDate = newConfig.startDate;
                              _endDate = newConfig.endDate;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        _buildSectionHeader('Reminders'),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context)
                                .tertiary
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: FlutterFlowTheme.of(context)
                                  .surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_reminders.isNotEmpty)
                                ..._reminders.map((r) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 6.0),
                                      child: Row(
                                        children: [
                                          Icon(Icons.notifications_active,
                                              size: 16,
                                              color:
                                                  FlutterFlowTheme.of(context)
                                                      .primary),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${TimeUtils.formatTimeOfDayForDisplay(r.time)} (${r.days.map((d) => [
                                                  'Mon',
                                                  'Tue',
                                                  'Wed',
                                                  'Thu',
                                                  'Fri',
                                                  'Sat',
                                                  'Sun'
                                                ][d - 1]).join(', ')})',
                                            style: FlutterFlowTheme.of(context)
                                                .bodyMedium,
                                          ),
                                          const Spacer(),
                                          InkWell(
                                            onTap: () {
                                              setState(() {
                                                _reminders.remove(r);
                                              });
                                            },
                                            child: Icon(Icons.close,
                                                size: 16,
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .secondaryText),
                                          ),
                                        ],
                                      ),
                                    )),
                              InkWell(
                                onTap: () async {
                                  final reminders =
                                      await ReminderConfigDialog.show(
                                    context: context,
                                    initialReminders: _reminders,
                                    // We don't use dueTime for habits anymore, passing null
                                    dueTime: null,
                                  );
                                  if (reminders != null) {
                                    setState(() => _reminders = reminders);
                                  }
                                },
                                child: Row(
                                  children: [
                                    Icon(Icons.add,
                                        size: 18,
                                        color: FlutterFlowTheme.of(context)
                                            .primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Add Reminder',
                                      style: FlutterFlowTheme.of(context)
                                          .bodyMedium
                                          .override(
                                            color: FlutterFlowTheme.of(context)
                                                .primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildSectionHeader('Weight'),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context)
                                .tertiary
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: FlutterFlowTheme.of(context)
                                  .surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Slider(
                                value: weight.toDouble(),
                                min: 1.0,
                                max: 3.0,
                                divisions: 2,
                                label: weight.toString(),
                                activeColor:
                                    FlutterFlowTheme.of(context).primary,
                                onChanged: (value) {
                                  if (mounted) {
                                    setState(() => weight = value.round());
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: (_canSave() && !_isSaving)
                          ? FlutterFlowTheme.of(context).primaryButtonGradient
                          : null,
                      color: (_canSave() && !_isSaving)
                          ? null
                          : FlutterFlowTheme.of(context).secondaryBackground,
                      borderRadius: BorderRadius.circular(
                          FlutterFlowTheme.of(context).buttonRadius),
                      boxShadow: (_canSave() && !_isSaving)
                          ? [
                              BoxShadow(
                                color: FlutterFlowTheme.of(context)
                                    .primary
                                    .withOpacity(0.15),
                                offset: const Offset(0, 2),
                                blurRadius: 3,
                              ),
                            ]
                          : null,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                            FlutterFlowTheme.of(context).buttonRadius),
                        onTap: (_canSave() && !_isSaving) ? _saveHabit : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          child: _isSaving
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : Text(
                                  widget.habitToEdit != null
                                      ? 'Save Habit'
                                      : 'Create Habit',
                                  style: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        color: (_canSave() && !_isSaving)
                                            ? Colors.white
                                            : FlutterFlowTheme.of(context)
                                                .secondaryText,
                                        fontWeight: FontWeight.w600,
                                      )),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: theme.neumorphicGradientSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: Text(
        title,
        style: theme.titleMedium.override(
          fontFamily: 'Readex Pro',
          fontWeight: FontWeight.w600,
          color: theme.primaryText,
        ),
      ),
    );
  }
}
