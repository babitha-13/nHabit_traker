import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/floating_timer.dart';
import 'package:habit_tracker/Helper/utils/task_type_dropdown_helper.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_dialog.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/expansion_state_manager.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Helper/utils/search_fab.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Helper/utils/reminder_config.dart';
import 'package:habit_tracker/Helper/utils/reminder_config_dialog.dart';
import 'package:habit_tracker/Helper/backend/time_logging_preferences_service.dart';
import 'package:intl/intl.dart';

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
  int _completionTimeFrame = 2; // 2 = 2 days, 7 = 7 days, 30 = 30 days
  // Search functionality
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();
  // Cache for bucketed items to avoid recalculation on every build
  Map<String, List<dynamic>>? _cachedBucketedItems;
  int _taskInstancesHashCode = 0;
  String _lastSearchQuery = '';
  int _lastCompletionTimeFrame = 2;
  String? _lastCategoryName;
  Set<String> _reorderingInstanceIds =
      {}; // Track instances being reordered to prevent stale updates
  // Optimistic operation tracking
  final Map<String, String> _optimisticOperations = {}; // operationId -> instanceId

  // Time estimate preferences (feature gating for quick add UI)
  bool _enableDefaultEstimates = false;
  bool _enableActivityEstimates = false;

  @override
  void initState() {
    super.initState();
    _quickTargetNumberController.text = _quickTargetNumber.toString();
    _quickHoursController.text = _quickTargetDuration.inHours.toString();
    _quickMinutesController.text =
        (_quickTargetDuration.inMinutes % 60).toString();
    _loadExpansionState();
    _loadData();
    _loadTimeEstimatePreferences();
    // Listen for search changes
    _searchManager.addListener(_onSearchChanged);
    // Listen for instance events
    NotificationCenter.addObserver(this, InstanceEvents.instanceCreated,
        (param) {
      if (param is ActivityInstanceRecord && mounted) {
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
      setState(() {
        _searchQuery = query;
        // Invalidate cache when search query changes
        _cachedBucketedItems = null;
      });
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
                  slivers: [
                    ..._buildSections(),
                  ],
                ),
              ),
              FloatingTimer(
                activeInstances: _activeFloatingInstances,
                onRefresh: _loadData,
                onInstanceUpdated: _updateInstanceInLocalState,
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
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

  List<ActivityInstanceRecord> get _activeFloatingInstances {
    return _taskInstances.where((inst) {
      return inst.templateShowInFloatingTimer == true &&
          inst.templateTrackingType == 'time' &&
          inst.isTimerActive &&
          inst.status != 'completed';
    }).toList();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }
      final instances = await queryAllTaskInstances(userId: uid);
      if (!mounted) return;
      final categoryFiltered = instances.where((inst) {
        final matches = (widget.categoryName == null ||
            inst.templateCategoryName == widget.categoryName);
        print(
            'Instance ${inst.templateName} matches filter: $matches (categoryName: ${inst.templateCategoryName} vs ${widget.categoryName})');
        return matches;
      }).toList();
      final categories = await queryTaskCategoriesOnce(
        userId: uid,
        callerTag: 'TaskPage._loadDataSilently.${widget.categoryName ?? 'all'}',
      );
      if (!mounted) return;
      // DEBUG: Print instance details
      // for (final inst in instances) {
      // }
      for (final cat in categories) {
        print('  - ${cat.name} (${cat.reference.id})');
      }
      if (mounted) {
        setState(() {
          _categories = categories;
          // Store all instances
          _taskInstances = categoryFiltered;
          // Invalidate cache when instances change
          _cachedBucketedItems = null;
          if (_selectedQuickCategoryId == null && categories.isNotEmpty) {
            // Set the quick-add category to the current tab's category
            final currentCategory = categories.firstWhere(
              (c) => c.name == widget.categoryName,
              orElse: () => categories.first,
            );
            _selectedQuickCategoryId = currentCategory.reference.id;
            print(
                'TaskPage: Set quick-add category to: ${currentCategory.name} (${currentCategory.reference.id})');
          }
          _isLoading = false;
        });
      }
      // Initialize missing order values during load (avoid DB writes during build/getters).
      // Best-effort: don't crash UI if something was deleted concurrently.
      try {
        await InstanceOrderService.initializeOrderValues(categoryFiltered, 'tasks');
      } catch (_) {}
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: $e')),
        );
      }
    }
  }

  Widget _buildQuickAddWithState(StateSetter setModalState) {
    // Helper to update both modal and parent state
    void updateState(VoidCallback fn) {
      setState(fn);
      setModalState(() {}); // Trigger modal rebuild
    }

    return _buildQuickAdd(updateState);
  }

  Widget _buildQuickAdd([void Function(VoidCallback)? updateStateFn]) {
    final theme = FlutterFlowTheme.of(context);
    // Use provided updater or default to setState
    final updateState = updateStateFn ?? ((VoidCallback fn) => setState(fn));
    final quickAddWidget = Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        gradient: theme.neumorphicGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
        boxShadow: theme.neumorphicShadowsRaised,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.tertiary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.surfaceBorderColor,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      key: ValueKey(_quickAddController.hashCode),
                      controller: _quickAddController,
                      style: theme.bodyMedium,
                      maxLength: 200,
                      decoration: InputDecoration(
                        hintText: 'Quick add task…',
                        hintStyle: TextStyle(
                          color: theme.secondaryText,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                      ),
                      onSubmitted: (_) => _submitQuickAdd(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: theme.primaryButtonGradient,
                    borderRadius: BorderRadius.circular(theme.buttonRadius),
                    boxShadow: [
                      BoxShadow(
                        color: theme.primary.withOpacity(0.3),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(theme.buttonRadius),
                      onTap: _submitQuickAdd,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...[
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    theme.surfaceBorderColor,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconTaskTypeDropdown(
                        selectedValue: _selectedQuickTrackingType ?? 'binary',
                        onChanged: (value) {
                          updateState(() {
                            _selectedQuickTrackingType = value;
                            if (value == 'binary') {
                              _quickTargetNumber = 1;
                              _quickTargetDuration = const Duration(hours: 1);
                              _quickUnitController.clear();
                            }
                          });
                        },
                        tooltip: 'Select task type',
                      ),
                      // Date icon or chip
                      if (_selectedQuickDueDate == null)
                        Container(
                          decoration: BoxDecoration(
                            color: theme.tertiary,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _selectQuickDueDate(updateState),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.calendar_today_outlined,
                                  color: theme.secondary,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: theme.accent1.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.accent1, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: theme.accent1.withOpacity(0.2),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _selectQuickDueDate(updateState),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.calendar_today,
                                        size: 14, color: theme.accent1),
                                    const SizedBox(width: 6),
                                    Text(
                                      quickIsRecurring
                                          ? 'From ${DateFormat('MMM dd').format(_selectedQuickDueDate!)}'
                                          : DateFormat('MMM dd')
                                              .format(_selectedQuickDueDate!),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.accent1,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () {
                                        // Clear due date without opening picker
                                        updateState(() {
                                          _selectedQuickDueDate = null;
                                          // Auto-remove reminders if due date is cleared
                                          if (!quickIsRecurring) {
                                            _quickReminders = [];
                                          }
                                        });
                                      },
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: theme.accent1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Time icon or chip
                      if (_selectedQuickDueTime == null)
                        Container(
                          decoration: BoxDecoration(
                            color: theme.tertiary,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _selectQuickDueTime(updateState),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.access_time_outlined,
                                  color: theme.secondary,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: theme.accent1.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.accent1, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: theme.accent1.withOpacity(0.2),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _selectQuickDueTime(updateState),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.access_time,
                                        size: 14, color: theme.accent1),
                                    const SizedBox(width: 6),
                                    Text(
                                      TimeUtils.formatTimeOfDayForDisplay(
                                          _selectedQuickDueTime!),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.accent1,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () {
                                        // Clear due time without opening picker
                                        updateState(() {
                                          _selectedQuickDueTime = null;
                                        });
                                      },
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: theme.accent1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Time estimate icon/chip (only when both toggles are ON and not time-target)
                      if (_enableDefaultEstimates &&
                          _enableActivityEstimates &&
                          !_isQuickTimeTarget())
                        if (_quickTimeEstimateMinutes == null)
                          Container(
                            decoration: BoxDecoration(
                              color: theme.tertiary,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: theme.surfaceBorderColor,
                                width: 1,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () =>
                                    _selectQuickTimeEstimate(updateState),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.timelapse_outlined,
                                    color: theme.secondary,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: theme.accent1.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: theme.accent1, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.accent1.withOpacity(0.2),
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () =>
                                    _selectQuickTimeEstimate(updateState),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.timelapse,
                                          size: 14, color: theme.accent1),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${_quickTimeEstimateMinutes}m',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.accent1,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          updateState(() {
                                            _quickTimeEstimateMinutes = null;
                                          });
                                        },
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: theme.accent1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      // Reminder icon or chip
                      if (_quickReminders.isEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: theme.tertiary,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _selectQuickReminders(updateState),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.notifications_outlined,
                                  color: theme.secondary,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: theme.accent1.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.accent1, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: theme.accent1.withOpacity(0.2),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _selectQuickReminders(updateState),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.notifications,
                                        size: 14, color: theme.accent1),
                                    const SizedBox(width: 6),
                                    Text(
                                      _quickReminders.length == 1
                                          ? _quickReminders.first
                                              .getDescription()
                                          : '${_quickReminders.length} reminders',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.accent1,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () {
                                        // Clear reminders without opening dialog
                                        updateState(() {
                                          _quickReminders = [];
                                        });
                                      },
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: theme.accent1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Recurring icon or chip
                      if (!quickIsRecurring || _quickFrequencyConfig == null)
                        Container(
                          decoration: BoxDecoration(
                            color: theme.tertiary,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                // Opening recurring - show frequency config
                                final config = await showFrequencyConfigDialog(
                                  context: context,
                                  initialConfig: _quickFrequencyConfig ??
                                      FrequencyConfig(
                                        type: FrequencyType.everyXPeriod,
                                        startDate: _selectedQuickDueDate ??
                                            DateTime.now(),
                                      ),
                                );
                                if (config != null) {
                                  updateState(() {
                                    _quickFrequencyConfig = config;
                                    quickIsRecurring = true;
                                    // Sync start date to due date
                                    _selectedQuickDueDate = config.startDate;
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.repeat_outlined,
                                  color: theme.secondary,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: theme.accent1.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.accent1, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: theme.accent1.withOpacity(0.2),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                // Reopen frequency config dialog to edit
                                final config = await showFrequencyConfigDialog(
                                  context: context,
                                  initialConfig: _quickFrequencyConfig,
                                );
                                if (config != null) {
                                  updateState(() {
                                    _quickFrequencyConfig = config;
                                    // Sync start date to due date
                                    _selectedQuickDueDate = config.startDate;
                                  });
                                } else {
                                  // User cancelled - check if they want to disable recurring
                                  final shouldDisable = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Disable Recurring?'),
                                      content: const Text(
                                          'Do you want to disable recurring for this task?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Disable'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (shouldDisable == true) {
                                    updateState(() {
                                      quickIsRecurring = false;
                                      _quickFrequencyConfig = null;
                                    });
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.repeat,
                                        size: 14, color: theme.accent1),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _getQuickFrequencyDescription(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.accent1,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () {
                                        // Clear recurring without opening dialog
                                        updateState(() {
                                          quickIsRecurring = false;
                                          _quickFrequencyConfig = null;
                                        });
                                      },
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: theme.accent1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_selectedQuickTrackingType == 'quantitative') ...[
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.accent2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.surfaceBorderColor),
                        boxShadow: [
                          BoxShadow(
                            color: theme.primary.withOpacity(0.1),
                            offset: const Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.track_changes,
                              size: 16, color: theme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Target:',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _quickTargetNumberController,
                              style: theme.bodyMedium,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.accent1, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                isDense: true,
                                filled: true,
                                fillColor: theme.secondaryBackground,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                _quickTargetNumber = int.tryParse(value) ?? 1;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Unit:',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _quickUnitController,
                              style: theme.bodyMedium,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.accent1, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                hintText: 'e.g., pages, reps',
                                hintStyle:
                                    TextStyle(color: theme.secondaryText),
                                isDense: true,
                                filled: true,
                                fillColor: theme.secondaryBackground,
                              ),
                              onChanged: (value) {},
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_selectedQuickTrackingType == 'time') ...[
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.accent2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.surfaceBorderColor),
                        boxShadow: [
                          BoxShadow(
                            color: theme.primary.withOpacity(0.1),
                            offset: const Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer, size: 16, color: theme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Target Duration:',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _quickHoursController,
                              style: theme.bodyMedium,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.accent1, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                labelText: 'Hours',
                                labelStyle:
                                    TextStyle(color: theme.secondaryText),
                                isDense: true,
                                filled: true,
                                fillColor: theme.secondaryBackground,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final hours = int.tryParse(value) ?? 1;
                                _quickTargetDuration = Duration(
                                  hours: hours,
                                  minutes: _quickTargetDuration.inMinutes % 60,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _quickMinutesController,
                              style: theme.bodyMedium,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.accent1, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                labelText: 'Minutes',
                                labelStyle:
                                    TextStyle(color: theme.secondaryText),
                                isDense: true,
                                filled: true,
                                fillColor: theme.secondaryBackground,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final minutes = int.tryParse(value) ?? 0;
                                _quickTargetDuration = Duration(
                                  hours: _quickTargetDuration.inHours,
                                  minutes: minutes,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
    return quickAddWidget;
  }

  bool _isTaskCompleted(ActivityInstanceRecord instance) {
    return instance.status == 'completed';
  }

  String _getQuickFrequencyDescription() {
    if (_quickFrequencyConfig == null) return '';
    switch (_quickFrequencyConfig!.type) {
      case FrequencyType.specificDays:
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final selectedDayNames = _quickFrequencyConfig!.selectedDays
            .map((day) => days[day - 1])
            .join(', ');
        return 'Recurring on $selectedDayNames';
      case FrequencyType.timesPerPeriod:
        final String period;
        switch (_quickFrequencyConfig!.periodType) {
          case PeriodType.weeks:
            period = 'week';
            break;
          case PeriodType.months:
            period = 'month';
            break;
          case PeriodType.year:
            period = 'year';
            break;
          case PeriodType.days:
            period = 'days';
            break;
        }
        return 'Recurring ${_quickFrequencyConfig!.timesPerPeriod} times per $period';
      case FrequencyType.everyXPeriod:
        // Special case: every 1 day is the same as every day
        if (_quickFrequencyConfig!.everyXValue == 1 &&
            _quickFrequencyConfig!.everyXPeriodType == PeriodType.days) {
          return 'Recurring every day';
        }
        final String period;
        switch (_quickFrequencyConfig!.everyXPeriodType) {
          case PeriodType.days:
            period = 'days';
            break;
          case PeriodType.weeks:
            period = 'weeks';
            break;
          case PeriodType.months:
            period = 'months';
            break;
          case PeriodType.year:
            period = 'years';
            break;
        }
        return 'Recurring every ${_quickFrequencyConfig!.everyXValue} $period';
      default:
        return 'Recurring';
    }
  }

  List<Widget> _buildSections() {
    final theme = FlutterFlowTheme.of(context);
    final buckets = _bucketedItems;
    final order = [
      'Overdue',
      'Today',
      'Tomorrow',
      'This Week',
      'Later',
      'No due date',
      'Recent Completions',
    ];
    final widgets = <Widget>[];
    for (final key in order) {
      final items = List<dynamic>.from(buckets[key]!);
      final visibleItems = items.where((item) {
        if (item is ActivityInstanceRecord) {
          // Allow completed tasks in Recent Completions section
          if (key == 'Recent Completions') {
            return true;
          }
          return !_isTaskCompleted(item);
        }
        return true;
      }).toList();
      if (visibleItems.isEmpty) continue;
      _applySort(visibleItems);
      final isExpanded = _expandedSections.contains(key);
      // Get or create GlobalKey for this section
      if (!_sectionKeys.containsKey(key)) {
        _sectionKeys[key] = GlobalKey();
      }
      widgets.add(
        SliverToBoxAdapter(
          child: _buildSectionHeader(
              key, visibleItems.length, isExpanded, _sectionKeys[key]!),
        ),
      );
      if (isExpanded) {
        widgets.add(
          SliverReorderableList(
            itemBuilder: (context, index) {
              final item = visibleItems[index];
              return ReorderableDelayedDragStartListener(
                index: index,
                key: Key('${item.reference.id}_drag'),
                child: _buildItemTile(item, key),
              );
            },
            itemCount: visibleItems.length,
            onReorder: (oldIndex, newIndex) =>
                _handleReorder(oldIndex, newIndex, key),
          ),
        );
        // Add "Show older" buttons for Recent Completions section
        if (key == 'Recent Completions') {
          widgets.add(
            SliverToBoxAdapter(
              child: _buildShowOlderButtons(theme),
            ),
          );
        }
        widgets.add(
          const SliverToBoxAdapter(
            child: SizedBox(height: 8),
          ),
        );
      }
    }
    if (widgets.isEmpty) {
      widgets.add(SliverFillRemaining(
        child: Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Center(
            child: Text(
              'No tasks yet',
              style: theme.bodyLarge,
            ),
          ),
        ),
      ));
    }
    // Add bottom padding to allow content to scroll past bottom FABs
    // FAB height (56px) + bottom position (16px) + FloatingTimer space + extra padding
    widgets.add(
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 120),
      ),
    );
    // Recent Completions will be handled via buckets like other sections
    return widgets;
  }

  Widget _buildSectionHeader(
      String title, int count, bool isExpanded, GlobalKey headerKey) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      key: headerKey,
      margin: EdgeInsets.fromLTRB(16, 8, 16, isExpanded ? 0 : 6),
      padding: EdgeInsets.fromLTRB(12, 8, 12, isExpanded ? 2 : 6),
      decoration: BoxDecoration(
        gradient: theme.neumorphicGradient,
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: isExpanded ? Radius.zero : const Radius.circular(16),
          bottomRight: isExpanded ? Radius.zero : const Radius.circular(16),
        ),
        boxShadow: isExpanded ? [] : theme.neumorphicShadowsRaised,
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              // Collapse this section
              _expandedSections.remove(title);
            } else {
              // Expand this section
              _expandedSections.add(title);
            }
          });
          // Save state persistently
          ExpansionStateManager().setTaskExpandedSections(_expandedSections);
          // Scroll to make the newly expanded section visible
          if (_expandedSections.contains(title)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (headerKey.currentContext != null) {
                Scrollable.ensureVisible(
                  headerKey.currentContext!,
                  duration: Duration.zero,
                  alignment: 0.0,
                  alignmentPolicy:
                      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                );
              }
            });
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  title == 'Recent Completions'
                      ? 'Recent Completions (${_completionTimeFrame == 2 ? '2 days' : _completionTimeFrame == 7 ? '7 days' : '30 days'}) ($count)'
                      : '$title ($count)',
                  style: theme.titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  String _getSubtitle(ActivityInstanceRecord instance, String bucketKey) {
    if (bucketKey == 'Recent Completions') {
      final completedAt = instance.completedAt!;
      final completedStr =
          _isSameDay(completedAt, DateTime.now()) ? 'Today' : 'Yesterday';
      final due = instance.dueDate;
      final dueStr = due != null ? DateFormat.MMMd().format(due) : 'No due';
      final timeStr = instance.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}'
          : '';
      return 'Completed $completedStr • Due: $dueStr$timeStr';
    }
    // For Today and Tomorrow, dates are obvious, show only time if available
    if (bucketKey == 'Today' || bucketKey == 'Tomorrow') {
      if (instance.hasDueTime()) {
        return '@ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}';
      }
      return '';
    }
    // For Overdue, This Week, Later, show date + time
    final dueDate = instance.dueDate;
    if (dueDate != null) {
      final formattedDate = DateFormat.MMMd().format(dueDate);
      final timeStr = instance.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}'
          : '';
      return '$formattedDate$timeStr';
    }
    // For No due date section, show just time if available
    if (instance.hasDueTime()) {
      return '@ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}';
    }
    return '';
  }

  void _showQuickAddBottomSheet() {
    final theme = FlutterFlowTheme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          // Get safe area insets for bottom navigation bar
          final bottomPadding = MediaQuery.of(context).padding.bottom;
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
          // Use the larger of keyboard height or safe area padding
          final totalBottomPadding =
              keyboardHeight > 0 ? keyboardHeight : bottomPadding;

          return Padding(
            padding: EdgeInsets.only(
              bottom: totalBottomPadding,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.primaryBackground,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildQuickAddWithState(setModalState),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _submitQuickAdd() async {
    final title = _quickAddController.text.trim();
    if (title.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task name')),
      );
      return;
    }
    final categoryId = _selectedQuickCategoryId;
    if (categoryId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }
    if (_selectedQuickTrackingType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a tracking type')),
      );
      return;
    }
    print('--- task_page.dart: calling createActivity (quick add task) ...');
    try {
      dynamic targetValue;
      switch (_selectedQuickTrackingType) {
        case 'binary':
          targetValue = null;
          break;
        case 'quantitative':
          targetValue = _quickTargetNumber;
          break;
        case 'time':
          targetValue = _quickTargetDuration.inMinutes;
          break;
        default:
          targetValue = null;
      }
      await createActivity(
        name: title,
        categoryId: categoryId,
        categoryName:
            _categories.firstWhere((c) => c.reference.id == categoryId).name,
        trackingType: _selectedQuickTrackingType!,
        target: targetValue,
        timeEstimateMinutes: (_enableDefaultEstimates &&
                _enableActivityEstimates &&
                !_isQuickTimeTarget())
            ? _quickTimeEstimateMinutes
            : null,
        isRecurring: quickIsRecurring,
        userId: currentUserUid,
        dueDate: _selectedQuickDueDate,
        dueTime: _selectedQuickDueTime != null
            ? TimeUtils.timeOfDayToString(_selectedQuickDueTime!)
            : null,
        priority: 1,
        unit: _quickUnitController.text,
        specificDays: _quickFrequencyConfig != null &&
                _quickFrequencyConfig!.type == FrequencyType.specificDays
            ? _quickFrequencyConfig!.selectedDays
            : null,
        categoryType: 'task',
        frequencyType: quickIsRecurring
            ? _quickFrequencyConfig!.type.toString().split('.').last
            : null,
        everyXValue: quickIsRecurring &&
                _quickFrequencyConfig!.type == FrequencyType.everyXPeriod
            ? _quickFrequencyConfig!.everyXValue
            : null,
        everyXPeriodType: quickIsRecurring &&
                _quickFrequencyConfig!.type == FrequencyType.everyXPeriod
            ? _quickFrequencyConfig!.everyXPeriodType.toString().split('.').last
            : null,
        timesPerPeriod: quickIsRecurring &&
                _quickFrequencyConfig!.type == FrequencyType.timesPerPeriod
            ? _quickFrequencyConfig!.timesPerPeriod
            : null,
        periodType: quickIsRecurring &&
                _quickFrequencyConfig!.type == FrequencyType.timesPerPeriod
            ? _quickFrequencyConfig!.periodType.toString().split('.').last
            : null,
        startDate: quickIsRecurring ? _quickFrequencyConfig!.startDate : null,
        endDate: quickIsRecurring ? _quickFrequencyConfig!.endDate : null,
        reminders: _quickReminders.isNotEmpty
            ? ReminderConfigList.toMapList(_quickReminders)
            : null,
      );
      print('--- task_page.dart: createActivity completed successfully');
      // Reset the form immediately after creating the task
      _resetQuickAdd();
      // Close the bottom sheet
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task created successfully')),
        );
        Navigator.pop(context);
      }
      // The createActivity function already broadcasts the instance creation event
      // No need to manually broadcast or refresh - the event handler will handle it
    } catch (e) {
      print('--- task_page.dart: createActivity failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding task: $e')),
      );
    }
  }

  void _resetQuickAdd() {
    setState(() {
      _quickAddController.clear();
      _selectedQuickTrackingType = 'binary';
      _quickTargetNumber = 1;
      _quickTargetDuration = const Duration(hours: 1);
      _selectedQuickDueDate = null;
      _selectedQuickDueTime = null;
      _quickTimeEstimateMinutes = null;
      _quickFrequencyConfig = null;
      _quickReminders = [];
      quickIsRecurring = false;
      _quickUnitController.clear();
      _quickTargetNumberController.text = '1';
      _quickHoursController.text = '1';
      _quickMinutesController.text = '0';
    });
  }

  Future<void> _loadTimeEstimatePreferences() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;
      final enableDefault =
          await TimeLoggingPreferencesService.getEnableDefaultEstimates(userId);
      final enableActivity =
          await TimeLoggingPreferencesService.getEnableActivityEstimates(userId);
      if (!mounted) return;
      setState(() {
        _enableDefaultEstimates = enableDefault;
        _enableActivityEstimates = enableActivity;
      });
    } catch (_) {
      // Ignore - default to feature OFF in this view
    }
  }

  bool _isQuickTimeTarget() {
    return _selectedQuickTrackingType == 'time' &&
        _quickTargetDuration.inMinutes > 0;
  }

  Future<void> _selectQuickDueDate(
      [void Function(VoidCallback)? updateStateFn]) async {
    final updateState = updateStateFn ?? ((VoidCallback fn) => setState(fn));
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedQuickDueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedQuickDueDate) {
      updateState(() {
        _selectedQuickDueDate = picked;
        if (quickIsRecurring && _quickFrequencyConfig != null) {
          _quickFrequencyConfig =
              _quickFrequencyConfig!.copyWith(startDate: picked);
        }
      });
    }
  }

  Future<void> _selectQuickDueTime(
      [void Function(VoidCallback)? updateStateFn]) async {
    final updateState = updateStateFn ?? ((VoidCallback fn) => setState(fn));
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedQuickDueTime ?? TimeUtils.getCurrentTime(),
    );
    if (picked != null && picked != _selectedQuickDueTime) {
      updateState(() {
        _selectedQuickDueTime = picked;
      });
    }
  }

  Future<void> _selectQuickTimeEstimate(
      [void Function(VoidCallback)? updateStateFn]) async {
    final updateState = updateStateFn ?? ((VoidCallback fn) => setState(fn));
    final theme = FlutterFlowTheme.of(context);
    final result = await _showQuickTimeEstimateSheet(
      theme: theme,
      initialMinutes: _quickTimeEstimateMinutes,
    );
    if (!mounted) return;
    updateState(() {
      _quickTimeEstimateMinutes = result;
    });
  }

  Future<int?> _showQuickTimeEstimateSheet({
    required FlutterFlowTheme theme,
    required int? initialMinutes,
  }) async {
    final controller =
        TextEditingController(text: initialMinutes?.toString() ?? '');
    const presets = <int>[5, 10, 15, 20, 30, 45, 60];

    final result = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            decoration: BoxDecoration(
              color: theme.primaryBackground,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: theme.surfaceBorderColor, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Time estimate',
                    style: theme.titleMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: 'Minutes (1–600)',
                            hintStyle: TextStyle(
                              color: theme.secondaryText,
                              fontSize: 14,
                            ),
                            filled: true,
                            fillColor: theme.tertiary.withOpacity(0.3),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: theme.surfaceBorderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: theme.surfaceBorderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primary),
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets
                        .map(
                          (m) => OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, m),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: theme.surfaceBorderColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              foregroundColor: theme.primaryText,
                            ),
                            child: Text('${m}m'),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final parsed = int.tryParse(controller.text.trim());
                        if (parsed == null) {
                          Navigator.pop(ctx, null);
                          return;
                        }
                        Navigator.pop(ctx, parsed.clamp(1, 600));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    controller.dispose();
    return result;
  }

  Future<void> _selectQuickReminders(
      [void Function(VoidCallback)? updateStateFn]) async {
    final updateState = updateStateFn ?? ((VoidCallback fn) => setState(fn));
    final reminders = await ReminderConfigDialog.show(
      context: context,
      initialReminders: _quickReminders,
      dueTime: _selectedQuickDueTime,
      onRequestDueTime: () => _selectQuickDueTime(updateState),
    );
    if (reminders != null) {
      updateState(() {
        _quickReminders = reminders;
        // Auto-set due date to today if reminders are added and no due date exists
        if (_quickReminders.isNotEmpty &&
            !quickIsRecurring &&
            _selectedQuickDueDate == null) {
          _selectedQuickDueDate = DateTime.now();
        }
      });
    }
  }

  Map<String, List<dynamic>> get _bucketedItems {
    // Check if cache is still valid
    final currentInstancesHash = _taskInstances.length.hashCode ^
        _taskInstances.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);

    final cacheInvalid = _cachedBucketedItems == null ||
        currentInstancesHash != _taskInstancesHashCode ||
        _searchQuery != _lastSearchQuery ||
        _completionTimeFrame != _lastCompletionTimeFrame ||
        widget.categoryName != _lastCategoryName;

    if (!cacheInvalid && _cachedBucketedItems != null) {
      return _cachedBucketedItems!;
    }

    // Recalculate buckets
    final Map<String, List<dynamic>> buckets = {
      'Overdue': [],
      'Today': [],
      'Tomorrow': [],
      'This Week': [],
      'Later': [],
      'No due date': [],
      'Recent Completions': [],
    };
    // Filter instances by search query if active
    final activeInstancesToProcess = _taskInstances
        .where((inst) => inst.status == 'pending') // Filter for pending tasks
        .where((instance) {
      if (_searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
    }).toList();
    print(
        '_bucketedItems: Processing ${activeInstancesToProcess.length} active task instances (search: "$_searchQuery")');
    final today = DateService.todayStart;
    final tomorrow = DateService.tomorrowStart;
    // "This Week" covers the next 5 days after tomorrow
    final thisWeekEnd = tomorrow.add(const Duration(days: 5));
    // Group recurring tasks by templateId to show only earliest pending instance
    final Map<String, List<ActivityInstanceRecord>> recurringTasksByTemplate =
        {};
    final List<ActivityInstanceRecord> oneOffTasks = [];
    for (final instance in activeInstancesToProcess) {
      if (!instance.isActive) {
        continue;
      }
      if (widget.categoryName != null &&
          instance.templateCategoryName != widget.categoryName) {
        continue;
      }
      if (instance.templateIsRecurring) {
        // Group recurring tasks by template
        final templateId = instance.templateId;
        (recurringTasksByTemplate[templateId] ??= []).add(instance);
      } else {
        // One-off tasks go directly to processing
        oneOffTasks.add(instance);
      }
    }
    // Process one-off tasks normally
    for (final instance in oneOffTasks) {
      final dueDate = instance.dueDate;
      if (dueDate == null) {
        buckets['No due date']!.add(instance);
        continue;
      }
      final instanceDueDate =
          DateTime(dueDate.year, dueDate.month, dueDate.day);
      if (instanceDueDate.isBefore(today)) {
        buckets['Overdue']!.add(instance);
      } else if (_isSameDay(instanceDueDate, today)) {
        buckets['Today']!.add(instance);
      } else if (_isSameDay(instanceDueDate, tomorrow)) {
        buckets['Tomorrow']!.add(instance);
      } else if (instanceDueDate.isAfter(tomorrow) &&
          !instanceDueDate.isAfter(thisWeekEnd)) {
        buckets['This Week']!.add(instance);
      } else {
        buckets['Later']!.add(instance);
      }
    }
    // Process recurring tasks - show only earliest pending instance per template
    for (final templateId in recurringTasksByTemplate.keys) {
      final instances = recurringTasksByTemplate[templateId]!;
      // Sort by due date (earliest first)
      instances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
      // Take the earliest pending instance
      final earliestInstance = instances.first;
      print(
          '  Processing recurring task: ${earliestInstance.templateName} (earliest of ${instances.length} instances)');
      final dueDate = earliestInstance.dueDate;
      if (dueDate == null) {
        buckets['No due date']!.add(earliestInstance);
        continue;
      }
      final instanceDueDate =
          DateTime(dueDate.year, dueDate.month, dueDate.day);
      if (instanceDueDate.isBefore(today)) {
        buckets['Overdue']!.add(earliestInstance);
      } else if (_isSameDay(instanceDueDate, today)) {
        buckets['Today']!.add(earliestInstance);
      } else if (_isSameDay(instanceDueDate, tomorrow)) {
        buckets['Tomorrow']!.add(earliestInstance);
      } else if (instanceDueDate.isAfter(tomorrow) &&
          !instanceDueDate.isAfter(thisWeekEnd)) {
        buckets['This Week']!.add(earliestInstance);
      } else {
        buckets['Later']!.add(earliestInstance);
      }
    }
    // Populate Recent Completions with unified time window logic
    final completionCutoff =
        DateService.todayStart.subtract(Duration(days: _completionTimeFrame));
    final allInstancesToProcess = _taskInstances.where((instance) {
      if (_searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
    }).toList();
    // Group completed instances by template for recurring tasks
    final Map<String, List<ActivityInstanceRecord>>
        completedRecurringByTemplate = {};
    final List<ActivityInstanceRecord> completedOneOffTasks = [];
    for (final instance in allInstancesToProcess) {
      if (instance.status != 'completed') continue;
      if (instance.completedAt == null) continue;
      if (widget.categoryName != null &&
          instance.templateCategoryName != widget.categoryName) {
        continue;
      }
      final completedDate = instance.completedAt!;
      final completedDateOnly =
          DateTime(completedDate.year, completedDate.month, completedDate.day);
      // Unified time window for both recurring and one-off tasks
      if (completedDateOnly.isAfter(completionCutoff) ||
          completedDateOnly.isAtSameMomentAs(completionCutoff)) {
        if (instance.templateIsRecurring) {
          // Group recurring tasks by template
          final templateId = instance.templateId;
          (completedRecurringByTemplate[templateId] ??= []).add(instance);
        } else {
          // Add one-off tasks directly
          completedOneOffTasks.add(instance);
        }
      }
    }
    // Add all completed instances of recurring tasks within time window
    for (final templateId in completedRecurringByTemplate.keys) {
      final instances = completedRecurringByTemplate[templateId]!;
      // Sort by completion date (latest first)
      instances.sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
      // Add ALL instances within the time window
      for (final instance in instances) {
        buckets['Recent Completions']!.add(instance);
        print(
            '  Added completed recurring task: ${instance.templateName} (completed: ${instance.completedAt})');
      }
    }
    // Add all completed one-off tasks within time window
    for (final instance in completedOneOffTasks) {
      buckets['Recent Completions']!.add(instance);
    }
    // Sort items within each bucket by tasks order
    for (final key in buckets.keys) {
      final items = buckets[key]!;
      if (items.isNotEmpty) {
        // Cast to ActivityInstanceRecord list
        final typedItems = items.cast<ActivityInstanceRecord>();
        // Sort by tasks order
        buckets[key] =
            InstanceOrderService.sortInstancesByOrder(typedItems, 'tasks');
      }
    }
    // Auto-expand sections with search results
    if (_searchQuery.isNotEmpty) {
      for (final key in buckets.keys) {
        if (buckets[key]!.isNotEmpty) {
          _expandedSections.add(key);
        }
      }
    }

    // Update cache
    _cachedBucketedItems = buckets;
    _taskInstancesHashCode = currentInstancesHash;
    _lastSearchQuery = _searchQuery;
    _lastCompletionTimeFrame = _completionTimeFrame;
    _lastCategoryName = widget.categoryName;

    buckets.forEach((key, value) {});
    return buckets;
  }

  // Recent Completions UI is now handled via standard sections and ItemComponent
  // Removed legacy actions for custom Recent Completions UI
  Widget _buildItemTile(dynamic item, String bucketKey) {
    if (item is ActivityInstanceRecord) {
      return _buildTaskTile(item, bucketKey);
    }
    return const SizedBox.shrink();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  Widget _buildTaskTile(ActivityInstanceRecord instance, String bucketKey) {
    return ItemComponent(
      page: "task",
      subtitle: _getSubtitle(instance, bucketKey),
      showCalendar: true,
      showTaskEdit: true,
      key: Key(instance.reference.id),
      instance: instance,
      categories: _categories,
      onRefresh: _loadData,
      onInstanceUpdated: _updateInstanceInLocalState,
      onInstanceDeleted: _removeInstanceFromLocalState,
      showTypeIcon: false,
      showRecurringIcon: instance.status != 'completed',
      showCompleted: bucketKey == 'Recent Completions' ? true : null,
    );
  }

  Widget _buildShowOlderButtons(FlutterFlowTheme theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Show fewer button (when not at minimum)
          if (_completionTimeFrame > 2) ...[
            GestureDetector(
              onTap: () {
                setState(() {
                  _completionTimeFrame = _completionTimeFrame == 30 ? 7 : 2;
                  // Invalidate cache when completion time frame changes
                  _cachedBucketedItems = null;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.secondaryBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.alternate,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off,
                      size: 16,
                      color: theme.secondaryText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Show fewer (${_completionTimeFrame == 30 ? '7 days' : '2 days'})',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          // Show older button (when not at maximum)
          if (_completionTimeFrame < 30) ...[
            GestureDetector(
              onTap: () {
                setState(() {
                  _completionTimeFrame = _completionTimeFrame == 2 ? 7 : 30;
                  // Invalidate cache when completion time frame changes
                  _cachedBucketedItems = null;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.primary.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history,
                      size: 16,
                      color: theme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Show older (${_completionTimeFrame == 2 ? '7 days' : '30 days'})',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _updateInstanceInLocalState(ActivityInstanceRecord updatedInstance) {
    setState(() {
      final index = _taskInstances.indexWhere(
          (inst) => inst.reference.id == updatedInstance.reference.id);
      if (index != -1) {
        _taskInstances[index] = updatedInstance;
        // Invalidate cache when instance is updated
        _cachedBucketedItems = null;
      }
      // DO NOT remove from list if completed - we want them to move to "Recent Completions"
      // instead of disappearing entirely
      /*
      if (updatedInstance.status == 'completed') {
        _taskInstances.removeWhere(
            (inst) => inst.reference.id == updatedInstance.reference.id);
      }
      */
    });
    // Background refresh to sync with server
    _loadDataSilently();
  }

  void _removeInstanceFromLocalState(ActivityInstanceRecord deletedInstance) {
    setState(() {
      _taskInstances.removeWhere(
          (inst) => inst.reference.id == deletedInstance.reference.id);
      // Invalidate cache when instance is removed
      _cachedBucketedItems = null;
    });
    // Background refresh to sync with server
    _loadDataSilently();
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
      if (mounted) {
        setState(() {
          _categories = categories;
          _taskInstances = categoryFiltered;
          // Invalidate cache when instances change
          _cachedBucketedItems = null;
        });
      }
      // Best-effort initialize missing order values (safe, caught).
      try {
        await InstanceOrderService.initializeOrderValues(categoryFiltered, 'tasks');
      } catch (_) {}
    } catch (e) {
      // Silent error handling - don't disrupt UI
    }
  }

  void _applySort(List<dynamic> items) {
    if (sortMode != 'importance') return;
    int cmpTask(ActivityInstanceRecord a, ActivityInstanceRecord b) {
      final ap = a.templatePriority;
      final bp = b.templatePriority;
      if (bp != ap) return bp.compareTo(ap);
      final ad = a.dueDate;
      final bd = b.dueDate;
      if (ad != null && bd != null) return ad.compareTo(bd);
      if (ad != null) return -1;
      if (bd != null) return 1;
      return a.templateName
          .toLowerCase()
          .compareTo(b.templateName.toLowerCase());
    }

    items.sort((x, y) {
      final xt = x is ActivityInstanceRecord;
      final yt = y is ActivityInstanceRecord;
      if (xt && yt) return cmpTask(x, y);
      if (xt && !yt) return -1;
      if (!xt && yt) return 1;
      return 0;
    });
  }

  // Event handlers for live updates
  void _handleInstanceCreated(ActivityInstanceRecord instance) {
    // Only add task instances to this page
    if (instance.templateCategoryType == 'task') {
      // Check if instance matches this page's category filter
      final matchesCategory = widget.categoryName == null ||
          instance.templateCategoryName == widget.categoryName;
      if (matchesCategory) {
        setState(() {
          _taskInstances.add(instance);
          // Invalidate cache when instance is added
          _cachedBucketedItems = null;
        });
      }
    }
  }

  void _handleInstanceUpdated(dynamic param) {
    // Handle both optimistic and reconciled updates
    ActivityInstanceRecord instance;
    bool isOptimistic = false;
    String? operationId;
    
    if (param is Map) {
      instance = param['instance'] as ActivityInstanceRecord;
      isOptimistic = param['isOptimistic'] as bool? ?? false;
      operationId = param['operationId'] as String?;
    } else if (param is ActivityInstanceRecord) {
      // Backward compatibility: handle old format
      instance = param;
    } else {
      return;
    }
    
    // Skip updates for instances currently being reordered to prevent stale data overwrites
    if (_reorderingInstanceIds.contains(instance.reference.id)) {
      return;
    }
    
    // Only handle task instances
    if (instance.templateCategoryType == 'task') {
      // Check if instance matches this page's category filter
      final matchesCategory = widget.categoryName == null ||
          instance.templateCategoryName == widget.categoryName;
      if (matchesCategory) {
        setState(() {
          final index = _taskInstances
              .indexWhere((inst) => inst.reference.id == instance.reference.id);
          
          if (index != -1) {
            if (isOptimistic) {
              // Store optimistic state with operation ID for later reconciliation
              _taskInstances[index] = instance;
              if (operationId != null) {
                _optimisticOperations[operationId] = instance.reference.id;
              }
            } else {
              // Reconciled update - replace optimistic state
              _taskInstances[index] = instance;
              if (operationId != null) {
                _optimisticOperations.remove(operationId);
              }
            }
            // Invalidate cache when instance is updated
            _cachedBucketedItems = null;
          } else if (!isOptimistic) {
            // New instance from backend (not optimistic) - add it
            _taskInstances.add(instance);
            _cachedBucketedItems = null;
          }
        });
      }
    }
  }
  
  void _handleRollback(dynamic param) {
    if (param is Map) {
      final operationId = param['operationId'] as String?;
      final instanceId = param['instanceId'] as String?;
      final originalInstance = param['originalInstance'] as ActivityInstanceRecord?;
      
      if (operationId != null && _optimisticOperations.containsKey(operationId)) {
        setState(() {
          _optimisticOperations.remove(operationId);
          if (originalInstance != null) {
            // Restore from original state
            final index = _taskInstances.indexWhere(
              (inst) => inst.reference.id == instanceId
            );
            if (index != -1) {
              _taskInstances[index] = originalInstance;
              _cachedBucketedItems = null;
            }
          } else if (instanceId != null) {
            // Fallback to reloading from backend
            _revertOptimisticUpdate(instanceId);
          }
        });
      }
    }
  }
  
  Future<void> _revertOptimisticUpdate(String instanceId) async {
    try {
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instanceId,
      );
      setState(() {
        final index = _taskInstances
            .indexWhere((inst) => inst.reference.id == instanceId);
        if (index != -1) {
          _taskInstances[index] = updatedInstance;
          _cachedBucketedItems = null;
        }
      });
    } catch (e) {
      // Error reverting - non-critical, will be fixed on next data load
    }
  }

  void _handleInstanceDeleted(ActivityInstanceRecord instance) {
    // Only handle task instances
    if (instance.templateCategoryType == 'task') {
      // Check if instance matches this page's category filter
      final matchesCategory = widget.categoryName == null ||
          instance.templateCategoryName == widget.categoryName;
      if (matchesCategory) {
        setState(() {
          _taskInstances.removeWhere(
              (inst) => inst.reference.id == instance.reference.id);
          // Invalidate cache when instance is deleted
          _cachedBucketedItems = null;
        });
      }
    }
  }

  /// Handle reordering of items within a section
  Future<void> _handleReorder(
      int oldIndex, int newIndex, String sectionKey) async {
    final reorderingIds = <String>{};
    try {
      final buckets = _bucketedItems;
      final items = buckets[sectionKey]!;
      // Allow dropping at the end (newIndex can equal items.length)
      if (oldIndex < 0 ||
          oldIndex >= items.length ||
          newIndex < 0 ||
          newIndex > items.length) return;
      // Create a copy of the items list for reordering
      final reorderedItems = List<ActivityInstanceRecord>.from(items);
      // Adjust newIndex for the case where we're moving down
      int adjustedNewIndex = newIndex;
      if (oldIndex < newIndex) {
        adjustedNewIndex -= 1;
      }
      // Get the item being moved
      final movedItem = reorderedItems.removeAt(oldIndex);
      reorderedItems.insert(adjustedNewIndex, movedItem);
      // OPTIMISTIC UI UPDATE: Update local state immediately
      // Update order values in _taskInstances
      for (int i = 0; i < reorderedItems.length; i++) {
        final instance = reorderedItems[i];
        final instanceId = instance.reference.id;
        reorderingIds.add(instanceId);
        // Create updated instance with new tasks order
        final updatedData = Map<String, dynamic>.from(instance.snapshotData);
        updatedData['tasksOrder'] = i;
        final updatedInstance = ActivityInstanceRecord.getDocumentFromData(
          updatedData,
          instance.reference,
        );
        // Update in _taskInstances
        final taskIndex = _taskInstances
            .indexWhere((inst) => inst.reference.id == instanceId);
        if (taskIndex != -1) {
          _taskInstances[taskIndex] = updatedInstance;
        }
      }
      // Add instance IDs to reordering set to prevent stale updates
      _reorderingInstanceIds.addAll(reorderingIds);
      // Invalidate cache to ensure UI uses updated order
      _cachedBucketedItems = null;
      // Trigger setState to update UI immediately (eliminates twitch)
      if (mounted) {
        setState(() {
          // State is already updated above
        });
      }
      // Perform database update in background
      await InstanceOrderService.reorderInstancesInSection(
        reorderedItems,
        'tasks',
        oldIndex,
        adjustedNewIndex,
      );
      // Clear reordering set after successful database update
      _reorderingInstanceIds.removeAll(reorderingIds);
    } catch (e) {
      // Clear reordering set even on error
      _reorderingInstanceIds.removeAll(reorderingIds);
      // Revert to correct state by refreshing data
      await _loadData();
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reordering items: $e')),
        );
      }
    }
  }
}
