import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/routine_service.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Routine/create_routine_page.dart';
import 'package:collection/collection.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';

class RoutineDetailPage extends StatefulWidget {
  final RoutineRecord routine;
  const RoutineDetailPage({
    Key? key,
    required this.routine,
  }) : super(key: key);
  @override
  State<RoutineDetailPage> createState() => _RoutineDetailPageState();
}

class _RoutineDetailPageState extends State<RoutineDetailPage> {
  RoutineWithInstances? _routineWithInstances;
  List<CategoryRecord> _categories = [];
  bool _isLoading = true;
  bool _isReordering = false;
  @override
  void initState() {
    super.initState();
    _loadRoutineWithInstances();
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        _refreshRoutine();
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceUpdated,
        (param) {
      if (mounted) {
        _handleRoutineInstanceUpdated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceDeleted,
        (param) {
      if (mounted) {
        _handleRoutineInstanceDeleted(param);
      }
    });
  }

  Future<void> _loadRoutineWithInstances() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final routineWithInstances = await RoutineService.getRoutineWithInstances(
        routineId: widget.routine.reference.id,
        userId: currentUserUid,
      );

      // Load categories for color lookup
      final habitCategories = await queryHabitCategoriesOnce(
        userId: currentUserUid,
        callerTag: 'RoutineDetailPage._loadRoutine.habits',
      );
      final taskCategories = await queryTaskCategoriesOnce(
        userId: currentUserUid,
        callerTag: 'RoutineDetailPage._loadRoutine.tasks',
      );
      final allCategories = [...habitCategories, ...taskCategories];

      // Automatically create instances for items without them (habits and tasks only)
      RoutineWithInstances? updatedRoutineWithInstances = routineWithInstances;
      if (routineWithInstances != null) {
        final routine = routineWithInstances.routine;
        final instances = Map<String, ActivityInstanceRecord>.from(
            routineWithInstances.instances);

        // Check each item in the routine
        for (int i = 0; i < routine.itemIds.length; i++) {
          final itemId = routine.itemIds[i];
          final itemType =
              routine.itemTypes.isNotEmpty && i < routine.itemTypes.length
                  ? routine.itemTypes[i]
                  : 'habit';

          // Skip if instance already exists
          if (instances.containsKey(itemId)) {
            continue;
          }

          // Auto-create instances for habits, tasks, and non-productive items
          if (itemType == 'habit' || itemType == 'task') {
            try {
              final newInstance =
                  await RoutineService.createInstanceForRoutineItem(
                itemId: itemId,
                userId: currentUserUid,
              );
              if (newInstance != null) {
                instances[itemId] = newInstance;
              }
            } catch (e) {
              // Silently fail for individual instance creation - item will show as missing
              // This prevents one failed instance from breaking the entire routine load
            }
          } else if (itemType == 'non_productive') {
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

        // Create new RoutineWithInstances with updated instances map
        updatedRoutineWithInstances = RoutineWithInstances(
          routine: routine,
          instances: instances,
        );
      }

      if (mounted) {
        setState(() {
          _routineWithInstances = updatedRoutineWithInstances;
          _categories = allCategories;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshRoutine() async {
    await _loadRoutineWithInstances();
  }

  ActivityInstanceRecord? _extractInstanceFromNotification(Object? param) {
    if (param is ActivityInstanceRecord) {
      return param;
    }
    if (param is Map && param['instance'] is ActivityInstanceRecord) {
      return param['instance'] as ActivityInstanceRecord;
    }
    return null;
  }

  void _handleRoutineInstanceUpdated(Object? param) {
    final updatedInstance = _extractInstanceFromNotification(param);
    if (updatedInstance == null || _routineWithInstances == null) {
      return;
    }
    final entry = _routineWithInstances!.instances.entries.firstWhereOrNull(
      (mapEntry) =>
          mapEntry.value.reference.id == updatedInstance.reference.id,
    );
    if (entry == null) {
      return;
    }
    setState(() {
      _routineWithInstances!.instances[entry.key] = updatedInstance;
    });
  }

  void _handleRoutineInstanceDeleted(Object? param) {
    final deletedInstance = _extractInstanceFromNotification(param);
    if (deletedInstance == null || _routineWithInstances == null) {
      return;
    }
    final entry = _routineWithInstances!.instances.entries.firstWhereOrNull(
      (mapEntry) =>
          mapEntry.value.reference.id == deletedInstance.reference.id,
    );
    if (entry == null) {
      return;
    }
    setState(() {
      _routineWithInstances!.instances.remove(entry.key);
    });
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    super.dispose();
  }

  void _editRoutine() {
    final routineToEdit = _routineWithInstances?.routine ?? widget.routine;
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => CreateRoutinePage(
          existingRoutine: routineToEdit,
        ),
      ),
    )
        .then((result) {
      // Keep UI in sync immediately when coming back from edit
      if (result is Map<String, dynamic> && result['itemIds'] != null) {
        final itemIds = List<String>.from(result['itemIds'] as List);
        final itemOrder = result['itemOrder'] != null
            ? List<String>.from(result['itemOrder'] as List)
            : itemIds;
        final itemNames = result['itemNames'] != null
            ? List<String>.from(result['itemNames'] as List)
            : null;
        final itemTypes = result['itemTypes'] != null
            ? List<String>.from(result['itemTypes'] as List)
            : null;

        // Check if items were added or removed
        final previousIds =
            _routineWithInstances?.routine.itemIds ?? <String>[];
        final itemsChanged = itemIds.length != previousIds.length ||
            !itemIds.every((id) => previousIds.contains(id)) ||
            !previousIds.every((id) => itemIds.contains(id));

        _applyRoutineEdit(itemIds, itemOrder, itemNames, itemTypes);

        // If items were added/removed, refresh instances in background
        if (itemsChanged) {
          _refreshRoutine();
        }
      }
    });
  }

  /// Apply routine edit result immediately to keep UI in sync
  void _applyRoutineEdit(
    List<String> itemIds,
    List<String> itemOrder,
    List<String>? itemNames,
    List<String>? itemTypes,
  ) {
    if (_routineWithInstances == null) return;
    final currentRoutine = _routineWithInstances!.routine;

    // Use provided names/types if available, otherwise fall back to existing
    final finalNames = itemNames ??
        itemOrder.map((id) {
          final index = currentRoutine.itemIds.indexOf(id);
          return index != -1 && index < currentRoutine.itemNames.length
              ? currentRoutine.itemNames[index]
              : 'Unknown Item';
        }).toList();

    final finalTypes = itemTypes ??
        itemOrder.map((id) {
          final index = currentRoutine.itemIds.indexOf(id);
          return index != -1 && index < currentRoutine.itemTypes.length
              ? currentRoutine.itemTypes[index]
              : 'habit';
        }).toList();

    final updatedData = Map<String, dynamic>.from(currentRoutine.snapshotData);
    updatedData['itemIds'] = itemIds;
    updatedData['itemOrder'] = itemOrder;
    updatedData['itemNames'] = finalNames;
    updatedData['itemTypes'] = finalTypes;
    updatedData['lastUpdated'] = DateTime.now();

    final updatedRoutine = RoutineRecord.getDocumentFromData(
      updatedData,
      currentRoutine.reference,
    );

    // Filter instances to only include items that still exist
    final filteredInstances = <String, ActivityInstanceRecord>{};
    for (final itemId in itemOrder) {
      if (_routineWithInstances!.instances.containsKey(itemId)) {
        filteredInstances[itemId] = _routineWithInstances!.instances[itemId]!;
      }
    }

    setState(() {
      _routineWithInstances = RoutineWithInstances(
        routine: updatedRoutine,
        instances: filteredInstances,
      );
    });
  }

  /// Legacy method for backward compatibility (reorder only)
  void _applyRoutineOrder(List<String> orderedIds) {
    _applyRoutineEdit(orderedIds, orderedIds, null, null);
  }

  Future<void> _onReorderItems(int oldIndex, int newIndex) async {
    if (_routineWithInstances == null) return;
    if (_isReordering) return;

    // Adjust newIndex for the case where we're moving down
    int adjustedNewIndex = newIndex;
    if (oldIndex < newIndex) {
      adjustedNewIndex -= 1;
    }

    final currentOrder = List<String>.from(_routineWithInstances!.routine.itemOrder);
    if (oldIndex < 0 ||
        oldIndex >= currentOrder.length ||
        adjustedNewIndex < 0 ||
        adjustedNewIndex >= currentOrder.length) {
      return;
    }

    final moved = currentOrder.removeAt(oldIndex);
    currentOrder.insert(adjustedNewIndex, moved);

    // Immediate UI sync (no refresh)
    _applyRoutineOrder(currentOrder);

    setState(() => _isReordering = true);
    try {
      await RoutineService.updateRoutine(
        routineId: _routineWithInstances!.routine.reference.id,
        userId: currentUserUid,
        itemIds: currentOrder,
        itemOrder: currentOrder,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error reordering routine items: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isReordering = false);
      }
    }
  }

  /// Create a pending instance for a non-productive item (for display with ItemComponent)
  /// Reuses existing instance for today if available, otherwise creates new one
  Future<ActivityInstanceRecord?> _createPendingNonProductiveInstance(
      String itemId) async {
    try {
      // First, check if there's already an instance for today
      final today = DateService.todayStart;
      final existingInstancesQuery =
          ActivityInstanceRecord.collectionForUser(currentUserUid)
              .where('templateId', isEqualTo: itemId)
              .where('belongsToDate', isEqualTo: today)
              .limit(1);
      final existingInstances = await existingInstancesQuery.get();

      if (existingInstances.docs.isNotEmpty) {
        // Reuse existing instance for today
        return ActivityInstanceRecord.fromSnapshot(
            existingInstances.docs.first);
      }

      // Only create new instance if none exists for today
      final templateDoc = await ActivityRecord.collectionForUser(currentUserUid)
          .doc(itemId)
          .get();
      if (!templateDoc.exists) {
        return null;
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);

      final newInstanceRef =
          await ActivityInstanceService.createActivityInstance(
        templateId: itemId,
        template: template,
        userId: currentUserUid,
        dueDate: DateTime.now(),
      );

      final instanceDoc = await newInstanceRef.get();
      if (instanceDoc.exists) {
        return ActivityInstanceRecord.fromSnapshot(instanceDoc);
      }
      return null;
    } catch (e) {
      print('RoutineDetailPage: Error creating non-productive instance: $e');
      return null;
    }
  }

  Future<void> _resetRoutineItems() async {
    // Check if there are any non-productive items to reset
    final hasRoutineItems = _routineWithInstances?.routine.itemTypes
            .any((type) => type == 'non_productive') ??
        false;

    if (!hasRoutineItems) {
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

      final resetCount = await RoutineService.resetRoutineItems(
        routineId: widget.routine.reference.id,
        currentInstances: _routineWithInstances!.instances,
        itemTypes: _routineWithInstances!.routine.itemTypes,
        itemIds: _routineWithInstances!.routine.itemIds,
        userId: currentUserUid,
      );

      // Refresh the routine to show new instances
      await _refreshRoutine();

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          Expanded(
            child: Text(
              title,
              style: theme.titleMedium.override(
                fontWeight: FontWeight.w600,
                color: theme.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: _resetRoutineItems,
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Reset Non-Productive Items',
            color: theme.secondaryText,
            iconSize: 20,
          ),
          IconButton(
            onPressed: _editRoutine,
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Routine',
            color: theme.secondaryText,
            iconSize: 20,
          ),
          const SizedBox(width: 4),
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
    // All items should have instances now (created in _loadRoutineWithInstances)
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
      key: ValueKey('${instance.reference.id}_${instance.status}'),
      instance: instance,
      categoryColorHex: categoryColor,
      onRefresh: _refreshRoutine,
      onInstanceUpdated: (updatedInstance) {
        setState(() {
          if (_routineWithInstances != null) {
            _routineWithInstances!.instances[itemId] = updatedInstance;
          }
        });
      },
      onInstanceDeleted: (deletedInstance) {
        setState(() {
          if (_routineWithInstances != null) {
            _routineWithInstances!.instances.remove(itemId);
          }
        });
      },
      onHabitUpdated: (updated) => {},
      onHabitDeleted: (deleted) async => _refreshRoutine(),
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
          'Routine',
          style: FlutterFlowTheme.of(context).headlineMedium,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _routineWithInstances == null
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
                        'Error loading routine',
                        style: FlutterFlowTheme.of(context).titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please try refreshing or check your connection',
                        style: FlutterFlowTheme.of(context).bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _refreshRoutine,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    // Routine Header
                    SliverToBoxAdapter(
                      child: _buildSectionHeader(
                        widget.routine.name,
                        _routineWithInstances!.routine.itemIds.length,
                      ),
                    ),
                    // Routine Description
                    if (widget.routine.description.isNotEmpty)
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
                            widget.routine.description,
                            style: FlutterFlowTheme.of(context).bodyMedium,
                          ),
                        ),
                      ),
                    // Items in Order (reorderable)
                    SliverReorderableList(
                      itemCount: _routineWithInstances!.routine.itemOrder.length,
                      onReorder: _onReorderItems,
                      itemBuilder: (context, index) {
                        final itemId =
                            _routineWithInstances!.routine.itemOrder[index];
                        final instance = _routineWithInstances!.instances[itemId];
                        final itemType = _routineWithInstances!.routine.itemTypes
                                    .isNotEmpty &&
                                index < _routineWithInstances!.routine.itemTypes.length
                            ? _routineWithInstances!.routine.itemTypes[index]
                            : 'habit';
                        final itemName = _routineWithInstances!.routine.itemNames
                                    .isNotEmpty &&
                                index < _routineWithInstances!.routine.itemNames.length
                            ? _routineWithInstances!.routine.itemNames[index]
                            : 'Unknown Item';

                        return ReorderableDelayedDragStartListener(
                          key: ValueKey('routine_item_$itemId'),
                          index: index,
                          enabled: !_isReordering,
                          child: _buildItemComponent(
                            instance,
                            itemId,
                            itemType,
                            itemName,
                          ),
                        );
                      },
                    ),
                    // Missing Instances Info
                    if (_routineWithInstances!.missingInstances.isNotEmpty)
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
