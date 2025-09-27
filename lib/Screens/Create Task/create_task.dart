import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';

class CreateTask extends StatefulWidget {
  final HabitRecord task;
  final List<CategoryRecord> categories;
  final Function(HabitRecord) onSave;

  const CreateTask({
    super.key,
    required this.task,
    required this.categories,
    required this.onSave,
  });

  @override
  State<CreateTask> createState() => _CreateTaskState();
}

class _CreateTaskState extends State<CreateTask> {
  late TextEditingController _titleController;
  String? _selectedCategoryId;
  String? _selectedTrackingType;
  int _targetNumber = 1;
  Duration _targetDuration = const Duration(hours: 1);
  String _unit = '';
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleController = TextEditingController(text: t.name);
    _selectedCategoryId = t.categoryId;
    _selectedTrackingType = t.trackingType;
    _targetNumber = t.target is int ? t.target as int : 1;
    _targetDuration = t.trackingType == 'time'
        ? Duration(minutes: t.target as int)
        : const Duration(hours: 1);
    _unit = t.unit;
    _dueDate = t.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _save() async {
    final docRef = widget.task.reference;
    final updateData = createHabitRecordData(
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
      lastUpdated: DateTime.now(),
    );
    try {
      await docRef.update(updateData);
      final updatedHabit = HabitRecord.getDocumentFromData(updateData, docRef);
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 12),
                // Category
                DropdownButtonFormField<String>(
                  value: widget.categories.any((c) => c.reference.id == _selectedCategoryId)
                      ? _selectedCategoryId
                      : null,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  items: widget.categories
                      .map((c) => DropdownMenuItem(value: c.reference.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCategoryId = v),
                ),
                const SizedBox(height: 12),
                // Tracking Type
                DropdownButtonFormField<String>(
                  value: _selectedTrackingType,
                  decoration: InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    controller: TextEditingController(text: _targetNumber.toString()),
                    onChanged: (v) => _targetNumber = int.tryParse(v) ?? 1,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    controller: TextEditingController(text: _unit),
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
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          controller:
                          TextEditingController(text: _targetDuration.inHours.toString()),
                          onChanged: (v) {
                            final h = int.tryParse(v) ?? 1;
                            setState(() => _targetDuration =
                                Duration(hours: h, minutes: _targetDuration.inMinutes % 60));
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
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          controller: TextEditingController(text: (_targetDuration.inMinutes % 60).toString()),
                          onChanged: (v) {
                            final m = int.tryParse(v) ?? 0;
                            setState(() => _targetDuration =
                                Duration(hours: _targetDuration.inHours, minutes: m));
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
                        'Due Date: ${_dueDate != null ? "${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}" : "None"}',
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.calendar_today), onPressed: _pickDueDate)
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
