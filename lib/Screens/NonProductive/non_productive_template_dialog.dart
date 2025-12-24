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
  int? _timeEstimateMinutes;

  @override
  void initState() {
    super.initState();
    if (widget.existingTemplate != null) {
      _nameController.text = widget.existingTemplate!.name;
      _descriptionController.text = widget.existingTemplate!.description;
      _selectedTrackingType = widget.existingTemplate!.trackingType;
      _targetValue = widget.existingTemplate!.target;
      _unitController.text = widget.existingTemplate!.unit;
      if (widget.existingTemplate!.hasTimeEstimateMinutes()) {
        _timeEstimateMinutes = widget.existingTemplate!.timeEstimateMinutes;
      }
      _updateTargetValue();
    } else {
      _selectedTrackingType = 'time';
      _targetValue = 5; // Default 5 minutes for time tracking
    }
  }

  /// Check if the current template is a time-target template
  bool _isTimeTarget() {
    if (_selectedTrackingType != 'time') return false;
    final targetValue = _targetValue is int ? _targetValue as int : 0;
    return targetValue > 0;
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
          _targetValue =
              _targetValue ?? 5; // Keep existing or default to 5 minutes
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
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
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
          timeEstimateMinutes: _timeEstimateMinutes != null
              ? _timeEstimateMinutes!.clamp(1, 600)
              : null,
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
        final templateRef =
            await NonProductiveService.createNonProductiveTemplate(
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
          timeEstimateMinutes: _timeEstimateMinutes != null
              ? _timeEstimateMinutes!.clamp(1, 600)
              : null,
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
    final theme = FlutterFlowTheme.of(context);
    final title = widget.existingTemplate != null
        ? 'Edit Non-Productive Template'
        : 'Create Non-Productive Template';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          gradient: theme.neumorphicGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.surfaceBorderColor,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 2),
              blurRadius: 4,
              spreadRadius: 0,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.titleMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(theme, _nameController, 'Name *'),
                  const SizedBox(height: 12),
                  _buildTextField(
                      theme, _descriptionController, 'Description (Optional)',
                      maxLines: 3),
                  const SizedBox(height: 12),
                  Text(
                    'Tracking Type',
                    style: theme.bodySmall.override(
                      color: theme.secondaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildTrackingTypeDropdown(theme),
                  const SizedBox(height: 12),
                  if (_selectedTrackingType == 'quantitative') ...[
                    _buildQuantitativeFields(theme),
                  ] else if (_selectedTrackingType == 'time') ...[
                    _buildTimeFields(theme),
                  ],
                  // Show time estimate field if both switches are enabled and not time-target
                  if (!_isTimeTarget()) ...[
                    const SizedBox(height: 12),
                    _buildTimeEstimateField(theme),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.accent4.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.accent4),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: theme.secondaryText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Non-productive items track time but do not earn points.',
                            style: theme.bodySmall.override(
                              color: theme.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildActionButtons(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      FlutterFlowTheme theme, TextEditingController controller, String hint,
      {int maxLines = 1}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.tertiary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        style: theme.bodyMedium,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: theme.secondaryText,
            fontSize: 14,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildTrackingTypeDropdown(FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.tertiary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.surfaceBorderColor, width: 1),
      ),
      child: DropdownButtonFormField<String>(
        value: _selectedTrackingType,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        isExpanded: true,
        icon: Icon(Icons.keyboard_arrow_down, color: theme.secondaryText),
        dropdownColor: theme.secondaryBackground,
        style: theme.bodySmall,
        items: _trackingTypes.map((String type) {
          String displayName;
          switch (type) {
            case 'binary':
              displayName = 'To Do';
              break;
            case 'quantitative':
              displayName = 'Quantity';
              break;
            case 'time':
              displayName = 'Timer';
              break;
            default:
              displayName = type;
          }
          return DropdownMenuItem<String>(
            value: type,
            child: Text(displayName, style: theme.bodySmall),
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
    );
  }

  Widget _buildQuantitativeFields(FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.accent2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.surfaceBorderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Target',
                    style: theme.bodySmall.override(
                        color: theme.primary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.secondaryBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.surfaceBorderColor),
                  ),
                  child: TextFormField(
                    initialValue: _targetValue?.toString() ?? '1',
                    keyboardType: TextInputType.number,
                    style: theme.bodyMedium,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (value) {
                      _targetValue = int.tryParse(value) ?? 1;
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unit',
                    style: theme.bodySmall.override(
                        color: theme.primary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.secondaryBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.surfaceBorderColor),
                  ),
                  child: TextFormField(
                    controller: _unitController,
                    style: theme.bodyMedium,
                    decoration: const InputDecoration(
                      hintText: 'e.g. pages',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeFields(FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.accent2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.surfaceBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Target Duration (minutes)',
              style: theme.bodySmall
                  .override(color: theme.primary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.surfaceBorderColor),
            ),
            child: TextFormField(
              initialValue: _targetValue?.toString() ?? '5',
              keyboardType: TextInputType.number,
              style: theme.bodyMedium,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: (value) {
                _targetValue = int.tryParse(value) ?? 5;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeEstimateField(FlutterFlowTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Time Estimate (minutes)',
          style: theme.bodySmall.override(
            color: theme.secondaryText,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.tertiary.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.surfaceBorderColor,
              width: 1,
            ),
          ),
          child: TextFormField(
            initialValue: _timeEstimateMinutes?.toString() ?? '',
            keyboardType: TextInputType.number,
            style: theme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Leave empty to use default',
              hintStyle: TextStyle(
                color: theme.secondaryText,
                fontSize: 14,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (v) {
              setState(() {
                _timeEstimateMinutes = v.isEmpty ? null : int.tryParse(v);
              });
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Custom time estimate for this activity (1-600 minutes)',
          style: theme.bodySmall.override(
            color: theme.secondaryText,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(FlutterFlowTheme theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: theme.bodyMedium),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            gradient: theme.primaryButtonGradient,
            borderRadius: BorderRadius.circular(theme.buttonRadius),
          ),
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveTemplate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(widget.existingTemplate != null ? 'Update' : 'Create',
                    style: theme.bodyMedium.override(
                        color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
