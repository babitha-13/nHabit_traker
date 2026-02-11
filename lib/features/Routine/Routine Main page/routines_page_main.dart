import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Routine/Routine%20Main%20page/Logic/routines_page_logic.dart';
import 'package:habit_tracker/features/Shared/Search/search_fab.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';

class Routines extends StatefulWidget {
  const Routines({super.key});
  @override
  State<Routines> createState() => _RoutinesState();
}

class _RoutinesState extends State<Routines> with RoutinesPageLogic {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    loadData();
    // Listen for search changes
    searchManager.addListener(onSearchChanged);
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        loadData();
      }
    });
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    searchManager.removeListener(onSearchChanged);
    super.dispose();
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
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      // Search indicator banner when search is active
                      if (searchQuery.isNotEmpty && filteredRoutines.isNotEmpty)
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
                        child: filteredRoutines.isEmpty
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
                                      searchQuery.isNotEmpty
                                          ? 'No routines found'
                                          : 'No routines yet',
                                      style: FlutterFlowTheme.of(context)
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      searchQuery.isNotEmpty
                                          ? 'Try a different search term'
                                          : 'Create routines to group related habits and tasks!',
                                      style: FlutterFlowTheme.of(context)
                                          .bodyMedium,
                                    ),
                                    if (searchQuery.isEmpty) ...[
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        onPressed: navigateToCreateRoutine,
                                        child: const Text('Create Routine'),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            : searchQuery.isEmpty
                                ? ReorderableListView.builder(
                                    itemCount: routines.length,
                                    onReorder: handleReorder,
                                    itemBuilder: (context, index) {
                                      final routine = routines[index];
                                      final itemNames =
                                          routine.itemNames.isNotEmpty
                                              ? routine.itemNames
                                              : getItemNames(routine.itemIds);
                                      return _buildRoutineTile(
                                        routine,
                                        itemNames,
                                        key: Key(routine.reference.id),
                                      );
                                    },
                                  )
                                : ListView.builder(
                                    itemCount: filteredRoutines.length,
                                    itemBuilder: (context, index) {
                                      final routine = filteredRoutines[index];
                                      final itemNames =
                                          routine.itemNames.isNotEmpty
                                              ? routine.itemNames
                                              : getItemNames(routine.itemIds);
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
                onPressed: navigateToCreateRoutine,
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
        onTap: () => navigateToRoutineDetail(routine),
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
            onPressed: () => showRoutineOverflowMenu(context, routine),
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
    final reminderLabel = getReminderChipLabel(routine);

    return [
      _buildRoutineInfoChip(
        icon: Icons.access_time,
        label: dueTimeLabel,
        onPressed: () => selectDueTime(routine),
        theme: theme,
      ),
      _buildRoutineInfoChip(
        icon: Icons.notifications_none,
        label: reminderLabel,
        onPressed: () => selectReminders(routine),
        theme: theme,
      ),
    ];
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
}
