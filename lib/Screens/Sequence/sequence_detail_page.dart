import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/sequence_service.dart';
import 'package:habit_tracker/Helper/backend/schema/sequence_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Sequence/create_sequence_page.dart';

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
  bool _isLoading = true;
  bool _isRefreshing = false;
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
      setState(() {
        _sequenceWithInstances = sequenceWithInstances;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshSequence() async {
    setState(() {
      _isRefreshing = true;
    });
    await _loadSequenceWithInstances();
    setState(() {
      _isRefreshing = false;
    });
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

  Future<void> _createInstanceForItem(String itemId, String itemType) async {
    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Creating instance...'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      // Create the instance using the service
      final instance = await SequenceService.createInstanceForSequenceItem(
        itemId: itemId,
        userId: currentUserUid,
      );
      if (instance != null) {
        // Update the local state to include the new instance
        setState(() {
          if (_sequenceWithInstances != null) {
            _sequenceWithInstances!.instances[itemId] = instance;
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Instance created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create instance'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating instance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _resetSequenceItems() async {
    // Check if there are any sequence items to reset
    final hasSequenceItems = _sequenceWithInstances?.sequence.itemTypes
            .any((type) => type == 'sequence_item') ??
        false;

    if (!hasSequenceItems) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No sequence items to reset'),
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
        title: const Text('Reset Sequence Items'),
        content: const Text(
            'This will create fresh instances for all completed sequence items. '
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
            content: Text('Resetting sequence items...'),
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
                'Reset $resetCount sequence item${resetCount != 1 ? 's' : ''}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resetting sequence items: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getItemTypeDisplayName(String categoryType) {
    switch (categoryType) {
      case 'habit':
        return 'Habit';
      case 'task':
        return 'Task';
      case 'sequence_item':
        return 'Sequence Item';
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
        return Colors.orange;
      default:
        return Colors.grey;
    }
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
    if (instance == null) {
      // Show placeholder for missing instance with original item name
      return GestureDetector(
        onTap: () => _createInstanceForItem(itemId, itemType),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).secondaryBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: FlutterFlowTheme.of(context).alternate,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _getItemTypeColor(itemType),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  itemType == 'habit'
                      ? Icons.repeat
                      : itemType == 'task'
                          ? Icons.assignment
                          : Icons.playlist_add,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemName,
                      style: FlutterFlowTheme.of(context).titleMedium,
                    ),
                    Text(
                      'Tap to start this item',
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getItemTypeColor(itemType).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getItemTypeDisplayName(itemType),
                  style: TextStyle(
                    fontSize: 10,
                    color: _getItemTypeColor(itemType),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Use actual category color if available, fallback to type color
    final categoryColor = instance.templateCategoryColor.isNotEmpty
        ? instance.templateCategoryColor
        : _getItemTypeColor(itemType).value.toRadixString(16).substring(2);

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
            tooltip: 'Reset Sequence Items',
          ),
          IconButton(
            onPressed: _editSequence,
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Sequence',
          ),
          IconButton(
            onPressed: _refreshSequence,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
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
