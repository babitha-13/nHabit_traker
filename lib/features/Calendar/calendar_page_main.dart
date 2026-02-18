import 'dart:async';
import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/features/Calendar/calender_page_ui.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_models.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_formatting_utils.dart';
import 'package:habit_tracker/features/Calendar/Time_breakdown_chart/time_breakdown_chart.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/features/Settings/default_time_estimates_service.dart';
import 'package:habit_tracker/services/Activtity/activity_update_broadcast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:habit_tracker/features/Calendar/Conflicting_events_overlap/calendar_overlap_calculator.dart';
import 'package:habit_tracker/features/Calendar/Time_breakdown_chart/time_breakdown_calculator.dart';
import 'package:habit_tracker/features/Calendar/calendar_event_service.dart';
import 'package:habit_tracker/features/Calendar/Event_tiles/calendar_event_tile.dart';
import 'package:habit_tracker/features/Calendar/Conflicting_events_overlap/calendar_overlap_ui.dart';
import 'package:habit_tracker/features/Calendar/calendar_time_entry_modal.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/services/diagnostics/calendar_optimistic_trace_logger.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final EventController _completedEventController = EventController();
  final EventController _plannedEventController = EventController();
  double _currentScrollOffset = 0.0;
  double _initialScrollOffset = 0.0;
  double _calendarViewportHeight = 0.0;
  DateTime _selectedDate = DateService.currentDate;
  bool _showPlanned = true;
  static const double _minVerticalZoom = 0.5;
  static const double _maxVerticalZoom = 3.0;
  static const double _zoomStep = 0.5;
  double _verticalZoom = 1.0;
  static const double _baseHeightPerMinute = 2.0;
  List<CalendarEventData> _sortedCompletedEvents = [];
  List<CalendarEventData> _sortedPlannedEvents = [];
  int _plannedOverlapPairCount = 0;
  final Set<String> _plannedOverlappedEventIds = {};
  List<PlannedOverlapGroup> _plannedOverlapGroups = const [];
  GlobalKey<DayViewState> _dayViewKey = GlobalKey<DayViewState>();
  Offset? _lastTapDownPosition;
  double? _pendingScrollSyncOffset;
  bool _pendingScrollSyncScheduled = false;
  double? _latestZoomScrollTarget;
  bool _zoomScrollCorrectionScheduled = false;
  int _defaultDurationMinutes = 10;
  final Map<String, String> _optimisticOperations = {};
  final Map<String, ActivityInstanceRecord> _optimisticInstances = {};
  bool _isLoadingEvents = false;
  bool _isFetching = false;
  bool _pendingRefresh = false;
  Timer? _loadingStateSafetyTimer;
  Timer? _observerRefreshDebounceTimer;
  DateTime? _lastRefreshStartedAt;
  static const Duration _observerRefreshDebounce = Duration(milliseconds: 600);
  static const Duration _observerRefreshMinInterval = Duration(seconds: 2);
  static const int _staleInstanceEventToleranceMs = 1500;
  Map<String, List<String>> _routineItemMap = {};
  final Map<String, int> _latestInstanceUpdateMsById = {};

  CalendarEventTileBuilder get _eventTileBuilder {
    return CalendarEventTileBuilder(
      calculateHeightPerMinute: _calculateHeightPerMinute,
      plannedOverlappedEventIds: _plannedOverlappedEventIds,
      onEditEntry: (metadata) => _showEditEntryDialog(metadata: metadata),
    );
  }

  @override
  void initState() {
    super.initState();
    _calculateInitialScrollOffset();
    _initializeTabState();
    _loadDefaultDuration();
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceUpdated,
      _handleInstanceUpdated,
    );
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceCreated,
      _handleInstanceCreated,
    );
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceDeleted,
      _handleInstanceDeleted,
    );
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        _scheduleObserverRefresh();
      }
    });
    NotificationCenter.addObserver(this, 'routineUpdated', (param) {
      if (mounted) {
        _scheduleObserverRefresh();
      }
    });
    NotificationCenter.addObserver(
      this,
      ActivityTemplateEvents.templateUpdated,
      (param) {
        if (mounted) {
          _scheduleObserverRefresh();
        }
      },
    );
    NotificationCenter.addObserver(this, 'instanceUpdateRollback', (param) {
      _handleRollback(param);
    });
  }

  Future<void> _loadDefaultDuration() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isNotEmpty) {
        final duration =
            await TimeLoggingPreferencesService.getDefaultDurationMinutes(
                userId);
        if (mounted) {
          setState(() {
            _defaultDurationMinutes = duration;
          });
        }
      }
    } catch (e) {}
  }

  Future<void> _initializeTabState() async {
    final savedShowPlanned = await _loadTabState();
    if (mounted) {
      setState(() {
        _showPlanned = savedShowPlanned;
      });
      _loadEvents();
    }
  }

  Future<bool> _loadTabState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('calendar_show_planned') ?? true; // Default to Planned
  }

  Future<void> _saveTabState(bool showPlanned) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('calendar_show_planned', showPlanned);
  }

  void _calculateInitialScrollOffset() {
    final now = DateService.currentDate;
    final minutes = now.hour * 60 + now.minute;
    final startMinutes = (minutes - 60).clamp(0, 24 * 60).toDouble();
    _initialScrollOffset = startMinutes * _calculateHeightPerMinute();
    _currentScrollOffset = _initialScrollOffset;
  }

  void _showManualEntryDialog({DateTime? startTime, DateTime? endTime}) {
    CalendarModals.showManualEntryDialog(
      context: context,
      selectedDate: _selectedDate,
      startTime: startTime,
      endTime: endTime,
      onPreviewChange: _handlePreviewChange,
      onSave: () {
        _loadEvents();
      },
      onRemovePreview: _removePreviewEvent,
    );
  }

  TimeBreakdownData _calculateTimeBreakdown() {
    return CalendarTimeBreakdownCalculator.calculateTimeBreakdown(
        _sortedCompletedEvents);
  }

  void _showTimeBreakdownChart() {
    final breakdownData = _calculateTimeBreakdown();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: FlutterFlowTheme.of(context)
                            .alternate
                            .withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Time Breakdown',
                        style: FlutterFlowTheme.of(context).titleLarge.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: TimeBreakdownChartWidget(
                    breakdownData: breakdownData,
                    selectedDate: _selectedDate,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditEntryDialog({required CalendarEventMetadata metadata}) async {
    await CalendarModals.showEditEntryDialog(
      context: context,
      metadata: metadata,
      selectedDate: _selectedDate,
      onPreviewChange: _handlePreviewChange,
      onSave: () {
        _loadEvents();
      },
      onRemovePreview: _removePreviewEvent,
    );
  }

  void _handlePreviewChange(
      DateTime start, DateTime end, String type, Color? color) {
    _removePreviewEvent();
    CalendarModals.handlePreviewChange(
      start: start,
      end: end,
      type: type,
      color: color,
      selectedDate: _selectedDate,
      defaultDurationMinutes: _defaultDurationMinutes,
      plannedEventController: _plannedEventController,
      dayViewKey: _dayViewKey,
      currentScrollOffset: _currentScrollOffset,
      calculateHeightPerMinute: _calculateHeightPerMinute,
      context: context,
    );
  }

  void _removePreviewEvent() {
    CalendarModals.removePreviewEvent(_plannedEventController);
  }

  void _scheduleObserverRefresh({bool force = false}) {
    if (!mounted) return;

    _observerRefreshDebounceTimer?.cancel();
    final now = DateService.currentDate;
    Duration delay = _observerRefreshDebounce;

    if (!force && _lastRefreshStartedAt != null) {
      final elapsed = now.difference(_lastRefreshStartedAt!);
      if (elapsed < _observerRefreshMinInterval) {
        final remaining = _observerRefreshMinInterval - elapsed;
        if (remaining > delay) {
          delay = remaining;
        }
      }
    }

    _observerRefreshDebounceTimer = Timer(delay, () {
      if (!mounted) return;
      _traceCalendarFlow(
        'observer_refresh_fire',
        extras: <String, Object?>{
          'force': force,
          'delayMs': delay.inMilliseconds,
          'isFetching': _isFetching,
          'pendingRefresh': _pendingRefresh,
        },
      );
      _loadEvents(isSilent: true);
    });
    _traceCalendarFlow(
      'observer_refresh_scheduled',
      extras: <String, Object?>{
        'force': force,
        'delayMs': delay.inMilliseconds,
        'isFetching': _isFetching,
        'pendingRefresh': _pendingRefresh,
      },
    );
  }

  Color? _findCurrentColorForInstance(String instanceId) {
    for (final event in _sortedCompletedEvents) {
      final metadata = CalendarEventMetadata.fromMap(event.event);
      if (metadata?.instanceId == instanceId) {
        return event.color;
      }
    }
    for (final event in _sortedPlannedEvents) {
      final metadata = CalendarEventMetadata.fromMap(event.event);
      if (metadata?.instanceId == instanceId) {
        return event.color;
      }
    }
    return null;
  }

  DateTime get _selectedDateOnly => DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );

  void _traceCalendarFlow(
    String stage, {
    String? operationId,
    String? instanceId,
    ActivityInstanceRecord? instance,
    Map<String, Object?> extras = const <String, Object?>{},
  }) {
    CalendarOptimisticTraceLogger.log(
      stage,
      source: 'calendar_page_main',
      operationId: operationId,
      instanceId: instanceId,
      instance: instance,
      extras: <String, Object?>{
        'selectedDate': _selectedDateOnly.toIso8601String(),
        'showPlanned': _showPlanned,
        'optimisticInstances': _optimisticInstances.length,
        ...extras,
      },
    );
  }

  bool _hasSessionOnSelectedDate(ActivityInstanceRecord instance) {
    if (instance.timeLogSessions.isEmpty) return false;
    final selectedDateOnly = _selectedDateOnly;
    for (final session in instance.timeLogSessions) {
      final sessionStart = session['startTime'];
      if (sessionStart is! DateTime) {
        continue;
      }
      final sessionDate = DateTime(
        sessionStart.year,
        sessionStart.month,
        sessionStart.day,
      );
      if (sessionDate.isAtSameMomentAs(selectedDateOnly)) {
        return true;
      }
    }
    return false;
  }

  bool _shouldIgnoreAsStaleInstanceEvent(ActivityInstanceRecord instance) {
    final incomingMs = instance.lastUpdated?.millisecondsSinceEpoch;
    if (incomingMs == null || incomingMs <= 0) {
      return false;
    }
    final instanceId = instance.reference.id;
    final knownMs = _latestInstanceUpdateMsById[instanceId];
    if (knownMs != null &&
        incomingMs + _staleInstanceEventToleranceMs < knownMs) {
      _traceCalendarFlow(
        'instance_event_stale_ignored',
        instance: instance,
        extras: <String, Object?>{
          'incomingMs': incomingMs,
          'knownMs': knownMs,
          'toleranceMs': _staleInstanceEventToleranceMs,
        },
      );
      return true;
    }
    if (knownMs == null || incomingMs > knownMs) {
      _latestInstanceUpdateMsById[instanceId] = incomingMs;
      _traceCalendarFlow(
        'instance_event_version_advanced',
        instance: instance,
        extras: <String, Object?>{
          'incomingMs': incomingMs,
          'previousKnownMs': knownMs,
        },
      );
    }
    return false;
  }

  void _handleInstanceCreated(dynamic param) {
    if (!mounted) return;
    ActivityInstanceRecord instance;
    bool isOptimistic = false;
    String? operationId;

    if (param is Map) {
      instance = param['instance'] as ActivityInstanceRecord;
      isOptimistic = param['isOptimistic'] as bool? ?? false;
      operationId = param['operationId'] as String?;
    } else if (param is ActivityInstanceRecord) {
      instance = param;
    } else {
      return;
    }
    _traceCalendarFlow(
      'observer_instance_created_received',
      operationId: operationId,
      instance: instance,
      extras: <String, Object?>{
        'isOptimistic': isOptimistic,
      },
    );
    if (isOptimistic) {
      _shouldIgnoreAsStaleInstanceEvent(instance);
    } else if (_shouldIgnoreAsStaleInstanceEvent(instance)) {
      if (operationId != null) {
        _optimisticOperations.remove(operationId);
      }
      _traceCalendarFlow(
        'observer_instance_created_dropped_stale',
        operationId: operationId,
        instance: instance,
      );
      return;
    }
    final selectedDateOnly = _selectedDateOnly;
    final instanceId = instance.reference.id;
    final incomingHasSelectedSessions = _hasSessionOnSelectedDate(instance);
    bool affectsSelectedDate = false;
    bool affectsPlannedSection = false;

    if (incomingHasSelectedSessions) {
      affectsSelectedDate = true;
    }

    if (instance.dueDate != null &&
        instance.dueTime != null &&
        instance.dueTime!.isNotEmpty) {
      final dueDateOnly = DateTime(
        instance.dueDate!.year,
        instance.dueDate!.month,
        instance.dueDate!.day,
      );
      if (dueDateOnly.isAtSameMomentAs(selectedDateOnly)) {
        affectsPlannedSection = true;
        affectsSelectedDate = true;
      }
    }
    if (instance.belongsToDate != null &&
        !affectsPlannedSection &&
        instance.dueTime != null &&
        instance.dueTime!.isNotEmpty) {
      final belongsToDateOnly = DateTime(
        instance.belongsToDate!.year,
        instance.belongsToDate!.month,
        instance.belongsToDate!.day,
      );
      if (belongsToDateOnly.isAtSameMomentAs(selectedDateOnly)) {
        affectsPlannedSection = true;
        affectsSelectedDate = true;
      }
    }
    _traceCalendarFlow(
      'observer_instance_created_classified',
      operationId: operationId,
      instance: instance,
      extras: <String, Object?>{
        'affectsSelectedDate': affectsSelectedDate,
        'affectsPlannedSection': affectsPlannedSection,
        'incomingHasSelectedSessions': incomingHasSelectedSessions,
      },
    );

    final existingColorHint = _findCurrentColorForInstance(instanceId);

    if (isOptimistic) {
      if (operationId != null) {
        _optimisticOperations[operationId] = instanceId;
      }
      // Add to optimistic instances if it affects planned section OR has time log sessions on selected date
      if (affectsPlannedSection || affectsSelectedDate) {
        _optimisticInstances[instanceId] = instance;
      }
      if (affectsPlannedSection) {
        _applyOptimisticPlannedPatch(instance);
      }
      if (affectsSelectedDate) {
        _applyOptimisticCompletedPatch(
          instance,
          fallbackColor: existingColorHint,
        );
        _scheduleObserverRefresh();
      }
      _traceCalendarFlow(
        'observer_instance_created_applied_optimistic',
        operationId: operationId,
        instance: instance,
        extras: <String, Object?>{
          'affectsSelectedDate': affectsSelectedDate,
          'affectsPlannedSection': affectsPlannedSection,
          'trackedOperations': _optimisticOperations.length,
        },
      );
    } else {
      if (operationId != null) {
        _optimisticOperations.remove(operationId);
      }
      _optimisticInstances.remove(instanceId);
      if (affectsPlannedSection) {
        _applyOptimisticPlannedPatch(instance);
      }
      if (affectsSelectedDate) {
        _applyOptimisticCompletedPatch(
          instance,
          fallbackColor: existingColorHint,
        );
      }
      if (affectsPlannedSection || affectsSelectedDate) {
        _scheduleObserverRefresh();
      }
      _traceCalendarFlow(
        'observer_instance_created_applied_reconciled',
        operationId: operationId,
        instance: instance,
        extras: <String, Object?>{
          'affectsSelectedDate': affectsSelectedDate,
          'affectsPlannedSection': affectsPlannedSection,
          'trackedOperations': _optimisticOperations.length,
        },
      );
    }
  }

  void _handleInstanceUpdated(dynamic param) {
    if (!mounted) return;
    ActivityInstanceRecord instance;
    bool isOptimistic = false;
    String? operationId;

    if (param is Map) {
      instance = param['instance'] as ActivityInstanceRecord;
      isOptimistic = param['isOptimistic'] as bool? ?? false;
      operationId = param['operationId'] as String?;
    } else if (param is ActivityInstanceRecord) {
      instance = param;
    } else {
      return;
    }
    _traceCalendarFlow(
      'observer_instance_updated_received',
      operationId: operationId,
      instance: instance,
      extras: <String, Object?>{
        'isOptimistic': isOptimistic,
      },
    );
    if (isOptimistic) {
      _shouldIgnoreAsStaleInstanceEvent(instance);
    } else if (_shouldIgnoreAsStaleInstanceEvent(instance)) {
      if (operationId != null) {
        _optimisticOperations.remove(operationId);
      }
      _traceCalendarFlow(
        'observer_instance_updated_dropped_stale',
        operationId: operationId,
        instance: instance,
      );
      return;
    }

    final selectedDateOnly = _selectedDateOnly;
    final instanceId = instance.reference.id;
    final incomingHasSelectedSessions = _hasSessionOnSelectedDate(instance);
    bool affectsSelectedDate = false;
    bool affectsPlannedSection = false;

    // Check if the instance was *previously* visible on this date
    // This is crucial for deletion/uncompletion where the new state has no logs
    // We check if we have an existing optimistic version or a completed event for this instance
    bool wasVisibleOnDate = _optimisticInstances.containsKey(instanceId) ||
        _sortedCompletedEvents.any((e) {
          final metadata = CalendarEventMetadata.fromMap(e.event);
          return metadata?.instanceId == instanceId;
        });

    if (incomingHasSelectedSessions) {
      affectsSelectedDate = true;
    } else if (wasVisibleOnDate) {
      // If it was visible but now has no logs (e.g. deleted/uncompleted), it definitely affects this date
      affectsSelectedDate = true;
    }

    if (instance.belongsToDate != null) {
      final belongsToDateOnly = DateTime(
        instance.belongsToDate!.year,
        instance.belongsToDate!.month,
        instance.belongsToDate!.day,
      );
      if (belongsToDateOnly.isAtSameMomentAs(selectedDateOnly)) {
        affectsSelectedDate = true;
      }
    }
    if (instance.dueDate != null &&
        instance.dueTime != null &&
        instance.dueTime!.isNotEmpty) {
      final dueDateOnly = DateTime(
        instance.dueDate!.year,
        instance.dueDate!.month,
        instance.dueDate!.day,
      );
      if (dueDateOnly.isAtSameMomentAs(selectedDateOnly)) {
        affectsPlannedSection = true;
        affectsSelectedDate = true;
      }
    }
    _traceCalendarFlow(
      'observer_instance_updated_classified',
      operationId: operationId,
      instance: instance,
      extras: <String, Object?>{
        'affectsSelectedDate': affectsSelectedDate,
        'affectsPlannedSection': affectsPlannedSection,
        'incomingHasSelectedSessions': incomingHasSelectedSessions,
        'wasVisibleOnDate': wasVisibleOnDate,
      },
    );

    final existingColorHint = _findCurrentColorForInstance(instanceId);
    if (isOptimistic) {
      if (operationId != null) {
        _optimisticOperations[operationId] = instanceId;
      }
      // Add to optimistic instances if it affects planned section OR has time log sessions on selected date
      if (affectsPlannedSection || affectsSelectedDate) {
        // ALWAYS update optimistic instances if it affects the date, even if logs are empty.
        // This ensures that "cleared logs" state overrides any stale backend data during _loadEvents.
        _optimisticInstances[instanceId] = instance;
      }
      if (affectsPlannedSection) {
        _applyOptimisticPlannedPatch(instance);
      }
      if (affectsSelectedDate) {
        _applyOptimisticCompletedPatch(
          instance,
          fallbackColor: existingColorHint,
        );
        _scheduleObserverRefresh();
      }
      _traceCalendarFlow(
        'observer_instance_updated_applied_optimistic',
        operationId: operationId,
        instance: instance,
        extras: <String, Object?>{
          'affectsSelectedDate': affectsSelectedDate,
          'affectsPlannedSection': affectsPlannedSection,
          'trackedOperations': _optimisticOperations.length,
        },
      );
    } else {
      if (operationId != null) {
        _optimisticOperations.remove(operationId);
      }
      _optimisticInstances.remove(instanceId);
      if (affectsPlannedSection) {
        _applyOptimisticPlannedPatch(instance);
      }
      if (affectsSelectedDate) {
        _applyOptimisticCompletedPatch(
          instance,
          fallbackColor: existingColorHint,
        );
      }
      if (affectsPlannedSection || affectsSelectedDate) {
        _scheduleObserverRefresh();
      }
      _traceCalendarFlow(
        'observer_instance_updated_applied_reconciled',
        operationId: operationId,
        instance: instance,
        extras: <String, Object?>{
          'affectsSelectedDate': affectsSelectedDate,
          'affectsPlannedSection': affectsPlannedSection,
          'trackedOperations': _optimisticOperations.length,
        },
      );
    }
  }

  void _handleInstanceDeleted(dynamic param) {
    if (!mounted) return;
    ActivityInstanceRecord instance;
    if (param is ActivityInstanceRecord) {
      instance = param;
    } else {
      return;
    }
    _traceCalendarFlow(
      'observer_instance_deleted_received',
      instance: instance,
    );
    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    final instanceId = instance.reference.id;
    _optimisticInstances.remove(instanceId);
    _latestInstanceUpdateMsById.remove(instanceId);
    bool affectsSelectedDate = false;
    bool affectsPlannedSection = false;
    if (instance.dueDate != null &&
        instance.dueTime != null &&
        instance.dueTime!.isNotEmpty) {
      final dueDateOnly = DateTime(
        instance.dueDate!.year,
        instance.dueDate!.month,
        instance.dueDate!.day,
      );
      if (dueDateOnly.isAtSameMomentAs(selectedDateOnly)) {
        affectsPlannedSection = true;
        affectsSelectedDate = true;
      }
    }
    if (instance.timeLogSessions.isNotEmpty) {
      for (final session in instance.timeLogSessions) {
        final sessionStart = session['startTime'] as DateTime;
        final sessionDate = DateTime(
          sessionStart.year,
          sessionStart.month,
          sessionStart.day,
        );
        if (sessionDate.isAtSameMomentAs(selectedDateOnly)) {
          affectsSelectedDate = true;
          break;
        }
      }
    }
    if (instance.belongsToDate != null) {
      final belongsToDateOnly = DateTime(
        instance.belongsToDate!.year,
        instance.belongsToDate!.month,
        instance.belongsToDate!.day,
      );
      if (belongsToDateOnly.isAtSameMomentAs(selectedDateOnly)) {
        affectsSelectedDate = true;
      }
    }
    _traceCalendarFlow(
      'observer_instance_deleted_classified',
      instance: instance,
      extras: <String, Object?>{
        'affectsSelectedDate': affectsSelectedDate,
        'affectsPlannedSection': affectsPlannedSection,
      },
    );
    if (affectsPlannedSection) {
      // Find and remove the event(s) for this instance
      CalendarEventData? removedEvent;
      _plannedEventController.removeWhere((e) {
        final metadata = CalendarEventMetadata.fromMap(e.event);
        if (metadata?.instanceId == instanceId) {
          removedEvent = e;
          return true;
        }
        return false;
      });

      final removedEventId = removedEvent != null
          ? CalendarOverlapCalculator.stableEventId(removedEvent!)
          : null;
      _sortedPlannedEvents.removeWhere((e) {
        final metadata = CalendarEventMetadata.fromMap(e.event);
        return metadata?.instanceId == instanceId;
      });

      // Use incremental overlap update if possible
      PlannedOverlapInfo overlapInfo;
      if (removedEventId != null && _plannedOverlapPairCount > 0) {
        overlapInfo = CalendarOverlapCalculator.updateOverlapsAfterRemoval(
          removedEventId,
          _sortedPlannedEvents,
          PlannedOverlapInfo(
            pairCount: _plannedOverlapPairCount,
            overlappedIds: _plannedOverlappedEventIds,
            groups: _plannedOverlapGroups,
          ),
          routineItemMap: _routineItemMap,
        );
      } else {
        // Fallback to full recompute
        overlapInfo = _computePlannedOverlaps(_sortedPlannedEvents);
      }

      _plannedOverlapPairCount = overlapInfo.pairCount;
      _plannedOverlappedEventIds
        ..clear()
        ..addAll(overlapInfo.overlappedIds);
      _plannedOverlapGroups = overlapInfo.groups;

      if (mounted) setState(() {});
      _traceCalendarFlow(
        'observer_instance_deleted_planned_removed',
        instance: instance,
        extras: <String, Object?>{
          'plannedCount': _sortedPlannedEvents.length,
          'overlapPairs': _plannedOverlapPairCount,
        },
      );
    }
    if (affectsSelectedDate && instance.timeLogSessions.isNotEmpty) {
      _scheduleObserverRefresh();
    }
  }

  void _handleRollback(dynamic param) {
    if (!mounted) return;
    if (param is Map) {
      final operationId = param['operationId'] as String?;
      final instanceId = param['instanceId'] as String?;
      _traceCalendarFlow(
        'observer_rollback_received',
        operationId: operationId,
        instanceId: instanceId,
      );
      if (operationId != null &&
          _optimisticOperations.containsKey(operationId)) {
        setState(() {
          _optimisticOperations.remove(operationId);
          if (instanceId != null) {
            _optimisticInstances.remove(instanceId);
            _latestInstanceUpdateMsById.remove(instanceId);
            _plannedEventController.removeWhere((e) {
              final metadata = CalendarEventMetadata.fromMap(e.event);
              return metadata?.instanceId == instanceId;
            });
            _sortedPlannedEvents.removeWhere((e) {
              final metadata = CalendarEventMetadata.fromMap(e.event);
              return metadata?.instanceId == instanceId;
            });

            // Use incremental overlap update if possible
            if (_sortedPlannedEvents.isNotEmpty) {
              final removedEventId = instanceId;
              final overlapInfo =
                  CalendarOverlapCalculator.updateOverlapsAfterRemoval(
                removedEventId,
                _sortedPlannedEvents,
                PlannedOverlapInfo(
                  pairCount: _plannedOverlapPairCount,
                  overlappedIds: _plannedOverlappedEventIds,
                  groups: _plannedOverlapGroups,
                ),
                routineItemMap: _routineItemMap,
              );
              _plannedOverlapPairCount = overlapInfo.pairCount;
              _plannedOverlappedEventIds
                ..clear()
                ..addAll(overlapInfo.overlappedIds);
              _plannedOverlapGroups = overlapInfo.groups;
            } else {
              _plannedOverlapPairCount = 0;
              _plannedOverlappedEventIds.clear();
              _plannedOverlapGroups = [];
            }
          }
        });
        _scheduleObserverRefresh(force: true);
        _traceCalendarFlow(
          'observer_rollback_applied',
          operationId: operationId,
          instanceId: instanceId,
          extras: <String, Object?>{
            'trackedOperations': _optimisticOperations.length,
            'optimisticInstances': _optimisticInstances.length,
          },
        );
      }
    }
  }

  void _applyOptimisticCompletedPatch(
    ActivityInstanceRecord instance, {
    Color? fallbackColor,
  }) {
    if (!mounted) return;

    final instanceId = instance.reference.id;
    final beforeCount = _sortedCompletedEvents.length;
    Color? previousColor = fallbackColor;
    if (previousColor == null) {
      for (final event in _sortedCompletedEvents) {
        final metadata = CalendarEventMetadata.fromMap(event.event);
        if (metadata?.instanceId == instanceId) {
          previousColor = event.color;
          break;
        }
      }
    }
    if (previousColor == null) {
      for (final event in _sortedPlannedEvents) {
        final metadata = CalendarEventMetadata.fromMap(event.event);
        if (metadata?.instanceId == instanceId) {
          previousColor = event.color;
          break;
        }
      }
    }

    // Remove old rendered sessions for this instance first.
    _sortedCompletedEvents.removeWhere((event) {
      final metadata = CalendarEventMetadata.fromMap(event.event);
      return metadata?.instanceId == instanceId;
    });
    final removedCount = beforeCount - _sortedCompletedEvents.length;

    final optimisticEvents = _buildCompletedEventsForSelectedDate(
      instance,
      fallbackColor: previousColor,
    );
    _sortedCompletedEvents.addAll(optimisticEvents);
    _sortedCompletedEvents = _cascadeCompletedEvents(_sortedCompletedEvents);

    _completedEventController.removeWhere((e) => true);
    _completedEventController.addAll(_sortedCompletedEvents);

    if (mounted) {
      setState(() {});
    }
    _traceCalendarFlow(
      'apply_completed_patch',
      instance: instance,
      extras: <String, Object?>{
        'removedEvents': removedCount,
        'addedEvents': optimisticEvents.length,
        'totalCompletedEvents': _sortedCompletedEvents.length,
      },
    );
  }

  List<CalendarEventData> _buildCompletedEventsForSelectedDate(
      ActivityInstanceRecord instance,
      {Color? fallbackColor}) {
    final events = <CalendarEventData>[];

    if (instance.timeLogSessions.isEmpty) {
      return events;
    }

    Color categoryColor = fallbackColor ?? Colors.blue;
    if (instance.templateCategoryColor.isNotEmpty) {
      try {
        categoryColor = _parseColor(instance.templateCategoryColor);
      } catch (_) {}
    }

    final selectedDateStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      0,
      0,
      0,
    );
    final selectedDateEnd = selectedDateStart.add(const Duration(days: 1));

    for (int i = 0; i < instance.timeLogSessions.length; i++) {
      final session = instance.timeLogSessions[i];
      final sessionStart = session['startTime'] as DateTime?;
      final sessionEnd = session['endTime'] as DateTime?;
      if (sessionStart == null || sessionEnd == null) {
        continue;
      }

      var validStartTime = sessionStart;
      var validEndTime = sessionEnd;
      if (validEndTime.difference(validStartTime).inSeconds < 60) {
        validEndTime = validStartTime.add(const Duration(minutes: 1));
      }

      if (validStartTime.isBefore(selectedDateStart)) {
        validStartTime = selectedDateStart;
      } else if (!validStartTime.isBefore(selectedDateEnd)) {
        continue;
      }

      if (validEndTime.isAfter(selectedDateEnd)) {
        validEndTime = selectedDateEnd.subtract(const Duration(seconds: 1));
      }

      if (!validEndTime.isAfter(validStartTime)) {
        validEndTime = validStartTime.add(const Duration(minutes: 1));
      }

      final startDateOnly = DateTime(
        validStartTime.year,
        validStartTime.month,
        validStartTime.day,
      );
      final selectedDateOnly = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      if (!startDateOnly.isAtSameMomentAs(selectedDateOnly)) {
        continue;
      }

      final metadata = CalendarEventMetadata(
        instanceId: instance.reference.id,
        sessionIndex: i,
        sessionStartEpochMs: sessionStart.millisecondsSinceEpoch,
        sessionEndEpochMs: sessionEnd.millisecondsSinceEpoch,
        activityName: instance.templateName,
        activityType: instance.templateCategoryType,
        templateId: instance.templateId,
        categoryId: instance.templateCategoryId.isNotEmpty
            ? instance.templateCategoryId
            : null,
        categoryName: instance.templateCategoryName.isNotEmpty
            ? instance.templateCategoryName
            : null,
        categoryColorHex: instance.templateCategoryColor.isNotEmpty
            ? instance.templateCategoryColor
            : null,
      );

      final prefix = instance.status == 'completed' ? '✓ ' : '';
      events.add(
        CalendarEventData(
          date: _selectedDate,
          startTime: validStartTime,
          endTime: validEndTime,
          title: '$prefix${instance.templateName}',
          color: categoryColor,
          description:
              'Session: ${_formatDuration(validEndTime.difference(validStartTime))}',
          event: metadata.toMap(),
        ),
      );
    }

    return events;
  }

  List<CalendarEventData> _cascadeCompletedEvents(
    List<CalendarEventData> sourceEvents,
  ) {
    final events = List<CalendarEventData>.from(sourceEvents)
        .where((e) => e.startTime != null && e.endTime != null)
        .toList();

    events.sort((a, b) {
      final endCompare = b.endTime!.compareTo(a.endTime!);
      if (endCompare != 0) return endCompare;
      return b.startTime!.compareTo(a.startTime!);
    });

    DateTime? earliestStartTime;
    final cascaded = <CalendarEventData>[];
    final selectedDayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final selectedDayEnd = selectedDayStart.add(const Duration(days: 1));
    for (final event in events) {
      DateTime startTime = event.startTime!;
      DateTime endTime = event.endTime!;
      final duration = endTime.difference(startTime);

      if (earliestStartTime != null && endTime.isAfter(earliestStartTime)) {
        endTime = earliestStartTime;
        startTime = endTime.subtract(duration);
      }

      if (startTime.isBefore(selectedDayStart)) {
        startTime = selectedDayStart;
      }
      if (!endTime.isAfter(startTime)) {
        endTime = startTime.add(const Duration(minutes: 1));
      }
      if (!endTime.isBefore(selectedDayEnd)) {
        endTime = selectedDayEnd.subtract(const Duration(seconds: 1));
      }
      if (!endTime.isAfter(startTime)) {
        continue;
      }

      if (earliestStartTime == null || startTime.isBefore(earliestStartTime)) {
        earliestStartTime = startTime;
      }

      cascaded.add(
        CalendarEventData(
          date: _selectedDate,
          startTime: startTime,
          endTime: endTime,
          title: event.title,
          color: event.color,
          description: event.description,
          event: event.event,
        ),
      );
    }

    cascaded.sort((a, b) => a.startTime!.compareTo(b.startTime!));
    return cascaded;
  }

  void _applyOptimisticPlannedPatch(ActivityInstanceRecord instance) {
    if (!mounted) return;

    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    if (instance.dueDate == null ||
        instance.dueTime == null ||
        instance.dueTime!.isEmpty) {
      _traceCalendarFlow(
        'apply_planned_patch_skipped_missing_due',
        instance: instance,
      );
      return;
    }

    final dueDateOnly = DateTime(
      instance.dueDate!.year,
      instance.dueDate!.month,
      instance.dueDate!.day,
    );

    if (!dueDateOnly.isAtSameMomentAs(selectedDateOnly)) {
      _traceCalendarFlow(
        'apply_planned_patch_skipped_other_date',
        instance: instance,
        extras: <String, Object?>{
          'dueDate': dueDateOnly.toIso8601String(),
        },
      );
      return;
    }

    final instanceId = instance.reference.id;
    final beforePlanned = _sortedPlannedEvents.length;
    _plannedEventController.removeWhere((e) {
      final metadata = CalendarEventMetadata.fromMap(e.event);
      return metadata?.instanceId == instanceId;
    });
    _sortedPlannedEvents.removeWhere((e) {
      final metadata = CalendarEventMetadata.fromMap(e.event);
      return metadata?.instanceId == instanceId;
    });
    final removedCount = beforePlanned - _sortedPlannedEvents.length;
    if (instance.status == 'completed' || instance.status == 'skipped') {
      final overlapInfo = _computePlannedOverlaps(_sortedPlannedEvents);
      _plannedOverlapPairCount = overlapInfo.pairCount;
      _plannedOverlappedEventIds
        ..clear()
        ..addAll(overlapInfo.overlappedIds);
      _plannedOverlapGroups = overlapInfo.groups;
      if (mounted) setState(() {});
      _traceCalendarFlow(
        'apply_planned_patch_removed_due_to_status',
        instance: instance,
        extras: <String, Object?>{
          'removedEvents': removedCount,
          'plannedCount': _sortedPlannedEvents.length,
          'overlapPairs': _plannedOverlapPairCount,
        },
      );
      return;
    }
    try {
      Color categoryColor;
      if (instance.templateCategoryColor.isNotEmpty) {
        try {
          categoryColor = _parseColor(instance.templateCategoryColor);
        } catch (e) {
          categoryColor = Colors.blue;
        }
      } else {
        categoryColor = Colors.blue;
      }
      final startTime = _parseDueTime(instance.dueTime!, _selectedDate);
      int? durationMinutes;
      if (instance.templateTrackingType == 'time' &&
          instance.templateTarget != null) {
        final target = instance.templateTarget;
        if (target is num) {
          durationMinutes = target.toInt();
        } else if (target is String) {
          durationMinutes = int.tryParse(target);
        }
      }
      durationMinutes ??= _defaultDurationMinutes;

      final isDueMarker = durationMinutes <= 0;
      final endTime = isDueMarker
          ? startTime.add(const Duration(minutes: 1))
          : startTime.add(Duration(minutes: durationMinutes));

      final metadata = CalendarEventMetadata(
        instanceId: instanceId,
        sessionIndex: -1,
        activityName: instance.templateName,
        activityType: instance.templateCategoryType,
        templateId: instance.templateId,
        categoryId: instance.templateCategoryId.isNotEmpty
            ? instance.templateCategoryId
            : null,
        categoryName: instance.templateCategoryName.isNotEmpty
            ? instance.templateCategoryName
            : null,
        categoryColorHex: instance.templateCategoryColor.isNotEmpty
            ? instance.templateCategoryColor
            : null,
      );

      final newEvent = CalendarEventData(
        date: _selectedDate,
        startTime: startTime,
        endTime: endTime,
        title: instance.templateName,
        color: categoryColor,
        description: isDueMarker
            ? null
            : _formatDuration(Duration(minutes: durationMinutes)),
        event: {
          ...metadata.toMap(),
          'isDueMarker': isDueMarker,
        },
      );
      _sortedPlannedEvents.add(newEvent);
      _sortedPlannedEvents.sort((a, b) {
        if (a.startTime == null || b.startTime == null) return 0;
        return a.startTime!.compareTo(b.startTime!);
      });
      _plannedEventController.add(newEvent);

      // Use incremental overlap update if possible
      PlannedOverlapInfo overlapInfo;
      if (_plannedOverlapPairCount == 0 && _sortedPlannedEvents.length == 1) {
        // No overlaps possible with just one event
        overlapInfo = const PlannedOverlapInfo(
          pairCount: 0,
          overlappedIds: {},
          groups: [],
        );
      } else {
        overlapInfo = CalendarOverlapCalculator.updateOverlapsAfterAdd(
          newEvent,
          _sortedPlannedEvents,
          PlannedOverlapInfo(
            pairCount: _plannedOverlapPairCount,
            overlappedIds: _plannedOverlappedEventIds,
            groups: _plannedOverlapGroups,
          ),
          routineItemMap: _routineItemMap,
        );
      }

      _plannedOverlapPairCount = overlapInfo.pairCount;
      _plannedOverlappedEventIds
        ..clear()
        ..addAll(overlapInfo.overlappedIds);
      _plannedOverlapGroups = overlapInfo.groups;
      if (mounted) setState(() {});
      _traceCalendarFlow(
        'apply_planned_patch_upserted',
        instance: instance,
        extras: <String, Object?>{
          'removedEvents': removedCount,
          'plannedCount': _sortedPlannedEvents.length,
          'overlapPairs': _plannedOverlapPairCount,
        },
      );
    } catch (e) {
      _traceCalendarFlow(
        'apply_planned_patch_error',
        instance: instance,
        extras: <String, Object?>{
          'error': e.toString(),
        },
      );
      _scheduleObserverRefresh(force: true);
    }
  }

  /// Helper to get stable event ID for comparison
  String? _getEventId(CalendarEventData event) {
    return CalendarOverlapCalculator.stableEventId(event);
  }

  String _eventIdentityKey(CalendarEventData event) {
    final id = _getEventId(event);
    if (id != null) return id;
    final start = event.startTime?.millisecondsSinceEpoch ?? -1;
    final end = event.endTime?.millisecondsSinceEpoch ?? -1;
    final title = event.title;
    return 'fallback:$start|$end|$title';
  }

  String _eventSignature(CalendarEventData event) {
    final start = event.startTime?.millisecondsSinceEpoch ?? -1;
    final end = event.endTime?.millisecondsSinceEpoch ?? -1;
    final color = event.color.value;
    final title = event.title;
    final description = event.description ?? '';
    return '$start|$end|$color|$title|$description';
  }

  String _eventCompareToken(CalendarEventData event) {
    return '${_eventIdentityKey(event)}|${_eventSignature(event)}';
  }

  /// Remove duplicate logical events while preserving order.
  List<CalendarEventData> _dedupeEvents(List<CalendarEventData> events) {
    if (events.isEmpty) return const [];
    final seen = <String>{};
    final deduped = <CalendarEventData>[];
    for (final event in events) {
      final token = _eventCompareToken(event);
      if (seen.add(token)) {
        deduped.add(event);
      }
    }
    return deduped;
  }

  bool _eventCollectionsEqual(
    Iterable<CalendarEventData> currentEvents,
    List<CalendarEventData> incomingEvents,
  ) {
    final currentTokens = currentEvents.map(_eventCompareToken).toList()
      ..sort();
    final incomingTokens = incomingEvents.map(_eventCompareToken).toList()
      ..sort();
    if (currentTokens.length != incomingTokens.length) return false;
    for (int i = 0; i < currentTokens.length; i++) {
      if (currentTokens[i] != incomingTokens[i]) return false;
    }
    return true;
  }

  /// Efficiently update event controllers by comparing full event snapshots.
  /// This avoids stale/duplicated controller state when IDs repeat.
  void _updateEventControllers(List<CalendarEventData> newCompletedEvents,
      List<CalendarEventData> newPlannedEvents,
      {bool forceReplace = false}) {
    final normalizedCompleted = _dedupeEvents(newCompletedEvents);
    final normalizedPlanned = _dedupeEvents(newPlannedEvents);

    final completedChanged = forceReplace ||
        !_eventCollectionsEqual(
          _completedEventController.allEvents,
          normalizedCompleted,
        );
    final plannedChanged = forceReplace ||
        !_eventCollectionsEqual(
          _plannedEventController.allEvents,
          normalizedPlanned,
        );

    if (completedChanged || plannedChanged) {
      // Batch all controller updates before setState
      if (completedChanged) {
        _completedEventController.removeWhere((e) => true);
        _completedEventController.addAll(normalizedCompleted);
      }

      if (plannedChanged) {
        _plannedEventController.removeWhere((e) => true);
        _plannedEventController.addAll(normalizedPlanned);
      }
    }
  }

  Future<void> _loadEvents({bool isSilent = false}) async {
    // CONCURRENCY CONTROL:
    // If a fetch is already in progress, queue a refresh and return.
    // This ensures we don't have race conditions and we always get the latest state eventually.
    if (_isFetching) {
      _pendingRefresh = true;
      _traceCalendarFlow(
        'load_events_queued_while_fetching',
        extras: <String, Object?>{
          'isSilent': isSilent,
        },
      );
      return;
    }

    _observerRefreshDebounceTimer?.cancel();
    _isFetching = true;
    _lastRefreshStartedAt = DateService.currentDate;
    _traceCalendarFlow(
      'load_events_start',
      extras: <String, Object?>{
        'isSilent': isSilent,
        'trackedOperations': _optimisticOperations.length,
      },
    );

    // Check userId BEFORE setting loading state to avoid showing loader if not authenticated
    final userId = await waitForCurrentUserUid();
    if (userId.isEmpty) {
      _isFetching = false;
      _traceCalendarFlow(
        'load_events_abort_no_user',
        extras: <String, Object?>{
          'isSilent': isSilent,
        },
      );
      return;
    }

    // Set loading state only after confirming user is authenticated
    if (mounted && !isSilent) {
      setState(() {
        _isLoadingEvents = true;
      });

      // Start safety timer to reset loading state if stuck for too long (60 seconds)
      _loadingStateSafetyTimer?.cancel();
      _loadingStateSafetyTimer = Timer(const Duration(seconds: 60), () {
        if (mounted && _isLoadingEvents) {
          print(
              '⚠️ Calendar loading state stuck for 60+ seconds, resetting...');
          setState(() {
            _isLoadingEvents = false;
          });
        }
      });
    }

    try {
      // Add timeout wrapper to prevent indefinite hanging
      final result = await CalendarEventService.loadEvents(
        userId: userId,
        selectedDate: _selectedDate,
        includePlanned: _showPlanned,
        optimisticInstances: _optimisticInstances,
      ).timeout(
        const Duration(
            seconds:
                35), // Slightly longer than the 30s timeout in CalendarEventService
        onTimeout: () {
          throw TimeoutException(
            'Calendar page _loadEvents timed out after 35 seconds',
            const Duration(seconds: 35),
          );
        },
      );

      final normalizedCompleted = _dedupeEvents(result.completedEvents);
      final normalizedPlanned = _dedupeEvents(result.plannedEvents);

      _sortedCompletedEvents = normalizedCompleted;
      _sortedPlannedEvents = normalizedPlanned;
      _routineItemMap = result.routineItemMap;
      final overlapInfo = _computePlannedOverlaps(normalizedPlanned);
      _plannedOverlapPairCount = overlapInfo.pairCount;
      _plannedOverlappedEventIds
        ..clear()
        ..addAll(overlapInfo.overlappedIds);
      _plannedOverlapGroups = overlapInfo.groups;

      // Use optimized update method instead of clear/addAll
      _updateEventControllers(
        normalizedCompleted,
        normalizedPlanned,
        forceReplace: !isSilent,
      );

      if (mounted) setState(() {});
      _traceCalendarFlow(
        'load_events_success',
        extras: <String, Object?>{
          'isSilent': isSilent,
          'completedEvents': normalizedCompleted.length,
          'plannedEvents': normalizedPlanned.length,
          'overlapPairs': _plannedOverlapPairCount,
          'routineCount': _routineItemMap.length,
          'trackedOperations': _optimisticOperations.length,
        },
      );
    } catch (e, stackTrace) {
      // Log errors, especially index errors and timeouts
      print('❌ Calendar page error loading events:');
      print('   Error: $e');
      print('   Stack trace: $stackTrace');
      _traceCalendarFlow(
        'load_events_error',
        extras: <String, Object?>{
          'isSilent': isSilent,
          'error': e.toString(),
        },
      );

      // Check if it's an index error and log it
      logFirestoreIndexError(
        e,
        'Calendar page loadEvents (multiple queries)',
        'activity_instances',
      );

      // DATA SAFETY:
      // Do NOT clear existing events on error. Keep showing what we have.
      // Clearing them causes "disappearing logs" on transient failures.
    } finally {
      _isFetching = false;

      // Cancel safety timer since loading is completing
      _loadingStateSafetyTimer?.cancel();
      _loadingStateSafetyTimer = null;

      // Reset loading state
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
        });
      }

      // Process queued refresh if one came in while we were fetching
      if (_pendingRefresh) {
        _pendingRefresh = false;
        // Recursive call to process the queued update
        // We use isSilent: true because the user has likely already seen the initial loader
        // or this is a background update chain.
        _traceCalendarFlow(
          'load_events_process_queued_refresh',
          extras: <String, Object?>{
            'isSilent': isSilent,
          },
        );
        _loadEvents(isSilent: true);
      } else {
        _traceCalendarFlow(
          'load_events_complete',
          extras: <String, Object?>{
            'isSilent': isSilent,
          },
        );
      }
    }
  }

  DateTime _parseDueTime(String dueTime, DateTime targetDate) {
    return CalendarFormattingUtils.parseDueTime(dueTime, targetDate);
  }

  Color _parseColor(String colorString) {
    return CalendarFormattingUtils.parseColor(colorString);
  }

  PlannedOverlapInfo _computePlannedOverlaps(List<CalendarEventData> planned) {
    return CalendarOverlapCalculator.computePlannedOverlaps(planned,
        routineItemMap: _routineItemMap);
  }

  Widget _buildEventTile(CalendarEventData event, bool isCompleted) {
    return _eventTileBuilder.buildEventTile(
      event,
      isCompleted,
      _sortedCompletedEvents,
      _sortedPlannedEvents,
    );
  }

  Widget _buildOverlapBanner() {
    return CalendarOverlapUI.buildOverlapBanner(
      context: context,
      selectedDate: _selectedDate,
      plannedOverlapPairCount: _plannedOverlapPairCount,
      plannedOverlapGroups: _plannedOverlapGroups,
    );
  }

  String _formatDuration(Duration duration) {
    return CalendarFormattingUtils.formatDuration(duration);
  }

  double _calculateHeightPerMinute() {
    return _baseHeightPerMinute * _verticalZoom;
  }

  double _effectiveScrollOffset() {
    if (_currentScrollOffset.isNaN || _currentScrollOffset.isInfinite) {
      _currentScrollOffset = 0.0;
    }
    return _currentScrollOffset;
  }

  ScrollController? _dayViewScrollController() {
    final state = _dayViewKey.currentState;
    if (state == null) return null;
    final dynamic dayViewState = state;
    try {
      final ScrollController? controller = dayViewState.scrollController;
      if (controller != null) {
        return controller;
      }
    } catch (_) {}
    return null;
  }

  bool _hasLiveDayViewClient() {
    final controller = _dayViewScrollController();
    return controller != null && controller.hasClients;
  }

  double _resolveViewportHeight() {
    if (_calendarViewportHeight > 0) {
      return _calendarViewportHeight;
    }
    final controller = _dayViewScrollController();
    if (controller != null && controller.hasClients) {
      final viewport = controller.position.viewportDimension;
      if (!viewport.isNaN && !viewport.isInfinite && viewport > 0) {
        return viewport;
      }
    }
    return 0.0;
  }

  double _buttonZoomFocalPoint() {
    final viewport = _resolveViewportHeight();
    if (viewport > 0) {
      return viewport / 2;
    }
    return 0.0;
  }

  double _normalizedFocalDy(double focalDy) {
    final viewportHeight = _resolveViewportHeight();
    return viewportHeight > 0
        ? focalDy.clamp(0.0, viewportHeight).toDouble()
        : math.max(0.0, focalDy);
  }

  double _anchorMinuteAtFocalPoint(double focalDy) {
    final heightPerMinute = _calculateHeightPerMinute();
    if (heightPerMinute <= 0) {
      return 0.0;
    }
    final normalizedFocalDy = _normalizedFocalDy(focalDy);
    final baseOffset = _effectiveScrollOffset();
    final totalPixelsBefore =
        (baseOffset + normalizedFocalDy).clamp(0.0, double.infinity);
    return totalPixelsBefore / heightPerMinute;
  }

  double _calculateMaxScrollExtent(double zoom) {
    final heightPerMinute = _baseHeightPerMinute * zoom;
    final totalHeight = heightPerMinute * 24 * 60;
    final viewport = _resolveViewportHeight();
    final effectiveViewport =
        viewport > 0 ? viewport : totalHeight; // Fallback before layout
    return math.max(0.0, totalHeight - effectiveViewport);
  }

  double _clampScrollOffsetForZoom(double desiredOffset, double zoom) {
    final maxScrollExtent = _calculateMaxScrollExtent(zoom);
    if (desiredOffset.isNaN || desiredOffset.isInfinite) {
      return _effectiveScrollOffset().clamp(0.0, maxScrollExtent);
    }
    return desiredOffset.clamp(0.0, maxScrollExtent);
  }

  void _syncDayViewScroll(double offset) {
    final controller = _dayViewScrollController();
    final targetOffset = offset.clamp(0.0, double.infinity).toDouble();
    if (controller == null || !controller.hasClients) {
      _pendingScrollSyncOffset = targetOffset;
      _schedulePendingScrollSync();
      _currentScrollOffset = targetOffset;
      _initialScrollOffset = targetOffset;
      return;
    }
    if ((controller.offset - targetOffset).abs() < 0.5) {
      _currentScrollOffset = targetOffset;
      _initialScrollOffset = targetOffset;
      return;
    }

    try {
      controller.jumpTo(targetOffset);
      _currentScrollOffset = targetOffset;
      _initialScrollOffset = targetOffset;
    } catch (_) {}
  }

  void _schedulePendingScrollSync() {
    if (!mounted || _pendingScrollSyncScheduled) {
      return;
    }
    _pendingScrollSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingScrollSyncScheduled = false;
      if (!mounted) return;
      if (_pendingScrollSyncOffset == null) return;

      final pending = _pendingScrollSyncOffset!;
      final controller = _dayViewScrollController();
      if (controller == null || !controller.hasClients) {
        _schedulePendingScrollSync();
        return;
      }
      _pendingScrollSyncOffset = null;
      _syncDayViewScroll(pending);
    });
  }

  void _applyZoomAroundFocalPoint({
    required double proposedZoom,
    required double focalDy,
    double? anchorMinute,
  }) {
    if (!_hasLiveDayViewClient()) {
      return;
    }
    final normalizedFocalDy = _normalizedFocalDy(focalDy);
    final resolvedAnchorMinute =
        anchorMinute ?? _anchorMinuteAtFocalPoint(normalizedFocalDy);
    final clampedZoom = proposedZoom.clamp(_minVerticalZoom, _maxVerticalZoom);
    final newHeight = _baseHeightPerMinute * clampedZoom;
    final currentOffset = _effectiveScrollOffset();
    final desiredOffset =
        (resolvedAnchorMinute * newHeight) - normalizedFocalDy;
    final clampedOffset = _clampScrollOffsetForZoom(desiredOffset, clampedZoom);

    final zoomChanged = (clampedZoom - _verticalZoom).abs() >= 0.001;
    final offsetChanged = (clampedOffset - currentOffset).abs() >= 0.5;
    if (!zoomChanged && !offsetChanged) return;

    // Pre-jump the scroll controller BEFORE setState. This updates the
    // DayView's internal _lastScrollOffset via its scroll listener.
    _syncDayViewScroll(clampedOffset);

    setState(() {
      _verticalZoom = clampedZoom;
      _initialScrollOffset = clampedOffset;
      _currentScrollOffset = clampedOffset;
    });

    // Post-frame correction: the DayView package recreates its internal page
    // (new ValueKey) when heightPerMinute changes, and the new ScrollPosition
    // starts at the controller's immutable initialScrollOffset (often 0).
    // We must correct it after the rebuild. We use a shared target field so
    // that during rapid pinch events, all callbacks read the LATEST target
    // rather than a stale captured value — preventing flicker.
    _latestZoomScrollTarget = clampedOffset;
    if (!_zoomScrollCorrectionScheduled) {
      _zoomScrollCorrectionScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _zoomScrollCorrectionScheduled = false;
        if (!mounted) return;
        final target = _latestZoomScrollTarget;
        if (target == null) return;
        _latestZoomScrollTarget = null;
        final controller = _dayViewScrollController();
        if (controller != null &&
            controller.hasClients &&
            (controller.offset - target).abs() >= 0.5) {
          try {
            controller.jumpTo(target);
            _currentScrollOffset = target;
            _initialScrollOffset = target;
          } catch (_) {}
        }
      });
    }
  }

  void _zoomIn() {
    final focalDy = _buttonZoomFocalPoint();
    final anchorMinute = _anchorMinuteAtFocalPoint(focalDy);
    _applyZoomAroundFocalPoint(
      proposedZoom: _verticalZoom + _zoomStep,
      focalDy: focalDy,
      anchorMinute: anchorMinute,
    );
  }

  void _zoomOut() {
    final focalDy = _buttonZoomFocalPoint();
    final anchorMinute = _anchorMinuteAtFocalPoint(focalDy);
    _applyZoomAroundFocalPoint(
      proposedZoom: _verticalZoom - _zoomStep,
      focalDy: focalDy,
      anchorMinute: anchorMinute,
    );
  }

  void _resetZoom() {
    final focalDy = _buttonZoomFocalPoint();
    final anchorMinute = _anchorMinuteAtFocalPoint(focalDy);
    _applyZoomAroundFocalPoint(
      proposedZoom: 1.0,
      focalDy: focalDy,
      anchorMinute: anchorMinute,
    );
  }

  void _onCalendarPointerDown(PointerDownEvent event) {
    _lastTapDownPosition = event.localPosition;
  }

  @override
  void reassemble() {
    super.reassemble();
    // Clean up observers on hot reload to prevent accumulation
    NotificationCenter.removeObserver(this);
  }

  @override
  void dispose() {
    _loadingStateSafetyTimer?.cancel();
    _observerRefreshDebounceTimer?.cancel();
    NotificationCenter.removeObserver(this);
    _completedEventController.dispose();
    _plannedEventController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Calendar View'),
        actions: [
          IconButton(
            icon: _isLoadingEvents
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoadingEvents ? null : _loadEvents,
            tooltip: 'Refresh Events',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: _zoomOut,
            tooltip: 'Zoom Out',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: _zoomIn,
            tooltip: 'Zoom In',
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetZoom,
            tooltip: 'Reset Zoom',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showManualEntryDialog,
        heroTag: 'add_entry',
        tooltip: 'Log Time Entry',
        child: const Icon(Icons.add),
      ),
      body: CalendarDayViewBody(
        showPlanned: _showPlanned,
        isPinching: false,
        selectedDate: _selectedDate,
        dayViewKey: _dayViewKey,
        plannedOverlapPairCount: _plannedOverlapPairCount,
        currentScrollOffset: _currentScrollOffset,
        initialScrollOffset: _initialScrollOffset,
        calendarViewportHeight: _calendarViewportHeight,
        lastTapDownPosition: _lastTapDownPosition,
        isLoadingEvents: _isLoadingEvents,
        plannedEventController: _plannedEventController,
        completedEventController: _completedEventController,
        defaultDurationMinutes: _defaultDurationMinutes,
        onChangeDate: (days) {
          setState(() {
            _selectedDate = _selectedDate.add(Duration(days: days));
            _dayViewKey = GlobalKey<DayViewState>();
          });
          _loadEvents();
        },
        onResetDate: () {
          setState(() {
            _selectedDate = DateService.currentDate;
            _dayViewKey = GlobalKey<DayViewState>();
          });
          _loadEvents();
        },
        onSaveTabState: _saveTabState,
        onTogglePlanned: (value) {
          final shouldLoadPlanned = value && !_showPlanned;
          setState(() {
            _showPlanned = value;
            _dayViewKey = GlobalKey<DayViewState>();
          });
          if (shouldLoadPlanned) {
            _loadEvents(isSilent: true);
          }
        },
        onShowTimeBreakdownChart: _showTimeBreakdownChart,
        onShowManualEntryDialog: (startTime, endTime) {
          _showManualEntryDialog(startTime: startTime, endTime: endTime);
        },
        onPointerDownEvent: _onCalendarPointerDown,
        onPointerMoveEvent: (_) {},
        onPointerUpEvent: (_) {},
        onPointerCancelEvent: (_) {},
        onCalendarViewportHeightChanged: (height) {
          if ((height - _calendarViewportHeight).abs() < 0.5) {
            return;
          }
          setState(() {
            _calendarViewportHeight = height;
          });
        },
        onCurrentScrollOffsetChanged: (offset) {
          _currentScrollOffset = offset;
        },
        calculateHeightPerMinute: _calculateHeightPerMinute,
        buildEventTile: _buildEventTile,
        buildOverlapBanner: _buildOverlapBanner,
      ),
    );
  }
}
