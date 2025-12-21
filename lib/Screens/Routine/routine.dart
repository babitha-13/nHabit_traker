import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/backend/routine_order_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Helper/utils/search_fab.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Screens/Routine/create_routine_page.dart';
import 'package:habit_tracker/Screens/Routine/routine_detail_page.dart';
import 'package:habit_tracker/Screens/NonProductive/non_productive_templates_page.dart';
import 'package:habit_tracker/Screens/NonProductive/non_productive_template_dialog.dart';

class Routines extends StatefulWidget {
  const Routines({super.key});
  @override
  State<Routines> createState() => _RoutinesState();
}

class _RoutinesState extends State<Routines> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  List<RoutineRecord> _routines = [];
  List<ActivityRecord> _habits = [];
  bool _isLoading = true;
  // Search functionality
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();
  // Track routines being reordered to prevent stale updates
  Set<String> _reorderingRoutineIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    // Listen for search changes
    _searchManager.addListener(_onSearchChanged);
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    _searchManager.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (mounted) {
      setState(() {
        _searchQuery = query;
      });
    }
  }

  List<RoutineRecord> get _filteredRoutines {
    if (_searchQuery.isEmpty) {
      return _routines;
    }
    final query = _searchQuery.toLowerCase();
    return _routines.where((routine) {
      final nameMatch = routine.name.toLowerCase().contains(query);
      final descriptionMatch =
          routine.description.toLowerCase().contains(query);
      return nameMatch || descriptionMatch;
    }).toList();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final routines = await queryRoutineRecordOnce(userId: userId);
        final habits = await queryActivitiesRecordOnce(userId: userId);
        // Sort routines by order to ensure consistent display
        final sortedRoutines =
            RoutineOrderService.sortRoutinesByOrder(routines);
        setState(() {
          _routines = sortedRoutines;
          _habits = habits;
          _isLoading = false;
        });
        // Initialize order values for routines that don't have them
        RoutineOrderService.initializeOrderValues(_routines);
      } else {}
    } catch (e) {
      if (e is FirebaseException) {}
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteRoutine(RoutineRecord routine) async {
    try {
      await deleteRoutine(routine.reference.id, userId: currentUserUid);
      await _loadData(); // Reload the list
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Routine "${routine.name}" deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting routine: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToCreateRoutine() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => const CreateRoutinePage(),
      ),
    )
        .then((_) {
      // Reload the list after creating a routine
      _loadData();
    });
  }

  void _navigateToEditRoutine(RoutineRecord routine) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => CreateRoutinePage(
          existingRoutine: routine,
        ),
      ),
    )
        .then((_) {
      // Reload the list after editing a routine
      _loadData();
    });
  }

  void _navigateToRoutineDetail(RoutineRecord routine) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RoutineDetailPage(
          routine: routine,
        ),
      ),
    );
  }

  List<String> _getItemNames(List<String> itemIds) {
    return itemIds.map((id) {
      try {
        final activity = _habits.firstWhere((h) => h.reference.id == id);
        return activity.name;
      } catch (e) {
        return 'Unknown Item';
      }
    }).toList();
  }

  void _navigateToNonProductiveTemplates() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const NonProductiveTemplatesPage(),
      ),
    );
  }

  Future<void> _showCreateNonProductiveDialog() async {
    final result = await showDialog<ActivityRecord>(
      context: context,
      builder: (context) => NonProductiveTemplateDialog(
        onTemplateCreated: (template) {
          Navigator.of(context).pop(template);
        },
      ),
    );
    // Optionally reload data if needed
    if (result != null) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      body: SafeArea(
        top: true,
        child: Stack(
          children: [
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      // Search indicator banner when search is active
                      if (_searchQuery.isNotEmpty &&
                          _filteredRoutines.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          color: FlutterFlowTheme.of(context)
                              .secondaryBackground
                              .withOpacity(0.7),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Drag and drop is disabled while searching',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        fontSize: 12,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Create New Routine button at the top
                      if (_filteredRoutines.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _navigateToCreateRoutine,
                              icon: const Icon(Icons.add),
                              label: const Text('Create New Routine'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    FlutterFlowTheme.of(context).primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                      // Routines list
                      Expanded(
                        child: _filteredRoutines.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.playlist_play,
                                      size: 64,
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'No routines found'
                                          : 'No routines yet',
                                      style: FlutterFlowTheme.of(context)
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'Try a different search term'
                                          : 'Create routines to group related habits and tasks!',
                                      style: FlutterFlowTheme.of(context)
                                          .bodyMedium,
                                    ),
                                    if (_searchQuery.isEmpty) ...[
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        onPressed: _navigateToCreateRoutine,
                                        child: const Text('Create Routine'),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            : _searchQuery.isEmpty
                                ? ReorderableListView.builder(
                                    itemCount: _routines.length,
                                    onReorder: _handleReorder,
                                    itemBuilder: (context, index) {
                                      final routine = _routines[index];
                                      final itemNames =
                                          routine.itemNames.isNotEmpty
                                              ? routine.itemNames
                                              : _getItemNames(routine.itemIds);
                                      return _buildRoutineTile(
                                        routine,
                                        itemNames,
                                        key: Key(routine.reference.id),
                                      );
                                    },
                                  )
                                : ListView.builder(
                                    itemCount: _filteredRoutines.length,
                                    itemBuilder: (context, index) {
                                      final routine = _filteredRoutines[index];
                                      final itemNames =
                                          routine.itemNames.isNotEmpty
                                              ? routine.itemNames
                                              : _getItemNames(routine.itemIds);
                                      return _buildRoutineTile(
                                        routine,
                                        itemNames,
                                      );
                                    },
                                  ),
                      ),
                      // Non-Productive Tasks Button at the bottom
                      // Add horizontal padding to avoid overlapping with FABs
                      Padding(
                        padding: const EdgeInsets.fromLTRB(80, 16, 80, 16),
                        child: ElevatedButton.icon(
                          onPressed: _navigateToNonProductiveTemplates,
                          icon: const Icon(Icons.access_time),
                          label: const Text('Non Productive Tasks'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                FlutterFlowTheme.of(context).primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
            // Search FAB at bottom-left
            const SearchFAB(heroTag: 'search_fab_routines'),
            // Existing FAB at bottom-right
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag:
                    null, // Disable Hero animation to avoid conflicts during navigation
                onPressed: _showCreateNonProductiveDialog,
                backgroundColor: FlutterFlowTheme.of(context).primary,
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRoutineOverflowMenu(
      BuildContext anchorContext, RoutineRecord routine) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    final selected = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        overlay.size.width - position.dx - size.width,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: const [
        PopupMenuItem<String>(
            value: 'edit',
            height: 32,
            child: Text('Edit', style: TextStyle(fontSize: 12))),
        PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
            value: 'delete',
            height: 32,
            child: Text('Delete', style: TextStyle(fontSize: 12))),
      ],
    );
    if (selected == null) return;
    if (selected == 'edit') {
      _navigateToEditRoutine(routine);
    } else if (selected == 'delete') {
      _showDeleteConfirmation(routine);
    }
  }

  void _showDeleteConfirmation(RoutineRecord routine) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Routine'),
        content: Text(
          'Are you sure you want to delete "${routine.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteRoutine(routine);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutineTile(
    RoutineRecord routine,
    List<String> itemNames, {
    Key? key,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1,
        ),
      ),
      child: ListTile(
        onTap: () => _navigateToRoutineDetail(routine),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.playlist_play,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          routine.name,
          style: FlutterFlowTheme.of(context).titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (routine.description.isNotEmpty)
              Text(
                routine.description,
                style: FlutterFlowTheme.of(context).bodyMedium,
              ),
            const SizedBox(height: 4),
            Text(
              '${itemNames.length} items',
              style: FlutterFlowTheme.of(context).bodySmall,
            ),
          ],
        ),
        trailing: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showRoutineOverflowMenu(context, routine),
            color: FlutterFlowTheme.of(context).secondaryText,
          ),
        ),
      ),
    );
  }

  /// Handle reordering of routines
  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    final reorderingIds = <String>{};
    try {
      // Allow dropping at the end (newIndex can equal sequences.length)
      if (oldIndex < 0 ||
          oldIndex >= _routines.length ||
          newIndex < 0 ||
          newIndex > _routines.length) return;

      // Create a copy of the routines list for reordering
      final reorderedRoutines = List<RoutineRecord>.from(_routines);

      // Adjust newIndex for the case where we're moving down
      int adjustedNewIndex = newIndex;
      if (oldIndex < newIndex) {
        adjustedNewIndex -= 1;
      }

      // Get the routine being moved
      final movedRoutine = reorderedRoutines.removeAt(oldIndex);
      reorderedRoutines.insert(adjustedNewIndex, movedRoutine);

      // OPTIMISTIC UI UPDATE: Update local state immediately
      // Update order values and create updated sequences
      final updatedRoutines = <RoutineRecord>[];
      for (int i = 0; i < reorderedRoutines.length; i++) {
        final routine = reorderedRoutines[i];
        final routineId = routine.reference.id;
        reorderingIds.add(routineId);

        // Create updated sequence with new listOrder
        final updatedData = Map<String, dynamic>.from(routine.snapshotData);
        updatedData['listOrder'] = i;
        final updatedRoutine = RoutineRecord.getDocumentFromData(
          updatedData,
          routine.reference,
        );

        updatedRoutines.add(updatedRoutine);
      }

      // Add routine IDs to reordering set to prevent stale updates
      _reorderingRoutineIds.addAll(reorderingIds);

      // Replace _sequences with the reordered list (this is the key fix!)
      if (mounted) {
        setState(() {
          _routines = updatedRoutines;
        });
      }

      // Perform database update in background
      await RoutineOrderService.reorderRoutines(
        updatedRoutines,
        oldIndex,
        adjustedNewIndex,
      );

      // Clear reordering set after successful database update
      _reorderingRoutineIds.removeAll(reorderingIds);
    } catch (e) {
      // Clear reordering set even on error
      _reorderingRoutineIds.removeAll(reorderingIds);
      // Revert to correct state by refreshing data
      await _loadData();
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reordering routines: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
