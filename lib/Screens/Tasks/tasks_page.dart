import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/task_record.dart';
import 'package:habit_tracker/Helper/backend/schema/task_instance_record.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/task_type_dropdown_helper.dart';
import 'package:habit_tracker/Helper/utils/task_frequency_helper.dart';
import 'package:habit_tracker/Screens/Create%20Catagory/create_category.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class TasksPage extends StatefulWidget {
  final bool showCompleted;
  const TasksPage({super.key, required this.showCompleted});

  @override
  _TasksPageState createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with TickerProviderStateMixin {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  List<TaskRecord> _tasks = [];
  List<CategoryRecord> _categories = [];
  List<TaskInstanceRecord> _todaysTaskInstances = [];
  final Map<String, bool> _categoryExpanded = {};
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  bool _shouldReloadOnReturn = false;
  late bool _showCompleted;
  bool _showTodaysView = false; // Default to all tasks view

  // Timer management for live updates
  final Map<String, Timer> _activeTimers = {};
  final Map<String, int> _liveAccumulatedTime = {};

  // Start a live timer for a task or instance
  void _startLiveTimer(String id, bool isInstance) {
    _stopLiveTimer(id); // Stop any existing timer

    _activeTimers[id] = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // Update live accumulated time
          _liveAccumulatedTime[id] = (_liveAccumulatedTime[id] ?? 0) + 1000;
        });
      } else {
        timer.cancel();
      }
    });
  }

  // Stop a live timer
  void _stopLiveTimer(String id) {
    _activeTimers[id]?.cancel();
    _activeTimers.remove(id);
    _liveAccumulatedTime.remove(id);
  }

  // Get current live accumulated time for a timer
  int _getLiveAccumulatedTime(
      String id, int baseAccumulatedTime, DateTime? startTime) {
    if (_activeTimers.containsKey(id) && startTime != null) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      return baseAccumulatedTime + elapsed;
    }
    return baseAccumulatedTime;
  }

  // Initialize live timers for all active timers
  void _initializeLiveTimers() {
    // Clear existing timers
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    _liveAccumulatedTime.clear();

    // Start timers for active tasks
    for (final task in _tasks) {
      if (task.isTimerActive && task.timerStartTime != null) {
        _startLiveTimer(task.reference.id, false);
      }
    }

    // Start timers for active task instances
    for (final instance in _todaysTaskInstances) {
      if (instance.isTimerActive == true && instance.timerStartTime != null) {
        _startLiveTimer(instance.reference.id, true);
      }
    }
  }

  // Tab system variables
  late TabController _tabController;
  List<String> _tabNames = ["Inbox"];
  String? _currentCategoryId;

  // Quick Add state variables
  final TextEditingController _quickAddController = TextEditingController();
  String? _selectedQuickTrackingType = 'binary';
  DateTime? _selectedQuickDueDate;
  int _quickTargetNumber = 1;
  Duration _quickTargetDuration = const Duration(hours: 1);
  final TextEditingController _quickUnitController = TextEditingController();
  bool _quickIsRecurring = false;
  String _quickSchedule = 'daily';
  int _quickFrequency = 1;
  List<int> _quickSelectedDays = [];

  // Sorting and filtering
  String _sortMode = 'default';

  @override
  void initState() {
    super.initState();
    _showCompleted = widget.showCompleted;
    _tabController = TabController(length: _tabNames.length, vsync: this);
    _loadCategories();
    NotificationCenter.addObserver(this, 'showTaskCompleted', (param) {
      if (param is bool && mounted) {
        setState(() {
          _showCompleted = param;
        });
      }
    });
    NotificationCenter.addObserver(this, 'loadTasks', (param) {
      if (mounted) {
        setState(() {
          _loadCategories();
        });
      }
    });
  }

  @override
  void dispose() {
    // Clean up all active timers
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    _liveAccumulatedTime.clear();

    NotificationCenter.removeObserver(this);
    _scrollController.dispose();
    _quickAddController.dispose();
    _quickUnitController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialDependencies) {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent && _shouldReloadOnReturn) {
        _shouldReloadOnReturn = false;
        _loadCategories();
      }
    } else {
      _didInitialDependencies = true;
    }
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        // Ensure inbox category exists first
        await getOrCreateInboxCategory(userId: userId);

        // Get all task categories (including system categories like inbox)
        final allTaskCategories = await queryTaskCategoriesOnce(userId: userId);

        // Get user-created categories only (excluding system categories)
        final userCategories =
            await queryUserCategoriesOnce(userId: userId, categoryType: 'task');

        setState(() {
          _categories = allTaskCategories;
          // Always show Inbox first, then user-created categories
          _tabNames = ["Inbox", ...userCategories.map((c) => c.name)];
          _tabController.dispose();
          _tabController = TabController(length: _tabNames.length, vsync: this);

          // Set current category ID to the first tab (Inbox)
          if (_categories.isNotEmpty) {
            final inboxCategory = _categories.firstWhere(
              (c) => c.name == 'Inbox' && c.isSystemCategory,
              orElse: () => _categories.firstWhere(
                (c) => c.name == 'Inbox',
                orElse: () => _categories.first,
              ),
            );
            _currentCategoryId = inboxCategory.reference.id;
          }

          _isLoading = false;
        });

        // Load tasks for the current category
        await _loadTasksForCurrentCategory();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading categories: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTasksForCurrentCategory() async {
    if (_currentCategoryId == null) return;

    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final tasks = await queryTasksRecordOnce(userId: userId);
        final todaysInstances = await queryTodaysTaskInstances(userId: userId);

        setState(() {
          // Filter tasks by current category
          _tasks = tasks
              .where((task) => task.categoryId == _currentCategoryId)
              .toList();
          _todaysTaskInstances = todaysInstances;
        });

        // Initialize live timers for active timers
        _initializeLiveTimers();
      }
    } catch (e) {
      print('Error loading tasks for category: $e');
    }
  }

  Map<String, List<TaskInstanceRecord>> get _groupedTodaysInstances {
    final grouped = <String, List<TaskInstanceRecord>>{};

    for (final instance in _todaysTaskInstances) {
      if (!_showCompleted && instance.status == 'completed') continue;

      final categoryName = instance.templateCategoryName.isNotEmpty
          ? instance.templateCategoryName
          : 'Uncategorized';
      (grouped[categoryName] ??= []).add(instance);
    }

    return grouped;
  }

  bool _isTaskCompleted(TaskRecord task) {
    if (!task.isActive) return false;
    switch (task.trackingType) {
      case 'binary':
        return task.status == 'complete';
      case 'quantitative':
        final currentValue = task.currentValue ?? 0;
        final target = task.target ?? 0;
        return target > 0 && currentValue >= target;
      case 'time':
        final currentMinutes = (task.accumulatedTime) ~/ 60000;
        final targetMinutes = task.target ?? 0;
        return targetMinutes > 0 && currentMinutes >= targetMinutes;
      default:
        return task.status == 'complete';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: _buildTasksView(),
                    ),
                  ],
                ),
          // FloatingTimer temporarily disabled for tasks - needs TaskRecord support
          // TODO: Implement TaskFloatingTimer or adapt FloatingTimer for TaskRecord
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        border: Border(
          bottom: BorderSide(
            color: FlutterFlowTheme.of(context).alternate,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tab bar with add button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: _tabNames.isEmpty
                      ? const SizedBox()
                      : TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          indicatorColor: FlutterFlowTheme.of(context).primary,
                          labelColor: FlutterFlowTheme.of(context).primaryText,
                          unselectedLabelColor:
                              FlutterFlowTheme.of(context).secondaryText,
                          tabs:
                              _tabNames.map((name) => Tab(text: name)).toList(),
                          onTap: (index) {
                            _onTabChanged(index);
                          },
                        ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.add,
                    color: FlutterFlowTheme.of(context).primaryText,
                  ),
                  onPressed: () async {
                    await _showAddCategoryDialog(context);
                    await _loadCategories();
                  },
                  tooltip: 'Add Category',
                ),
              ],
            ),
          ),
          // Quick Add section
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _buildQuickAdd(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAdd() {
    return Container(
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Main input row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quickAddController,
                    decoration: const InputDecoration(
                      hintText: 'Quick add task…',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _submitQuickAdd(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _submitQuickAdd,
                  padding: const EdgeInsets.all(4),
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          // Always show options
          ...[
            Divider(
              height: 1,
              thickness: 1,
              color: FlutterFlowTheme.of(context).alternate,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: [
                  // Compact single row with icons only
                  Row(
                    children: [
                      // Task type dropdown (icon only)
                      IconTaskTypeDropdown(
                        selectedValue: _selectedQuickTrackingType ?? 'binary',
                        onChanged: (value) {
                          setState(() {
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
                      const SizedBox(width: 4),
                      // Due date picker (icon only)
                      IconButton(
                        icon: Icon(
                          _selectedQuickDueDate != null
                              ? Icons.calendar_today
                              : Icons.calendar_today_outlined,
                          color: _selectedQuickDueDate != null
                              ? FlutterFlowTheme.of(context).primary
                              : FlutterFlowTheme.of(context).secondaryText,
                        ),
                        onPressed: _selectQuickDueDate,
                        tooltip: _selectedQuickDueDate != null
                            ? 'Due: ${DateFormat('MMM dd').format(_selectedQuickDueDate!)}'
                            : 'Set due date',
                        padding: const EdgeInsets.all(4),
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      // Recurring task toggle (icon only)
                      IconButton(
                        icon: Icon(
                          _quickIsRecurring
                              ? Icons.repeat
                              : Icons.repeat_outlined,
                          color: _quickIsRecurring
                              ? FlutterFlowTheme.of(context).primary
                              : FlutterFlowTheme.of(context).secondaryText,
                        ),
                        onPressed: () {
                          setState(() {
                            _quickIsRecurring = !_quickIsRecurring;
                            if (!_quickIsRecurring) {
                              // Reset recurring options when disabled
                              _quickSchedule = 'daily';
                              _quickFrequency = 1;
                              _quickSelectedDays = [];
                            } else {
                              // Set default frequency when enabling
                              _quickFrequency =
                                  TaskFrequencyHelper.getDefaultFrequency(
                                      _quickSchedule);
                            }
                          });
                        },
                        tooltip: _quickIsRecurring
                            ? 'Recurring task'
                            : 'Make recurring',
                        padding: const EdgeInsets.all(4),
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Target value row (conditional)
                  if (_selectedQuickTrackingType == 'quantitative') ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Target',
                                style: FlutterFlowTheme.of(context).bodySmall,
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                initialValue: _quickTargetNumber.toString(),
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (value) {
                                  _quickTargetNumber = int.tryParse(value) ?? 1;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unit',
                                style: FlutterFlowTheme.of(context).bodySmall,
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: _quickUnitController,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  hintText: 'e.g., pages, reps',
                                ),
                                onChanged: (value) {
                                  // Unit value stored in controller
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_selectedQuickTrackingType == 'time') ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Target Duration',
                                style: FlutterFlowTheme.of(context).bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: _quickTargetDuration.inHours
                                          .toString(),
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        labelText: 'Hours',
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (value) {
                                        final hours = int.tryParse(value) ?? 1;
                                        _quickTargetDuration = Duration(
                                          hours: hours,
                                          minutes:
                                              _quickTargetDuration.inMinutes %
                                                  60,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue:
                                          (_quickTargetDuration.inMinutes % 60)
                                              .toString(),
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        labelText: 'Minutes',
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (value) {
                                        final minutes =
                                            int.tryParse(value) ?? 0;
                                        _quickTargetDuration = Duration(
                                          hours: _quickTargetDuration.inHours,
                                          minutes: minutes,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Recurring options (only show when recurring is enabled)
                  if (_quickIsRecurring) ...[
                    // Schedule dropdown
                    Row(
                      children: [
                        Expanded(
                          child: ScheduleDropdown(
                            selectedSchedule: _quickSchedule,
                            onChanged: (value) {
                              setState(() {
                                _quickSchedule = value ?? 'daily';
                                // Reset frequency and days when schedule changes
                                _quickFrequency =
                                    TaskFrequencyHelper.getDefaultFrequency(
                                        _quickSchedule);
                                _quickSelectedDays = [];
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    // Frequency input for weekly/monthly
                    if (TaskFrequencyHelper.shouldShowFrequencyInput(
                        _quickSchedule)) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: FrequencyInput(
                              schedule: _quickSchedule,
                              frequency: _quickFrequency,
                              onChanged: (value) {
                                setState(() {
                                  _quickFrequency = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Day selection for weekly
                    if (TaskFrequencyHelper.shouldShowDaySelection(
                        _quickSchedule)) ...[
                      const SizedBox(height: 6),
                      DaySelectionChips(
                        selectedDays: _quickSelectedDays,
                        onChanged: (days) {
                          setState(() {
                            _quickSelectedDays = days;
                          });
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTasksView() {
    if (_showTodaysView) {
      return _buildTodaysInstancesView();
    } else {
      return _buildAllTasksView();
    }
  }

  Widget _buildTodaysInstancesView() {
    final groupedInstances = _groupedTodaysInstances;

    if (groupedInstances.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              size: 64,
              color: Colors.green,
            ),
            const SizedBox(height: 16),
            Text(
              'All tasks completed for today! 🎉',
              style: FlutterFlowTheme.of(context).titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Great job staying productive!',
              style: FlutterFlowTheme.of(context).bodyMedium,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _showTodaysView = false),
              child: const Text('View All Tasks'),
            ),
          ],
        ),
      );
    }

    final slivers = <Widget>[];

    for (final categoryName in groupedInstances.keys) {
      final instances = groupedInstances[categoryName]!;
      CategoryRecord? category;
      try {
        category = _categories.firstWhere((c) => c.name == categoryName);
      } catch (e) {
        // Create a default category if not found
        final categoryData = createCategoryRecordData(
          name: categoryName,
          color: '#2196F3',
          userId: currentUserUid,
          isActive: true,
          weight: 1.0,
          createdTime: DateTime.now(),
          lastUpdated: DateTime.now(),
          categoryType: 'task',
        );
        category = CategoryRecord.getDocumentFromData(
          categoryData,
          FirebaseFirestore.instance.collection('categories').doc(),
        );
      }

      final expanded = _categoryExpanded[categoryName] ?? true;

      slivers.add(
        SliverToBoxAdapter(
          child: _buildCategoryHeader(
              category, expanded, categoryName, instances.length),
        ),
      );

      if (expanded) {
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final instance = instances[index];
                return _buildTaskInstanceCard(instance);
              },
              childCount: instances.length,
            ),
          ),
        );
      }
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        ...slivers,
        const SliverToBoxAdapter(
          child: SizedBox(height: 140),
        ),
      ],
    );
  }

  Future<void> _selectQuickDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedQuickDueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedQuickDueDate = picked;
      });
    }
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

    if (_currentCategoryId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No category selected')),
      );
      return;
    }

    if (_selectedQuickTrackingType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a tracking type')),
      );
      return;
    }

    try {
      // Note: targetValue not used in current createTask implementation
      // but kept for future enhancement

      final categoryName = _categories
          .firstWhere((c) => c.reference.id == _currentCategoryId)
          .name;

      // Prepare tracking type specific data
      dynamic targetValue;
      String unitValue = '';

      switch (_selectedQuickTrackingType) {
        case 'quantitative':
          targetValue = _quickTargetNumber;
          unitValue = _quickUnitController.text.trim();
          break;
        case 'time':
          targetValue = _quickTargetDuration.inMinutes; // Store as minutes
          unitValue = 'minutes';
          break;
        case 'binary':
        default:
          targetValue = null;
          unitValue = '';
          break;
      }

      await createTaskWithTracking(
        title: title,
        description: '',
        dueDate: _selectedQuickDueDate,
        priority: 1,
        categoryId: _currentCategoryId!,
        categoryName: categoryName,
        trackingType: _selectedQuickTrackingType ?? 'binary',
        target: targetValue,
        unit: unitValue,
        isRecurring: _quickIsRecurring,
        schedule: _quickIsRecurring ? _quickSchedule : 'daily',
        frequency: _quickIsRecurring ? _quickFrequency : 1,
        specificDays: _quickIsRecurring ? _quickSelectedDays : null,
      );

      // Reset form
      _quickAddController.clear();
      setState(() {
        _selectedQuickDueDate = null;
        _quickTargetNumber = 1;
        _quickTargetDuration = const Duration(hours: 1);
        _quickUnitController.clear();
        _quickIsRecurring = false;
        _quickSchedule = 'daily';
        _quickFrequency = 1;
        _quickSelectedDays = [];
      });

      await _loadTasksForCurrentCategory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Task "$title" created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildAllTasksView() {
    final bucketedTasks = _bucketedTasks;

    if (bucketedTasks.values.every((list) => list.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment,
              size: 64,
              color: FlutterFlowTheme.of(context).secondaryText,
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks found',
              style: FlutterFlowTheme.of(context).titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first task to get started!',
              style: FlutterFlowTheme.of(context).bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _shouldReloadOnReturn = true;
                // Quick add is always expanded now
              },
              child: const Text('Add Task'),
            ),
          ],
        ),
      );
    }

    final slivers = <Widget>[];
    final order = ['Overdue', 'Today', 'Tomorrow', 'This Week', 'Later'];

    for (final bucketName in order) {
      final tasks = bucketedTasks[bucketName] ?? [];
      final visibleTasks = tasks.where((task) {
        final isCompleted = _isTaskCompleted(task);
        return _showCompleted || !isCompleted;
      }).toList();

      if (visibleTasks.isEmpty) continue;

      _applySortToTasks(visibleTasks);

      // Section header
      slivers.add(
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  bucketName,
                  style: FlutterFlowTheme.of(context).titleMedium.override(
                        fontFamily: 'Readex Pro',
                        fontWeight: FontWeight.w600,
                        color: bucketName == 'Overdue' ? Colors.red : null,
                      ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: bucketName == 'Overdue'
                        ? Colors.red.withOpacity(0.1)
                        : FlutterFlowTheme.of(context).primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${visibleTasks.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: bucketName == 'Overdue'
                          ? Colors.red
                          : FlutterFlowTheme.of(context).primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Tasks in this section
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final task = visibleTasks[index];
              return _buildTaskCard(task, _getCategoryColor(task.categoryName));
            },
            childCount: visibleTasks.length,
          ),
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        ...slivers,
        const SliverToBoxAdapter(
          child: SizedBox(height: 140),
        ),
      ],
    );
  }

  Map<String, List<TaskRecord>> get _bucketedTasks {
    final buckets = <String, List<TaskRecord>>{
      'Overdue': <TaskRecord>[],
      'Today': <TaskRecord>[],
      'Tomorrow': <TaskRecord>[],
      'This Week': <TaskRecord>[],
      'Later': <TaskRecord>[],
    };

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final endOfWeek = today.add(Duration(days: 7 - today.weekday));

    for (final task in _tasks) {
      if (!task.isActive) continue;

      final due = task.dueDate;
      if (due == null) {
        buckets['Later']!.add(task);
        continue;
      }

      final dueDate = DateTime(due.year, due.month, due.day);

      if (dueDate.isBefore(today)) {
        buckets['Overdue']!.add(task);
      } else if (dueDate.isAtSameMomentAs(today)) {
        buckets['Today']!.add(task);
      } else if (dueDate.isAtSameMomentAs(tomorrow)) {
        buckets['Tomorrow']!.add(task);
      } else if (!dueDate.isAfter(endOfWeek)) {
        buckets['This Week']!.add(task);
      } else {
        buckets['Later']!.add(task);
      }
    }

    return buckets;
  }

  void _applySortToTasks(List<TaskRecord> tasks) {
    switch (_sortMode) {
      case 'priority':
        tasks.sort((a, b) => b.priority.compareTo(a.priority));
        break;
      case 'dueDate':
        tasks.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        break;
      case 'default':
      default:
        tasks.sort((a, b) {
          final ao = a.hasManualOrder() ? a.manualOrder : 0;
          final bo = b.hasManualOrder() ? b.manualOrder : 0;
          return ao.compareTo(bo);
        });
        break;
    }
  }

  String _getCategoryColor(String categoryName) {
    try {
      final category = _categories.firstWhere((c) => c.name == categoryName);
      return category.color;
    } catch (e) {
      return '#2196F3'; // Default blue color
    }
  }

  Widget _buildCategoryHeader(CategoryRecord category, bool expanded,
      String categoryName, int itemCount) {
    return Container(
      margin: EdgeInsets.fromLTRB(16, 8, 16, expanded ? 0 : 6),
      padding: EdgeInsets.fromLTRB(12, 8, 12, expanded ? 2 : 6),
      decoration: BoxDecoration(
        gradient: FlutterFlowTheme.of(context).neumorphicGradient,
        border: Border.all(
          color: FlutterFlowTheme.of(context).surfaceBorderColor,
          width: 1,
        ),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: expanded ? Radius.zero : const Radius.circular(16),
          bottomRight: expanded ? Radius.zero : const Radius.circular(16),
        ),
        boxShadow: expanded
            ? []
            : FlutterFlowTheme.of(context).neumorphicShadowsRaised,
      ),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                category.name,
                style: FlutterFlowTheme.of(context).titleMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Color(
                      int.parse(category.color.replaceFirst('#', '0xFF'))),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$itemCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FlutterFlowTheme.of(context).primary,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          _buildCategoryWeightStars(category),
          SizedBox(
            height: 20,
            width: 20,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              menuPadding: EdgeInsets.zero,
              tooltip: 'Category options',
              icon: Icon(
                Icons.more_vert,
                size: 20,
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
              onSelected: (value) => _handleCategoryMenuAction(value, category),
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 16),
                      SizedBox(width: 5),
                      Text('Edit category'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 16, color: Colors.red),
                      SizedBox(width: 5),
                      Text('Delete category',
                          style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              if (mounted) {
                setState(() {
                  _categoryExpanded[categoryName] = !expanded;
                });
              }
            },
            child: Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskInstanceCard(TaskInstanceRecord instance) {
    final isCompleted = instance.status == 'completed';
    final categoryColor = _getCategoryColor(instance.templateCategoryName);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
          gradient: FlutterFlowTheme.of(context).neumorphicGradientSubtle,
          border: Border(
            left: BorderSide(
                color: FlutterFlowTheme.of(context).surfaceBorderColor,
                width: 1),
            right: BorderSide(
                color: FlutterFlowTheme.of(context).surfaceBorderColor,
                width: 1),
            top: BorderSide.none,
          )),
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        decoration: BoxDecoration(
          gradient: FlutterFlowTheme.of(context).neumorphicGradientSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: FlutterFlowTheme.of(context).surfaceBorderColor,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: Color(
                          int.parse(categoryColor.replaceFirst('#', '0xFF'))),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 5),
                  SizedBox(
                    width: 36,
                    child:
                        Center(child: _buildTaskInstanceLeftControls(instance)),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            instance.templateName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .override(
                                  fontFamily: 'Readex Pro',
                                  fontWeight: FontWeight.w600,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                  color: isCompleted
                                      ? FlutterFlowTheme.of(context)
                                          .secondaryText
                                      : FlutterFlowTheme.of(context)
                                          .primaryText,
                                ),
                          ),
                        ),
                        if (instance.templateTrackingType != 'binary') ...[
                          const SizedBox(width: 5),
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 160),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context)
                                    .secondaryBackground,
                                border: Border.all(
                                  color: FlutterFlowTheme.of(context).alternate,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _getInstanceProgressDisplayText(instance),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FlutterFlowTheme.of(context)
                                    .bodySmall
                                    .override(
                                      fontFamily: 'Readex Pro',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      lineHeight: 1.05,
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 5),
                      _buildTaskInstancePriorityStars(instance),
                      const SizedBox(width: 5),
                      GestureDetector(
                        onTap: () => _snoozeTaskInstance(instance),
                        child: const Icon(Icons.snooze, size: 20),
                      ),
                      const SizedBox(width: 5),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, size: 20),
                        onSelected: (value) =>
                            _handleTaskInstanceMenuAction(value, instance),
                        itemBuilder: (context) => [
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 16),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'duplicate',
                            child: Row(
                              children: [
                                Icon(Icons.copy, size: 16),
                                SizedBox(width: 8),
                                Text('Duplicate'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 16, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete',
                                    style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (instance.templateTrackingType != 'binary') ...[
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: Color(
                          int.parse(categoryColor.replaceFirst('#', '0xFF'))),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Stack(
                    children: [
                      // Background track (always full width) - white fill
                      Container(
                        width: double.infinity,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Progress fill
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor:
                            _getInstanceProgress(instance).clamp(0.0, 1.0),
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Color(int.parse(
                                categoryColor.replaceFirst('#', '0xFF'))),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTaskInstanceLeftControls(TaskInstanceRecord instance) {
    final isCompleted = instance.status == 'completed';

    switch (instance.templateTrackingType) {
      case 'binary':
        return SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: isCompleted,
            onChanged: (value) => _toggleInstanceCompletion(instance),
            activeColor: _getTaskPriorityColor(instance.templatePriority),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      case 'quantitative':
        return GestureDetector(
          onLongPress: () => _showInstanceQuantControlsMenu(instance),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primaryText,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _incrementInstance(instance),
                child: const Icon(
                  Icons.add,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      case 'time':
        final bool isActive = instance.isTimerActive == true;
        return Builder(
          builder: (btnCtx) => GestureDetector(
            onLongPress: () => _showInstanceTimerControlsMenu(btnCtx, instance),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isActive
                    ? FlutterFlowTheme.of(context).error
                    : FlutterFlowTheme.of(context).primaryText,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _toggleInstanceTimer(instance),
                  child: Icon(
                    isActive ? Icons.stop : Icons.play_arrow,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTaskInstancePriorityStars(TaskInstanceRecord instance) {
    final current = instance.templatePriority;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final level = i + 1;
        final filled = current >= level;
        return Icon(
          filled ? Icons.star : Icons.star_border,
          size: 24,
          color: filled
              ? Colors.amber
              : FlutterFlowTheme.of(context).secondaryText.withOpacity(0.35),
        );
      }),
    );
  }

  String _getInstanceProgressDisplayText(TaskInstanceRecord instance) {
    switch (instance.templateTrackingType) {
      case 'quantitative':
        final current = instance.currentValue is int
            ? instance.currentValue as int
            : int.tryParse(instance.currentValue.toString()) ?? 0;
        final target = instance.templateTarget is int
            ? instance.templateTarget as int
            : int.tryParse(instance.templateTarget.toString()) ?? 1;
        final unit =
            instance.templateUnit.isNotEmpty ? instance.templateUnit : 'units';
        return '$current / $target $unit';
      case 'time':
        // For time tracking, use live accumulated time if timer is active
        final instanceId = instance.reference.id;
        final currentMs = instance.isTimerActive == true
            ? _getLiveAccumulatedTime(
                instanceId, instance.accumulatedTime, instance.timerStartTime)
            : instance.accumulatedTime;
        final currentDuration = Duration(milliseconds: currentMs);

        final targetMinutes = instance.templateTarget is int
            ? instance.templateTarget as int
            : int.tryParse(instance.templateTarget.toString()) ?? 0;
        final targetDuration = Duration(minutes: targetMinutes);

        return '${_formatDuration(currentDuration)} / ${_formatDuration(targetDuration)}';
      default:
        return '';
    }
  }

  Future<void> _toggleInstanceCompletion(TaskInstanceRecord instance) async {
    try {
      final newStatus =
          instance.status == 'completed' ? 'pending' : 'completed';
      await instance.reference.update({'status': newStatus});
      _loadTasksForCurrentCategory(); // Refresh the list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  Future<void> _incrementInstance(TaskInstanceRecord instance) async {
    try {
      final current = instance.currentValue is int
          ? instance.currentValue as int
          : int.tryParse(instance.currentValue.toString()) ?? 0;
      final newValue = current + 1;

      await TaskInstanceService.updateInstanceProgress(
        instanceId: instance.reference.id,
        instanceType: 'task',
        currentValue: newValue,
      );
      _loadTasksForCurrentCategory(); // Refresh the list

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${instance.templateName}: $newValue ${instance.templateUnit}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating progress: $e')),
        );
      }
    }
  }

  Future<void> _toggleInstanceTimer(TaskInstanceRecord instance) async {
    try {
      final isActive = instance.isTimerActive == true;
      final instanceId = instance.reference.id;

      if (isActive) {
        // Stop timer
        _stopLiveTimer(instanceId);

        final now = DateTime.now();
        final startTime = instance.timerStartTime ?? now;
        final additionalTime = now.difference(startTime).inMilliseconds;
        final newAccumulatedTime = instance.accumulatedTime + additionalTime;

        await TaskInstanceService.updateInstanceProgress(
          instanceId: instanceId,
          instanceType: 'task',
          isTimerActive: false,
          timerStartTime: null,
          accumulatedTime: newAccumulatedTime,
          currentValue:
              newAccumulatedTime, // Store as milliseconds, not Duration
        );
      } else {
        // Start timer
        await TaskInstanceService.updateInstanceProgress(
          instanceId: instanceId,
          instanceType: 'task',
          isTimerActive: true,
          timerStartTime: DateTime.now(),
        );

        // Start live timer
        _startLiveTimer(instanceId, true);
      }

      _loadTasksForCurrentCategory(); // Refresh the list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling timer: $e')),
        );
      }
    }
  }

  Future<void> _showInstanceTimerControlsMenu(
      BuildContext anchorContext, TaskInstanceRecord instance) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);

    final hasAccumulatedTime = instance.accumulatedTime > 0;
    final isActive = instance.isTimerActive == true;

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
      items: [
        if (isActive)
          const PopupMenuItem<String>(
            value: 'stop',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.stop, size: 18),
                SizedBox(width: 8),
                Text('Stop Timer')
              ],
            ),
          )
        else
          const PopupMenuItem<String>(
            value: 'start',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.play_arrow, size: 18),
                SizedBox(width: 8),
                Text('Start Timer')
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'reset',
          enabled: hasAccumulatedTime,
          height: 36,
          child: Row(
            children: [
              Icon(Icons.refresh,
                  size: 18, color: hasAccumulatedTime ? null : Colors.grey),
              const SizedBox(width: 8),
              Text('Reset Timer',
                  style:
                      TextStyle(color: hasAccumulatedTime ? null : Colors.grey))
            ],
          ),
        ),
      ],
    );

    if (selected == 'start' || selected == 'stop') {
      await _toggleInstanceTimer(instance);
    } else if (selected == 'reset' && hasAccumulatedTime) {
      await _resetInstanceTimer(instance);
    }
  }

  Future<void> _showInstanceQuantControlsMenu(
      TaskInstanceRecord instance) async {
    final currentValue = instance.currentValue is int
        ? instance.currentValue as int
        : int.tryParse(instance.currentValue.toString()) ?? 0;
    final canDecrement = currentValue > 0;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          100, 100, 100, 100), // Will be positioned by caller
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'inc',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 8),
              Text('Increase')
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'dec',
          enabled: canDecrement,
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.remove, size: 18),
              SizedBox(width: 8),
              Text('Decrease')
            ],
          ),
        ),
      ],
    );

    if (selected == 'inc') {
      await _incrementInstance(instance);
    } else if (selected == 'dec' && canDecrement) {
      await _decrementInstance(instance);
    }
  }

  Future<void> _decrementInstance(TaskInstanceRecord instance) async {
    try {
      final current = instance.currentValue is int
          ? instance.currentValue as int
          : int.tryParse(instance.currentValue.toString()) ?? 0;
      final newValue = (current - 1).clamp(0, 999999);

      await TaskInstanceService.updateInstanceProgress(
        instanceId: instance.reference.id,
        instanceType: 'task',
        currentValue: newValue,
      );
      _loadTasksForCurrentCategory(); // Refresh the list

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${instance.templateName}: $newValue ${instance.templateUnit}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating progress: $e')),
        );
      }
    }
  }

  Future<void> _snoozeTaskInstance(TaskInstanceRecord instance) async {
    // Implementation for snoozing task instance - placeholder for now
  }

  Future<void> _handleTaskInstanceMenuAction(
      String action, TaskInstanceRecord instance) async {
    switch (action) {
      case 'edit':
        // Implementation for editing task instance
        break;
      case 'duplicate':
        // Implementation for duplicating task instance
        break;
      case 'delete':
        // Implementation for deleting task instance
        break;
    }
  }

  double _getInstanceProgress(TaskInstanceRecord instance) {
    if (instance.templateTarget == null) {
      return 0.0;
    }

    switch (instance.templateTrackingType) {
      case 'quantitative':
        final current = instance.currentValue is int
            ? instance.currentValue as int
            : int.tryParse(instance.currentValue.toString()) ?? 0;
        final target = instance.templateTarget is int
            ? instance.templateTarget as int
            : int.tryParse(instance.templateTarget.toString()) ?? 1;
        if (target <= 0) return 0.0;
        return (current / target).clamp(0.0, 1.0);

      case 'time':
        // For time tracking, use live accumulated time if timer is active
        final instanceId = instance.reference.id;
        final currentMs = instance.isTimerActive == true
            ? _getLiveAccumulatedTime(
                instanceId, instance.accumulatedTime, instance.timerStartTime)
            : instance.accumulatedTime;
        final targetMinutes = instance.templateTarget is int
            ? instance.templateTarget as int
            : int.tryParse(instance.templateTarget.toString()) ?? 0;
        final targetMs =
            targetMinutes * 60 * 1000; // Convert minutes to milliseconds

        if (targetMs <= 0) return 0.0;
        return (currentMs / targetMs).clamp(0.0, 1.0);

      default:
        return 0.0;
    }
  }

  Widget _buildCategoryWeightStars(CategoryRecord category) {
    final current = category.weight.round().clamp(1, 3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final level = i + 1;
        final filled = current >= level;
        return GestureDetector(
          onTap: () async {
            try {
              final next = current % 3 + 1;
              await updateCategory(
                categoryId: category.reference.id,
                weight: next.toDouble(),
              );
              await _loadTasksForCurrentCategory();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error updating category weight: $e')),
              );
            }
          },
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: 24,
            color: filled
                ? Colors.amber
                : FlutterFlowTheme.of(context).secondaryText.withOpacity(0.35),
          ),
        );
      }),
    );
  }

  void _handleCategoryMenuAction(String action, CategoryRecord category) {
    switch (action) {
      case 'edit':
        _showEditCategoryDialog(category);
        break;
      case 'delete':
        _showDeleteCategoryConfirmation(category);
        break;
    }
  }

  void _showEditCategoryDialog(CategoryRecord category) {
    showDialog(
      context: context,
      builder: (context) => CreateCategory(category: category),
    );
  }

  void _showDeleteCategoryConfirmation(CategoryRecord category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Are you sure you want to delete "${category.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await deleteCategory(category.reference.id,
                    userId: currentUserUid);
                await _loadTasksForCurrentCategory();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Category "${category.name}" deleted successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                print('Error deleting category: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting category: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
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

  Widget _buildTaskCard(TaskRecord task, String categoryColor) {
    final isCompleted = _isTaskCompleted(task);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
          gradient: FlutterFlowTheme.of(context).neumorphicGradientSubtle,
          border: Border(
            left: BorderSide(
                color: FlutterFlowTheme.of(context).surfaceBorderColor,
                width: 1),
            right: BorderSide(
                color: FlutterFlowTheme.of(context).surfaceBorderColor,
                width: 1),
            top: BorderSide.none,
          )),
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        decoration: BoxDecoration(
          gradient: FlutterFlowTheme.of(context).neumorphicGradientSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: FlutterFlowTheme.of(context).surfaceBorderColor,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: Color(
                          int.parse(categoryColor.replaceFirst('#', '0xFF'))),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 5),
                  SizedBox(
                    width: 36,
                    child: Center(child: _buildTaskLeftControls(task)),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .override(
                                  fontFamily: 'Readex Pro',
                                  fontWeight: FontWeight.w600,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                  color: isCompleted
                                      ? FlutterFlowTheme.of(context)
                                          .secondaryText
                                      : FlutterFlowTheme.of(context)
                                          .primaryText,
                                ),
                          ),
                        ),
                        if (task.trackingType != 'binary') ...[
                          const SizedBox(width: 5),
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 160),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context)
                                    .secondaryBackground,
                                border: Border.all(
                                  color: FlutterFlowTheme.of(context).alternate,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _getTaskProgressDisplayText(task),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FlutterFlowTheme.of(context)
                                    .bodySmall
                                    .override(
                                      fontFamily: 'Readex Pro',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      lineHeight: 1.05,
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 5),
                      _buildTaskPriorityStars(task),
                      const SizedBox(width: 5),
                      GestureDetector(
                        onTap: () => _snoozeTask(task),
                        child: const Icon(Icons.snooze, size: 20),
                      ),
                      const SizedBox(width: 5),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, size: 20),
                        onSelected: (value) =>
                            _handleTaskMenuAction(value, task),
                        itemBuilder: (context) => [
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 16),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'duplicate',
                            child: Row(
                              children: [
                                Icon(Icons.copy, size: 16),
                                SizedBox(width: 8),
                                Text('Duplicate'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 16, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete',
                                    style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (task.trackingType != 'binary') ...[
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: Color(
                          int.parse(categoryColor.replaceFirst('#', '0xFF'))),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Stack(
                    children: [
                      // Background track (always full width) - white fill
                      Container(
                        width: double.infinity,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Progress fill
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _getTaskProgress(task).clamp(0.0, 1.0),
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Color(int.parse(
                                categoryColor.replaceFirst('#', '0xFF'))),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTaskLeftControls(TaskRecord task) {
    final isCompleted = _isTaskCompleted(task);

    switch (task.trackingType) {
      case 'binary':
        return SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: isCompleted,
            onChanged: (value) => _toggleTaskCompletion(task),
            activeColor: _getTaskPriorityColor(task.priority),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      case 'quantitative':
        return GestureDetector(
          onLongPress: () => _showTaskQuantControlsMenu(task),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primaryText,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _incrementTask(task),
                child: const Icon(
                  Icons.add,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      case 'time':
        final bool isActive = task.isTimerActive;
        return Builder(
          builder: (btnCtx) => GestureDetector(
            onLongPress: () => _showTaskTimerControlsMenu(btnCtx, task),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isActive
                    ? FlutterFlowTheme.of(context).error
                    : FlutterFlowTheme.of(context).primaryText,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _toggleTimer(task),
                  child: Icon(
                    isActive ? Icons.stop : Icons.play_arrow,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTaskPriorityStars(TaskRecord task) {
    final current = task.priority;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final level = i + 1;
        final filled = current >= level;
        return GestureDetector(
          onTap: () => _updateTaskPriority(task, level),
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: 24,
            color: filled
                ? Colors.amber
                : FlutterFlowTheme.of(context).secondaryText.withOpacity(0.35),
          ),
        );
      }),
    );
  }

  Color _getTaskPriorityColor(int priority) {
    switch (priority) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getTaskProgressDisplayText(TaskRecord task) {
    switch (task.trackingType) {
      case 'quantitative':
        final current = task.currentValue is int
            ? task.currentValue as int
            : int.tryParse(task.currentValue.toString()) ?? 0;
        final target = task.target is int
            ? task.target as int
            : int.tryParse(task.target.toString()) ?? 1;
        final unit = task.unit.isNotEmpty ? task.unit : 'units';
        return '$current / $target $unit';
      case 'time':
        // For time tracking, use live accumulated time if timer is active
        final taskId = task.reference.id;
        final currentMs = task.isTimerActive
            ? _getLiveAccumulatedTime(
                taskId, task.accumulatedTime, task.timerStartTime)
            : task.accumulatedTime;
        final currentDuration = Duration(milliseconds: currentMs);

        final targetMinutes = task.target is int
            ? task.target as int
            : int.tryParse(task.target.toString()) ?? 0;
        final targetDuration = Duration(minutes: targetMinutes);

        return '${_formatDuration(currentDuration)} / ${_formatDuration(targetDuration)}';
      default:
        return '';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  Future<void> _showTaskQuantControlsMenu(TaskRecord task) async {
    final currentValue = (task.currentValue ?? 0) as num;
    final canDecrement = currentValue > 0;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          100, 100, 100, 100), // Will be positioned by caller
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'inc',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 8),
              Text('Increase')
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'dec',
          enabled: canDecrement,
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.remove, size: 18),
              SizedBox(width: 8),
              Text('Decrease')
            ],
          ),
        ),
      ],
    );

    if (selected == 'inc') {
      await _incrementTask(task);
    } else if (selected == 'dec' && canDecrement) {
      await _decrementTask(task);
    }
  }

  Future<void> _showTaskTimerControlsMenu(
      BuildContext anchorContext, TaskRecord task) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);

    final hasAccumulatedTime = task.accumulatedTime > 0;

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
      items: [
        if (task.isTimerActive)
          const PopupMenuItem<String>(
            value: 'stop',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.stop, size: 18),
                SizedBox(width: 8),
                Text('Stop Timer')
              ],
            ),
          )
        else
          const PopupMenuItem<String>(
            value: 'start',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.play_arrow, size: 18),
                SizedBox(width: 8),
                Text('Start Timer')
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'reset',
          enabled: hasAccumulatedTime,
          height: 36,
          child: Row(
            children: [
              Icon(Icons.refresh,
                  size: 18, color: hasAccumulatedTime ? null : Colors.grey),
              const SizedBox(width: 8),
              Text('Reset Timer',
                  style:
                      TextStyle(color: hasAccumulatedTime ? null : Colors.grey))
            ],
          ),
        ),
      ],
    );

    if (selected == 'start' || selected == 'stop') {
      await _toggleTimer(task);
    } else if (selected == 'reset' && hasAccumulatedTime) {
      await _resetTaskTimer(task);
    }
  }

  Future<void> _decrementTask(TaskRecord task) async {
    try {
      final currentValue = (task.currentValue ?? 0) as num;
      final newValue = (currentValue - 1).clamp(0, double.infinity);

      await updateTask(
        taskRef: task.reference,
        currentValue: newValue,
      );
      await _loadTasksForCurrentCategory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${task.name}: $newValue ${task.unit}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  Future<void> _resetTaskTimer(TaskRecord task) async {
    try {
      final taskId = task.reference.id;

      // Stop live timer
      _stopLiveTimer(taskId);

      // Stop timer if it's running
      if (task.isTimerActive) {
        await updateTask(
          taskRef: task.reference,
          isTimerActive: false,
          timerStartTime: null,
        );
      }

      // Reset accumulated time and current value
      await updateTask(
        taskRef: task.reference,
        accumulatedTime: 0,
        currentValue: 0,
      );

      await _loadTasksForCurrentCategory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${task.name} timer reset'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting timer: $e')),
        );
      }
    }
  }

  Future<void> _resetInstanceTimer(TaskInstanceRecord instance) async {
    try {
      final instanceId = instance.reference.id;

      // Stop live timer
      _stopLiveTimer(instanceId);

      // Stop timer if it's running and reset accumulated time
      await TaskInstanceService.updateInstanceProgress(
        instanceId: instanceId,
        instanceType: 'task',
        isTimerActive: false,
        timerStartTime: null,
        accumulatedTime: 0,
        currentValue: 0,
      );

      _loadTasksForCurrentCategory(); // Refresh the list

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${instance.templateName} timer reset'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting timer: $e')),
        );
      }
    }
  }

  Future<void> _updateTaskPriority(TaskRecord task, int newPriority) async {
    try {
      await task.reference.update({'priority': newPriority});
      _loadTasksForCurrentCategory(); // Refresh the list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating priority: $e')),
        );
      }
    }
  }

  double _getTaskProgress(TaskRecord task) {
    if (task.target == null) {
      return 0.0;
    }

    switch (task.trackingType) {
      case 'quantitative':
        final current = task.currentValue is int
            ? task.currentValue as int
            : int.tryParse(task.currentValue.toString()) ?? 0;
        final target = task.target is int
            ? task.target as int
            : int.tryParse(task.target.toString()) ?? 1;
        if (target <= 0) return 0.0;
        return (current / target).clamp(0.0, 1.0);

      case 'time':
        // For time tracking, use live accumulated time if timer is active
        final taskId = task.reference.id;
        final currentMs = task.isTimerActive
            ? _getLiveAccumulatedTime(
                taskId, task.accumulatedTime, task.timerStartTime)
            : task.accumulatedTime;
        final targetMinutes = task.target is int
            ? task.target as int
            : int.tryParse(task.target.toString()) ?? 0;
        final targetMs =
            targetMinutes * 60 * 1000; // Convert minutes to milliseconds

        if (targetMs <= 0) return 0.0;
        return (currentMs / targetMs).clamp(0.0, 1.0);

      default:
        return 0.0;
    }
  }

  Future<void> _toggleTimer(TaskRecord task) async {
    try {
      final taskId = task.reference.id;

      if (task.isTimerActive) {
        // Stop timer
        _stopLiveTimer(taskId);

        final now = DateTime.now();
        final startTime = task.timerStartTime ?? now;
        final additionalTime = now.difference(startTime).inMilliseconds;
        final newAccumulatedTime = task.accumulatedTime + additionalTime;

        await updateTask(
          taskRef: task.reference,
          isTimerActive: false,
          timerStartTime: null,
          accumulatedTime: newAccumulatedTime,
          currentValue:
              newAccumulatedTime, // Store as milliseconds, not Duration
        );
      } else {
        // Start timer
        await updateTask(
          taskRef: task.reference,
          isTimerActive: true,
          timerStartTime: DateTime.now(),
        );

        // Start live timer
        _startLiveTimer(taskId, false);
      }
      await _loadTasksForCurrentCategory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling timer: $e')),
        );
      }
    }
  }

  Future<void> _incrementTask(TaskRecord task) async {
    try {
      final currentValue = (task.currentValue ?? 0) as num;
      final newValue = currentValue + 1;

      await updateTask(
        taskRef: task.reference,
        currentValue: newValue,
      );
      await _loadTasksForCurrentCategory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${task.name}: $newValue ${task.unit}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  Future<void> _toggleTaskCompletion(TaskRecord task) async {
    try {
      final isCompleted = _isTaskCompleted(task);
      final newStatus = isCompleted ? 'incomplete' : 'complete';

      await updateTask(
        taskRef: task.reference,
        status: newStatus,
        completedTime: isCompleted ? null : DateTime.now(),
      );
      await _loadTasksForCurrentCategory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('${task.name} ${isCompleted ? 'reopened' : 'completed'}!'),
            backgroundColor: isCompleted ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  Future<void> _snoozeTask(TaskRecord task) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    try {
      await updateTask(
        taskRef: task.reference,
        dueDate: tomorrow,
      );
      await _loadTasksForCurrentCategory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${task.name} snoozed until tomorrow'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error snoozing task: $e')),
        );
      }
    }
  }

  void _handleTaskMenuAction(String action, TaskRecord task) {
    switch (action) {
      case 'edit':
        _editTask(task);
        break;
      case 'duplicate':
        _duplicateTask(task);
        break;
      case 'delete':
        _deleteTask(task);
        break;
    }
  }

  void _editTask(TaskRecord task) {
    // Navigate to edit task page
    print('Edit task: ${task.name}');
  }

  Future<void> _duplicateTask(TaskRecord task) async {
    try {
      await createTask(
        title: '${task.name} (Copy)',
        description: task.description,
        dueDate: task.dueDate,
        priority: task.priority,
        categoryId: task.categoryId,
        categoryName: task.categoryName,
        isRecurring: task.isRecurring,
        schedule: task.schedule,
        frequency: task.frequency,
        specificDays: task.specificDays,
      );
      await _loadTasksForCurrentCategory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${task.name} duplicated!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error duplicating task: $e')),
        );
      }
    }
  }

  Future<void> _deleteTask(TaskRecord task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await deleteTask(task.reference);
        await _loadTasksForCurrentCategory();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${task.name} deleted'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting task: $e')),
          );
        }
      }
    }
  }

  void _onTabChanged(int index) {
    if (index < _tabNames.length) {
      final tabName = _tabNames[index];
      CategoryRecord? category;

      if (tabName == "Inbox") {
        // Find the inbox category (system category)
        category = _categories.firstWhere(
          (c) => c.name == 'Inbox' && c.isSystemCategory,
          orElse: () => _categories.firstWhere(
            (c) => c.name == 'Inbox',
            orElse: () => _categories.first,
          ),
        );
      } else {
        // Find user-created category by name
        category = _categories.firstWhere(
          (c) => c.name == tabName && !c.isSystemCategory,
          orElse: () => _categories.firstWhere(
            (c) => c.name == tabName,
            orElse: () => _categories.first,
          ),
        );
      }

      setState(() {
        _currentCategoryId = category?.reference.id;
      });

      // Load tasks for the new category
      _loadTasksForCurrentCategory();
    }
  }

  Future<void> _showAddCategoryDialog(BuildContext context) async {
    final TextEditingController categoryController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
          contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Center(
                      child: Text(
                        "Add Category",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: FlutterFlowTheme.of(context).primaryText,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(
                  hintText: "Enter category name",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final newName = categoryController.text.trim();
                    if (newName.isEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Category name cannot be empty"),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                    }

                    final exists = _categories.any(
                      (c) => c.name.toLowerCase() == newName.toLowerCase(),
                    );
                    if (exists) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Category already exists"),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                    }

                    // Prevent creating categories with reserved names
                    if (newName.toLowerCase() == "inbox") {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text("'Inbox' is a reserved category name"),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                    }

                    try {
                      await createCategory(
                        name: newName,
                        description: null,
                        weight: 1,
                        categoryType: 'task',
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Category "$newName" created successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error creating category: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlutterFlowTheme.of(context).primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    "Add",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              )
            ],
          ),
        );
      },
    );
  }
}
