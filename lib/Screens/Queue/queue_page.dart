import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic%20update.dart';
import 'package:habit_tracker/Screens/Item_component/item_component_main.dart';
import 'package:habit_tracker/Helper/backend/today_progress_state.dart';
import 'package:habit_tracker/Screens/Shared/section_expansion_state_manager.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_fab.dart';
import 'package:habit_tracker/Screens/Queue/weekly_view.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';
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
import 'package:habit_tracker/Screens/Queue/Queue_progress_section/queue_progress_calculator.dart';
import 'package:habit_tracker/Screens/Queue/Helpers/queue_focus_handler.dart';
import 'package:habit_tracker/Screens/Queue/Queue_progress_section/queue_progress_section.dart';
import 'package:habit_tracker/Screens/Queue/Queue_filter/queue_filter_dialog.dart';
import 'dart:async';

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

class _QueuePageState extends State<QueuePage> {
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
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();
  bool _isSearchBarVisible = false;
  QueueFilterState _currentFilter = QueueFilterState();
  QueueSortState _currentSort = QueueSortState();
  Map<String, List<ActivityInstanceRecord>>? _cachedBucketedItems;
  int _instancesHashCode = 0;
  int _categoriesHashCode = 0;
  String _lastSearchQuery = '';
  QueueFilterState? _lastFilter;
  QueueSortState? _lastSort;
  Set<String> _lastExpandedSections = {};
  String? _pendingFocusTemplateId;
  String? _pendingFocusInstanceId;
  bool _hasAppliedInitialFocus = false;
  String? _highlightedInstanceId;
  Timer? _highlightTimer;
  @override
  void initState() {
    super.initState();
    _pendingFocusTemplateId = widget.focusTemplateId;
    _pendingFocusInstanceId = widget.focusInstanceId;
    _loadExpansionState();
    _loadFilterAndSortState().then((_) {
      _loadData().then((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadCumulativeScoreHistory();
          }
        });
        if (widget.expandCompleted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              NotificationCenter.post('expandQueueSection', 'Completed');
            }
          });
        }
      });
    });
    NotificationCenter.addObserver(this, 'cumulativeScoreUpdated', (param) {
      if (!mounted) return;
      final data = TodayProgressState().getCumulativeScoreData();
      final updatedScore =
          (data['cumulativeScore'] as double?) ?? _cumulativeScore;
      final updatedGain = (data['dailyGain'] as double?) ?? _dailyScoreGain;
      setState(() {
        _cumulativeScore = updatedScore;
        _dailyScoreGain = updatedGain;
      });
      _queueHistoryOverlay(updatedScore, updatedGain);
    });
    NotificationCenter.addObserver(this, 'todayProgressUpdated', (param) {
      if (!mounted) return;
      _refreshLiveCumulativeScore();
    });
    NotificationCenter.addObserver(this, 'loadData', (param) {
      if (mounted) {
        setState(() {
          _loadData();
        });
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
  void dispose() {
    NotificationCenter.removeObserver(this);
    _searchManager.removeListener(_onSearchChanged);
    _searchManager.removeSearchOpenListener(_onSearchVisibilityChanged);
    _scrollController.dispose();
    _highlightTimer?.cancel();
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
    setState(() {
      _isSearchBarVisible = isVisible;
    });
  }

  Future<void> _loadData() async {
    if (_isLoadingData) return;
    if (!mounted) return;
    _isLoadingData = true;
    _ignoreInstanceEvents = true; // Temporarily ignore events during load
    setState(() => _isLoading = true);
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final result = await QueueDataService.loadQueueData(userId: userId);
        if (!mounted) return;

        // Use filter logic service to initialize filter state
        final updatedFilter = QueueFilterLogic.initializeFilterState(
          currentFilter: _currentFilter,
          categories: result.categories,
        );

        if (mounted) {
          setState(() {
            _instances = result.instances;
            _categories = result.categories;
            _cachedBucketedItems = null;
            _itemKeys.removeWhere(
              (id, key) => !result.instances
                  .any((instance) => instance.reference.id == id),
            );
            _currentFilter = updatedFilter;
            _isLoading = false;
            _isLoadingData = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _maybeApplyPendingFocus();
            }
          });
          _calculateProgress();
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

  void _calculateProgress({bool optimistic = false}) async {
    final progressData = await QueueScoreManager.calculateProgress(
      instances: _instances,
      categories: _categories,
      userId: currentUserUid,
      optimistic: optimistic,
    );
    if (mounted) {
      setState(() {
        _dailyTarget = progressData['target'] as double;
        _pointsEarned = progressData['earned'] as double;
        _dailyPercentage = progressData['percentage'] as double;
      });
    }
    if (optimistic) {
      _updateCumulativeScoreLiveOptimistic();
    } else {
      _updateCumulativeScoreLive();
    }
  }

  Future<void> _updateCumulativeScoreLiveOptimistic() async {
    await _updateCumulativeScoreLive();
  }

  Future<void> _updateCumulativeScoreLive() async {
    if (_isUpdatingLiveScore) {
      _pendingLiveScoreUpdate = true;
      return;
    }

    _isUpdatingLiveScore = true;

    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      final scoreData = await QueueScoreManager.updateCumulativeScoreLive(
        dailyPercentage: _dailyPercentage,
        pointsEarned: _pointsEarned,
        userId: userId,
      );
      if (mounted) {
        setState(() {
          _cumulativeScore = scoreData['cumulativeScore'] as double;
          _dailyScoreGain = scoreData['dailyGain'] as double;
        });
      }

      _queueHistoryOverlay(
        scoreData['cumulativeScore'] as double,
        scoreData['dailyGain'] as double,
      );
    } catch (e) {
    } finally {
      _isUpdatingLiveScore = false;
      if (_pendingLiveScoreUpdate) {
        _pendingLiveScoreUpdate = false;
        Future.microtask(_refreshLiveCumulativeScore);
      }
    }
  }

  Future<void> _refreshLiveCumulativeScore() async {
    try {
      final scoreData = QueueScoreManager.refreshLiveCumulativeScore(
        currentCumulativeScore: _cumulativeScore,
        currentDailyScoreGain: _dailyScoreGain,
      );

      if (scoreData['needsUpdate'] == 1.0) {
        await _updateCumulativeScoreLive();
        return;
      }

      if (mounted) {
        setState(() {
          _cumulativeScore = scoreData['cumulativeScore'] as double;
          _dailyScoreGain = scoreData['dailyGain'] as double;
        });
      }

      _queueHistoryOverlay(
        scoreData['cumulativeScore'] as double,
        scoreData['dailyGain'] as double,
      );
    } catch (e) {}
  }

  Future<void> _loadCumulativeScoreHistory({bool forceReload = false}) async {
    if (_isLoadingHistory) {
      if (forceReload) {
        _pendingHistoryReload = true;
      }
      return;
    }

    try {
      _isLoadingHistory = true;
      final userId = currentUserUid;
      if (userId.isEmpty) {
        _isLoadingHistory = false;
        return;
      }

      final result = await QueueScoreManager.loadCumulativeScoreHistory(
        userId: userId,
      );

      final currentCumulativeScore = result['cumulativeScore'] as double;
      final currentDailyGain = result['dailyGain'] as double;
      final history = result['history'] as List<Map<String, dynamic>>;

      final bool isNewHistoryValid =
          history.any((h) => (h['score'] as double) > 0);
      final bool wasOldHistoryValid =
          _cumulativeScoreHistory.any((h) => (h['score'] as double) > 0);

      if (!isNewHistoryValid && wasOldHistoryValid) {
        _isLoadingHistory = false;
        return;
      }
      if (mounted) {
        setState(() {
          _cumulativeScore = currentCumulativeScore;
          _dailyScoreGain = currentDailyGain;
          _cumulativeScoreHistory = history;
          _historyLoaded = true;
        });
      } else {
        _cumulativeScore = currentCumulativeScore;
        _dailyScoreGain = currentDailyGain;
        _cumulativeScoreHistory = history;
        _historyLoaded = true;
      }

      final overlayScore = _pendingHistoryScore ?? _cumulativeScore;
      final overlayGain = _pendingHistoryGain ?? _dailyScoreGain;
      _queueHistoryOverlay(overlayScore, overlayGain);
      _pendingHistoryScore = null;
      _pendingHistoryGain = null;
    } catch (e) {
    } finally {
      _isLoadingHistory = false;
      if (_pendingHistoryReload) {
        _pendingHistoryReload = false;
        Future.microtask(_loadCumulativeScoreHistory);
      }
    }
  }

  List<Map<String, dynamic>> _getMiniGraphHistory() {
    if (_cumulativeScoreHistory.isEmpty) return [];
    return List<Map<String, dynamic>>.from(_cumulativeScoreHistory);
  }

  bool _applyLiveScoreToHistory(double score, double gain) {
    return QueueScoreManager.applyLiveScoreToHistory(
      _cumulativeScoreHistory,
      score,
      gain,
    );
  }

  void _queueHistoryOverlay(double score, double gain) {
    if (_historyLoaded) {
      final changed = _applyLiveScoreToHistory(score, gain);
      if (changed && mounted) {
        setState(() {});
      }
    } else {
      _pendingHistoryScore = score;
      _pendingHistoryGain = gain;
    }
  }

  Map<String, List<ActivityInstanceRecord>> get _bucketedItems {
    final currentInstancesHash =
        QueueBucketService.calculateInstancesHash(_instances);
    final currentCategoriesHash =
        QueueBucketService.calculateCategoriesHash(_categories);

    final cacheInvalid = _cachedBucketedItems == null ||
        currentInstancesHash != _instancesHashCode ||
        currentCategoriesHash != _categoriesHashCode ||
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
    return QueueUIBuilders.buildProgressCharts(
      context: context,
      dailyPercentage: _dailyPercentage,
      dailyTarget: _dailyTarget,
      pointsEarned: _pointsEarned,
      miniGraphHistory: miniGraphHistory,
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
          await _refreshLiveCumulativeScore();
        }
      },
      child: CustomScrollView(
        controller: _scrollController,
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
    setState(() {
      QueueInstanceHandlers.updateInstanceInLocalState(
        _instances,
        updatedInstance,
      );
      _cachedBucketedItems = null;
    });
    _calculateProgress(optimistic: true);
    _calculateProgress(optimistic: false);
  }

  void _removeInstanceFromLocalState(
      ActivityInstanceRecord deletedInstance) async {
    setState(() {
      QueueInstanceHandlers.removeInstanceFromLocalState(
        _instances,
        deletedInstance,
      );
      _cachedBucketedItems = null;
    });
    _calculateProgress(optimistic: true);
    _calculateProgress(optimistic: false);
  }

  void _handleInstanceCreated(ActivityInstanceRecord instance) {
    setState(() {
      QueueInstanceHandlers.handleInstanceCreated(_instances, instance);
      _cachedBucketedItems = null;
    });
    _calculateProgress(optimistic: true);
    _calculateProgress(optimistic: false);
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

    setState(() {
      QueueInstanceHandlers.handleInstanceUpdated(
        _instances,
        param,
        _reorderingInstanceIds,
        _optimisticOperations,
      );
      _cachedBucketedItems = null;
    });
    bool isOptimistic = false;
    if (param is Map) {
      isOptimistic = param['isOptimistic'] as bool? ?? false;
    }
    _calculateProgress(optimistic: true);
    if (!isOptimistic) {
      _calculateProgress(optimistic: false);
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
        setState(() {
          QueueInstanceHandlers.handleRollback(
            _instances,
            param,
            _optimisticOperations,
          );
          _cachedBucketedItems = null;
        });
        if (originalInstance == null && instanceId != null) {
          _revertOptimisticUpdate(instanceId);
        } else {
          _calculateProgress(optimistic: false);
        }
      }
    }
  }

  Future<void> _revertOptimisticUpdate(String instanceId) async {
    final updatedInstance =
        await QueueInstanceHandlers.revertOptimisticUpdate(instanceId);
    if (updatedInstance != null) {
      setState(() {
        final index =
            _instances.indexWhere((inst) => inst.reference.id == instanceId);
        if (index != -1) {
          _instances[index] = updatedInstance;
          _cachedBucketedItems = null;
        }
      });
      _calculateProgress(optimistic: false);
    }
  }

  void _handleInstanceDeleted(ActivityInstanceRecord instance) {
    setState(() {
      QueueInstanceHandlers.handleInstanceDeleted(_instances, instance);
      _cachedBucketedItems = null;
    });
    _calculateProgress(optimistic: true);
    _calculateProgress(optimistic: false);
  }

  Future<void> _silentRefreshInstances() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;
      final result =
          await QueueDataService.silentRefreshInstances(userId: userId);
      if (mounted) {
        setState(() {
          _instances = result.instances;
          _categories = result.categories;
          _cachedBucketedItems = null;
        });
        _calculateProgress();
      }
    } catch (e) {}
  }

  Future<void> _refreshWithoutFlicker() async {
    await _silentRefreshInstances();
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

      final result = await QueueReorderHandler.handleReorder(
        items: items,
        oldIndex: oldIndex,
        newIndex: newIndex,
        allInstances: _instances,
        reorderingInstanceIds: _reorderingInstanceIds,
        isSortActive: _currentSort.isActive,
        sectionKey: sectionKey,
      );

      if (result.success && result.updatedInstances != null) {
        if (result.reorderingIds != null) {
          _reorderingInstanceIds.addAll(result.reorderingIds!);
        }
        _cachedBucketedItems = null;
        if (mounted) {
          setState(() {
            _instances.clear();
            _instances.addAll(result.updatedInstances!);
          });
        }
        if (result.reorderingIds != null) {
          _reorderingInstanceIds.removeAll(result.reorderingIds!);
        }
      } else {
        if (result.reorderingIds != null) {
          _reorderingInstanceIds.removeAll(result.reorderingIds!);
        }
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Error reordering items: ${result.error ?? 'Unknown error'}')),
          );
        }
      }
    } catch (e) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reordering items: $e')),
        );
      }
    }
  }
}
