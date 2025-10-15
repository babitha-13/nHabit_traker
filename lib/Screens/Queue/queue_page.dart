import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/daily_progress_calculator.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/progress_donut_chart.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/backend/today_progress_state.dart';
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
    'Tomorrow': false, // Collapsed by default
    'This Week': false, // Collapsed by default
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

    // Listen for instance events
    NotificationCenter.addObserver(this, InstanceEvents.instanceCreated,
        (param) {
      if (param is ActivityInstanceRecord && mounted) {
        _handleInstanceCreated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceUpdated,
        (param) {
      if (param is ActivityInstanceRecord && mounted) {
        _handleInstanceUpdated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceDeleted,
        (param) {
      if (param is ActivityInstanceRecord && mounted) {
        _handleInstanceDeleted(param);
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

  /// Calculate progress for today's habits and tasks
  /// Uses shared DailyProgressCalculator for consistency with historical data
  void _calculateProgress() async {
    print('QueuePage: _calculateProgress() called');
    print('  - Total instances: ${_instances.length}');

    // Separate habit and task instances
    final habitInstances = _instances
        .where((inst) => inst.templateCategoryType == 'habit')
        .toList();
    final taskInstances = _instances
        .where((inst) => inst.templateCategoryType == 'task')
        .toList();

    print('  - Habit instances: ${habitInstances.length}');
    print('  - Task instances: ${taskInstances.length}');

    // Use the shared calculator - same logic as DayEndProcessor
    final progressData = await DailyProgressCalculator.calculateTodayProgress(
      userId: currentUserUid,
      allInstances: habitInstances,
      categories: _categories,
      taskInstances: taskInstances,
    );

    _dailyTarget = progressData['target'] as double;
    _pointsEarned = progressData['earned'] as double;
    _dailyPercentage = progressData['percentage'] as double;

    // Extract breakdown for detailed logging
    final habitTarget = progressData['habitTarget'] as double;
    final habitEarned = progressData['habitEarned'] as double;
    final taskTarget = progressData['taskTarget'] as double;
    final taskEarned = progressData['taskEarned'] as double;

    // Debug logging
    print('QueuePage: Progress calculation (via DailyProgressCalculator):');
    print(
        '  - Total target: $_dailyTarget (Habits: $habitTarget, Tasks: $taskTarget)');
    print(
        '  - Total earned: $_pointsEarned (Habits: $habitEarned, Tasks: $taskEarned)');
    print('  - Percentage: $_dailyPercentage%');

    // Update UI with new progress values immediately
    if (mounted) {
      setState(() {
        // Progress values are already updated above
      });
    }

    // Publish to shared state for other pages (after UI update)
    TodayProgressState().updateProgress(
      target: _dailyTarget,
      earned: _pointsEarned,
      percentage: _dailyPercentage,
    );
  }

  /// Check if instance is due today or overdue
  bool _isTodayOrOverdue(ActivityInstanceRecord instance) {
    if (instance.dueDate == null) return true; // No due date = today

    final today = _todayDate();
    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);

    // For habits: include if today is within the window [dueDate, windowEndDate]
    if (instance.templateCategoryType == 'habit') {
      final windowEnd = instance.windowEndDate;

      if (windowEnd != null) {
        // Today should be >= dueDate AND <= windowEnd
        final isWithinWindow = !today.isBefore(dueDate) &&
            !today.isAfter(
                DateTime(windowEnd.year, windowEnd.month, windowEnd.day));

        print(
            'QueuePage: _isTodayOrOverdue check for ${instance.templateName}:');
        print('  - Today: $today');
        print('  - Due Date: $dueDate');
        print('  - Window End: ${windowEnd}');
        print('  - Is within window: $isWithinWindow');

        return isWithinWindow;
      }

      // Fallback to due date check if no window
      final isDueToday = dueDate.isAtSameMomentAs(today);
      print(
          'QueuePage: _isTodayOrOverdue check for ${instance.templateName} (no window):');
      print('  - Today: $today');
      print('  - Due Date: $dueDate');
      print('  - Is due today: $isDueToday');

      return isDueToday;
    }

    // For tasks: only if due today or overdue
    final isTodayOrOverdue =
        dueDate.isAtSameMomentAs(today) || dueDate.isBefore(today);

    print('QueuePage: _isTodayOrOverdue check for ${instance.templateName}:');
    print('  - Today: $today');
    print('  - Due Date: $dueDate');
    print('  - Is today or overdue: $isTodayOrOverdue');

    return isTodayOrOverdue;
  }

  // Removed _wasCompletedToday - now handled by DailyProgressCalculator

  bool _isInstanceCompleted(ActivityInstanceRecord instance) {
    return instance.status == 'completed' || instance.status == 'skipped';
  }

  Map<String, List<ActivityInstanceRecord>> get _bucketedItems {
    final Map<String, List<ActivityInstanceRecord>> buckets = {
      'Overdue': [],
      'Today': [],
      'Tomorrow': [],
      'This Week': [],
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

      // Skip snoozed instances
      if (instance.snoozedUntil != null &&
          DateTime.now().isBefore(instance.snoozedUntil!)) {
        print(
            '  ${instance.templateName}: SKIPPED (snoozed until ${instance.snoozedUntil})');
        continue;
      }

      final dueDate = instance.dueDate;
      if (dueDate == null) {
        // Skip instances without due dates (no "Later" section)
        print('  ${instance.templateName}: SKIPPED (no due date)');
        continue;
      }
      final dateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);

      // OVERDUE: Only tasks that are overdue
      if (dateOnly.isBefore(today) && instance.templateCategoryType == 'task') {
        buckets['Overdue']!.add(instance);
        print('  ${instance.templateName}: OVERDUE (task)');
      }
      // TODAY: Both habits and tasks for today
      else if (_isTodayOrOverdue(instance)) {
        buckets['Today']!.add(instance);
        print('  ${instance.templateName}: TODAY (within window or due today)');
      }
      // TOMORROW: Both habits and tasks for tomorrow
      else if (_isSameDay(dateOnly, _tomorrowDate())) {
        buckets['Tomorrow']!.add(instance);
        print('  ${instance.templateName}: TOMORROW');
      }
      // THIS WEEK: Both habits and tasks for this week
      else if (!dateOnly.isAfter(endOfWeek)) {
        buckets['This Week']!.add(instance);
        print('  ${instance.templateName}: THIS WEEK');
      }
      // Skip anything beyond this week (no "Later" section)
      else {
        print('  ${instance.templateName}: SKIPPED (beyond this week)');
      }
    }

    // Populate Recent Completions (completed today or yesterday)
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    for (final instance in _instances) {
      if (instance.status != 'completed') continue;
      print(
          'QueuePage: Processing completed instance ${instance.templateName}');
      print('  - Status: ${instance.status}');
      print('  - CompletedAt: ${instance.completedAt}');
      if (instance.completedAt == null) {
        print('  - SKIPPED: completedAt is null');
        continue;
      }
      final completedDate = instance.completedAt!;
      final completedDateOnly =
          DateTime(completedDate.year, completedDate.month, completedDate.day);
      final isRecent = completedDateOnly.isAfter(yesterdayStart) ||
          completedDateOnly.isAtSameMomentAs(yesterdayStart);
      print('  - Completed date only: $completedDateOnly');
      print('  - Yesterday start: $yesterdayStart');
      print('  - Is recent: $isRecent');
      if (isRecent) {
        buckets['Recent Completions']!.add(instance);
        print('  - ADDED to Recent Completions');
      } else {
        print('  - NOT recent enough');
      }
    }

    return buckets;
  }

  String _getSubtitle(ActivityInstanceRecord item, String bucketKey) {
    if (bucketKey == 'Recent Completions') {
      print(
          'QueuePage: _getSubtitle for Recent Completions - ${item.templateName}');
      print('  - CompletedAt: ${item.completedAt}');
      print('  - Status: ${item.status}');
      if (item.completedAt == null) {
        print('  - ERROR: completedAt is null!');
        return 'Completed • ${item.templateCategoryName} • Error: No completion date';
      }
      final completedAt = item.completedAt!;
      final completedStr =
          _isSameDay(completedAt, DateTime.now()) ? 'Today' : 'Yesterday';
      final due = item.dueDate;
      final dueStr = due != null ? DateFormat.MMMd().format(due) : 'No due';
      final icon = item.templateCategoryType == 'task' ? '📋' : '🔁';
      final subtitle =
          'Completed $completedStr • ${item.templateCategoryName} • Due: $dueStr • $icon';
      print('  - Generated subtitle: $subtitle');
      return subtitle;
    }

    if (bucketKey == 'Today' || bucketKey == 'Tomorrow') {
      // For habits, show window countdown
      if (item.templateCategoryType == 'habit' && item.windowEndDate != null) {
        final daysLeft = _getWindowDaysLeft(item);
        if (daysLeft > 0) {
          return '${item.templateCategoryName} • $daysLeft days left';
        } else {
          return item.templateCategoryName;
        }
      }
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
    return DateService.todayStart;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _tomorrowDate() => _todayDate().add(const Duration(days: 1));

  String _getDayEndCountdown() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    final hours = timeUntilMidnight.inHours;
    final minutes = timeUntilMidnight.inMinutes % 60;

    if (hours > 0) {
      return 'Day ends in ${hours}h ${minutes}m';
    } else {
      return 'Day ends in ${minutes}m';
    }
  }

  /// Calculate days left in habit window
  int _getWindowDaysLeft(ActivityInstanceRecord item) {
    if (item.windowEndDate == null) return 0;

    final today = _todayDate();
    final windowEnd = DateTime(item.windowEndDate!.year,
        item.windowEndDate!.month, item.windowEndDate!.day);

    final daysLeft = windowEnd.difference(today).inDays;
    return daysLeft >= 0 ? daysLeft : 0;
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$key (${items.length})',
                      style: theme.titleMedium.override(
                        fontFamily: 'Readex Pro',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
                  showCompleted: key == 'Recent Completions' ? true : null,
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
    print(
        'QueuePage: _updateInstanceInLocalState called for ${updatedInstance.templateName}');
    print('  - Status: ${updatedInstance.status}');
    print('  - Current Value: ${updatedInstance.currentValue}');
    print('  - Category Type: ${updatedInstance.templateCategoryType}');

    setState(() {
      final index = _instances.indexWhere(
          (inst) => inst.reference.id == updatedInstance.reference.id);
      if (index != -1) {
        _instances[index] = updatedInstance;
        print('  - Updated instance at index $index');
      } else {
        print('  - Instance not found in local state!');
      }
    });

    // Recalculate progress for instant updates
    print('QueuePage: Triggering _calculateProgress() after instance update');
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

  // Event handlers for live updates
  void _handleInstanceCreated(ActivityInstanceRecord instance) {
    setState(() {
      _instances.add(instance);
    });
    print('QueuePage: Added new instance ${instance.templateName}');
    // Recalculate progress for instant updates
    _calculateProgress();
  }

  void _handleInstanceUpdated(ActivityInstanceRecord instance) {
    setState(() {
      final index = _instances
          .indexWhere((inst) => inst.reference.id == instance.reference.id);
      if (index != -1) {
        _instances[index] = instance;
        print('QueuePage: Updated instance ${instance.templateName}');
      }
    });
    // Recalculate progress for instant updates
    _calculateProgress();
  }

  void _handleInstanceDeleted(ActivityInstanceRecord instance) {
    setState(() {
      _instances
          .removeWhere((inst) => inst.reference.id == instance.reference.id);
    });
    print('QueuePage: Removed instance ${instance.templateName}');
    // Recalculate progress for instant updates
    _calculateProgress();
  }
}
