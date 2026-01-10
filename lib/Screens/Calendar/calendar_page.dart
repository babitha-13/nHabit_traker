import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Screens/Calendar/Calender%20UI/calender_body.dart';
import 'package:habit_tracker/Screens/Calendar/Calender%20models/planned_overlap_group.dart';
import 'package:habit_tracker/Screens/Calendar/Calender%20models/calender_event_metadata.dart';
import 'package:habit_tracker/Screens/Calendar/Calender%20models/planned_overlap_info.dart';
import 'package:habit_tracker/Screens/Calendar/time_breakdown_pie_chart.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/backend/time_logging_preferences_service.dart';
import 'package:habit_tracker/Helper/utils/activity_template_events.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:habit_tracker/Screens/Calendar/Utils/calendar_formatting_utils.dart';
import 'package:habit_tracker/Screens/Calendar/Calculators/calendar_overlap_calculator.dart';
import 'package:habit_tracker/Screens/Calendar/Calculators/calendar_time_breakdown_calculator.dart';
import 'package:habit_tracker/Screens/Calendar/Services/calendar_event_service.dart';
import 'package:habit_tracker/Screens/Calendar/Calender%20UI/calendar_event_tile.dart';
import 'package:habit_tracker/Screens/Calendar/Calender%20UI/calendar_overlap_ui.dart';
import 'package:habit_tracker/Screens/Calendar/Calender%20UI/calendar_modals.dart';

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
  DateTime _selectedDate = DateTime.now();
  bool _showPlanned = true;
  static const double _minVerticalZoom = 0.5;
  static const double _maxVerticalZoom = 3.0;
  static const double _zoomStep = 0.2;
  double _verticalZoom = 1.0;
  static const double _baseHeightPerMinute = 2.0;
  List<CalendarEventData> _sortedCompletedEvents = [];
  List<CalendarEventData> _sortedPlannedEvents = [];
  int _plannedOverlapPairCount = 0;
  final Set<String> _plannedOverlappedEventIds = {};
  List<PlannedOverlapGroup> _plannedOverlapGroups = const [];
  GlobalKey<DayViewState> _dayViewKey = GlobalKey<DayViewState>();
  Offset? _lastTapDownPosition;
  double? _initialZoomOnGestureStart;
  double? _initialScaleOnGestureStart;
  int _defaultDurationMinutes = 10;
  final Map<String, String> _optimisticOperations = {};
  final Map<String, ActivityInstanceRecord> _optimisticInstances = {};
  bool _isLoadingEvents = false;

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
    NotificationCenter.addObserver(this, InstanceEvents.instanceUpdated, _handleInstanceUpdated,);
    NotificationCenter.addObserver(this, InstanceEvents.instanceCreated, _handleInstanceCreated,);
    NotificationCenter.addObserver(this, InstanceEvents.instanceDeleted, _handleInstanceDeleted,);
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        _loadEvents();
      }
    });
    NotificationCenter.addObserver(this, 'routineUpdated', (param) {
      if (mounted) {
        _loadEvents();
      }
    });
    NotificationCenter.addObserver(
      this,
      ActivityTemplateEvents.templateUpdated,
      (param) {
        if (mounted) {
          _loadEvents();
        }
      },
    );
    NotificationCenter.addObserver(this, 'instanceUpdateRollback', (param) {
      _handleRollback(param);
    });
  }

  Future<void> _loadDefaultDuration() async {
    try {
      final userId = currentUserUid;
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
    } catch (e) {
    }
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
    final now = DateTime.now();
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
    return CalendarTimeBreakdownCalculator.calculateTimeBreakdown(_sortedCompletedEvents);
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
    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
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
      }
    }

    if (isOptimistic) {
      if (operationId != null) {
        _optimisticOperations[operationId] = instance.reference.id;
      }
      if (affectsPlannedSection) {
        _optimisticInstances[instance.reference.id] = instance;
        _applyOptimisticPlannedPatch(instance);
      }
    } else {
      if (operationId != null) {
        _optimisticOperations.remove(operationId);
      }
      _optimisticInstances.remove(instance.reference.id);
      if (affectsPlannedSection) {
        _loadEvents();
      }
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

    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    bool affectsSelectedDate = false;
    bool affectsPlannedSection = false;
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
    if (isOptimistic) {
      if (operationId != null) {
        _optimisticOperations[operationId] = instance.reference.id;
      }
      if (affectsPlannedSection) {
        _optimisticInstances[instance.reference.id] = instance;
      }
      if (affectsSelectedDate) {
        _applyOptimisticPlannedPatch(instance);
        _loadEvents();
      }
    } else {
      if (operationId != null) {
        _optimisticOperations.remove(operationId);
      }
      _optimisticInstances.remove(instance.reference.id);
      if (affectsSelectedDate) {
        _loadEvents();
      }
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
    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    final instanceId = instance.reference.id;
    _optimisticInstances.remove(instanceId);
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
    if (affectsPlannedSection) {
      _plannedEventController.removeWhere((e) {
        final metadata = CalendarEventMetadata.fromMap(e.event);
        return metadata?.instanceId == instanceId;
      });
      _sortedPlannedEvents.removeWhere((e) {
        final metadata = CalendarEventMetadata.fromMap(e.event);
        return metadata?.instanceId == instanceId;
      });
      final overlapInfo = _computePlannedOverlaps(_sortedPlannedEvents);
      _plannedOverlapPairCount = overlapInfo.pairCount;
      _plannedOverlappedEventIds
        ..clear()
        ..addAll(overlapInfo.overlappedIds);
      _plannedOverlapGroups = overlapInfo.groups;

      if (mounted) setState(() {});
    }
    if (affectsSelectedDate && instance.timeLogSessions.isNotEmpty) {
      _loadEvents();
    }
  }

  void _handleRollback(dynamic param) {
    if (!mounted) return;
    if (param is Map) {
      final operationId = param['operationId'] as String?;
      final instanceId = param['instanceId'] as String?;
      if (operationId != null &&
          _optimisticOperations.containsKey(operationId)) {
        setState(() {
          _optimisticOperations.remove(operationId);
          if (instanceId != null) {
            _optimisticInstances.remove(instanceId);
            _plannedEventController.removeWhere((e) {
              final metadata = CalendarEventMetadata.fromMap(e.event);
              return metadata?.instanceId == instanceId;
            });
            _sortedPlannedEvents.removeWhere((e) {
              final metadata = CalendarEventMetadata.fromMap(e.event);
              return metadata?.instanceId == instanceId;
            });
          }
        });
        _loadEvents();
      }
    }
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
      return;
    }

    final dueDateOnly = DateTime(
      instance.dueDate!.year,
      instance.dueDate!.month,
      instance.dueDate!.day,
    );

    if (!dueDateOnly.isAtSameMomentAs(selectedDateOnly)) {
      return;
    }

    final instanceId = instance.reference.id;
    _plannedEventController.removeWhere((e) {
      final metadata = CalendarEventMetadata.fromMap(e.event);
      return metadata?.instanceId == instanceId;
    });
    _sortedPlannedEvents.removeWhere((e) {
      final metadata = CalendarEventMetadata.fromMap(e.event);
      return metadata?.instanceId == instanceId;
    });
    if (instance.status == 'completed' || instance.status == 'skipped') {
      final overlapInfo = _computePlannedOverlaps(_sortedPlannedEvents);
      _plannedOverlapPairCount = overlapInfo.pairCount;
      _plannedOverlappedEventIds
        ..clear()
        ..addAll(overlapInfo.overlappedIds);
      _plannedOverlapGroups = overlapInfo.groups;
      if (mounted) setState(() {});
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
      final overlapInfo = _computePlannedOverlaps(_sortedPlannedEvents);
      _plannedOverlapPairCount = overlapInfo.pairCount;
      _plannedOverlappedEventIds
        ..clear()
        ..addAll(overlapInfo.overlappedIds);
      _plannedOverlapGroups = overlapInfo.groups;
      if (mounted) setState(() {});
    } catch (e) {
      _loadEvents();
    }
  }

  Future<void> _loadEvents() async {
    if (mounted) {
      setState(() {
        _isLoadingEvents = true;
      });
    }
    try {
      final userId = currentUserUid;
      final result = await CalendarEventService.loadEvents(
        userId: userId,
        selectedDate: _selectedDate,
        optimisticInstances: _optimisticInstances,
      );

      _sortedCompletedEvents = result.completedEvents;
      _sortedPlannedEvents = result.plannedEvents;
      final overlapInfo = _computePlannedOverlaps(result.plannedEvents);
      _plannedOverlapPairCount = overlapInfo.pairCount;
      _plannedOverlappedEventIds
        ..clear()
        ..addAll(overlapInfo.overlappedIds);
      _plannedOverlapGroups = overlapInfo.groups;
      _completedEventController.removeWhere((e) => true);
      _plannedEventController.removeWhere((e) => true);
      _completedEventController.addAll(result.completedEvents);
      _plannedEventController.addAll(result.plannedEvents);
      if (mounted) setState(() {});
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
        });
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
    return CalendarOverlapCalculator.computePlannedOverlaps(planned);
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

  double _calculateMaxScrollExtent(double zoom) {
    final heightPerMinute = _baseHeightPerMinute * zoom;
    final totalHeight = heightPerMinute * 24 * 60;
    final viewport = _calendarViewportHeight > 0
        ? _calendarViewportHeight
        : totalHeight; // Fallback before layout
    return math.max(0.0, totalHeight - viewport);
  }

  double _clampScrollOffsetForZoom(double desiredOffset, double zoom) {
    final maxScrollExtent = _calculateMaxScrollExtent(zoom);
    if (desiredOffset.isNaN || desiredOffset.isInfinite) {
      return _currentScrollOffset.clamp(0.0, maxScrollExtent);
    }
    return desiredOffset.clamp(0.0, maxScrollExtent);
  }

  void _syncDayViewScroll(double offset) {
    final state = _dayViewKey.currentState;
    if (state == null) return;
    final dynamic dayViewState = state;
    try {
      final ScrollController? controller = dayViewState.scrollController;
      if (controller != null && controller.hasClients) {
        controller.jumpTo(offset);
        return;
      }
    } catch (_) {
    }
    try {
      dayViewState.animateTo(
        offset,
        duration: const Duration(milliseconds: 1),
        curve: Curves.linear,
      );
    } catch (_) {
    }
  }

  void _zoomIn() {
    final oldHeight = _calculateHeightPerMinute();
    final newScale = (_verticalZoom + _zoomStep).clamp(_minVerticalZoom, _maxVerticalZoom);

    if ((newScale - _verticalZoom).abs() < 0.001) return;
    final newHeight = _baseHeightPerMinute * newScale;
    final ratio = newHeight / oldHeight;
    _initialScrollOffset = _currentScrollOffset * ratio;

    setState(() {
      _verticalZoom = newScale;
    });
  }

  void _zoomOut() {
    final oldHeight = _calculateHeightPerMinute();
    final newScale = (_verticalZoom - _zoomStep).clamp(_minVerticalZoom, _maxVerticalZoom);

    if ((newScale - _verticalZoom).abs() < 0.001) return;
    final newHeight = _baseHeightPerMinute * newScale;
    final ratio = newHeight / oldHeight;
    _initialScrollOffset = _currentScrollOffset * ratio;

    setState(() {
      _verticalZoom = newScale;
    });
  }

  void _resetZoom() {
    setState(() {
      _verticalZoom = 1.0;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _initialZoomOnGestureStart = _verticalZoom;
    _initialScaleOnGestureStart = 1.0; // Scale starts at 1.0
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_initialZoomOnGestureStart == null ||
        _initialScaleOnGestureStart == null) {
      return; // Gesture not properly initialized
    }

    final scaleChange = details.scale / _initialScaleOnGestureStart!;
    final proposedZoom = _initialZoomOnGestureStart! * scaleChange;
    final clampedZoom = proposedZoom.clamp(_minVerticalZoom, _maxVerticalZoom);
    final oldHeight = _baseHeightPerMinute * _verticalZoom;
    final newHeight = _baseHeightPerMinute * clampedZoom;
    final focalDy = details.localFocalPoint.dy;
    final totalPixelsBefore = (_currentScrollOffset + focalDy).clamp(0.0, double.infinity);
    final focalMinutes = oldHeight > 0 ? totalPixelsBefore / oldHeight : 0.0;
    final desiredOffset = (focalMinutes * newHeight) - focalDy;
    final clampedOffset = _clampScrollOffsetForZoom(desiredOffset, clampedZoom);
    final zoomChanged = (clampedZoom - _verticalZoom).abs() >= 0.001;
    final offsetChanged = (clampedOffset - _currentScrollOffset).abs() >= 0.5; // avoid noisy rebuilds
    if (!zoomChanged && !offsetChanged) return;

    setState(() {
      _verticalZoom = clampedZoom;
      _initialScrollOffset = clampedOffset;
      _currentScrollOffset = clampedOffset;
    });
    _syncDayViewScroll(clampedOffset);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _initialZoomOnGestureStart = null;
    _initialScaleOnGestureStart = null;
  }

  @override
  void dispose() {
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
        },
        onResetDate: () {
          setState(() {
            _selectedDate = DateTime.now();
            _dayViewKey = GlobalKey<DayViewState>();
          });
        },
        onSaveTabState: _saveTabState,
        onTogglePlanned: (value) {
          setState(() {
            _showPlanned = value;
            _dayViewKey = GlobalKey<DayViewState>();
          });
        },
        onShowTimeBreakdownChart: _showTimeBreakdownChart,
        onShowManualEntryDialog: (startTime, endTime) {
          _showManualEntryDialog(startTime: startTime, endTime: endTime);
        },
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onCalendarViewportHeightChanged: (height) {
          setState(() {
            _calendarViewportHeight = height;
          });
        },
        onCurrentScrollOffsetChanged: (offset) {
          setState(() {
            _currentScrollOffset = offset;
          });
        },
        onPointerDown: (position) {
          setState(() {
            _lastTapDownPosition = position;
          });
        },
        calculateHeightPerMinute: _calculateHeightPerMinute,
        buildEventTile: _buildEventTile,
        buildOverlapBanner: _buildOverlapBanner,
      ),
    );
  }
}