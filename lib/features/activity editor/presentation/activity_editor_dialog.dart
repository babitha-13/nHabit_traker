import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/features/activity%20editor/Frequency_config/frequency_config_model.dart';
import 'package:habit_tracker/features/activity%20editor/Services/activity_editor_helper_service.dart';
import 'package:habit_tracker/features/activity%20editor/Services/activity_editor_initialization_service.dart';
import 'package:habit_tracker/features/activity%20editor/Services/activity_editor_ui_builders_service.dart';
import 'package:habit_tracker/features/activity%20editor/Reminder_config/reminder_config.dart';

// Public typedef for services to reference the state class
// This allows service files to reference the private state class
typedef ActivityEditorDialogState = _ActivityEditorDialogState;

class ActivityEditorDialog extends StatefulWidget {
  final ActivityRecord? activity; // Null for creation
  final bool isHabit;
  final List<CategoryRecord> categories;
  final Function(ActivityRecord?)? onSave; // Optional callback
  final ActivityInstanceRecord? instance;
  final bool?
      isEssential; // Optional: if null, derived from activity.categoryType

  const ActivityEditorDialog({
    super.key,
    this.activity,
    required this.isHabit,
    required this.categories,
    this.onSave,
    this.instance,
    this.isEssential,
  });

  @override
  State<ActivityEditorDialog> createState() => _ActivityEditorDialogState();
}

class _ActivityEditorDialogState extends State<ActivityEditorDialog> {
  late TextEditingController _titleController;
  late TextEditingController _unitController;
  late TextEditingController _descriptionController;
  String? _selectedCategoryId;
  String? _selectedTrackingType;
  int _targetNumber = 1;
  Duration _targetDuration = const Duration(hours: 1);
  String _unit = '';
  int _priority = 1;
  DateTime? _dueDate;
  DateTime? _endDate;
  TimeOfDay? _selectedDueTime;
  bool quickIsTaskRecurring = false;
  FrequencyConfig? _frequencyConfig;
  DateTime? _originalStartDate;
  FrequencyConfig? _originalFrequencyConfig;
  List<ReminderConfig> _reminders = [];
  bool _isSaving = false;
  List<CategoryRecord> _loadedCategories = [];
  bool _isLoadingCategories = false;
  int? _timeEstimateMinutes;
  int? _defaultTimeEstimateMinutes;
  bool _frequencyEnabled = false; // For essentials: frequency can be disabled

  bool get _isRecurring => quickIsTaskRecurring && _frequencyConfig != null;

  /// Check if this is an essential activity
  bool get _isEssential {
    if (widget.isEssential != null) return widget.isEssential!;
    return widget.activity?.categoryType == 'essential';
  }

  /// Get the categories to use - prefer loaded categories, fallback to widget categories
  List<CategoryRecord> get _categories {
    return _loadedCategories.isNotEmpty ? _loadedCategories : widget.categories;
  }

  @override
  void initState() {
    super.initState();
    final t = widget.activity;

    // Initialize controllers first (they are late final and must be initialized here)
    _titleController = TextEditingController(text: t?.name ?? '');
    _unitController = TextEditingController(text: t?.unit ?? '');
    _descriptionController = TextEditingController(text: t?.description ?? '');

    // Delegate rest of initialization to service
    ActivityEditorInitializationService.initializeState(this);
  }

  @override
  void dispose() {
    ActivityEditorInitializationService.dispose(this);
    super.dispose();
  }

  // ==================== PUBLIC ACCESSORS FOR SERVICES ====================
  // These methods allow services in separate files to access private state members
  TextEditingController get titleController => _titleController;
  TextEditingController get unitController => _unitController;
  TextEditingController get descriptionController => _descriptionController;
  String? get selectedCategoryId => _selectedCategoryId;
  set selectedCategoryId(String? value) => _selectedCategoryId = value;
  String? get selectedTrackingType => _selectedTrackingType;
  set selectedTrackingType(String? value) => _selectedTrackingType = value;
  int get targetNumber => _targetNumber;
  set targetNumber(int value) => _targetNumber = value;
  Duration get targetDuration => _targetDuration;
  set targetDuration(Duration value) => _targetDuration = value;
  String get unit => _unit;
  set unit(String value) => _unit = value;
  int get priority => _priority;
  set priority(int value) => _priority = value;
  DateTime? get dueDate => _dueDate;
  set dueDate(DateTime? value) => _dueDate = value;
  DateTime? get endDate => _endDate;
  set endDate(DateTime? value) => _endDate = value;
  TimeOfDay? get selectedDueTime => _selectedDueTime;
  set selectedDueTime(TimeOfDay? value) => _selectedDueTime = value;
  // quickIsTaskRecurring is already public (no underscore)
  FrequencyConfig? get frequencyConfig => _frequencyConfig;
  set frequencyConfig(FrequencyConfig? value) => _frequencyConfig = value;
  DateTime? get originalStartDate => _originalStartDate;
  set originalStartDate(DateTime? value) => _originalStartDate = value;
  FrequencyConfig? get originalFrequencyConfig => _originalFrequencyConfig;
  set originalFrequencyConfig(FrequencyConfig? value) =>
      _originalFrequencyConfig = value;
  List<ReminderConfig> get reminders => _reminders;
  set reminders(List<ReminderConfig> value) => _reminders = value;
  bool get isSaving => _isSaving;
  set isSaving(bool value) => _isSaving = value;
  List<CategoryRecord> get loadedCategories => _loadedCategories;
  set loadedCategories(List<CategoryRecord> value) => _loadedCategories = value;
  bool get isLoadingCategories => _isLoadingCategories;
  set isLoadingCategories(bool value) => _isLoadingCategories = value;
  int? get timeEstimateMinutes => _timeEstimateMinutes;
  set timeEstimateMinutes(int? value) => _timeEstimateMinutes = value;
  int? get defaultTimeEstimateMinutes => _defaultTimeEstimateMinutes;
  set defaultTimeEstimateMinutes(int? value) =>
      _defaultTimeEstimateMinutes = value;
  bool get frequencyEnabled => _frequencyEnabled;
  set frequencyEnabled(bool value) => _frequencyEnabled = value;
  bool get isRecurring => _isRecurring;
  bool get isEssential => _isEssential;
  List<CategoryRecord> get categories => _categories;
  String? get validCategoryId => _validCategoryId;

  /// Get the valid category ID for the dropdown
  /// Returns null if no category is selected or if the selected category is invalid
  String? get _validCategoryId {
    return ActivityEditorHelperService.getValidCategoryId(this);
  }

  @override
  Widget build(BuildContext context) {
    return ActivityEditorUIBuildersService.build(this, context);
  }
}
