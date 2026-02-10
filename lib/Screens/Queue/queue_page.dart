import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Screens/Item_component/item_component_main.dart';
import 'package:habit_tracker/Screens/Progress/Statemanagement/today_progress_state.dart';
import 'package:habit_tracker/Screens/Shared/section_expansion_state_manager.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_fab.dart';
import 'package:habit_tracker/Screens/Queue/Weekly_view/weekly_view.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/instance_order_service.dart';
import 'package:habit_tracker/Screens/Queue/Queue_filter/queue_filter_state_manager.dart'
    show QueueFilterState, QueueFilterStateManager;
import 'package:habit_tracker/Screens/Queue/Helpers/queue_sort_state_manager.dart'
    show QueueSortState, QueueSortStateManager, QueueSortType;
import 'package:habit_tracker/Screens/Queue/Helpers/queue_utils.dart';
import 'package:habit_tracker/Screens/Queue/Helpers/queue_instance_state_manager.dart';
import 'package:habit_tracker/Screens/Queue/Helpers/queue_bucket_service.dart';
import 'package:habit_tracker/Screens/Queue/Helpers/queue_page_refresh.dart';
import 'package:habit_tracker/Screens/Queue/Helpers/queue_reorder_handler.dart';
import 'package:habit_tracker/Screens/Queue/Queue_filter/queue_filter_logic.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/today_points_service.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/score_coordinator.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/score_history_service.dart';
import 'package:habit_tracker/Screens/Queue/Helpers/queue_focus_handler.dart';
import 'package:habit_tracker/Screens/Queue/Queue_charts_section/queue_charts_section.dart';
import 'package:habit_tracker/Screens/Queue/Queue_filter/queue_filter_dialog.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/progress_page_data_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/activity_template_service.dart';
import 'package:habit_tracker/Screens/Progress/Point_system_helper/points_service.dart';
import 'dart:async';

// #region agent log
void _logQueueCrashDebug(String location, Map<String, dynamic> data) {
  // Disabled to prevent OOM
}
// #endregion

class QueuePage extends StatefulWidget {
  final bool expandCompleted;
  final String? focusTemplateId;
  final String? focusInstanceId;
  const QueuePage({
    super.key,
    this.expandCompleted = false,
    this.focusTemplateId,
    this.focusInstanceId,
  });
  @override
  _QueuePageState createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  List<ActivityInstanceRecord> _instances = [];
  List<CategoryRecord> _categories = [];
  Set<String> _expandedSections = {};
  final Map<String, GlobalKey> _sectionKeys = {};
  final Map<String, GlobalKey> _itemKeys = {};
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  bool _shouldReloadOnReturn = false;
  bool _isLoadingData = false; // Guard against concurrent loads
  bool _ignoreInstanceEvents = true; // Ignore events during initial load
  final Set<String> _reorderingInstanceIds = {};
  final Map<String, String> _optimisticOperations = {};
  double _dailyTarget = 0.0;
  double _pointsEarned = 0.0;
  double _dailyPercentage = 0.0;
  double _cumulativeScore = 0.0;
  double _dailyScoreGain = 0.0;
  List<Map<String, dynamic>> _cumulativeScoreHistory = [];
  bool _isLoadingHistory = false;
  bool _pendingHistoryReload = false;
  bool _historyLoaded = false;
  bool _isUpdatingLiveScore = false;
  bool _pendingLiveScoreUpdate = false;
  double? _pendingHistoryScore;
  double? _pendingHistoryGain;
  bool _isCalculatingProgress = false;
  int _progressCalculationVersion =
      0; // Track calculation order to prevent overwriting newer values
  bool _isInitialLoadComplete =
      false; // Track if initial load is done (use incremental after this)
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();
  bool _isSearchBarVisible = false;
  QueueFilterState _currentFilter = QueueFilterState();
  QueueSortState _currentSort = QueueSortState();
  Map<String, List<ActivityInstanceRecord>>? _cachedBucketedItems;
  int _instancesHashCode = 0; // Current hash of instances
  int _categoriesHashCode = 0; // Current hash of categories
  int _lastCachedInstancesHash = 0; // Hash used when cache was built
  int _lastCachedCategoriesHash = 0; // Hash used when cache was built
  String _lastSearchQuery = '';
  QueueFilterState? _lastFilter;
  QueueSortState? _lastSort;
  Set<String> _lastExpandedSections = {};
  String? _pendingFocusTemplateId;
  String? _pendingFocusInstanceId;
  bool _hasAppliedInitialFocus = false;
  String? _highlightedInstanceId;
  Timer? _highlightTimer;
  DateTime?
      _lastKnownDate; // Track last known date for day transition detection
  Timer? _fullSyncDebounceTimer;
  Timer? _fullSyncIntervalTimer;
  DateTime? _lastFullSyncAt;
  static const Duration _fullSyncDebounceDuration = Duration(seconds: 60);
  static const Duration _fullSyncInterval = Duration(minutes: 5);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastKnownDate = DateService.todayStart;
    _pendingFocusTemplateId = widget.focusTemplateId;
    _pendingFocusInstanceId = widget.focusInstanceId;
    _loadExpansionState();
    _startFullSyncTimers();
    // Load filter/sort state and data in parallel for faster initialization
    Future.wait([
      _loadFilterAndSortState(),
      _loadData(isInitialLoad: true),
    ]).then((_) async {
      // Wait for progress calculation and score update to complete
      // This ensures shared state is updated before loading history
      // Fixes race condition where _loadCumulativeScoreHistory() was called
      // before _updateTodayScore() completed
      if (mounted) {
        // Wait for non-optimistic calculation to complete (reconciles with backend)
        await _calculateProgress(optimistic: false);
        // _updateTodayScore() is called from _calculateProgress(optimistic: false)
        // and awaited, so it's already complete at this point
        // Now safe to load history with updated shared state
        if (mounted) {
          await _loadCumulativeScoreHistory(isInitialLoad: true);
        }
      }
      if (widget.expandCompleted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            NotificationCenter.post('expandQueueSection', 'Completed');
          }
        });
      }
    });
    NotificationCenter.addObserver(this, 'cumulativeScoreUpdated', (param) {
      if (!mounted) return;
      final data = TodayProgressState().getCumulativeScoreData();
      final updatedScore =
          (data['cumulativeScore'] as double?) ?? _cumulativeScore;
      final updatedTodayScore =
          (data['todayScore'] as double?) ?? _dailyScoreGain;
      // Only update if values actually changed
      if (updatedScore != _cumulativeScore ||
          updatedTodayScore != _dailyScoreGain) {
        setState(() {
          _cumulativeScore = updatedScore;
          _dailyScoreGain = updatedTodayScore;
        });
        _queueHistoryOverlay(updatedScore, updatedTodayScore);
      }
    });
    NotificationCenter.addObserver(this, 'todayProgressUpdated', (param) {
      if (!mounted) return;
      // GUARD: Don't trigger if we're already calculating (prevents infinite loop)
      if (_isCalculatingProgress || _isUpdatingLiveScore) {
        return;
      }
      // When completion points update, recalculate today's score
      _updateTodayScore();
    });
    NotificationCenter.addObserver(this, 'loadData', (param) {
      if (mounted) {
        // Don't wrap async call in setState - call directly
        _loadData();
      }
    });
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        _silentRefreshInstances();
      }
    });
    _isSearchBarVisible = _searchManager.isSearchOpen;
    _searchManager.addListener(_onSearchChanged);
    _searchManager.addSearchOpenListener(_onSearchVisibilityChanged);
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
    NotificationCenter.addObserver(this, 'expandQueueSection', (param) {
      if (mounted && param is String) {
        setState(() {
          _expandedSections.add(param);
          ExpansionStateManager().setQueueExpandedSections(_expandedSections);
        });
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
  void reassemble() {
    super.reassemble();
    // Clean up observers on hot reload to prevent accumulation
    NotificationCenter.removeObserver(this);
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    _searchManager.removeListener(_onSearchChanged);
    _searchManager.removeSearchOpenListener(_onSearchVisibilityChanged);
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _stopFullSyncTimers();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _startFullSyncTimers();
      _scheduleFullSync(immediate: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopFullSyncTimers();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only check day transition and load data after initial dependencies are set
    // This prevents multiple calls during hot restart on web
    if (!_didInitialDependencies) {
      _didInitialDependencies = true;
      // Check for day transition when page becomes visible
      _checkDayTransition();
    } else {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent && _shouldReloadOnReturn) {
        _shouldReloadOnReturn = false;
        _checkDayTransition();
        _loadData();
      }
    }
  }

  void _checkDayTransition() {
    final today = DateService.todayStart;
    if (_lastKnownDate != null && !_isSameDay(_lastKnownDate!, today)) {
      if (currentUserUid.isEmpty) return;
      // Day has changed - reload all data
      _lastKnownDate = today;
      // Invalidate daily progress cache since historical data may have changed
      DailyProgressQueryService.invalidateUserCache(currentUserUid);
      _loadData();
      _loadCumulativeScoreHistory(forceReload: true);
      _calculateProgress();
    } else if (_lastKnownDate == null) {
      _lastKnownDate = today;
    }
  }

  void _startFullSyncTimers() {
    _fullSyncIntervalTimer?.cancel();
    _fullSyncIntervalTimer = Timer.periodic(_fullSyncInterval, (_) {
      if (!mounted) return;
      final lastSync = _lastFullSyncAt;
      if (lastSync == null ||
          DateTime.now().difference(lastSync) >= _fullSyncInterval) {
        _triggerFullSync(reason: 'interval');
      }
    });
  }

  void _stopFullSyncTimers() {
    _fullSyncDebounceTimer?.cancel();
    _fullSyncIntervalTimer?.cancel();
  }

  void _scheduleFullSync({bool immediate = false}) {
    _fullSyncDebounceTimer?.cancel();
    if (immediate) {
      _triggerFullSync(reason: 'immediate');
      return;
    }
    _fullSyncDebounceTimer = Timer(_fullSyncDebounceDuration, () {
      if (!mounted) return;
      _triggerFullSync(reason: 'debounced');
    });
  }

  Future<void> _triggerFullSync({String reason = 'scheduled'}) async {
    if (!mounted || currentUserUid.isEmpty) return;
    if (_isCalculatingProgress || _isLoadingData) {
      _scheduleFullSync();
      return;
    }
    await _calculateProgress(optimistic: false);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  void didUpdateWidget(covariant QueuePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final templateChanged = widget.focusTemplateId != oldWidget.focusTemplateId;
    final instanceChanged = widget.focusInstanceId != oldWidget.focusInstanceId;
    if (templateChanged || instanceChanged) {
      _pendingFocusTemplateId = widget.focusTemplateId;
      _pendingFocusInstanceId = widget.focusInstanceId;
      _hasAppliedInitialFocus = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _maybeApplyPendingFocus();
        }
      });
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
        _cachedBucketedItems = null;
      });
    }
  }

  void _onSearchChanged(String query) {
    if (mounted) {
      setState(() {
        _searchQuery = query;
        _cachedBucketedItems = null;
      });
    }
  }

  void _onSearchVisibilityChanged(bool isVisible) {
    if (!mounted) {
      _isSearchBarVisible = isVisible;
      return;
    }
    // Only update if value actually changed
    if (_isSearchBarVisible != isVisible) {
      setState(() {
        _isSearchBarVisible = isVisible;
      });
    }
  }

  Future<void> _loadData({bool isInitialLoad = false}) async {
    if (_isLoadingData) return;
    if (!mounted) return;
    _isLoadingData = true;
    _ignoreInstanceEvents = true; // Temporarily ignore events during load
    // Only set loading state if it's not already true
    if (!_isLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isNotEmpty) {
        final result = await QueueDataService.loadQueueData(userId: userId);
        if (!mounted) return;

        // Use filter logic service to initialize filter state
        final updatedFilter = QueueFilterLogic.initializeFilterState(
          currentFilter: _currentFilter,
          categories: result.categories,
        );

        if (mounted) {
          // Calculate hash codes when data changes (not in getter)
          final newInstancesHash =
              QueueBucketService.calculateInstancesHash(result.instances);
          final newCategoriesHash =
              QueueBucketService.calculateCategoriesHash(result.categories);

          // Batch all state updates into single setState
          setState(() {
            _instances = result.instances;
            _categories = result.categories;
            _cachedBucketedItems = null;
            _itemKeys.removeWhere(
              (id, key) => !result.instances
                  .any((instance) => instance.reference.id == id),
            );
            _currentFilter = updatedFilter;
            // Only clear loading state if this is not the initial load
            // (initial load will be cleared after history is loaded)
            if (!isInitialLoad) {
              _isLoading = false;
            }
            _isLoadingData = false;
            // Update hash codes when data changes
            _instancesHashCode = newInstancesHash;
            _categoriesHashCode = newCategoriesHash;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _maybeApplyPendingFocus();
            }
          });
          // Fast UI update using local instances
          _calculateProgress(optimistic: true);
          // Reconcile with backend in background
          Future.microtask(() async {
            await _calculateProgress(optimistic: false);
            // Mark initial load as complete - use incremental updates from now on
            _isInitialLoadComplete = true;
          });
          _ignoreInstanceEvents = false;
          try {
            await InstanceOrderService.initializeOrderValues(
                result.instances, 'queue');
          } catch (_) {}
        } else {
          _isLoadingData = false;
          _ignoreInstanceEvents = false;
        }
      } else {
        // Batch state updates for empty user case
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isLoadingData = false;
          });
        } else {
          _isLoadingData = false;
        }
        _ignoreInstanceEvents = false;
      }
    } catch (e) {
      // Batch state updates for error case
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingData = false;
        });
      } else {
        _isLoadingData = false;
      }
      _ignoreInstanceEvents = false;
    }
  }

  void _maybeApplyPendingFocus() {
    if (_hasAppliedInitialFocus) return;
    final targetInstanceId = _pendingFocusInstanceId ?? widget.focusInstanceId;
    final targetTemplateId = _pendingFocusTemplateId ?? widget.focusTemplateId;

    // Use focus handler service to find target
    final focusResult = QueueFocusHandler.findFocusTarget(
      buckets: _bucketedItems,
      targetInstanceId: targetInstanceId,
      targetTemplateId: targetTemplateId,
    );

    if (focusResult == null) {
      return;
    }

    _pendingFocusInstanceId = null;
    _pendingFocusTemplateId = null;
    _hasAppliedInitialFocus = true;

    setState(() {
      _highlightedInstanceId = focusResult.instanceId;
      if (focusResult.sectionKey != null) {
        _expandedSections.add(focusResult.sectionKey!);
        _cachedBucketedItems = null;
      }
    });
    if (focusResult.sectionKey != null) {
      ExpansionStateManager().setQueueExpandedSections(_expandedSections);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final highlightKey = _itemKeys[focusResult.instanceId];
      if (highlightKey?.currentContext != null) {
        Scrollable.ensureVisible(
          highlightKey!.currentContext!,
          duration: const Duration(milliseconds: 400),
          alignment: 0.1,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });

    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() => _highlightedInstanceId = null);
      }
    });
  }

  Future<void> _calculateProgress({bool optimistic = false}) async {
    if (currentUserUid.isEmpty) {
      return;
    }
    // Increment version to track calculation order
    final calculationVersion = ++_progressCalculationVersion;

    if (optimistic) {
      // INSTANT calculation - synchronous, no Firestore queries
      // Like an Excel sheet - calculates from instances already in memory
      final progressData =
          TodayCompletionPointsService.calculateTodayCompletionPointsSync(
        userId: currentUserUid,
        instances: _instances,
        categories: _categories,
      );

      // Only update UI if this is still the latest calculation
      // (no newer calculation has started since we began)
      if (mounted && calculationVersion == _progressCalculationVersion) {
        final newTarget = progressData['target'] as double;
        final newEarned = progressData['earned'] as double;
        final newPercentage = progressData['percentage'] as double;
        // Only update if values actually changed
        if (newTarget != _dailyTarget ||
            newEarned != _pointsEarned ||
            newPercentage != _dailyPercentage) {
          setState(() {
            _dailyTarget = newTarget;
            _pointsEarned = newEarned;
            _dailyPercentage = newPercentage;
          });
        }
      }

      // Don't update score from optimistic calculation - wait for non-optimistic
      // to ensure we use reconciled values from backend
      // Score will be updated by _calculateProgress(optimistic: false) which awaits _updateTodayScore()
    } else {
      // Prevent concurrent non-optimistic calculations
      if (_isCalculatingProgress) {
        return; // Skip if already calculating
      }

      _isCalculatingProgress = true;

      try {
        final userId = await waitForCurrentUserUid();
        if (userId.isEmpty) {
          _isCalculatingProgress = false;
          return;
        }
        // #region agent log
        _logQueueCrashDebug('_calculateProgress', {
          'hypothesisId': 'Q',
          'event': 'calc_start',
          'optimistic': false,
          'instanceCount': _instances.length,
          'categoryCount': _categories.length,
          'version': calculationVersion,
        });
        // #endregion
        // BACKEND RECONCILIATION: Use full calculation with Firestore
        // Fetch full data to ensure completed items are included even if filtered from UI
        final breakdownData =
            await ProgressPageDataService.fetchInstancesForBreakdown(
                userId: userId);
        final allHabits =
            breakdownData['habits'] as List<ActivityInstanceRecord>;
        final allTasks = breakdownData['tasks'] as List<ActivityInstanceRecord>;
        final allCategories =
            breakdownData['categories'] as List<CategoryRecord>;
        final allInstances = [...allHabits, ...allTasks];

        final progressData =
            await TodayCompletionPointsService.calculateTodayCompletionPoints(
          userId: userId,
          instances: allInstances,
          categories: allCategories,
          optimistic: false,
        );
        // #region agent log
        _logQueueCrashDebug('_calculateProgress', {
          'hypothesisId': 'Q',
          'event': 'calc_result',
          'target': progressData['target'],
          'earned': progressData['earned'],
          'percentage': progressData['percentage'],
          'version': calculationVersion,
        });
        // #endregion

        // Only update UI if this is still the latest calculation
        // (no newer calculation has started since we began)
        if (mounted && calculationVersion == _progressCalculationVersion) {
          final newTarget = progressData['target'] as double;
          final newEarned = progressData['earned'] as double;
          final newPercentage = progressData['percentage'] as double;
          // Only update if values actually changed
          if (newTarget != _dailyTarget ||
              newEarned != _pointsEarned ||
              newPercentage != _dailyPercentage) {
            setState(() {
              _dailyTarget = newTarget;
              _pointsEarned = newEarned;
              _dailyPercentage = newPercentage;
            });
          }

          // For non-optimistic, await to ensure accuracy
          // Pass fetched data to avoid re-fetching
          await _updateTodayScore(
            habitInstancesOverride: allHabits,
            categoriesOverride: allCategories,
          );
          _lastFullSyncAt = DateTime.now();
        }
      } catch (e) {
        // #region agent log
        _logQueueCrashDebug('_calculateProgress', {
          'hypothesisId': 'Q',
          'event': 'calc_error',
          'errorType': e.runtimeType.toString(),
        });
        // #endregion
        rethrow;
      } finally {
        _isCalculatingProgress = false;
      }
    }
  }

  Future<void> _updateTodayScore({
    List<ActivityInstanceRecord>? habitInstancesOverride,
    List<CategoryRecord>? categoriesOverride,
  }) async {
    if (_isUpdatingLiveScore) {
      _pendingLiveScoreUpdate = true;
      return;
    }

    _isUpdatingLiveScore = true;

    try {
      // #region agent log
      _logQueueCrashDebug('_updateTodayScore', {
        'hypothesisId': 'Q',
        'event': 'score_start',
        'instanceCount': _instances.length,
        'categoryCount': _categories.length,
      });
      // #endregion
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      List<ActivityInstanceRecord> habitInstances;
      List<CategoryRecord> categories;

      if (habitInstancesOverride != null && categoriesOverride != null) {
        habitInstances = habitInstancesOverride;
        categories = categoriesOverride;
      } else {
        // Fetch accurate data from DB to ensure score is correct even if local list is filtered
        final breakdownData =
            await ProgressPageDataService.fetchInstancesForBreakdown(
                userId: userId);
        habitInstances =
            breakdownData['habits'] as List<ActivityInstanceRecord>;
        categories = breakdownData['categories'] as List<CategoryRecord>;
      }

      final scoreData = await ScoreCoordinator.updateTodayScore(
        userId: userId,
        completionPercentage: _dailyPercentage,
        pointsEarned: _pointsEarned,
        categories: categories,
        habitInstances: habitInstances,
        includeBreakdown: true, // Always include breakdown for consistency
      );
      if (mounted) {
        final newCumulativeScore =
            (scoreData['cumulativeScore'] as num?)?.toDouble() ?? 0.0;
        final newDailyScoreGain =
            (scoreData['todayScore'] as num?)?.toDouble() ?? 0.0;
        // Only update if values actually changed
        if (newCumulativeScore != _cumulativeScore ||
            newDailyScoreGain != _dailyScoreGain) {
          setState(() {
            _cumulativeScore = newCumulativeScore;
            _dailyScoreGain = newDailyScoreGain;
          });
        }
      }

      final finalCumulativeScore =
          (scoreData['cumulativeScore'] as num?)?.toDouble() ?? 0.0;
      final finalTodayScore =
          (scoreData['todayScore'] as num?)?.toDouble() ?? 0.0;

      _queueHistoryOverlay(finalCumulativeScore, finalTodayScore);

      // Update single document history (non-blocking)
      unawaited(ScoreHistoryService.updateScoreHistoryDocument(
        userId: userId,
        cumulativeScore: finalCumulativeScore,
        todayScore: finalTodayScore,
      ));
    } catch (e) {
      // #region agent log
      _logQueueCrashDebug('_updateTodayScore', {
        'hypothesisId': 'Q',
        'event': 'score_error',
        'errorType': e.runtimeType.toString(),
      });
      // #endregion
      rethrow;
    } finally {
      _isUpdatingLiveScore = false;
      if (_pendingLiveScoreUpdate) {
        _pendingLiveScoreUpdate = false;
        Future.microtask(_updateTodayScore);
      }
    }
  }

  /// Calculate target contribution for a single instance
  /// Used for incremental progress updates (only queries template for this instance)
  Future<double> _getInstanceTargetContribution(
      ActivityInstanceRecord instance) async {
    if (instance.templateCategoryType != 'habit' ||
        instance.templateCategoryType == 'essential') {
      return 0.0;
    }

    // Fetch template only for this one instance (1 read)
    final userId = await waitForCurrentUserUid();
    if (userId.isEmpty) return 0.0;
    final template = await ActivityTemplateService.getTemplateById(
      userId: userId,
      templateId: instance.templateId,
    );
    if (template != null) {
      return PointsService.calculateDailyTargetWithTemplate(instance, template);
    }
    // Fallback to basic calculation if template fetch fails
    return PointsService.calculateDailyTarget(instance);
  }

  /// Calculate earned points contribution for a single instance
  /// Used for incremental progress updates
  Future<double> _getInstanceEarnedContribution(
      ActivityInstanceRecord instance) async {
    if (instance.templateCategoryType == 'essential') {
      return 0.0;
    }
    final userId = await waitForCurrentUserUid();
    if (userId.isEmpty) return 0.0;
    return await PointsService.calculatePointsEarned(instance, userId);
  }

  /// Calculate progress incrementally by applying delta from instance change
  /// Only calculates contribution for the changed instance instead of all instances
  Future<void> _calculateProgressIncremental({
    required ActivityInstanceRecord? oldInstance,
    required ActivityInstanceRecord? newInstance,
  }) async {
    // Prevent concurrent calculations
    if (_isCalculatingProgress) {
      return;
    }

    _isCalculatingProgress = true;
    final calculationVersion = ++_progressCalculationVersion;

    try {
      // Calculate old contribution (if instance existed)
      double oldTarget = 0.0;
      double oldEarned = 0.0;
      if (oldInstance != null) {
        oldTarget = await _getInstanceTargetContribution(oldInstance);
        oldEarned = await _getInstanceEarnedContribution(oldInstance);
      }

      // Calculate new contribution (if instance exists)
      double newTarget = 0.0;
      double newEarned = 0.0;
      if (newInstance != null) {
        newTarget = await _getInstanceTargetContribution(newInstance);
        newEarned = await _getInstanceEarnedContribution(newInstance);
      }

      // Apply delta
      final updatedTarget = _dailyTarget - oldTarget + newTarget;
      final updatedEarned = _pointsEarned - oldEarned + newEarned;
      final updatedPercentage = PointsService.calculateDailyPerformancePercent(
          updatedEarned, updatedTarget);

      // Only update UI if this is still the latest calculation
      if (mounted && calculationVersion == _progressCalculationVersion) {
        // Only update if values actually changed
        if (updatedTarget != _dailyTarget ||
            updatedEarned != _pointsEarned ||
            updatedPercentage != _dailyPercentage) {
          setState(() {
            _dailyTarget = updatedTarget;
            _pointsEarned = updatedEarned;
            _dailyPercentage = updatedPercentage;
          });
        }

        // Update score after progress calculation
        final habitInstances = _instances
            .where((inst) => inst.templateCategoryType == 'habit')
            .toList();
        await _updateTodayScore(
          habitInstancesOverride: habitInstances,
          categoriesOverride: _categories,
        );
      }
    } finally {
      _isCalculatingProgress = false;
    }
  }

  Future<void> _loadCumulativeScoreHistory(
      {bool forceReload = false, bool isInitialLoad = false}) async {
    if (_isLoadingHistory) {
      if (forceReload) {
        _pendingHistoryReload = true;
      }
      return;
    }

    try {
      // #region agent log
      _logQueueCrashDebug('_loadCumulativeScoreHistory', {
        'hypothesisId': 'Q',
        'event': 'history_start',
        'forceReload': forceReload,
      });
      // #endregion
      _isLoadingHistory = true;
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        _isLoadingHistory = false;
        // Clear loading state on initial load even if user is empty
        if (isInitialLoad && mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Load 30 days of history from single document (optimized - 1 read instead of 30+)
      final result = await ScoreHistoryService.loadScoreHistoryFromSingleDoc(
        userId: userId,
        days: 30,
        cumulativeScore: _cumulativeScore > 0 ? _cumulativeScore : null,
        todayScore: _dailyScoreGain > 0 ? _dailyScoreGain : null,
      );

      final currentCumulativeScore =
          (result['cumulativeScore'] as num?)?.toDouble() ?? 0.0;
      final currentTodayScore =
          (result['todayScore'] as num?)?.toDouble() ?? 0.0;
      final history =
          (result['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final bool isNewHistoryValid =
          history.any((h) => (h['score'] as double) > 0);
      final bool wasOldHistoryValid =
          _cumulativeScoreHistory.any((h) => (h['score'] as double) > 0);

      if (!isNewHistoryValid && wasOldHistoryValid) {
        _isLoadingHistory = false;
        // Clear loading state on initial load even if history is invalid
        if (isInitialLoad && mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
      // Only update if values actually changed
      final scoreChanged = currentCumulativeScore != _cumulativeScore ||
          currentTodayScore != _dailyScoreGain;
      final historyChanged =
          history.length != _cumulativeScoreHistory.length || !_historyLoaded;

      if (mounted && (scoreChanged || historyChanged)) {
        setState(() {
          _cumulativeScore = currentCumulativeScore;
          _dailyScoreGain = currentTodayScore;
          _cumulativeScoreHistory = history;
          _historyLoaded = true;
          // Clear loading state on initial load after history is loaded
          if (isInitialLoad) {
            _isLoading = false;
          }
        });
      } else if (!mounted) {
        _cumulativeScore = currentCumulativeScore;
        _dailyScoreGain = currentTodayScore;
        _cumulativeScoreHistory = history;
        _historyLoaded = true;
      } else if (isInitialLoad && mounted) {
        // Even if nothing changed, clear loading state on initial load
        setState(() {
          _isLoading = false;
        });
      }

      final overlayScore = _pendingHistoryScore ?? _cumulativeScore;
      final overlayGain = _pendingHistoryGain ?? _dailyScoreGain;
      _queueHistoryOverlay(overlayScore, overlayGain);
      _pendingHistoryScore = null;
      _pendingHistoryGain = null;
    } catch (e) {
      // #region agent log
      _logQueueCrashDebug('_loadCumulativeScoreHistory', {
        'hypothesisId': 'Q',
        'event': 'history_error',
        'errorType': e.runtimeType.toString(),
      });
      // #endregion
      // Clear loading state on initial load even if there's an error
      if (isInitialLoad && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } finally {
      _isLoadingHistory = false;
      if (_pendingHistoryReload) {
        _pendingHistoryReload = false;
        Future.microtask(() => _loadCumulativeScoreHistory());
      }
    }
  }

  List<Map<String, dynamic>> _getMiniGraphHistory() {
    // Only return history if it's loaded and has valid data
    // This prevents showing incorrect values during initial load
    if (!_historyLoaded || _cumulativeScoreHistory.isEmpty) return [];
    return List<Map<String, dynamic>>.from(_cumulativeScoreHistory);
  }

  void _queueHistoryOverlay(double cumulativeScore, double todayScore) {
    if (_historyLoaded) {
      // Create a copy of the list to ensure Flutter detects the change
      final historyCopy =
          List<Map<String, dynamic>>.from(_cumulativeScoreHistory);
      final changed = ScoreCoordinator.updateHistoryWithTodayScore(
        historyCopy,
        todayScore,
        cumulativeScore,
      );
      // Only update if history actually changed
      if (changed && mounted) {
        setState(() {
          // Assign new list reference to trigger widget rebuild
          _cumulativeScoreHistory = historyCopy;
        });
      }
    } else {
      // Don't create temporary history entries - just store pending values
      // This prevents showing incorrect values in the chart during initial load
      if (_pendingHistoryScore != cumulativeScore ||
          _pendingHistoryGain != todayScore) {
        _pendingHistoryScore = cumulativeScore;
        _pendingHistoryGain = todayScore;
        // Don't update _cumulativeScoreHistory until real history is loaded
        // This ensures the chart shows loading state until valid data is available
      }
    }
  }

  Map<String, List<ActivityInstanceRecord>> get _bucketedItems {
    // Hash codes are now calculated when data changes, not in getter
    // This avoids expensive hash calculations on every build
    // Compare current hash codes with cached ones to detect data changes
    final cacheInvalid = _cachedBucketedItems == null ||
        _instancesHashCode != _lastCachedInstancesHash ||
        _categoriesHashCode != _lastCachedCategoriesHash ||
        _searchQuery != _lastSearchQuery ||
        !QueueUtils.filtersEqual(_currentFilter, _lastFilter) ||
        !QueueUtils.sortsEqual(_currentSort, _lastSort) ||
        !QueueUtils.setsEqual(_expandedSections, _lastExpandedSections);

    if (!cacheInvalid && _cachedBucketedItems != null) {
      return _cachedBucketedItems!;
    }
    final buckets = QueueBucketService.bucketItems(
      instances: _instances,
      categories: _categories,
      currentFilter: _currentFilter,
      currentSort: _currentSort,
      expandedSections: _expandedSections,
      searchQuery: _searchQuery,
      isDefaultFilterState: _isDefaultFilterState(),
    );

    if (_searchQuery.isNotEmpty) {
      for (final key in buckets.keys) {
        if (buckets[key]!.isNotEmpty) {
          _expandedSections.add(key);
        }
      }
    }
    _cachedBucketedItems = buckets;
    // Store the hash codes that were used to build this cache
    _lastCachedInstancesHash = _instancesHashCode;
    _lastCachedCategoriesHash = _categoriesHashCode;
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

  String _getSubtitle(ActivityInstanceRecord item, String bucketKey) {
    return QueueUtils.getSubtitle(item, bucketKey);
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
          title: const TabBar(
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
                if (sortType == QueueSortType.none) {
                  await QueueSortStateManager().clearSortState();
                  if (mounted) {
                    setState(() {
                      _currentSort = QueueSortState();
                      _cachedBucketedItems = null;
                    });
                  }
                  return;
                }
                if (sortType == QueueSortType.points) {
                  final sort = QueueSortState(
                    sortType: QueueSortType.points,
                  );
                  if (mounted) {
                    await QueueSortStateManager().setSortState(sort);
                    setState(() {
                      _currentSort = sort;
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
                      _cachedBucketedItems = null;
                    });
                  }
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: QueueSortType.none,
                  child: Text('Manual Order'),
                ),
                const PopupMenuItem<String>(
                  value: QueueSortType.points,
                  child: Text('Sort by Points'),
                ),
                const PopupMenuItem<String>(
                  value: QueueSortType.time,
                  child: Text('Sort by Time'),
                ),
                const PopupMenuItem<String>(
                  value: QueueSortType.urgency,
                  child: Text('Sort by Urgency'),
                ),
              ],
            ),
            _buildFilterButton(theme),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildDailyTabContent(),
                      WeeklyView(searchQuery: _searchQuery),
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

  Widget _buildProgressCharts() {
    final miniGraphHistory = _getMiniGraphHistory();
    // Wrap expensive chart widgets in RepaintBoundary to isolate repaints
    return RepaintBoundary(
      child: QueueUIBuilders.buildProgressCharts(
        context: context,
        dailyPercentage: _dailyPercentage,
        dailyTarget: _dailyTarget,
        pointsEarned: _pointsEarned,
        miniGraphHistory: miniGraphHistory,
        isHistoryLoading: _isLoadingHistory,
      ),
    );
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
                          _expandedSections.remove(key);
                        } else {
                          _expandedSections.add(key);
                        }
                        _cachedBucketedItems = null;
                      });
                      ExpansionStateManager()
                          .setQueueExpandedSections(_expandedSections);
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
              final highlightKey = _itemKeys.putIfAbsent(
                item.reference.id,
                () => GlobalKey(),
              );
              final isHighlighted = _highlightedInstanceId == item.reference.id;
              return ReorderableDelayedDragStartListener(
                index: index,
                key: Key('${item.reference.id}_drag'),
                child: AnimatedContainer(
                  key: highlightKey,
                  duration: const Duration(milliseconds: 250),
                  decoration: isHighlighted
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.primary,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.primary.withOpacity(0.25),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ],
                        )
                      : null,
                  child: ItemComponent(
                    key: ValueKey(item.reference.id),
                    subtitle: _getSubtitle(item, key),
                    instance: item,
                    categoryColorHex: _getCategoryColor(item),
                    onRefresh:
                        () async {}, // No-op - updates handled via NotificationCenter
                    onInstanceUpdated: _updateInstanceInLocalState,
                    onInstanceDeleted: _removeInstanceFromLocalState,
                    onHabitUpdated: (updated) => {},
                    onHabitDeleted:
                        (deleted) {}, // No-op - instance deletions handled via NotificationCenter
                    isHabit: isHabit,
                    showTypeIcon: true,
                    showRecurringIcon: true,
                    showCompleted:
                        (key == 'Completed' || key == 'Skipped/Snoozed')
                            ? true
                            : null,
                    page: 'queue',
                  ),
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
    final bodySlivers = <Widget>[];
    if (!_isSearchBarVisible) {
      bodySlivers.add(
        SliverToBoxAdapter(
          child: _buildProgressCharts(),
        ),
      );
      bodySlivers.add(const SliverToBoxAdapter(
        child: SizedBox(height: 16),
      ));
    }
    bodySlivers.addAll(slivers);
    bodySlivers.add(const SliverToBoxAdapter(
      child: SizedBox(height: 140),
    ));

    return RefreshIndicator(
      onRefresh: () async {
        await _loadData();
        if (mounted) {
          await _loadCumulativeScoreHistory(forceReload: true);
          await _updateTodayScore();
        }
      },
      child: CustomScrollView(
        controller: _scrollController,
        cacheExtent:
            500.0, // Cache 500px worth of items above/below viewport for better scroll performance
        slivers: bodySlivers,
      ),
    );
  }

  String _getCategoryColor(ActivityInstanceRecord instance) {
    return QueueUtils.getCategoryColor(instance, _categories);
  }

  bool _isDefaultFilterState() {
    return QueueUtils.isDefaultFilterState(_currentFilter, _categories);
  }

  int _getExcludedCategoryCount() {
    return QueueUtils.getExcludedCategoryCount(_currentFilter, _categories);
  }

  Widget _buildFilterButton(FlutterFlowTheme theme) {
    return buildFilterButton(
      context: context,
      currentFilter: _currentFilter,
      categories: _categories,
      onFilterChanged: (result) async {
        if (mounted) {
          setState(() {
            _currentFilter = result;
            _cachedBucketedItems = null;
          });
          // Use filter logic service to handle state persistence
          await QueueFilterLogic.handleFilterStateChange(
            newFilter: result,
            categories: _categories,
          );
        }
      },
      isDefaultFilterState: _isDefaultFilterState(),
      excludedCategoryCount: _getExcludedCategoryCount(),
    );
  }

  void _updateInstanceInLocalState(
      ActivityInstanceRecord updatedInstance) async {
    // Recalculate hash codes when instances change
    QueueInstanceHandlers.updateInstanceInLocalState(
      _instances,
      updatedInstance,
    );
    final newInstancesHash =
        QueueBucketService.calculateInstancesHash(_instances);

    setState(() {
      _cachedBucketedItems = null;
      _instancesHashCode = newInstancesHash;
    });
    _calculateProgress(optimistic: true);
    _scheduleFullSync();
  }

  void _removeInstanceFromLocalState(
      ActivityInstanceRecord deletedInstance) async {
    // Recalculate hash codes when instances change
    QueueInstanceHandlers.removeInstanceFromLocalState(
      _instances,
      deletedInstance,
    );
    final newInstancesHash =
        QueueBucketService.calculateInstancesHash(_instances);

    setState(() {
      _cachedBucketedItems = null;
      _instancesHashCode = newInstancesHash;
    });
    _calculateProgress(optimistic: true);
    _scheduleFullSync();
  }

  void _handleInstanceCreated(ActivityInstanceRecord instance) {
    // Recalculate hash codes when instances change
    QueueInstanceHandlers.handleInstanceCreated(_instances, instance);
    final newInstancesHash =
        QueueBucketService.calculateInstancesHash(_instances);

    setState(() {
      _cachedBucketedItems = null;
      _instancesHashCode = newInstancesHash;
    });

    // Use incremental update if initial load is complete
    if (_isInitialLoadComplete) {
      // Incremental update: add new instance's contribution
      Future.microtask(() => _calculateProgressIncremental(
            oldInstance: null,
            newInstance: instance,
          ));
    } else {
      // Full calculation for initial load
      _calculateProgress(optimistic: true);
      _scheduleFullSync();
    }
  }

  void _handleInstanceUpdated(dynamic param) {
    ActivityInstanceRecord? instance;
    if (param is Map) {
      instance = param['instance'] as ActivityInstanceRecord?;
      if (instance != null &&
          _reorderingInstanceIds.contains(instance.reference.id)) {
        return;
      }
    } else if (param is ActivityInstanceRecord) {
      if (_reorderingInstanceIds.contains(param.reference.id)) {
        return;
      }
    }

    // Get old instance before updating for incremental calculation
    ActivityInstanceRecord? oldInstance;
    if (instance != null) {
      final oldIndex = _instances
          .indexWhere((inst) => inst.reference.id == instance!.reference.id);
      if (oldIndex != -1) {
        oldInstance = _instances[oldIndex];
      }
    }

    // Recalculate hash codes when instances change
    QueueInstanceHandlers.handleInstanceUpdated(
      _instances,
      param,
      _reorderingInstanceIds,
      _optimisticOperations,
    );
    final newInstancesHash =
        QueueBucketService.calculateInstancesHash(_instances);

    setState(() {
      _cachedBucketedItems = null;
      _instancesHashCode = newInstancesHash;
    });
    bool isOptimistic = false;
    if (param is Map) {
      isOptimistic = param['isOptimistic'] as bool? ?? false;
    }

    // Use incremental update if initial load is complete, otherwise use full calculation
    if (_isInitialLoadComplete && !isOptimistic && instance != null) {
      // Incremental update: only calculate contribution for changed instance
      Future.microtask(() => _calculateProgressIncremental(
            oldInstance: oldInstance,
            newInstance: instance,
          ));
    } else {
      // Full calculation for initial load or optimistic updates
      _calculateProgress(optimistic: true);
      if (!isOptimistic) {
        _scheduleFullSync();
      }
    }
  }

  void _handleRollback(dynamic param) {
    if (param is Map) {
      final operationId = param['operationId'] as String?;
      final instanceId = param['instanceId'] as String?;
      final originalInstance =
          param['originalInstance'] as ActivityInstanceRecord?;
      if (operationId != null &&
          _optimisticOperations.containsKey(operationId)) {
        // Recalculate hash codes when instances change
        QueueInstanceHandlers.handleRollback(
          _instances,
          param,
          _optimisticOperations,
        );
        final newInstancesHash =
            QueueBucketService.calculateInstancesHash(_instances);

        setState(() {
          _cachedBucketedItems = null;
          _instancesHashCode = newInstancesHash;
        });
        if (originalInstance == null && instanceId != null) {
          _revertOptimisticUpdate(instanceId);
        } else {
          _scheduleFullSync(immediate: true);
        }
      }
    }
  }

  Future<void> _revertOptimisticUpdate(String instanceId) async {
    final updatedInstance =
        await QueueInstanceHandlers.revertOptimisticUpdate(instanceId);
    if (updatedInstance != null) {
      final index =
          _instances.indexWhere((inst) => inst.reference.id == instanceId);
      if (index != -1) {
        // Recalculate hash codes when instances change
        _instances[index] = updatedInstance;
        final newInstancesHash =
            QueueBucketService.calculateInstancesHash(_instances);

        setState(() {
          _cachedBucketedItems = null;
          _instancesHashCode = newInstancesHash;
        });
      }
      _calculateProgress(optimistic: false);
    }
  }

  void _handleInstanceDeleted(ActivityInstanceRecord instance) {
    // Recalculate hash codes when instances change
    QueueInstanceHandlers.handleInstanceDeleted(_instances, instance);
    final newInstancesHash =
        QueueBucketService.calculateInstancesHash(_instances);

    setState(() {
      _cachedBucketedItems = null;
      _instancesHashCode = newInstancesHash;
    });

    // Use incremental update if initial load is complete
    if (_isInitialLoadComplete) {
      // Incremental update: subtract deleted instance's contribution
      Future.microtask(() => _calculateProgressIncremental(
            oldInstance: instance,
            newInstance: null,
          ));
    } else {
      // Full calculation for initial load
      _calculateProgress(optimistic: true);
      _scheduleFullSync();
    }
  }

  Future<void> _silentRefreshInstances() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      final result =
          await QueueDataService.silentRefreshInstances(userId: userId);
      if (mounted) {
        // Calculate hash codes when data changes
        final newInstancesHash =
            QueueBucketService.calculateInstancesHash(result.instances);
        final newCategoriesHash =
            QueueBucketService.calculateCategoriesHash(result.categories);

        setState(() {
          _instances = result.instances;
          _categories = result.categories;
          _cachedBucketedItems = null;
          _instancesHashCode = newInstancesHash;
          _categoriesHashCode = newCategoriesHash;
        });
        // Fast UI update using local instances
        _calculateProgress(optimistic: true);
        _scheduleFullSync();
      }
    } catch (e) {}
  }

  Future<void> _handleReorder(
      int oldIndex, int newIndex, String sectionKey) async {
    try {
      if (_currentSort.isActive) {
        final clearedSort = QueueSortState();
        await QueueSortStateManager().setSortState(clearedSort);
        if (mounted) {
          setState(() {
            _currentSort = clearedSort;
            _cachedBucketedItems = null;
          });
        }
      }

      final buckets = _bucketedItems;
      final items = buckets[sectionKey]!;

      await QueueReorderHandler.handleReorder(
        items: items,
        oldIndex: oldIndex,
        newIndex: newIndex,
        allInstances: _instances,
        reorderingInstanceIds: _reorderingInstanceIds,
        isSortActive: _currentSort.isActive,
        sectionKey: sectionKey,
        onOptimisticUpdate: (updatedInstances, reorderingIds) {
          if (mounted) {
            final newInstancesHash =
                QueueBucketService.calculateInstancesHash(updatedInstances);
            setState(() {
              _instances = updatedInstances;
              _reorderingInstanceIds.clear();
              _reorderingInstanceIds.addAll(reorderingIds);
              _cachedBucketedItems = null;
              _instancesHashCode = newInstancesHash;
            });
          }
        },
      );

      // Clear reordering IDs after successful update
      if (mounted) {
        setState(() {
          _reorderingInstanceIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _reorderingInstanceIds.clear();
        });
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error reordering items: $e')),
          );
        }
      }
    }
  }
}
