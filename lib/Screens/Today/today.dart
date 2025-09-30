import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/habit_tracking_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/utils/floating_timer.dart';
import 'package:habit_tracker/Helper/utils/neumorphic_container.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Screens/Create%20Catagory/create_category.dart';
import 'package:habit_tracker/Screens/Dashboard/compact_habit_item.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class TodayPage extends StatefulWidget {
  final bool showCompleted;
  const TodayPage({super.key, required this.showCompleted});

  @override
  _TodayPageState createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  List<HabitRecord> _habits = [];
  List<CategoryRecord> _categories = [];
  List<HabitRecord> _tasks = [];
  List<HabitRecord> _tasksTodayOrder = [];
  final Map<String, bool> _categoryExpanded = {};
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  bool _weeklyGoalsExpanded = false;
  bool _tasksExpanded = true;
  bool _shouldReloadOnReturn = false;
  late bool _showCompleted;
  double _netImpactScore = 0;
  double _dailyCompletionPercent = 0;
  int _completedHabits = 0;
  int _totalHabits = 0;
  int _thriveScore = 0;

  @override
  void initState() {
    super.initState();
    _showCompleted = widget.showCompleted;
    _loadHabits();
    NotificationCenter.addObserver(this, 'showCompleted', (param) {
      if (param is bool && mounted) {
        setState(() {
          _showCompleted = param;
          print("zxvv");
          print(_showCompleted);
        });
      }
    });
    NotificationCenter.addObserver(this, 'loadToday', (param) {
      if (mounted) {
        setState(() {
          _loadHabits();
        });
      }
    });
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

  Future<void> _loadHabits() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final habits = await queryHabitsRecordOnce(userId: userId);
        final categories = await queryHabitCategoriesOnce(userId: userId);
        final taskCategories = await queryTaskCategoriesOnce(userId: userId);
        final taskCategoryNames = taskCategories.map((c) => c.name).toSet();
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);
        final allCategories = [...categories, ...taskCategories];
        setState(() {
          _habits = habits;
          _categories = allCategories;
          _tasks = habits.where((h) {
            // if (h.isRecurring) return false;
            if (h.dueDate == null) return false;
            final due =
                DateTime(h.dueDate!.year, h.dueDate!.month, h.dueDate!.day);
            if (due != todayDate) return false;
            final isTaskCategory = taskCategoryNames.contains(h.categoryName) ||
                h.categoryName.toLowerCase() == 'tasks' ||
                h.categoryName.toLowerCase() == 'task';
            if (!isTaskCategory) return false;
            if (_isTaskCompleted(h) && !_showCompleted) return false;
            return true;
          }).toList();
          _recomputeTasksTodayOrder();
          _calculateScores();
          _isLoading = false;
        });
        if (_tasks.isNotEmpty) {
          print('Task tracking types:');
          for (final task in _tasks) {
            print(
                '  - ${task.name}: ${task.trackingType}, target: ${task.target}');
          }
        }
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
    final open = _tasks.where((t) {
      if (!t.isActive) return false;
      switch (t.trackingType) {
        case 'binary':
          return t.status != 'complete';
        case 'quantitative':
          final currentValue = t.currentValue ?? 0;
          final target = t.target ?? 0;
          return currentValue < target;
        case 'time':
          final currentMinutes = (t.accumulatedTime) ~/ 60000;
          final targetMinutes = t.target ?? 0;
          return currentMinutes < targetMinutes;
        default:
          return t.status != 'complete';
      }
    }).toList();

    open.sort((a, b) {
      final ao = a.hasManualOrder() ? a.manualOrder : 1000000 + open.indexOf(a);
      final bo = b.hasManualOrder() ? b.manualOrder : 1000000 + open.indexOf(b);
      return ao.compareTo(bo);
    });
    _tasksTodayOrder = open;
  }

  void _calculateScores() {
    final actualHabits = _habits.where((h) => h.isRecurring).toList();
    _totalHabits = actualHabits.length;
    _completedHabits = 0;
    _netImpactScore = 0;

    for (final habit in actualHabits) {
      final isCompleted = HabitTrackingUtil.isCompletedToday(habit);

      if (isCompleted) {
        _completedHabits++;
        final impactPoints = _getImpactPoints(habit.priority.toString());
        _netImpactScore += impactPoints;
      }
    }

    _dailyCompletionPercent =
        _totalHabits > 0 ? (_completedHabits / _totalHabits) * 100 : 0;
    _thriveScore = 1247;
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
            Text(
              DateFormat('EEEE, MMMM d, y').format(DateTime.now()),
              style: FlutterFlowTheme.of(context).titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
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

  bool _isTaskCompleted(HabitRecord task) {
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

  Map<String, List<HabitRecord>> get _groupedWeeklyGoals {
    final grouped = <String, List<HabitRecord>>{};
    for (final habit in _habits) {
      if (!habit.isRecurring) continue;

      if (!_isFlexibleWeekly(habit)) continue;
      if (_shouldShowInTodayMain(habit)) continue;
      if (_remainingCompletionsThisWeek(habit) <= 0) continue;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Note: skippedDates tracking moved to separate records
      if (false) {
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
    // Note: completedDates tracking moved to separate completion records
    return <DateTime>[].where((date) {
      final d = DateTime(date.year, date.month, date.day);
      return !d.isBefore(weekStart) && !d.isAfter(weekEnd);
    }).length;
  }

  int _daysRemainingThisWeekInclusiveToday() {
    final now = DateTime.now();
    return DateTime.sunday - now.weekday + 1;
  }

  int _remainingCompletionsThisWeek(HabitRecord habit) {
    final done = _completedCountThisWeek(habit);
    final remaining = habit.frequency - done;
    return remaining > 0 ? remaining : 0;
  }

  bool _shouldShowInTodayMain(HabitRecord habit) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Note: skippedDates tracking moved to separate records
    if (false) {
      return false;
    }
    if (habit.hasSnoozedUntil()) {
      final until = habit.snoozedUntil!;
      final untilDate = DateTime(until.year, until.month, until.day);
      if (!today.isAfter(untilDate)) {
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
      return remaining >= daysRemaining;
    }
    return false;
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
                    _buildScoreBar(),
                    Expanded(
                      child: _buildDailyView(),
                    ),
                  ],
                ),
          FloatingTimer(
            activeHabits: _activeFloatingHabits,
            onRefresh: _loadHabits,
            onHabitUpdated: (updated) => _updateHabitInLocalState(updated),
          ),
        ],
      ),
    );
  }

  List<HabitRecord> get _activeFloatingHabits {
    final all = [
      ..._tasksTodayOrder,
      ..._groupedHabits.values.expand((list) => list)
    ];
    return all.where((h) => h.showInFloatingTimer == true).toList();
  }

  Widget _buildDailyView() {
    final weeklyGoals = _groupedWeeklyGoals;
    if (_groupedHabits.isEmpty &&
        weeklyGoals.isEmpty &&
        _tasksTodayOrder.isEmpty) {
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
              'No habits or tasks found',
              style: FlutterFlowTheme.of(context).titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first habit or task to get started!',
              style: FlutterFlowTheme.of(context).bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _shouldReloadOnReturn = true;
              },
              child: const Text('Add Habit'),
            ),
          ],
        ),
      );
    }

    final slivers = <Widget>[];

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
                        if (mounted) {
                          setState(() {
                            _tasksExpanded = !_tasksExpanded;
                          });
                        }
                      },
                      child: Icon(
                        size: 28,
                        _tasksExpanded ? Icons.expand_less : Icons.expand_more,
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        ),
      );
      if (_tasksExpanded) {
        slivers.add(
          SliverReorderableList(
            itemCount: _tasksTodayOrder.length,
            itemBuilder: (context, index) {
              final task = _tasksTodayOrder[index];
              return ReorderableDelayedDragStartListener(
                key: ValueKey('task_${task.reference.id}'),
                index: index,
                child: CompactHabitItem(
                  tasks: _tasks,
                  showTaskEdit: true,
                  categories: _categories
                      .where((c) => c.categoryType == 'task')
                      .toList(),
                  showCompleted: _showCompleted,
                  key: Key(task.reference.id),
                  habit: task,
                  categoryColorHex: _getTaskCategoryColor(task),
                  onRefresh: _loadHabits,
                  onHabitUpdated: (updated) =>
                      _updateTaskInLocalState(updated, null),
                  onHabitDeleted: (deleted) {
                    setState(() {
                      _tasks.removeWhere(
                          (t) => t.reference.id == deleted.reference.id);
                      _tasksTodayOrder.removeWhere(
                          (t) => t.reference.id == deleted.reference.id);
                    });
                  },
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
                  await updateHabit(habitRef: t.reference, manualOrder: i);
                } catch (_) {}
              }
            },
          ),
        );
      }
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 10)));
    }
    for (final categoryName in _groupedHabits.keys) {
      final habits = _groupedHabits[categoryName]!;
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
          categoryType: 'habit',
        );
        category = CategoryRecord.getDocumentFromData(
          categoryData,
          FirebaseFirestore.instance.collection('categories').doc(),
        );
      }
      final expanded = _categoryExpanded[categoryName] ?? true;
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
          ),
        ),
      );
      if (expanded) {
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
                child: CompactHabitItem(
                  showCompleted: _showCompleted,
                  key: Key(habit.reference.id),
                  habit: habit,
                  categoryColorHex: category!.color,
                  onRefresh: _loadHabits,
                  onHabitUpdated: (updated) {
                    final habitIndex = _habits.indexWhere(
                        (h) => h.reference.id == updated.reference.id);
                    if (habitIndex != -1) {
                      _habits[habitIndex] = updated;
                    }

                    final taskIndex = _tasks.indexWhere(
                        (t) => t.reference.id == updated.reference.id);
                    if (taskIndex != -1) {
                      _tasks[taskIndex] = updated;
                    } else if (updated.trackingType == 'time' &&
                        updated.isTimerActive) {
                      setState(() {
                        _tasks.add(updated);
                      });
                    } else {
                      setState(() {
                        _tasks.removeWhere(
                            (t) => t.reference.id == updated.reference.id);
                      });
                    }
                  },
                  onHabitDeleted: (deleted) async => _loadHabits(),
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
    if (weeklyGoals.isNotEmpty) {
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 10)));
      slivers.add(
          SliverToBoxAdapter(child: _buildWeeklyGoalsSection(weeklyGoals)));
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

  Widget _buildWeeklyGoalsSection(Map<String, List<HabitRecord>> weeklyGoals) {
    if (weeklyGoals.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
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
                      ...habits.map((h) => _buildWeeklyGoalRow(h)),
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
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            // Note: skippedDates tracking moved to separate records
            final skipped = <DateTime>[];
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
    final current = (category.weight ?? 1.0).round().clamp(1, 3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final level = i + 1;
        final filled = current >= level;
        return GestureDetector(
          onTap: () async {
            try {
              final next = current % 3 + 1;

              // Update local state immediately for instant UI feedback
              setState(() {
                // Find and update the category in the local list
                final categoryIndex = _categories
                    .indexWhere((c) => c.reference.id == category.reference.id);
                if (categoryIndex != -1) {
                  final updatedCategoryData = createCategoryRecordData(
                    weight: next.toDouble(),
                    categoryType: 'habit', // Today page is for habits
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

              // Update backend in the background
              await updateCategory(
                categoryId: category.reference.id,
                weight: next.toDouble(),
              );
            } catch (e) {
              // If backend update fails, revert the local change
              setState(() {
                final categoryIndex = _categories
                    .indexWhere((c) => c.reference.id == category.reference.id);
                if (categoryIndex != -1) {
                  final revertedCategoryData = createCategoryRecordData(
                    weight: current.toDouble(),
                    categoryType: 'habit', // Today page is for habits
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
            size: 24,
            color: filled
                ? Colors.amber
                : FlutterFlowTheme.of(context).secondaryText.withOpacity(0.35),
          ),
        );
      }),
    );
  }

  String _getTaskCategoryColor(HabitRecord task) {
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
    } catch (_) {}

    if (matchedCategory != null && matchedCategory.color.isNotEmpty) {
      return matchedCategory.color;
    }
    final name = task.categoryName.trim().toLowerCase();
    if (name == 'tasks' || name == 'task') {
      return '#2196F3';
    }
    return '#2196F3';
  }

  CategoryRecord _getTasksCategory() {
    try {
      return _categories.firstWhere(
          (c) => c.name.toLowerCase() == 'tasks' && c.categoryType == 'task');
    } catch (e) {
      try {
        return _categories.firstWhere((c) => c.categoryType == 'task');
      } catch (e2) {
        final categoryData = createCategoryRecordData(
          name: 'Tasks',
          color: '#2196F3',
          userId: currentUserUid,
          isActive: true,
          weight: 1.0,
          createdTime: DateTime.now(),
          lastUpdated: DateTime.now(),
          categoryType: 'task',
        );
        return CategoryRecord.getDocumentFromData(
          categoryData,
          FirebaseFirestore.instance.collection('categories').doc(),
        );
      }
    }
  }

  void _updateHabitInLocalState(HabitRecord updated) {
    setState(() {
      final habitIndex =
          _habits.indexWhere((h) => h.reference.id == updated.reference.id);
      if (habitIndex != -1) {
        _habits[habitIndex] = updated;
      }
      final taskIndex =
          _tasks.indexWhere((t) => t.reference.id == updated.reference.id);
      if (taskIndex != -1) {
        _tasks[taskIndex] = updated;
        if (_isTaskCompleted(updated)) {
          _tasksTodayOrder
              .removeWhere((t) => t.reference.id == updated.reference.id);
        } else {
          if (!_tasksTodayOrder
              .any((t) => t.reference.id == updated.reference.id)) {
            _tasksTodayOrder.add(updated);
          }
        }
      } else if (updated.trackingType == 'time' && updated.isTimerActive) {
        _tasks.add(updated);
      } else {
        _tasks.removeWhere((t) => t.reference.id == updated.reference.id);
        _tasksTodayOrder
            .removeWhere((t) => t.reference.id == updated.reference.id);
      }
      _recomputeTasksTodayOrder();
      _removeEmptyCategories();
    });
    _loadDataSilently();
  }

  void _removeEmptyCategories() {
    final categoriesWithTasks = <String>{};
    for (final task in _tasks) {
      if (!task.isRecurring && task.categoryName.isNotEmpty) {
        categoriesWithTasks.add(task.categoryName);
      }
    }
    for (final habit in _habits) {
      if (habit.isRecurring && habit.categoryName.isNotEmpty) {
        categoriesWithTasks.add(habit.categoryName);
      }
    }
    _categories.removeWhere((category) {
      return !categoriesWithTasks.contains(category.name);
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

  void _updateTaskInLocalState(HabitRecord task, String? newStatus,
      [dynamic newCurrentValue,
      bool? newIsTimerActive,
      int? newAccumulatedTime,
      DateTime? newTimerStartTime]) {
    setState(() {
      final idx = _tasks.indexWhere((t) => t.reference.id == task.reference.id);
      if (idx != -1) {
        final updatedData = {
          ..._tasks[idx].snapshotData,
          if (newStatus != null) 'status': newStatus,
          if (newCurrentValue != null) 'currentValue': newCurrentValue,
          if (newIsTimerActive != null) 'isTimerActive': newIsTimerActive,
          if (newAccumulatedTime != null) 'accumulatedTime': newAccumulatedTime,
          if (newTimerStartTime != null) 'timerStartTime': newTimerStartTime,
          'lastUpdated': DateTime.now(),
        };
        final updated = HabitRecord.getDocumentFromData(
          updatedData,
          _tasks[idx].reference,
        );
        _tasks[idx] = updated;
        if (_isTaskCompleted(updated)) {
          _tasksTodayOrder
              .removeWhere((t) => t.reference.id == updated.reference.id);
        } else {
          if (!_tasksTodayOrder
              .any((t) => t.reference.id == updated.reference.id)) {
            _tasksTodayOrder.add(updated);
          }
        }
        _recomputeTasksTodayOrder();
      }
      _loadDataSilently();
    });
  }

  Future<void> _loadDataSilently() async {
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) return;
      final allHabits = await queryHabitsRecordOnce(userId: uid);
      final categories = await queryCategoriesRecordOnce(userId: uid);
      final taskCategories = await queryTaskCategoriesOnce(userId: uid);
      final taskCategoryNames = taskCategories.map((c) => c.name).toSet();
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      if (!mounted) return;
      setState(() {
        _tasks = allHabits.where((h) {
          // if (h.isRecurring) return false;
          if (h.dueDate == null) return false;
          final due =
              DateTime(h.dueDate!.year, h.dueDate!.month, h.dueDate!.day);
          return due == todayDate &&
              (taskCategoryNames.contains(h.categoryName) ||
                  h.categoryName.toLowerCase() == 'tasks' ||
                  h.categoryName.toLowerCase() == 'task');
        }).toList();
        _habits = allHabits.where((h) => h.isRecurring).toList();
        _categories = categories;
        _recomputeTasksTodayOrder();
        _calculateScores();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: $e')),
        );
      }
    }
  }
}
