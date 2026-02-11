import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Calendar/Helpers/calendar_models.dart';
import 'Services/manual_time_log_helper_service.dart';
import 'Services/manual_time_log_initialization_service.dart';
import 'Services/manual_time_log_search_service.dart';
import 'Services/manual_time_log_preview_service.dart';
import 'Services/manual_time_log_datetime_service.dart';
import 'Services/manual_time_log_save_service.dart';
import 'Services/manual_time_log_ui_builders_service.dart';

// Manual time log modal for logging time manually, used by both Timer and Calendar pages

// Public typedef for services to reference the state class
typedef ManualTimeLogModalState = _ManualTimeLogModalState;

class ManualTimeLogModal extends StatefulWidget {
  final DateTime selectedDate;
  final VoidCallback onSave;
  final bool markCompleteOnSave;

  const ManualTimeLogModal({
    super.key,
    required this.selectedDate,
    required this.onSave,
    this.initialStartTime,
    this.initialEndTime,
    this.onPreviewChange,
    this.fromTimer = false,
    this.editMetadata,
    this.markCompleteOnSave = true,
  });

  final DateTime? initialStartTime;
  final DateTime? initialEndTime;
  final Function(DateTime start, DateTime end, String type, Color? color)?
      onPreviewChange;
  final bool fromTimer; // If true, auto-mark binary tasks as complete
  final CalendarEventMetadata?
      editMetadata; // If provided, we're editing an existing entry

  @override
  State<ManualTimeLogModal> createState() => _ManualTimeLogModalState();
}

class _ManualTimeLogModalState extends State<ManualTimeLogModal> {
  final TextEditingController _activityController = TextEditingController();
  final FocusNode _activityFocusNode = FocusNode();
  final GlobalKey _textFieldKey = GlobalKey();

  // 'task', 'habit', 'essential'
  String _selectedType = 'task';
  List<CategoryRecord> _allCategories = [];
  CategoryRecord? _selectedCategory;

  late DateTime _startTime;
  late DateTime _endTime;
  bool _isLoading = false;

  // Search/Suggestions
  List<ActivityRecord> _allActivities = [];
  List<ActivityRecord> _suggestions = [];
  bool _showSuggestions = false;
  ActivityRecord? _selectedTemplate;

  // OverlayEntry for dropdown suggestions
  OverlayEntry? _overlayEntry;

  // Completion controls
  bool _markAsComplete = false; // For binary tasks
  int _quantityValue = 0; // For quantity tasks

  // Cached default duration for time logging (in minutes)
  int _defaultDurationMinutes = 10;

  // ==================== PUBLIC ACCESSORS FOR SERVICES ====================
  // These methods allow services in separate files to access private state members
  TextEditingController get activityController => _activityController;
  FocusNode get activityFocusNode => _activityFocusNode;
  GlobalKey get textFieldKey => _textFieldKey;
  String get selectedType => _selectedType;
  set selectedType(String value) => _selectedType = value;
  List<CategoryRecord> get allCategories => _allCategories;
  set allCategories(List<CategoryRecord> value) => _allCategories = value;
  CategoryRecord? get selectedCategory => _selectedCategory;
  set selectedCategory(CategoryRecord? value) => _selectedCategory = value;
  DateTime get startTime => _startTime;
  set startTime(DateTime value) => _startTime = value;
  DateTime get endTime => _endTime;
  set endTime(DateTime value) => _endTime = value;
  bool get isLoading => _isLoading;
  set isLoading(bool value) => _isLoading = value;
  List<ActivityRecord> get allActivities => _allActivities;
  set allActivities(List<ActivityRecord> value) => _allActivities = value;
  List<ActivityRecord> get suggestions => _suggestions;
  set suggestions(List<ActivityRecord> value) => _suggestions = value;
  bool get showSuggestions => _showSuggestions;
  set showSuggestions(bool value) => _showSuggestions = value;
  ActivityRecord? get selectedTemplate => _selectedTemplate;
  set selectedTemplate(ActivityRecord? value) => _selectedTemplate = value;
  OverlayEntry? get overlayEntry => _overlayEntry;
  set overlayEntry(OverlayEntry? value) => _overlayEntry = value;
  bool get markAsComplete => _markAsComplete;
  set markAsComplete(bool value) => _markAsComplete = value;
  int get quantityValue => _quantityValue;
  set quantityValue(int value) => _quantityValue = value;
  int get defaultDurationMinutes => _defaultDurationMinutes;
  set defaultDurationMinutes(int value) => _defaultDurationMinutes = value;

  @override
  void initState() {
    super.initState();
    ManualTimeLogInitializationService.initializeState(this);
  }

  @override
  void dispose() {
    ManualTimeLogInitializationService.dispose(this);
    super.dispose();
  }

  Future<void> _loadDefaultDuration() async {
    return ManualTimeLogInitializationService.loadDefaultDuration(this);
  }

  Future<void> _loadCategories() async {
    return ManualTimeLogInitializationService.loadCategories(this);
  }

  Future<void> _loadActivities() async {
    return ManualTimeLogInitializationService.loadActivities(this);
  }

  void _onSearchChanged() {
    return ManualTimeLogSearchService.onSearchChanged(this);
  }

  void _removeOverlay() {
    return ManualTimeLogSearchService.removeOverlay(this);
  }

  void _showOverlay() {
    return ManualTimeLogSearchService.showOverlay(this);
  }

  void _selectType(String type) {
    return ManualTimeLogPreviewService.selectType(this, type);
  }

  void _updatePreview() {
    return ManualTimeLogPreviewService.updatePreview(this);
  }

  bool _shouldMarkCompleteOnSave() {
    return ManualTimeLogHelperService.shouldMarkCompleteOnSave(this);
  }

  Future<void> _pickStartTime() async {
    return ManualTimeLogDateTimeService.pickStartTime(this);
  }

  Future<void> _pickEndTime() async {
    return ManualTimeLogDateTimeService.pickEndTime(this);
  }

  Future<void> _saveEntry() async {
    return ManualTimeLogSaveService.saveEntry(this);
  }

  Future<void> _deleteEntry() async {
    return ManualTimeLogSaveService.deleteEntry(this);
  }

  Future<bool> _onWillPop() async {
    return ManualTimeLogHelperService.onWillPop(this);
  }

  void _updateDefaultCategory() {
    return ManualTimeLogHelperService.updateDefaultCategory(this);
  }

  @override
  Widget build(BuildContext context) {
    return ManualTimeLogUIBuildersService.build(this, context);
  }

  Widget _buildTypeChip(String label, String value, FlutterFlowTheme theme) {
    return ManualTimeLogUIBuildersService.buildTypeChip(
        this, label, value, theme);
  }

  Widget _buildCategoryDropdown(FlutterFlowTheme theme) {
    return ManualTimeLogUIBuildersService.buildCategoryDropdown(this, theme);
  }

  Widget _buildCompletionControls(FlutterFlowTheme theme) {
    return ManualTimeLogUIBuildersService.buildCompletionControls(this, theme);
  }
}
