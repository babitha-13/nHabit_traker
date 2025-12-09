import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/sequence_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/sequence_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Sequence/create_sequence_page.dart';
import 'package:collection/collection.dart';

class SequenceDetailPage extends StatefulWidget {
  final SequenceRecord sequence;
  const SequenceDetailPage({
    Key? key,
    required this.sequence,
  }) : super(key: key);
  @override
  _SequenceDetailPageState createState() => _SequenceDetailPageState();
}

class _SequenceDetailPageState extends State<SequenceDetailPage> {
  SequenceWithInstances? _sequenceWithInstances;
  List<CategoryRecord> _categories = [];
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadSequenceWithInstances();
  }

  Future<void> _loadSequenceWithInstances() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final sequenceWithInstances =
          await SequenceService.getSequenceWithInstances(
        sequenceId: widget.sequence.reference.id,
        userId: currentUserUid,
      );

      // Load categories for color lookup
      final habitCategories =
          await queryHabitCategoriesOnce(userId: currentUserUid);
      final taskCategories =
          await queryTaskCategoriesOnce(userId: currentUserUid);
      final allCategories = [...habitCategories, ...taskCategories];

      // Automatically create instances for items without them (habits and tasks only)
      SequenceWithInstances? updatedSequenceWithInstances =
          sequenceWithInstances;
      if (sequenceWithInstances != null) {
        final sequence = sequenceWithInstances.sequence;
        final instances = Map<String, ActivityInstanceRecord>.from(
            sequenceWithInstances.instances);

        // Check each item in the sequence
        for (int i = 0; i < sequence.itemIds.length; i++) {
          final itemId = sequence.itemIds[i];
          final itemType =
              sequence.itemTypes.isNotEmpty && i < sequence.itemTypes.length
                  ? sequence.itemTypes[i]
                  : 'habit';

          // Skip if instance already exists
          if (instances.containsKey(itemId)) {
            continue;
          }

          // Auto-create instances for habits, tasks, and non-productive items
          if (itemType == 'habit' || itemType == 'task') {
            try {
              final newInstance =
                  await SequenceService.createInstanceForSequenceItem(
                itemId: itemId,
                userId: currentUserUid,
              );
              if (newInstance != null) {
                instances[itemId] = newInstance;
              }
            } catch (e) {
              // Silently fail for individual instance creation - item will show as missing
              // This prevents one failed instance from breaking the entire sequence load
            }
          } else if (itemType == 'non_productive' ||
              itemType == 'sequence_item') {
            // Create pending instance for non-productive items so they can use ItemComponent
            try {
              final newInstance =
                  await _createPendingNonProductiveInstance(itemId);
              if (newInstance != null) {
                instances[itemId] = newInstance;
              }
            } catch (e) {
              // Silently fail for individual instance creation
            }
          }
        }

        // Create new SequenceWithInstances with updated instances map
        updatedSequenceWithInstances = SequenceWithInstances(
          sequence: sequence,
          instances: instances,
        );
      }

      setState(() {
        _sequenceWithInstances = updatedSequenceWithInstances;
        _categories = allCategories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshSequence() async {
    await _loadSequenceWithInstances();
  }

  void _editSequence() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => CreateSequencePage(
          existingSequence: widget.sequence,
        ),
      ),
    )
        .then((_) {
      // Refresh the sequence data after editing
      _refreshSequence();
    });
  }

  /// Create a pending instance for a non-productive item (for display with ItemComponent)
  Future<ActivityInstanceRecord?> _createPendingNonProductiveInstance(
      String itemId) async {
    try {
      final templateDoc = await ActivityRecord.collectionForUser(currentUserUid)
          .doc(itemId)
          .get();
      if (!templateDoc.exists) {
        return null;
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);

      // Fetch category color
      String? categoryColor;
      try {
        if (template.categoryId.isNotEmpty) {
          final categoryDoc =
              await CategoryRecord.collectionForUser(currentUserUid)
                  .doc(template.categoryId)
                  .get();
          if (categoryDoc.exists) {
            final category = CategoryRecord.fromSnapshot(categoryDoc);
            categoryColor = category.color;
          }
        }
      } catch (e) {
        // Continue without color if fetch fails
      }

      // Create pending instance (no time logs yet)
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final instanceData = createActivityInstanceRecordData(
        templateId: itemId,
        templateName: template.name,
        templateCategoryType: 'non_productive',
        templateCategoryColor: categoryColor,
        templateTrackingType: template.trackingType,
        templateTarget: template.target,
        templateUnit: template.unit,
        templatePriority: template.priority,
        templateDescription: template.description,
        dueDate: todayStart,
        status: 'pending',
        currentValue: 0,
        accumulatedTime: 0,
        totalTimeLogged: 0,
        timeLogSessions: [],
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        isActive: true,
      );

      final instanceRef =
          await ActivityInstanceRecord.collectionForUser(currentUserUid)
              .add(instanceData);
      final instanceDoc = await instanceRef.get();
      if (instanceDoc.exists) {
        return ActivityInstanceRecord.fromSnapshot(instanceDoc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _resetSequenceItems() async {
    // Check if there are any non-productive items to reset
    // (sequence_item is legacy, now all are non_productive)
    final hasSequenceItems = _sequenceWithInstances?.sequence.itemTypes.any(
            (type) => type == 'sequence_item' || type == 'non_productive') ??
        false;

    if (!hasSequenceItems) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No non-productive items to reset'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Non-Productive Items'),
        content: const Text(
            'This will create fresh instances for all completed non-productive items. '
            'Habits and tasks will not be affected.\n\n'
            'Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resetting non-productive items...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final resetCount = await SequenceService.resetSequenceItems(
        sequenceId: widget.sequence.reference.id,
        currentInstances: _sequenceWithInstances!.instances,
        itemTypes: _sequenceWithInstances!.sequence.itemTypes,
        itemIds: _sequenceWithInstances!.sequence.itemIds,
        userId: currentUserUid,
      );

      // Refresh the sequence to show new instances
      await _refreshSequence();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Reset $resetCount non-productive item${resetCount != 1 ? 's' : ''}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resetting non-productive items: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getCategoryColor(ActivityInstanceRecord instance) {
    final category = _categories
        .firstWhereOrNull((c) => c.name == instance.templateCategoryName);
    if (category == null) {
      return '#000000';
    }
    return category.color;
  }

  Widget _buildSectionHeader(String title, int count) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: theme.neumorphicGradient,
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: theme.neumorphicShadowsRaised,
      ),
      child: Row(
        children: [
          Icon(
            Icons.playlist_play,
            color: theme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: theme.titleMedium.override(
              fontWeight: FontWeight.w600,
              color: theme.primary,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemComponent(ActivityInstanceRecord? instance, String itemId,
      String itemType, String itemName) {
    // All items should have instances now (created in _loadSequenceWithInstances)
    // If instance is null, show loading placeholder (shouldn't happen)
    if (instance == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        padding: const EdgeInsets.all(16),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // Use ItemComponent for all items with instances (habits, tasks, and non-productive)
    // Use actual category color if available, fallback to category lookup
    final categoryColor = instance.templateCategoryColor.isNotEmpty
        ? instance.templateCategoryColor
        : _getCategoryColor(instance);

    return ItemComponent(
      key: Key(instance.reference.id),
      instance: instance,
      categoryColorHex: categoryColor,
      onRefresh: _refreshSequence,
      onInstanceUpdated: (updatedInstance) {
        setState(() {
          if (_sequenceWithInstances != null) {
            _sequenceWithInstances!.instances[itemId] = updatedInstance;
          }
        });
      },
      onInstanceDeleted: (deletedInstance) {
        setState(() {
          if (_sequenceWithInstances != null) {
            _sequenceWithInstances!.instances.remove(itemId);
          }
        });
      },
      onHabitUpdated: (updated) => {},
      onHabitDeleted: (deleted) async => _refreshSequence(),
      isHabit: itemType == 'habit',
      showTypeIcon: true,
      showRecurringIcon: true,
      showCompleted: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        title: Text(
          widget.sequence.name,
          style: FlutterFlowTheme.of(context).headlineMedium,
        ),
        actions: [
          IconButton(
            onPressed: _resetSequenceItems,
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Reset Non-Productive Items',
          ),
          IconButton(
            onPressed: _editSequence,
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Sequence',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sequenceWithInstances == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: FlutterFlowTheme.of(context).secondaryText,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading sequence',
                        style: FlutterFlowTheme.of(context).titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please try refreshing or check your connection',
                        style: FlutterFlowTheme.of(context).bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _refreshSequence,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    // Sequence Header
                    SliverToBoxAdapter(
                      child: _buildSectionHeader(
                        widget.sequence.name,
                        _sequenceWithInstances!.sequence.itemIds.length,
                      ),
                    ),
                    // Sequence Description
                    if (widget.sequence.description.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: FlutterFlowTheme.of(context)
                                .secondaryBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: FlutterFlowTheme.of(context).alternate,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            widget.sequence.description,
                            style: FlutterFlowTheme.of(context).bodyMedium,
                          ),
                        ),
                      ),
                    // Items in Order
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final itemId =
                              _sequenceWithInstances!.sequence.itemOrder[index];
                          final instance =
                              _sequenceWithInstances!.instances[itemId];
                          final itemType = _sequenceWithInstances!
                                  .sequence.itemTypes.isNotEmpty
                              ? _sequenceWithInstances!
                                  .sequence.itemTypes[index]
                              : 'habit';
                          final itemName = _sequenceWithInstances!
                                  .sequence.itemNames.isNotEmpty
                              ? _sequenceWithInstances!
                                  .sequence.itemNames[index]
                              : 'Unknown Item';
                          return _buildItemComponent(
                              instance, itemId, itemType, itemName);
                        },
                        childCount:
                            _sequenceWithInstances!.sequence.itemOrder.length,
                      ),
                    ),
                    // Missing Instances Info
                    if (_sequenceWithInstances!.missingInstances.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Some items don\'t have instances for today. They may appear after day-end processing.',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        color: Colors.orange.shade700,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Bottom spacing
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 100),
                    ),
                  ],
                ),
    );
  }
}
