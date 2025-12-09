import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/weekly_progress_calculator.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/expansion_state_manager.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:collection/collection.dart';
import 'dart:async';
import 'package:intl/intl.dart';
class WeeklyView extends StatefulWidget {
  const WeeklyView({super.key});
  @override
  State<WeeklyView> createState() => _WeeklyViewState();
}
class _WeeklyViewState extends State<WeeklyView> {
  final ScrollController _scrollController = ScrollController();
  List<ActivityInstanceRecord> _instances = [];
  List<CategoryRecord> _categories = [];
  Set<String> _expandedSections = {};
  final Map<String, GlobalKey> _sectionKeys = {};
  bool _isLoading = true;
  // Weekly progress data
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _habits = [];
  DateTime? _weekStart;
  DateTime? _weekEnd;
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
        _loadData();
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
  Future<void> _loadExpansionState() async {
    final expandedSections =
        await ExpansionStateManager().getWeeklyExpandedSections();
    if (mounted) {
      setState(() {
        _expandedSections = expandedSections;
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
        if (mounted) {
          setState(() {
            _instances = allInstances;
            _categories = allCategories;
          });
          // Calculate weekly progress and wait for it to complete
          await _calculateWeeklyProgress();
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  Future<void> _calculateWeeklyProgress() async {
    print('WeeklyView: _calculateWeeklyProgress() called');
    final weekStart = DateService.currentWeekStart;
    // Use the weekly progress calculator
    final progressData = await WeeklyProgressCalculator.calculateWeeklyProgress(
      userId: currentUserUid,
      weekStart: weekStart,
      allInstances: _instances,
      categories: _categories,
    );
    if (mounted) {
      _tasks = List<Map<String, dynamic>>.from(progressData['tasks']);
      _habits = List<Map<String, dynamic>>.from(progressData['habits']);
      _weekStart = progressData['weekStart'] as DateTime;
      _weekEnd = progressData['weekEnd'] as DateTime;
    }
  }
  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _buildWeeklyView();
  }
  Widget _buildWeeklyView() {
    final theme = FlutterFlowTheme.of(context);
    // Show week range
    final weekRangeText = _weekStart != null && _weekEnd != null
        ? '${DateFormat.MMMd().format(_weekStart!)} - ${DateFormat.MMMd().format(_weekEnd!)}'
        : '';
    final slivers = <Widget>[
      // Week range header
      SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Weekly Progress',
                style: theme.titleLarge.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (weekRangeText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  weekRangeText,
                  style: theme.bodyMedium.override(
                    color: theme.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
    // Add Tasks section
    if (_tasks.isNotEmpty) {
      slivers.add(_buildSectionHeader('Tasks', _tasks.length, 'Tasks'));
      if (_expandedSections.contains('Tasks')) {
        slivers.add(_buildTasksList());
      }
    }
    // Add Habits section
    if (_habits.isNotEmpty) {
      slivers.add(_buildSectionHeader('Habits', _habits.length, 'Habits'));
      if (_expandedSections.contains('Habits')) {
        slivers.add(_buildHabitsList());
      }
    }
    // Show empty state if no items
    if (_tasks.isEmpty && _habits.isEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_view_week,
                  size: 64,
                  color: theme.secondaryText,
                ),
                const SizedBox(height: 16),
                Text(
                  'No items for this week',
                  style: theme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Create some habits and tasks to see your weekly progress!',
                  style: theme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
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
  Widget _buildSectionHeader(String title, int count, String sectionKey) {
    final expanded = _expandedSections.contains(sectionKey);
    final theme = FlutterFlowTheme.of(context);
    // Get or create GlobalKey for this section
    if (!_sectionKeys.containsKey(sectionKey)) {
      _sectionKeys[sectionKey] = GlobalKey();
    }
    return SliverToBoxAdapter(
      child: Container(
        key: _sectionKeys[sectionKey],
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
                  '$title ($count)',
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
                    if (expanded) {
                      // Collapse this section
                      _expandedSections.remove(sectionKey);
                    } else {
                      // Expand this section
                      _expandedSections.add(sectionKey);
                    }
                  });
                  // Save state persistently
                  ExpansionStateManager()
                      .setWeeklyExpandedSections(_expandedSections);
                  // Scroll to make the newly expanded section visible
                  if (_expandedSections.contains(sectionKey)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_sectionKeys[sectionKey]?.currentContext != null) {
                        Scrollable.ensureVisible(
                          _sectionKeys[sectionKey]!.currentContext!,
                          duration: Duration.zero,
                          alignment: 0.0,
                          alignmentPolicy:
                              ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
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
    );
  }
  Widget _buildTasksList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final task = _tasks[index];
          final isOverdue = task['isOverdue'] as bool;
          final nextDueSubtitle = task['nextDueSubtitle'] as String;
          final currentInstance =
              task['currentInstance'] as ActivityInstanceRecord?;
          final displayTrackingType = task['displayTrackingType'] as String;
          final displayUnit = task['displayUnit'] as String;
          final weeklyTarget = task['weeklyTarget'] as double;
          final weeklyCompletion = task['weeklyCompletion'] as double;
          final isRecurring = task['templateIsRecurring'] as bool;
          if (currentInstance == null) {
            return const SizedBox.shrink();
          }
          // Create display instance with converted tracking type
          final displayInstance = _createDisplayInstance(
            currentInstance,
            displayTrackingType,
            displayUnit,
            weeklyTarget,
            weeklyCompletion,
          );
          // Create subtitle with category name and status information for weekly view
          String subtitle = currentInstance.templateCategoryName;
          // Handle one-off vs recurring tasks differently
          if (!isRecurring) {
            // For one-off tasks, show completion status clearly
            final status = currentInstance.status;
            if (status == 'completed' && currentInstance.completedAt != null) {
              final completedDate = currentInstance.completedAt!;
              final timeStr = currentInstance.hasDueTime()
                  ? ' @ ${TimeUtils.formatTimeForDisplay(currentInstance.dueTime)}'
                  : '';
              subtitle +=
                  ' • ✓ Completed ${DateFormat.MMMd().format(completedDate)}$timeStr';
            } else if (status == 'skipped' &&
                currentInstance.skippedAt != null) {
              final skippedDate = currentInstance.skippedAt!;
              final timeStr = currentInstance.hasDueTime()
                  ? ' @ ${TimeUtils.formatTimeForDisplay(currentInstance.dueTime)}'
                  : '';
              subtitle +=
                  ' • ✗ Skipped ${DateFormat.MMMd().format(skippedDate)}$timeStr';
            } else if (currentInstance.snoozedUntil != null) {
              final snoozedDate = currentInstance.snoozedUntil!;
              subtitle +=
                  ' • ⏰ Snoozed until ${DateFormat.MMMd().format(snoozedDate)}';
            } else {
              // Show original target for pending one-off tasks
              final target = currentInstance.templateTarget;
              final unit = currentInstance.templateUnit;
              if (target != null && unit.isNotEmpty) {
                subtitle += ' • $target $unit';
              }
              // Add due time for pending tasks
              if (currentInstance.hasDueTime()) {
                subtitle +=
                    ' @ ${TimeUtils.formatTimeForDisplay(currentInstance.dueTime)}';
              }
            }
          } else {
            // For recurring tasks, show weekly progress
            final status = currentInstance.status;
            if (status == 'completed' && currentInstance.completedAt != null) {
              final completedDate = currentInstance.completedAt!;
              subtitle +=
                  ' • Completed ${DateFormat.MMMd().format(completedDate)}';
            } else if (status == 'skipped' &&
                currentInstance.skippedAt != null) {
              final skippedDate = currentInstance.skippedAt!;
              subtitle += ' • Skipped ${DateFormat.MMMd().format(skippedDate)}';
            } else if (currentInstance.snoozedUntil != null) {
              final snoozedDate = currentInstance.snoozedUntil!;
              subtitle +=
                  ' • Snoozed until ${DateFormat.MMMd().format(snoozedDate)}';
            }
            // Add next due date for recurring tasks
            if (nextDueSubtitle.isNotEmpty) {
              subtitle += ' • $nextDueSubtitle';
            }
          }
          return Container(
            decoration: isOverdue
                ? BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Colors.red,
                        width: 4,
                      ),
                    ),
                  )
                : null,
            child: ItemComponent(
              subtitle: subtitle,
              key: Key('task_${task['templateId']}'),
              instance: displayInstance,
              categoryColorHex: _getCategoryColor(currentInstance),
              onRefresh: _loadData,
              onInstanceUpdated: _updateInstanceInLocalState,
              onInstanceDeleted: _removeInstanceFromLocalState,
              onHabitUpdated: (updated) => {},
              onHabitDeleted: (deleted) async => _loadData(),
              isHabit: false,
              showTypeIcon: true,
              showRecurringIcon: true,
              showCompleted: true, // Show completed items in weekly view
            ),
          );
        },
        childCount: _tasks.length,
      ),
    );
  }
  Widget _buildHabitsList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final habit = _habits[index];
          final currentInstance =
              habit['currentInstance'] as ActivityInstanceRecord?;
          final displayTrackingType = habit['displayTrackingType'] as String;
          final displayUnit = habit['displayUnit'] as String;
          final weeklyTarget = habit['weeklyTarget'] as double;
          final weeklyCompletion = habit['weeklyCompletion'] as double;
          if (currentInstance == null) {
            return const SizedBox.shrink();
          }
          // Create display instance with converted tracking type
          final displayInstance = _createDisplayInstance(
            currentInstance,
            displayTrackingType,
            displayUnit,
            weeklyTarget,
            weeklyCompletion,
          );
          // Create subtitle with category name and status information for weekly view
          String enhancedSubtitle = currentInstance.templateCategoryName;
          final status = currentInstance.status;
          if (status == 'completed' && currentInstance.completedAt != null) {
            final completedDate = currentInstance.completedAt!;
            final timeStr = currentInstance.hasDueTime()
                ? ' @ ${TimeUtils.formatTimeForDisplay(currentInstance.dueTime)}'
                : '';
            enhancedSubtitle +=
                ' • Completed ${DateFormat.MMMd().format(completedDate)}$timeStr';
          } else if (status == 'skipped' && currentInstance.skippedAt != null) {
            final skippedDate = currentInstance.skippedAt!;
            final timeStr = currentInstance.hasDueTime()
                ? ' @ ${TimeUtils.formatTimeForDisplay(currentInstance.dueTime)}'
                : '';
            enhancedSubtitle +=
                ' • Skipped ${DateFormat.MMMd().format(skippedDate)}$timeStr';
          } else if (currentInstance.snoozedUntil != null) {
            final snoozedDate = currentInstance.snoozedUntil!;
            enhancedSubtitle +=
                ' • Snoozed until ${DateFormat.MMMd().format(snoozedDate)}';
          } else if (currentInstance.hasDueTime()) {
            // Add due time for pending habits
            enhancedSubtitle +=
                ' @ ${TimeUtils.formatTimeForDisplay(currentInstance.dueTime)}';
          }
          return ItemComponent(
            subtitle: enhancedSubtitle,
            key: Key('habit_${habit['templateId']}'),
            instance: displayInstance,
            categoryColorHex: _getCategoryColor(currentInstance),
            onRefresh: _loadData,
            onInstanceUpdated: _updateInstanceInLocalState,
            onInstanceDeleted: _removeInstanceFromLocalState,
            onHabitUpdated: (updated) => {},
            onHabitDeleted: (deleted) async => _loadData(),
            isHabit: true,
            showTypeIcon: false,
            showRecurringIcon: false,
            showCompleted: true, // Show completed items in weekly view
          );
        },
        childCount: _habits.length,
      ),
    );
  }
  String _getCategoryColor(ActivityInstanceRecord instance) {
    final category = _categories
        .firstWhereOrNull((c) => c.name == instance.templateCategoryName);
    return category?.color ?? '#000000';
  }
  /// Create a display instance with converted tracking type for weekly view
  ActivityInstanceRecord _createDisplayInstance(
    ActivityInstanceRecord originalInstance,
    String displayTrackingType,
    String displayUnit,
    double weeklyTarget,
    double weeklyCompletion,
  ) {
    // Create a copy of the original instance with modified tracking type and values
    // This is for display purposes only in the weekly view
    return ActivityInstanceRecord.getDocumentFromData(
      {
        ...originalInstance.snapshotData,
        'templateTrackingType': displayTrackingType,
        'templateUnit': displayUnit,
        'templateTarget': weeklyTarget.toInt(), // Convert double to int
        'currentValue': weeklyCompletion.toInt(), // Convert double to int
      },
      originalInstance.reference,
    );
  }
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
    // Recalculate weekly progress for instant updates
    print(
        'WeeklyView: Triggering _calculateWeeklyProgress() after instance update');
    _calculateWeeklyProgress();
  }
  /// Remove instance from local state and recalculate progress
  void _removeInstanceFromLocalState(
      ActivityInstanceRecord deletedInstance) async {
    setState(() {
      _instances.removeWhere(
          (inst) => inst.reference.id == deletedInstance.reference.id);
    });
    // Recalculate weekly progress for instant updates
    _calculateWeeklyProgress();
  }
  // Event handlers for live updates
  void _handleInstanceCreated(ActivityInstanceRecord instance) {
    setState(() {
      _instances.add(instance);
    });
    _calculateWeeklyProgress();
  }
  void _handleInstanceUpdated(ActivityInstanceRecord instance) {
    setState(() {
      final index = _instances
          .indexWhere((inst) => inst.reference.id == instance.reference.id);
      if (index != -1) {
        _instances[index] = instance;
      }
    });
    _calculateWeeklyProgress();
  }
  void _handleInstanceDeleted(ActivityInstanceRecord instance) {
    setState(() {
      _instances
          .removeWhere((inst) => inst.reference.id == instance.reference.id);
    });
    _calculateWeeklyProgress();
  }
}
