import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
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
  String _selectedSchedule = 'daily';
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

  static const List<String> _weekDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();

    _frequencyConfig = FrequencyConfig(type: FrequencyType.everyXPeriod);

    if (widget.habitToEdit != null) {
      final habit = widget.habitToEdit!;
      _nameController.text = habit.name;
      _unitController.text = habit.unit ?? '';
      _selectedCategoryId = habit.categoryId;
      _selectedTrackingType = habit.trackingType;
      _selectedSchedule = habit.schedule ?? 'daily';
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
    FrequencyType type;
    int timesPerPeriod = 1;
    PeriodType periodType = PeriodType.weeks;
    int everyXValue = 1;
    PeriodType everyXPeriodType = PeriodType.days;
    List<int> selectedDays = [];

    switch (habit.schedule) {
      case 'daily':
        type = FrequencyType.everyXPeriod;
        everyXValue = habit.frequency ?? 1;
        everyXPeriodType = PeriodType.days;
        break;
      case 'weekly':
        if (habit.specificDays != null && habit.specificDays!.isNotEmpty) {
          type = FrequencyType.specificDays;
          selectedDays = habit.specificDays!;
        } else {
          type = FrequencyType.timesPerPeriod;
          timesPerPeriod = habit.frequency ?? 1;
          periodType = PeriodType.weeks;
        }
        break;
      case 'monthly':
        type = FrequencyType.timesPerPeriod;
        timesPerPeriod = habit.frequency ?? 1;
        periodType = PeriodType.months;
        break;
      default:
        type = FrequencyType.everyXPeriod;
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

      // Convert frequency config to schedule and frequency fields
      String? schedule;
      int? frequency;
      List<int>? specificDays;

      switch (_frequencyConfig.type) {
        case FrequencyType.specificDays:
          schedule = 'weekly';
          frequency = _frequencyConfig.selectedDays.length;
          specificDays = _frequencyConfig.selectedDays;
          break;
        case FrequencyType.timesPerPeriod:
          schedule = _frequencyConfig.periodType == PeriodType.weeks
              ? 'weekly'
              : _frequencyConfig.periodType == PeriodType.months
                  ? 'monthly'
                  : 'yearly';
          frequency = _frequencyConfig.timesPerPeriod;
          break;
        case FrequencyType.everyXPeriod:
          schedule = _frequencyConfig.everyXPeriodType == PeriodType.days
              ? 'daily'
              : _frequencyConfig.everyXPeriodType == PeriodType.weeks
                  ? 'weekly'
                  : 'monthly';
          frequency = _frequencyConfig.everyXValue;
          break;
        default:
          schedule = 'daily';
          frequency = 1;
      }

      final recordData = createActivityRecordData(
        priority: weight,
        name: _nameController.text.trim(),
        categoryId: selectedCategory.reference.id,
        categoryName: selectedCategory.name,
        trackingType: _selectedTrackingType,
        target: targetValue,
        schedule: null, // Deprecated
        frequency: null, // Deprecated
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
        await widget.habitToEdit!.reference.update(recordData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Habit updated successfully!')),
          );
          Navigator.pop(context, true);
        }
      } else {
        await ActivityRecord.collectionForUser(userId).add(recordData);
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
                                value: _selectedCategoryId,
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
