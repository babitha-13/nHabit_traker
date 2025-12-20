import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/sequence_service.dart';
import 'package:habit_tracker/Helper/backend/activity_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/sequence_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/backend/category_color_util.dart';
import 'package:habit_tracker/Screens/Sequence/create_sequence_item_dialog.dart';

class CreateSequencePage extends StatefulWidget {
  final SequenceRecord? existingSequence;
  const CreateSequencePage({
    Key? key,
    this.existingSequence,
  }) : super(key: key);
  @override
  _CreateSequencePageState createState() => _CreateSequencePageState();
}

class _CreateSequencePageState extends State<CreateSequencePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  List<ActivityRecord> _allActivities = [];
  List<ActivityRecord> _filteredActivities = [];
  List<ActivityRecord> _selectedItems = [];
  Set<String> _newlyCreatedItemIds = {};
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSelectedItemsExpanded = true;
  bool _wasKeyboardVisible = false;
  @override
  void initState() {
    super.initState();
    if (widget.existingSequence != null) {
      _nameController.text = widget.existingSequence!.name;
      _descriptionController.text = widget.existingSequence!.description;
    }
    _loadActivities();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
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
        // Load all activities including non-productive items
        final activities = await queryActivitiesRecordOnce(
          userId: userId,
          includeSequenceItems: true,
        );
        // Filter out completed/skipped one-time tasks (keep recurring tasks, habits, and non-productive items)
        final filteredActivities = activities.where((activity) {
          // Keep all habits (always recurring)
          if (activity.categoryType == 'habit') return true;
          // Keep all non-productive items
          if (activity.categoryType == 'non_productive') return true;
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
        // If editing, load existing items
        if (widget.existingSequence != null) {
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
    if (widget.existingSequence == null) return;
    final existingItems = <ActivityRecord>[];
    for (final itemId in widget.existingSequence!.itemIds) {
      try {
        final activity =
            _allActivities.firstWhere((a) => a.reference.id == itemId);
        existingItems.add(activity);
      } catch (e) {
        // Silently ignore missing activities - they may have been deleted
        print('Activity not found for sequence item: $itemId');
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
        title: const Text('Delete Non-Productive Item'),
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
      await _deleteSequenceItem(activity);
    }
  }

  Future<void> _deleteSequenceItem(ActivityRecord activity) async {
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
            content: Text(
                'Non-productive item "${activity.name}" deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting non-productive item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _createNewSequenceItem() async {
    showDialog(
      context: context,
      builder: (context) => CreateSequenceItemDialog(
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

  Future<void> _saveSequence() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: const Text('Please add at least one item to the sequence'),
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
      print('🔍 DEBUG: - name: ${_nameController.text.trim()}');
      if (widget.existingSequence != null) {
        // Update existing sequence
        await updateSequence(
          sequenceId: widget.existingSequence!.reference.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          itemIds: itemIds,
          itemOrder: itemOrder,
          userId: currentUserUid,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Sequence "${_nameController.text.trim()}" updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        // Create new sequence
        await createSequence(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          itemIds: itemIds,
          itemOrder: itemOrder,
          userId: currentUserUid,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Sequence "${_nameController.text.trim()}" created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving sequence: $e'),
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
      case 'non_productive':
        return Colors.grey.shade600; // Muted color for non-productive
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
    // For tasks and non-productive, use type color
    return _getItemTypeColor(activity.categoryType);
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

  Widget _buildSimplifiedItemCard(ActivityRecord activity, bool isSelected) {
    final theme = FlutterFlowTheme.of(context);
    final stripeColor = _getStripeColor(activity);
    final isNonProductive = activity.categoryType == 'non_productive';

    return GestureDetector(
      onLongPress:
          isNonProductive ? () => _showDeleteConfirmation(activity) : null,
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
              isNonProductive
                  ? SizedBox(
                      width: 3,
                      child: CustomPaint(
                        size: const Size(3, double.infinity),
                        painter: _DottedLinePainter(color: stripeColor),
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
                              : Icons.access_time,
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
                    onTap: () {
                      if (isSelected) {
                        _removeItem(activity);
                      } else {
                        _addItem(activity);
                      }
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected ? theme.primary : Colors.transparent,
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
          widget.existingSequence != null ? 'Edit Sequence' : 'Create Sequence',
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
                onPressed: _isSaving ? null : _saveSequence,
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
                child: Column(
                  children: [
                    // Sequence Details
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sequence Name *',
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
                                hintText: 'Enter sequence name',
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
                                  return 'Please enter a sequence name';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Description (Optional)',
                            style: theme.bodySmall.override(
                              color: theme.secondaryText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildTextField(
                            theme,
                            _descriptionController,
                            'Enter description',
                            maxLines: 2,
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
                              const SizedBox(width: 8),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: theme.primaryButtonGradient,
                                  borderRadius:
                                      BorderRadius.circular(theme.buttonRadius),
                                ),
                                child: ElevatedButton.icon(
                                  onPressed: _createNewSequenceItem,
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
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Drag to reorder items in the sequence',
                                      style: theme.bodySmall.override(
                                        color: theme.secondaryText,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height:
                                          200, // Max height for selected items
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
                                          final isNonProductive =
                                              activity.categoryType ==
                                                  'non_productive';
                                          return Container(
                                            key:
                                                ValueKey(activity.reference.id),
                                            margin: const EdgeInsets.only(
                                                bottom: 4),
                                            padding: const EdgeInsets.fromLTRB(
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
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  // Left stripe
                                                  isNonProductive
                                                      ? SizedBox(
                                                          width: 3,
                                                          child: CustomPaint(
                                                            size: const Size(
                                                                3,
                                                                double
                                                                    .infinity),
                                                            painter:
                                                                _DottedLinePainter(
                                                                    color:
                                                                        stripeColor),
                                                          ),
                                                        )
                                                      : Container(
                                                          width: 3,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: stripeColor,
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
                                                                  .circular(4),
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
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: theme
                                                              .bodyMedium
                                                              .override(
                                                            fontFamily:
                                                                'Readex Pro',
                                                            fontWeight:
                                                                FontWeight.w600,
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
                                                        color:
                                                            theme.secondaryText,
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
    );
  }
}

/// Custom painter for creating a dotted vertical line
class _DottedLinePainter extends CustomPainter {
  final Color color;

  _DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    const double dashHeight = 4.0;
    const double dashSpace = 3.0;
    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(1.5, startY),
        Offset(1.5, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
