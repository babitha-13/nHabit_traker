import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Frequency_config/frequency_config_dialog.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Screens/Shared/section_expansion_state_manager.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_fab.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/instance_order_service.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/Screens/Task/Logic/task_quick_add_helper.dart';
import 'package:habit_tracker/Screens/Task/UI/task_sections_ui_helper.dart';
import 'package:habit_tracker/Screens/Task/Logic/task_bucketing_logic_helper.dart';
import 'package:habit_tracker/Screens/Task/Logic/task_event_handlers_helper.dart';
import 'package:habit_tracker/Screens/Task/Logic/task_reorder_helper.dart';

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
    // Load expansion state and data in parallel for faster initialization
    Future.wait([
      _loadExpansionState(),
      _loadData(),
    ]);
    // Listen for search changes
    _searchManager.addListener(_onSearchChanged);
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
      if (route != null && route.isCurrent) {
        _loadData();
      }
    } else {
      _didInitialDependencies = true;
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
                  cacheExtent: 500.0, // Cache 500px worth of items above/below viewport for better scroll performance
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
    if (!mounted) return;
    // Only set loading state if it's not already true
    if (!_isLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }
      // Load instances and categories in parallel for faster data loading
      final results = await Future.wait([
        queryAllTaskInstances(userId: uid),
        queryTaskCategoriesOnce(
          userId: uid,
          callerTag: 'TaskPage._loadData.${widget.categoryName ?? 'all'}',
        ),
      ]);
      if (!mounted) return;
      
      final instances = results[0] as List<ActivityInstanceRecord>;
      final categories = results[1] as List<CategoryRecord>;
      
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
        final newHash = sortedInstances.length.hashCode ^
            sortedInstances.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
        
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
    } catch (e) {
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
      _selectedQuickTrackingType,
      _selectedQuickDueDate,
      _selectedQuickDueTime,
      _quickTimeEstimateMinutes,
      quickIsRecurring,
      _quickFrequencyConfig,
      _quickReminders,
      _quickTargetNumber,
      _quickTargetDuration,
      _quickTargetNumberController,
      _quickHoursController,
      _quickMinutesController,
      _quickUnitController,
      (value) => setState(() {
        _selectedQuickTrackingType = value;
        if (value == 'binary') {
          _quickTargetNumber = 1;
          _quickTargetDuration = const Duration(hours: 1);
          _quickUnitController.clear();
        }
      }),
      (value) => setState(() {
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
      }),
      (value) => setState(() => _selectedQuickDueTime = value),
      (value) => setState(() => _quickTimeEstimateMinutes = value),
      (isRecurring, config) => setState(() {
        quickIsRecurring = isRecurring;
        _quickFrequencyConfig = config;
        if (config != null) {
          _selectedQuickDueDate = config.startDate;
        }
      }),
      (reminders) => setState(() {
        _quickReminders = reminders;
        if (reminders.isNotEmpty &&
            !quickIsRecurring &&
            _selectedQuickDueDate == null) {
          _selectedQuickDueDate = DateTime.now();
        }
      }),
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
        setState(() {
          _expandedSections = newSections;
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
        final newHash = updated.length.hashCode ^
            updated.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onCacheInvalidate: () {
        // Only invalidate if cache exists
        if (_cachedBucketedItems != null) {
          setState(() {
            _cachedBucketedItems = null;
          });
        }
      },
      loadDataSilently: _loadDataSilently,
    );
  }

  void _removeInstanceFromLocalState(ActivityInstanceRecord deletedInstance) {
    TaskEventHandlersHelper.removeInstanceFromLocalState(
      deletedInstance: deletedInstance,
      taskInstances: _taskInstances,
      onTaskInstancesUpdate: (updated) {
        // Recalculate hash code when instances change
        final newHash = updated.length.hashCode ^
            updated.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onCacheInvalidate: () {
        // Only invalidate if cache exists
        if (_cachedBucketedItems != null) {
          setState(() {
            _cachedBucketedItems = null;
          });
        }
      },
    );
  }

  Future<void> _loadDataSilently() async {
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) return;
      final instances = await queryAllTaskInstances(userId: uid);
      final categories = await queryTaskCategoriesOnce(
        userId: uid,
        callerTag: 'TaskPage._loadData.${widget.categoryName ?? 'all'}',
      );
      final categoryFiltered = instances.where((inst) {
        final matches = (widget.categoryName == null ||
            inst.templateCategoryName == widget.categoryName);
        return matches;
      }).toList();
      final sortedInstances =
          InstanceOrderService.sortInstancesByOrder(categoryFiltered, 'tasks');
      if (mounted) {
        // Calculate hash code when data changes
        final newHash = sortedInstances.length.hashCode ^
            sortedInstances.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
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
        final newHash = updated.length.hashCode ^
            updated.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onOptimisticOperationsUpdate: (updated) {
        setState(() {
          _optimisticOperations.clear();
          _optimisticOperations.addAll(updated);
        });
      },
      onCacheInvalidate: () {
        // Only invalidate if cache exists
        if (_cachedBucketedItems != null) {
          setState(() {
            _cachedBucketedItems = null;
          });
        }
      },
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
        final newHash = updated.length.hashCode ^
            updated.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onOptimisticOperationsUpdate: (updated) {
        setState(() {
          _optimisticOperations.clear();
          _optimisticOperations.addAll(updated);
        });
      },
      onCacheInvalidate: () {
        // Only invalidate if cache exists
        if (_cachedBucketedItems != null) {
          setState(() {
            _cachedBucketedItems = null;
          });
        }
      },
    );
  }

  void _handleRollback(dynamic param) {
    TaskEventHandlersHelper.handleRollback(
      param: param,
      taskInstances: _taskInstances,
      optimisticOperations: _optimisticOperations,
      onTaskInstancesUpdate: (updated) {
        // Recalculate hash code when instances change
        final newHash = updated.length.hashCode ^
            updated.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onOptimisticOperationsUpdate: (updated) {
        setState(() {
          _optimisticOperations.clear();
          _optimisticOperations.addAll(updated);
        });
      },
      onCacheInvalidate: () {
        // Only invalidate if cache exists
        if (_cachedBucketedItems != null) {
          setState(() {
            _cachedBucketedItems = null;
          });
        }
      },
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
          onCacheInvalidate: () {
            setState(() {
              _cachedBucketedItems = null;
            });
          },
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
        final newHash = updated.length.hashCode ^
            updated.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
        setState(() {
          _taskInstances = updated;
          _cachedBucketedItems = null;
          _taskInstancesHashCode = newHash;
        });
      },
      onCacheInvalidate: () {
        // Only invalidate if cache exists
        if (_cachedBucketedItems != null) {
          setState(() {
            _cachedBucketedItems = null;
          });
        }
      },
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
        final newHash = updated.length.hashCode ^
            updated.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
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
      onCacheInvalidate: () {
        // Only invalidate if cache exists
        if (_cachedBucketedItems != null) {
          setState(() {
            _cachedBucketedItems = null;
          });
        }
      },
      loadData: _loadData,
      context: context,
    );
  }
}
