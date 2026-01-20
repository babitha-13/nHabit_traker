import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Screens/Routine/Backend_data/routine_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Screens/Routine/Backend_data/routine_order_service.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/time_utils.dart';
import 'package:habit_tracker/Screens/Routine/Create%20Routine/create_routine_page.dart';
import 'package:habit_tracker/Screens/Routine/Routine_reminder_frequency/routine_reminder.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Routine/routine_detail_page.dart';

/// Routine Main page mixin for Routines page that contains all business logic
/// This separates business logic from UI code
mixin RoutinesPageLogic<T extends StatefulWidget> on State<T> {
  // State variables
  List<RoutineRecord> routines = [];
  List<ActivityRecord> habits = [];
  bool isLoading = true;
  // Search functionality
  String searchQuery = '';
  final SearchStateManager searchManager = SearchStateManager();
  // Track routines being reordered to prevent stale updates
  Set<String> reorderingRoutineIds = {};
  // Cache for filtered routines to avoid recalculation on every build
  List<RoutineRecord>? cachedFilteredRoutines;
  int routinesHashCode = 0; // Current hash of routines
  String lastSearchQuery = '';

  void onSearchChanged(String query) {
    if (mounted) {
      setState(() {
        searchQuery = query;
        // Invalidate cache when search query changes
        cachedFilteredRoutines = null;
      });
    }
  }

  List<RoutineRecord> get filteredRoutines {
    // Check if cache is still valid
    final currentRoutinesHash = routines.length.hashCode ^
        routines.fold(0, (sum, r) => sum ^ r.reference.id.hashCode);
    
    final cacheInvalid = cachedFilteredRoutines == null ||
        currentRoutinesHash != routinesHashCode ||
        searchQuery != lastSearchQuery;
    
    if (!cacheInvalid && cachedFilteredRoutines != null) {
      return cachedFilteredRoutines!;
    }
    
    // Recalculate filtered list
    List<RoutineRecord> filtered;
    if (searchQuery.isEmpty) {
      filtered = routines;
    } else {
      final query = searchQuery.toLowerCase();
      filtered = routines.where((routine) {
        final nameMatch = routine.name.toLowerCase().contains(query);
        final descriptionMatch =
            routine.description.toLowerCase().contains(query);
        return nameMatch || descriptionMatch;
      }).toList();
    }
    
    // Update cache
    cachedFilteredRoutines = filtered;
    routinesHashCode = currentRoutinesHash;
    lastSearchQuery = searchQuery;
    
    return filtered;
  }

  Future<void> loadData() async {
    if (!mounted) return;
    // Only set loading state if it's not already true
    if (!isLoading) {
      setState(() {
        isLoading = true;
      });
    }
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        // Load routines and habits in parallel for faster data loading
        final results = await Future.wait([
          queryRoutineRecordOnce(userId: userId),
          queryActivitiesRecordOnce(userId: userId),
        ]);
        if (!mounted) return;
        
        final routinesResult = results[0] as List<RoutineRecord>;
        final habitsResult = results[1] as List<ActivityRecord>;
        
        // Sort routines by order to ensure consistent display
        final sortedRoutines =
            RoutineOrderService.sortRoutinesByOrder(routinesResult);
        
        // Calculate hash code when data changes (not in getter)
        final newHash = sortedRoutines.length.hashCode ^
            sortedRoutines.fold(0, (sum, r) => sum ^ r.reference.id.hashCode);
        
        if (mounted) {
          setState(() {
            routines = sortedRoutines;
            habits = habitsResult;
            // Invalidate cache when data changes
            cachedFilteredRoutines = null;
            // Update hash code when data changes
            routinesHashCode = newHash;
            isLoading = false;
          });
        }
        // Initialize order values for routines that don't have them
        RoutineOrderService.initializeOrderValues(routines);
      } else {
        // Batch state updates for empty user case
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (e is FirebaseException) {}
      // Batch state updates for error case
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> deleteRoutine(RoutineRecord routine) async {
    final routineName = routine.name;
    final routineId = routine.reference.id;

    // OPTIMISTIC UPDATE: Remove from local list immediately
    setState(() {
      routines.removeWhere((r) => r.reference.id == routineId);
    });

    try {
      await RoutineService.deleteRoutine(routineId, userId: currentUserUid);
      // Background reconciliation: reload to ensure sync
      loadData();
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
        loadData();
      }
    }
  }

  void navigateToCreateRoutine() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => const CreateRoutinePage(),
      ),
    )
        .then((_) {
      // Reload the list after creating a routine
      loadData();
    });
  }

  void navigateToEditRoutine(RoutineRecord routine) {
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
              routines.indexWhere((r) => r.reference.id == routineId);
          if (routineIndex != -1) {
            final updatedRoutine = RoutineRecord.getDocumentFromData(
              {
                ...routines[routineIndex].snapshotData,
                'itemIds': itemIds,
                'itemOrder': itemOrder ?? itemIds,
                'itemNames': itemNames ?? [],
                'itemTypes': itemTypes ?? [],
                'lastUpdated': DateTime.now(),
              },
              routines[routineIndex].reference,
            );
            setState(() {
              routines[routineIndex] = updatedRoutine;
            });
          }
        }
      }
      // Reload the list to ensure everything is in sync
      loadData();
    });
  }

  void navigateToRoutineDetail(RoutineRecord routine) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RoutineDetailPage(
          routine: routine,
        ),
      ),
    );
  }

  List<String> getItemNames(List<String> itemIds) {
    return itemIds.map((id) {
      try {
        final activity = habits.firstWhere((h) => h.reference.id == id);
        return activity.name;
      } catch (e) {
        return 'Unknown Item';
      }
    }).toList();
  }

  Future<void> showRoutineOverflowMenu(
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
      navigateToEditRoutine(routine);
    } else if (selected == 'delete') {
      showDeleteConfirmation(routine);
    }
  }

  void showDeleteConfirmation(RoutineRecord routine) {
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
              deleteRoutine(routine);
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

  Future<void> selectDueTime(RoutineRecord routine) async {
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
        routines.indexWhere((r) => r.reference.id == routineId);
    if (routineIndex != -1) {
      final updatedRoutine = RoutineRecord.getDocumentFromData(
        {
          ...routines[routineIndex].snapshotData,
          'dueTime': newDueTime,
          'lastUpdated': DateTime.now(),
        },
        routines[routineIndex].reference,
      );
      setState(() {
        routines[routineIndex] = updatedRoutine;
      });
    }

    try {
      await RoutineService.updateRoutine(
        routineId: routineId,
        dueTime: newDueTime,
        userId: currentUserUid,
      );
      // Background reconciliation: reload to ensure sync
      loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating due time: $e'),
          backgroundColor: Colors.red,
        ),
      );
      // Background refresh to restore correct state
      loadData();
    }
  }

  Future<void> selectReminders(RoutineRecord routine) async {
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
        routines.indexWhere((r) => r.reference.id == routineId);
    if (routineIndex != -1) {
      final updatedData =
          Map<String, dynamic>.from(routines[routineIndex].snapshotData);
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
        routines[routineIndex].reference,
      );
      setState(() {
        routines[routineIndex] = updatedRoutine;
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
      loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating reminders: $e'),
          backgroundColor: Colors.red,
        ),
      );
      // Background refresh to restore correct state
      loadData();
    }
  }

  String getReminderChipLabel(RoutineRecord routine) {
    final reminders = ReminderConfigList.fromMapList(routine.reminders);
    if (!routine.remindersEnabled || reminders.isEmpty) {
      return 'Set reminders';
    }
    if (reminders.length == 1) {
      return reminders.first.getDescription();
    }
    return '${reminders.length} reminders';
  }

  /// Handle reordering of routines
  Future<void> handleReorder(int oldIndex, int newIndex) async {
    final reorderingIds = <String>{};
    try {
      // Allow dropping at the end (newIndex can equal sequences.length)
      if (oldIndex < 0 ||
          oldIndex >= routines.length ||
          newIndex < 0 ||
          newIndex > routines.length) return;

      // Create a copy of the routines list for reordering
      final reorderedRoutines = List<RoutineRecord>.from(routines);

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
      reorderingRoutineIds.addAll(reorderingIds);

      // Replace routines with the reordered list (this is the key fix!)
      if (mounted) {
        setState(() {
          routines = updatedRoutines;
        });
      }

      // Perform database update in background
      await RoutineOrderService.reorderRoutines(
        updatedRoutines,
        oldIndex,
        adjustedNewIndex,
      );

      // Clear reordering set after successful database update
      reorderingRoutineIds.removeAll(reorderingIds);
    } catch (e) {
      // Clear reordering set even on error
      reorderingRoutineIds.removeAll(reorderingIds);
      // Revert to correct state by refreshing data
      await loadData();
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
