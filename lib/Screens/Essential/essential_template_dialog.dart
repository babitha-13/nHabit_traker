import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/essential_service.dart';
import 'package:habit_tracker/Helper/backend/time_logging_preferences_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_dialog.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Screens/Create%20Catagory/create_category.dart';

class essentialTemplateDialog extends StatefulWidget {
  final ActivityRecord? existingTemplate;
  final Function(ActivityRecord)? onTemplateCreated;
  final Function(ActivityRecord)? onTemplateUpdated;

  const essentialTemplateDialog({
    Key? key,
    this.existingTemplate,
    this.onTemplateCreated,
    this.onTemplateUpdated,
  }) : super(key: key);

  @override
  _essentialTemplateDialogState createState() =>
      _essentialTemplateDialogState();
}

class _essentialTemplateDialogState extends State<essentialTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSaving = false;
  int? _timeEstimateMinutes;
  int? _defaultTimeEstimateMinutes;
  TimeOfDay? _selectedDueTime;
  bool _frequencyEnabled = false;
  FrequencyConfig? _frequencyConfig;
  List<CategoryRecord> _categories = [];
  String? _selectedCategoryId;
  bool _isLoadingCategories = false;
  static const String _createNewCategoryValue = '__create_new__';

  @override
  void initState() {
    super.initState();
    if (widget.existingTemplate != null) {
      _nameController.text = widget.existingTemplate!.name;
      _descriptionController.text = widget.existingTemplate!.description;
      _selectedCategoryId = widget.existingTemplate!.categoryId.isNotEmpty
          ? widget.existingTemplate!.categoryId
          : null;
      if (widget.existingTemplate!.hasTimeEstimateMinutes()) {
        _timeEstimateMinutes = widget.existingTemplate!.timeEstimateMinutes;
      }
      if (widget.existingTemplate!.hasDueTime()) {
        _selectedDueTime =
            TimeUtils.stringToTimeOfDay(widget.existingTemplate!.dueTime);
      }
      _initializeFrequencyFromTemplate(widget.existingTemplate!);
    } else {
      _frequencyEnabled = false;
      _frequencyConfig = _defaultFrequencyConfig();
    }
    _loadDefaultTimeEstimate();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoadingCategories = true;
    });
    try {
      var categories = await queryEssentialCategoriesOnce(
        userId: currentUserUid,
        callerTag: 'essentialTemplateDialog._loadCategories',
      );

      // If no categories exist, ensure default "Others" category is created
      if (categories.isEmpty) {
        try {
          final defaultCategory = await getOrCreateEssentialDefaultCategory(
            userId: currentUserUid,
          );
          categories = [defaultCategory];
        } catch (e) {
          // If default category creation fails, continue with empty list
          print('Error creating default essential category: $e');
        }
      }

      if (mounted) {
        setState(() {
          _categories = categories;
          _isLoadingCategories = false;
          // If no category is selected and we have categories, select the first one
          // Or if editing and categoryId is empty, try to get default
          if (_selectedCategoryId == null && categories.isNotEmpty) {
            // Try to find "Others" category first, otherwise use first category
            try {
              final othersCategory = categories.firstWhere(
                (c) => c.name == 'Others',
              );
              _selectedCategoryId = othersCategory.reference.id;
            } catch (e) {
              _selectedCategoryId = categories.first.reference.id;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCategories = false;
        });
      }
    }
  }

  Future<void> _loadDefaultTimeEstimate() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;
      final minutes =
          await TimeLoggingPreferencesService.getDefaultDurationMinutes(userId);
      if (!mounted) return;
      setState(() => _defaultTimeEstimateMinutes = minutes);
    } catch (e) {
      print('essentialTemplateDialog: Failed to load default time: $e');
    }
  }

  /// Check if the current template is a time-target template
  bool _isTimeTarget() {
    return false; // Forced binary
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
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
      final dueTimeString = _selectedDueTime != null
          ? TimeUtils.timeOfDayToString(_selectedDueTime!)
          : null;
      final freqPayload = _frequencyPayloadForBackend(
          isUpdate: widget.existingTemplate != null);
      // Get category name from selected category
      String? categoryName;
      if (_selectedCategoryId != null) {
        try {
          final selectedCategory = _categories.firstWhere(
            (c) => c.reference.id == _selectedCategoryId,
          );
          categoryName = selectedCategory.name;
        } catch (e) {
          // Category not found, use default
          categoryName = 'Others';
        }
      } else {
        categoryName = 'Others';
      }
      if (widget.existingTemplate != null) {
        // Update existing template
        await essentialService.updateessentialTemplate(
          templateId: widget.existingTemplate!.reference.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          categoryId: _selectedCategoryId,
          categoryName: categoryName,
          trackingType: 'binary',
          target: null,
          unit: null,
          userId: currentUserUid,
          timeEstimateMinutes: _timeEstimateMinutes != null
              ? _timeEstimateMinutes!.clamp(1, 600)
              : null,
          dueTime: dueTimeString,
          frequencyType: freqPayload.frequencyType,
          everyXValue: freqPayload.everyXValue,
          everyXPeriodType: freqPayload.everyXPeriodType,
          specificDays: freqPayload.specificDays,
        );
        // Fetch updated template
        final updatedDoc = await widget.existingTemplate!.reference.get();
        if (updatedDoc.exists && mounted) {
          final updated = ActivityRecord.fromSnapshot(updatedDoc);
          if (widget.onTemplateUpdated != null) {
            widget.onTemplateUpdated!(updated);
          }
        }
      } else {
        // Create new template
        final templateRef = await essentialService.createessentialTemplate(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          categoryId: _selectedCategoryId,
          categoryName: categoryName,
          trackingType: 'binary',
          target: null,
          unit: null,
          userId: currentUserUid,
          timeEstimateMinutes: _timeEstimateMinutes != null
              ? _timeEstimateMinutes!.clamp(1, 600)
              : null,
          dueTime: dueTimeString,
          frequencyType: freqPayload.frequencyType,
          everyXValue: freqPayload.everyXValue,
          everyXPeriodType: freqPayload.everyXPeriodType,
          specificDays: freqPayload.specificDays,
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.existingTemplate != null
                  ? 'Template updated successfully!'
                  : 'Template created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
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
        ? 'Edit essential Template'
        : 'Create Essential Template';

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
                      maxLines: 1),
                  const SizedBox(height: 12),
                  Text(
                    'Category',
                    style: theme.bodySmall.override(
                      color: theme.secondaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildCategoryDropdown(theme),
                  const SizedBox(height: 12),
                  // Show time estimate field if both switches are enabled and not time-target
                  if (!_isTimeTarget()) ...[
                    const SizedBox(height: 12),
                    _buildTimeEstimateField(theme),
                  ],
                  const SizedBox(height: 16),
                  _buildDueTimeField(theme),
                  const SizedBox(height: 12),
                  _buildFrequencyField(theme),
                  const SizedBox(height: 16),
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

  Widget _buildCategoryDropdown(FlutterFlowTheme theme) {
    // Use a key to force rebuild when categories or selected category changes
    final dropdownKey = ValueKey(
        'category_dropdown_${_categories.length}_$_selectedCategoryId');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.tertiary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: DropdownButtonFormField<String>(
        key: dropdownKey,
        value: _selectedCategoryId,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        isExpanded: true,
        icon: Icon(Icons.keyboard_arrow_down, color: theme.secondaryText),
        dropdownColor: theme.secondaryBackground,
        style: theme.bodySmall,
        hint: Text('Select Category',
            style: TextStyle(color: theme.secondaryText)),
        items: [
          ..._categories.map(
            (c) => DropdownMenuItem(
              value: c.reference.id,
              child: Text(
                c.name,
                style: theme.bodySmall,
              ),
            ),
          ),
          const DropdownMenuItem(
            value: _createNewCategoryValue,
            child: Row(
              children: [
                Icon(Icons.add, size: 16),
                SizedBox(width: 8),
                Text(
                  'Create New Category...',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
        onChanged: _isLoadingCategories
            ? null
            : (v) {
                if (v == _createNewCategoryValue) {
                  _showCreateCategoryDialog();
                } else if (mounted && v != null) {
                  setState(() => _selectedCategoryId = v);
                }
              },
        menuMaxHeight: 260,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Future<void> _showCreateCategoryDialog() async {
    final newCategoryId = await showDialog<String>(
      context: context,
      builder: (context) => CreateCategory(categoryType: 'essential'),
    );
    if (newCategoryId != null) {
      // Reload categories to include the new one
      await _loadCategories();
      // Select the newly created category
      if (mounted) {
        setState(() {
          _selectedCategoryId = newCategoryId;
        });
      }
    }
  }

  Widget _buildTimeEstimateField(FlutterFlowTheme theme) {
    final hintText = _defaultTimeEstimateMinutes != null
        ? '${_defaultTimeEstimateMinutes!} mins (default)'
        : 'Leave empty to use default';

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Time Estimate',
        labelStyle: TextStyle(color: theme.secondaryText),
        filled: true,
        fillColor: theme.tertiary.withOpacity(0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.surfaceBorderColor),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      child: Row(
        children: [
          Icon(Icons.timelapse, size: 20, color: theme.secondaryText),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              initialValue: _timeEstimateMinutes?.toString() ?? '',
              keyboardType: TextInputType.number,
              style: theme.bodyMedium,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: hintText,
                hintStyle: theme.bodySmall.override(
                  color: theme.secondaryText.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
              onChanged: (v) {
                setState(() {
                  _timeEstimateMinutes = v.isEmpty ? null : int.tryParse(v);
                });
              },
            ),
          ),
          if (_timeEstimateMinutes != null)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => _timeEstimateMinutes = null),
            ),
        ],
      ),
    );
  }

  Widget _buildDueTimeField(FlutterFlowTheme theme) {
    final label = _selectedDueTime != null
        ? _selectedDueTime!.format(context)
        : 'Add Due time';
    return InkWell(
      onTap: _pickDueTime,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Due Time',
          labelStyle: TextStyle(color: theme.secondaryText),
          filled: true,
          fillColor: theme.tertiary.withOpacity(0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.surfaceBorderColor),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 20, color: theme.secondaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: theme.bodyMedium.override(
                  color: _selectedDueTime != null
                      ? theme.primaryText
                      : theme.secondaryText,
                ),
              ),
            ),
            if (_selectedDueTime != null)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _selectedDueTime = null),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrequencyField(FlutterFlowTheme theme) {
    final summary = _frequencySummary();
    return InkWell(
      onTap: _openFrequencyDialog,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Frequency',
          labelStyle: TextStyle(color: theme.secondaryText),
          filled: true,
          fillColor: theme.tertiary.withOpacity(0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.surfaceBorderColor),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: Row(
          children: [
            Icon(Icons.repeat, size: 20, color: theme.secondaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                summary,
                style: theme.bodyMedium.override(
                  color: _frequencyEnabled
                      ? theme.primaryText
                      : theme.secondaryText,
                ),
              ),
            ),
            if (_frequencyEnabled)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _clearFrequency,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDueTime() async {
    final initial = _selectedDueTime ?? TimeUtils.getCurrentTime();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      setState(() {
        _selectedDueTime = picked;
      });
    }
  }

  Future<void> _openFrequencyDialog() async {
    final config = await showFrequencyConfigDialog(
      context: context,
      initialConfig: _frequencyConfig ?? _defaultFrequencyConfig(),
      allowedTypes: const {
        FrequencyType.everyXPeriod,
        FrequencyType.specificDays,
      },
    );
    if (config != null) {
      setState(() {
        _frequencyEnabled = true;
        _frequencyConfig = config;
      });
    }
  }

  void _clearFrequency() {
    setState(() {
      _frequencyEnabled = false;
      _frequencyConfig = _defaultFrequencyConfig();
    });
  }

  String _frequencySummary() {
    if (!_frequencyEnabled || _frequencyConfig == null) {
      return "Manual only (won't auto-schedule)";
    }
    final config = _frequencyConfig!;
    switch (config.type) {
      case FrequencyType.specificDays:
        final days = config.selectedDays.isNotEmpty
            ? config.selectedDays
            : [1, 2, 3, 4, 5, 6, 7];
        final label = days.map(_weekdayShortLabel).join(', ');
        return 'Specific days ($label)';
      case FrequencyType.everyXPeriod:
      default:
        final value = config.everyXValue > 0 ? config.everyXValue : 1;
        final unit = _describePeriod(config.everyXPeriodType, value);
        if (value == 1 && config.everyXPeriodType == PeriodType.days) {
          return 'Every day';
        }
        return 'Every $value $unit';
    }
  }

  FrequencyConfig _defaultFrequencyConfig() {
    return FrequencyConfig(
      type: FrequencyType.everyXPeriod,
      everyXValue: 1,
      everyXPeriodType: PeriodType.days,
    );
  }

  void _initializeFrequencyFromTemplate(ActivityRecord template) {
    if (template.frequencyType.isEmpty) {
      _frequencyEnabled = false;
      _frequencyConfig = _defaultFrequencyConfig();
      return;
    }
    _frequencyEnabled = true;
    _frequencyConfig = _frequencyConfigFromTemplate(template);
  }

  FrequencyConfig _frequencyConfigFromTemplate(ActivityRecord template) {
    final type = template.frequencyType;
    if (type == 'specific_days') {
      final days = template.specificDays.isNotEmpty
          ? List<int>.from(template.specificDays)
          : [1, 2, 3, 4, 5, 6, 7];
      return FrequencyConfig(
        type: FrequencyType.specificDays,
        selectedDays: days,
      );
    }
    final value = template.everyXValue > 0 ? template.everyXValue : 1;
    final period = _periodTypeFromString(template.everyXPeriodType);
    return FrequencyConfig(
      type: FrequencyType.everyXPeriod,
      everyXValue: value,
      everyXPeriodType: period,
    );
  }

  PeriodType _periodTypeFromString(String? value) {
    switch (value) {
      case 'week':
        return PeriodType.weeks;
      case 'month':
        return PeriodType.months;
      default:
        return PeriodType.days;
    }
  }

  String _periodTypeToString(PeriodType type) {
    switch (type) {
      case PeriodType.weeks:
        return 'week';
      case PeriodType.months:
        return 'month';
      default:
        return 'day';
    }
  }

  String _describePeriod(PeriodType type, int value) {
    final plural = value == 1 ? '' : 's';
    switch (type) {
      case PeriodType.weeks:
        return 'week$plural';
      case PeriodType.months:
        return 'month$plural';
      default:
        return 'day$plural';
    }
  }

  String _weekdayShortLabel(int day) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (day < 1 || day > 7) return 'Day $day';
    return labels[day - 1];
  }

  _FrequencyPayload _frequencyPayloadForBackend({required bool isUpdate}) {
    if (!_frequencyEnabled || _frequencyConfig == null) {
      return _FrequencyPayload(
        frequencyType: isUpdate ? '' : null,
        everyXValue: null,
        everyXPeriodType: null,
        specificDays: isUpdate ? <int>[] : null,
      );
    }
    final config = _frequencyConfig!;
    switch (config.type) {
      case FrequencyType.specificDays:
        final days = config.selectedDays.isNotEmpty
            ? List<int>.from(config.selectedDays)
            : [1, 2, 3, 4, 5, 6, 7];
        return _FrequencyPayload(
          frequencyType: 'specific_days',
          specificDays: days,
        );
      case FrequencyType.everyXPeriod:
      default:
        final value = config.everyXValue > 0 ? config.everyXValue : 1;
        return _FrequencyPayload(
          frequencyType: 'every_x',
          everyXValue: value,
          everyXPeriodType: _periodTypeToString(config.everyXPeriodType),
        );
    }
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

class _FrequencyPayload {
  final String? frequencyType;
  final int? everyXValue;
  final String? everyXPeriodType;
  final List<int>? specificDays;
  const _FrequencyPayload({
    this.frequencyType,
    this.everyXValue,
    this.everyXPeriodType,
    this.specificDays,
  });
}
