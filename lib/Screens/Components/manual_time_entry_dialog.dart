import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/time_logging_preferences_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:intl/intl.dart';

class ManualTimeEntryDialog extends StatefulWidget {
  final DateTime selectedDate;
  final VoidCallback onSave;

  const ManualTimeEntryDialog({
    super.key,
    required this.selectedDate,
    required this.onSave,
  });

  @override
  State<ManualTimeEntryDialog> createState() => _ManualTimeEntryDialogState();
}

class _ManualTimeEntryDialogState extends State<ManualTimeEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isProductive = true;
  late DateTime _startTime;
  late DateTime _endTime;
  bool _isLoading = false;
  int _defaultDurationMinutes = 10;
  bool _useGlobalDefault = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startTime = DateTime(widget.selectedDate.year, widget.selectedDate.month, widget.selectedDate.day, now.hour, now.minute);
    _endTime = _startTime.add(Duration(minutes: _defaultDurationMinutes));
    _loadDefaultDuration();
  }

  Future<void> _loadDefaultDuration() async {
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final enableDefaultEstimates =
            await TimeLoggingPreferencesService.getEnableDefaultEstimates(userId);
        int durationMinutes = 10; // Default fallback
        if (enableDefaultEstimates) {
          durationMinutes = await TimeLoggingPreferencesService
              .getDefaultDurationMinutes(userId);
        }
        if (mounted) {
          setState(() {
            _defaultDurationMinutes = durationMinutes;
            _useGlobalDefault = enableDefaultEstimates;
            // Update end time if it was set to the old default
            if (_endTime.isBefore(_startTime) ||
                _endTime.isAtSameMomentAs(_startTime)) {
              _endTime = _startTime.add(Duration(minutes: _defaultDurationMinutes));
            }
          });
        }
      }
    } catch (e) {
      // On error, keep default of 10 minutes
      print('Error loading default duration: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (time != null) {
      setState(() {
        _startTime = DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
          widget.selectedDate.day,
          time.hour,
          time.minute,
        );
      });
    }
  }

  Future<void> _pickEndTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endTime),
    );
    if (time != null) {
      setState(() {
        _endTime = DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
          widget.selectedDate.day,
          time.hour,
          time.minute,
        );
      });
    }
  }

  Future<void> _saveEntry() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_startTime.isAfter(_endTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time cannot be before start time.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await TaskInstanceService.logManualTimeEntry(
        taskName: _nameController.text,
        startTime: _startTime,
        endTime: _endTime,
        activityType: _isProductive ? 'task' : 'non_productive',
      );
      widget.onSave();
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save entry: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log Time Entry'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Activity Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(_isProductive ? 'Productive Task' : 'Non-Productive'),
                value: _isProductive,
                onChanged: (value) {
                  setState(() {
                    _isProductive = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Start Time'),
                subtitle: Text(DateFormat.jm().format(_startTime)),
                onTap: _pickStartTime,
                leading: const Icon(Icons.access_time),
              ),
              ListTile(
                title: const Text('End Time'),
                subtitle: Text(DateFormat.jm().format(_endTime)),
                onTap: _pickEndTime,
                leading: const Icon(Icons.access_time_filled),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveEntry,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
