import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/non_productive_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

class NonProductiveTemplateDialog extends StatefulWidget {
  final ActivityRecord? existingTemplate;
  final Function(ActivityRecord)? onTemplateCreated;
  final Function(ActivityRecord)? onTemplateUpdated;

  const NonProductiveTemplateDialog({
    Key? key,
    this.existingTemplate,
    this.onTemplateCreated,
    this.onTemplateUpdated,
  }) : super(key: key);

  @override
  _NonProductiveTemplateDialogState createState() =>
      _NonProductiveTemplateDialogState();
}

class _NonProductiveTemplateDialogState
    extends State<NonProductiveTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _unitController = TextEditingController();
  String _selectedTrackingType = 'time';
  dynamic _targetValue;
  bool _isSaving = false;
  final List<String> _trackingTypes = ['binary', 'quantitative', 'time'];

  @override
  void initState() {
    super.initState();
    if (widget.existingTemplate != null) {
      _nameController.text = widget.existingTemplate!.name;
      _descriptionController.text = widget.existingTemplate!.description;
      _selectedTrackingType = widget.existingTemplate!.trackingType;
      _targetValue = widget.existingTemplate!.target;
      _unitController.text = widget.existingTemplate!.unit;
      _updateTargetValue();
    } else {
      _selectedTrackingType = 'time';
      _targetValue = 5; // Default 5 minutes for time tracking
    }
  }

  void _updateTargetValue() {
    setState(() {
      switch (_selectedTrackingType) {
        case 'binary':
          _targetValue = null;
          break;
        case 'quantitative':
          _targetValue = _targetValue ?? 1; // Keep existing or default to 1
          break;
        case 'time':
          _targetValue = _targetValue ?? 5; // Keep existing or default to 5 minutes
          break;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
    });
    try {
      if (widget.existingTemplate != null) {
        // Update existing template
        await NonProductiveService.updateNonProductiveTemplate(
          templateId: widget.existingTemplate!.reference.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          trackingType: _selectedTrackingType,
          target: _targetValue,
          unit: _unitController.text.trim().isEmpty
              ? null
              : _unitController.text.trim(),
          userId: currentUserUid,
        );
        // Fetch updated template
        final updatedDoc = await widget.existingTemplate!.reference.get();
        if (updatedDoc.exists) {
          final updated = ActivityRecord.fromSnapshot(updatedDoc);
          if (widget.onTemplateUpdated != null) {
            widget.onTemplateUpdated!(updated);
          }
        }
      } else {
        // Create new template
        final templateRef = await NonProductiveService.createNonProductiveTemplate(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          trackingType: _selectedTrackingType,
          target: _targetValue,
          unit: _unitController.text.trim().isEmpty
              ? null
              : _unitController.text.trim(),
          userId: currentUserUid,
        );
        // Fetch created template
        final createdDoc = await templateRef.get();
        if (createdDoc.exists) {
          final created = ActivityRecord.fromSnapshot(createdDoc);
          if (widget.onTemplateCreated != null) {
            widget.onTemplateCreated!(created);
          }
        }
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existingTemplate != null
                ? 'Template updated successfully!'
                : 'Template created successfully!'),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existingTemplate != null
          ? 'Edit Non-Productive Template'
          : 'Create Non-Productive Template'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'e.g., Sleep, Travel, Rest',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Text(
                'Tracking Type',
                style: FlutterFlowTheme.of(context).titleSmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedTrackingType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: _trackingTypes.map((String type) {
                  String displayName;
                  switch (type) {
                    case 'binary':
                      displayName = 'Yes/No (Binary)';
                      break;
                    case 'quantitative':
                      displayName = 'Quantity';
                      break;
                    case 'time':
                      displayName = 'Time Duration';
                      break;
                    default:
                      displayName = type;
                  }
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(displayName),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedTrackingType = newValue;
                    });
                    _updateTargetValue();
                  }
                },
              ),
              const SizedBox(height: 16),
              if (_selectedTrackingType == 'quantitative') ...[
                TextFormField(
                  initialValue: _targetValue?.toString() ?? '1',
                  decoration: const InputDecoration(
                    labelText: 'Target Quantity *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    _targetValue = int.tryParse(value) ?? 1;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _unitController,
                  decoration: const InputDecoration(
                    labelText: 'Unit (e.g., glasses, pages)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ] else if (_selectedTrackingType == 'time') ...[
                TextFormField(
                  initialValue: _targetValue?.toString() ?? '5',
                  decoration: const InputDecoration(
                    labelText: 'Target Duration (minutes) *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    _targetValue = int.tryParse(value) ?? 5;
                  },
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Note: Non-productive items track time but do not earn points.',
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      color: FlutterFlowTheme.of(context).secondaryText,
                    ),
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
          onPressed: _isSaving ? null : _saveTemplate,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.existingTemplate != null ? 'Update' : 'Create'),
        ),
      ],
    );
  }
}

