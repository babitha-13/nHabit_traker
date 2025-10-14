import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_dialog.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_widget.dart';
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

  @override
  void initState() {
    super.initState();
    _loadCategories();

    _frequencyConfig = FrequencyConfig(type: FrequencyType.everyXPeriod);

    if (widget.habitToEdit != null) {
      final habit = widget.habitToEdit!;
      _nameController.text = habit.name;
      _unitController.text = habit.unit;
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
      _endDate = habit.endDate;
      // If endDate is 2099 or later, treat as perpetual (set to null)
      if (_endDate != null && _endDate!.year >= 2099) {
        _endDate = null;
      }

      // Convert legacy schedule to FrequencyConfig
      _frequencyConfig =
          _convertLegacyScheduleToFrequencyConfig(habit, _startDate, _endDate);
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
                'DEBUG: Habit category matching - original ID: ${habit.categoryId}, name: ${habit.categoryName}');
            print(
                'DEBUG: Available categories: ${categories.map((c) => '${c.name} (${c.reference.id})').toList()}');
            print('DEBUG: Final selected category ID: $_selectedCategoryId');
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
      );

      print('DEBUG: Saving ActivityRecord data: $recordData');

      if (widget.habitToEdit != null) {
        // Update the template
        await widget.habitToEdit!.reference.update(recordData);

        // Update all pending instances with new template data
        try {
          print('DEBUG: Fetching instances for template');
          final instances =
              await ActivityInstanceService.getInstancesForTemplate(
                  templateId: widget.habitToEdit!.reference.id);

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
                    'DEBUG: New category: ${recordData['categoryName']} (${recordData['categoryId']})');

                await instance.reference.update({
                  'templateName': recordData['name'],
                  'templateCategoryId': recordData['categoryId'],
                  'templateCategoryName': recordData['categoryName'],
                  'templateTrackingType': recordData['trackingType'],
                  'templateTarget': recordData['target'],
                  'templateUnit': recordData['unit'],
                  'lastUpdated': DateTime.now(),
                });

                print(
                    'DEBUG: Instance ${instance.reference.id} updated successfully');
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
            } catch (e) {
              print('DEBUG: Verification failed: $e');
            }
          }

          print('DEBUG: All habit instance updates completed');
        } catch (e) {
          print('Error updating habit instances: $e');
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
            '--- create_habit.dart: Preparing to call createActivity for a new habit...');
        print(
            '--- create_habit.dart: Habit Name: ${_nameController.text.trim()}');
        print('--- create_habit.dart: Category Name: ${selectedCategory.name}');
        print('--- create_habit.dart: User ID: $userId');

        await createActivity(
          name: _nameController.text.trim(),
          categoryName: selectedCategory.name,
          trackingType: _selectedTrackingType!,
          target: targetValue,
          isRecurring: true, // Habits are always recurring
          userId: userId,
          priority: weight,
          unit: _unitController.text.trim(),
          categoryType: 'habit',
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
        );

        print('--- create_habit.dart: createActivity call finished.');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('New Habit Created successfully!')),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Basic Information'),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter a name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: () {
                                  if (_selectedCategoryId == null) return null;
                                  final isValid = _categories.any((c) =>
                                      c.reference.id == _selectedCategoryId);
                                  print(
                                      'DEBUG: Habit dropdown value check - selectedId: $_selectedCategoryId, isValid: $isValid');
                                  return isValid ? _selectedCategoryId : null;
                                }(),
                                decoration: const InputDecoration(
                                  labelText: 'Category *',
                                  border: OutlineInputBorder(),
                                ),
                                items: _categories
                                    .map((c) => DropdownMenuItem(
                                        value: c.reference.id,
                                        child: Text(c.name)))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _selectedCategoryId = v),
                                validator: (v) =>
                                    v == null ? 'Select a category' : null,
                              ),
                            ),
                            const SizedBox(
                              width: 5,
                            ),
                            GestureDetector(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => const CreateCategory(
                                      categoryType: 'habit'),
                                ).then((value) {
                                  _loadCategories();
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context).primary,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: FlutterFlowTheme.of(context).primary,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 3,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          ],
                        ),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Tracking Type'),
                      DropdownButtonFormField<String>(
                        value: _selectedTrackingType,
                        decoration: const InputDecoration(
                          labelText: 'Type *',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'binary',
                              child: Text('Binary (Done/Not Done)')),
                          DropdownMenuItem(
                              value: 'quantitative',
                              child: Text('Quantity (Number)')),
                          DropdownMenuItem(
                              value: 'time', child: Text('Time (Duration)')),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedTrackingType = v),
                        validator: (v) =>
                            v == null ? 'Select tracking type' : null,
                      ),
                      const SizedBox(height: 24),
                      if (_selectedTrackingType == 'quantitative') ...[
                        _buildSectionHeader('Target'),
                        Row(children: [
                          Expanded(
                              child: TextFormField(
                            initialValue: _targetNumber.toString(),
                            decoration: const InputDecoration(
                                labelText: 'Target *',
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => setState(
                                () => _targetNumber = int.tryParse(v) ?? 1),
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                              child: TextFormField(
                            controller: _unitController,
                            decoration: const InputDecoration(
                                labelText: 'Unit',
                                border: OutlineInputBorder()),
                          )),
                        ]),
                      ] else if (_selectedTrackingType == 'time') ...[
                        _buildSectionHeader('Target'),
                        Row(children: [
                          Expanded(
                              child: TextFormField(
                            initialValue: _targetDuration.inHours.toString(),
                            decoration: const InputDecoration(
                                labelText: 'Hours *',
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final hours = int.tryParse(v) ?? 1;
                              setState(() => _targetDuration = Duration(
                                  hours: hours,
                                  minutes: _targetDuration.inMinutes % 60));
                            },
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                              child: TextFormField(
                            initialValue:
                                (_targetDuration.inMinutes % 60).toString(),
                            decoration: const InputDecoration(
                                labelText: 'Minutes',
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final mins = int.tryParse(v) ?? 0;
                              setState(() => _targetDuration = Duration(
                                  hours: _targetDuration.inHours,
                                  minutes: mins));
                            },
                          )),
                        ]),
                      ],
                      const SizedBox(height: 24),
                      _buildSectionHeader('Schedule'),
                      FrequencyConfigWidget(
                        initialConfig: _frequencyConfig,
                        onChanged: (newConfig) {
                          setState(() {
                            _frequencyConfig = newConfig;
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Weight'),
                      const SizedBox(height: 8),
                      InputDecorator(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_canSave() && !_isSaving) ? _saveHabit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FlutterFlowTheme.of(context).primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            widget.habitToEdit != null
                                ? 'Save Habit'
                                : 'Create Habit',
                            style: const TextStyle(color: Colors.white)),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: FlutterFlowTheme.of(context).titleMedium),
    );
  }
}
