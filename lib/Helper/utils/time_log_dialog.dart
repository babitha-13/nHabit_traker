import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/non_productive_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:intl/intl.dart';

class TimeLogDialog extends StatefulWidget {
  final ActivityRecord template;
  final String? existingInstanceId; // If editing existing instance

  const TimeLogDialog({
    Key? key,
    required this.template,
    this.existingInstanceId,
  }) : super(key: key);

  @override
  _TimeLogDialogState createState() => _TimeLogDialogState();
}

class _TimeLogDialogState extends State<TimeLogDialog> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  DateTime _startTime = DateTime.now().subtract(const Duration(hours: 1));
  DateTime _endTime = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (picked != null) {
      setState(() {
        _startTime = DateTime(
          _startTime.year,
          _startTime.month,
          _startTime.day,
          picked.hour,
          picked.minute,
        );
        // Ensure end time is after start time
        if (_endTime.isBefore(_startTime) ||
            _endTime.isAtSameMomentAs(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 1));
        }
      });
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endTime),
    );
    if (picked != null) {
      setState(() {
        _endTime = DateTime(
          _endTime.year,
          _endTime.month,
          _endTime.day,
          picked.hour,
          picked.minute,
        );
        // Ensure end time is after start time
        if (_endTime.isBefore(_startTime) ||
            _endTime.isAtSameMomentAs(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 1));
        }
      });
    }
  }

  void _setQuickDuration(Duration duration) {
    setState(() {
      _endTime = _startTime.add(duration);
    });
  }

  void _setEndTimeToNow() {
    setState(() {
      _endTime = DateTime.now();
    });
  }

  Future<void> _saveTimeLog() async {
    if (_endTime.isBefore(_startTime) ||
        _endTime.isAtSameMomentAs(_startTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      if (widget.existingInstanceId != null) {
        // Update existing instance
        await NonProductiveService.logTimeForInstance(
          instanceId: widget.existingInstanceId!,
          startTime: _startTime,
          endTime: _endTime,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          userId: currentUserUid,
        );
      } else {
        // Create new instance
        await NonProductiveService.createNonProductiveInstance(
          templateId: widget.template.reference.id,
          startTime: _startTime,
          endTime: _endTime,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          userId: currentUserUid,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existingInstanceId != null
                ? 'Time log updated successfully!'
                : 'Time logged successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('MMM d, yyyy h:mm a').format(dateTime);
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  String _formatDuration() {
    final duration = _endTime.difference(_startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Log Time: ${widget.template.name}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Start Time
              ListTile(
                title: const Text('Start Time'),
                subtitle: Text(_formatDateTime(_startTime)),
                trailing: const Icon(Icons.access_time),
                onTap: _selectStartTime,
              ),
              const Divider(),
              // End Time
              ListTile(
                title: const Text('End Time'),
                subtitle: Text(_formatDateTime(_endTime)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.access_time),
                      onPressed: _selectEndTime,
                      tooltip: 'Select End Time',
                    ),
                    IconButton(
                      icon: const Icon(Icons.schedule),
                      onPressed: _setEndTimeToNow,
                      tooltip: 'Set to Now',
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Duration Display
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Duration: ${_formatDuration()}',
                  style: FlutterFlowTheme.of(context).titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              // Quick Duration Buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildQuickDurationButton('15m', const Duration(minutes: 15)),
                  _buildQuickDurationButton('30m', const Duration(minutes: 30)),
                  _buildQuickDurationButton('1h', const Duration(hours: 1)),
                  _buildQuickDurationButton('2h', const Duration(hours: 2)),
                ],
              ),
              const SizedBox(height: 16),
              // Notes
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveTimeLog,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildQuickDurationButton(String label, Duration duration) {
    return OutlinedButton(
      onPressed: () => _setQuickDuration(duration),
      child: Text(label),
    );
  }
}

