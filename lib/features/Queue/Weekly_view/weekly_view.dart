import 'package:flutter/material.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/features/Queue/Weekly_view/weekly_progress_calculator.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/features/Item_component/presentation/item_component_main.dart';
import 'package:habit_tracker/features/Shared/section_expansion_state_manager.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';
import 'package:collection/collection.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class WeeklyView extends StatefulWidget {
  final String searchQuery;
  const WeeklyView({
    super.key,
    this.searchQuery = '',
  });
  @override
  State<WeeklyView> createState() => _WeeklyViewState();
}

class _WeeklyViewState extends State<WeeklyView> {
  final ScrollController _scrollController = ScrollController();
  List<ActivityInstanceRecord> _instances = [];
  List<CategoryRecord> _categories = [];
  Set<String> _expandedSections = {};
  final Map<String, GlobalKey> _sectionKeys = {};
  final Set<String> _quickLogInProgress = {};
  bool _isLoading = true;
  // Optimistic operation tracking
  final Map<String, String> _optimisticOperations =
      {}; // operationId -> instanceId
  // Weekly progress data
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _habits = [];
  DateTime? _weekStart;
  DateTime? _weekEnd;

  List<Map<String, dynamic>> get _filteredTasks {
    if (widget.searchQuery.isEmpty) return _tasks;
    return _tasks.where((task) {
      final name = (task['templateName'] as String?)?.toLowerCase() ?? '';
      return name.contains(widget.searchQuery.toLowerCase());
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredHabits {
    if (widget.searchQuery.isEmpty) return _habits;
    return _habits.where((habit) {
      final name = (habit['templateName'] as String?)?.toLowerCase() ?? '';
      return name.contains(widget.searchQuery.toLowerCase());
    }).toList();
  }

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
  }

  @override
  void didUpdateWidget(covariant WeeklyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery) {
      // No need to reload data, but we might want to ensure expanded sections
      // are updated if we want to auto-expand search results
      if (widget.searchQuery.isNotEmpty) {
        setState(() {
          if (_tasks.any((t) => (t['templateName'] as String)
              .toLowerCase()
              .contains(widget.searchQuery.toLowerCase()))) {
            _expandedSections.add('Tasks');
          }
          if (_habits.any((h) => (h['templateName'] as String)
              .toLowerCase()
              .contains(widget.searchQuery.toLowerCase()))) {
            _expandedSections.add('Habits');
          }
        });
      }
    }
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
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isNotEmpty) {
        final results = await Future.wait([
          queryAllInstances(userId: userId),
          ActivityInstanceService.getRecentCompletedInstances(userId: userId),
          queryHabitCategoriesOnce(
            userId: userId,
            callerTag: 'WeeklyView._loadData.habits',
          ),
          queryTaskCategoriesOnce(
            userId: userId,
            callerTag: 'WeeklyView._loadData.tasks',
          ),
        ]);
        final baseInstances = results[0] as List<ActivityInstanceRecord>;
        final recentCompleted = results[1] as List<ActivityInstanceRecord>;
        final habitCategories = results[2] as List<CategoryRecord>;
        final taskCategories = results[3] as List<CategoryRecord>;
        final allCategories = [...habitCategories, ...taskCategories];
        // Deduplicate instances by reference ID
        final uniqueInstances = <String, ActivityInstanceRecord>{};
        for (final instance in [...baseInstances, ...recentCompleted]) {
          uniqueInstances[instance.reference.id] = instance;
        }
        final mergedInstances = uniqueInstances.values.toList();
        if (mounted) {
          setState(() {
            _instances = mergedInstances;
            _categories = allCategories;
          });
          // Calculate weekly progress and wait for it to complete
          await _calculateWeeklyProgress(userId: userId);
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

  Future<void> _calculateWeeklyProgress({String? userId}) async {
    print('WeeklyView: _calculateWeeklyProgress() called');
    final weekStart = DateService.currentWeekStart;
    final uid = userId ?? await waitForCurrentUserUid();
    if (uid.isEmpty) return;
    // Use the weekly progress calculator
    final progressData = await WeeklyProgressCalculator.calculateWeeklyProgress(
      userId: uid,
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // Show week range
    final weekRangeText = _weekStart != null && _weekEnd != null
        ? '${DateFormat.MMMd().format(_weekStart!)} - ${DateFormat.MMMd().format(_weekEnd!)}'
        : '';
    final filteredTasks = _filteredTasks;
    final filteredHabits = _filteredHabits;
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
                const SizedBox(height: 4),
                Text(
                  'Weekly view is for tracking. Quick + logs to today only.',
                  style: theme.bodySmall.override(
                    color: theme.secondaryText,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    ];
    // Add Tasks section
    if (filteredTasks.isNotEmpty) {
      slivers.add(_buildSectionHeader('Tasks', filteredTasks.length, 'Tasks'));
      if (_expandedSections.contains('Tasks')) {
        slivers.add(_buildTasksList(filteredTasks));
      }
    }
    // Add Habits section
    if (filteredHabits.isNotEmpty) {
      slivers
          .add(_buildSectionHeader('Habits', filteredHabits.length, 'Habits'));
      if (_expandedSections.contains('Habits')) {
        slivers.add(_buildHabitsList(filteredHabits));
      }
    }
    // Show empty state if no items
    if (filteredTasks.isEmpty && filteredHabits.isEmpty) {
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
        SliverToBoxAdapter(
          child: SizedBox(height: 140 + bottomInset),
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
            bottomLeft: expanded
                ? const Radius.circular(12)
                : const Radius.circular(16),
            bottomRight: expanded
                ? const Radius.circular(12)
                : const Radius.circular(16),
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

  Widget _buildTasksList(List<Map<String, dynamic>> tasks) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final task = tasks[index];
          final isOverdue = task['isOverdue'] as bool;
          final nextDueSubtitle = task['nextDueSubtitle'] as String;
          final currentInstance =
              task['currentInstance'] as ActivityInstanceRecord?;
          final displayTrackingType = task['displayTrackingType'] as String;
          final displayUnit = task['displayUnit'] as String;
          final weeklyTarget = task['weeklyTarget'] as double;
          final weeklyCompletion = task['weeklyCompletion'] as double;
          final isRecurring = task['templateIsRecurring'] as bool;
          final isWeeklyTargetMet = task['isWeeklyTargetMet'] as bool? ?? false;
          final templateInstances =
              List<ActivityInstanceRecord>.from(task['instances'] as List);
          final quickLogInstance =
              _findTodayActionableInstance(templateInstances);
          final canQuickLog = quickLogInstance != null &&
              _supportsWeeklyQuickLog(quickLogInstance);
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
            isWeeklyTargetMet: isWeeklyTargetMet,
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
          final itemCard = ItemComponent(
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
            page: 'weekly',
            showQuickLogOnLeft: canQuickLog,
            onQuickLog: canQuickLog
                ? () => _handleWeeklyQuickLog(
                      instance: quickLogInstance,
                      label: currentInstance.templateName,
                    )
                : null,
            showManagementActions: false,
            enableExpandedEdit: false,
            showSwipeTimerAction: false,
          );

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
            child: itemCard,
          );
        },
        childCount: tasks.length,
      ),
    );
  }

  Widget _buildHabitsList(List<Map<String, dynamic>> habits) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final habit = habits[index];
          final currentInstance =
              habit['currentInstance'] as ActivityInstanceRecord?;
          final displayTrackingType = habit['displayTrackingType'] as String;
          final displayUnit = habit['displayUnit'] as String;
          final weeklyTarget = habit['weeklyTarget'] as double;
          final weeklyCompletion = habit['weeklyCompletion'] as double;
          final isWeeklyTargetMet =
              habit['isWeeklyTargetMet'] as bool? ?? false;
          final templateInstances =
              List<ActivityInstanceRecord>.from(habit['instances'] as List);
          final quickLogInstance =
              _findTodayActionableInstance(templateInstances);
          final canQuickLog = quickLogInstance != null &&
              _supportsWeeklyQuickLog(quickLogInstance);
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
            isWeeklyTargetMet: isWeeklyTargetMet,
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
          final itemCard = ItemComponent(
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
            page: 'weekly',
            showQuickLogOnLeft: canQuickLog,
            onQuickLog: canQuickLog
                ? () => _handleWeeklyQuickLog(
                      instance: quickLogInstance,
                      label: currentInstance.templateName,
                    )
                : null,
            showManagementActions: false,
            enableExpandedEdit: false,
            showSwipeTimerAction: false,
          );

          return itemCard;
        },
        childCount: habits.length,
      ),
    );
  }

  bool _supportsWeeklyQuickLog(ActivityInstanceRecord instance) {
    final trackingType = instance.templateTrackingType.toLowerCase();
    return trackingType == 'binary' || trackingType == 'quantitative';
  }

  ActivityInstanceRecord? _findTodayActionableInstance(
    List<ActivityInstanceRecord> instances,
  ) {
    final today = DateService.todayStart;
    for (final instance in instances) {
      if (!instance.isActive || instance.status != 'pending') continue;
      if (_isActionableToday(instance, today)) {
        return instance;
      }
    }
    return null;
  }

  bool _isActionableToday(ActivityInstanceRecord instance, DateTime today) {
    final dueDate = instance.dueDate;
    if (dueDate == null) return false;
    final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
    if (instance.templateCategoryType == 'task') {
      // Mirrors queue behavior: pending tasks due on/before today are actionable.
      return !dueDateOnly.isAfter(today);
    }
    final windowEnd = instance.windowEndDate;
    if (windowEnd != null) {
      final windowEndOnly =
          DateTime(windowEnd.year, windowEnd.month, windowEnd.day);
      return !today.isBefore(dueDateOnly) && !today.isAfter(windowEndOnly);
    }
    return dueDateOnly.isAtSameMomentAs(today);
  }

  Future<void> _handleWeeklyQuickLog({
    required ActivityInstanceRecord instance,
    required String label,
  }) async {
    final instanceId = instance.reference.id;
    if (_quickLogInProgress.contains(instanceId)) return;
    setState(() {
      _quickLogInProgress.add(instanceId);
    });

    try {
      final trackingType = instance.templateTrackingType.toLowerCase();
      if (trackingType == 'quantitative') {
        final currentValue = instance.currentValue;
        final current = currentValue is num ? currentValue.toDouble() : 0.0;
        await ActivityInstanceService.updateInstanceProgress(
          instanceId: instanceId,
          currentValue: current + 1,
          referenceTime: DateService.currentDate,
        );
      } else if (trackingType == 'binary') {
        await ActivityInstanceService.completeInstance(
          instanceId: instanceId,
        );
      }

      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logged today for $label')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not log today: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _quickLogInProgress.remove(instanceId);
        });
      }
    }
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
    double weeklyCompletion, {
    bool isWeeklyTargetMet = false,
  }) {
    // Create a copy of the original instance with modified tracking type and values
    // This is for display purposes only in the weekly view
    return ActivityInstanceRecord.getDocumentFromData(
      {
        ...originalInstance.snapshotData,
        'templateTrackingType': displayTrackingType,
        'templateUnit': displayUnit,
        'templateTarget': weeklyTarget.toInt(), // Convert double to int
        'currentValue': weeklyCompletion.toInt(), // Convert double to int
        'status': isWeeklyTargetMet ? 'completed' : originalInstance.status,
      },
      originalInstance.reference,
    );
  }

  /// Update instance in local state and recalculate progress
  void _updateInstanceInLocalState(
      ActivityInstanceRecord updatedInstance) async {
    try {
      if (!mounted) return;
      setState(() {
        final index = _instances.indexWhere(
            (inst) => inst.reference.id == updatedInstance.reference.id);
        if (index != -1) {
          _instances[index] = updatedInstance;
        } else {}
      });
      // Recalculate weekly progress for instant updates
      print(
          'WeeklyView: Triggering _calculateWeeklyProgress() after instance update');
      await _calculateWeeklyProgress();
    } catch (e) {
      print('WeeklyView: Error in _updateInstanceInLocalState: $e');
    }
  }

  /// Remove instance from local state and recalculate progress
  void _removeInstanceFromLocalState(
      ActivityInstanceRecord deletedInstance) async {
    try {
      if (!mounted) return;
      setState(() {
        _instances.removeWhere(
            (inst) => inst.reference.id == deletedInstance.reference.id);
      });
      // Recalculate weekly progress for instant updates
      await _calculateWeeklyProgress();
    } catch (e) {
      print('WeeklyView: Error in _removeInstanceFromLocalState: $e');
    }
  }

  // Event handlers for live updates
  void _handleInstanceCreated(ActivityInstanceRecord instance) async {
    try {
      if (!mounted) return;
      setState(() {
        _instances.add(instance);
      });
      await _calculateWeeklyProgress();
    } catch (e) {
      print('WeeklyView: Error in _handleInstanceCreated: $e');
    }
  }

  void _handleInstanceUpdated(dynamic param) async {
    try {
      if (!mounted) return;
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

      setState(() {
        final index = _instances
            .indexWhere((inst) => inst.reference.id == instance.reference.id);

        if (index != -1) {
          if (isOptimistic) {
            // Store optimistic state with operation ID for later reconciliation
            _instances[index] = instance;
            if (operationId != null) {
              _optimisticOperations[operationId] = instance.reference.id;
            }
          } else {
            // Reconciled update - replace optimistic state
            _instances[index] = instance;
            if (operationId != null) {
              _optimisticOperations.remove(operationId);
            }
          }
        } else if (!isOptimistic) {
          // New instance from backend (not optimistic) - add it
          _instances.add(instance);
        }
      });
      await _calculateWeeklyProgress();
    } catch (e) {
      print('WeeklyView: Error in _handleInstanceUpdated: $e');
    }
  }

  void _handleRollback(dynamic param) async {
    try {
      if (!mounted) return;
      if (param is Map) {
        final operationId = param['operationId'] as String?;
        final instanceId = param['instanceId'] as String?;
        final originalInstance =
            param['originalInstance'] as ActivityInstanceRecord?;

        if (operationId != null &&
            _optimisticOperations.containsKey(operationId)) {
          setState(() {
            _optimisticOperations.remove(operationId);
            if (originalInstance != null) {
              // Restore from original state
              final index = _instances
                  .indexWhere((inst) => inst.reference.id == instanceId);
              if (index != -1) {
                _instances[index] = originalInstance;
              }
            } else if (instanceId != null) {
              // Fallback to reloading from backend
              _revertOptimisticUpdate(instanceId);
            }
          });
          await _calculateWeeklyProgress();
        }
      }
    } catch (e) {
      print('WeeklyView: Error in _handleRollback: $e');
    }
  }

  Future<void> _revertOptimisticUpdate(String instanceId) async {
    try {
      if (!mounted) return;
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instanceId,
      );
      if (!mounted) return;
      setState(() {
        final index =
            _instances.indexWhere((inst) => inst.reference.id == instanceId);
        if (index != -1) {
          _instances[index] = updatedInstance;
        }
      });
      await _calculateWeeklyProgress();
    } catch (e) {
      // Error reverting - non-critical, will be fixed on next data load
      print('WeeklyView: Error in _revertOptimisticUpdate: $e');
    }
  }

  void _handleInstanceDeleted(ActivityInstanceRecord instance) async {
    try {
      if (!mounted) return;
      setState(() {
        _instances
            .removeWhere((inst) => inst.reference.id == instance.reference.id);
      });
      await _calculateWeeklyProgress();
    } catch (e) {
      print('WeeklyView: Error in _handleInstanceDeleted: $e');
    }
  }
}
