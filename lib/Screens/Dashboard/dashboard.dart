import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/habit_tracking_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/backend/schema/task_record.dart';
import 'package:habit_tracker/Helper/utils/floating_timer.dart';
import 'package:habit_tracker/Helper/utils/neumorphic_container.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Screens/Dashboard/compact_habit_item.dart';
import 'dart:async';

class Dashboard extends StatefulWidget {
  final bool showCompleted;
  const Dashboard({super.key, required this.showCompleted});

  @override
  _DashboardState createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  List<HabitRecord> _habits = [];
  List<CategoryRecord> _categories = [];
  List<TaskRecord> _tasks = [];
  List<TaskRecord> _tasksTodayOrder = [];
  final Map<String, bool> _categoryExpanded = {};
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  bool _weeklyGoalsExpanded = false;
  bool _tasksExpanded = true;
  bool _shouldReloadOnReturn = false;
  double _netImpactScore = 0;
  double _dailyCompletionPercent = 0;
  int _completedHabits = 0;
  int _totalHabits = 0;
  int _thriveScore = 0;
  late bool _showCompleted;

  @override
  void initState() {
    super.initState();
    _showCompleted = widget.showCompleted;
    _loadHabits();
    NotificationCenter.addObserver(this, 'showCompleted', (param) {
      if (param is bool && mounted) {
        setState(() {
          _showCompleted = param;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh when returning to this page so newly created habits appear
    if (_didInitialDependencies) {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent && _shouldReloadOnReturn) {
        _shouldReloadOnReturn = false;
        _loadHabits();
      }
    } else {
      _didInitialDependencies = true;
    }
  }

  // Scroll listener removed with bottom bar

  Future<void> _loadHabits() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final habits = await queryHabitsRecordOnce(userId: userId);
        final categories = await queryCategoriesRecordOnce(userId: userId);
        final tasks = await queryTasksRecordOnce(userId: userId);

        setState(() {
          _habits = habits;
          _categories = categories;
          _tasks = tasks;
          _recomputeTasksTodayOrder();
          _calculateScores();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading habits: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _recomputeTasksTodayOrder() {
    // Get tasks from TaskRecord collection
    final tasksFromTaskCollection =
        _tasks.where((t) => t.isActive && t.status != 'done').toList();

    // Get tasks from HabitRecord collection (items with isRecurring = false)
    final tasksFromHabitCollection = _habits
        .where((h) => !h.isRecurring && h.isActive && h.taskStatus != 'done')
        .map((h) => _convertHabitRecordToTaskRecord(h))
        .toList();

    // Combine both sources
    final allTasks = [...tasksFromTaskCollection, ...tasksFromHabitCollection];

    // Sort by manual order
    allTasks.sort((a, b) {
      final ao =
          a.hasManualOrder() ? a.manualOrder : 1000000 + allTasks.indexOf(a);
      final bo =
          b.hasManualOrder() ? b.manualOrder : 1000000 + allTasks.indexOf(b);
      return ao.compareTo(bo);
    });
    _tasksTodayOrder = allTasks;
  }

  // Helper method to convert HabitRecord (task) to TaskRecord for display purposes
  TaskRecord _convertHabitRecordToTaskRecord(HabitRecord habit) {
    final taskData = createTaskRecordData(
      title: habit.name,
      description: habit.description,
      status: habit.taskStatus,
      dueDate: habit.dueDate,
      priority: habit.priority,
      isActive: habit.isActive,
      createdTime: habit.createdTime,
      categoryId: habit.categoryId,
      categoryName: habit.categoryName,
      manualOrder: habit.manualOrder,
    );
    return TaskRecord.getDocumentFromData(taskData, habit.reference);
  }

  void _calculateScores() {
    // Only count actual habits (isRecurring = true) for habit completion metrics
    final actualHabits = _habits.where((h) => h.isRecurring).toList();
    _totalHabits = actualHabits.length;
    _completedHabits = 0;
    _netImpactScore = 0;

    for (final habit in actualHabits) {
      final isCompleted = HabitTrackingUtil.isCompletedToday(habit);

      if (isCompleted) {
        _completedHabits++;

        // Calculate impact score based on impact level
        final impactPoints = _getImpactPoints(habit.impactLevel);
        _netImpactScore += impactPoints;
      }
    }

    _dailyCompletionPercent =
        _totalHabits > 0 ? (_completedHabits / _totalHabits) * 100 : 0;

    // Thrive score is cumulative - for now using a placeholder
    _thriveScore = 1247; // TODO: Calculate from historical data
  }

  double _getImpactPoints(String impactLevel) {
    switch (impactLevel) {
      case 'Low':
        return 1.0;
      case 'Medium':
        return 2.0;
      case 'High':
        return 3.0;
      case 'Very High':
        return 5.0;
      default:
        return 2.0;
    }
  }

  Widget _buildScoreBar() {
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Text(
              DateFormat('EEEE, MMMM d, y').format(DateTime.now()),
              style: FlutterFlowTheme.of(context).titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
            ),
            const SizedBox(height: 12),

            // Score metrics row
            Row(
              children: [
                // Net Impact Score
                Expanded(
                  child: NeumorphicContainer(
                    padding: const EdgeInsets.all(12),
                    radius: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Net Impact',
                          style:
                              FlutterFlowTheme.of(context).bodySmall.override(
                                    fontFamily: 'Readex Pro',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _netImpactScore >= 0
                              ? '+${_netImpactScore.toStringAsFixed(1)}'
                              : _netImpactScore.toStringAsFixed(1),
                          style:
                              FlutterFlowTheme.of(context).titleMedium.override(
                                    fontFamily: 'Readex Pro',
                                    color: _netImpactScore >= 0
                                        ? Colors.green
                                        : Colors.red,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Daily Completion
                Expanded(
                  child: NeumorphicContainer(
                    padding: const EdgeInsets.all(12),
                    radius: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Completion',
                          style:
                              FlutterFlowTheme.of(context).bodySmall.override(
                                    fontFamily: 'Readex Pro',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_dailyCompletionPercent.toStringAsFixed(0)}%',
                          style:
                              FlutterFlowTheme.of(context).titleMedium.override(
                                    fontFamily: 'Readex Pro',
                                    color: FlutterFlowTheme.of(context).primary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_completedHabits/$_totalHabits',
                          style: FlutterFlowTheme.of(context)
                              .bodySmall
                              .override(
                                fontFamily: 'Readex Pro',
                                fontSize: 10,
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Thrive Score
                Expanded(
                  child: NeumorphicContainer(
                    padding: const EdgeInsets.all(12),
                    radius: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thrive',
                          style:
                              FlutterFlowTheme.of(context).bodySmall.override(
                                    fontFamily: 'Readex Pro',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _thriveScore.toString(),
                          style:
                              FlutterFlowTheme.of(context).titleMedium.override(
                                    fontFamily: 'Readex Pro',
                                    color: FlutterFlowTheme.of(context).primary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<HabitRecord>> get _groupedHabits {
    final grouped = <String, List<HabitRecord>>{};

    for (final habit in _habits) {
      // Skip tasks (items with isRecurring = false) - they should appear under Tasks section only
      if (!habit.isRecurring) continue;

      if (!_shouldShowInTodayMain(habit)) continue;

      final isCompleted = HabitTrackingUtil.isCompletedToday(habit);
      if (!_showCompleted && isCompleted) continue;

      final categoryName =
          habit.categoryName.isNotEmpty ? habit.categoryName : 'Uncategorized';
      (grouped[categoryName] ??= []).add(habit);
    }

    return grouped;
  }

  // Weekly goals (Today): flexible weekly habits not promoted to main list,
  // still having remaining completions this week
  Map<String, List<HabitRecord>> get _groupedWeeklyGoals {
    final grouped = <String, List<HabitRecord>>{};
    for (final habit in _habits) {
      // Skip tasks (items with isRecurring = false) - they should appear under Tasks section only
      if (!habit.isRecurring) continue;

      if (!_isFlexibleWeekly(habit)) continue;
      if (_shouldShowInTodayMain(habit)) continue; // promoted
      if (_remainingCompletionsThisWeek(habit) <= 0) continue;
      // skip if user explicitly skipped today
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (habit.skippedDates.any((d) =>
          d.year == today.year &&
          d.month == today.month &&
          d.day == today.day)) {
        continue;
      }

      final categoryName =
          habit.categoryName.isNotEmpty ? habit.categoryName : 'Uncategorized';
      (grouped[categoryName] ??= []).add(habit);
    }
    return grouped;
  }

  bool _isFlexibleWeekly(HabitRecord habit) {
    return habit.schedule == 'weekly' && habit.specificDays.isEmpty;
  }

  int _completedCountThisWeek(HabitRecord habit) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    return habit.completedDates.where((date) {
      final d = DateTime(date.year, date.month, date.day);
      return !d.isBefore(weekStart) && !d.isAfter(weekEnd);
    }).length;
  }

  int _daysRemainingThisWeekInclusiveToday() {
    final now = DateTime.now();
    return DateTime.sunday - now.weekday + 1; // inclusive of today
  }

  int _remainingCompletionsThisWeek(HabitRecord habit) {
    final done = _completedCountThisWeek(habit);
    final remaining = habit.weeklyTarget - done;
    return remaining > 0 ? remaining : 0;
  }

  bool _shouldShowInTodayMain(HabitRecord habit) {
    // Respect explicit skip
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (habit.skippedDates.any((d) =>
        d.year == today.year && d.month == today.month && d.day == today.day)) {
      return false;
    }

    // Respect snoozedUntil: hide until the day after snoozedUntil
    if (habit.hasSnoozedUntil()) {
      final until = habit.snoozedUntil!;
      final untilDate = DateTime(until.year, until.month, until.day);
      if (!today.isAfter(untilDate)) {
        // Today is on or before snoozedUntil -> don't show
        return false;
      }
    }

    if (habit.schedule == 'daily') return true;

    if (habit.schedule == 'weekly' && habit.specificDays.isNotEmpty) {
      return habit.specificDays.contains(now.weekday);
    }

    if (_isFlexibleWeekly(habit)) {
      final remaining = _remainingCompletionsThisWeek(habit);
      if (remaining <= 0) return false;
      final daysRemaining = _daysRemainingThisWeekInclusiveToday();
      // Promote to Today if must-day (==) or behind (>)
      return remaining >= daysRemaining;
    }

    // For other schedules (monthly, etc.) not shown on Today for now
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      child: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildScoreBar(),
                    Expanded(
                      child: _buildDailyView(),
                    ),
                  ],
                ),
          FloatingTimer(
            activeHabits: _habits,
            onRefresh: _loadHabits,
            onHabitUpdated: (updated) => _updateHabitInLocalState(updated),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyView() {
    final weeklyGoals = _groupedWeeklyGoals;
    if (_groupedHabits.isEmpty && weeklyGoals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.list_alt,
              size: 64,
              color: FlutterFlowTheme.of(context).secondaryText,
            ),
            const SizedBox(height: 16),
            Text(
              'No habits found',
              style: FlutterFlowTheme.of(context).titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first habit to get started!',
              style: FlutterFlowTheme.of(context).bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _shouldReloadOnReturn = true;
                // context.pushNamed('AddHabitPg');
              },
              child: const Text('Add Habit'),
            ),
          ],
        ),
      );
    }

    final slivers = <Widget>[];

    // Tasks header
    if (_tasksTodayOrder.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Container(
            margin: EdgeInsets.fromLTRB(16, 8, 16, _tasksExpanded ? 0 : 6),
            padding: EdgeInsets.fromLTRB(12, 8, 12, _tasksExpanded ? 2 : 6),
            decoration: BoxDecoration(
              gradient: FlutterFlowTheme.of(context).neumorphicGradient,
              border: Border.all(
                color: FlutterFlowTheme.of(context).surfaceBorderColor,
                width: 1,
              ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft:
                    _tasksExpanded ? Radius.zero : const Radius.circular(16),
                bottomRight:
                    _tasksExpanded ? Radius.zero : const Radius.circular(16),
              ),
              boxShadow: _tasksExpanded
                  ? []
                  : FlutterFlowTheme.of(context).neumorphicShadowsRaised,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tasks',
                      style: FlutterFlowTheme.of(context).titleMedium.override(
                            fontFamily: 'Readex Pro',
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(width: 5),
                    _buildCategoryWeightStars(_getTasksCategory()),
                    const SizedBox(width: 5),
                    GestureDetector(
                      onTap: () {
                        _tasksExpanded = !_tasksExpanded;
                      },
                      child: Icon(
                        _tasksExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 28,
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        ),
      );
      // Tasks reorderable list
      if (_tasksExpanded) {
        slivers.add(
          SliverReorderableList(
            itemCount: _tasksTodayOrder.length,
            itemBuilder: (context, index) {
              final task = _tasksTodayOrder[index];
              final isLast = index == _tasksTodayOrder.length - 1;
              return ReorderableDelayedDragStartListener(
                key: ValueKey('task_${task.reference.id}'),
                index: index,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  decoration: BoxDecoration(
                    gradient:
                        FlutterFlowTheme.of(context).neumorphicGradientSubtle,
                    border: Border(
                      left: BorderSide(
                          color:
                              FlutterFlowTheme.of(context).surfaceBorderColor,
                          width: 1),
                      right: BorderSide(
                          color:
                              FlutterFlowTheme.of(context).surfaceBorderColor,
                          width: 1),
                      top: BorderSide.none,
                      bottom: isLast
                          ? BorderSide(
                              color: FlutterFlowTheme.of(context)
                                  .surfaceBorderColor,
                              width: 1)
                          : BorderSide.none,
                    ),
                    borderRadius: isLast
                        ? const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          )
                        : BorderRadius.zero,
                    // No individual shadows - let section container handle shadows
                    boxShadow: const [],
                  ),
                  padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                  child: _buildTaskRow(task),
                ),
              );
            },
            proxyDecorator: (child, index, animation) {
              final size = MediaQuery.of(context).size;
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  return Material(
                    elevation: 6,
                    color: Colors.transparent,
                    child: SizedBox(
                      width: size.width,
                      child: IntrinsicHeight(child: child),
                    ),
                  );
                },
              );
            },
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > _tasksTodayOrder.length) {
                newIndex = _tasksTodayOrder.length;
              }
              if (newIndex > oldIndex) newIndex -= 1;
              setState(() {
                final item = _tasksTodayOrder.removeAt(oldIndex);
                _tasksTodayOrder.insert(newIndex, item);
              });
              for (int i = 0; i < _tasksTodayOrder.length; i++) {
                final t = _tasksTodayOrder[i];
                try {
                  await updateTask(taskRef: t.reference, manualOrder: i);
                } catch (_) {}
              }
            },
          ),
        );
      }
      // Spacer after Tasks card before Category groups
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 10)));
    }

    // Category groups
    for (final categoryName in _groupedHabits.keys) {
      final habits = _groupedHabits[categoryName]!;
      // Resolve category record
      CategoryRecord? category;
      try {
        category = _categories.firstWhere((c) => c.name == categoryName);
      } catch (e) {
        final categoryData = createCategoryRecordData(
          name: categoryName,
          color: '#2196F3',
          userId: currentUserUid,
          isActive: true,
          weight: 1.0,
          createdTime: DateTime.now(),
          lastUpdated: DateTime.now(),
          categoryType: 'habit', // Dashboard is for habits
        );
        category = CategoryRecord.getDocumentFromData(
          categoryData,
          FirebaseFirestore.instance.collection('categories').doc(),
        );
      }

      final expanded = _categoryExpanded[categoryName] ?? true;

      // Header
      slivers.add(
        SliverToBoxAdapter(
          child: Container(
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        color: Color(int.parse(
                            category.color.replaceFirst('#', '0xFF'))),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(width: 5),
                    _buildCategoryWeightStars(category),
                    const SizedBox(width: 5),
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
                        onSelected: (value) => category != null
                            ? _handleCategoryMenuAction(value, category)
                            : null,
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
                    const SizedBox(width: 5),
                    GestureDetector(
                      onTap: () {
                        _categoryExpanded[categoryName] = !expanded;
                      },
                      child: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 28,
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        ),
      );

      // Habits reorderable list (within category)
      if (expanded) {
        // Sort by manualOrder, fallback to in-category index
        final sortedHabits = List<HabitRecord>.from(habits);
        sortedHabits.sort((a, b) {
          final ao = a.hasManualOrder() ? a.manualOrder : habits.indexOf(a);
          final bo = b.hasManualOrder() ? b.manualOrder : habits.indexOf(b);
          return ao.compareTo(bo);
        });

        slivers.add(
          SliverReorderableList(
            itemCount: sortedHabits.length,
            itemBuilder: (context, index) {
              final habit = sortedHabits[index];
              final isLast = index == sortedHabits.length - 1;
              return ReorderableDelayedDragStartListener(
                key: ValueKey('habit_${habit.reference.id}'),
                index: index,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  decoration: BoxDecoration(
                    gradient:
                        FlutterFlowTheme.of(context).neumorphicGradientSubtle,
                    border: Border(
                      left: BorderSide(
                          color:
                              FlutterFlowTheme.of(context).surfaceBorderColor,
                          width: 1),
                      right: BorderSide(
                          color:
                              FlutterFlowTheme.of(context).surfaceBorderColor,
                          width: 1),
                      top: BorderSide.none,
                      bottom: isLast
                          ? BorderSide(
                              color: FlutterFlowTheme.of(context)
                                  .surfaceBorderColor,
                              width: 1)
                          : BorderSide.none,
                    ),
                    borderRadius: isLast
                        ? const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          )
                        : BorderRadius.zero,
                    // No individual shadows - let section container handle shadows
                    boxShadow: const [],
                  ),
                  padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                  child: CompactHabitItem(
                    key: Key(habit.reference.id),
                    habit: habit,
                    categoryColorHex: category!.color,
                    onRefresh: _loadHabits,
                    onHabitUpdated: (updated) =>
                        _updateHabitInLocalState(updated),
                    onHabitDeleted: (deleted) async => _loadHabits(),
                  ),
                ),
              );
            },
            proxyDecorator: (child, index, animation) {
              final size = MediaQuery.of(context).size;
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  return Material(
                    elevation: 6,
                    color: Colors.transparent,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: size.width,
                        maxHeight: 140,
                      ),
                      child: child,
                    ),
                  );
                },
              );
            },
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > sortedHabits.length) {
                newIndex = sortedHabits.length;
              }
              if (newIndex > oldIndex) newIndex -= 1;
              final item = sortedHabits.removeAt(oldIndex);
              sortedHabits.insert(newIndex, item);

              // Persist manualOrder sequentially within this category
              for (int i = 0; i < sortedHabits.length; i++) {
                final h = sortedHabits[i];
                try {
                  await updateHabit(habitRef: h.reference, manualOrder: i);
                } catch (_) {}
              }
              await _loadHabits();
            },
          ),
        );
      }
    }

    // Weekly goals section (at the bottom)
    if (weeklyGoals.isNotEmpty) {
      // Add spacing before weekly section
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 10)));
      slivers.add(
          SliverToBoxAdapter(child: _buildWeeklyGoalsSection(weeklyGoals)));
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        ...slivers,
        const SliverToBoxAdapter(
          child:
              SizedBox(height: 140), // Space for FABs + nav bar + extra padding
        ),
      ],
    );
  }

  // Quick add task removed from Habits page
  Widget _buildWeeklyGoalsSection(Map<String, List<HabitRecord>> weeklyGoals) {
    if (weeklyGoals.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        // Weekly Goals Header (like category header)
        Container(
          margin: EdgeInsets.fromLTRB(16, 8, 16, _weeklyGoalsExpanded ? 0 : 6),
          padding: EdgeInsets.fromLTRB(12, 8, 12, _weeklyGoalsExpanded ? 2 : 6),
          decoration: BoxDecoration(
            gradient: FlutterFlowTheme.of(context).neumorphicGradient,
            border: Border.all(
              color: FlutterFlowTheme.of(context).surfaceBorderColor,
              width: 1,
            ),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: _weeklyGoalsExpanded
                  ? Radius.zero
                  : const Radius.circular(16),
              bottomRight: _weeklyGoalsExpanded
                  ? Radius.zero
                  : const Radius.circular(16),
            ),
            boxShadow: _weeklyGoalsExpanded
                ? []
                : FlutterFlowTheme.of(context).neumorphicShadowsRaised,
          ),
          child: Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Weekly goals',
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
                      color: FlutterFlowTheme.of(context).warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                tooltip: _weeklyGoalsExpanded
                    ? 'Hide Weekly goals'
                    : 'Show Weekly goals',
                icon: Icon(
                  _weeklyGoalsExpanded ? Icons.expand_less : Icons.expand_more,
                ),
                onPressed: () => setState(
                    () => _weeklyGoalsExpanded = !_weeklyGoalsExpanded),
              ),
            ],
          ),
        ),
        // Weekly Goals Content (when expanded)
        if (_weeklyGoalsExpanded)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            decoration: BoxDecoration(
              gradient: FlutterFlowTheme.of(context).neumorphicGradientSubtle,
              border: Border(
                left: BorderSide(
                    color: FlutterFlowTheme.of(context).surfaceBorderColor,
                    width: 1),
                right: BorderSide(
                    color: FlutterFlowTheme.of(context).surfaceBorderColor,
                    width: 1),
                bottom: BorderSide(
                    color: FlutterFlowTheme.of(context).surfaceBorderColor,
                    width: 1),
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: FlutterFlowTheme.of(context).neumorphicShadowsRaised,
            ),
            child: Column(
              children: weeklyGoals.entries.map((entry) {
                final categoryName = entry.key;
                final habits = entry.value;
                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    gradient:
                        FlutterFlowTheme.of(context).neumorphicGradientSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: FlutterFlowTheme.of(context).surfaceBorderColor,
                        width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              categoryName,
                              style: FlutterFlowTheme.of(context)
                                  .bodyLarge
                                  .override(
                                    fontFamily: 'Readex Pro',
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...habits.map((h) => _buildWeeklyGoalRow(h)).toList(),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildWeeklyGoalRow(HabitRecord habit) {
    final remaining = _remainingCompletionsThisWeek(habit);
    final daysLeft = _daysRemainingThisWeekInclusiveToday();
    final behind = remaining > daysLeft;
    final mustToday = remaining == daysLeft;
    String statusLabel = 'On track';
    Color statusColor = FlutterFlowTheme.of(context).secondaryText;
    if (behind) {
      statusLabel = 'Behind';
      statusColor = FlutterFlowTheme.of(context).error;
    } else if (mustToday) {
      statusLabel = 'Priority';
      statusColor = FlutterFlowTheme.of(context).warning;
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            habit.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.08),
            border: Border.all(color: statusColor.withOpacity(0.4), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            statusLabel,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(width: 8),
        Text('Left: $remaining', style: FlutterFlowTheme.of(context).bodySmall),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () async {
            // Promote to Today by clearing today's skip (if any)
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final skipped = List<DateTime>.from(habit.skippedDates);
            skipped.removeWhere((d) =>
                d.year == today.year &&
                d.month == today.month &&
                d.day == today.day);
            await habit.reference.update(
                {'skippedDates': skipped, 'lastUpdated': DateTime.now()});
            await _loadHabits();
          },
          child: const Text('Do today'),
        ),
        TextButton(
          onPressed: () async {
            await HabitTrackingUtil.skipToday(habit);
            await _loadHabits();
          },
          child: const Text('Snooze'),
        ),
      ],
    );
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
              setState(() {
                final categoryIndex = _categories
                    .indexWhere((c) => c.reference.id == category.reference.id);
                if (categoryIndex != -1) {
                  final updatedCategoryData = createCategoryRecordData(
                    weight: next.toDouble(),
                    categoryType: 'habit', // Dashboard is for habits
                  );
                  final updatedCategory = CategoryRecord.getDocumentFromData(
                    {
                      ..._categories[categoryIndex].snapshotData,
                      ...updatedCategoryData,
                    },
                    _categories[categoryIndex].reference,
                  );
                  _categories[categoryIndex] = updatedCategory;
                }
              });
              await updateCategory(
                categoryId: category.reference.id,
                weight: next.toDouble(),
              );
            } catch (e) {
              setState(() {
                final categoryIndex = _categories
                    .indexWhere((c) => c.reference.id == category.reference.id);
                if (categoryIndex != -1) {
                  final revertedCategoryData = createCategoryRecordData(
                    weight: current.toDouble(),
                    categoryType: 'habit', // Dashboard is for habits
                  );
                  final revertedCategory = CategoryRecord.getDocumentFromData(
                    {
                      ..._categories[categoryIndex].snapshotData,
                      ...revertedCategoryData,
                    },
                    _categories[categoryIndex].reference,
                  );
                  _categories[categoryIndex] = revertedCategory;
                }
              });
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error updating category weight: $e')),
              );
            }
          },
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            color: filled
                ? Colors.amber
                : FlutterFlowTheme.of(context).secondaryText.withOpacity(0.35),
            size: 24,
          ),
        );
      }),
    );
  }

  CategoryRecord _getTasksCategory() {
    try {
      return _categories.firstWhere((c) => c.name.toLowerCase() == 'tasks');
    } catch (e) {
      final categoryData = createCategoryRecordData(
        name: 'Tasks',
        color: '#2196F3',
        userId: currentUserUid,
        isActive: true,
        weight: 1.0,
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        categoryType: 'task', // This is for tasks
      );
      return CategoryRecord.getDocumentFromData(
        categoryData,
        FirebaseFirestore.instance.collection('categories').doc(),
      );
    }
  }

  void _updateHabitInLocalState(HabitRecord updatedHabit) {
    setState(() {
      final habitIndex = _habits
          .indexWhere((h) => h.reference.id == updatedHabit.reference.id);
      if (habitIndex != -1) {
        _habits[habitIndex] = updatedHabit;
      }
    });
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

  // Show edit category dialog
  void _showEditCategoryDialog(CategoryRecord category) {
    final nameController = TextEditingController(text: category.name);
    final descriptionController =
        TextEditingController(text: category.description);
    int weight = category.weight.round();
    String selectedColor =
        category.color.isNotEmpty ? category.color : '#2196F3';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Edit Category'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Category Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text('Weight: $weight'),
                    ),
                    Expanded(
                      child: Slider(
                        value: weight.toDouble(),
                        min: 1.0,
                        max: 3.0,
                        divisions: 2,
                        onChanged: (value) {
                          setLocalState(() {
                            weight = value.round();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Color'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    '#2196F3',
                    '#4CAF50',
                    '#FF9800',
                    '#F44336',
                    '#9C27B0',
                    '#607D8B'
                  ]
                      .map((color) => GestureDetector(
                            onTap: () =>
                                setLocalState(() => selectedColor = color),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Color(
                                    int.parse(color.replaceFirst('#', '0xFF'))),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selectedColor == color
                                      ? FlutterFlowTheme.of(context).accent1
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: selectedColor == color
                                  ? const Icon(Icons.check,
                                      size: 16, color: Colors.white)
                                  : null,
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    await updateCategory(
                      categoryId: category.reference.id,
                      name: nameController.text,
                      description: descriptionController.text.isNotEmpty
                          ? descriptionController.text
                          : null,
                      weight: weight.toDouble(),
                      color: selectedColor,
                      categoryType: 'habit', // Dashboard is for habits
                    );

                    // Update local state
                    final updatedCategoryData = createCategoryRecordData(
                      name: nameController.text,
                      description: descriptionController.text.isNotEmpty
                          ? descriptionController.text
                          : null,
                      weight: weight.toDouble(),
                      color: selectedColor,
                      categoryType: 'habit', // Dashboard is for habits
                    );
                    final updatedCategory = CategoryRecord.getDocumentFromData(
                      {
                        ...category.snapshotData,
                        ...updatedCategoryData,
                      },
                      category.reference,
                    );
                    setState(() {
                      final categoryIndex = _categories.indexWhere(
                          (c) => c.reference.id == category.reference.id);
                      if (categoryIndex != -1) {
                        _categories[categoryIndex] = updatedCategory;
                      }
                    });

                    Navigator.of(context).pop();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Category "${nameController.text}" updated successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    print('Error updating category: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error updating category: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  // Show delete category confirmation
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
                await deleteCategory(category.uid, userId: currentUserUid);

                // Update local state
                setState(() {
                  _categories.removeWhere(
                      (c) => c.reference.id == category.reference.id);
                });

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

  // Legacy task list helper removed (unused)

  Widget _buildTaskRow(TaskRecord task) {
    final double screenWidth = MediaQuery.of(context).size.width;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: screenWidth - 32),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
        decoration: BoxDecoration(
          gradient: FlutterFlowTheme.of(context).neumorphicGradientSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: FlutterFlowTheme.of(context).surfaceBorderColor,
            width: 0.5,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Category accent stripe
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: _taskStripeColor(task),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Checkbox(
                value: task.status == 'done',
                onChanged: (val) async {
                  try {
                    final now = DateTime.now();
                    final newStatus = val == true ? 'done' : 'todo';
                    final newCompletedTime = val == true ? now : null;
                    await updateTask(
                      taskRef: task.reference,
                      status: newStatus,
                      completedTime: newCompletedTime,
                    );
                    // Local update to avoid full page reload
                    final idx = _tasks
                        .indexWhere((t) => t.reference.id == task.reference.id);
                    if (idx != -1) {
                      final data = createTaskRecordData(
                        status: newStatus,
                        completedTime: newCompletedTime,
                      );
                      final updated = TaskRecord.getDocumentFromData(
                        {
                          ..._tasks[idx].snapshotData,
                          ...data,
                        },
                        _tasks[idx].reference,
                      );
                      setState(() {
                        _tasks[idx] = updated;
                        _recomputeTasksTodayOrder();
                      });
                    } else {
                      setState(() => _recomputeTasksTodayOrder());
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating task: $e')),
                      );
                    }
                  }
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FlutterFlowTheme.of(context).bodyMedium.override(
                            fontFamily: 'Readex Pro',
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (task.categoryName.isNotEmpty)
                      Text(
                        task.categoryName,
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                              fontFamily: 'Readex Pro',
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                      ),
                  ],
                ),
              ),
              // Importance stars + anchored menus
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTaskPriorityStars(task),
                  const SizedBox(width: 5),
                  Builder(
                      builder: (btnCtx) => GestureDetector(
                            onTap: () {
                              _showTaskSnoozeMenu(btnCtx, task);
                            },
                            child: const Icon(
                              Icons.snooze,
                              size: 20,
                            ),
                          )),
                  const SizedBox(width: 5),
                  Builder(
                    builder: (btnCtx) => GestureDetector(
                      onTap: () {
                        _showTaskOverflowMenu(btnCtx, task);
                      },
                      child: const Icon(
                        Icons.more_vert,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskPriorityStars(TaskRecord task) {
    final current = task.priority;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final level = index + 1;
        final filled = current >= level;
        return GestureDetector(
          onTap: () async {
            try {
              final next = current == 0 ? 1 : (current % 3) + 1;
              await updateTask(taskRef: task.reference, priority: next);
              // Local update to avoid full page reload
              final idx =
                  _tasks.indexWhere((t) => t.reference.id == task.reference.id);
              if (idx != -1) {
                final data = createTaskRecordData(priority: next);
                final updated = TaskRecord.getDocumentFromData(
                  {
                    ..._tasks[idx].snapshotData,
                    ...data,
                  },
                  _tasks[idx].reference,
                );
                setState(() {
                  _tasks[idx] = updated;
                  _recomputeTasksTodayOrder();
                });
              } else {
                setState(() => _recomputeTasksTodayOrder());
              }
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error updating importance: $e')),
              );
            }
          },
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            color: filled
                ? Colors.amber
                : FlutterFlowTheme.of(context).secondaryText.withOpacity(0.35),
            size: 24,
          ),
        );
      }),
    );
  }

  // Habit priority stars moved into CompactHabitItem

  // Habit snooze/reschedule is handled inside CompactHabitItem

  Color _taskStripeColor(TaskRecord task) {
    // Prefer matching category by ID; fallback to name match
    CategoryRecord? matchedCategory;
    try {
      if (task.categoryId.isNotEmpty) {
        matchedCategory =
            _categories.firstWhere((c) => c.reference.id == task.categoryId);
      } else if (task.categoryName.isNotEmpty) {
        final taskName = task.categoryName.trim().toLowerCase();
        matchedCategory = _categories.firstWhere(
          (c) => c.name.trim().toLowerCase() == taskName,
        );
      }
    } catch (_) {
      // No match; fall through to fallbacks
    }

    if (matchedCategory != null && matchedCategory.color.isNotEmpty) {
      try {
        return Color(
          int.parse(matchedCategory.color.replaceFirst('#', '0xFF')),
        );
      } catch (_) {
        // Invalid color encoding; use fallback below
      }
    }

    // Fallbacks: themed colors for generic names else subtle divider color
    final theme = FlutterFlowTheme.of(context);
    final name = task.categoryName.trim().toLowerCase();
    if (name == 'tasks' || name == 'task') {
      return theme.secondary;
    }
    return FlutterFlowTheme.of(context).alternate;
  }

  // -- Context menus (compact, anchored) --
  Future<void> _showTaskSnoozeMenu(
      BuildContext anchorContext, TaskRecord task) async {
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
          side: BorderSide(color: FlutterFlowTheme.of(context).alternate)),
      items: const [
        PopupMenuItem<String>(
            value: 'snooze_tomorrow',
            height: 32,
            child: Text('Snooze to tomorrow', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'snooze_weekend',
            height: 32,
            child: Text('Snooze to weekend', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'snooze_next_week',
            height: 32,
            child: Text('Snooze to next week', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'pick_date',
            height: 32,
            child: Text('Pick a date…', style: TextStyle(fontSize: 12))),
        PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
            value: 'skip_today',
            height: 32,
            child: Text('Skip today', style: TextStyle(fontSize: 12))),
      ],
    );
    if (selected == null) return;
    if (selected == 'snooze_tomorrow') {
      await _snoozeTask(task, _tomorrowDate());
    } else if (selected == 'snooze_weekend') {
      await _snoozeTask(task, _nextWeekend());
    } else if (selected == 'snooze_next_week') {
      await _snoozeTask(task, _nextWeekMonday());
    } else if (selected == 'pick_date') {
      final picked = await showDatePicker(
        context: context,
        initialDate: _tomorrowDate(),
        firstDate: _todayDate(),
        lastDate: _todayDate().add(const Duration(days: 365)),
      );
      if (picked != null) {
        await _snoozeTask(task, picked);
      }
    } else if (selected == 'skip_today') {
      await _snoozeTask(task, _tomorrowDate());
    }
  }

  Future<void> _showTaskOverflowMenu(
      BuildContext anchorContext, TaskRecord task) async {
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
          side: BorderSide(color: FlutterFlowTheme.of(context).alternate)),
      items: const [
        PopupMenuItem<String>(
            value: 'edit',
            height: 32,
            child: Text('Edit', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'duplicate',
            height: 32,
            child: Text('Duplicate', style: TextStyle(fontSize: 12))),
        PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
            value: 'recurring',
            height: 32,
            child: Row(
              children: [
                Icon(Icons.repeat, size: 18),
                SizedBox(width: 8),
                Text('Make recurring', style: TextStyle(fontSize: 12)),
              ],
            )),
        PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
            value: 'delete',
            height: 32,
            child: Text('Delete', style: TextStyle(fontSize: 12))),
      ],
    );
    if (selected == null) return;
    if (selected == 'edit') {
      // Navigate but do not reload this page
      _shouldReloadOnReturn = true;
      // context.pushNamed('TasksPg');
    } else if (selected == 'duplicate') {
      try {
        await createTask(
          title: task.title,
          description: task.description,
          dueDate: task.dueDate,
          priority: task.priority,
          categoryId: task.categoryId,
          categoryName: task.categoryName,
        );
        // Minimal local refresh: requery only this user's tasks list
        final tasks = await queryTasksRecordOnce(userId: currentUserUid);
        setState(() {
          _tasks = tasks;
          _recomputeTasksTodayOrder();
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task duplicated')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error duplicating: $e')),
        );
      }
    } else if (selected == 'recurring') {
      await _showMakeRecurringDialog(task);
    } else if (selected == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Task'),
          content: Text('Delete "${task.title}"? This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                  foregroundColor: FlutterFlowTheme.of(context).error),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        try {
          await deleteTask(task.reference);
          // Local removal to avoid full page reload
          setState(() {
            _tasks.removeWhere((t) => t.reference.id == task.reference.id);
            _recomputeTasksTodayOrder();
          });
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting: $e')),
          );
        }
      }
    }
  }

  // -- Today tab: task Snooze/Skip helpers --
  DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _tomorrowDate() => _todayDate().add(const Duration(days: 1));

  DateTime _nextWeekend() {
    final today = _todayDate();
    final int daysUntilSaturday = (DateTime.saturday - today.weekday) % 7;
    return today
        .add(Duration(days: daysUntilSaturday == 0 ? 7 : daysUntilSaturday));
  }

  DateTime _nextWeekMonday() {
    final today = _todayDate();
    final int daysUntilMonday = (DateTime.monday - today.weekday) % 7;
    return today
        .add(Duration(days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
  }

  Future<void> _snoozeTask(TaskRecord task, DateTime newDate) async {
    try {
      await updateTask(taskRef: task.reference, dueDate: newDate);
      // Local update to avoid full page reload
      final idx = _tasks.indexWhere((t) => t.reference.id == task.reference.id);
      if (idx != -1) {
        final data = createTaskRecordData(dueDate: newDate);
        final updated = TaskRecord.getDocumentFromData(
          {
            ..._tasks[idx].snapshotData,
            ...data,
          },
          _tasks[idx].reference,
        );
        setState(() {
          _tasks[idx] = updated;
          _recomputeTasksTodayOrder();
        });
      } else {
        setState(() => _recomputeTasksTodayOrder());
      }
      if (!mounted) return;
      final label = DateFormat('EEE, MMM d').format(newDate);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Snoozed to $label')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error snoozing: $e')),
      );
    }
  }

  // Legacy task snooze sheet removed (unused)

  Future<void> _showMakeRecurringDialog(TaskRecord task) async {
    String trackingType = 'binary';
    String schedule = 'daily';
    int targetNumber = 1;
    int targetMinutes = 30;
    int weeklyTarget = 3;
    String unit = '';
    bool deleteTaskAfter = true;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Make Recurring'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tracking Type'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: trackingType,
                  items: const [
                    DropdownMenuItem(value: 'binary', child: Text('Binary')),
                    DropdownMenuItem(
                        value: 'quantitative', child: Text('Quantity')),
                    DropdownMenuItem(value: 'time', child: Text('Time')),
                  ],
                  onChanged: (v) => trackingType = v ?? 'binary',
                ),
                const SizedBox(height: 12),
                if (trackingType == 'quantitative') ...[
                  TextField(
                    decoration: const InputDecoration(
                        labelText: 'Target number',
                        border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => targetNumber = int.tryParse(v) ?? 1,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                        labelText: 'Unit (e.g., pages)',
                        border: OutlineInputBorder()),
                    onChanged: (v) => unit = v,
                  ),
                ] else if (trackingType == 'time') ...[
                  TextField(
                    decoration: const InputDecoration(
                        labelText: 'Target minutes',
                        border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => targetMinutes = int.tryParse(v) ?? 30,
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Schedule'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: schedule,
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  ],
                  onChanged: (v) => schedule = v ?? 'daily',
                ),
                if (schedule == 'weekly' || schedule == 'monthly') ...[
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      labelText: schedule == 'weekly'
                          ? 'Times per week'
                          : 'Times per month',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => weeklyTarget = int.tryParse(v) ?? 3,
                  ),
                ],
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: deleteTaskAfter,
                  onChanged: (v) => setState(() => deleteTaskAfter = v ?? true),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remove one-off task after creating habit'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  dynamic target;
                  switch (trackingType) {
                    case 'binary':
                      target = true;
                      break;
                    case 'quantitative':
                      target = targetNumber;
                      break;
                    case 'time':
                      target = targetMinutes; // minutes
                      break;
                  }

                  await createHabit(
                    name: task.title,
                    categoryName: task.categoryName.isNotEmpty
                        ? task.categoryName
                        : 'default',
                    impactLevel: 'Medium',
                    trackingType: trackingType,
                    target: target,
                    schedule: schedule,
                    weeklyTarget: weeklyTarget,
                    description: unit.isNotEmpty ? 'Unit: ' + unit : null,
                  );

                  if (deleteTaskAfter) {
                    await updateTask(
                      taskRef: task.reference,
                      status: 'done',
                      isActive: false,
                      completedTime: DateTime.now(),
                    );
                  }

                  if (!mounted) return;
                  Navigator.of(context).pop();
                  await _loadHabits();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Habit created from task')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating habit: $e')),
                  );
                }
              },
              child: const Text('Create Habit'),
            ),
          ],
        );
      },
    );
  }
}
