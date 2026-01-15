import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/category_color_util.dart';
import 'package:habit_tracker/Screens/Essential/create_essential_item_dialog.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/time_utils.dart';
import 'package:habit_tracker/Screens/Routine/Backend_data/routine_service.dart';
import 'package:habit_tracker/Screens/Item_component/item_dotted_line_painter.dart';

class CreateRoutinePage extends StatefulWidget {
  final RoutineRecord? existingRoutine;
  const CreateRoutinePage({
    Key? key,
    this.existingRoutine,
  }) : super(key: key);
  @override
  _CreateRoutinePageState createState() => _CreateRoutinePageState();
}

class _CreateRoutinePageState extends State<CreateRoutinePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  List<ActivityRecord> _allActivities = [];
  List<ActivityRecord> _filteredActivities = [];
  List<ActivityRecord> _selectedItems = [];
  Set<String> _newlyCreatedItemIds = {};
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSelectedItemsExpanded = true;
  bool _wasKeyboardVisible = false;
  // Current routine (fetched from Firestore when editing)
  RoutineRecord? _currentRoutine;
  // Reminder state
  TimeOfDay? _startTime;
  List<ReminderConfig> _reminders = [];
  String? _reminderFrequencyType;
  int _everyXValue = 1;
  String? _everyXPeriodType;
  List<int> _specificDays = [];
  bool _remindersEnabled = false;

  @override
  void initState() {
    super.initState();
    // Fetch latest routine from Firestore if editing
    if (widget.existingRoutine != null) {
      _fetchLatestRoutine();
    } else {
      _loadActivities();
    }
  }

  /// Fetch the latest routine document from Firestore to avoid stale data
  Future<void> _fetchLatestRoutine() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty || widget.existingRoutine == null) return;

      // Fetch the latest routine document (uses cache first, then server)
      final routineRef = RoutineRecord.collectionForUser(userId)
          .doc(widget.existingRoutine!.reference.id);
      final latestRoutine = await RoutineRecord.getDocumentOnce(routineRef);

      if (mounted) {
        setState(() {
          _currentRoutine = latestRoutine;
        });
        // Initialize form from latest routine
        _initializeFromRoutine(latestRoutine);
        // Now load activities (which will load existing items)
        _loadActivities();
      }
    } catch (e) {
      // Fallback to widget.existingRoutine if fetch fails
      if (mounted) {
        setState(() {
          _currentRoutine = widget.existingRoutine;
        });
        _initializeFromRoutine(widget.existingRoutine!);
        _loadActivities();
      }
    }
  }

  /// Initialize form state from a routine record
  void _initializeFromRoutine(RoutineRecord routine) {
    _nameController.text = routine.name;
    // Load existing reminder config
    if (routine.hasDueTime()) {
      _startTime = TimeUtils.stringToTimeOfDay(routine.dueTime);
    }
    if (routine.hasReminders()) {
      _reminders = ReminderConfigList.fromMapList(routine.reminders);
    }
    _reminderFrequencyType = routine.reminderFrequencyType.isEmpty
        ? null
        : routine.reminderFrequencyType;
    _everyXValue = routine.everyXValue;
    _everyXPeriodType =
        routine.everyXPeriodType.isEmpty ? null : routine.everyXPeriodType;
    _specificDays = List.from(routine.specificDays);
    _remindersEnabled = routine.remindersEnabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadActivities() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        // Load all activities including Essential Activities
        final activities = await queryActivitiesRecordOnce(
          userId: userId,
          includeEssentialItems: true,
        );
        // Filter out completed/skipped one-time tasks (keep recurring tasks, habits, and Essential Activities)
        final filteredActivities = activities.where((activity) {
          // Keep all habits (always recurring)
          if (activity.categoryType == 'habit') return true;
          // Keep all Essential Activities
          if (activity.categoryType == 'essential') return true;
          // For tasks: exclude completed/skipped one-time tasks
          if (activity.categoryType == 'task') {
            // Keep recurring tasks (regardless of status)
            if (activity.isRecurring) return true;
            // For one-time tasks:
            // - Exclude if inactive (completed tasks get marked inactive)
            // - Exclude if status is explicitly 'complete' or 'skipped'
            if (!activity.isActive) return false;
            return activity.status != 'complete' &&
                activity.status != 'skipped';
          }
          // Keep everything else by default
          return true;
        }).toList();
        setState(() {
          _allActivities = filteredActivities;
          _filteredActivities = filteredActivities;
          _isLoading = false;
        });
        // If editing, load existing items from current routine
        if (_currentRoutine != null) {
          _loadExistingItems();
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _loadExistingItems() {
    if (_currentRoutine == null) return;
    final existingItems = <ActivityRecord>[];
    final orderedIds = _currentRoutine!.itemOrder.isNotEmpty
        ? _currentRoutine!.itemOrder
        : _currentRoutine!.itemIds;
    for (final itemId in orderedIds) {
      try {
        final activity =
            _allActivities.firstWhere((a) => a.reference.id == itemId);
        existingItems.add(activity);
      } catch (e) {
        // Silently ignore missing activities - they may have been deleted
        print('Activity not found for routine item: $itemId');
      }
    }
    setState(() {
      _selectedItems = existingItems;
    });
  }

  void _filterActivities(String query) {
    setState(() {
      _filteredActivities = _allActivities.where((activity) {
        return activity.name.toLowerCase().contains(query.toLowerCase()) ||
            activity.categoryName.toLowerCase().contains(query.toLowerCase());
      }).toList();
    });
  }

  void _addItem(ActivityRecord activity) {
    if (!_selectedItems
        .any((item) => item.reference.id == activity.reference.id)) {
      setState(() {
        _selectedItems.add(activity);
      });
    }
  }

  void _removeItem(ActivityRecord activity) {
    setState(() {
      _selectedItems
          .removeWhere((item) => item.reference.id == activity.reference.id);
    });
  }

  void _reorderItems(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _selectedItems.removeAt(oldIndex);
      _selectedItems.insert(newIndex, item);
    });
  }

  Future<void> _showDeleteConfirmation(ActivityRecord activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete essential Item'),
        content: Text(
          'Are you sure you want to permanently delete "${activity.name}"?\n\nThis action cannot be undone.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteEssentialItem(activity);
    }
  }

  Future<void> _deleteEssentialItem(ActivityRecord activity) async {
    try {
      // Call business logic to delete the activity
      await ActivityService.deleteActivity(activity.reference);

      // Update local state to remove deleted item from all lists
      setState(() {
        _allActivities
            .removeWhere((item) => item.reference.id == activity.reference.id);
        _filteredActivities
            .removeWhere((item) => item.reference.id == activity.reference.id);
        _selectedItems
            .removeWhere((item) => item.reference.id == activity.reference.id);
        _newlyCreatedItemIds.remove(activity.reference.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('essential item "${activity.name}" deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting essential item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _createNewEssentialItem() async {
    showDialog(
      context: context,
      builder: (context) => CreateEssentialItemDialog(
        onItemCreated: (activity) {
          setState(() {
            _allActivities.add(activity);
            _filteredActivities.add(activity);
            _selectedItems.add(activity);
            _newlyCreatedItemIds.add(activity.reference.id);
          });
        },
      ),
    );
  }

  Future<void> _saveRoutine() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one item to the routine'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      final itemIds = _selectedItems.map((item) => item.reference.id).toList();
      final itemOrder =
          _selectedItems.map((item) => item.reference.id).toList();
      final itemNames = _selectedItems.map((item) => item.name).toList();
      final itemTypes =
          _selectedItems.map((item) => item.categoryType).toList();
      print('🔍 DEBUG: - name: ${_nameController.text.trim()}');
      if (_currentRoutine != null) {
        // Update existing routine using current routine's ID
        await RoutineService.updateRoutine(
          routineId: _currentRoutine!.reference.id,
          name: _nameController.text.trim(),
          itemIds: itemIds,
          itemOrder: itemOrder,
          userId: currentUserUid,
          dueTime: _startTime != null
              ? TimeUtils.timeOfDayToString(_startTime!)
              : null,
          reminders: _reminders.isNotEmpty
              ? ReminderConfigList.toMapList(_reminders)
              : null,
          reminderFrequencyType: _reminderFrequencyType,
          everyXValue:
              _reminderFrequencyType == 'every_x' ? _everyXValue : null,
          everyXPeriodType:
              _reminderFrequencyType == 'every_x' ? _everyXPeriodType : null,
          specificDays: _reminderFrequencyType == 'specific_days' &&
                  _specificDays.isNotEmpty
              ? _specificDays
              : null,
          remindersEnabled: _remindersEnabled,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Routine "${_nameController.text.trim()}" updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(<String, dynamic>{
            'routineId': _currentRoutine!.reference.id,
            'itemIds': itemIds,
            'itemOrder': itemOrder,
            'itemNames': itemNames,
            'itemTypes': itemTypes,
          });
        }
      } else {
        // Create new routine
        final ref = await RoutineService.createRoutine(
          name: _nameController.text.trim(),
          itemIds: itemIds,
          itemOrder: itemOrder,
          userId: currentUserUid,
          dueTime: _startTime != null
              ? TimeUtils.timeOfDayToString(_startTime!)
              : null,
          reminders: _reminders.isNotEmpty
              ? ReminderConfigList.toMapList(_reminders)
              : null,
          reminderFrequencyType: _reminderFrequencyType,
          everyXValue:
              _reminderFrequencyType == 'every_x' ? _everyXValue : null,
          everyXPeriodType:
              _reminderFrequencyType == 'every_x' ? _everyXPeriodType : null,
          specificDays: _reminderFrequencyType == 'specific_days' &&
                  _specificDays.isNotEmpty
              ? _specificDays
              : null,
          remindersEnabled: _remindersEnabled,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Routine "${_nameController.text.trim()}" created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(<String, dynamic>{
            'routineId': ref.id,
            'itemIds': itemIds,
            'itemOrder': itemOrder,
            'itemNames': itemNames,
            'itemTypes': itemTypes,
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving routine: $e'),
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

  Color _getItemTypeColor(String categoryType) {
    switch (categoryType) {
      case 'habit':
        return Colors.green;
      case 'task':
        return const Color(0xFF2F4F4F); // Dark Slate Gray (charcoal) for tasks
      case 'essential':
        return Colors.grey.shade600; // Muted color for essential
      default:
        return Colors.grey;
    }
  }

  Color _getStripeColor(ActivityRecord activity) {
    // For habits, use category color if available, otherwise use type color
    if (activity.categoryType == 'habit') {
      try {
        final hex = CategoryColorUtil.hexForName(activity.categoryName);
        return Color(int.parse(hex.replaceFirst('#', '0xFF')));
      } catch (_) {
        return _getItemTypeColor(activity.categoryType);
      }
    }
    // For tasks and essential, use type color
    return _getItemTypeColor(activity.categoryType);
  }

  Widget _buildSimplifiedItemCard(ActivityRecord activity, bool isSelected) {
    final theme = FlutterFlowTheme.of(context);
    final stripeColor = _getStripeColor(activity);
    final isessential = activity.categoryType == 'essential';

    return GestureDetector(
      onLongPress: isessential ? () => _showDeleteConfirmation(activity) : null,
      onTap: () {
        if (isSelected) {
          _removeItem(activity);
        } else {
          _addItem(activity);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          gradient: theme.neumorphicGradientSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.cardBorderColor,
            width: 1,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left stripe
              isessential
                  ? SizedBox(
                      width: 3,
                      child: CustomPaint(
                        size: const Size(3, double.infinity),
                        painter: DottedLinePainter(color: stripeColor),
                      ),
                    )
                  : Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: stripeColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
              const SizedBox(width: 5),
              // Icon
              SizedBox(
                width: 36,
                child: Center(
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: stripeColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      activity.categoryType == 'habit'
                          ? Icons.flag
                          : activity.categoryType == 'task'
                              ? Icons.assignment
                              : Icons.monitor_heart,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      activity.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyMedium.override(
                        fontFamily: 'Readex Pro',
                        fontWeight: FontWeight.w600,
                        color: theme.primaryText,
                      ),
                    ),
                    if (activity.categoryName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        activity.categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall.override(
                          fontFamily: 'Readex Pro',
                          color: theme.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Plus/Check button
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (isSelected) {
                        _removeItem(activity);
                      } else {
                        _addItem(activity);
                      }
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color:
                              isSelected ? theme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: isSelected
                              ? null
                              : Border.all(
                                  color: stripeColor,
                                  width: 2,
                                ),
                        ),
                        child: Icon(
                          isSelected ? Icons.check : Icons.add,
                          size: 18,
                          color: isSelected ? Colors.white : stripeColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final bottomSafePadding = MediaQuery.of(context).viewPadding.bottom;
    // Auto-expand/collapse based on keyboard visibility
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && isKeyboardVisible != _wasKeyboardVisible) {
        setState(() {
          _isSelectedItemsExpanded = !isKeyboardVisible;
          _wasKeyboardVisible = isKeyboardVisible;
        });
      }
    });
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        elevation: 0,
        title: Text(
          widget.existingRoutine != null ? 'Edit Routine' : 'Create Routine',
          style: theme.titleMedium.override(
            fontFamily: 'Readex Pro',
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              decoration: BoxDecoration(
                gradient: theme.primaryButtonGradient,
                borderRadius: BorderRadius.circular(theme.buttonRadius),
              ),
              child: TextButton(
                onPressed: _isSaving ? null : _saveRoutine,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Save',
                        style: theme.bodyMedium.override(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: BoxDecoration(
                gradient: theme.neumorphicGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border.all(
                  color: theme.surfaceBorderColor,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, -2),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomSafePadding),
                  child: Column(
                    children: [
                      // Routine Details
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Routine Name *',
                              style: theme.bodySmall.override(
                                color: theme.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: theme.tertiary.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: theme.surfaceBorderColor,
                                  width: 1,
                                ),
                              ),
                              child: TextFormField(
                                controller: _nameController,
                                style: theme.bodyMedium,
                                decoration: InputDecoration(
                                  hintText: 'Enter routine name',
                                  hintStyle: TextStyle(
                                    color: theme.secondaryText,
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter a routine name';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Search and Add Items
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add Items',
                              style: theme.titleMedium.override(
                                fontFamily: 'Readex Pro',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.tertiary.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: theme.surfaceBorderColor,
                                        width: 1,
                                      ),
                                    ),
                                    child: TextField(
                                      controller: _searchController,
                                      style: theme.bodyMedium,
                                      decoration: InputDecoration(
                                        hintText:
                                            'Search habits, tasks, or non-produc...',
                                        hintStyle: TextStyle(
                                          color: theme.secondaryText,
                                          fontSize: 14,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                vertical: 8),
                                        prefixIcon: Icon(
                                          Icons.search,
                                          color: theme.secondaryText,
                                          size: 20,
                                        ),
                                        prefixIconConstraints:
                                            const BoxConstraints(
                                          minWidth: 40,
                                          minHeight: 20,
                                        ),
                                      ),
                                      onChanged: _filterActivities,
                                    ),
                                  ),
                                ),
                                if (widget.existingRoutine == null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: theme.primaryButtonGradient,
                                      borderRadius: BorderRadius.circular(
                                          theme.buttonRadius),
                                    ),
                                    child: ElevatedButton.icon(
                                      onPressed: _createNewEssentialItem,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                      ),
                                      icon: const Icon(Icons.add,
                                          color: Colors.white),
                                      label: Text(
                                        'New Item',
                                        style: theme.bodyMedium.override(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Available Items List
                      Expanded(
                        child: _filteredActivities.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 64,
                                      color: theme.secondaryText,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No items found',
                                      style: theme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Try a different search term or create a new item',
                                      style: theme.bodyMedium,
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _filteredActivities.length,
                                itemBuilder: (context, index) {
                                  final activity = _filteredActivities[index];
                                  final isSelected = _selectedItems.any(
                                    (item) =>
                                        item.reference.id ==
                                        activity.reference.id,
                                  );
                                  return _buildSimplifiedItemCard(
                                      activity, isSelected);
                                },
                              ),
                      ),
                      // Selected Items - Collapsible
                      if (_selectedItems.isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          decoration: BoxDecoration(
                            gradient: theme.neumorphicGradientSubtle,
                            border: Border(
                              top: BorderSide(
                                color: theme.surfaceBorderColor,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Column(
                            children: [
                              // Collapsible Header
                              GestureDetector(
                                onTap: () {
                                  // Dismiss keyboard first, then toggle
                                  FocusScope.of(context).unfocus();
                                  setState(() {
                                    _isSelectedItemsExpanded =
                                        !_isSelectedItemsExpanded;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Selected Items (${_selectedItems.length})',
                                          style: theme.titleMedium.override(
                                            fontFamily: 'Readex Pro',
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        _isSelectedItemsExpanded
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        color: theme.secondaryText,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Expandable Content
                              AnimatedCrossFade(
                                duration: const Duration(milliseconds: 300),
                                crossFadeState: _isSelectedItemsExpanded
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                firstChild: const SizedBox.shrink(),
                                secondChild: Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Drag to reorder items in the routine',
                                        style: theme.bodySmall.override(
                                          color: theme.secondaryText,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height:
                                            260, // Max height for selected items
                                        child: ReorderableListView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          itemCount: _selectedItems.length,
                                          onReorder: _reorderItems,
                                          itemBuilder: (context, index) {
                                            final activity =
                                                _selectedItems[index];
                                            final stripeColor =
                                                _getStripeColor(activity);
                                            final isessential =
                                                activity.categoryType ==
                                                    'essential';
                                            return Container(
                                              key: ValueKey(
                                                  activity.reference.id),
                                              margin: const EdgeInsets.only(
                                                  bottom: 4),
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      6, 6, 6, 6),
                                              decoration: BoxDecoration(
                                                gradient: theme
                                                    .neumorphicGradientSubtle,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: theme.cardBorderColor,
                                                  width: 1,
                                                ),
                                              ),
                                              child: IntrinsicHeight(
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    // Left stripe
                                                    isessential
                                                        ? SizedBox(
                                                            width: 3,
                                                            child: CustomPaint(
                                                              size: const Size(
                                                                  3,
                                                                  double
                                                                      .infinity),
                                                              painter:
                                                                  DottedLinePainter(
                                                                      color:
                                                                          stripeColor),
                                                            ),
                                                          )
                                                        : Container(
                                                            width: 3,
                                                            decoration:
                                                                BoxDecoration(
                                                              color:
                                                                  stripeColor,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          2),
                                                            ),
                                                          ),
                                                    const SizedBox(width: 5),
                                                    // Icon
                                                    SizedBox(
                                                      width: 32,
                                                      child: Center(
                                                        child: Container(
                                                          width: 24,
                                                          height: 24,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: stripeColor,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                          child: Icon(
                                                            activity.categoryType ==
                                                                    'habit'
                                                                ? Icons.flag
                                                                : activity.categoryType ==
                                                                        'task'
                                                                    ? Icons
                                                                        .assignment
                                                                    : Icons
                                                                        .playlist_add,
                                                            color: Colors.white,
                                                            size: 16,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    // Content
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Text(
                                                            activity.name,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: theme
                                                                .bodyMedium
                                                                .override(
                                                              fontFamily:
                                                                  'Readex Pro',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: theme
                                                                  .primaryText,
                                                            ),
                                                          ),
                                                          if (activity
                                                              .categoryName
                                                              .isNotEmpty) ...[
                                                            const SizedBox(
                                                                height: 2),
                                                            Text(
                                                              activity
                                                                  .categoryName,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: theme
                                                                  .bodySmall
                                                                  .override(
                                                                fontFamily:
                                                                    'Readex Pro',
                                                                color: theme
                                                                    .secondaryText,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                    // Drag handle
                                                    Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Icon(
                                                          Icons.drag_handle,
                                                          color: theme
                                                              .secondaryText,
                                                          size: 20,
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
