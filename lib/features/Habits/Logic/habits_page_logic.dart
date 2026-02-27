import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/features/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/features/Shared/section_expansion_state_manager.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';
import 'package:habit_tracker/features/Habits/Logic/habits_event_handlers_helper.dart';
import 'package:habit_tracker/features/Habits/presentation/window_display_helper.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';
import 'dart:async';
import 'package:intl/intl.dart';

// FirestoreCacheService handles its own cache updates via NotificationCenter.
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_repository.dart';

mixin HabitsPageLogic<T extends StatefulWidget> on State<T> {
  List<ActivityInstanceRecord> habitInstances = [];
  List<CategoryRecord> categories = [];
  Set<String> expandedCategories = {};
  bool isLoading = true;
  bool didInitialDependencies = false;
  bool shouldReloadOnReturn = false;
  late bool showCompleted;
  bool hasAutoExpandedOnLoad = false;
  String searchQuery = '';
  final SearchStateManager searchManager = SearchStateManager();
  Map<String, List<ActivityInstanceRecord>>? cachedGroupedByCategory;
  int habitInstancesHashCode = 0; // Current hash of instances
  int lastCachedHabitInstancesHash = 0; // Hash used when cache was built
  String lastSearchQuery = '';
  bool lastShowCompleted = false;
  Set<String> reorderingInstanceIds =
      {}; // Track instances being reordered to prevent stale updates
  final Map<String, String> optimisticOperations =
      {}; // operationId -> instanceId

  int _calculateInstancesHash(List<ActivityInstanceRecord> instances) {
    return instances.length.hashCode ^
        instances.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
  }

  Future<void> loadExpansionState() async {
    final expandedSections =
        await ExpansionStateManager().getHabitsExpandedSections();
    if (mounted) {
      setState(() {
        expandedCategories = expandedSections;
      });
    }
  }

  void onSearchChanged(String query) {
    if (mounted) {
      if (searchQuery != query) {
        setState(() {
          searchQuery = query;
          cachedGroupedByCategory = null;
          if (query.isNotEmpty) {
            final grouped = getGroupedByCategory();
            for (final key in grouped.keys) {
              if (grouped[key]!.isNotEmpty) {
                expandedCategories.add(key);
              }
            }
          }
        });
      }
    }
  }

  Map<String, List<ActivityInstanceRecord>> getGroupedByCategory() {
    final cacheInvalid = cachedGroupedByCategory == null ||
        habitInstancesHashCode != lastCachedHabitInstancesHash ||
        searchQuery != lastSearchQuery ||
        showCompleted != lastShowCompleted;

    if (!cacheInvalid && cachedGroupedByCategory != null) {
      return cachedGroupedByCategory!;
    }
    final grouped = <String, List<ActivityInstanceRecord>>{};
    final instancesToProcess = habitInstances.where((instance) {
      if (searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(searchQuery.toLowerCase());
    }).toList();
    for (final instance in instancesToProcess) {
      if (!showCompleted && instance.status == 'completed') continue;
      final categoryName = instance.templateCategoryName.isNotEmpty
          ? instance.templateCategoryName
          : 'Uncategorized';
      (grouped[categoryName] ??= []).add(instance);
    }
    for (final key in grouped.keys) {
      final items = grouped[key]!;
      if (items.isNotEmpty) {
        grouped[key] =
            InstanceOrderService.sortInstancesByOrder(items, 'habits');
      }
    }
    cachedGroupedByCategory = grouped;
    lastCachedHabitInstancesHash = habitInstancesHashCode;
    lastSearchQuery = searchQuery;
    lastShowCompleted = showCompleted;

    return grouped;
  }

  String getDueDateSubtitle(ActivityInstanceRecord instance) {
    if (WindowDisplayHelper.hasCompletionWindow(instance)) {
      if (instance.status == 'completed' || instance.status == 'skipped') {
        return WindowDisplayHelper.getNextWindowStartSubtitle(instance);
      } else {
        return WindowDisplayHelper.getWindowEndSubtitle(instance);
      }
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    if (instance.dueDate == null) {
      if (instance.hasDueTime()) {
        return '@ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}';
      }
      return 'No due date';
    }
    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);
    String dateStr;
    if (dueDate.isAtSameMomentAs(today)) {
      dateStr = 'Today';
    } else if (dueDate.isAtSameMomentAs(tomorrow)) {
      dateStr = 'Tomorrow';
    } else {
      dateStr = DateFormat.MMMd().format(instance.dueDate!);
    }
    final timeStr = instance.hasDueTime()
        ? ' @ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}'
        : '';
    return '$dateStr$timeStr';
  }

  Future<void> loadHabits() async {
    if (!mounted) return;
    if (!isLoading && habitInstances.isEmpty) {
      setState(() => isLoading = true);
    }
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isNotEmpty) {
        final results = await Future.wait<dynamic>([
          TodayInstanceRepository.instance.ensureHydrated(userId: userId),
          queryHabitCategoriesOnce(
            userId: userId,
            callerTag: 'HabitsPage._loadHabits',
          ),
        ]);
        if (!mounted) return;

        final instances = TodayInstanceRepository.instance
            .selectHabitItemsLatestPerTemplate();
        final categoriesResult = results[1] as List<CategoryRecord>;
        try {
          await InstanceOrderService.initializeOrderValues(instances, 'habits');
        } catch (_) {}
        if (mounted) {
          final optimisticInstanceIds = optimisticOperations.values.toSet();
          final mergedInstances = instances.map((inst) {
            if (optimisticInstanceIds.contains(inst.reference.id)) {
              final localIndex = habitInstances.indexWhere(
                  (local) => local.reference.id == inst.reference.id);
              if (localIndex != -1) {
                final local = habitInstances[localIndex];
                if (local.status == 'completed' && inst.status != 'completed') {
                  return local;
                }
                if (optimisticOperations.containsValue(inst.reference.id)) {
                  return local;
                }
              }
            }
            return inst;
          }).toList();

          final newHash = mergedInstances.length.hashCode ^
              mergedInstances.fold(
                  0, (sum, inst) => sum ^ inst.reference.id.hashCode);

          setState(() {
            habitInstances = mergedInstances;
            categories = categoriesResult;
            cachedGroupedByCategory = null;
            habitInstancesHashCode = newHash;
            isLoading = false;
          });
          if (!hasAutoExpandedOnLoad && habitInstances.isNotEmpty) {
            hasAutoExpandedOnLoad = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && expandedCategories.isEmpty) {
                final grouped = getGroupedByCategory();
                if (grouped.isNotEmpty) {
                  setState(() {
                    expandedCategories.add(grouped.keys.first);
                  });
                  ExpansionStateManager()
                      .setHabitsExpandedSections(expandedCategories);
                }
              }
            });
          }
        }
      } else {
        if (mounted) {
          setState(() => isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void updateInstanceInLocalState(ActivityInstanceRecord updatedInstance) {
    final index = habitInstances.indexWhere(
        (inst) => inst.reference.id == updatedInstance.reference.id);
    if (index != -1) {
      habitInstances[index] = updatedInstance;
    }
    if (!showCompleted && updatedInstance.status == 'completed') {
      habitInstances.removeWhere(
          (inst) => inst.reference.id == updatedInstance.reference.id);
    }
    final newHash = habitInstances.length.hashCode ^
        habitInstances.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);

    setState(() {
      cachedGroupedByCategory = null;
      habitInstancesHashCode = newHash;
    });
  }

  void removeInstanceFromLocalState(ActivityInstanceRecord deletedInstance) {
    habitInstances.removeWhere(
        (inst) => inst.reference.id == deletedInstance.reference.id);
    final newHash = habitInstances.length.hashCode ^
        habitInstances.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
    setState(() {
      cachedGroupedByCategory = null;
      habitInstancesHashCode = newHash;
    });
  }

  Future<void> loadHabitsSilently() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isNotEmpty) {
        await TodayInstanceRepository.instance.refreshToday(userId: userId);
        final instances = TodayInstanceRepository.instance
            .selectHabitItemsLatestPerTemplate();

        if (mounted) {
          final newHash = _calculateInstancesHash(instances);
          setState(() {
            habitInstances = instances;
            cachedGroupedByCategory = null;
            habitInstancesHashCode = newHash;
          });
        }
      }
    } catch (e) {
      print('Error invalidating category cache: $e');
    }
  }

  void handleInstanceCreated(dynamic param) {
    List<ActivityInstanceRecord>? updatedInstances;
    Map<String, String>? updatedOperations;

    HabitsEventHandlersHelper.handleInstanceCreated(
      param: param,
      showCompleted: showCompleted,
      habitInstances: habitInstances,
      optimisticOperations: optimisticOperations,
      onHabitInstancesUpdate: (updated) {
        updatedInstances = updated;
      },
      onOptimisticOperationsUpdate: (updated) {
        updatedOperations = updated;
      },
    );

    if (updatedInstances == null || updatedOperations == null) {
      return;
    }

    setState(() {
      habitInstances = updatedInstances!;
      optimisticOperations
        ..clear()
        ..addAll(updatedOperations!);
      cachedGroupedByCategory = null;
      habitInstancesHashCode = _calculateInstancesHash(updatedInstances!);
    });
  }

  void handleInstanceUpdated(dynamic param) {
    List<ActivityInstanceRecord>? updatedInstances;
    Map<String, String>? updatedOperations;

    HabitsEventHandlersHelper.handleInstanceUpdated(
      param: param,
      showCompleted: showCompleted,
      habitInstances: habitInstances,
      reorderingInstanceIds: reorderingInstanceIds,
      optimisticOperations: optimisticOperations,
      onHabitInstancesUpdate: (updated) {
        updatedInstances = updated;
      },
      onOptimisticOperationsUpdate: (updated) {
        updatedOperations = updated;
      },
    );

    if (updatedInstances == null || updatedOperations == null) {
      return;
    }

    setState(() {
      habitInstances = updatedInstances!;
      optimisticOperations
        ..clear()
        ..addAll(updatedOperations!);
      cachedGroupedByCategory = null;
      habitInstancesHashCode = _calculateInstancesHash(updatedInstances!);
    });
  }

  void handleRollback(dynamic param) {
    List<ActivityInstanceRecord>? updatedInstances;
    Map<String, String>? updatedOperations;

    HabitsEventHandlersHelper.handleRollback(
      param: param,
      habitInstances: habitInstances,
      optimisticOperations: optimisticOperations,
      onHabitInstancesUpdate: (updated) {
        updatedInstances = updated;
      },
      onOptimisticOperationsUpdate: (updated) {
        updatedOperations = updated;
      },
      revertOptimisticUpdate: (instanceId) {
        revertOptimisticUpdate(instanceId);
      },
    );

    if (updatedOperations != null) {
      optimisticOperations
        ..clear()
        ..addAll(updatedOperations!);
    }
    if (updatedInstances != null) {
      setState(() {
        habitInstances = updatedInstances!;
        cachedGroupedByCategory = null;
        habitInstancesHashCode = _calculateInstancesHash(updatedInstances!);
      });
    }
  }

  Future<void> revertOptimisticUpdate(String instanceId) async {
    List<ActivityInstanceRecord>? updatedInstances;
    await HabitsEventHandlersHelper.revertOptimisticUpdate(
      instanceId: instanceId,
      habitInstances: habitInstances,
      onHabitInstancesUpdate: (updated) {
        updatedInstances = updated;
      },
    );

    if (updatedInstances != null && mounted) {
      setState(() {
        habitInstances = updatedInstances!;
        cachedGroupedByCategory = null;
        habitInstancesHashCode = _calculateInstancesHash(updatedInstances!);
      });
    }
  }

  void handleInstanceDeleted(dynamic param) {
    List<ActivityInstanceRecord>? updatedInstances;
    Map<String, String>? updatedOperations;

    HabitsEventHandlersHelper.handleInstanceDeleted(
      param: param,
      habitInstances: habitInstances,
      optimisticOperations: optimisticOperations,
      onHabitInstancesUpdate: (updated) {
        updatedInstances = updated;
      },
      onOptimisticOperationsUpdate: (updated) {
        updatedOperations = updated;
      },
    );

    if (updatedInstances == null || updatedOperations == null) {
      return;
    }

    setState(() {
      habitInstances = updatedInstances!;
      optimisticOperations
        ..clear()
        ..addAll(updatedOperations!);
      cachedGroupedByCategory = null;
      habitInstancesHashCode = _calculateInstancesHash(updatedInstances!);
    });
  }

  Future<void> handleReorder(
      int oldIndex, int newIndex, String categoryName) async {
    final reorderingIds = <String>{};
    try {
      final groupedHabits = getGroupedByCategory();
      final items = groupedHabits[categoryName]!;
      if (oldIndex < 0 ||
          oldIndex >= items.length ||
          newIndex < 0 ||
          newIndex > items.length) return;
      final reorderedItems = List<ActivityInstanceRecord>.from(items);
      int adjustedNewIndex = newIndex;
      if (oldIndex < newIndex) {
        adjustedNewIndex -= 1;
      }
      final movedItem = reorderedItems.removeAt(oldIndex);
      reorderedItems.insert(adjustedNewIndex, movedItem);
      for (int i = 0; i < reorderedItems.length; i++) {
        final instance = reorderedItems[i];
        final instanceId = instance.reference.id;
        reorderingIds.add(instanceId);
        final updatedData = Map<String, dynamic>.from(instance.snapshotData);
        updatedData['habitsOrder'] = i;
        final updatedInstance = ActivityInstanceRecord.getDocumentFromData(
          updatedData,
          instance.reference,
        );
        final habitIndex = habitInstances
            .indexWhere((inst) => inst.reference.id == instanceId);
        if (habitIndex != -1) {
          habitInstances[habitIndex] = updatedInstance;
        }
      }
      reorderingInstanceIds.addAll(reorderingIds);
      cachedGroupedByCategory = null;
      if (mounted) {
        setState(() {});
      }
      await InstanceOrderService.reorderInstancesInSection(
        reorderedItems,
        'habits',
        oldIndex,
        adjustedNewIndex,
      );
      reorderingInstanceIds.removeAll(reorderingIds);
    } catch (e) {
      reorderingInstanceIds.removeAll(reorderingIds);
      await loadHabits();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reordering items: $e')),
        );
      }
    }
  }
}
