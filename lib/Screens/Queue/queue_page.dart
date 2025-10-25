import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/background_scheduler.dart';
import 'package:habit_tracker/Helper/backend/day_end_scheduler.dart';
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
import 'package:habit_tracker/Helper/utils/expansion_state_manager.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Screens/Queue/weekly_view.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';
import 'package:habit_tracker/Helper/utils/window_display_helper.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Screens/Progress/progress_page.dart';
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
  String? _expandedSection;
  final Map<String, GlobalKey> _sectionKeys = {};
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  bool _shouldReloadOnReturn = false;
  // Progress tracking variables
  double _dailyTarget = 0.0;
  double _pointsEarned = 0.0;
  double _dailyPercentage = 0.0;
  // Removed legacy Recent Completions expansion state; now uses standard sections
  // Search functionality
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();
  @override
  void initState() {
    super.initState();
    _loadExpansionState();
    _loadData();
    NotificationCenter.addObserver(this, 'loadData', (param) {
      if (mounted) {
        setState(() {
          _loadData();
        });
      }
    });
    // Listen for category updates to refresh data
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        _silentRefreshInstances();
      }
    });
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
    _searchManager.removeListener(_onSearchChanged);
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
  Future<void> _loadExpansionState() async {
    final expandedSection =
        await ExpansionStateManager().getQueueExpandedSection();
    if (mounted) {
      setState(() {
        _expandedSection = expandedSection;
      });
    }
  }
  void _onSearchChanged(String query) {
    if (mounted) {
      setState(() {
        _searchQuery = query;
      });
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
        // Count instances by type
        int taskCount = 0;
        int habitCount = 0;
        for (final inst in allInstances) {
          if (inst.templateCategoryType == 'task') taskCount++;
          if (inst.templateCategoryType == 'habit') habitCount++;
        }
        print(
            'QueuePage: Loaded ${allInstances.length} instances ($taskCount tasks, $habitCount habits)');
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
      if (mounted) setState(() => _isLoading = false);
    }
  }
  /// Calculate progress for today's habits and tasks
  /// Uses shared DailyProgressCalculator for consistency with historical data
  void _calculateProgress() async {
    // Separate habit and task instances
    final habitInstances = _instances
        .where((inst) => inst.templateCategoryType == 'habit')
        .toList();
    final taskInstances = _instances
        .where((inst) => inst.templateCategoryType == 'task')
        .toList();
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
    // Simple progress summary
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
        return isWithinWindow;
      }
      // Fallback to due date check if no window
      final isDueToday = dueDate.isAtSameMomentAs(today);
      return isDueToday;
    }
    // For tasks: only if due today or overdue
    final isTodayOrOverdue =
        dueDate.isAtSameMomentAs(today) || dueDate.isBefore(today);
    return isTodayOrOverdue;
  }
  // Removed _wasCompletedToday - now handled by DailyProgressCalculator
  bool _isInstanceCompleted(ActivityInstanceRecord instance) {
    return instance.status == 'completed' || instance.status == 'skipped';
  }
  Map<String, List<ActivityInstanceRecord>> get _bucketedItems {
    final Map<String, List<ActivityInstanceRecord>> buckets = {
      'Overdue': [],
      'Pending': [],
      'Needs Processing': [],
      'Completed/Skipped': [],
    };
    final today = _todayDate();
    // Filter instances by search query if active
    final instancesToProcess = _instances.where((instance) {
      if (_searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
    }).toList();
    for (final instance in instancesToProcess) {
      // Don't skip completed/skipped instances here - they'll be handled in the Completed/Skipped section
      if (_isInstanceCompleted(instance)) {
        continue;
      }
      // Skip snoozed instances from main processing (they'll be handled in Completed/Skipped section)
      if (instance.snoozedUntil != null &&
          DateTime.now().isBefore(instance.snoozedUntil!)) {
        continue;
      }
      final dueDate = instance.dueDate;
      if (dueDate == null) {
        // Skip instances without due dates (no "Later" section)
        continue;
      }
      final dateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
      // Check for expired habit instances that need processing
      if (instance.templateCategoryType == 'habit' &&
          instance.windowEndDate != null &&
          instance.status == 'pending') {
        final windowEndDate = DateTime(
          instance.windowEndDate!.year,
          instance.windowEndDate!.month,
          instance.windowEndDate!.day,
        );
        if (windowEndDate.isBefore(today)) {
          buckets['Needs Processing']!.add(instance);
          continue;
        }
      }
      // OVERDUE: Only tasks that are overdue
      if (dateOnly.isBefore(today) && instance.templateCategoryType == 'task') {
        buckets['Overdue']!.add(instance);
      }
      // PENDING: Both habits and tasks for today
      else if (_isTodayOrOverdue(instance)) {
        buckets['Pending']!.add(instance);
      }
      // Skip anything beyond today (no "Later" section)
    }
    // Populate Completed/Skipped (completed or skipped TODAY only)
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    for (final instance in instancesToProcess) {
      if (instance.status != 'completed' && instance.status != 'skipped')
        continue;
      // For completed items, check completion date
      if (instance.status == 'completed') {
        if (instance.completedAt == null) {
          continue;
        }
        final completedAt = instance.completedAt!;
        final completedDateOnly =
            DateTime(completedAt.year, completedAt.month, completedAt.day);
        final isToday = completedDateOnly.isAtSameMomentAs(todayStart);
        if (isToday) {
          buckets['Completed/Skipped']!.add(instance);
        }
      }
      // For skipped items, check skipped date
      else if (instance.status == 'skipped') {
        if (instance.skippedAt == null) {
          continue;
        }
        final skippedAt = instance.skippedAt!;
        final skippedDateOnly =
            DateTime(skippedAt.year, skippedAt.month, skippedAt.day);
        final isToday = skippedDateOnly.isAtSameMomentAs(todayStart);
        if (isToday) {
          buckets['Completed/Skipped']!.add(instance);
        }
      }
    }
    // Add snoozed instances to Completed/Skipped section (only if due today)
    for (final instance in instancesToProcess) {
      if (instance.snoozedUntil != null &&
          DateTime.now().isBefore(instance.snoozedUntil!)) {
        // Only show snoozed items if their original due date was today
        final dueDate = instance.dueDate;
        if (dueDate != null) {
          final dueDateOnly =
              DateTime(dueDate.year, dueDate.month, dueDate.day);
          if (dueDateOnly.isAtSameMomentAs(todayStart)) {
            buckets['Completed/Skipped']!.add(instance);
          }
        }
      }
    }
    // Sort items within each bucket by queue order
    for (final key in buckets.keys) {
      final items = buckets[key]!;
      if (items.isNotEmpty) {
        // Initialize order values for items that don't have them
        InstanceOrderService.initializeOrderValues(items, 'queue');
        // Sort by queue order
        buckets[key] =
            InstanceOrderService.sortInstancesByOrder(items, 'queue');
      }
    }
    // Auto-expand sections with search results
    if (_searchQuery.isNotEmpty) {
      for (final key in buckets.keys) {
        if (buckets[key]!.isNotEmpty) {
          _expandedSection = key;
          break; // Expand the first section with results
        }
      }
    }
    return buckets;
  }
  String _getSubtitle(ActivityInstanceRecord item, String bucketKey) {
    if (bucketKey == 'Completed/Skipped') {
      // For completed/skipped habits with completion windows, show next window info
      if (item.templateCategoryType == 'habit' &&
          WindowDisplayHelper.hasCompletionWindow(item)) {
        return WindowDisplayHelper.getNextWindowStartSubtitle(item);
      }
      String statusText;
      // Check if item is snoozed first
      if (item.snoozedUntil != null &&
          DateTime.now().isBefore(item.snoozedUntil!)) {
        statusText = 'Snoozed';
      } else if (item.status == 'completed') {
        statusText = 'Completed';
      } else if (item.status == 'skipped') {
        statusText = 'Skipped';
      } else {
        statusText = 'Unknown';
      }
      final due = item.dueDate;
      final dueStr = due != null ? DateFormat.MMMd().format(due) : 'No due';
      final timeStr = item.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(item.dueTime)}'
          : '';
      final subtitle =
          '$statusText • ${item.templateCategoryName} • Due: $dueStr$timeStr';
      return subtitle;
    }
    if (bucketKey == 'Pending') {
      // For habits with completion windows, show when window ends
      if (item.templateCategoryType == 'habit' &&
          WindowDisplayHelper.hasCompletionWindow(item)) {
        return WindowDisplayHelper.getWindowEndSubtitle(item);
      }
      // Show category name + due time if available
      String subtitle = item.templateCategoryName;
      if (item.hasDueTime()) {
        subtitle += ' @ ${TimeUtils.formatTimeForDisplay(item.dueTime)}';
      }
      return subtitle;
    }
    final dueDate = item.dueDate;
    if (dueDate != null) {
      final formattedDate = DateFormat.MMMd().format(dueDate);
      final timeStr = item.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(item.dueTime)}'
          : '';
      return '$formattedDate$timeStr • ${item.templateCategoryName}';
    }
    return item.templateCategoryName;
  }
  DateTime _todayDate() {
    return DateService.todayStart;
  }
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: Column(
          children: [
            // Tab bar
            TabBar(
              tabs: [
                Tab(
                  text: 'Today',
                ),
                Tab(
                  text: 'This Week',
                ),
              ],
            ),
            const Divider(height: 1),
            // Tab content
            Expanded(
              child: TabBarView(
                children: [
                  _buildDailyTabContent(),
                  const WeeklyView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildDailyTabContent() {
    return Stack(
      children: [
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Progress indicator
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProgressPage(),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ProgressDonutChart(
                              percentage: _dailyPercentage,
                              totalTarget: _dailyTarget,
                              pointsEarned: _pointsEarned,
                              size: 90,
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Daily Progress',
                                  style: FlutterFlowTheme.of(context)
                                      .titleMedium
                                      .override(
                                        fontFamily: 'Readex Pro',
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_pointsEarned.toStringAsFixed(1)} / ${_dailyTarget.toStringAsFixed(1)} points',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        fontFamily: 'Readex Pro',
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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
      'Pending',
      'Needs Processing',
      'Completed/Skipped'
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
      final expanded = _expandedSection == key;
      // Get or create GlobalKey for this section
      if (!_sectionKeys.containsKey(key)) {
        _sectionKeys[key] = GlobalKey();
      }
      slivers.add(
        SliverToBoxAdapter(
          child: Container(
            key: _sectionKeys[key],
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
                    if (key == 'Needs Processing')
                      Text(
                        'These habits have expired windows and need processing',
                        style: theme.bodySmall.override(
                          fontFamily: 'Readex Pro',
                          color: theme.error,
                        ),
                      ),
                  ],
                ),
                GestureDetector(
                  onTap: () {
                    if (mounted) {
                      setState(() {
                        if (expanded) {
                          // Collapse current section
                          _expandedSection = null;
                        } else {
                          // Expand this section (accordion behavior)
                          _expandedSection = key;
                        }
                      });
                      // Save state persistently
                      ExpansionStateManager()
                          .setQueueExpandedSection(_expandedSection);
                      // Scroll to make the newly expanded section visible
                      if (_expandedSection == key) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_sectionKeys[key]?.currentContext != null) {
                            Scrollable.ensureVisible(
                              _sectionKeys[key]!.currentContext!,
                              duration: Duration.zero,
                              alignment: 0.0,
                              alignmentPolicy: ScrollPositionAlignmentPolicy
                                  .keepVisibleAtEnd,
                            );
                          }
                        });
                      }
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
        // Add Process Expired button for Needs Processing section
        if (key == 'Needs Processing') {
          slivers.add(
            SliverToBoxAdapter(
              child: Container(
                margin: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _processExpiredInstances,
                        icon: Icon(Icons.refresh),
                        label: Text('Process Expired Instances'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.error,
                          foregroundColor: theme.primaryBackground,
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        slivers.add(
          SliverReorderableList(
            itemBuilder: (context, index) {
              final item = items[index];
              final isHabit = item.templateCategoryType == 'habit';
              return ReorderableDelayedDragStartListener(
                index: index,
                key: Key('${item.reference.id}_drag'),
                child: ItemComponent(
                  key: Key(item.reference.id),
                  subtitle: _getSubtitle(item, key),
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
                  showCompleted: key == 'Completed/Skipped' ? true : null,
                ),
              );
            },
            itemCount: items.length,
            onReorder: (oldIndex, newIndex) =>
                _handleReorder(oldIndex, newIndex, key),
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
      } else {
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
    // Recalculate progress for instant updates
    _calculateProgress();
  }
  void _handleInstanceUpdated(ActivityInstanceRecord instance) {
    setState(() {
      final index = _instances
          .indexWhere((inst) => inst.reference.id == instance.reference.id);
      if (index != -1) {
        _instances[index] = instance;
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
    // Recalculate progress for instant updates
    _calculateProgress();
  }
  /// Silent refresh instances without loading indicator
  Future<void> _silentRefreshInstances() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;
      final allInstances = await queryAllInstances(userId: userId);
      final habitCategories = await queryHabitCategoriesOnce(userId: userId);
      final taskCategories = await queryTaskCategoriesOnce(userId: userId);
      final allCategories = [...habitCategories, ...taskCategories];
      if (mounted) {
        setState(() {
          _instances = allInstances;
          _categories = allCategories;
          // Don't touch _isLoading
        });
        _calculateProgress();
      }
    } catch (e) {
    }
  }
  Future<void> _processExpiredInstances() async {
    try {
      // Show loading indicator
      setState(() => _isLoading = true);
      // Find the oldest expired instance to determine the date to process
      final buckets = _bucketedItems;
      final expiredInstances = buckets['Needs Processing'] ?? [];
      if (expiredInstances.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }
      // Find the oldest window end date among expired instances
      DateTime? oldestWindowEnd;
      for (final instance in expiredInstances) {
        if (instance.windowEndDate != null) {
          final windowEndDate = DateTime(
            instance.windowEndDate!.year,
            instance.windowEndDate!.month,
            instance.windowEndDate!.day,
          );
          if (oldestWindowEnd == null ||
              windowEndDate.isBefore(oldestWindowEnd)) {
            oldestWindowEnd = windowEndDate;
          }
        }
      }
      if (oldestWindowEnd != null) {
        await BackgroundScheduler.triggerDayEndProcessing(
            targetDate: oldestWindowEnd);
        // Refresh the data
        await _loadData();
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully processed expired instances'),
            backgroundColor: FlutterFlowTheme.of(context).success,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing expired instances: $e'),
          backgroundColor: FlutterFlowTheme.of(context).error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
  /// Handle reordering of items within a section
  Future<void> _handleReorder(
      int oldIndex, int newIndex, String sectionKey) async {
    try {
      final buckets = _bucketedItems;
      final items = buckets[sectionKey]!;
      if (oldIndex >= items.length || newIndex >= items.length) return;
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
      // Update order values in the local _instances list
      for (int i = 0; i < reorderedItems.length; i++) {
        final instance = reorderedItems[i];
        final index = _instances
            .indexWhere((inst) => inst.reference.id == instance.reference.id);
        if (index != -1) {
          // Create updated instance with new queue order by creating new data map
          final updatedData = Map<String, dynamic>.from(instance.snapshotData);
          updatedData['queueOrder'] = i;
          final updatedInstance = ActivityInstanceRecord.getDocumentFromData(
            updatedData,
            instance.reference,
          );
          _instances[index] = updatedInstance;
        }
      }
      // Trigger setState to update UI immediately (eliminates twitch)
      if (mounted) {
        setState(() {
          // State is already updated above
        });
      }
      // Perform database update in background
      await InstanceOrderService.reorderInstancesInSection(
        reorderedItems,
        'queue',
        oldIndex,
        newIndex,
      );
    } catch (e) {
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
  /// Show snooze bottom sheet for day-end processing
  void showSnoozeBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SnoozeBottomSheet(),
    );
  }
}
/// Snooze bottom sheet widget
class _SnoozeBottomSheet extends StatefulWidget {
  @override
  _SnoozeBottomSheetState createState() => _SnoozeBottomSheetState();
}
class _SnoozeBottomSheetState extends State<_SnoozeBottomSheet> {
  bool _isLoading = false;
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final snoozeStatus = DayEndScheduler.getSnoozeStatus();
    return Container(
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.secondaryText,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Title
          Text(
            'Day Ending Soon',
            style: theme.headlineSmall.override(
              fontFamily: 'Outfit',
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // Description
          Text(
            'You have ${snoozeStatus['remainingSnooze']} minutes of snooze time remaining. Extend your day to finish more tasks!',
            style: theme.bodyMedium.override(
              fontFamily: 'Readex Pro',
              color: theme.secondaryText,
            ),
          ),
          const SizedBox(height: 24),
          // Current processing time
          if (snoozeStatus['scheduledTime'] != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.secondaryBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.alternate),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    color: theme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Processing Time',
                          style: theme.bodySmall.override(
                            fontFamily: 'Readex Pro',
                            color: theme.secondaryText,
                          ),
                        ),
                        Text(
                          _formatTime(
                              DateTime.parse(snoozeStatus['scheduledTime'])),
                          style: theme.bodyMedium.override(
                            fontFamily: 'Readex Pro',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          // Snooze buttons
          Text(
            'Snooze Options',
            style: theme.titleMedium.override(
              fontFamily: 'Readex Pro',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SnoozeButton(
                  minutes: 15,
                  label: '15 min',
                  enabled: snoozeStatus['canSnooze15'],
                  onPressed: () => _handleSnooze(15),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SnoozeButton(
                  minutes: 30,
                  label: '30 min',
                  enabled: snoozeStatus['canSnooze30'],
                  onPressed: () => _handleSnooze(30),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SnoozeButton(
                  minutes: 60,
                  label: '1 hr',
                  enabled: snoozeStatus['canSnooze60'],
                  onPressed: () => _handleSnooze(60),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // View Tasks button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: theme.primaryText,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'View Tasks',
                style: theme.titleMedium.override(
                  fontFamily: 'Readex Pro',
                  color: theme.primaryText,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
  String _formatTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }
  Future<void> _handleSnooze(int minutes) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final success = await DayEndScheduler.snooze(minutes);
      if (success) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Day-end processing snoozed for $minutes minutes'),
              backgroundColor: FlutterFlowTheme.of(context).success,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot snooze - maximum time limit reached'),
              backgroundColor: FlutterFlowTheme.of(context).error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error snoozing: $e'),
            backgroundColor: FlutterFlowTheme.of(context).error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
/// Snooze button widget
class _SnoozeButton extends StatelessWidget {
  final int minutes;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  const _SnoozeButton({
    required this.minutes,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? theme.primary : theme.secondaryBackground,
        foregroundColor: enabled ? theme.primaryText : theme.secondaryText,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: enabled ? 2 : 0,
      ),
      child: Text(
        label,
        style: theme.bodyMedium.override(
          fontFamily: 'Readex Pro',
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
