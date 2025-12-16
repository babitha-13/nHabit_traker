import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

class ManualTimeLogModal extends StatefulWidget {
  final DateTime selectedDate;
  final VoidCallback onSave;

  const ManualTimeLogModal({
    super.key,
    required this.selectedDate,
    required this.onSave,
    this.initialStartTime,
    this.initialEndTime,
    this.onPreviewChange,
    this.fromTimer = false,
  });

  final DateTime? initialStartTime;
  final DateTime? initialEndTime;
  final Function(DateTime start, DateTime end, String type, Color? color)?
      onPreviewChange;
  final bool fromTimer; // If true, auto-mark binary tasks as complete

  @override
  State<ManualTimeLogModal> createState() => _ManualTimeLogModalState();
}

class _ManualTimeLogModalState extends State<ManualTimeLogModal> {
  final TextEditingController _activityController = TextEditingController();
  final FocusNode _activityFocusNode = FocusNode();
  final GlobalKey _textFieldKey = GlobalKey();

  // 'task', 'habit', 'non_productive'
  String _selectedType = 'task';

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

  @override
  void initState() {
    super.initState();
    if (widget.initialStartTime != null) {
      // Ensure initial start time is on the selected date
      final initialStart = widget.initialStartTime!;
      _startTime = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
        initialStart.hour,
        initialStart.minute,
      );
    } else {
      final now = DateTime.now();
      _startTime = DateTime(widget.selectedDate.year, widget.selectedDate.month,
          widget.selectedDate.day, now.hour, now.minute);
    }

    if (widget.initialEndTime != null) {
      // Use the provided end time as-is (preserves exact time from timer)
      // Only adjust date if needed for calendar display
      final initialEnd = widget.initialEndTime!;
      final endDateOnly = DateTime(
        initialEnd.year,
        initialEnd.month,
        initialEnd.day,
      );
      final selectedDateOnly = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        widget.selectedDate.day,
      );

      // If end time is on the next day (crossing midnight), keep it on next day
      // Otherwise, preserve the exact time but adjust date to match selected date
      if (endDateOnly.difference(selectedDateOnly).inDays == 1) {
        // End time is on next day - keep it as-is
        _endTime = initialEnd;
      } else if (endDateOnly.difference(selectedDateOnly).inDays == 0) {
        // End time is on the same day - keep it as-is (preserves seconds)
        _endTime = initialEnd;
      } else {
        // End time is on a different day - adjust date but preserve time
        _endTime = DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
          widget.selectedDate.day,
          initialEnd.hour,
          initialEnd.minute,
          initialEnd.second,
        );
      }
    } else {
      // Default to 10 minutes only when no end time provided (manual calendar entry)
      _endTime = _startTime.add(const Duration(minutes: 10));
    }

    // Ensure end time is after start time
    // Only apply default if end time is invalid (shouldn't happen with timer)
    if (_endTime.isBefore(_startTime) ||
        _endTime.isAtSameMomentAs(_startTime)) {
      // This fallback should only happen for manual calendar entries
      _endTime = _startTime.add(const Duration(minutes: 10));
    }
    _loadActivities();

    // Initial preview update
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePreview();
    });

    _activityController.addListener(_onSearchChanged);
    _activityFocusNode.addListener(() {
      if (!_activityFocusNode.hasFocus) {
        // Delay hiding suggestions to allow tap
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() => _showSuggestions = false);
            _removeOverlay();
          }
        });
      } else {
        setState(() => _showSuggestions = true);
        _onSearchChanged();
      }
    });
  }

  @override
  void dispose() {
    _removeOverlay();
    _activityController.dispose();
    _activityFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadActivities() async {
    final uid = currentUserUid;
    // Include sequence items to ensure non-productive tasks are fetched
    final activities = await queryActivitiesRecordOnce(
      userId: uid,
      includeSequenceItems: true,
    );
    if (mounted) {
      setState(() {
        _allActivities = activities;
      });
    }
  }

  void _onSearchChanged() {
    final query = _activityController.text.toLowerCase();

    setState(() {
      // Filter based on selected type and query
      _suggestions = _allActivities.where((activity) {
        // 1. Filter by type
        bool typeMatch = false;
        if (_selectedType == 'habit') {
          typeMatch = activity.categoryType == 'habit';
        } else if (_selectedType == 'task') {
          typeMatch = activity.categoryType == 'task';
        } else if (_selectedType == 'non_productive') {
          // Include legacy 'sequence_item' as non-productive
          typeMatch = activity.categoryType == 'non_productive' ||
              activity.categoryType == 'sequence_item';
        }

        if (!typeMatch) return false;

        // 2. Filter by name (if query exists)
        if (query.isEmpty) return true;
        return activity.name.toLowerCase().contains(query);
      }).toList();

      // Update visibility based on query and focus
      _showSuggestions = _activityFocusNode.hasFocus;
    });

    // Update overlay based on visibility and suggestions
    if (_showSuggestions && _suggestions.isNotEmpty) {
      // Remove existing overlay and create new one with updated suggestions
      _removeOverlay();
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    _removeOverlay(); // Remove existing overlay if any

    if (_suggestions.isNotEmpty) {
      final theme = FlutterFlowTheme.of(context);
      final RenderBox? renderBox =
          _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) return;

      final size = renderBox.size;
      final offset = renderBox.localToGlobal(Offset.zero);

      _overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          left: offset.dx,
          top: offset.dy +
              size.height +
              4, // Position below text field with small gap
          width: size.width,
          child: Material(
            elevation: 16,
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(1.0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final item = _suggestions[index];
                  return ListTile(
                    title: Text(item.name, style: theme.bodyMedium),
                    subtitle: item.categoryName.isNotEmpty
                        ? Text(item.categoryName, style: theme.bodySmall)
                        : null,
                    dense: true,
                    onTap: () {
                      setState(() {
                        _selectedTemplate = item;
                        _activityController.text = item.name;
                        _showSuggestions = false;

                        // Initialize completion controls based on tracking type
                        // If from timer and binary task, auto-mark as complete
                        if (widget.fromTimer && item.trackingType == 'binary') {
                          _markAsComplete = true;
                        } else {
                          _markAsComplete = false; // Reset checkbox
                        }
                        // Initialize quantity with current value (default to 0 if null)
                        _quantityValue = item.currentValue is int
                            ? item.currentValue as int
                            : (item.currentValue is double
                                ? (item.currentValue as double).toInt()
                                : 0);

                        _updatePreview();
                      });
                      _activityFocusNode.unfocus();
                      _removeOverlay();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  void _selectType(String type) {
    setState(() {
      _selectedType = type;
      _selectedTemplate = null;
      _activityController.clear();
      _removeOverlay();
      _onSearchChanged();
      _updatePreview();
    });
  }

  void _updatePreview() {
    if (widget.onPreviewChange == null) return;

    Color? previewColor;
    if (_selectedType == 'habit') {
      previewColor = Colors.orange;
    } else if (_selectedType == 'non_productive') {
      previewColor = Colors.grey;
    } else {
      previewColor =
          null; // Use default or let cal decide (neutral grey initially)
    }

    widget.onPreviewChange!(
      _startTime,
      _endTime,
      _selectedType,
      previewColor,
    );
  }

  Future<void> _pickStartTime() async {
    // Hide suggestions dropdown before showing time picker
    if (mounted) {
      setState(() => _showSuggestions = false);
    }
    _activityFocusNode.unfocus();
    _removeOverlay();

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (time != null) {
      setState(() {
        // Properly combine selected date with chosen time
        // Use the date from widget.selectedDate and time from picker
        final selectedDateOnly = DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
          widget.selectedDate.day,
        );
        _startTime = selectedDateOnly.add(Duration(
          hours: time.hour,
          minutes: time.minute,
        ));
        // Auto-adjust end time if it's before start time
        if (_endTime.isBefore(_startTime)) {
          _endTime = _startTime.add(const Duration(minutes: 10));
        }
        _updatePreview();
      });
    }
  }

  Future<void> _pickEndTime() async {
    // Hide suggestions dropdown before showing time picker
    if (mounted) {
      setState(() => _showSuggestions = false);
    }
    _activityFocusNode.unfocus();
    _removeOverlay();

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endTime),
    );
    if (time != null) {
      setState(() {
        // Properly combine selected date with chosen time
        // Use the date from widget.selectedDate and time from picker
        final selectedDateOnly = DateTime(
          widget.selectedDate.year,
          widget.selectedDate.month,
          widget.selectedDate.day,
        );
        _endTime = selectedDateOnly.add(Duration(
          hours: time.hour,
          minutes: time.minute,
        ));
        _updatePreview();
      });
    }
  }

  Future<void> _saveEntry() async {
    final name = _activityController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an activity name'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_selectedType == 'habit' && _selectedTemplate == null) {
      // Check if user typed a name that exactly matches an existing habit
      final exactMatch = _allActivities.firstWhereOrNull((a) =>
          a.categoryType == 'habit' &&
          a.name.toLowerCase() == name.toLowerCase());

      if (exactMatch != null) {
        _selectedTemplate = exactMatch;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please select an existing habit from the list. Creating new habits is not allowed here.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // Validate time range
    if (_startTime.isAfter(_endTime) || _startTime.isAtSameMomentAs(_endTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Validate that times are on the selected date (within reasonable bounds)
    final selectedDateStart = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
      0,
      0,
      0,
    );

    final startDateOnly = DateTime(
      _startTime.year,
      _startTime.month,
      _startTime.day,
    );
    final endDateOnly = DateTime(
      _endTime.year,
      _endTime.month,
      _endTime.day,
    );
    final selectedDateOnly = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
    );

    // Check if start time is on the selected date
    if (!startDateOnly.isAtSameMomentAs(selectedDateOnly)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Start time must be on the selected date (${DateFormat('MMM d, y').format(widget.selectedDate)}).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Check if end time is on the same day as start time (or next day if crossing midnight)
    final daysDifference = endDateOnly.difference(startDateOnly).inDays;
    if (daysDifference > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Time entry cannot span more than one day. Please adjust the end time.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Validate duration is reasonable (not too long)
    final duration = _endTime.difference(_startTime);
    if (duration.inHours > 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Time entry cannot be longer than 24 hours. Please adjust the time range.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final templateId = _selectedTemplate?.reference.id;
      debugPrint(
          'ManualTimeLogModal: Saving entry - taskName: ${_selectedTemplate?.name ?? name}, templateId: $templateId, activityType: $_selectedType');
      debugPrint(
          'ManualTimeLogModal: Time range - startTime: $_startTime, endTime: $_endTime');
      debugPrint(
          'ManualTimeLogModal: Selected date: ${widget.selectedDate}, Start date: $startDateOnly, End date: $endDateOnly');
      debugPrint(
          'ManualTimeLogModal: Duration: ${duration.inHours}h ${duration.inMinutes.remainder(60)}m');

      await TaskInstanceService.logManualTimeEntry(
        taskName: _selectedTemplate?.name ?? name,
        startTime: _startTime,
        endTime: _endTime,
        activityType: _selectedType, // 'task', 'habit', 'non_productive'
        templateId: templateId,
      );

      // Handle completion separately if needed
      // If from timer and should mark complete
      if (widget.fromTimer) {
        bool shouldMarkComplete = false;

        // If creating a new task (no template selected), mark as complete
        // Timer tasks are binary by default
        if (_selectedType == 'task' && _selectedTemplate == null) {
          shouldMarkComplete = true;
        }
        // If selected template is binary and checkbox is checked
        else if (_selectedTemplate != null &&
            _selectedTemplate!.trackingType == 'binary' &&
            _markAsComplete) {
          shouldMarkComplete = true;
        }
        // For non-productive, qty, and timer type habits: don't mark complete
        // (shouldMarkComplete stays false)

        if (shouldMarkComplete && templateId != null) {
          // Find the instance that was just created/updated and mark it complete
          try {
            // The logManualTimeEntry creates/updates an instance
            // We need to find it and mark it complete
            // For now, completion is handled automatically for new task instances
            // in logManualTimeEntry, so we may not need to do anything here
            // But if we do, we'd need to query for the instance
          } catch (e) {
            debugPrint('Error marking instance as complete: $e');
            // Don't fail the save if completion marking fails
          }
        }
      }

      // Get root context before closing modal
      final rootContext = Navigator.of(context, rootNavigator: true).context;

      // Close modal first, then show success and call onSave
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSave();
        // Show success message after a short delay to ensure modal is closed
        Future.delayed(const Duration(milliseconds: 300), () {
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              const SnackBar(
                content: Text('Time entry logged successfully!'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
          }
        });
      }
    } catch (e) {
      // Log detailed error for debugging
      debugPrint('ManualTimeLogModal: Error saving time entry: $e');
      debugPrint('ManualTimeLogModal: Error type: ${e.runtimeType}');
      debugPrint(
          'ManualTimeLogModal: Error stack trace: ${StackTrace.current}');
      debugPrint(
          'ManualTimeLogModal: Entry details - taskName: ${_selectedTemplate?.name ?? name}, templateId: ${_selectedTemplate?.reference.id}, activityType: $_selectedType');
      debugPrint(
          'ManualTimeLogModal: Time details - startTime: $_startTime, endTime: $_endTime');

      // Get root context before closing modal
      final rootContext = Navigator.of(context, rootNavigator: true).context;

      // Close modal first, then show error
      if (mounted) {
        Navigator.of(context).pop();
        // Show error message after a short delay to ensure modal is closed
        Future.delayed(const Duration(milliseconds: 300), () {
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(
                content: Text('Failed to save entry: ${e.toString()}'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: Colors.grey[200]),
          ),

          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Activity Type Selector
                    Row(
                      children: [
                        _buildTypeChip('Task', 'task', theme),
                        const SizedBox(width: 8),
                        _buildTypeChip('Habit', 'habit', theme),
                        const SizedBox(width: 8),
                        _buildTypeChip(
                            'Non-Productive', 'non_productive', theme),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Activity Input with Overlay Dropdown
                    Container(
                      key: _textFieldKey,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.tertiary.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.surfaceBorderColor,
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: _activityController,
                        focusNode: _activityFocusNode,
                        style: theme.bodyMedium,
                        decoration: InputDecoration(
                          hintText: _selectedType == 'habit'
                              ? 'Search existing habit...'
                              : 'Type or search activity...',
                          hintStyle: TextStyle(
                            color: theme.secondaryText,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          icon: const Icon(Icons.search,
                              size: 20, color: Colors.grey),
                          suffixIcon: _activityController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _activityController.clear();
                                    setState(() => _selectedTemplate = null);
                                    _removeOverlay();
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Time Pickers Row
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickStartTime,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time,
                                      size: 18, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat.jm().format(_startTime),
                                    style: theme.bodyMedium
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Icon(Icons.arrow_forward,
                              size: 16, color: Colors.grey),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: _pickEndTime,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time_filled,
                                      size: 18, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat.jm().format(_endTime),
                                    style: theme.bodyMedium
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Completion Controls (conditional based on tracking type)
                    if (_selectedTemplate != null) ...[
                      _buildCompletionControls(theme),
                      const SizedBox(height: 16),
                    ],

                    const SizedBox(height: 8),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveEntry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'Log Time Entry',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16), // Bottom padding
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String label, String value, FlutterFlowTheme theme) {
    final isSelected = _selectedType == value;
    Color color;
    if (value == 'habit') {
      color = Colors.orange;
    } else if (value == 'non_productive') {
      color = Colors.grey;
    } else {
      color = theme.primary; // Task
    }

    return Expanded(
      child: GestureDetector(
        onTap: () => _selectType(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey.shade600,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionControls(FlutterFlowTheme theme) {
    if (_selectedTemplate == null) return const SizedBox.shrink();

    final trackingType = _selectedTemplate!.trackingType;

    // Binary tasks: Show checkbox
    if (trackingType == 'binary') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.tertiary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.surfaceBorderColor),
        ),
        child: Row(
          children: [
            Checkbox(
              value: _markAsComplete,
              onChanged: (value) {
                setState(() {
                  _markAsComplete = value ?? false;
                });
              },
              activeColor: theme.primary,
            ),
            Expanded(
              child: Text(
                'Mark as complete',
                style: theme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    // Quantity tasks: Show stepper
    if (trackingType == 'qty') {
      final target = _selectedTemplate!.target;
      final unit = _selectedTemplate!.unit ?? '';

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.tertiary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.surfaceBorderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quantity Progress',
              style: theme.bodySmall.copyWith(
                color: theme.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    setState(() {
                      if (_quantityValue > 0) _quantityValue--;
                    });
                  },
                  color: theme.primary,
                ),
                Expanded(
                  child: Text(
                    '$_quantityValue${target != null ? ' / $target' : ''} $unit',
                    textAlign: TextAlign.center,
                    style: theme.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    setState(() {
                      _quantityValue++;
                    });
                  },
                  color: theme.primary,
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Time duration tasks: Show info text
    if (trackingType == 'time') {
      final target = _selectedTemplate!.target;
      final targetMinutes =
          target is int ? target : (target is double ? target.toInt() : 0);
      final hours = targetMinutes ~/ 60;
      final minutes = targetMinutes % 60;
      final targetStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Will auto-complete if total time reaches $targetStr',
                style: theme.bodySmall.copyWith(
                  color: Colors.blue.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Non-productive or unknown: No controls
    return const SizedBox.shrink();
  }
}
