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
import 'package:habit_tracker/Helper/utils/expansion_state_manager.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Screens/Queue/weekly_view.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';
import 'package:habit_tracker/Helper/utils/window_display_helper.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Screens/Progress/progress_page.dart';
import 'package:habit_tracker/Helper/backend/cumulative_score_service.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/utils/cumulative_score_line_painter.dart';
import 'package:habit_tracker/Helper/utils/queue_filter_state_manager.dart'
    show QueueFilterState, QueueFilterStateManager;
import 'package:habit_tracker/Helper/utils/queue_sort_state_manager.dart'
    show QueueSortState, QueueSortStateManager, QueueSortType;
import 'package:habit_tracker/Screens/Queue/queue_filter_dialog.dart';
import 'package:habit_tracker/Helper/backend/points_service.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

class QueuePage extends StatefulWidget {
  final bool expandCompleted;
  const QueuePage({super.key, this.expandCompleted = false});
  @override
  _QueuePageState createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  List<ActivityInstanceRecord> _instances = [];
  List<CategoryRecord> _categories = [];
  Set<String> _expandedSections = {};
  final Map<String, GlobalKey> _sectionKeys = {};
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  bool _shouldReloadOnReturn = false;
  bool _isLoadingData = false; // Guard against concurrent loads
  bool _ignoreInstanceEvents = true; // Ignore events during initial load
  // Progress tracking variables
  double _dailyTarget = 0.0;
  double _pointsEarned = 0.0;
  double _dailyPercentage = 0.0;
  // Cumulative score variables
  double _cumulativeScore = 0.0;
  double _dailyScoreGain = 0.0;
  List<Map<String, dynamic>> _cumulativeScoreHistory = [];
  bool _isLoadingCumulativeScore = false; // Guard against recursive loads
  bool _pendingCumulativeScoreReload = false;
  // Removed legacy Recent Completions expansion state; now uses standard sections
  // Search functionality
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();
  // Filter and sort state
  QueueFilterState _currentFilter = QueueFilterState();
  QueueSortState _currentSort = QueueSortState();
  @override
  void initState() {
    super.initState();
    _loadExpansionState();
    // Load filter and sort state first, then load data to ensure filters are applied correctly
    _loadFilterAndSortState().then((_) {
      _loadData().then((_) {
        // Load cumulative score after main data finishes to avoid Firestore race conditions
        _loadCumulativeScore();
        // Handle auto-expand request from widget constructor
        if (widget.expandCompleted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                NotificationCenter.post('expandQueueSection', 'Completed');
              }
            });
        }
      });
    });
    // Listen for cumulative score updates from Progress page
    NotificationCenter.addObserver(this, 'cumulativeScoreUpdated', (param) {
      if (mounted && !_isLoadingCumulativeScore) {
        setState(() {
          final data = TodayProgressState().getCumulativeScoreData();
          _cumulativeScore = data['cumulativeScore'] as double;
          _dailyScoreGain = data['dailyGain'] as double;
        });
      }
    });
    // Listen for today's progress updates to recalculate cumulative score
    NotificationCenter.addObserver(this, 'todayProgressUpdated', (param) {
      if (!mounted) return;
      if (_isLoadingCumulativeScore) {
        _pendingCumulativeScoreReload = true;
        return;
      }
      _loadCumulativeScore();
    });
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
    // Listen for instance events (but ignore during initial load)
    NotificationCenter.addObserver(this, InstanceEvents.instanceCreated,
        (param) {
      if (param is ActivityInstanceRecord &&
          mounted &&
          !_ignoreInstanceEvents) {
        _handleInstanceCreated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceUpdated,
        (param) {
      if (param is ActivityInstanceRecord &&
          mounted &&
          !_ignoreInstanceEvents) {
        _handleInstanceUpdated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceDeleted,
        (param) {
      if (param is ActivityInstanceRecord &&
          mounted &&
          !_ignoreInstanceEvents) {
        _handleInstanceDeleted(param);
      }
    });
    // Listen for section expansion requests
    NotificationCenter.addObserver(this, 'expandQueueSection', (param) {
      if (mounted && param is String) {
        setState(() {
          _expandedSections.add(param);
          ExpansionStateManager().setQueueExpandedSections(_expandedSections);
        });
        // Scroll to the section after a delay to ensure it's rendered
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sectionKeys[param]?.currentContext != null) {
            Scrollable.ensureVisible(
              _sectionKeys[param]!.currentContext!,
              duration: const Duration(milliseconds: 300),
              alignment: 0.0,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            );
          }
        });
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
    final expandedSections =
        await ExpansionStateManager().getQueueExpandedSections();
    if (mounted) {
      setState(() {
        _expandedSections = expandedSections;
      });
    }
  }

  Future<void> _loadFilterAndSortState() async {
    final filterState = await QueueFilterStateManager().getFilterState();
    final sortState = await QueueSortStateManager().getSortState();
    if (mounted) {
      setState(() {
        _currentFilter = filterState;
        _currentSort = sortState;
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
    // Prevent concurrent loads
    if (_isLoadingData) return;
    _isLoadingData = true;
    _ignoreInstanceEvents = true; // Temporarily ignore events during load
    setState(() => _isLoading = true);
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final allInstances = await queryAllInstances(userId: userId);
        final habitCategories = await queryHabitCategoriesOnce(userId: userId);
        final taskCategories = await queryTaskCategoriesOnce(userId: userId);
        final allCategories = [...habitCategories, ...taskCategories];
        // Deduplicate instances by reference ID to prevent duplicates
        final uniqueInstances = <String, ActivityInstanceRecord>{};
        for (final instance in allInstances) {
          uniqueInstances[instance.reference.id] = instance;
        }
        final deduplicatedInstances = uniqueInstances.values.toList();
        // Count instances by type
        int taskCount = 0;
        int habitCount = 0;
        for (final inst in deduplicatedInstances) {
          if (inst.templateCategoryType == 'task') taskCount++;
          if (inst.templateCategoryType == 'habit') habitCount++;
        }
        print(
            'QueuePage: Loaded ${deduplicatedInstances.length} instances ($taskCount tasks, $habitCount habits)');
        if (mounted) {
          setState(() {
            _instances = deduplicatedInstances;
            _categories = allCategories;

            // Initialize default filter state (all categories selected) if filter is empty
            var updatedFilter = _currentFilter;
            final allHabitNames =
                habitCategories.map((cat) => cat.name).toSet();
            final allTaskNames = taskCategories.map((cat) => cat.name).toSet();

            // If filter state is empty (default), initialize with all categories selected
            if (!_currentFilter.hasAnyFilter) {
              updatedFilter = QueueFilterState(
                allTasks: true,
                allHabits: true,
                selectedHabitCategoryNames: allHabitNames,
                selectedTaskCategoryNames: allTaskNames,
              );
            } else {
              // If filter has allHabits/allTasks true but selected sets are empty,
              // populate them with all category names (handles old saved states)
              if (_currentFilter.allHabits &&
                  _currentFilter.selectedHabitCategoryNames.isEmpty &&
                  habitCategories.isNotEmpty) {
                updatedFilter = QueueFilterState(
                  allTasks: updatedFilter.allTasks,
                  allHabits: updatedFilter.allHabits,
                  selectedHabitCategoryNames: allHabitNames,
                  selectedTaskCategoryNames:
                      updatedFilter.selectedTaskCategoryNames,
                );
              }
              if (updatedFilter.allTasks &&
                  updatedFilter.selectedTaskCategoryNames.isEmpty &&
                  taskCategories.isNotEmpty) {
                updatedFilter = QueueFilterState(
                  allTasks: updatedFilter.allTasks,
                  allHabits: updatedFilter.allHabits,
                  selectedHabitCategoryNames:
                      updatedFilter.selectedHabitCategoryNames,
                  selectedTaskCategoryNames: allTaskNames,
                );
              }
            }
            _currentFilter = updatedFilter;
            _isLoading = false;
            _isLoadingData = false;
          });
          // Calculate progress for today's habits
          _calculateProgress();
          // Enable instance event listeners after initial load completes
          _ignoreInstanceEvents = false;

          // Initialize order values for instances that don't have them (run once after load)
          InstanceOrderService.initializeOrderValues(
              deduplicatedInstances, 'queue');
        } else {
          _isLoadingData = false;
          _ignoreInstanceEvents = false;
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        _isLoadingData = false;
        _ignoreInstanceEvents = false;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _isLoadingData = false;
      _ignoreInstanceEvents = false;
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

  Future<void> _loadCumulativeScore() async {
    // Prevent recursive calls
    if (_isLoadingCumulativeScore) return;

    try {
      _isLoadingCumulativeScore = true;
      final userId = currentUserUid;
      if (userId.isEmpty) {
        _isLoadingCumulativeScore = false;
        return;
      }

      // Use local variables to track score values (setState is async)
      double currentCumulativeScore = 0.0;
      double currentDailyGain = 0.0;

      // First check if the Progress page has already calculated the live score
      final sharedData = TodayProgressState().getCumulativeScoreData();
      if (sharedData['hasLiveScore'] as bool) {
        currentCumulativeScore = sharedData['cumulativeScore'] as double;
        currentDailyGain = sharedData['dailyGain'] as double;
      } else {
        // Calculate the live cumulative score ourselves
        // Get today's progress
        final progressData = TodayProgressState().getProgressData();
        final todayPercentage = progressData['percentage'] ?? 0.0;

        if (todayPercentage > 0) {
          // Calculate projected score including today's progress
          final projectionData =
              await CumulativeScoreService.calculateProjectedDailyScore(
            userId,
            todayPercentage,
          );

          currentCumulativeScore = projectionData['projectedCumulative'] ?? 0.0;
          currentDailyGain = projectionData['projectedGain'] ?? 0.0;

          // Publish to shared state for other pages
          TodayProgressState().updateCumulativeScore(
            cumulativeScore: currentCumulativeScore,
            dailyGain: currentDailyGain,
            hasLiveScore: true,
          );
        } else {
          // No progress today, use base score from Firestore
          final userStats =
              await CumulativeScoreService.getCumulativeScore(userId);
          if (userStats != null) {
            currentCumulativeScore = userStats.cumulativeScore;
            currentDailyGain = userStats.lastDailyGain;

            // Publish base cumulative score to shared state
            TodayProgressState().updateCumulativeScore(
              cumulativeScore: currentCumulativeScore,
              dailyGain: currentDailyGain,
              hasLiveScore: false,
            );
          }
        }
      }

      // Update state with calculated values
      if (mounted) {
        setState(() {
          _cumulativeScore = currentCumulativeScore;
          _dailyScoreGain = currentDailyGain;
        });
      }

      // Load cumulative score history for the last 7 days
      final endDate = DateService.currentDate;
      final startDate = endDate.subtract(const Duration(days: 7));

      final query = await DailyProgressRecord.collectionForUser(userId)
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .orderBy('date', descending: false)
          .get();

      final history = <Map<String, dynamic>>[];
      final today = DateService.currentDate;
      bool todayIncluded = false;

      for (final doc in query.docs) {
        final record = DailyProgressRecord.fromSnapshot(doc);
        if (record.cumulativeScoreSnapshot > 0) {
          history.add({
            'date': record.date,
            'score': record.cumulativeScoreSnapshot,
            'gain': record.dailyScoreGain,
          });
          // Check if today's snapshot is already saved
          if (record.date != null &&
              record.date!.year == today.year &&
              record.date!.month == today.month &&
              record.date!.day == today.day) {
            todayIncluded = true;
          }
        }
      }

      // Add today's live cumulative score if not already in history
      if (!todayIncluded && currentCumulativeScore > 0) {
        history.add({
          'date': today,
          'score': currentCumulativeScore,
          'gain': currentDailyGain,
        });
      }

      if (mounted) {
        setState(() {
          _cumulativeScoreHistory = history;
        });
      }
    } catch (e) {
      print('Error loading cumulative score: $e');
    } finally {
      _isLoadingCumulativeScore = false;
      if (_pendingCumulativeScoreReload) {
        _pendingCumulativeScoreReload = false;
        Future.microtask(_loadCumulativeScore);
      }
    }
  }

  Widget _buildCumulativeScoreMiniGraph() {
    if (_cumulativeScoreHistory.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'No data',
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomPaint(
        painter: CumulativeScoreLinePainter(
          data: _cumulativeScoreHistory,
          minScore: _cumulativeScoreHistory
              .map((d) => d['score'] as double)
              .reduce((a, b) => a < b ? a : b),
          maxScore: _cumulativeScoreHistory
              .map((d) => d['score'] as double)
              .reduce((a, b) => a > b ? a : b),
          scoreRange: _cumulativeScoreHistory
                  .map((d) => d['score'] as double)
                  .reduce((a, b) => a > b ? a : b) -
              _cumulativeScoreHistory
                  .map((d) => d['score'] as double)
                  .reduce((a, b) => a < b ? a : b),
          color: FlutterFlowTheme.of(context).primary,
        ),
        size: const Size(double.infinity, double.infinity),
      ),
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

  /// Apply filter logic to instances
  List<ActivityInstanceRecord> _applyFilters(
      List<ActivityInstanceRecord> instances) {
    // If in default state (all categories selected), show all items (no filtering)
    if (_isDefaultFilterState()) {
      return instances;
    }

    // Check if any categories are actually selected
    final hasSelectedHabits =
        _currentFilter.selectedHabitCategoryNames.isNotEmpty;
    final hasSelectedTasks =
        _currentFilter.selectedTaskCategoryNames.isNotEmpty;

    // If filter was applied but no categories are selected, show nothing
    // (This handles the case where user explicitly unchecks everything)
    if (!hasSelectedHabits && !hasSelectedTasks) {
      return []; // Nothing selected, show nothing
    }

    // Filter based ONLY on which sub-items (categories) are checked
    // "All Habits" and "All Tasks" checkboxes only control checking/unchecking of sub-items,
    // they don't directly affect filtering - filtering is purely based on selected category names
    return instances.where((instance) {
      // Skip instances with empty category name (shouldn't happen, but safety check)
      if (instance.templateCategoryName.isEmpty) {
        return false;
      }
      // Check habits
      if (instance.templateCategoryType == 'habit' &&
          hasSelectedHabits &&
          _currentFilter.selectedHabitCategoryNames
              .contains(instance.templateCategoryName)) {
        return true;
      }
      // Check tasks
      if (instance.templateCategoryType == 'task' &&
          hasSelectedTasks &&
          _currentFilter.selectedTaskCategoryNames
              .contains(instance.templateCategoryName)) {
        return true;
      }
      return false;
    }).toList();
  }

  /// Parse time string (HH:mm) to minutes since midnight
  /// Returns null if parsing fails
  int? _parseTimeToMinutes(String? timeStr) {
    if (timeStr == null) return null;
    final timeValues = timeStr.split(':');
    if (timeValues.length != 2) return null;
    final hour = int.tryParse(timeValues[0]);
    final minute = int.tryParse(timeValues[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  /// Compare two time strings (HH:mm format)
  /// Returns: -1 if timeA < timeB, 0 if equal, 1 if timeA > timeB
  /// Items without time are considered "larger" (go to end)
  int _compareTimes(String? timeA, String? timeB) {
    if (timeA == null && timeB == null) return 0;
    if (timeA == null) return 1; // A has no time, put it after B
    if (timeB == null) return -1; // B has no time, put it after A

    final timeAInt = _parseTimeToMinutes(timeA);
    final timeBInt = _parseTimeToMinutes(timeB);

    if (timeAInt == null && timeBInt == null) return 0;
    if (timeAInt == null) return 1;
    if (timeBInt == null) return -1;

    // Always ascending for time
    return timeAInt.compareTo(timeBInt);
  }

  /// Sort items within a section based on sort state
  List<ActivityInstanceRecord> _sortSectionItems(
      List<ActivityInstanceRecord> items, String sectionKey) {
    // Only sort expanded sections
    if (!_expandedSections.contains(sectionKey) || !_currentSort.isActive) {
      return items;
    }

    final sortedItems = List<ActivityInstanceRecord>.from(items);

    if (_currentSort.sortType == QueueSortType.points) {
      // Sort by daily target points - always descending (highest first)
      sortedItems.sort((a, b) {
        final categoryA = _categories
            .firstWhereOrNull((c) => c.reference.id == a.templateCategoryId);
        final categoryB = _categories
            .firstWhereOrNull((c) => c.reference.id == b.templateCategoryId);

        double pointsA = 0.0;
        double pointsB = 0.0;

        if (categoryA != null) {
          pointsA = PointsService.calculateDailyTarget(a, categoryA);
        }
        if (categoryB != null) {
          pointsB = PointsService.calculateDailyTarget(b, categoryB);
        }

        // Always descending for points
        return pointsB.compareTo(pointsA);
      });
    } else if (_currentSort.sortType == QueueSortType.time) {
      // Sort by time only - date-agnostic, always ascending (earliest time first)
      sortedItems.sort((a, b) {
        final timeA = a.dueTime;
        final timeB = b.dueTime;

        // Items with time come first, sorted by time
        // Items without time go to the end
        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1; // A has no time, put it after B
        if (timeB == null) return -1; // B has no time, put it after A

        // Both have time - parse and compare
        final timeAInt = _parseTimeToMinutes(timeA);
        final timeBInt = _parseTimeToMinutes(timeB);

        if (timeAInt == null && timeBInt == null) return 0;
        if (timeAInt == null) return 1;
        if (timeBInt == null) return -1;

        // Always ascending for time
        return timeAInt.compareTo(timeBInt);
      });
    } else if (_currentSort.sortType == QueueSortType.urgency) {
      // Sort by urgency - date (deadline) then time, always ascending (most urgent first)
      sortedItems.sort((a, b) {
        // For habits with windows, use windowEndDate (deadline)
        // For tasks and habits without windows, use dueDate
        DateTime? dateA;
        DateTime? dateB;

        if (WindowDisplayHelper.hasCompletionWindow(a)) {
          dateA = a.windowEndDate;
        } else {
          dateA = a.dueDate;
        }

        if (WindowDisplayHelper.hasCompletionWindow(b)) {
          dateB = b.windowEndDate;
        } else {
          dateB = b.dueDate;
        }

        // Handle null dates (put them at the end)
        if (dateA == null && dateB == null) {
          // Both have no date, compare by time
          return _compareTimes(a.dueTime, b.dueTime);
        }
        if (dateA == null) return 1; // A has no date, put it after B
        if (dateB == null) return -1; // B has no date, put it after A

        // Compare dates - always ascending (earliest deadline first)
        int dateComparison = dateA.compareTo(dateB);
        if (dateComparison != 0) {
          return dateComparison;
        }

        // If dates are equal, compare times
        return _compareTimes(a.dueTime, b.dueTime);
      });
    }

    // Note: We don't update _instances here to avoid triggering infinite loops
    // The order will be persisted to the database for future loads
    // Save the updated order to database (async, don't wait)
    InstanceOrderService.reorderInstancesInSection(
      sortedItems,
      'queue',
      0,
      sortedItems.length - 1,
    ).catchError((e) {
      print('Error saving sorted order: $e');
    });

    return sortedItems;
  }

  Map<String, List<ActivityInstanceRecord>> get _bucketedItems {
    final Map<String, List<ActivityInstanceRecord>> buckets = {
      'Overdue': [],
      'Pending': [],
      'Completed': [],
      'Skipped/Snoozed': [],
    };
    final today = _todayDate();
    // Apply filters first
    final filteredInstances = _applyFilters(_instances);
    // Filter instances by search query if active
    final instancesToProcess = filteredInstances.where((instance) {
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
    // Populate Completed bucket (completed TODAY only)
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    for (final instance in instancesToProcess) {
      if (instance.status == 'completed') {
        if (instance.completedAt == null) {
          continue;
        }
        final completedAt = instance.completedAt!;
        final completedDateOnly =
            DateTime(completedAt.year, completedAt.month, completedAt.day);
        final isToday = completedDateOnly.isAtSameMomentAs(todayStart);
        if (isToday) {
          buckets['Completed']!.add(instance);
        }
      }
    }
    // Populate Skipped/Snoozed bucket (skipped TODAY or currently snoozed)
    for (final instance in instancesToProcess) {
      // For skipped items, check skipped date
      if (instance.status == 'skipped') {
        if (instance.skippedAt == null) {
          continue;
        }
        final skippedAt = instance.skippedAt!;
        final skippedDateOnly =
            DateTime(skippedAt.year, skippedAt.month, skippedAt.day);
        final isToday = skippedDateOnly.isAtSameMomentAs(todayStart);
        if (isToday) {
          buckets['Skipped/Snoozed']!.add(instance);
        }
      }
    }
    // Add snoozed instances to Skipped/Snoozed section (only if due today)
    for (final instance in instancesToProcess) {
      if (instance.snoozedUntil != null &&
          DateTime.now().isBefore(instance.snoozedUntil!)) {
        // Only show snoozed items if their original due date was today
        final dueDate = instance.dueDate;
        if (dueDate != null) {
          final dueDateOnly =
              DateTime(dueDate.year, dueDate.month, dueDate.day);
          if (dueDateOnly.isAtSameMomentAs(todayStart)) {
            buckets['Skipped/Snoozed']!.add(instance);
          }
        }
      }
    }
    // Sort items within each bucket
    for (final key in buckets.keys) {
      final items = buckets[key]!;
      if (items.isNotEmpty) {
        // Apply sort if active, otherwise use queue order
        if (_currentSort.isActive && _expandedSections.contains(key)) {
          buckets[key] = _sortSectionItems(items, key);
        } else {
          // Sort by queue order (manual order)
          buckets[key] =
              InstanceOrderService.sortInstancesByOrder(items, 'queue');
        }
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
    return buckets;
  }

  String _getSubtitle(ActivityInstanceRecord item, String bucketKey) {
    if (bucketKey == 'Completed') {
      // For completed habits with completion windows, show next window info
      if (item.templateCategoryType == 'habit' &&
          WindowDisplayHelper.hasCompletionWindow(item)) {
        return WindowDisplayHelper.getNextWindowStartSubtitle(item);
      }
      final due = item.dueDate;
      final dueStr = due != null ? DateFormat.MMMd().format(due) : 'No due';
      final timeStr = item.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(item.dueTime)}'
          : '';
      final subtitle =
          'Completed • ${item.templateCategoryName} • Due: $dueStr$timeStr';
      return subtitle;
    }
    if (bucketKey == 'Skipped/Snoozed') {
      // For skipped/snoozed habits with completion windows, show next window info
      if (item.templateCategoryType == 'habit' &&
          WindowDisplayHelper.hasCompletionWindow(item)) {
        return WindowDisplayHelper.getNextWindowStartSubtitle(item);
      }
      String statusText;
      // Check if item is snoozed first
      if (item.snoozedUntil != null &&
          DateTime.now().isBefore(item.snoozedUntil!)) {
        statusText = 'Snoozed';
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
    final theme = FlutterFlowTheme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: theme.primaryBackground,
          elevation: 0,
          title: TabBar(
            dividerColor: Colors.transparent,
            tabs: [
              Tab(
                text: 'Today',
              ),
              Tab(
                text: 'This Week',
              ),
            ],
          ),
          actions: [
            // Sort button
            PopupMenuButton<String>(
              icon: Icon(
                Icons.sort,
                color:
                    _currentSort.isActive ? theme.primary : theme.secondaryText,
              ),
              tooltip: 'Sort',
              onSelected: (String sortType) async {
                if (sortType == QueueSortType.points) {
                  final sort = QueueSortState(
                    sortType: QueueSortType.points,
                  );
                  if (mounted) {
                    await QueueSortStateManager().setSortState(sort);
                    setState(() {
                      _currentSort = sort;
                    });
                  }
                } else if (sortType == QueueSortType.time) {
                  final sort = QueueSortState(
                    sortType: QueueSortType.time,
                  );
                  if (mounted) {
                    await QueueSortStateManager().setSortState(sort);
                    setState(() {
                      _currentSort = sort;
                    });
                  }
                } else if (sortType == QueueSortType.urgency) {
                  final sort = QueueSortState(
                    sortType: QueueSortType.urgency,
                  );
                  if (mounted) {
                    await QueueSortStateManager().setSortState(sort);
                    setState(() {
                      _currentSort = sort;
                    });
                  }
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: QueueSortType.points,
                  child: Text('Sort by Points'),
                ),
                PopupMenuItem<String>(
                  value: QueueSortType.time,
                  child: Text('Sort by Time'),
                ),
                PopupMenuItem<String>(
                  value: QueueSortType.urgency,
                  child: Text('Sort by Urgency'),
                ),
              ],
            ),
            // Filter button with prominent active state
            _buildFilterButton(theme),
          ],
        ),
        body: Column(
          children: [
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
            : _buildDailyView(),
        // FloatingTimer(
        //   activeHabits: _activeFloatingHabits,
        //   onRefresh: _loadData,
        //   onHabitUpdated: (updated) => {},
        // ),
      ],
    );
  }

  /// Build the progress charts widget (used in scrollable view)
  Widget _buildProgressCharts() {
    return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProgressPage(),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).secondaryBackground,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 4,
                            color: Color(0x33000000),
                            offset: Offset(0, 2),
                          )
                        ],
                      ),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Daily Progress Donut Chart
                            Column(
                              children: [
                                ProgressDonutChart(
                                  percentage: _dailyPercentage,
                                  totalTarget: _dailyTarget,
                                  pointsEarned: _pointsEarned,
                                  size: 80,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Daily Progress',
                                  style: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        fontFamily: 'Readex Pro',
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                Text(
                                  '${_pointsEarned.toStringAsFixed(1)} / ${_dailyTarget.toStringAsFixed(1)}',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        fontFamily: 'Readex Pro',
                          color: FlutterFlowTheme.of(context).secondaryText,
                                      ),
                                ),
                              ],
                            ),
                            // Cumulative Score Graph
                            Column(
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  child: _buildCumulativeScoreMiniGraph(),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Cumulative Score',
                                  style: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        fontFamily: 'Readex Pro',
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                Text(
                                  '${_cumulativeScore.toStringAsFixed(0)} pts',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        fontFamily: 'Readex Pro',
                          color: FlutterFlowTheme.of(context).secondaryText,
                                      ),
                                ),
                                if (_dailyScoreGain != 0)
                                  Text(
                                    _dailyScoreGain >= 0
                                        ? '+${_dailyScoreGain.toStringAsFixed(1)}'
                                        : _dailyScoreGain.toStringAsFixed(1),
                                    style: FlutterFlowTheme.of(context)
                                        .bodySmall
                                        .override(
                                          fontFamily: 'Readex Pro',
                                          color: _dailyScoreGain >= 0
                                              ? Colors.green
                                              : Colors.red,
                                          fontWeight: FontWeight.w600,
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

  // List<ActivityRecord> get _activeFloatingHabits {
  //   // TODO: Re-implement with instances
  //   return [];
  // }
  Widget _buildDailyView() {
    final buckets = _bucketedItems;
    final order = ['Overdue', 'Pending', 'Completed', 'Skipped/Snoozed'];
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
      final expanded = _expandedSections.contains(key);
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
                  ],
                ),
                GestureDetector(
                  onTap: () {
                    if (mounted) {
                      setState(() {
                        if (expanded) {
                          // Collapse this section
                          _expandedSections.remove(key);
                        } else {
                          // Expand this section
                          _expandedSections.add(key);
                        }
                      });
                      // Save state persistently
                      ExpansionStateManager()
                          .setQueueExpandedSections(_expandedSections);
                      // Scroll to make the newly expanded section visible
                      if (_expandedSections.contains(key)) {
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
                  showCompleted:
                      (key == 'Completed' || key == 'Skipped/Snoozed')
                          ? true
                          : null,
                  page: 'queue',
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
        // Progress charts as first scrollable item
        SliverToBoxAdapter(
          child: _buildProgressCharts(),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 16),
        ),
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
    if (category == null) {}
    return category?.color ?? '#000000';
  }

  /// Check if filter is in default state (all categories selected)
  bool _isDefaultFilterState() {
    if (_categories.isEmpty) return true; // No categories = default state

    final habitCategories = _categories
        .where((c) => c.categoryType == 'habit')
        .map((c) => c.name)
        .toSet();
    final taskCategories = _categories
        .where((c) => c.categoryType == 'task')
        .map((c) => c.name)
        .toSet();

    // Check if all habit categories are selected
    final allHabitsSelected = habitCategories.isEmpty ||
        (habitCategories.length ==
                _currentFilter.selectedHabitCategoryNames.length &&
            habitCategories.every((name) =>
                _currentFilter.selectedHabitCategoryNames.contains(name)));

    // Check if all task categories are selected
    final allTasksSelected = taskCategories.isEmpty ||
        (taskCategories.length ==
                _currentFilter.selectedTaskCategoryNames.length &&
            taskCategories.every((name) =>
                _currentFilter.selectedTaskCategoryNames.contains(name)));

    return allHabitsSelected && allTasksSelected;
  }

  /// Count the number of excluded categories (not selected)
  int _getExcludedCategoryCount() {
    if (_categories.isEmpty) return 0;

    final habitCategories = _categories
        .where((c) => c.categoryType == 'habit')
        .map((c) => c.name)
        .toSet();
    final taskCategories = _categories
        .where((c) => c.categoryType == 'task')
        .map((c) => c.name)
        .toSet();

    final excludedHabits = habitCategories.length -
        _currentFilter.selectedHabitCategoryNames.length;
    final excludedTasks =
        taskCategories.length - _currentFilter.selectedTaskCategoryNames.length;

    return excludedHabits + excludedTasks;
  }

  /// Build a prominent filter button with badge and colored background when active
  Widget _buildFilterButton(FlutterFlowTheme theme) {
    final isFilterActive = !_isDefaultFilterState();
    final excludedCount = _getExcludedCategoryCount();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isFilterActive
                ? theme.primary.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isFilterActive
                ? Border.all(
                    color: theme.primary.withOpacity(0.4),
                    width: 1.5,
                  )
                : null,
          ),
          child: IconButton(
            icon: Icon(
              Icons.filter_list,
              color: isFilterActive ? theme.primary : theme.secondaryText,
            ),
            onPressed: () async {
              final result = await showQueueFilterDialog(
                context: context,
                categories: _categories,
                initialFilter: _currentFilter,
              );
              if (result != null && mounted) {
                setState(() {
                  _currentFilter = result;
                });
                // Check if result is in default state (all categories selected)
                // If so, clear stored state; otherwise save it
                final habitCategories = _categories
                    .where((c) => c.categoryType == 'habit')
                    .map((c) => c.name)
                    .toSet();
                final taskCategories = _categories
                    .where((c) => c.categoryType == 'task')
                    .map((c) => c.name)
                    .toSet();
                final allHabitsSelected = habitCategories.isEmpty ||
                    (habitCategories.length ==
                            result.selectedHabitCategoryNames.length &&
                        habitCategories.every((name) =>
                            result.selectedHabitCategoryNames.contains(name)));
                final allTasksSelected = taskCategories.isEmpty ||
                    (taskCategories.length ==
                            result.selectedTaskCategoryNames.length &&
                        taskCategories.every((name) =>
                            result.selectedTaskCategoryNames.contains(name)));

                if (allHabitsSelected && allTasksSelected) {
                  // Default state - clear stored filter
                  await QueueFilterStateManager().clearFilterState();
                } else {
                  // Not default - save the filter state
                  await QueueFilterStateManager().setFilterState(result);
                }
              }
            },
            tooltip: isFilterActive
                ? 'Filter active ($excludedCount excluded)'
                : 'Filter',
          ),
        ),
        // Badge showing excluded category count when not in default state
        if (isFilterActive && excludedCount > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: theme.primary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.primaryBackground,
                  width: 1.5,
                ),
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Center(
                child: Text(
                  excludedCount > 99 ? '99+' : '$excludedCount',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
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
      } else {}
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
      // Check if instance already exists to prevent duplicates
      final exists =
          _instances.any((inst) => inst.reference.id == instance.reference.id);
      if (!exists) {
        _instances.add(instance);
      }
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
      // Deduplicate instances by reference ID to prevent duplicates
      final uniqueInstances = <String, ActivityInstanceRecord>{};
      for (final instance in allInstances) {
        uniqueInstances[instance.reference.id] = instance;
      }
      final deduplicatedInstances = uniqueInstances.values.toList();
      if (mounted) {
        setState(() {
          _instances = deduplicatedInstances;
          _categories = allCategories;
          // Don't touch _isLoading
        });
        _calculateProgress();
      }
    } catch (e) {}
  }

  /// Handle reordering of items within a section
  Future<void> _handleReorder(
      int oldIndex, int newIndex, String sectionKey) async {
    try {
      // If a sort is active, clear it immediately so the manual order sticks
      if (_currentSort.isActive) {
        final clearedSort = QueueSortState();
        await QueueSortStateManager().setSortState(clearedSort);
        if (mounted) {
          setState(() {
            _currentSort = clearedSort;
          });
        }
      }

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
        adjustedNewIndex,
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
}
