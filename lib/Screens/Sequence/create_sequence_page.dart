import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/sequence_service.dart';
import 'package:habit_tracker/Helper/backend/activity_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/sequence_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
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
        setState(() {
          _allActivities = activities;
          _filteredActivities = activities;
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
      } catch (e) {}
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
            content:
                Text('Non-productive item "${activity.name}" deleted successfully'),
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
          content: Text('Please add at least one item to the sequence'),
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
          // Create instances for newly created non-productive items first
          await _createInstancesForNewItems();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Sequence "${_nameController.text.trim()}" updated successfully!${_newlyCreatedItemIds.isNotEmpty ? ' Instances created for new items.' : ''}'),
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
          // Create instances for newly created non-productive items first
          await _createInstancesForNewItems();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Sequence "${_nameController.text.trim()}" created successfully!${_newlyCreatedItemIds.isNotEmpty ? ' Instances created for new items.' : ''}'),
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

  Future<void> _createInstancesForNewItems() async {
    if (_newlyCreatedItemIds.isEmpty) return;
    try {
      for (final itemId in _newlyCreatedItemIds) {
        try {
          final instance = await SequenceService.createInstanceForSequenceItem(
            itemId: itemId,
            userId: currentUserUid,
          );
          if (instance != null) {
          } else {}
        } catch (e) {}
      }
    } catch (e) {}
  }

  String _getItemTypeDisplayName(String categoryType) {
    switch (categoryType) {
      case 'habit':
        return 'Habit';
      case 'task':
        return 'Task';
      case 'sequence_item':
      case 'non_productive':
        return 'Non-Productive'; // sequence_item is legacy, now non_productive
      default:
        return 'Unknown';
    }
  }

  Color _getItemTypeColor(String categoryType) {
    switch (categoryType) {
      case 'habit':
        return Colors.green;
      case 'task':
        return Colors.blue;
      case 'sequence_item':
      case 'non_productive':
        return Colors.grey.shade600; // Muted color for non-productive
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        title: Text(
          widget.existingSequence != null ? 'Edit Sequence' : 'Create Sequence',
          style: FlutterFlowTheme.of(context).headlineMedium,
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSequence,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: FlutterFlowTheme.of(context).titleMedium.override(
                          color: FlutterFlowTheme.of(context).primary,
                        ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  // Sequence Details
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Sequence Name *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a sequence name';
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
                          style: FlutterFlowTheme.of(context).titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Search habits, tasks, or non-productive items...',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.search),
                                ),
                                onChanged: _filterActivities,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _createNewSequenceItem,
                              icon: const Icon(Icons.add),
                              label: const Text('New Item'),
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
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryText,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No items found',
                                  style:
                                      FlutterFlowTheme.of(context).titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Try a different search term or create a new item',
                                  style:
                                      FlutterFlowTheme.of(context).bodyMedium,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filteredActivities.length,
                            itemBuilder: (context, index) {
                              final activity = _filteredActivities[index];
                              final isSelected = _selectedItems.any(
                                (item) =>
                                    item.reference.id == activity.reference.id,
                              );
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: GestureDetector(
                                  onLongPress: activity.categoryType ==
                                              'sequence_item' ||
                                          activity.categoryType ==
                                              'non_productive'
                                      ? () => _showDeleteConfirmation(activity)
                                      : null,
                                  child: ListTile(
                                    leading: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: _getItemTypeColor(
                                            activity.categoryType),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        activity.categoryType == 'habit'
                                            ? Icons.flag
                                            :                                         activity.categoryType == 'task'
                                                ? Icons.assignment
                                                : (activity.categoryType ==
                                                            'non_productive' ||
                                                        activity.categoryType ==
                                                            'sequence_item')
                                                    ? Icons.access_time
                                                    : Icons.playlist_add,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(activity.name),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(activity.categoryName),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getItemTypeColor(
                                                    activity.categoryType)
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            _getItemTypeDisplayName(
                                                activity.categoryType),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: _getItemTypeColor(
                                                  activity.categoryType),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: isSelected
                                        ? Icon(
                                            Icons.check_circle,
                                            color: FlutterFlowTheme.of(context)
                                                .primary,
                                          )
                                        : const Icon(Icons.add_circle_outline),
                                    onTap: () {
                                      if (isSelected) {
                                        _removeItem(activity);
                                      } else {
                                        _addItem(activity);
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  // Selected Items - Collapsible
                  if (_selectedItems.isNotEmpty) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).secondaryBackground,
                        border: Border(
                          top: BorderSide(
                            color: FlutterFlowTheme.of(context).alternate,
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
                                      style: FlutterFlowTheme.of(context)
                                          .titleMedium,
                                    ),
                                  ),
                                  Icon(
                                    _isSelectedItemsExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: FlutterFlowTheme.of(context)
                                        .secondaryText,
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
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Drag to reorder items in the sequence',
                                    style: FlutterFlowTheme.of(context)
                                        .bodySmall
                                        .override(
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryText,
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
                                        final activity = _selectedItems[index];
                                        return Card(
                                          key: ValueKey(activity.reference.id),
                                          margin:
                                              const EdgeInsets.only(bottom: 4),
                                          child: ListTile(
                                            leading: Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: _getItemTypeColor(
                                                    activity.categoryType),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                activity.categoryType == 'habit'
                                                    ? Icons.flag
                                                    : activity.categoryType ==
                                                            'task'
                                                        ? Icons.assignment
                                                        : Icons.playlist_add,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                            title: Text(activity.name),
                                            subtitle:
                                                Text(activity.categoryName),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: _getItemTypeColor(
                                                            activity
                                                                .categoryType)
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Text(
                                                    _getItemTypeDisplayName(
                                                        activity.categoryType),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: _getItemTypeColor(
                                                          activity
                                                              .categoryType),
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  Icons.drag_handle,
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .secondaryText,
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
    );
  }
}
