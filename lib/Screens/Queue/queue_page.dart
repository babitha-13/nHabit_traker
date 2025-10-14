import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/points_service.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/progress_donut_chart.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  _QueuePageState createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  List<ActivityInstanceRecord> _instances = [];
  List<CategoryRecord> _categories = [];
  final Map<String, bool> _timeSectionExpanded = {
    'Overdue': true,
    'Today': true,
    'Recent Completions': false,
  };
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  bool _shouldReloadOnReturn = false;
  // Progress tracking variables
  double _dailyTarget = 0.0;
  double _pointsEarned = 0.0;
  double _dailyPercentage = 0.0;
  // Removed legacy Recent Completions expansion state; now uses standard sections

  @override
  void initState() {
    super.initState();
    _loadData();
    NotificationCenter.addObserver(this, 'loadData', (param) {
      if (mounted) {
        setState(() {
          _loadData();
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
        _loadData();
      }
    } else {
      _didInitialDependencies = true;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final allInstances = await queryAllInstances(userId: userId);
        final habitCategories = await queryHabitCategoriesOnce(userId: userId);
        final taskCategories = await queryTaskCategoriesOnce(userId: userId);
        final allCategories = [...habitCategories, ...taskCategories];

        // DEBUG: Print instance details
        print('QueuePage: Received ${allInstances.length} instances');
        int taskCount = 0;
        int habitCount = 0;
        for (final inst in allInstances) {
          print('  Instance: ${inst.templateName}');
          print('    - Category ID: ${inst.templateCategoryId}');
          print('    - Category Name: ${inst.templateCategoryName}');
          print('    - Category Type: ${inst.templateCategoryType}');
          print('    - Status: ${inst.status}');
          print('    - Due Date: ${inst.dueDate}');
          if (inst.templateCategoryType == 'task') taskCount++;
          if (inst.templateCategoryType == 'habit') habitCount++;
        }
        print('QueuePage: Tasks: $taskCount, Habits: $habitCount');

        if (mounted) {
          setState(() {
            _instances = allInstances;
            _categories = allCategories;
            _isLoading = false;
          });

          // Calculate progress for today's habits
          _calculateProgress();
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print('QueuePage: Error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Calculate progress for today's habits
  void _calculateProgress() async {
    final todayHabits = _instances
        .where((inst) =>
            inst.templateCategoryType == 'habit' && _isTodayOrOverdue(inst))
        .toList();

    // Also include completed habits from today
    final completedTodayHabits = _instances
        .where((inst) =>
            inst.templateCategoryType == 'habit' &&
            inst.status == 'completed' &&
            _wasCompletedToday(inst))
        .toList();

    // Combine both pending and completed habits for today
    final allTodayHabits = [...todayHabits, ...completedTodayHabits];

    // Use enhanced calculation with template data for accurate frequency
    try {
      _dailyTarget = await PointsService.calculateTotalDailyTargetWithTemplates(
          allTodayHabits, _categories, currentUserUid);
    } catch (e) {
      // Fallback to basic calculation if template fetch fails
      _dailyTarget =
          PointsService.calculateTotalDailyTarget(allTodayHabits, _categories);
    }

    _pointsEarned =
        PointsService.calculateTotalPointsEarned(allTodayHabits, _categories);
    _dailyPercentage = PointsService.calculateDailyPerformancePercent(
        _pointsEarned, _dailyTarget);

    // Debug logging
    print('QueuePage: Progress calculation:');
    print('  - Pending habits: ${todayHabits.length}');
    print('  - Completed today: ${completedTodayHabits.length}');
    print('  - Total habits: ${allTodayHabits.length}');
    print('  - Daily target: $_dailyTarget');
    print('  - Points earned: $_pointsEarned');
    print('  - Percentage: $_dailyPercentage%');

    // Update UI with new progress values
    if (mounted) {
      setState(() {
        // Progress values are already updated above
      });
    }
  }

  /// Check if instance is due today or overdue
  bool _isTodayOrOverdue(ActivityInstanceRecord instance) {
    if (instance.dueDate == null) return true; // No due date = today

    final today = _todayDate();
    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);

    return dueDate.isAtSameMomentAs(today) || dueDate.isBefore(today);
  }

  /// Check if a completed instance was completed today
  bool _wasCompletedToday(ActivityInstanceRecord instance) {
    if (instance.completedAt == null) return false;

    final today = _todayDate();
    final completedDate = DateTime(instance.completedAt!.year,
        instance.completedAt!.month, instance.completedAt!.day);

    return completedDate.isAtSameMomentAs(today);
  }

  bool _isInstanceCompleted(ActivityInstanceRecord instance) {
    return instance.status == 'completed';
  }

  Map<String, List<ActivityInstanceRecord>> get _bucketedItems {
    final Map<String, List<ActivityInstanceRecord>> buckets = {
      'Overdue': [],
      'Today': [],
      'Tomorrow': [],
      'This Week': [],
      'Later': [],
      'Recent Completions': [],
    };

    final today = _todayDate();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    print('_bucketedItems: Processing ${_instances.length} instances');
    for (final instance in _instances) {
      if (_isInstanceCompleted(instance)) {
        print('  ${instance.templateName}: SKIPPED (completed)');
        continue;
      }

      final dueDate = instance.dueDate;
      if (dueDate == null) {
        buckets['Later']!.add(instance);
        continue;
      }
      final dateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);

      if (dateOnly.isBefore(today)) {
        buckets['Overdue']!.add(instance);
      } else if (_isSameDay(dateOnly, today)) {
        buckets['Today']!.add(instance);
      } else if (_isSameDay(dateOnly, _tomorrowDate())) {
        buckets['Tomorrow']!.add(instance);
      } else if (!dateOnly.isAfter(endOfWeek)) {
        buckets['This Week']!.add(instance);
      } else {
        buckets['Later']!.add(instance);
      }
    }

    // Populate Recent Completions (completed today or yesterday)
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    for (final instance in _instances) {
      if (instance.status != 'completed') continue;
      if (instance.completedAt == null) continue;
      final completedDate = instance.completedAt!;
      final completedDateOnly =
          DateTime(completedDate.year, completedDate.month, completedDate.day);
      final isRecent = completedDateOnly.isAfter(yesterdayStart) ||
          completedDateOnly.isAtSameMomentAs(yesterdayStart);
      if (isRecent) {
        buckets['Recent Completions']!.add(instance);
      }
    }

    return buckets;
  }

  String _getSubtitle(ActivityInstanceRecord item, String bucketKey) {
    if (bucketKey == 'Recent Completions') {
      final completedAt = item.completedAt!;
      final completedStr =
          _isSameDay(completedAt, DateTime.now()) ? 'Today' : 'Yesterday';
      final due = item.dueDate;
      final dueStr = due != null ? DateFormat.MMMd().format(due) : 'No due';
      final icon = item.templateCategoryType == 'task' ? '📋' : '🔁';
      return 'Completed $completedStr • ${item.templateCategoryName} • Due: $dueStr • $icon';
    }

    if (bucketKey == 'Today' || bucketKey == 'Tomorrow') {
      return item.templateCategoryName;
    }

    final dueDate = item.dueDate;
    if (dueDate != null) {
      final formattedDate = DateFormat.MMMd().format(dueDate);
      return '$formattedDate • ${item.templateCategoryName}';
    }

    return item.templateCategoryName;
  }

  DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _tomorrowDate() => _todayDate().add(const Duration(days: 1));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Progress indicator
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          ProgressDonutChart(
                            percentage: _dailyPercentage,
                            totalTarget: _dailyTarget,
                            pointsEarned: _pointsEarned,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Daily Progress',
                            style: FlutterFlowTheme.of(context).bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _buildDailyView(),
                    ),
                  ],
                ),
          // FloatingTimer(
          //   activeHabits: _activeFloatingHabits,
          //   onRefresh: _loadData,
          //   onHabitUpdated: (updated) => {},
          // ),
        ],
      ),
    );
  }

  // List<ActivityRecord> get _activeFloatingHabits {
  //   // TODO: Re-implement with instances
  //   return [];
  // }

  Widget _buildDailyView() {
    final buckets = _bucketedItems;
    final order = [
      'Overdue',
      'Today',
      'Tomorrow',
      'This Week',
      'Later',
      'Recent Completions'
    ];
    final theme = FlutterFlowTheme.of(context);

    final visibleSections =
        order.where((key) => buckets[key]!.isNotEmpty).toList();

    if (visibleSections.isEmpty) {
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
              'No items in the queue for the selected filter',
              style: FlutterFlowTheme.of(context).titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final slivers = <Widget>[];

    for (final key in visibleSections) {
      final items = buckets[key]!;
      final expanded = _timeSectionExpanded[key] ?? false;

      slivers.add(
        SliverToBoxAdapter(
          child: Container(
            margin: EdgeInsets.fromLTRB(16, 8, 16, expanded ? 0 : 6),
            padding: EdgeInsets.fromLTRB(12, 8, 12, expanded ? 2 : 6),
            decoration: BoxDecoration(
              gradient: theme.neumorphicGradient,
              border: Border.all(
                color: theme.surfaceBorderColor,
                width: 1,
              ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: expanded ? Radius.zero : const Radius.circular(16),
                bottomRight: expanded ? Radius.zero : const Radius.circular(16),
              ),
              boxShadow: expanded ? [] : theme.neumorphicShadowsRaised,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$key (${items.length})',
                  style: theme.titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    if (mounted) {
                      setState(() {
                        _timeSectionExpanded[key] = !expanded;
                      });
                    }
                  },
                  child: Icon(
                    size: 28,
                    expanded ? Icons.expand_less : Icons.expand_more,
                  ),
                )
              ],
            ),
          ),
        ),
      );

      if (expanded) {
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                final isHabit = item.templateCategoryType == 'habit';
                return ItemComponent(
                  subtitle: _getSubtitle(item, key),
                  key: Key(item.reference.id),
                  instance: item,
                  categoryColorHex: _getCategoryColor(item),
                  onRefresh: _loadData,
                  onInstanceUpdated: _updateInstanceInLocalState,
                  onInstanceDeleted: _removeInstanceFromLocalState,
                  onHabitUpdated: (updated) => {},
                  onHabitDeleted: (deleted) async => _loadData(),
                  isHabit: isHabit,
                  showTypeIcon: true,
                  showRecurringIcon: true,
                );
              },
              childCount: items.length,
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

  String _getCategoryColor(ActivityInstanceRecord instance) {
    final category = _categories
        .firstWhereOrNull((c) => c.name == instance.templateCategoryName);
    if (category == null) {
      print(
          'QueuePage: Could not find category for instance ${instance.templateName} with category name: ${instance.templateCategoryName}');
    }
    return category?.color ?? '#000000';
  }

  // Recent Completions UI is now handled via standard sections and ItemComponent

  /// Update instance in local state and recalculate progress
  void _updateInstanceInLocalState(
      ActivityInstanceRecord updatedInstance) async {
    setState(() {
      final index = _instances.indexWhere(
          (inst) => inst.reference.id == updatedInstance.reference.id);
      if (index != -1) {
        _instances[index] = updatedInstance;
      }
    });

    // Recalculate progress for instant updates
    _calculateProgress();
  }

  /// Remove instance from local state and recalculate progress
  void _removeInstanceFromLocalState(
      ActivityInstanceRecord deletedInstance) async {
    setState(() {
      _instances.removeWhere(
          (inst) => inst.reference.id == deletedInstance.reference.id);
    });

    // Recalculate progress for instant updates
    _calculateProgress();
  }
}
