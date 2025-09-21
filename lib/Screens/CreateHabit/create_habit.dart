import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

class CreateHabitPage extends StatefulWidget {
  final HabitRecord? habitToEdit;

  const CreateHabitPage({super.key, this.habitToEdit});

  @override
  State<CreateHabitPage> createState() => _CreateHabitPageState();
}

class _CreateHabitPageState extends State<CreateHabitPage> {
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
  int _weeklyTarget = 1;
  List<int> _selectedDays = [];
  static const List<String> _weekDays = [
    'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    if (widget.habitToEdit != null) {
      final habit = widget.habitToEdit!;
      _nameController.text = habit.name;
      _unitController.text = habit.unit ?? '';
      _selectedCategoryId = habit.categoryId;
      _selectedTrackingType = habit.trackingType;
      _selectedSchedule = habit.schedule;
      weight = habit.weight;
      _weeklyTarget = habit.weeklyTarget ?? 1;
      if (habit.trackingType == 'quantitative') {
        _targetNumber = habit.target ?? 1;
      } else if (habit.trackingType == 'time') {
        final minutes = habit.target ?? 60;
        _targetDuration = Duration(minutes: minutes);
      }
      _selectedDays = habit.specificDays ?? [];
    }
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
      final categories = await queryCategoriesRecordOnce(userId: userId);
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
    if (_selectedTrackingType == 'quantitative' && _targetNumber <= 0) return false;
    if (_selectedTrackingType == 'time' && _targetDuration.inMinutes <= 0) return false;
    if (_selectedSchedule == 'weekly' && _weeklyTarget <= 0) return false;
    if (_selectedSchedule == 'monthly' && _weeklyTarget <= 0) return false;
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
        case 'binary': targetValue = true; break;
        case 'quantitative': targetValue = _targetNumber; break;
        case 'time': targetValue = _targetDuration.inMinutes; break;
      }

      final recordData = createHabitRecordData(
        weight: weight,
        name: _nameController.text.trim(),
        categoryId: selectedCategory.reference.id,
        categoryName: selectedCategory.name,
        impactLevel: 'Medium',
        trackingType: _selectedTrackingType,
        target: targetValue,
        schedule: _selectedSchedule,
        weeklyTarget: _weeklyTarget,
        unit: _unitController.text.trim(),
        dayEndTime: 0,
        specificDays: _selectedDays.isNotEmpty ? _selectedDays : null,
        isRecurring: true,
        isActive: true,
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        userId: userId,
      );
      if (widget.habitToEdit != null) {
        await widget.habitToEdit!.reference.update(recordData);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Habit updated successfully!')),
          );
          Navigator.pop(context, true);
        }
      } else {
        await HabitRecord.collectionForUser(userId).add(recordData);
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
        title: const Text('Create Habit'),
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
                        validator: (v) => v == null || v.trim().isEmpty ? 'Enter a name' : null,
                      ),
                      const SizedBox(height: 12),
                      if (_isLoading) const Center(child: CircularProgressIndicator())
                      else DropdownButtonFormField<String>(
                        value: _selectedCategoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category *',
                          border: OutlineInputBorder(),
                        ),
                        items: _categories.map((c) => DropdownMenuItem(
                            value: c.reference.id, child: Text(c.name))).toList(),
                        onChanged: (v) => setState(() => _selectedCategoryId = v),
                        validator: (v) => v == null ? 'Select a category' : null,
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
                          DropdownMenuItem(value: 'binary', child: Text('Binary (Done/Not Done)')),
                          DropdownMenuItem(value: 'quantitative', child: Text('Quantity (Number)')),
                          DropdownMenuItem(value: 'time', child: Text('Time (Duration)')),
                        ],
                        onChanged: (v) => setState(() => _selectedTrackingType = v),
                        validator: (v) => v == null ? 'Select tracking type' : null,
                      ),
                      const SizedBox(height: 24),

                      if (_selectedTrackingType == 'quantitative') ...[
                        _buildSectionHeader('Target'),
                        Row(children: [
                          Expanded(child: TextFormField(
                            initialValue: _targetNumber.toString(),
                            decoration: const InputDecoration(labelText: 'Target *', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => setState(() => _targetNumber = int.tryParse(v) ?? 1),
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: TextFormField(
                            controller: _unitController,
                            decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                          )),
                        ]),
                      ] else if (_selectedTrackingType == 'time') ...[
                        _buildSectionHeader('Target'),
                        Row(children: [
                          Expanded(child: TextFormField(
                            initialValue: _targetDuration.inHours.toString(),
                            decoration: const InputDecoration(labelText: 'Hours *', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final hours = int.tryParse(v) ?? 1;
                              setState(() => _targetDuration = Duration(hours: hours, minutes: _targetDuration.inMinutes % 60));
                            },
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: TextFormField(
                            initialValue: (_targetDuration.inMinutes % 60).toString(),
                            decoration: const InputDecoration(labelText: 'Minutes', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final mins = int.tryParse(v) ?? 0;
                              setState(() => _targetDuration = Duration(hours: _targetDuration.inHours, minutes: mins));
                            },
                          )),
                        ]),
                      ],
                      const SizedBox(height: 24),
                      _buildSectionHeader('Schedule'),
                      DropdownButtonFormField<String>(
                        value: _selectedSchedule,
                        decoration: const InputDecoration(
                          labelText: 'Frequency *',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'daily', child: Text('Daily')),
                          DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                          DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                        ],
                        onChanged: (v) => setState(() => _selectedSchedule = v ?? 'daily'),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedSchedule == 'weekly' || _selectedSchedule == 'monthly') ...[
                        TextFormField(
                          initialValue: _weeklyTarget.toString(),
                          decoration: InputDecoration(
                            labelText: _selectedSchedule == 'weekly' ? 'Times per week *' : 'Times per month *',
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => setState(() => _weeklyTarget = int.tryParse(v) ?? 1),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_selectedSchedule == 'weekly') ...[
                        const Text('Days of week:', style: TextStyle(fontSize: 12)),
                        Wrap(
                          spacing: 8,
                          children: List.generate(7, (i) {
                            final isSelected = _selectedDays.contains(i + 1);
                            return FilterChip(
                              label: Text(_weekDays[i].substring(0, 3)),
                              selected: isSelected,
                              onSelected: (s) => setState(() {
                                if (s) { _selectedDays.add(i + 1); }
                                else { _selectedDays.remove(i + 1); }
                              }),
                            );
                          }),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildSectionHeader('Weight'),
                      const SizedBox(height: 8),
                      InputDecorator(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        : const Text('Create Habit', style: TextStyle(color: Colors.white)),
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
