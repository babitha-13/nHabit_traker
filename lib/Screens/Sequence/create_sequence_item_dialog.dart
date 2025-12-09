import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/sequence_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
class CreateSequenceItemDialog extends StatefulWidget {
  final Function(ActivityRecord) onItemCreated;
  const CreateSequenceItemDialog({
    Key? key,
    required this.onItemCreated,
  }) : super(key: key);
  @override
  _CreateSequenceItemDialogState createState() =>
      _CreateSequenceItemDialogState();
}
class _CreateSequenceItemDialogState extends State<CreateSequenceItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _unitController = TextEditingController();
  String _selectedTrackingType = 'binary';
  dynamic _targetValue;
  bool _isCreating = false;
  final List<String> _trackingTypes = ['binary', 'quantitative', 'time'];
  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _unitController.dispose();
    super.dispose();
  }
  void _updateTargetValue() {
    setState(() {
      switch (_selectedTrackingType) {
        case 'binary':
          _targetValue = null;
          break;
        case 'quantitative':
          _targetValue = 1; // Default quantity
          break;
        case 'time':
          _targetValue = 5; // Default 5 minutes
          break;
      }
    });
  }
  Future<void> _createSequenceItem() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isCreating = true;
    });
    try {
      final sequenceItem = await SequenceService.createSequenceItem(
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
      // Get the created activity record
      final activityDoc = await ActivityRecord.collectionForUser(currentUserUid)
          .doc(sequenceItem.id)
          .get();
      if (activityDoc.exists) {
        final activity = ActivityRecord.fromSnapshot(activityDoc);
        widget.onItemCreated(activity);
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Non-productive item "${activity.name}" created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating non-productive item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Non-Productive Item'),
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
                  labelText: 'Item Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an item name';
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
                maxLines: 2,
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
                  initialValue: '1',
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
                  initialValue: '5',
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
                'Note: This item is non-productive and will only appear in sequences. It tracks time but does not earn points.',
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
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isCreating ? null : _createSequenceItem,
          child: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
