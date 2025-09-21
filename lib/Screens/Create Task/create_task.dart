import 'package:flutter/material.dart';
// import 'package:go_router/go_router.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

class CreateTaskPage extends StatefulWidget {
  const CreateTaskPage({Key? key}) : super(key: key);

  @override
  State<CreateTaskPage> createState() => _CreateTaskPageState();
}

class _CreateTaskPageState extends State<CreateTaskPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _unitController = TextEditingController();

  // Form state
  String? _selectedCategoryId;
  String? _selectedTrackingType = 'binary'; // default binary
  List<CategoryRecord> _categories = [];
  bool _isLoading = true;
  bool _isSaving = false;

  // Tracking type fields
  int _targetNumber = 1;
  Duration _targetDuration = const Duration(hours: 1);

  // Task-specific fields
  DateTime? _selectedDueDate;
  int _priority = 1; // default Low

  @override
  void initState() {
    super.initState();
    _loadCategories();
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

  Future<void> _selectDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDueDate = picked);
    }
  }

  bool _canSave() {
    if (_nameController.text.trim().isEmpty) return false;
    if (_selectedCategoryId == null) return false;
    if (_selectedTrackingType == null) return false;

    if (_selectedTrackingType == 'quantitative' && _targetNumber <= 0) {
      return false;
    }
    if (_selectedTrackingType == 'time' && _targetDuration.inMinutes <= 0) {
      return false;
    }

    return true;
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_canSave()) return;

    setState(() => _isSaving = true);

    try {
      final userId = currentUserUid;
      if (userId.isEmpty) throw Exception("User not authenticated");

      final selectedCategory = _categories.firstWhere(
            (c) => c.reference.id == _selectedCategoryId,
        orElse: () => throw Exception("Category not found"),
      );

      // Target based on tracking type
      dynamic targetValue;
      switch (_selectedTrackingType) {
        case 'binary':
          targetValue = true;
          break;
        case 'quantitative':
          targetValue = _targetNumber;
          break;
        case 'time':
          targetValue = _targetDuration.inMinutes;
          break;
      }

      final recordData = createHabitRecordData(
        name: _nameController.text.trim(),
        categoryId: selectedCategory.reference.id,
        categoryName: selectedCategory.name,
        impactLevel: 'Medium',
        trackingType: _selectedTrackingType,
        target: targetValue,
        unit: _unitController.text.trim(),
        priority: _priority,
        dueDate: _selectedDueDate,
        taskStatus: 'todo',
        isRecurring: false, // tasks are one-time
        isActive: true,
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        userId: userId,
      );

      await HabitRecord.collectionForUser(userId).add(recordData);

      if (mounted) {
        // context.goNamed('TasksPg');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving task: $e')),
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
        title: const Text("Create Task"),
        backgroundColor: FlutterFlowTheme.of(context).primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              // context.goNamed('TasksPg');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Save Button
              Container(
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_canSave() && !_isSaving) ? _saveTask : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlutterFlowTheme.of(context).primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Create Task",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ),
              ),

              // Scrollable Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader("Basic Information"),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: "Task Name *",
                          hintText: "e.g., Read Chapter 5",
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return "Please enter a name";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else
                        DropdownButtonFormField<String>(
                          value: _selectedCategoryId,
                          decoration: const InputDecoration(
                            labelText: "Category *",
                            border: OutlineInputBorder(),
                          ),
                          items: _categories
                              .map((cat) => DropdownMenuItem(
                            value: cat.reference.id,
                            child: Text(cat.name),
                          ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedCategoryId = v),
                          validator: (val) =>
                          val == null ? "Please select a category" : null,
                        ),
                      const SizedBox(height: 24),

                      _buildSectionHeader("Tracking Type"),
                      DropdownButtonFormField<String>(
                        value: _selectedTrackingType,
                        decoration: const InputDecoration(
                          labelText: "Type *",
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'binary',
                              child: Text("Binary (Done/Not Done)")),
                          DropdownMenuItem(
                              value: 'quantitative',
                              child: Text("Quantity (Number)")),
                          DropdownMenuItem(
                              value: 'time',
                              child: Text("Time (Duration)")),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedTrackingType = val),
                        validator: (val) =>
                        val == null ? "Please select a type" : null,
                      ),
                      const SizedBox(height: 24),

                      if (_selectedTrackingType == 'quantitative') ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: _targetNumber.toString(),
                                decoration: const InputDecoration(
                                  labelText: "Target *",
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (val) => setState(() =>
                                _targetNumber = int.tryParse(val) ?? 1),
                                validator: (val) {
                                  final num = int.tryParse(val ?? "");
                                  if (num == null || num <= 0) {
                                    return "Enter a valid number";
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _unitController,
                                decoration: const InputDecoration(
                                  labelText: "Unit",
                                  hintText: "e.g., pages, km",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ] else if (_selectedTrackingType == 'time') ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: _targetDuration.inHours.toString(),
                                decoration: const InputDecoration(
                                  labelText: "Hours *",
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (val) {
                                  final h = int.tryParse(val) ?? 1;
                                  setState(() => _targetDuration =
                                      Duration(hours: h));
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue:
                                (_targetDuration.inMinutes % 60).toString(),
                                decoration: const InputDecoration(
                                  labelText: "Minutes",
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (val) {
                                  final m = int.tryParse(val) ?? 0;
                                  setState(() => _targetDuration = Duration(
                                    hours: _targetDuration.inHours,
                                    minutes: m,
                                  ));
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],

                      _buildSectionHeader("Task Details"),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _selectDueDate,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: "Due Date (Optional)",
                                  border: OutlineInputBorder(),
                                ),
                                child: Text(
                                  _selectedDueDate != null
                                      ? "${_selectedDueDate!.day}/${_selectedDueDate!.month}/${_selectedDueDate!.year}"
                                      : "No due date",
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _priority,
                              decoration: const InputDecoration(
                                labelText: "Priority",
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 1, child: Text("Low")),
                                DropdownMenuItem(value: 2, child: Text("Medium")),
                                DropdownMenuItem(value: 3, child: Text("High")),
                              ],
                              onChanged: (v) =>
                                  setState(() => _priority = v ?? 1),
                            ),
                          ),
                        ],
                      ),
                    ],
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
      child: Text(
        title,
        style: FlutterFlowTheme.of(context).titleMedium.override(
          fontFamily: 'Readex Pro',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
