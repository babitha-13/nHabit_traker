import 'dart:async';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/core/config/instance_repository_flags.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/features/Shared/section_expansion_state_manager.dart';
import 'package:habit_tracker/features/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/features/Shared/Search/search_fab.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';
import 'package:habit_tracker/features/activity%20editor/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/features/Task/Logic/task_quick_add_helper.dart';
import 'package:habit_tracker/features/Task/UI/task_sections_ui_helper.dart';
import 'package:habit_tracker/features/Task/Logic/task_bucketing_logic_helper.dart';
import 'package:habit_tracker/features/Task/Logic/task_event_handlers_helper.dart';
import 'package:habit_tracker/features/Task/Logic/task_reorder_helper.dart';
import 'package:habit_tracker/features/activity%20editor/Frequency_config/frequency_config_model.dart';
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_repository.dart';
import 'package:habit_tracker/services/diagnostics/instance_parity_logger.dart';

class TaskPage extends StatefulWidget {
  final String? categoryName;
  const TaskPage({super.key, this.categoryName});
  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final TextEditingController _quickAddController = TextEditingController();
  final TextEditingController _quickTargetNumberController =
      TextEditingController();
  final TextEditingController _quickHoursController = TextEditingController();
  final TextEditingController _quickMinutesController = TextEditingController();
  List<ActivityInstanceRecord> _taskInstances = [];
  List<CategoryRecord> _categories = [];
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  String sortMode = 'default';
  String? _selectedQuickCategoryId;
  String? _selectedQuickTrackingType = 'binary';
  DateTime? _selectedQuickDueDate;
  TimeOfDay? _selectedQuickDueTime;
  int? _quickTimeEstimateMinutes;
  int _quickTargetNumber = 1;
  Duration _quickTargetDuration = const Duration(hours: 1);
  final TextEditingController _quickUnitController = TextEditingController();
  bool quickIsRecurring = false;
  FrequencyConfig? _quickFrequencyConfig;
  List<ReminderConfig> _quickReminders = [];
  Set<String> _expandedSections = {};
  final Map<String, GlobalKey> _sectionKeys = {};
  final int _completionTimeFrame = 2; // 2 = 2 days, 7 = 7 days, 30 = 30 days
  // Search functionality
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();
  // Cache for bucketed items to avoid recalculation on every build
  Map<String, List<dynamic>>? _cachedBucketedItems;
  int _taskInstancesHashCode = 0; // Current hash of instances
  int _lastCachedTaskInstancesHash = 0; // Hash used when cache was built
  String _lastSearchQuery = '';
  int _lastCompletionTimeFrame = 2;
  String? _lastCategoryName;
  Set<String> _reorderingInstanceIds =
      {}; // Track instances being reordered to prevent stale updates
  // Optimistic operation tracking
  final Map<String, String> _optimisticOperations =
      {}; // operationId -> instanceId

  @override
  void initState() {
    super.initState();
    _quickTargetNumberController.text = _quickTargetNumber.toString();
    _quickHoursController.text = _quickTargetDuration.inHours.toString();
    _quickMinutesController.text =
        (_quickTargetDuration.inMinutes % 60).toString();
    // Load expansion state first; data load is driven by didChangeDependencies
    // to avoid duplicate initial fetches.
    _loadExpansionState();
    // Listen for search changes
    _searchManager.addListener(_onSearchChanged);
    // Register observers
    _registerObservers();
  }

  void _registerObservers() {
    // Listen for instance events
    NotificationCenter.addObserver(this, InstanceEvents.instanceCreated,
        (param) {
      if (mounted) {
        _handleInstanceCreated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceUpdated,
        (param) {
      if (mounted) {
        _handleInstanceUpdated(param);
      }
    });
    // Listen for rollback events
    NotificationCenter.addObserver(this, 'instanceUpdateRollback', (param) {
      if (mounted) {
        _handleRollback(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceDeleted,
        (param) {
      if (param is ActivityInstanceRecord && mounted) {
        _handleInstanceDeleted(param);
      }
    });
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        _loadDataSilently();
      }
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    // Clean up observers on hot reload to prevent accumulation
    NotificationCenter.removeObserver(this);
    // Force didChangeDependencies to run the reload path after hot reload
    _didInitialDependencies = false;
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    _searchManager.removeListener(_onSearchChanged);
    _quickAddController.dispose();
    _quickTargetNumberController.dispose();
    _quickHoursController.dispose();
    _quickMinutesController.dispose();
    _quickUnitController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialDependencies) {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent && !_isLoading) {
        // Only reload if category actually changed
        if (widget.categoryName != _lastCategoryName) {
          _loadData();
        }
      }
    } else {
      _didInitialDependencies = true;
      // Re-register observers after hot reload (they were removed in reassemble())
      _registerObservers();
      // After initial mount or hot reload, ensure data is loaded
      // Use addPostFrameCallback to avoid race with initState() on initial mount
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadData();
        }
      });
    }
  }

  Future<void> _loadExpansionState() async {
    final expandedSections =
        await ExpansionStateManager().getTaskExpandedSections();
    if (mounted) {
      setState(() {
        _expandedSections = expandedSections;
      });
    }
  }

  void _onSearchChanged(String query) {
    if (mounted) {
      // Only update if value actually changed
      if (_searchQuery != query) {
        setState(() {
          _searchQuery = query;
          // Invalidate cache when search query changes
          _cachedBucketedItems = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final returnedWidget = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  cacheExtent:
                      500.0, // Cache 500px worth of items above/below viewport for better scroll performance
                  slivers: [
                    ..._buildSections(),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  heroTag: 'fab_add_task',
                  onPressed: _showQuickAddBottomSheet,
                  backgroundColor: theme.primary,
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ),
              const SearchFAB(heroTag: 'search_fab_tasks'),
            ],
          );
    return returnedWidget;
  }

  Future<void> _loadData() async {
    if (!mounted) {
      return;
    }
    // Only set loading state if it's not already true
    if (!_isLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final uid = await waitForCurrentUserUid();
      if (uid.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }
      final useRepo = InstanceRepositoryFlags.useRepoTasks;
      if (!useRepo) {
        InstanceRepositoryFlags.onLegacyPathUsed('TaskPage._loadData');
      }
      final results = await Future.wait<dynamic>([
        if (useRepo)
          TodayInstanceRepository.instance.ensureHydratedForTasks(userId: uid)
        else
          queryAllTaskInstances(userId: uid),
        queryTaskCategoriesOnce(
          userId: uid,
          callerTag: 'TaskPage._loadData.${widget.categoryName ?? 'all'}',
        ),
        if (useRepo && InstanceRepositoryFlags.enableParityChecks)
          queryAllTaskInstances(userId: uid),
      ]).timeout(const Duration(seconds: 15), onTimeout: () {
        throw TimeoutException('Data loading timed out');
      });
      if (!mounted) {
        return;
      }

      final instances = useRepo
          ? TodayInstanceRepository.instance.selectTaskItems()
          : results[0] as List<ActivityInstanceRecord>;
      final categories = results[1] as List<CategoryRecord>;

      if (useRepo && InstanceRepositoryFlags.enableParityChecks) {
        final legacy = results[2] as List<ActivityInstanceRecord>;
        InstanceParityLogger.logTaskParity(
          legacy: legacy,
          repo: instances,
        );
      }

      final categoryFiltered = instances.where((inst) {
        final matches = (widget.categoryName == null ||
            inst.templateCategoryName == widget.categoryName);
        return matches;
      }).toList();
      final sortedInstances =
          InstanceOrderService.sortInstancesByOrder(categoryFiltered, 'tasks');
      if (!mounted) return;

      if (mounted) {
        // Calculate hash code when data changes (not in getter)
        final newHash = _calculateInstancesHash(sortedInstances);

        setState(() {
          _categories = categories;
          // Store all instances
          _taskInstances = sortedInstances;
          // Invalidate cache when instances change
          _cachedBucketedItems = null;
          // Update hash code when data changes
          _taskInstancesHashCode = newHash;
          if (_selectedQuickCategoryId == null && categories.isNotEmpty) {
            final currentCategory = _resolveQuickAddCategory(categories);
            _selectedQuickCategoryId = currentCategory.reference.id;
          }
          _isLoading = false;
        });
      }
      // Initialize missing order values during load (avoid DB writes during build/getters).
      // Best-effort: don't crash UI if something was deleted concurrently.
      try {
        await InstanceOrderService.initializeOrderValues(
            sortedInstances, 'tasks');
      } catch (_) {}
    } catch (e, stackTrace) {
      print('🔴 TaskPage._loadData: ERROR - $e');
      print('🔴 TaskPage._loadData: StackTrace: $stackTrace');
      // Batch state updates for error case
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: $e')),
        );
      }
    }
  }

  CategoryRecord _resolveQuickAddCategory(List<CategoryRecord> categories) {
    if (widget.categoryName == null) {
      // All tab should create tasks in Inbox by default
      return categories.firstWhere(
        (c) => c.name.toLowerCase() == 'inbox',
        orElse: () => categories.first,
      );
    }
    return categories.firstWhere(
      (c) => c.name.toLowerCase() == widget.categoryName!.toLowerCase(),
      orElse: () => categories.first,
    );
  }

  List<Widget> _buildSections() {
    return TaskSectionsUIHelper.buildSections(
      context: context,
      bucketedItems: _bucketedItems,
      expandedSections: _expandedSections,
      sectionKeys: _sectionKeys,
      completionTimeFrame: _completionTimeFrame,
      categoryName: widget.categoryName,
      categories: _categories,
      onSectionToggle: (key) {
        setState(() {
          if (_expandedSections.contains(key)) {
            _expandedSections.remove(key);
          } else {
            _expandedSections.add(key);
          }
        });
        ExpansionStateManager().setTaskExpandedSections(_expandedSections);
        if (_expandedSections.contains(key) && _sectionKeys.containsKey(key)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_sectionKeys[key]!.currentContext != null) {
              Scrollable.ensureVisible(
                _sectionKeys[key]!.currentContext!,
                duration: Duration.zero,
                alignment: 0.0,
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              );
            }
          });
        }
      },
      buildItemTile: (item, key) => _buildItemTile(item, key),
      applySort: (items) => _applySort(items),
      getCategoryColor: (instance) => _getCategoryColor(instance),
      getSubtitle: (instance, bucketKey) => _getSubtitle(instance, bucketKey),
      loadData: _loadData,
      updateInstanceInLocalState: _updateInstanceInLocalState,
      removeInstanceFromLocalState: _removeInstanceFromLocalState,
      handleReorder: _handleReorder,
    );
  }

  String _getSubtitle(ActivityInstanceRecord instance, String bucketKey) {
    return TaskSectionsUIHelper.getSubtitle(
      instance: instance,
      bucketKey: bucketKey,
    );
  }

  void _showQuickAddBottomSheet() {
    TaskQuickAddHelper.showQuickAddBottomSheet(
      context,
      (fn) => setState(fn),
      setState,
      _quickAddController,
      () => _selectedQuickTrackingType,
      () => _selectedQuickDueDate,
      () => _selectedQuickDueTime,
      () => _quickTimeEstimateMinutes,
      () => quickIsRecurring,
      () => _quickFrequencyConfig,
      () => _quickReminders,
      () => _quickTargetNumber,
      () => _quickTargetDuration,
      _quickTargetNumberController,
      _quickHoursController,
      _quickMinutesController,
      _quickUnitController,
      (value) {
        _selectedQuickTrackingType = value;
        if (value == 'binary') {
          _quickTargetNumber = 1;
          _quickTargetDuration = const Duration(hours: 1);
          _quickUnitController.clear();
        }
      },
      (value) {
        _selectedQuickDueDate = value;
        if (quickIsRecurring &&
            _quickFrequencyConfig != null &&
            value != null) {
          _quickFrequencyConfig =
              _quickFrequencyConfig!.copyWith(startDate: value);
        }
        if (value == null && !quickIsRecurring) {
          _quickReminders = [];
        }
      },
      (value) => _selectedQuickDueTime = value,
      (value) => _quickTimeEstimateMinutes = value,
      (isRecurring, config) {
        quickIsRecurring = isRecurring;
        _quickFrequencyConfig = config;
        if (config != null) {
          _selectedQuickDueDate = config.startDate;
        }
      },
      (reminders) {
        _quickReminders = reminders;
        if (reminders.isNotEmpty &&
            !quickIsRecurring &&
            _selectedQuickDueDate == null) {
          _selectedQuickDueDate = DateTime.now();
        }
      },
      _submitQuickAdd,
    );
  }

  Future<void> _submitQuickAdd() async {
    await TaskQuickAddHelper.submitQuickAdd(
      context,
      _quickAddController.text.trim(),
      _selectedQuickCategoryId,
      _categories,
      _selectedQuickTrackingType,
      _quickTargetNumber,
      _quickTargetDuration,
      _quickTimeEstimateMinutes,
      quickIsRecurring,
      _quickFrequencyConfig,
      _selectedQuickDueDate,
      _selectedQuickDueTime,
      _quickUnitController,
      _quickReminders,
      _resetQuickAdd,
    );
  }

  void _resetQuickAdd() {
    TaskQuickAddHelper.resetQuickAdd(
      setState: setState,
      quickAddController: _quickAddController,
      onTrackingTypeChanged: (value) =>
          setState(() => _selectedQuickTrackingType = value),
      onDueDateChanged: (value) =>
          setState(() => _selectedQuickDueDate = value),
      onDueTimeChanged: (value) =>
          setState(() => _selectedQuickDueTime = value),
      onTimeEstimateChanged: (value) =>
          setState(() => _quickTimeEstimateMinutes = value),
      onRecurringChanged: (isRecurring, config) => setState(() {
        quickIsRecurring = isRecurring;
        _quickFrequencyConfig = config;
      }),
      onRemindersChanged: (reminders) =>
          setState(() => _quickReminders = reminders),
      quickTargetNumberController: _quickTargetNumberController,
      quickHoursController: _quickHoursController,
      quickMinutesController: _quickMinutesController,
      quickUnitController: _quickUnitController,
      onTargetNumberChanged: (value) =>
          setState(() => _quickTargetNumber = value),
      onTargetDurationChanged: (value) =>
          setState(() => _quickTargetDuration = value),
    );
  }

  /// Calculate hash code for instances including status and other relevant fields
  /// This ensures cache is invalidated when instance data changes, not just when IDs change
  int _calculateInstancesHash(List<ActivityInstanceRecord> instances) {
    return instances.length.hashCode ^
        instances.fold(
            0,
            (sum, inst) =>
                sum ^
                inst.reference.id.hashCode ^
                inst.status.hashCode ^
                (inst.completedAt?.millisecondsSinceEpoch ?? 0).hashCode ^
                (inst.dueDate?.millisecondsSinceEpoch ?? 0).hashCode ^
                (inst.currentValue?.hashCode ?? 0) ^
                inst.accumulatedTime.hashCode);
  }

  /// Invalidate cache efficiently without unnecessary setState calls
  /// Only invalidates if cache actually exists
  void _invalidateCache() {
    if (_cachedBucketedItems != null) {
      _cachedBucketedItems = null;
      // No need for setState here - cache will be recalculated on next access
      // setState will be called when instances are actually updated
    }
  }

  /// Update optimistic operations only if map actually changed
  /// This prevents unnecessary setState calls and rebuilds
  void _updateOptimisticOperations(Map<String, String> updated) {
    // Check if map actually changed by comparing keys and values
    if (_optimisticOperations.length != updated.length) {
      setState(() {
        _optimisticOperations.clear();
        _optimisticOperations.addAll(updated);
      });
      return;
    }

    // Check if any keys or values differ
    bool hasChanges = false;
    for (final entry in updated.entries) {
      if (_optimisticOperations[entry.key] != entry.value) {
        hasChanges = true;
        break;
      }
    }

    // Also check for removed keys
    if (!hasChanges) {
      for (final key in _optimisticOperations.keys) {
        if (!updated.containsKey(key)) {
          hasChanges = true;
          break;
        }
      }
    }

    // Only call setState if map actually changed
    if (hasChanges) {
      setState(() {
        _optimisticOperations.clear();
        _optimisticOperations.addAll(updated);
      });
    }
  }

  Map<String, List<dynamic>> get _bucketedItems {
    // Hash codes are now calculated when data changes, not in getter
    // This avoids expensive hash calculations on every build
    // Compare current hash code with cached one to detect data changes
    final cacheInvalid = _cachedBucketedItems == null ||
        _taskInstancesHashCode != _lastCachedTaskInstancesHash ||
        _searchQuery != _lastSearchQuery ||
        _completionTimeFrame != _lastCompletionTimeFrame ||
        widget.categoryName != _lastCategoryName;

    if (!cacheInvalid && _cachedBucketedItems != null) {
      return _cachedBucketedItems!;
    }

    final result = TaskBucketingLogicHelper.getBucketedItems(
      taskInstances: _taskInstances,
      searchQuery: _searchQuery,
      completionTimeFrame: _completionTimeFrame,
      categoryName: widget.categoryName,
      cachedBucketedItems: null, // Always recalculate if cache invalid
      taskInstancesHashCode: _taskInstancesHashCode,
      lastSearchQuery: _lastSearchQuery,
      lastCompletionTimeFrame: _lastCompletionTimeFrame,
      lastCategoryName: _lastCategoryName,
      onExpandedSectionsUpdate: (newSections) {
        // Defer setState to after build completes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _expandedSections != newSections) {
            setState(() {
              _expandedSections = newSections;
            });
          }
        });
      },
      expandedSections: _expandedSections,
    );

    // Update cache state - hash codes are already updated when data changes
    _cachedBucketedItems = result;
    _lastCachedTaskInstancesHash = _taskInstancesHashCode;
    _lastSearchQuery = _searchQuery;
    _lastCompletionTimeFrame = _completionTimeFrame;
    _lastCategoryName = widget.categoryName;

    return result;
  }

  // Recent Completions UI is now handled via standard sections and ItemComponent
  // Removed legacy actions for custom Recent Completions UI
  Widget _buildItemTile(dynamic item, String bucketKey) {
    if (item is ActivityInstanceRecord) {
      return TaskSectionsUIHelper.buildItemTile(
        item: item,
        bucketKey: bucketKey,
        instance: item,
        categories: _categories,
        categoryName: widget.categoryName,
        getCategoryColor: (instance) => _getCategoryColor(instance),
        getSubtitle: (instance, bucketKey) => _getSubtitle(instance, bucketKey),
        loadData: _loadData,
        updateInstanceInLocalState: _updateInstanceInLocalState,
        removeInstanceFromLocalState: _removeInstanceFromLocalState,
      );
    }
    return const SizedBox.shrink();
  }

  String _getCategoryColor(ActivityInstanceRecord instance) {
    return TaskSectionsUIHelper.getCategoryColor(
      instance: instance,
      categories: _categories,
    );
  }

  void _updateInstanceInLocalState(ActivityInstanceRecord updatedInstance) {
    TaskEventHandlersHelper.updateInstanceInLocalState(
      updatedInstance: updatedInstance,
      taskInstances: _taskInstances,
      onTaskInstancesUpdate: (updated) {
        // Recalculate hash code when instances change
        final newHash = _calculateInstancesHash(updated);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onCacheInvalidate: _invalidateCache,
      loadDataSilently: _loadDataSilently,
    );
  }

  void _removeInstanceFromLocalState(ActivityInstanceRecord deletedInstance) {
    TaskEventHandlersHelper.removeInstanceFromLocalState(
      deletedInstance: deletedInstance,
      taskInstances: _taskInstances,
      onTaskInstancesUpdate: (updated) {
        // Recalculate hash code when instances change
        final newHash = _calculateInstancesHash(updated);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onCacheInvalidate: _invalidateCache,
    );
  }

  Future<void> _loadDataSilently() async {
    try {
      final uid = await waitForCurrentUserUid();
      if (uid.isEmpty) return;
      final useRepo = InstanceRepositoryFlags.useRepoTasks;
      if (!useRepo) {
        InstanceRepositoryFlags.onLegacyPathUsed('TaskPage._loadDataSilently');
      }
      final results = await Future.wait<dynamic>([
        if (useRepo)
          TodayInstanceRepository.instance.refreshTodayForTasks(userId: uid)
        else
          queryAllTaskInstances(userId: uid),
        queryTaskCategoriesOnce(
          userId: uid,
          callerTag: 'TaskPage._loadData.${widget.categoryName ?? 'all'}',
        ),
        if (useRepo && InstanceRepositoryFlags.enableParityChecks)
          queryAllTaskInstances(userId: uid),
      ]);
      final instances = useRepo
          ? TodayInstanceRepository.instance.selectTaskItems()
          : results[0] as List<ActivityInstanceRecord>;
      final categories = results[1] as List<CategoryRecord>;

      if (useRepo && InstanceRepositoryFlags.enableParityChecks) {
        final legacy = results[2] as List<ActivityInstanceRecord>;
        InstanceParityLogger.logTaskParity(
          legacy: legacy,
          repo: instances,
        );
      }
      final categoryFiltered = instances.where((inst) {
        final matches = (widget.categoryName == null ||
            inst.templateCategoryName == widget.categoryName);
        return matches;
      }).toList();
      final sortedInstances =
          InstanceOrderService.sortInstancesByOrder(categoryFiltered, 'tasks');
      if (mounted) {
        // Calculate hash code when data changes
        final newHash = _calculateInstancesHash(sortedInstances);
        setState(() {
          _categories = categories;
          _taskInstances = sortedInstances;
          // Invalidate cache when instances change
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      }
      // Best-effort initialize missing order values (safe, caught).
      try {
        await InstanceOrderService.initializeOrderValues(
            sortedInstances, 'tasks');
      } catch (_) {}
    } catch (e) {
      // Silent error handling - don't disrupt UI
    }
  }

  void _applySort(List<dynamic> items) {
    TaskSectionsUIHelper.applySort(
      items: items,
      sortMode: sortMode,
    );
  }

  // Event handlers for live updates
  void _handleInstanceCreated(dynamic param) {
    TaskEventHandlersHelper.handleInstanceCreated(
      param: param,
      categoryName: widget.categoryName,
      taskInstances: _taskInstances,
      optimisticOperations: _optimisticOperations,
      onTaskInstancesUpdate: (updated) {
        // Recalculate hash code when instances change
        final newHash = _calculateInstancesHash(updated);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onOptimisticOperationsUpdate: _updateOptimisticOperations,
      onCacheInvalidate: _invalidateCache,
    );
  }

  void _handleInstanceUpdated(dynamic param) {
    TaskEventHandlersHelper.handleInstanceUpdated(
      param: param,
      categoryName: widget.categoryName,
      taskInstances: _taskInstances,
      reorderingInstanceIds: _reorderingInstanceIds,
      optimisticOperations: _optimisticOperations,
      onTaskInstancesUpdate: (updated) {
        // Recalculate hash code when instances change
        final newHash = _calculateInstancesHash(updated);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onOptimisticOperationsUpdate: _updateOptimisticOperations,
      onCacheInvalidate: _invalidateCache,
    );
  }

  void _handleRollback(dynamic param) {
    TaskEventHandlersHelper.handleRollback(
      param: param,
      taskInstances: _taskInstances,
      optimisticOperations: _optimisticOperations,
      onTaskInstancesUpdate: (updated) {
        // Recalculate hash code when instances change
        final newHash = _calculateInstancesHash(updated);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onOptimisticOperationsUpdate: _updateOptimisticOperations,
      onCacheInvalidate: _invalidateCache,
      revertOptimisticUpdate: (instanceId) {
        TaskEventHandlersHelper.revertOptimisticUpdate(
          instanceId: instanceId,
          taskInstances: _taskInstances,
          onTaskInstancesUpdate: (updated) {
            setState(() {
              _taskInstances = updated;
              _cachedBucketedItems = null;
            });
          },
          onCacheInvalidate: _invalidateCache,
        );
      },
    );
  }

  void _handleInstanceDeleted(ActivityInstanceRecord instance) {
    TaskEventHandlersHelper.handleInstanceDeleted(
      instance: instance,
      categoryName: widget.categoryName,
      taskInstances: _taskInstances,
      onTaskInstancesUpdate: (updated) {
        // Recalculate hash code when instances change
        final newHash = _calculateInstancesHash(updated);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onCacheInvalidate: _invalidateCache,
    );
  }

  /// Handle reordering of items within a section
  Future<void> _handleReorder(
      int oldIndex, int newIndex, String sectionKey) async {
    await TaskReorderHelper.handleReorder(
      oldIndex: oldIndex,
      newIndex: newIndex,
      sectionKey: sectionKey,
      bucketedItems: _bucketedItems,
      taskInstances: _taskInstances,
      reorderingInstanceIds: _reorderingInstanceIds,
      onTaskInstancesUpdate: (updated) {
        // Recalculate hash code when instances change
        final newHash = _calculateInstancesHash(updated);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onReorderingInstanceIdsUpdate: (updated) {
        setState(() {
          _reorderingInstanceIds = updated;
        });
      },
      onCacheInvalidate: _invalidateCache,
      loadData: _loadData,
      context: context,
    );
  }
}
