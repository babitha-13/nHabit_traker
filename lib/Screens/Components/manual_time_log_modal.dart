import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/time_logging_preferences_service.dart';
import 'package:habit_tracker/Screens/Calendar/calendar_page.dart';

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
      // Default to user's configured duration only when no end time provided (manual calendar entry)
      _endTime = _startTime.add(Duration(minutes: _defaultDurationMinutes));
    }

    // Ensure end time is after start time
    // Only apply default if end time is invalid (shouldn't happen with timer)
    if (_endTime.isBefore(_startTime) ||
        _endTime.isAtSameMomentAs(_startTime)) {
      // This fallback should only happen for manual calendar entries
      _endTime = _startTime.add(Duration(minutes: _defaultDurationMinutes));
    }
    _loadDefaultDuration();
    _loadActivities();
    _loadCategories();

    // If editing, prefill the form
    if (widget.editMetadata != null) {
      _selectedType = widget.editMetadata!.activityType;
      _activityController.text = widget.editMetadata!.activityName;
      // Find and select the template if it exists
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadActivities(); // Ensure activities are loaded
        await _loadCategories(); // Ensure categories are loaded
        if (mounted && widget.editMetadata!.templateId != null) {
          final template = _allActivities.firstWhereOrNull(
            (a) => a.reference.id == widget.editMetadata!.templateId,
          );
          if (template != null) {
            setState(() {
              _selectedTemplate = template;
              // Set category from template
              _selectedCategory = _allCategories.firstWhereOrNull(
                (c) =>
                    c.reference.id == template.categoryId ||
                    c.name == template.categoryName,
              );
            });
          }
        }
      });
    }

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

  Future<void> _loadDefaultDuration() async {
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final enableDefaultEstimates =
            await TimeLoggingPreferencesService.getEnableDefaultEstimates(
                userId);
        int durationMinutes = 10; // Default fallback
        if (enableDefaultEstimates) {
          durationMinutes =
              await TimeLoggingPreferencesService.getDefaultDurationMinutes(
                  userId);
        }
        if (mounted) {
          setState(() {
            _defaultDurationMinutes = durationMinutes;
            // Update end time if it was set to the old default
            if (_endTime.isBefore(_startTime) ||
                _endTime.isAtSameMomentAs(_startTime)) {
              _endTime =
                  _startTime.add(Duration(minutes: _defaultDurationMinutes));
            }
          });
        }
      }
    } catch (e) {
      // On error, keep default of 10 minutes
      print('Error loading default duration: $e');
    }
  }

  Future<void> _loadCategories() async {
    final uid = currentUserUid;
    final categories = await queryCategoriesRecordOnce(
      userId: uid,
      callerTag: 'ManualTimeLogModal',
    );
    if (mounted) {
      setState(() {
        _allCategories = categories;
        _updateDefaultCategory();
      });
    }
  }

  void _updateDefaultCategory() {
    if (_selectedTemplate != null) {
      _selectedCategory = _allCategories.firstWhereOrNull((c) =>
          c.reference.id == _selectedTemplate?.categoryId ||
          c.name == _selectedTemplate?.categoryName);
      return;
    }

    if (_selectedType == 'task') {
      _selectedCategory = _allCategories.firstWhereOrNull(
          (c) => c.name == 'Inbox' && c.categoryType == 'task');
    } else if (_selectedType == 'essential') {
      _selectedCategory = _allCategories.firstWhereOrNull((c) =>
          (c.name == 'Others' || c.name == 'Other') &&
          c.categoryType == 'essential');

      // Fallback if "Others" not found for essential
      _selectedCategory ??= _allCategories.firstWhereOrNull((c) =>
          c.name == 'essential' ||
          c.name == 'Essential' ||
          c.categoryType == 'essential');
    }
  }

  Future<void> _loadActivities() async {
    final uid = currentUserUid;
    // Include sequence items to ensure Essential Activities are fetched
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
        } else if (_selectedType == 'essential') {
          typeMatch = activity.categoryType == 'essential';
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

                        // Auto-select category from template
                        _selectedCategory = _allCategories.firstWhereOrNull(
                          (c) =>
                              c.reference.id == item.categoryId ||
                              c.name == item.categoryName,
                        );

                        // Update duration from template estimate if not from timer
                        if (widget.initialEndTime == null &&
                            item.timeEstimateMinutes != null &&
                            item.timeEstimateMinutes! > 0) {
                          _endTime = _startTime.add(
                              Duration(minutes: item.timeEstimateMinutes!));
                        }

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
      _updateDefaultCategory();
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
    } else if (_selectedType == 'essential') {
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

  bool _shouldMarkCompleteOnSave() {
    bool shouldComplete = widget.markCompleteOnSave;
    if (_selectedTemplate != null &&
        _selectedTemplate?.trackingType == 'binary' &&
        _markAsComplete) {
      shouldComplete = true;
    }
    return shouldComplete;
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
          _endTime = _startTime.add(Duration(minutes: _defaultDurationMinutes));
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

      // Check if we're editing an existing entry
      if (widget.editMetadata != null) {
        // Update existing session time
        await TaskInstanceService.updateTimeLogSession(
          instanceId: widget.editMetadata!.instanceId,
          sessionIndex: widget.editMetadata!.sessionIndex,
          startTime: _startTime,
          endTime: _endTime,
        );
        
        // Check if name or type has changed and update instance metadata
        // Use template name if template is selected, otherwise use typed name
        final finalName = _selectedTemplate?.name ?? name;
        final hasNameChanged = finalName != widget.editMetadata!.activityName;
        final hasTypeChanged = _selectedType != widget.editMetadata!.activityType;
        
        if (hasNameChanged || hasTypeChanged || templateId != null || _selectedCategory != null) {
          // Update instance metadata
          final instanceRef = ActivityInstanceRecord.collectionForUser(currentUserUid)
              .doc(widget.editMetadata!.instanceId);
          
          final updateData = <String, dynamic>{
            'lastUpdated': DateTime.now(),
          };
          
          // Update name if changed (use template name if available, otherwise typed name)
          if (hasNameChanged) {
            updateData['templateName'] = finalName;
          }
          
          // Update type if changed
          if (hasTypeChanged) {
            updateData['templateCategoryType'] = _selectedType;
          }
          
          // Update template ID if a template is selected
          if (templateId != null) {
            updateData['templateId'] = templateId;
          }
          
          // Update category if changed
          if (_selectedCategory != null) {
            updateData['templateCategoryId'] = _selectedCategory!.reference.id;
            updateData['templateCategoryName'] = _selectedCategory!.name;
            if (_selectedCategory!.color.isNotEmpty) {
              updateData['templateCategoryColor'] = _selectedCategory!.color;
            }
          }
          
          // Also update the template if it exists
          if (templateId != null) {
            final templateRef = ActivityRecord.collectionForUser(currentUserUid)
                .doc(templateId);
            final templateUpdateData = <String, dynamic>{
              'lastUpdated': DateTime.now(),
            };
            
            if (hasNameChanged) {
              templateUpdateData['name'] = finalName;
            }
            
            if (_selectedCategory != null) {
              templateUpdateData['categoryId'] = _selectedCategory!.reference.id;
              templateUpdateData['categoryName'] = _selectedCategory!.name;
            }
            
            try {
              await templateRef.update(templateUpdateData);
            } catch (e) {
              // Template might not exist, continue with instance update
              print('Warning: Could not update template: $e');
            }
          }
          
          // Update the instance
          await instanceRef.update(updateData);
        }
      } else {
        // Create new entry
        final shouldMarkComplete = _shouldMarkCompleteOnSave();

        await TaskInstanceService.logManualTimeEntry(
          taskName: _selectedTemplate?.name ?? name,
          startTime: _startTime,
          endTime: _endTime,
          activityType: _selectedType, // 'task', 'habit', 'essential'
          templateId: templateId,
          markComplete: shouldMarkComplete,
          categoryId: _selectedCategory?.reference.id,
          categoryName: _selectedCategory?.name,
        );
      }

      // Close modal first, then call onSave
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSave();
      }
    } catch (e) {
      // Error saving time entry

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

  Future<void> _deleteEntry() async {
    if (widget.editMetadata == null) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Fetch the instance to check its status and tracking type
      final instance = await ActivityInstanceRecord.getDocumentOnce(
        ActivityInstanceRecord.collectionForUser(currentUserUid)
            .doc(widget.editMetadata!.instanceId),
      );

      // Check if instance is completed and not a timer type
      // For non-timer types (binary, quantitative), show dialog with options
      bool shouldUncomplete = false;
      if (instance.status == 'completed' &&
          instance.templateTrackingType != 'time' &&
          instance.templateCategoryType != 'essential') {
        // Show dialog asking user what to do
        final userChoice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Time Entry'),
            content: const Text(
                'This task/habit is marked as completed. What would you like to do?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop('uncomplete'),
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
                child: const Text('Uncomplete'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop('keep'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Keep Completed'),
              ),
            ],
          ),
        );

        if (userChoice == null || userChoice == 'cancel') {
          if (mounted) {
            setState(() => _isLoading = false);
          }
          return;
        }

        shouldUncomplete = userChoice == 'uncomplete';
      } else {
        // For timer types or non-completed items, show simple confirmation
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Time Entry'),
            content: const Text(
                'Are you sure you want to delete this time entry? This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );

        if (confirmed != true) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
          return;
        }
      }

      // Uncomplete if user chose to uncomplete
      if (shouldUncomplete) {
        await ActivityInstanceService.uncompleteInstance(
          instanceId: widget.editMetadata!.instanceId,
        );
      }

      // Delete the time log session
      // For timer types, this will auto-uncomplete if time falls below target
      await TaskInstanceService.deleteTimeLogSession(
        instanceId: widget.editMetadata!.instanceId,
        sessionIndex: widget.editMetadata!.sessionIndex,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSave();
      }
    } catch (e) {
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      if (mounted) {
        Navigator.of(context).pop();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (rootContext.mounted) {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(
                content: Text('Failed to delete entry: ${e.toString()}'),
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

  /// Handle back button - show warning if user has unsaved changes
  Future<bool> _onWillPop() async {
    // Check if user has made any changes
    final hasChanges = _activityController.text.isNotEmpty ||
        _selectedTemplate != null ||
        _markAsComplete ||
        _quantityValue > 0;

    if (!hasChanges) {
      // No changes, allow back navigation
      return true;
    }

    // Show warning dialog
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text(
          'You have unsaved changes. Are you sure you want to discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return shouldDiscard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isEditMode = widget.editMetadata != null;
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final hasKeyboard = keyboardInset > 0;
    
    // When keyboard is shown, we want the container to be pushed up by keyboardInset.
    // When keyboard is not shown, we want it to respect the bottom safe area.
    final containerBottomPadding = hasKeyboard ? keyboardInset : bottomSafeArea;
    
    // This padding is inside the scrollable area or at the bottom of the content.
    final contentBottomPadding = hasKeyboard ? 8.0 : 12.0;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Container(
          padding: EdgeInsets.only(
            bottom: containerBottomPadding,
          ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: Colors.grey[200], height: 1),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: contentBottomPadding),
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
                            _buildTypeChip('essential', 'essential', theme),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Activity Input with Overlay Dropdown
                        Container(
                          key: _textFieldKey,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          constraints: const BoxConstraints(minHeight: 42),
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
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              hintText: _selectedType == 'habit'
                                  ? 'Search existing habit...'
                                  : 'Create New or Search...',
                              hintStyle: TextStyle(
                                color: theme.secondaryText,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              icon: const Icon(Icons.search,
                                  size: 20, color: Colors.grey),
                              suffixIcon: _activityController.text.isNotEmpty
                                  ? IconButton(
                                      padding: const EdgeInsets.all(8),
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () {
                                        _activityController.clear();
                                        setState(() {
                                          _selectedTemplate = null;
                                          _updateDefaultCategory();
                                        });
                                        _removeOverlay();
                                      },
                                    )
                                  : null,
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Category Dropdown
                        _buildCategoryDropdown(theme),

                        const SizedBox(height: 10),

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
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.access_time,
                                          size: 18, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Text(
                                        DateFormat.jm().format(_startTime),
                                        style: theme.bodyMedium.copyWith(
                                            fontWeight: FontWeight.w600),
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
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.access_time_filled,
                                          size: 18, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Text(
                                        DateFormat.jm().format(_endTime),
                                        style: theme.bodyMedium.copyWith(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // Completion Controls (conditional based on tracking type)
                        if (_selectedTemplate != null) ...[
                          _buildCompletionControls(theme),
                          const SizedBox(height: 12),
                        ],

                        const SizedBox(height: 6),

                        // Submit Button (and delete when editing)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _saveEntry,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.primary,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
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
                                            color: Colors.white,
                                            strokeWidth: 2),
                                      )
                                    : Text(
                                        isEditMode
                                            ? 'Update Entry'
                                            : 'Log Time Entry',
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                            if (isEditMode) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.delete),
                                color: Colors.red,
                                tooltip: 'Delete entry',
                                onPressed: _isLoading ? null : _deleteEntry,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChip(String label, String value, FlutterFlowTheme theme) {
    final isSelected = _selectedType == value;
    Color color;
    if (value == 'habit') {
      color = Colors.orange;
    } else if (value == 'essential') {
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

  Widget _buildCategoryDropdown(FlutterFlowTheme theme) {
    // If habit is selected, we usually don't allow changing category for existing ones
    final isLocked = _selectedTemplate != null;

    final filteredCategories = isLocked
        ? <CategoryRecord>[]
        : _allCategories
            .where((category) => category.categoryType == _selectedType)
            .toList();
    final dropdownCategories =
        filteredCategories.isNotEmpty ? filteredCategories : _allCategories;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isLocked ? Colors.grey[100] : theme.tertiary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<CategoryRecord>(
          value: _selectedCategory,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            icon: Icon(Icons.category, size: 20, color: Colors.grey),
          ),
          hint: Text('Select Category', style: theme.bodySmall),
          isExpanded: true,
          style: theme.bodyMedium,
          disabledHint: _selectedCategory != null
              ? Text(_selectedCategory!.name, style: theme.bodyMedium)
              : null,
          items: isLocked
              ? null
              : dropdownCategories.map((category) {
                  Color categoryColor;
                  try {
                    categoryColor = Color(
                        int.parse(category.color.replaceFirst('#', '0xFF')));
                  } catch (e) {
                    categoryColor = theme.primary;
                  }
                  return DropdownMenuItem<CategoryRecord>(
                    value: category,
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: categoryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(category.name),
                      ],
                    ),
                  );
                }).toList(),
          onChanged: isLocked
              ? null
              : (value) {
                  setState(() {
                    _selectedCategory = value;
                  });
                },
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
      final unit = _selectedTemplate!.unit;

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

    // Time duration tasks: Show info text only if target is set (> 0)
    if (trackingType == 'time') {
      final target = _selectedTemplate!.target;
      final targetMinutes =
          target is int ? target : (target is double ? target.toInt() : 0);

      // Only show completion message if target is set (greater than 0)
      if (targetMinutes > 0) {
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
      // If no target, don't show any completion message
      return const SizedBox.shrink();
    }

    // essential or unknown: No controls
    return const SizedBox.shrink();
  }
}
