import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/daily_progress_calculator.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/progress_donut_chart.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/backend/today_progress_state.dart';
import 'package:habit_tracker/Helper/utils/expansion_state_manager.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Helper/utils/search_fab.dart';
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
import 'package:habit_tracker/Helper/utils/TimeManager.dart';
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
  Set<String> _reorderingInstanceIds =
      {}; // Track instances being reordered to prevent stale updates
  // Optimistic operation tracking
  final Map<String, String> _optimisticOperations = {}; // operationId -> instanceId
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
  // Cache for bucketed items to avoid recalculation on every build
  Map<String, List<ActivityInstanceRecord>>? _cachedBucketedItems;
  int _instancesHashCode = 0;
  int _categoriesHashCode = 0;
  String _lastSearchQuery = '';
  QueueFilterState? _lastFilter;
  QueueSortState? _lastSort;
  Set<String> _lastExpandedSections = {};
  @override
  void initState() {
    super.initState();
    _loadExpansionState();
    // Load filter and sort state first, then load data to ensure filters are applied correctly
    _loadFilterAndSortState().then((_) {
      _loadData().then((_) {
        // Defer cumulative score loading until after initial render for faster initial load
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadCumulativeScore();
          }
        });
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
      if (mounted && !_ignoreInstanceEvents) {
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
        // Invalidate cache when filter/sort state changes
        _cachedBucketedItems = null;
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

  Future<void> _loadData() async {
    // Prevent concurrent loads
    if (_isLoadingData) return;
    if (!mounted) return;
    _isLoadingData = true;
    _ignoreInstanceEvents = true; // Temporarily ignore events during load
    setState(() => _isLoading = true);
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        // Batch Firestore queries in parallel for faster loading
        final results = await Future.wait([
          queryAllInstances(userId: userId),
          queryHabitCategoriesOnce(
            userId: userId,
            callerTag: 'QueuePage._loadData.habits',
          ),
          queryTaskCategoriesOnce(
            userId: userId,
            callerTag: 'QueuePage._loadData.tasks',
          ),
        ]);
        if (!mounted) return;
        final allInstances = results[0] as List<ActivityInstanceRecord>;
        final habitCategories = results[1] as List<CategoryRecord>;
        final taskCategories = results[2] as List<CategoryRecord>;
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
            // Invalidate cache when data changes
            _cachedBucketedItems = null;

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
          try {
            await InstanceOrderService.initializeOrderValues(
                deduplicatedInstances, 'queue');
          } catch (_) {}
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
  /// [optimistic] - If true, calculates instantly from local data without Firestore queries
  void _calculateProgress({bool optimistic = false}) async {
    // Separate habit and task instances
    final habitInstances = _instances
        .where((inst) => inst.templateCategoryType == 'habit')
        .toList();
    final taskInstances = _instances
        .where((inst) => inst.templateCategoryType == 'task')
        .toList();
    
    if (optimistic) {
      // INSTANT UPDATE: Calculate from local data only (no Firestore queries)
      try {
        final progressData = DailyProgressCalculator.calculateTodayProgressOptimistic(
          allInstances: habitInstances,
          categories: _categories,
          taskInstances: taskInstances,
        );
        
        // Update UI immediately
        if (mounted) {
          setState(() {
            _dailyTarget = progressData['target'] as double;
            _pointsEarned = progressData['earned'] as double;
            _dailyPercentage = progressData['percentage'] as double;
          });
        }
        
        // Publish to shared state for other pages
        TodayProgressState().updateProgress(
          target: _dailyTarget,
          earned: _pointsEarned,
          percentage: _dailyPercentage,
        );
        
        // Update cumulative score optimistically
        _updateCumulativeScoreLiveOptimistic();
      } catch (e) {
        // If optimistic calculation fails, fall back to full calculation
        _calculateProgress(optimistic: false);
      }
    } else {
      // BACKEND RECONCILIATION: Use full calculation with Firestore
      try {
        final progressData = await DailyProgressCalculator.calculateTodayProgress(
          userId: currentUserUid,
          allInstances: habitInstances,
          categories: _categories,
          taskInstances: taskInstances,
        );
        
        // Update UI with backend data
        if (mounted) {
          setState(() {
            _dailyTarget = progressData['target'] as double;
            _pointsEarned = progressData['earned'] as double;
            _dailyPercentage = progressData['percentage'] as double;
          });
        }
        
        // Publish to shared state for other pages
        TodayProgressState().updateProgress(
          target: _dailyTarget,
          earned: _pointsEarned,
          percentage: _dailyPercentage,
        );
        
        // Update cumulative score live when progress changes
        _updateCumulativeScoreLive();
      } catch (e) {
        // Error in backend calculation - non-critical, continue silently
      }
    }
  }

  /// Update cumulative score optimistically without Firestore queries
  /// Uses last known cumulative score and simplified calculations for instant updates
  void _updateCumulativeScoreLiveOptimistic() {
    try {
      // Get today's progress (already updated optimistically)
      final todayPercentage = _dailyPercentage;
      final todayEarned = _pointsEarned;

      double currentCumulativeScore = 0.0;
      double currentDailyGain = 0.0;

      // Get last known cumulative score from shared state
      final sharedData = TodayProgressState().getCumulativeScoreData();
      final lastKnownCumulative = sharedData['cumulativeScore'] as double? ?? _cumulativeScore;
      final lastKnownGain = sharedData['dailyGain'] as double? ?? _dailyScoreGain;

      if (todayPercentage > 0) {
        // Calculate simplified projected score optimistically
        // Use basic daily score calculation without consistency bonus/penalty
        // This provides instant feedback, full calculation happens in background
        final dailyScore = CumulativeScoreService.calculateDailyScore(
          todayPercentage,
          todayEarned,
        );
        
        // Simplified projection: assume no bonus/penalty for instant update
        // Full calculation with bonuses/penalties happens in background
        currentDailyGain = dailyScore;
        currentCumulativeScore = (lastKnownCumulative + currentDailyGain).clamp(0.0, double.infinity);
      } else {
        // No progress today, use last known values
        currentCumulativeScore = lastKnownCumulative;
        currentDailyGain = lastKnownGain;
      }

      // Update cumulative score values immediately
      if (mounted) {
        setState(() {
          _cumulativeScore = currentCumulativeScore;
          _dailyScoreGain = currentDailyGain;

          // Update today's entry in history if it exists
          if (_cumulativeScoreHistory.isNotEmpty) {
            final today = DateService.currentDate;
            final lastItem = _cumulativeScoreHistory.last;
            final lastDate = lastItem['date'] as DateTime;

            if (lastDate.year == today.year &&
                lastDate.month == today.month &&
                lastDate.day == today.day) {
              // Update today's entry with live values
              _cumulativeScoreHistory.last['score'] = currentCumulativeScore;
              _cumulativeScoreHistory.last['gain'] = currentDailyGain;
            }
          }
        });
      }

      // Publish to shared state for other pages
      TodayProgressState().updateCumulativeScore(
        cumulativeScore: currentCumulativeScore,
        dailyGain: currentDailyGain,
        hasLiveScore: todayPercentage > 0,
      );
    } catch (e) {
      // Error in optimistic calculation - non-critical, continue silently
      // Full calculation will happen in background
    }
  }

  /// Update cumulative score live without reloading full history
  /// This provides instant updates similar to daily progress chart
  Future<void> _updateCumulativeScoreLive() async {
    if (_isLoadingCumulativeScore) return;

    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      // Get today's progress
      final todayPercentage = _dailyPercentage;
      final todayEarned = _pointsEarned;

      double currentCumulativeScore = 0.0;
      double currentDailyGain = 0.0;

      if (todayPercentage > 0) {
        // Calculate projected score including today's progress
        final projectionData =
            await CumulativeScoreService.calculateProjectedDailyScore(
          userId,
          todayPercentage,
          todayEarned,
        );

        currentCumulativeScore = projectionData['projectedCumulative'] ?? 0.0;
        currentDailyGain = projectionData['projectedGain'] ?? 0.0;
      } else {
        // No progress today, use base score from Firestore
        final userStats =
            await CumulativeScoreService.getCumulativeScore(userId);
        if (userStats != null) {
          currentCumulativeScore = userStats.cumulativeScore;
          currentDailyGain = userStats.lastDailyGain;
        }
      }

      // Update cumulative score values
      if (mounted) {
        setState(() {
          _cumulativeScore = currentCumulativeScore;
          _dailyScoreGain = currentDailyGain;

          // Update today's entry in history if it exists
          if (_cumulativeScoreHistory.isNotEmpty) {
            final today = DateService.currentDate;
            final lastItem = _cumulativeScoreHistory.last;
            final lastDate = lastItem['date'] as DateTime;

            if (lastDate.year == today.year &&
                lastDate.month == today.month &&
                lastDate.day == today.day) {
              // Update today's entry with live values
              _cumulativeScoreHistory.last['score'] = currentCumulativeScore;
              _cumulativeScoreHistory.last['gain'] = currentDailyGain;
            }
          }
        });
      }

      // Publish to shared state for other pages
      TodayProgressState().updateCumulativeScore(
        cumulativeScore: currentCumulativeScore,
        dailyGain: currentDailyGain,
        hasLiveScore: todayPercentage > 0,
      );
    } catch (e) {
      // Error updating cumulative score live - non-critical, continue silently
    }
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
        final todayEarned = progressData['earned'] ?? 0.0;

        if (todayPercentage > 0) {
          // Calculate projected score including today's progress
          final projectionData =
              await CumulativeScoreService.calculateProjectedDailyScore(
            userId,
            todayPercentage,
            todayEarned,
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

      // Load cumulative score history for the last 30 days
      // Load cumulative score history for the last 30 days
      // Use todayStart to ensuring consistent midnight-to-midnight querying
      final endDate = DateService.todayStart;
      final startDate = endDate.subtract(const Duration(days: 30));

      final query = await DailyProgressRecord.collectionForUser(userId)
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .orderBy('date', descending: false)
          .get();

      // Create a map for quick lookup of existing records
      final recordMap = <String, DailyProgressRecord>{};
      for (final doc in query.docs) {
        final record = DailyProgressRecord.fromSnapshot(doc);
        if (record.date != null) {
          final dateKey = DateFormat('yyyy-MM-dd').format(record.date!);
          recordMap[dateKey] = record;
        }
      }

      final history = <Map<String, dynamic>>[];

      double lastKnownScore = 0.0;

      // Fetch the last record BEFORE the start date to get the baseline score
      try {
        final lastPriorRecordQuery =
            await DailyProgressRecord.collectionForUser(userId)
                .where('date', isLessThan: startDate)
                .orderBy('date', descending: true)
                .limit(1)
                .get();

        if (lastPriorRecordQuery.docs.isNotEmpty) {
          final priorRec =
              DailyProgressRecord.fromSnapshot(lastPriorRecordQuery.docs.first);
          if (priorRec.cumulativeScoreSnapshot > 0) {
            lastKnownScore = priorRec.cumulativeScoreSnapshot;
          }
        } else {
          // If no prior record exists, use the first record in our current range as baseline
          // This handles new users or when history doesn't go back 30 days
          if (recordMap.isNotEmpty) {
            // Get the earliest date in our map
            final sortedDates = recordMap.keys.toList()..sort();
            final firstRecord = recordMap[sortedDates.first]!;
            if (firstRecord.cumulativeScoreSnapshot > 0) {
              // Use the score from the day BEFORE the first record
              // by subtracting that day's gain
              lastKnownScore = firstRecord.cumulativeScoreSnapshot -
                  firstRecord.dailyScoreGain;
              if (lastKnownScore < 0) lastKnownScore = 0;
            }
          }
        }
      } catch (e) {
        // Error fetching prior cumulative score
      }

      // Iterate day by day from startDate to endDate
      for (int i = 0; i <= 30; i++) {
        final date = startDate.add(Duration(days: i));
        final dateKey = DateFormat('yyyy-MM-dd').format(date);

        if (recordMap.containsKey(dateKey)) {
          final record = recordMap[dateKey]!;
          // Use cumulativeScoreSnapshot if available, otherwise calculate from lastKnownScore
          // This matches Progress page logic to ensure consistent data
          if (record.cumulativeScoreSnapshot > 0) {
            lastKnownScore = record.cumulativeScoreSnapshot;
          } else if (record.hasDailyScoreGain()) {
            // If no snapshot but has gain, calculate from last known score
            lastKnownScore = (lastKnownScore + record.dailyScoreGain)
                .clamp(0.0, double.infinity);
          }
          history.add({
            'date': date,
            'score': lastKnownScore,
            'gain': record.dailyScoreGain,
          });
        } else {
          // No record for this day, simply carry forward the last cumulative score
          // Gain is 0 for missing days
          history.add({
            'date': date,
            'score': lastKnownScore,
            'gain': 0.0,
          });
        }
      }

      // Ensure today reflects the live score (if today is the last day in loop)
      // The loop goes up to endDate (today). existing logic overrides today with live score.
      // Let's check if the last item in history is today.
      if (history.isNotEmpty) {
        final lastItem = history.last;
        final lastDate = lastItem['date'] as DateTime;
        final today = DateService.currentDate;

        if (lastDate.year == today.year &&
            lastDate.month == today.month &&
            lastDate.day == today.day) {
          // Always update today's entry with current values to match Progress page behavior
          // Use projected score if available (hasLiveScore), otherwise use base score
          history.last['score'] = currentCumulativeScore;
          history.last['gain'] = currentDailyGain;
        }
      }

      // Safeguard: Check if the new history is all zeros (invalid) while we possibly have valid data
      final bool isNewHistoryValid =
          history.any((h) => (h['score'] as double) > 0);
      final bool wasOldHistoryValid =
          _cumulativeScoreHistory.any((h) => (h['score'] as double) > 0);

      if (!isNewHistoryValid && wasOldHistoryValid) {
        // Warning: New cumulative score history is empty/zero. Ignoring update to preserve data.
        _isLoadingCumulativeScore = false;
        return;
      }

      if (mounted) {
        setState(() {
          _cumulativeScoreHistory = history;
        });
      }
    } catch (e) {
      // Error loading cumulative score
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

    return CumulativeScoreGraph(
      history: _cumulativeScoreHistory,
      color: FlutterFlowTheme.of(context).primary,
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
      // Error saving sorted order
    });

    return sortedItems;
  }

  Map<String, List<ActivityInstanceRecord>> get _bucketedItems {
    // Check if cache is still valid
    final currentInstancesHash = _instances.length.hashCode ^
        _instances.fold(0, (sum, inst) => sum ^ inst.reference.id.hashCode);
    final currentCategoriesHash = _categories.length.hashCode ^
        _categories.fold(0, (sum, cat) => sum ^ cat.reference.id.hashCode);

    final cacheInvalid = _cachedBucketedItems == null ||
        currentInstancesHash != _instancesHashCode ||
        currentCategoriesHash != _categoriesHashCode ||
        _searchQuery != _lastSearchQuery ||
        !_filtersEqual(_currentFilter, _lastFilter) ||
        !_sortsEqual(_currentSort, _lastSort) ||
        !_setsEqual(_expandedSections, _lastExpandedSections);

    if (!cacheInvalid && _cachedBucketedItems != null) {
      return _cachedBucketedItems!;
    }

    // Recalculate buckets
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

    // Update cache
    _cachedBucketedItems = buckets;
    _instancesHashCode = currentInstancesHash;
    _categoriesHashCode = currentCategoriesHash;
    _lastSearchQuery = _searchQuery;
    _lastFilter = QueueFilterState(
      allTasks: _currentFilter.allTasks,
      allHabits: _currentFilter.allHabits,
      selectedHabitCategoryNames:
          Set.from(_currentFilter.selectedHabitCategoryNames),
      selectedTaskCategoryNames:
          Set.from(_currentFilter.selectedTaskCategoryNames),
    );
    _lastSort = QueueSortState(
      sortType: _currentSort.sortType,
    );
    _lastExpandedSections = Set.from(_expandedSections);

    return buckets;
  }

  bool _filtersEqual(QueueFilterState? a, QueueFilterState? b) {
    if (a == null || b == null) return a == b;
    return a.allTasks == b.allTasks &&
        a.allHabits == b.allHabits &&
        _setsEqual(
            a.selectedHabitCategoryNames, b.selectedHabitCategoryNames) &&
        _setsEqual(a.selectedTaskCategoryNames, b.selectedTaskCategoryNames);
  }

  bool _sortsEqual(QueueSortState? a, QueueSortState? b) {
    if (a == null || b == null) return a == b;
    return a.sortType == b.sortType;
  }

  bool _setsEqual<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    return a.every((item) => b.contains(item));
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
                      // Invalidate cache when sort changes
                      _cachedBucketedItems = null;
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
                      // Invalidate cache when sort changes
                      _cachedBucketedItems = null;
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
                      // Invalidate cache when sort changes
                      _cachedBucketedItems = null;
                    });
                  }
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: QueueSortType.points,
                  child: const Text('Sort by Points'),
                ),
                PopupMenuItem<String>(
                  value: QueueSortType.time,
                  child: const Text('Sort by Time'),
                ),
                PopupMenuItem<String>(
                  value: QueueSortType.urgency,
                  child: const Text('Sort by Urgency'),
                ),
              ],
            ),
            // Filter button with prominent active state
            _buildFilterButton(theme),
          ],
        ),
        body: Stack(
          children: [
            Column(
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
            const SearchFAB(heroTag: 'search_fab_queue'),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  const SizedBox(height: 4),
                  Text(
                    'Daily Progress',
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          fontFamily: 'Readex Pro',
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    '${_pointsEarned.toStringAsFixed(1)} / ${_dailyTarget.toStringAsFixed(1)}',
                    style: FlutterFlowTheme.of(context).bodySmall.override(
                          fontFamily: 'Readex Pro',
                          color: FlutterFlowTheme.of(context).secondaryText,
                        ),
                  ),
                ],
              ),
              // Cumulative Score Graph
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 80,
                    child: _buildCumulativeScoreMiniGraph(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cumulative Score',
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          fontFamily: 'Readex Pro',
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _cumulativeScoreHistory.isNotEmpty
                            ? '${(_cumulativeScoreHistory.last['score'] as double).toStringAsFixed(0)} pts'
                            : '0 pts',
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                              fontFamily: 'Readex Pro',
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                      ),
                      if (_cumulativeScoreHistory.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Builder(
                          builder: (context) {
                            final dailyGain =
                                _cumulativeScoreHistory.last['gain'] as double;
                            if (dailyGain == 0) return const SizedBox.shrink();
                            return Text(
                              dailyGain >= 0
                                  ? '+${dailyGain.toStringAsFixed(1)}'
                                  : dailyGain.toStringAsFixed(1),
                              style: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .override(
                                    fontFamily: 'Readex Pro',
                                    color: dailyGain >= 0
                                        ? Colors.green
                                        : Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get active floating timer instances
  /// Uses TimerManager to get globally tracked active timers
  List<ActivityInstanceRecord> get _activeFloatingInstances {
    return TimerManager().activeTimers;
  }

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
                        // Invalidate cache when expansion changes (affects sorting)
                        _cachedBucketedItems = null;
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
                  onRefresh: _refreshWithoutFlicker,
                  onInstanceUpdated: _updateInstanceInLocalState,
                  onInstanceDeleted: _removeInstanceFromLocalState,
                  onHabitUpdated: (updated) => {},
                  onHabitDeleted: (deleted) async => _refreshWithoutFlicker(),
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
    return RefreshIndicator(
      onRefresh: () async {
        await _loadData();
        // Also reload cumulative score after data refresh
        if (mounted) {
          await _loadCumulativeScore();
        }
      },
      child: CustomScrollView(
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
      ),
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
                  // Invalidate cache when filter changes
                  _cachedBucketedItems = null;
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
        // Invalidate cache when instance is updated
        _cachedBucketedItems = null;
      } else {}
    });
    // OPTIMISTIC UPDATE: Calculate progress instantly from local data
    _calculateProgress(optimistic: true);
    // BACKGROUND RECONCILIATION: Recalculate with backend data
    _calculateProgress(optimistic: false);
  }

  /// Remove instance from local state and recalculate progress
  void _removeInstanceFromLocalState(
      ActivityInstanceRecord deletedInstance) async {
    setState(() {
      _instances.removeWhere(
          (inst) => inst.reference.id == deletedInstance.reference.id);
      // Invalidate cache when instance is removed
      _cachedBucketedItems = null;
    });
    // OPTIMISTIC UPDATE: Calculate progress instantly from local data
    _calculateProgress(optimistic: true);
    // BACKGROUND RECONCILIATION: Recalculate with backend data
    _calculateProgress(optimistic: false);
  }

  // Event handlers for live updates
  void _handleInstanceCreated(ActivityInstanceRecord instance) {
    setState(() {
      // Check if instance already exists to prevent duplicates
      final exists =
          _instances.any((inst) => inst.reference.id == instance.reference.id);
      if (!exists) {
        _instances.add(instance);
        // Invalidate cache when instance is added
        _cachedBucketedItems = null;
      }
    });
    // OPTIMISTIC UPDATE: Calculate progress instantly from local data
    _calculateProgress(optimistic: true);
    // BACKGROUND RECONCILIATION: Recalculate with backend data
    _calculateProgress(optimistic: false);
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
        // Invalidate cache when instance is updated
        _cachedBucketedItems = null;
      } else if (!isOptimistic) {
        // New instance from backend (not optimistic) - add it
        _instances.add(instance);
        _cachedBucketedItems = null;
      }
    });
    
    // OPTIMISTIC UPDATE: Calculate progress instantly from local data
    _calculateProgress(optimistic: true);
    
    // BACKGROUND RECONCILIATION: Only if this is a reconciled update
    if (!isOptimistic) {
      _calculateProgress(optimistic: false);
    }
  }
  
  void _handleRollback(dynamic param) {
    if (param is Map) {
      final operationId = param['operationId'] as String?;
      final instanceId = param['instanceId'] as String?;
      
      if (operationId != null && _optimisticOperations.containsKey(operationId)) {
        // Revert to previous state by reloading from backend
        setState(() {
          _optimisticOperations.remove(operationId);
          // Reload the specific instance from backend
          if (instanceId != null) {
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
        final index = _instances
            .indexWhere((inst) => inst.reference.id == instanceId);
        if (index != -1) {
          _instances[index] = updatedInstance;
          _cachedBucketedItems = null;
        }
      });
      // Recalculate progress with actual data
      _calculateProgress(optimistic: false);
    } catch (e) {
      // Error reverting - non-critical, will be fixed on next data load
    }
  }

  void _handleInstanceDeleted(ActivityInstanceRecord instance) {
    setState(() {
      _instances
          .removeWhere((inst) => inst.reference.id == instance.reference.id);
      // Invalidate cache when instance is deleted
      _cachedBucketedItems = null;
    });
    // OPTIMISTIC UPDATE: Calculate progress instantly from local data
    _calculateProgress(optimistic: true);
    // BACKGROUND RECONCILIATION: Recalculate with backend data
    _calculateProgress(optimistic: false);
  }

  /// Silent refresh instances without loading indicator
  Future<void> _silentRefreshInstances() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;
      // Batch Firestore queries in parallel for faster loading
      final results = await Future.wait([
        queryAllInstances(userId: userId),
        queryHabitCategoriesOnce(
          userId: userId,
          callerTag: 'QueuePage._silentRefreshInstances.habits',
        ),
        queryTaskCategoriesOnce(
          userId: userId,
          callerTag: 'QueuePage._silentRefreshInstances.tasks',
        ),
      ]);
      final allInstances = results[0] as List<ActivityInstanceRecord>;
      final habitCategories = results[1] as List<CategoryRecord>;
      final taskCategories = results[2] as List<CategoryRecord>;
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
          // Invalidate cache when data changes
          _cachedBucketedItems = null;
          // Don't touch _isLoading
        });
        _calculateProgress();
      }
    } catch (e) {
      // Silently ignore errors in silent refresh - non-critical background operation
      print('Error in silent refresh instances: $e');
    }
  }

  /// Wrapper for silent refresh to use as callback
  Future<void> _refreshWithoutFlicker() async {
    await _silentRefreshInstances();
  }

  /// Handle reordering of items within a section
  Future<void> _handleReorder(
      int oldIndex, int newIndex, String sectionKey) async {
    final reorderingIds = <String>{};
    try {
      // If a sort is active, clear it immediately so the manual order sticks
      if (_currentSort.isActive) {
        final clearedSort = QueueSortState();
        await QueueSortStateManager().setSortState(clearedSort);
        if (mounted) {
          setState(() {
            _currentSort = clearedSort;
            // Invalidate cache when sort is cleared
            _cachedBucketedItems = null;
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
        final instanceId = instance.reference.id;
        reorderingIds.add(instanceId);
        final index =
            _instances.indexWhere((inst) => inst.reference.id == instanceId);
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
        'queue',
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

class CumulativeScoreGraph extends StatefulWidget {
  final List<Map<String, dynamic>> history;
  final Color color;

  const CumulativeScoreGraph({
    Key? key,
    required this.history,
    required this.color,
  }) : super(key: key);

  @override
  State<CumulativeScoreGraph> createState() => _CumulativeScoreGraphState();
}

class _CumulativeScoreGraphState extends State<CumulativeScoreGraph> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToEnd();
  }

  @override
  void didUpdateWidget(CumulativeScoreGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.history.length != oldWidget.history.length) {
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // We want exactly 7 days to be visible at once
        final double visibleDays = 7.0;
        final double dayWidth = constraints.maxWidth / visibleDays;

        double totalWidth = dayWidth * widget.history.length;
        if (totalWidth < constraints.maxWidth) {
          totalWidth = constraints.maxWidth;
        }

        // Calculate min/max scores for scale
        final minScore = widget.history.isEmpty
            ? 0.0
            : widget.history
                .map((d) => d['score'] as double)
                .reduce((a, b) => a < b ? a : b);
        final maxScore = widget.history.isEmpty
            ? 100.0
            : widget.history
                .map((d) => d['score'] as double)
                .reduce((a, b) => a > b ? a : b);
        final adjustedMaxScore =
            maxScore == minScore ? minScore + 10.0 : maxScore;
        final adjustedRange = adjustedMaxScore - minScore;

        // Generate scale labels (3-5 labels)
        final numLabels = 5;
        final scaleLabels = <double>[];
        for (int i = 0; i < numLabels; i++) {
          final value = minScore + (adjustedRange * i / (numLabels - 1));
          scaleLabels.add(value);
        }

        // Calculate date labels - ensure minimum 1-day interval between labels
        final dateLabels = <Map<String, dynamic>>[];
        if (widget.history.isNotEmpty) {
          // Always include the first date
          final firstDate = widget.history[0]['date'] as DateTime;
          dateLabels.add({
            'index': 0,
            'date': firstDate,
          });

          // Track the last displayed date to ensure minimum 1-day spacing
          DateTime? lastDisplayedDate = firstDate;

          // Iterate through remaining dates, ensuring at least 1 day apart
          for (int i = 1; i < widget.history.length; i++) {
            final currentDate = widget.history[i]['date'] as DateTime;
            final daysSinceLastLabel =
                currentDate.difference(lastDisplayedDate!).inDays;

            // Only add label if at least 1 day has passed since last label
            // Also limit to approximately 5 labels total to avoid crowding
            if (daysSinceLastLabel >= 1 && dateLabels.length < 5) {
              dateLabels.add({
                'index': i,
                'date': currentDate,
              });
              lastDisplayedDate = currentDate;
            }
          }

          // Always include the last date if not already included
          final lastIndex = widget.history.length - 1;
          final lastDate = widget.history[lastIndex]['date'] as DateTime;
          final alreadyIncluded =
              dateLabels.any((label) => label['index'] == lastIndex);
          if (!alreadyIncluded) {
            // Check if last date is at least 1 day from the previous label
            final lastLabelDate = dateLabels.isNotEmpty
                ? dateLabels.last['date'] as DateTime
                : null;
            if (lastLabelDate == null ||
                lastDate.difference(lastLabelDate).inDays >= 1) {
              dateLabels.add({
                'index': lastIndex,
                'date': lastDate,
              });
            } else {
              // Replace the last label with the actual last date if they're too close
              dateLabels.removeLast();
              dateLabels.add({
                'index': lastIndex,
                'date': lastDate,
              });
            }
          }
        }

        return Container(
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Y-axis scale labels
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: scaleLabels.reversed.map((value) {
                    return Text(
                      value.toStringAsFixed(0),
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            fontFamily: 'Readex Pro',
                            fontSize: 9,
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                    );
                  }).toList(),
                ),
              ),
              // Chart and date labels with horizontal scroll
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Graph area
                        SizedBox(
                          height: constraints.maxHeight > 0
                              ? constraints.maxHeight - 20
                              : 80,
                          child: CustomPaint(
                            painter: CumulativeScoreLinePainter(
                              data: widget.history,
                              minScore: minScore,
                              maxScore: adjustedMaxScore,
                              scoreRange: adjustedRange,
                              color: widget.color,
                            ),
                          ),
                        ),
                        // X-axis date labels
                        Container(
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Stack(
                            children: dateLabels.map((label) {
                              final index = label['index'] as int;
                              final date = label['date'] as DateTime;
                              final xPosition = (index /
                                      (widget.history.length > 1
                                          ? widget.history.length - 1
                                          : 1)) *
                                  totalWidth;
                              return Positioned(
                                left: xPosition - 15, // Center the label
                                child: Text(
                                  DateFormat('MM/dd').format(date),
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        fontFamily: 'Readex Pro',
                                        fontSize: 8,
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                      ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
