import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/routine_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/backend/routine_order_service.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_fab.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/time_utils.dart';
import 'package:habit_tracker/Screens/Routine/create_routine_page.dart';
import 'package:habit_tracker/Screens/Routine/Routine_reminder_frequency/routine_reminder.dart';
import 'package:habit_tracker/Screens/Routine/routine_detail_page.dart';

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
    final routineName = routine.name;
    final routineId = routine.reference.id;

    // OPTIMISTIC UPDATE: Remove from local list immediately
    setState(() {
      _routines.removeWhere((r) => r.reference.id == routineId);
    });

    try {
      await deleteRoutine(routineId, userId: currentUserUid);
      // Background reconciliation: reload to ensure sync
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Routine "$routineName" deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // On error: show snackbar and reload to restore correct state
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting routine: $e'),
            backgroundColor: Colors.red,
          ),
        );
        // Background refresh to restore correct state
        _loadData();
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
        .then((result) {
      // Apply edit result immediately to avoid stale data on quick re-open
      if (result is Map<String, dynamic> && result['routineId'] != null) {
        final routineId = result['routineId'] as String;
        final itemIds = result['itemIds'] as List<String>?;
        final itemOrder = result['itemOrder'] as List<String>?;
        final itemNames = result['itemNames'] as List<String>?;
        final itemTypes = result['itemTypes'] as List<String>?;

        if (itemIds != null && mounted) {
          // Find and update the routine in local list immediately
          final routineIndex =
              _routines.indexWhere((r) => r.reference.id == routineId);
          if (routineIndex != -1) {
            final updatedRoutine = RoutineRecord.getDocumentFromData(
              {
                ..._routines[routineIndex].snapshotData,
                'itemIds': itemIds,
                'itemOrder': itemOrder ?? itemIds,
                'itemNames': itemNames ?? [],
                'itemTypes': itemTypes ?? [],
                'lastUpdated': DateTime.now(),
              },
              _routines[routineIndex].reference,
            );
            setState(() {
              _routines[routineIndex] = updatedRoutine;
            });
          }
        }
      }
      // Reload the list to ensure everything is in sync
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
                    ],
                  ),
            // Search FAB at bottom-left
            const SearchFAB(heroTag: 'search_fab_routines'),
            // FAB at bottom-right for creating new routine
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'fab_create_routine',
                onPressed: _navigateToCreateRoutine,
                backgroundColor: FlutterFlowTheme.of(context).primary,
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                ),
                tooltip: 'Create New Routine',
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
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _buildRoutineInfoChips(routine),
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

  List<Widget> _buildRoutineInfoChips(RoutineRecord routine) {
    final theme = FlutterFlowTheme.of(context);
    final dueTimeLabel = routine.hasDueTime()
        ? TimeUtils.formatTimeForDisplay(routine.dueTime)
        : 'Set due time';
    final reminderLabel = _getReminderChipLabel(routine);

    return [
      _buildRoutineInfoChip(
        icon: Icons.access_time,
        label: dueTimeLabel,
        onPressed: () => _selectDueTime(routine),
        theme: theme,
      ),
      _buildRoutineInfoChip(
        icon: Icons.notifications_none,
        label: reminderLabel,
        onPressed: () => _selectReminders(routine),
        theme: theme,
      ),
    ];
  }

  Future<void> _selectDueTime(RoutineRecord routine) async {
    final currentDueTime = TimeUtils.stringToTimeOfDay(routine.dueTime);
    final picked = await showTimePicker(
      context: context,
      initialTime: currentDueTime ?? TimeUtils.getCurrentTime(),
    );

    if (picked == null) return;

    final newDueTime = TimeUtils.timeOfDayToString(picked);
    final routineId = routine.reference.id;

    // OPTIMISTIC UPDATE: Patch routine's dueTime immediately
    final routineIndex =
        _routines.indexWhere((r) => r.reference.id == routineId);
    if (routineIndex != -1) {
      final updatedRoutine = RoutineRecord.getDocumentFromData(
        {
          ..._routines[routineIndex].snapshotData,
          'dueTime': newDueTime,
          'lastUpdated': DateTime.now(),
        },
        _routines[routineIndex].reference,
      );
      setState(() {
        _routines[routineIndex] = updatedRoutine;
      });
    }

    try {
      await RoutineService.updateRoutine(
        routineId: routineId,
        dueTime: newDueTime,
        userId: currentUserUid,
      );
      // Background reconciliation: reload to ensure sync
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating due time: $e'),
          backgroundColor: Colors.red,
        ),
      );
      // Background refresh to restore correct state
      _loadData();
    }
  }

  Future<void> _selectReminders(RoutineRecord routine) async {
    final reminders = ReminderConfigList.fromMapList(routine.reminders);
    final result = await RoutineReminderSettingsDialog.show(
      context: context,
      dueTime: TimeUtils.stringToTimeOfDay(routine.dueTime),
      initialReminders: reminders,
      initialFrequencyType: routine.reminderFrequencyType.isEmpty
          ? null
          : routine.reminderFrequencyType,
      initialEveryXValue: routine.everyXValue,
      initialEveryXPeriodType:
          routine.everyXPeriodType.isEmpty ? null : routine.everyXPeriodType,
      initialSpecificDays: List.from(routine.specificDays),
    );

    if (result == null) return;

    final routineId = routine.reference.id;

    // OPTIMISTIC UPDATE: Patch routine's reminder fields immediately
    final routineIndex =
        _routines.indexWhere((r) => r.reference.id == routineId);
    if (routineIndex != -1) {
      final updatedData =
          Map<String, dynamic>.from(_routines[routineIndex].snapshotData);
      updatedData['reminders'] = ReminderConfigList.toMapList(result.reminders);
      updatedData['reminderFrequencyType'] = result.frequencyType ?? '';
      updatedData['everyXValue'] =
          result.frequencyType == 'every_x' ? result.everyXValue : 1;
      updatedData['everyXPeriodType'] = result.frequencyType == 'every_x'
          ? (result.everyXPeriodType ?? '')
          : '';
      updatedData['specificDays'] = result.frequencyType == 'specific_days'
          ? result.specificDays
          : const [];
      updatedData['remindersEnabled'] = result.remindersEnabled;
      updatedData['lastUpdated'] = DateTime.now();

      final updatedRoutine = RoutineRecord.getDocumentFromData(
        updatedData,
        _routines[routineIndex].reference,
      );
      setState(() {
        _routines[routineIndex] = updatedRoutine;
      });
    }

    try {
      await RoutineService.updateRoutine(
        routineId: routineId,
        reminders: ReminderConfigList.toMapList(result.reminders),
        reminderFrequencyType: result.frequencyType,
        everyXValue: result.frequencyType == 'every_x' ? result.everyXValue : 1,
        everyXPeriodType:
            result.frequencyType == 'every_x' ? result.everyXPeriodType : null,
        specificDays: result.frequencyType == 'specific_days'
            ? result.specificDays
            : const [],
        remindersEnabled: result.remindersEnabled,
        userId: currentUserUid,
      );
      // Background reconciliation: reload to ensure sync
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating reminders: $e'),
          backgroundColor: Colors.red,
        ),
      );
      // Background refresh to restore correct state
      _loadData();
    }
  }

  String _getReminderChipLabel(RoutineRecord routine) {
    final reminders = ReminderConfigList.fromMapList(routine.reminders);
    if (!routine.remindersEnabled || reminders.isEmpty) {
      return 'Set reminders';
    }
    if (reminders.length == 1) {
      return reminders.first.getDescription();
    }
    return '${reminders.length} reminders';
  }

  Widget _buildRoutineInfoChip({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required FlutterFlowTheme theme,
  }) {
    return ActionChip(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(icon, size: 16, color: theme.secondaryText),
      label: Text(
        label,
        style: theme.bodySmall.copyWith(
          color: theme.secondaryText,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      labelPadding: const EdgeInsets.only(left: 4, right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      backgroundColor: theme.secondaryBackground,
      shape: StadiumBorder(
        side: BorderSide(color: theme.surfaceBorderColor, width: 0.4),
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
