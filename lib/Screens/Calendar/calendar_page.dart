import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:habit_tracker/Helper/backend/calendar_queue_service.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:from_css_color/from_css_color.dart';
import 'package:habit_tracker/Screens/Components/manual_time_log_modal.dart';
import 'package:habit_tracker/Screens/Calendar/time_breakdown_pie_chart.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/backend/time_logging_preferences_service.dart';
import 'package:habit_tracker/Helper/utils/planned_duration_resolver.dart';
import 'package:habit_tracker/Helper/backend/routine_planned_calendar_service.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Metadata stored with calendar events for editing
class CalendarEventMetadata {
  final String instanceId;
  final int sessionIndex; // Index in timeLogSessions array
  final String activityName;
  final String activityType; // 'task', 'habit', 'non_productive'
  final String? templateId;
  final String? categoryId;
  final String? categoryName;
  final String? categoryColorHex;

  CalendarEventMetadata({
    required this.instanceId,
    required this.sessionIndex,
    required this.activityName,
    required this.activityType,
    this.templateId,
    this.categoryId,
    this.categoryName,
    this.categoryColorHex,
  });

  Map<String, dynamic> toMap() {
    return {
      'instanceId': instanceId,
      'sessionIndex': sessionIndex,
      'activityName': activityName,
      'activityType': activityType,
      'templateId': templateId,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'categoryColorHex': categoryColorHex,
    };
  }

  static CalendarEventMetadata? fromMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return CalendarEventMetadata(
        instanceId: data['instanceId'] as String,
        sessionIndex: data['sessionIndex'] as int,
        activityName: data['activityName'] as String,
        activityType: data['activityType'] as String,
        templateId: data['templateId'] as String?,
        categoryId: data['categoryId'] as String?,
        categoryName: data['categoryName'] as String?,
        categoryColorHex: data['categoryColorHex'] as String?,
      );
    }
    return null;
  }
}

/// Custom painter for diagonal stripe pattern
///
/// Minimalist design: Uses thicker lines with generous spacing to differentiate
/// non-productive activities from tasks while maintaining a clean aesthetic.
class _DiagonalStripePainter extends CustomPainter {
  final Color stripeColor;
  final double stripeWidth;
  final double spacing;

  _DiagonalStripePainter({
    this.stripeColor = const Color(0xFFBDBDBD),
    this.stripeWidth = 3.5, // Thicker for better visibility with spacing
    this.spacing = 16.0, // Generous spacing for minimalist look
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = stripeColor
      ..strokeWidth = stripeWidth
      ..style = PaintingStyle.stroke;

    // Draw diagonal lines at 45 degrees (from top-left to bottom-right)
    // Calculate perpendicular spacing for even stripe distribution
    final lineSpacing = spacing + stripeWidth;
    final perpendicularSpacing = lineSpacing / math.sqrt(2);

    // Calculate offset range needed to cover entire canvas
    // For line y = x + offset:
    // - To cover from left edge: offset ranges from 0 to height
    // - To cover from top edge: offset ranges from -width to 0
    final minOffset = -size.width;
    final maxOffset = size.height;

    // Generate lines at regular intervals within the offset range
    final numLines =
        ((maxOffset - minOffset) / perpendicularSpacing).ceil() + 2;

    // Draw lines with equation: y = x + offset
    for (int i = -1; i < numLines; i++) {
      final offset = minOffset + (i * perpendicularSpacing);

      // Find all possible intersection points with canvas boundaries
      // For line y = x + offset:
      // - Top edge (y=0): x = -offset, point = (-offset, 0)
      // - Bottom edge (y=height): x = height - offset, point = (height - offset, height)
      // - Left edge (x=0): y = offset, point = (0, offset)
      // - Right edge (x=width): y = width + offset, point = (width, width + offset)

      final intersections = <Offset>[];

      // Check top edge intersection
      final topX = -offset;
      if (topX >= 0 && topX <= size.width) {
        intersections.add(Offset(topX, 0));
      }

      // Check bottom edge intersection
      final bottomX = size.height - offset;
      if (bottomX >= 0 && bottomX <= size.width) {
        intersections.add(Offset(bottomX, size.height));
      }

      // Check left edge intersection
      final leftY = offset;
      if (leftY >= 0 && leftY <= size.height) {
        intersections.add(Offset(0, leftY));
      }

      // Check right edge intersection
      final rightY = size.width + offset;
      if (rightY >= 0 && rightY <= size.height) {
        intersections.add(Offset(size.width, rightY));
      }

      // Draw line between the two valid intersection points
      if (intersections.length >= 2) {
        // Sort by x coordinate to get start and end points
        intersections.sort((a, b) => a.dx.compareTo(b.dx));
        canvas.drawLine(intersections.first, intersections.last, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DiagonalStripePainter oldDelegate) {
    return oldDelegate.stripeColor != stripeColor ||
        oldDelegate.stripeWidth != stripeWidth ||
        oldDelegate.spacing != spacing;
  }
}

class _PlannedOverlapGroup {
  final DateTime start;
  final DateTime end;
  final List<CalendarEventData> events;

  const _PlannedOverlapGroup({
    required this.start,
    required this.end,
    required this.events,
  });
}

class _PlannedOverlapInfo {
  final int pairCount;
  final Set<String> overlappedIds;
  final List<_PlannedOverlapGroup> groups;

  const _PlannedOverlapInfo({
    required this.pairCount,
    required this.overlappedIds,
    required this.groups,
  });
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  // Separate event controllers for completed and planned
  final EventController _completedEventController = EventController();
  final EventController _plannedEventController = EventController();

  // Scroll tracking
  double _currentScrollOffset = 0.0;
  double _initialScrollOffset = 0.0;

  // State for view control
  DateTime _selectedDate = DateTime.now();
  bool _showPlanned =
      true; // Toggle between Planned (true) and Completed (false)

  // Vertical zoom constraints
  static const double _minVerticalZoom = 0.5;
  static const double _maxVerticalZoom = 3.0;
  static const double _zoomStep = 0.2;
  double _verticalZoom = 1.0;

  // Base height per minute
  static const double _baseHeightPerMinute = 2.0;

  // Sorted events for label collision detection
  List<CalendarEventData> _sortedCompletedEvents = [];
  List<CalendarEventData> _sortedPlannedEvents = [];

  // Planned schedule overlap detection (prominent conflict UI)
  int _plannedOverlapPairCount = 0;
  final Set<String> _plannedOverlappedEventIds = {};
  List<_PlannedOverlapGroup> _plannedOverlapGroups = const [];

  // Key to access DayView state for scrolling
  GlobalKey<DayViewState> _dayViewKey = GlobalKey<DayViewState>();

  // Track the last tap position for precise time calculation
  Offset? _lastTapDownPosition;

  // Track zoom gesture start for proportional zooming
  double? _initialZoomOnGestureStart;
  double? _initialScaleOnGestureStart;

  // Cached default duration for time logging (in minutes)
  int _defaultDurationMinutes = 10;

  // Track optimistic operations for rollback
  final Map<String, String> _optimisticOperations = {};

  // Cache optimistic instances for immediate display
  final Map<String, ActivityInstanceRecord> _optimisticInstances = {};

  // Loading state for events
  bool _isLoadingEvents = false;

  @override
  void initState() {
    super.initState();
    _calculateInitialScrollOffset();
    _initializeTabState();
    _loadDefaultDuration();
    // Listen for instance updates to refresh calendar
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
        _loadEvents();
      }
    });
    NotificationCenter.addObserver(this, 'instanceUpdateRollback', (param) {
      _handleRollback(param);
    });
  }

  /// Load user's default duration preference
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
      // On error, keep default of 10 minutes
      print('Error loading default duration: $e');
    }
  }

  /// Initialize tab state by loading saved preference
  Future<void> _initializeTabState() async {
    final savedShowPlanned = await _loadTabState();
    if (mounted) {
      setState(() {
        _showPlanned = savedShowPlanned;
      });
      _loadEvents();
    }
  }

  /// Load saved tab state from SharedPreferences
  Future<bool> _loadTabState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('calendar_show_planned') ?? true; // Default to Planned
  }

  /// Save tab state to SharedPreferences
  Future<void> _saveTabState(bool showPlanned) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('calendar_show_planned', showPlanned);
  }

  void _calculateInitialScrollOffset() {
    final now = DateTime.now();
    // Calculate minutes from midnight
    final minutes = now.hour * 60 + now.minute;
    // Start 1 hour before current time for context
    final startMinutes = (minutes - 60).clamp(0, 24 * 60).toDouble();

    // Set initial offsets
    _initialScrollOffset = startMinutes * _calculateHeightPerMinute();
    _currentScrollOffset = _initialScrollOffset;
  }

  void _showManualEntryDialog({DateTime? startTime, DateTime? endTime}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return ManualTimeLogModal(
          selectedDate: _selectedDate,
          initialStartTime: startTime,
          initialEndTime: endTime,
          onPreviewChange: _handlePreviewChange,
          onSave: () {
            // Reload events to reflect the new entry
            _loadEvents();
          },
        );
      },
    ).whenComplete(() {
      _removePreviewEvent();
    });
  }

  /// Calculate time breakdown by category from events
  /// NOTE: This processes ALL time-logged events, not just completed ones
  /// The name "_sortedCompletedEvents" is misleading - it contains all events with time logs
  TimeBreakdownData _calculateTimeBreakdown() {
    // Track totals per type
    double habitMinutes = 0.0;
    double taskMinutes = 0.0;
    double nonProductiveMinutes = 0.0;

    // Map to store minutes per category (keyed by categoryId or categoryName)
    // For habits: Map<categoryId or categoryName, minutes>
    final habitCategoryTimeMap = <String, double>{};
    final habitCategoryColorMap =
        <String, String>{}; // Store color hex per category

    // For tasks: Map<categoryId or categoryName, minutes>
    final taskCategoryTimeMap = <String, double>{};
    final taskCategoryColorMap =
        <String, String>{}; // Store color hex per category

    // Process all events with time logs
    for (final event in _sortedCompletedEvents) {
      if (event.startTime == null || event.endTime == null) continue;

      // Extract metadata
      final metadata = CalendarEventMetadata.fromMap(event.event);
      if (metadata == null) continue;

      // Calculate duration in minutes
      final duration = event.endTime!.difference(event.startTime!);
      final minutes = duration.inMinutes.toDouble();

      // Add to type totals
      if (metadata.activityType == 'habit') {
        habitMinutes += minutes;
      } else if (metadata.activityType == 'task') {
        taskMinutes += minutes;
      } else if (metadata.activityType == 'non_productive') {
        nonProductiveMinutes += minutes;
      }

      // For habits and tasks, accumulate per category
      if (metadata.activityType == 'habit' || metadata.activityType == 'task') {
        // Prefer categoryName over categoryId for display, use categoryId as fallback
        final categoryKey = metadata.categoryName?.isNotEmpty == true
            ? metadata.categoryName!
            : (metadata.categoryId?.isNotEmpty == true
                ? metadata.categoryId!
                : 'Uncategorized');

        // Get color hex from metadata
        String? colorHex = metadata.categoryColorHex;

        if (metadata.activityType == 'habit') {
          habitCategoryTimeMap[categoryKey] =
              (habitCategoryTimeMap[categoryKey] ?? 0.0) + minutes;
          // Set color from metadata if available, otherwise keep existing or use default
          if (colorHex != null && colorHex.isNotEmpty) {
            habitCategoryColorMap[categoryKey] = colorHex;
          } else if (!habitCategoryColorMap.containsKey(categoryKey)) {
            // Only use default if no color has been set yet
            habitCategoryColorMap[categoryKey] = '#FF9800'; // Orange default
          }
        } else {
          taskCategoryTimeMap[categoryKey] =
              (taskCategoryTimeMap[categoryKey] ?? 0.0) + minutes;
          // Set color from metadata if available, otherwise keep existing or use default
          if (colorHex != null && colorHex.isNotEmpty) {
            taskCategoryColorMap[categoryKey] = colorHex;
          } else if (!taskCategoryColorMap.containsKey(categoryKey)) {
            // Only use default if no color has been set yet
            taskCategoryColorMap[categoryKey] =
                '#1A1A1A'; // Dark charcoal default
          }
        }
      }
    }

    // Create segments - ordered: habit categories, task categories, non-productive, unlogged
    final segments = <PieChartSegment>[];

    // Add habit category segments
    final habitCategoryKeys = habitCategoryTimeMap.keys.toList()
      ..sort(); // Sort for consistent ordering
    for (final categoryKey in habitCategoryKeys) {
      final minutes = habitCategoryTimeMap[categoryKey]!;
      if (minutes > 0) {
        final colorHex = habitCategoryColorMap[categoryKey] ?? '#FF9800';
        Color categoryColor;
        try {
          categoryColor = fromCssColor(colorHex);
        } catch (e) {
          categoryColor = Colors.orange; // Fallback
        }
        segments.add(PieChartSegment(
          label: categoryKey,
          value: minutes,
          color: categoryColor,
          category: 'habit',
        ));
      }
    }

    // Add task category segments
    final taskCategoryKeys = taskCategoryTimeMap.keys.toList()
      ..sort(); // Sort for consistent ordering
    for (final categoryKey in taskCategoryKeys) {
      final minutes = taskCategoryTimeMap[categoryKey]!;
      if (minutes > 0) {
        final colorHex = taskCategoryColorMap[categoryKey] ?? '#1A1A1A';
        Color categoryColor;
        try {
          categoryColor = fromCssColor(colorHex);
        } catch (e) {
          categoryColor = const Color(0xFF1A1A1A); // Fallback
        }
        segments.add(PieChartSegment(
          label: categoryKey,
          value: minutes,
          color: categoryColor,
          category: 'task',
        ));
      }
    }

    // Add non-productive segment (single segment)
    if (nonProductiveMinutes > 0) {
      segments.add(PieChartSegment(
        label: 'Non-Productive',
        value: nonProductiveMinutes,
        color: Colors.grey,
        category: 'non_productive',
      ));
    }

    // Calculate unlogged time (24 hours = 1440 minutes)
    final totalLogged = habitMinutes + taskMinutes + nonProductiveMinutes;
    final unloggedMinutes = (24 * 60) - totalLogged;

    if (unloggedMinutes > 0) {
      segments.add(PieChartSegment(
        label: 'Unlogged',
        value: unloggedMinutes,
        color: Colors.grey.shade300,
        category: 'unlogged',
      ));
    }

    return TimeBreakdownData(
      habitMinutes: habitMinutes,
      taskMinutes: taskMinutes,
      nonProductiveMinutes: nonProductiveMinutes,
      segments: segments,
    );
  }

  /// Show pie chart bottom sheet
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
                // Fixed header with close button
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
    // Fetch the instance to get the session data
    try {
      final instance = await ActivityInstanceRecord.getDocumentOnce(
        ActivityInstanceRecord.collectionForUser(currentUserUid)
            .doc(metadata.instanceId),
      );

      if (instance.timeLogSessions.isEmpty ||
          metadata.sessionIndex >= instance.timeLogSessions.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session not found')),
        );
        return;
      }

      final session = instance.timeLogSessions[metadata.sessionIndex];
      final sessionStart = session['startTime'] as DateTime;
      final sessionEnd = session['endTime'] as DateTime?;

      if (sessionEnd == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session is not completed')),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          return ManualTimeLogModal(
            selectedDate: _selectedDate,
            initialStartTime: sessionStart,
            initialEndTime: sessionEnd,
            onPreviewChange: _handlePreviewChange,
            onSave: () {
              // Reload events to reflect the updated entry
              _loadEvents();
            },
            // Pass edit metadata
            editMetadata: metadata,
          );
        },
      ).whenComplete(() {
        _removePreviewEvent();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading session: $e')),
        );
      }
    }
  }

  void _handlePreviewChange(
      DateTime start, DateTime end, String type, Color? color) {
    // Remove existing preview
    _removePreviewEvent();

    // Validate that times are on the selected date to prevent calendar_view validation errors
    final selectedDateStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      0,
      0,
      0,
    );
    final selectedDateEnd = selectedDateStart.add(const Duration(days: 1));

    // Clamp times to selected date
    var validStartTime = start;
    var validEndTime = end;

    if (validStartTime.isBefore(selectedDateStart)) {
      validStartTime = selectedDateStart;
    } else if (validStartTime.isAfter(selectedDateEnd) ||
        validStartTime.isAtSameMomentAs(selectedDateEnd)) {
      validStartTime = selectedDateEnd.subtract(const Duration(seconds: 1));
    }

    if (validEndTime.isAfter(selectedDateEnd)) {
      validEndTime = selectedDateEnd.subtract(const Duration(seconds: 1));
    }

    // Ensure end time is after start time
    if (validEndTime.isBefore(validStartTime) ||
        validEndTime.isAtSameMomentAs(validStartTime)) {
      validEndTime =
          validStartTime.add(Duration(minutes: _defaultDurationMinutes));
    }

    // Ensure both times are on the same date as selectedDate
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

    // Only create preview if start time is on the selected date
    if (!startDateOnly.isAtSameMomentAs(selectedDateOnly)) {
      return; // Don't add preview if times don't match selected date
    }

    // Determine color
    Color previewColor = color ?? Colors.grey.withOpacity(0.5);
    String title = "New Entry";
    if (type == 'habit') title = "New Habit";
    if (type == 'task') title = "New Task";
    if (type == 'non_productive') title = "Non-Productive";

    final previewEvent = CalendarEventData(
      date: _selectedDate,
      startTime: validStartTime,
      endTime: validEndTime,
      title: title,
      description: "Preview",
      color: previewColor,
      event: "preview_id", // Use event field as ID tag
    );

    // Add to appropriate controller (using planned for preview is safer visual layer)
    _plannedEventController.add(previewEvent);

    // Auto-scroll logic
    // We need to ensure the start time is visible above the bottom sheet
    // Estimate bottom sheet height as 50% of screen or ~300-400px
    // Ideally we check MediaQuery, but inside this callback context might be tricky if not careful.
    // However, DayView gives us scroll control.

    if (_dayViewKey.currentState != null) {
      // Calculate Y position of the event start
      final minutesFromMidnight = start.hour * 60 + start.minute;
      final eventY = minutesFromMidnight * _calculateHeightPerMinute();

      // Get current scroll offset
      // Since we don't have direct access to ScrollController from DayViewState publicly in all versions,
      // we rely on our tracked _currentScrollOffset or try to jump if exposed.
      // CalendarView 1.0.3+ usually exposes proper controller or jump methods?
      // Checking `calendar_view` source previously showed `animateTo` might not be heavily exposed on State
      // But we can approximate.
      // Actually, let's use the scrollController if we can find it, or just use the logical check.

      // Since we are likely using a version where direct scroll manipulation might be limited via GlobalKey<DayViewState> without custom fork,
      // We will perform a best-effort check.
      // Wait, we tracked `_currentScrollOffset`.

      final viewportHeight = MediaQuery.of(context).size.height;
      final bottomSheetHeight = viewportHeight * 0.5; // Approximation

      // We use the tracked _currentScrollOffset as the best available source of truth
      final visibleBottom =
          _currentScrollOffset + (viewportHeight - bottomSheetHeight);

      if (eventY > visibleBottom - 50) {
        // Buffer
        // Event is hidden behind bottom sheet. Scroll UP to reveal it.
        // Target: prevent it from being hidden. Put it at 30% of screen height from top?
        // Actually, we just need it in view.
        final targetOffset = math.max(0.0, eventY - (viewportHeight * 0.2));

        // Attempt to animate scroll using dynamic access to DayViewState
        final state = _dayViewKey.currentState as dynamic;
        try {
          // Try common scroll methods usually present on ScrollableState or similar
          // Note: DayViewState in calendar_view often has 'animateTo' or exposes 'scrollController'
          if (state.mounted) {
            state.animateTo(
              targetOffset,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        } catch (e) {
          // Auto-scroll not supported on this version of DayView
          // Fallback: If animateTo fails, try accessing scrollController property
          try {
            if (state.scrollController != null) {
              state.scrollController.animateTo(
                targetOffset,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          } catch (e2) {
            // Auto-scroll completely failed
          }
        }
      }
    }
  }

  void _removePreviewEvent() {
    _plannedEventController.removeWhere((e) => e.event == "preview_id");
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
      // Force DayView rebuild by creating new key
      _dayViewKey = GlobalKey<DayViewState>();
    });
    _loadEvents();
  }

  void _resetDate() {
    setState(() {
      _selectedDate = DateTime.now();
      // Force DayView rebuild by creating new key
      _dayViewKey = GlobalKey<DayViewState>();
    });
    _loadEvents();
  }

  /// Handle instance creation - refresh calendar if the instance should appear in planned section
  void _handleInstanceCreated(dynamic param) {
    if (!mounted) return;

    // Handle both optimistic and reconciled instance creation
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

    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    // Check if new instance should appear in planned section on selected date
    bool affectsPlannedSection = false;

    // Check if instance is due on the selected date and has a due time
    // (planned events require both dueDate and dueTime)
    if (instance.dueDate != null &&
        instance.dueTime != null &&
        instance.dueTime!.isNotEmpty) {
      final dueDateOnly = DateTime(
        instance.dueDate!.year,
        instance.dueDate!.month,
        instance.dueDate!.day,
      );
      if (dueDateOnly.isAtSameMomentAs(selectedDateOnly)) {
        // Instance is due on selected date and has a time - should appear in planned section
        affectsPlannedSection = true;
      }
    }

    // Also check if instance belongs to the selected date (for habits)
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

    // Handle optimistic updates with immediate UI patches
    if (isOptimistic) {
      // Track optimistic operation
      if (operationId != null) {
        _optimisticOperations[operationId] = instance.reference.id;
      }
      
      // Store optimistic instance for planned section
      if (affectsPlannedSection) {
        _optimisticInstances[instance.reference.id] = instance;
        // Apply immediate UI patch
        _applyOptimisticPlannedPatch(instance);
      }
    } else {
      // Reconciled update - remove from optimistic tracking
      if (operationId != null) {
        _optimisticOperations.remove(operationId);
      }
      
      // Remove from optimistic cache
      _optimisticInstances.remove(instance.reference.id);
      
      // Background reconciliation: reload events to sync with backend
      if (affectsPlannedSection) {
        _loadEvents();
      }
    }
  }

  /// Handle instance updates - refresh calendar if the instance affects the selected date
  void _handleInstanceUpdated(dynamic param) {
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

    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    // Check if instance affects the selected date
    bool affectsSelectedDate = false;
    bool affectsPlannedSection = false;

    // Check if instance has timeLogSessions on the selected date
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

    // Check if instance belongs to the selected date (for habits and tasks)
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

    // Check if instance affects planned section (has dueDate + dueTime on selected date)
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

    // Handle optimistic updates with immediate UI patches
    if (isOptimistic) {
      // Track optimistic operation
      if (operationId != null) {
        _optimisticOperations[operationId] = instance.reference.id;
      }
      
      // Store optimistic instance for planned section
      if (affectsPlannedSection) {
        _optimisticInstances[instance.reference.id] = instance;
      }
      
      // Apply immediate UI patches if instance affects selected date
      if (affectsSelectedDate) {
        _applyOptimisticPlannedPatch(instance);
        // For completed events (time logs), we still need full reload
        // but we can optimize planned section immediately
        if (instance.timeLogSessions.isNotEmpty) {
          // Background reload for completed events
          _loadEvents();
        }
      }
    } else {
      // Reconciled update - remove from optimistic tracking
      if (operationId != null) {
        _optimisticOperations.remove(operationId);
      }
      
      // Remove from optimistic cache
      _optimisticInstances.remove(instance.reference.id);
      
      // Background reconciliation: reload events to sync with backend
      if (affectsSelectedDate) {
        _loadEvents();
      }
    }
  }

  void _handleInstanceDeleted(dynamic param) {
    if (!mounted) return;

    // Handle instance deletion
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

    // Remove from optimistic cache
    _optimisticInstances.remove(instanceId);

    // Check if deleted instance affected the selected date
    bool affectsSelectedDate = false;
    bool affectsPlannedSection = false;

    // Check if instance was in planned section (dueDate + dueTime on selected date)
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

    // Check if instance had timeLogSessions on the selected date
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

    // Also refresh if instance belonged to the selected date (for habits and tasks)
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

    // Apply immediate UI patch for planned section
    if (affectsPlannedSection) {
      _plannedEventController.removeWhere((e) {
        final metadata = CalendarEventMetadata.fromMap(e.event);
        return metadata?.instanceId == instanceId;
      });
      _sortedPlannedEvents.removeWhere((e) {
        final metadata = CalendarEventMetadata.fromMap(e.event);
        return metadata?.instanceId == instanceId;
      });

      // Recalculate overlaps
      final overlapInfo = _computePlannedOverlaps(_sortedPlannedEvents);
      _plannedOverlapPairCount = overlapInfo.pairCount;
      _plannedOverlappedEventIds
        ..clear()
        ..addAll(overlapInfo.overlappedIds);
      _plannedOverlapGroups = overlapInfo.groups;

      if (mounted) setState(() {});
    }

    // Background reload for completed events (time logs)
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
          // Remove from optimistic cache on rollback
          if (instanceId != null) {
            _optimisticInstances.remove(instanceId);
            // Remove optimistic event from planned section
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
        // Reload events to restore correct state
        _loadEvents();
      }
    }
  }

  /// Apply optimistic patch to planned events without waiting for backend
  void _applyOptimisticPlannedPatch(ActivityInstanceRecord instance) {
    if (!mounted) return;

    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    // Only handle instances with dueDate + dueTime on selected date
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

    // Remove existing event for this instance (if any)
    _plannedEventController.removeWhere((e) {
      final metadata = CalendarEventMetadata.fromMap(e.event);
      return metadata?.instanceId == instanceId;
    });
    _sortedPlannedEvents.removeWhere((e) {
      final metadata = CalendarEventMetadata.fromMap(e.event);
      return metadata?.instanceId == instanceId;
    });

    // If instance is completed or skipped, don't add to planned section
    if (instance.status == 'completed' || instance.status == 'skipped') {
      // Recalculate overlaps and update UI
      final overlapInfo = _computePlannedOverlaps(_sortedPlannedEvents);
      _plannedOverlapPairCount = overlapInfo.pairCount;
      _plannedOverlappedEventIds
        ..clear()
        ..addAll(overlapInfo.overlappedIds);
      _plannedOverlapGroups = overlapInfo.groups;
      if (mounted) setState(() {});
      return;
    }

    // Create new planned event for this instance
    try {
      // Determine category color (use fallback if categories not loaded)
      Color categoryColor;
      if (instance.templateCategoryType == 'habit') {
        // Try to use cached category color, fallback to blue
        if (instance.templateCategoryColor.isNotEmpty) {
          categoryColor = _parseColor(instance.templateCategoryColor);
        } else {
          categoryColor = Colors.blue;
        }
      } else if (instance.templateCategoryType == 'non_productive') {
        categoryColor = Colors.grey;
      } else {
        // Tasks default to Dark Charcoal/Black
        categoryColor = const Color(0xFF1A1A1A);
      }

      // Parse due time
      final startTime = _parseDueTime(instance.dueTime!, _selectedDate);

      // Determine duration (fast heuristic for optimistic update)
      int? durationMinutes;
      if (instance.templateTrackingType == 'time' && instance.templateTarget != null) {
        // Use target minutes if available
        final target = instance.templateTarget;
        if (target is num) {
          durationMinutes = target.toInt();
        } else if (target is String) {
          durationMinutes = int.tryParse(target);
        }
      }
      
      // Fallback to default duration if no target
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

      // Add to planned events
      _sortedPlannedEvents.add(newEvent);
      _sortedPlannedEvents.sort((a, b) {
        if (a.startTime == null || b.startTime == null) return 0;
        return a.startTime!.compareTo(b.startTime!);
      });

      // Update controller
      _plannedEventController.add(newEvent);

      // Recalculate overlaps
      final overlapInfo = _computePlannedOverlaps(_sortedPlannedEvents);
      _plannedOverlapPairCount = overlapInfo.pairCount;
      _plannedOverlappedEventIds
        ..clear()
        ..addAll(overlapInfo.overlappedIds);
      _plannedOverlapGroups = overlapInfo.groups;

      // Update UI
      if (mounted) setState(() {});
    } catch (e) {
      // On error, fall back to full reload
      print('Error applying optimistic planned patch: $e');
      _loadEvents();
    }
  }

  Future<void> _loadEvents() async {
    // Set loading state
    if (mounted) {
      setState(() {
        _isLoadingEvents = true;
      });
    }

    try {
      // Don't clear events yet - keep old events visible while loading new ones
      // This prevents the flicker effect

      // Get categories for color lookup
      final userId = currentUserUid;

    // Get date range for filtering (start and end of selected date)
    final selectedDateStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      0,
      0,
      0,
    );
    final selectedDateEnd = selectedDateStart.add(const Duration(days: 1));

    // Batch all Firestore queries in parallel for faster loading
    final results = await Future.wait([
      queryHabitCategoriesOnce(
        userId: userId,
        callerTag: 'CalendarPage._loadEvents.habits',
      ),
      queryTaskCategoriesOnce(
        userId: userId,
        callerTag: 'CalendarPage._loadEvents.tasks',
      ),
      CalendarQueueService.getCompletedItems(
        userId: userId,
        date: _selectedDate,
      ),
      TaskInstanceService.getTimeLoggedTasks(
        userId: userId,
        startDate: selectedDateStart,
        endDate: selectedDateEnd,
      ),
      TaskInstanceService.getNonProductiveInstances(
        userId: userId,
        startDate: selectedDateStart,
        endDate: selectedDateEnd,
      ),
      CalendarQueueService.getQueueItems(
        userId: userId,
        date: _selectedDate,
      ),
      queryRoutineRecordOnce(userId: userId),
    ]);

    final habitCategories = results[0] as List<CategoryRecord>;
    final taskCategories = results[1] as List<CategoryRecord>;
    final allCategories = [...habitCategories, ...taskCategories];
    final completedItems = results[2] as List<ActivityInstanceRecord>;
    final timeLoggedTasks = results[3] as List<ActivityInstanceRecord>;
    final nonProductiveInstances = results[4] as List<ActivityInstanceRecord>;
    final queueItems = results[5] as Map<String, dynamic>;
    final routines = results[6] as List<RoutineRecord>;

    // Debug: Track data sources
    final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    print('[Calendar] Loading events for selected date: $selectedDateStr');
    print('  - Date range: ${DateFormat('yyyy-MM-dd HH:mm').format(selectedDateStart)} to ${DateFormat('yyyy-MM-dd HH:mm').format(selectedDateEnd)}');
    print('  - completedItems: ${completedItems.length}');
    print('  - timeLoggedTasks: ${timeLoggedTasks.length}');
    print('  - nonProductiveInstances: ${nonProductiveInstances.length}');

    // Combine all items into a map to handle duplicates (keyed by instance ID)
    final allItemsMap = <String, ActivityInstanceRecord>{};
    for (final item in completedItems) {
      allItemsMap[item.reference.id] = item;
    }
    for (final item in timeLoggedTasks) {
      allItemsMap[item.reference.id] = item;
    }
    for (final item in nonProductiveInstances) {
      allItemsMap[item.reference.id] = item;
    }

    print('  - allItemsMap total: ${allItemsMap.length}');

    // Separate event lists
    final completedEvents = <CalendarEventData>[];
    final plannedEvents = <CalendarEventData>[];

    // Process all items to generate calendar events
    // Show ALL time logged on the selected date, regardless of completion status
    // This allows users to see partial progress (e.g., 10 min of 1 hour goal)
    for (final item in allItemsMap.values) {
      Color categoryColor;
      if (item.templateCategoryType == 'habit') {
        CategoryRecord? category;
        try {
          category = allCategories.firstWhere(
            (c) => c.reference.id == item.templateCategoryId,
          );
        } catch (e) {
          try {
            category = allCategories.firstWhere(
              (c) => c.name == item.templateCategoryName,
            );
          } catch (e2) {
            // Use default if category not found
          }
        }
        categoryColor =
            category != null ? _parseColor(category.color) : Colors.blue;
      } else if (item.templateCategoryType == 'non_productive') {
        categoryColor = Colors.grey;
      } else {
        // Tasks default to Dark Charcoal/Black
        categoryColor = const Color(0xFF1A1A1A);
      }

      // A. Time Tracked Events - has timeLogSessions
      // Show ALL sessions on the selected date, regardless of completion status
      // This includes time logged from:
      // - Manual time log modal
      // - Timer page
      // - Play button on duration tasks
      // - Right swipe to record time on task cards
      if (item.timeLogSessions.isNotEmpty) {
        // Filter sessions that fall on the selected date
        final sessionsOnDate = item.timeLogSessions.where((session) {
          final sessionStart = session['startTime'] as DateTime;
          final sessionDate = DateTime(
            sessionStart.year,
            sessionStart.month,
            sessionStart.day,
          );
          final selectedDateOnly = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
          );
          return sessionDate.isAtSameMomentAs(selectedDateOnly);
        }).toList();

        print(
            '  - Item ${item.templateName}: ${item.timeLogSessions.length} total sessions, ${sessionsOnDate.length} on selected date ($selectedDateStr)');

        // If we have sessions for this date, show them
        if (sessionsOnDate.isNotEmpty) {
          // Create a calendar event for each session
          // We need to find the original session index in the full timeLogSessions array
          for (int i = 0; i < sessionsOnDate.length; i++) {
            final session = sessionsOnDate[i];
            final sessionStart = session['startTime'] as DateTime;
            final sessionEnd = session['endTime'] as DateTime?;
            if (sessionEnd == null) {
              print('    - Session $i: Skipped (no endTime)');
              continue;
            }

            // Find the original index in the full timeLogSessions array
            int originalSessionIndex = -1;
            for (int j = 0; j < item.timeLogSessions.length; j++) {
              final fullSession = item.timeLogSessions[j];
              final fullSessionStart = fullSession['startTime'] as DateTime;
              if (fullSessionStart.isAtSameMomentAs(sessionStart)) {
                originalSessionIndex = j;
                break;
              }
            }

            var actualSessionEnd = sessionEnd;
            if (actualSessionEnd.difference(sessionStart).inSeconds < 60) {
              actualSessionEnd = sessionStart.add(const Duration(minutes: 1));
            }

            // Validate that times are on the selected date to prevent calendar_view validation errors
            // If event crosses midnight, clamp times to the selected date
            final selectedDateStart = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              0,
              0,
              0,
            );
            final selectedDateEnd =
                selectedDateStart.add(const Duration(days: 1));

            var validStartTime = sessionStart;
            var validEndTime = actualSessionEnd;

            // Clamp start time to selected date
            if (validStartTime.isBefore(selectedDateStart)) {
              validStartTime = selectedDateStart;
            } else if (validStartTime.isAfter(selectedDateEnd) ||
                validStartTime.isAtSameMomentAs(selectedDateEnd)) {
              // Skip events that start after the selected date
              continue;
            }

            // Clamp end time to selected date (but ensure it's after start time)
            if (validEndTime.isAfter(selectedDateEnd)) {
              validEndTime =
                  selectedDateEnd.subtract(const Duration(seconds: 1));
            }

            // Ensure end time is after start time
            if (validEndTime.isBefore(validStartTime) ||
                validEndTime.isAtSameMomentAs(validStartTime)) {
              validEndTime = validStartTime.add(const Duration(minutes: 1));
            }

            // Ensure both times are on the same date as selectedDate
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

            // Only add event if start time is on the selected date
            if (startDateOnly.isAtSameMomentAs(selectedDateOnly)) {
              // Use checkmark for completed items, no checkmark for incomplete
              final prefix = item.status == 'completed' ? '✓ ' : '';

              print(
                  '    - Creating event: ${item.templateName} from ${validStartTime} to ${validEndTime}');

              // Look up category color from loaded categories (same logic as calendar event color)
              String? categoryColorHex;
              if (item.templateCategoryType == 'habit' ||
                  item.templateCategoryType == 'task') {
                CategoryRecord? category;
                try {
                  category = allCategories.firstWhere(
                    (c) => c.reference.id == item.templateCategoryId,
                  );
                } catch (e) {
                  try {
                    category = allCategories.firstWhere(
                      (c) => c.name == item.templateCategoryName,
                    );
                  } catch (e2) {
                    // Category not found, will use fallback
                  }
                }
                if (category != null) {
                  categoryColorHex = category.color;
                } else if (item.templateCategoryColor.isNotEmpty) {
                  // Fallback to instance's cached color if category not found
                  categoryColorHex = item.templateCategoryColor;
                }
              } else if (item.templateCategoryType == 'non_productive') {
                // Non-productive uses grey
                categoryColorHex = '#808080'; // Grey hex
              }

              // Create metadata for editing
              final categoryType = item.templateCategoryType;
              final metadata = CalendarEventMetadata(
                instanceId: item.reference.id,
                sessionIndex:
                    originalSessionIndex >= 0 ? originalSessionIndex : i,
                activityName: item.templateName,
                activityType: categoryType,
                templateId: item.templateId,
                categoryId: item.templateCategoryId.isNotEmpty
                    ? item.templateCategoryId
                    : null,
                categoryName: item.templateCategoryName.isNotEmpty
                    ? item.templateCategoryName
                    : null,
                categoryColorHex: categoryColorHex,
              );

              completedEvents.add(CalendarEventData(
                date: _selectedDate,
                startTime: validStartTime,
                endTime: validEndTime,
                title: '$prefix${item.templateName}',
                color:
                    categoryColor, // Removed _muteColor for better visibility
                description:
                    'Session: ${_formatDuration(validEndTime.difference(validStartTime))}',
                event: metadata.toMap(), // Store metadata for editing
              ));
            }
          }
        }
      }
      // Note: We no longer handle legacy timer events or binary completions separately
      // All time logging should use timeLogSessions for consistency
    }

    // Sort all completed events by end time (descending) for backward cascading
    // This ensures items completed at the same time cascade backwards from completion time
    completedEvents.sort((a, b) {
      if (a.endTime == null || b.endTime == null) return 0;
      // Sort descending by end time, then by start time if end times are equal
      final endCompare = b.endTime!.compareTo(a.endTime!);
      if (endCompare != 0) return endCompare;
      if (a.startTime == null || b.startTime == null) return 0;
      return b.startTime!.compareTo(a.startTime!);
    });

    // Apply backward cascading logic to prevent overlaps
    // Events cascade backwards from their completion time
    DateTime? earliestStartTime; // Track the earliest start time we've seen
    final cascadedEvents = <CalendarEventData>[];
    for (final event in completedEvents) {
      if (event.startTime == null || event.endTime == null) continue;

      DateTime startTime = event.startTime!;
      DateTime endTime = event.endTime!;
      final duration = endTime.difference(startTime);

      // If this event's end time is after the earliest start time we've seen,
      // shift it backwards (earlier) so it ends where the previous one starts
      if (earliestStartTime != null && endTime.isAfter(earliestStartTime)) {
        endTime = earliestStartTime;
        startTime = endTime.subtract(duration);
      }

      // Update earliest start time (most backward/earliest time we've seen)
      if (earliestStartTime == null || startTime.isBefore(earliestStartTime)) {
        earliestStartTime = startTime;
      }

      // Ensure date matches selected date (cascading might shift times but date should remain)
      cascadedEvents.add(CalendarEventData(
        date: _selectedDate,
        startTime: startTime,
        endTime: endTime,
        title: event.title,
        color: event.color,
        description: event.description,
        event: event.event, // Preserve metadata during cascading
      ));
    }

    // Assign sorted completed events
    _sortedCompletedEvents = cascadedEvents;
    // Note: cascadedEvents are processed in reverse order (end time desc).
    // For label collision, we want them sorted by START time ascending.
    _sortedCompletedEvents.sort((a, b) => a.startTime!.compareTo(b.startTime!));

    // Debug: Track event creation
    print('[Calendar] Event processing for $selectedDateStr:');
    print('  - completedEvents created: ${completedEvents.length}');
    print('  - cascadedEvents: ${cascadedEvents.length}');
    print('  - _sortedCompletedEvents: ${_sortedCompletedEvents.length}');

    // Planned items were already fetched in the batch query above
    final plannedItems =
        List<ActivityInstanceRecord>.from(queueItems['planned'] ?? []);

    // Merge optimistic instances that should appear in planned section
    final selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    for (final optimisticInstance in _optimisticInstances.values) {
      // Check if optimistic instance should appear in planned section
      if (optimisticInstance.dueDate != null &&
          optimisticInstance.dueTime != null &&
          optimisticInstance.dueTime!.isNotEmpty) {
        final dueDateOnly = DateTime(
          optimisticInstance.dueDate!.year,
          optimisticInstance.dueDate!.month,
          optimisticInstance.dueDate!.day,
        );
        if (dueDateOnly.isAtSameMomentAs(selectedDateOnly)) {
          // Add to planned items if not already present (by instance ID)
          final exists = plannedItems.any(
              (item) => item.reference.id == optimisticInstance.reference.id);
          if (!exists) {
            plannedItems.add(optimisticInstance);
          }
        }
      }
    }

    // Process planned items
    // Filter to only include items with a dueTime (only items with due times should appear in planned section)
    final plannedItemsWithTime = plannedItems
        .where((item) => item.dueTime != null && item.dueTime!.isNotEmpty)
        .toList();
    
    print('[Calendar] Planned items for $selectedDateStr:');
    print('  - Total planned items: ${plannedItems.length}');
    print('  - Planned items with time: ${plannedItemsWithTime.length}');

    // Items already scheduled at explicit times (exclude from routine-duration computation)
    final explicitlyScheduledTemplateIds = <String>{
      ...plannedItemsWithTime.map((i) => i.templateId).whereType<String>(),
    };

    // Resolve planned duration per instance based on:
    // time-target -> target minutes
    // else -> activity estimate (if enabled+present) -> global default (if enabled) -> none
    final plannedDurationByInstanceId = userId.isEmpty
        ? <String, int?>{}
        : await PlannedDurationResolver.resolveDurationMinutesForInstances(
            userId: userId,
            instances: plannedItemsWithTime,
          );

    for (final item in plannedItemsWithTime) {
      Color categoryColor;
      if (item.templateCategoryType == 'habit') {
        CategoryRecord? category;
        try {
          category = allCategories.firstWhere(
            (c) => c.reference.id == item.templateCategoryId,
          );
        } catch (e) {
          try {
            category = allCategories.firstWhere(
              (c) => c.name == item.templateCategoryName,
            );
          } catch (e2) {
            // Use default if category not found
          }
        }
        categoryColor =
            category != null ? _parseColor(category.color) : Colors.blue;
      } else if (item.templateCategoryType == 'non_productive') {
        categoryColor = Colors.grey;
      } else {
        // Tasks default to Dark Charcoal/Black
        categoryColor = const Color(0xFF1A1A1A);
      }

      // Parse due time - no need for else block since we filtered out items without dueTime
      DateTime startTime = _parseDueTime(item.dueTime!, _selectedDate);

      final instanceId = item.reference.id;
      final durationMinutes = plannedDurationByInstanceId[instanceId];

      final metadata = CalendarEventMetadata(
        instanceId: instanceId,
        sessionIndex: -1,
        activityName: item.templateName,
        activityType: item.templateCategoryType,
        templateId: item.templateId,
        categoryId:
            item.templateCategoryId.isNotEmpty ? item.templateCategoryId : null,
        categoryName: item.templateCategoryName.isNotEmpty
            ? item.templateCategoryName
            : null,
        categoryColorHex: item.templateCategoryColor.isNotEmpty
            ? item.templateCategoryColor
            : null,
      );

      // If duration is null, render as a due-time marker line (very thin tile).
      final isDueMarker = durationMinutes == null || durationMinutes <= 0;
      final endTime = isDueMarker
          ? startTime.add(const Duration(minutes: 1))
          : startTime.add(Duration(minutes: durationMinutes));

      plannedEvents.add(CalendarEventData(
        date: _selectedDate,
        startTime: startTime,
        endTime: endTime,
        title: item.templateName,
        color: categoryColor,
        description: isDueMarker
            ? null
            : _formatDuration(Duration(minutes: durationMinutes)),
        event: {
          ...metadata.toMap(),
          'isDueMarker': isDueMarker,
        },
      ));
    }

    // Add routines with due time as planned events (single block = sum of item durations).
    // Excludes items already scheduled explicitly in the planned list.
    if (userId.isNotEmpty && routines.isNotEmpty) {
      final routinePlanned =
          await RoutinePlannedCalendarService.getPlannedRoutineEvents(
        userId: userId,
        date: _selectedDate,
        routines: routines,
        excludedTemplateIds: explicitlyScheduledTemplateIds,
      );

      for (final r in routinePlanned) {
        final startTime = _parseDueTime(r.dueTime, _selectedDate);
        final isDueMarker =
            r.durationMinutes == null || r.durationMinutes! <= 0;
        final endTime = isDueMarker
            ? startTime.add(const Duration(minutes: 1))
            : startTime.add(Duration(minutes: r.durationMinutes!));

        final metadata = CalendarEventMetadata(
          instanceId: 'routine:${r.routineId}',
          sessionIndex: -1,
          activityName: r.name,
          activityType: 'routine',
          templateId: null,
          categoryId: null,
          categoryName: null,
          categoryColorHex: null,
        );

        plannedEvents.add(CalendarEventData(
          date: _selectedDate,
          startTime: startTime,
          endTime: endTime,
          title: 'Routine: ${r.name}',
          color: Colors.deepPurple,
          description: isDueMarker
              ? null
              : _formatDuration(Duration(minutes: r.durationMinutes!)),
          event: {
            ...metadata.toMap(),
            'routineId': r.routineId,
            'isDueMarker': isDueMarker,
          },
        ));
      }
    }

    // Sort planned events by start time and assign
    plannedEvents.sort((a, b) {
      if (a.startTime == null || b.startTime == null) return 0;
      return a.startTime!.compareTo(b.startTime!);
    });
    _sortedPlannedEvents = plannedEvents;
    
    print('[Calendar] Planned events for $selectedDateStr: ${plannedEvents.length}');

    // Detect overlaps in the planned schedule (for prominent conflict highlighting)
    final overlapInfo = _computePlannedOverlaps(plannedEvents);
    _plannedOverlapPairCount = overlapInfo.pairCount;
    _plannedOverlappedEventIds
      ..clear()
      ..addAll(overlapInfo.overlappedIds);
    _plannedOverlapGroups = overlapInfo.groups;

    // Add legacy/timer events if any (optional, maybe filter by date?)
    // For now, skipping legacy complex timer logic for past dates to keep it simple,
    // or we can add them if they match date.
    // The original code loaded them all. We should filter.
    // Simplifying for now to focus on the requested feature.

    // Clear and update controllers all at once to prevent flicker
    // Old events stay visible until new ones are ready
    _completedEventController.removeWhere((e) => true);
    _plannedEventController.removeWhere((e) => true);
    _completedEventController.addAll(cascadedEvents);
    _plannedEventController.addAll(plannedEvents);

    // Debug: Track controller updates
    print('[Calendar] Controller updates:');
    print(
        '  - _completedEventController events: ${_completedEventController.events.length}');
    print(
        '  - _plannedEventController events: ${_plannedEventController.events.length}');

    // Force rebuild to show new events
    if (mounted) setState(() {});
    } finally {
      // Always reset loading state
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
        });
      }
    }
  }

  /// Parse dueTime string (HH:mm) to DateTime for target date
  DateTime _parseDueTime(String dueTime, DateTime targetDate) {
    final timeOfDay = TimeUtils.stringToTimeOfDay(dueTime);
    if (timeOfDay == null) {
      return DateTime(targetDate.year, targetDate.month, targetDate.day, 9, 0);
    }
    return DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      timeOfDay.hour,
      timeOfDay.minute,
    );
  }

  /// Parse color string (hex) to Color
  Color _parseColor(String colorString) {
    try {
      return fromCssColor(colorString);
    } catch (e) {
      return Colors.blue; // Default color
    }
  }

  String? _stableEventId(CalendarEventData event) {
    final metadata = CalendarEventMetadata.fromMap(event.event);
    final id = metadata?.instanceId;
    if (id != null && id.isNotEmpty) return id;
    if (event.startTime == null || event.endTime == null) return null;
    return '${event.title}_${event.startTime!.millisecondsSinceEpoch}_${event.endTime!.millisecondsSinceEpoch}';
  }

  _PlannedOverlapInfo _computePlannedOverlaps(List<CalendarEventData> planned) {
    final events = planned
        .where((e) => e.startTime != null && e.endTime != null)
        .toList()
      ..sort((a, b) => a.startTime!.compareTo(b.startTime!));

    int overlapPairs = 0;
    final overlappedIds = <String>{};
    final groups = <_PlannedOverlapGroup>[];

    // Active list for accurate pair counting
    final active = <CalendarEventData>[];

    // Group tracking (overlap chains)
    final currentGroup = <CalendarEventData>[];
    DateTime? currentGroupStart;
    DateTime? currentGroupEnd;

    void finalizeGroupIfNeeded() {
      if (currentGroup.length <= 1) {
        currentGroup.clear();
        currentGroupStart = null;
        currentGroupEnd = null;
        return;
      }
      final start = currentGroupStart!;
      final end = currentGroupEnd!;
      groups.add(
        _PlannedOverlapGroup(
          start: start,
          end: end,
          events: List.of(currentGroup),
        ),
      );
      for (final e in currentGroup) {
        final id = _stableEventId(e);
        if (id != null) overlappedIds.add(id);
      }
      currentGroup.clear();
      currentGroupStart = null;
      currentGroupEnd = null;
    }

    for (final e in events) {
      final start = e.startTime!;
      final end = e.endTime!;

      // Remove inactive events (end <= start doesn't overlap)
      active.removeWhere((a) => !a.endTime!.isAfter(start));

      if (active.isNotEmpty) {
        overlapPairs += active.length;
        final id = _stableEventId(e);
        if (id != null) overlappedIds.add(id);
        for (final a in active) {
          final aid = _stableEventId(a);
          if (aid != null) overlappedIds.add(aid);
        }
      }

      active.add(e);

      // Overlap group (chain-based)
      if (currentGroup.isEmpty) {
        currentGroup.add(e);
        currentGroupStart = start;
        currentGroupEnd = end;
      } else {
        final groupEnd = currentGroupEnd!;
        if (start.isBefore(groupEnd)) {
          currentGroup.add(e);
          if (end.isAfter(groupEnd)) currentGroupEnd = end;
        } else {
          finalizeGroupIfNeeded();
          currentGroup.add(e);
          currentGroupStart = start;
          currentGroupEnd = end;
        }
      }
    }
    finalizeGroupIfNeeded();

    return _PlannedOverlapInfo(
      pairCount: overlapPairs,
      overlappedIds: overlappedIds,
      groups: groups,
    );
  }

  bool _isSelectedDateToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    return selected.isAtSameMomentAs(today);
  }

  Future<void> _showOverlapDetailsSheet() async {
    if (_plannedOverlapGroups.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const Text(
                  'Schedule overlaps',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'These planned items overlap in time. Adjust due times to resolve.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _plannedOverlapGroups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final group = _plannedOverlapGroups[index];
                      final timeRange =
                          '${DateFormat('HH:mm').format(group.start)}–${DateFormat('HH:mm').format(group.end)}';

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.red.withOpacity(0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: Colors.red),
                                const SizedBox(width: 8),
                                Text(
                                  timeRange,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...group.events.map((e) {
                              final st = e.startTime!;
                              final et = e.endTime!;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      margin: const EdgeInsets.only(top: 4),
                                      decoration: BoxDecoration(
                                        color: e.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '${DateFormat('HH:mm').format(st)}–${DateFormat('HH:mm').format(et)}  ${e.title}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlapBanner() {
    final isToday = _isSelectedDateToday();
    final headline = isToday
        ? '${_plannedOverlapPairCount} overlap${_plannedOverlapPairCount == 1 ? '' : 's'} in today\'s schedule'
        : '${_plannedOverlapPairCount} overlap${_plannedOverlapPairCount == 1 ? '' : 's'} in this day\'s schedule';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Material(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _showOverlapDetailsSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to review conflicts',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.red),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Calculate horizontal offset for floating labels to avoid overlap
  double _calculateLabelOffset(
    CalendarEventData event,
    List<CalendarEventData> sortedEvents,
    bool isCompletedList,
  ) {
    if (event.startTime == null || event.endTime == null) return 0.0;

    final index = sortedEvents.indexOf(event);
    if (index <= 0) return 0.0;

    // Track occupied end pixels for each "lane"
    // lane 0 is default (offset 0). lane 1 is offset 60, etc.
    final laneFreeY = <double>[];

    final heightPerMinute = _calculateHeightPerMinute();

    // Helper to get Y pixel from datetime (minutes from midnight)
    double getPixelY(DateTime time) {
      final minutes = time.hour * 60 + time.minute + time.second / 60.0;
      return minutes * heightPerMinute;
    }

    for (int i = 0; i <= index; i++) {
      final e = sortedEvents[i];
      if (e.startTime == null || e.endTime == null) continue;

      final startY = getPixelY(e.startTime!);
      final duration = e.endTime!.difference(e.startTime!);
      final durationMinutes = duration.inSeconds / 60.0;

      // Replicate layout logic from _buildEventTile
      final isThin = duration.inSeconds < 60 && isCompletedList;
      final timeBoxHeight = durationMinutes * heightPerMinute;
      final cappedHeight = math.max(1.0, timeBoxHeight);
      final actualHeight = isThin
          ? 3.0.clamp(1.0, cappedHeight)
          : timeBoxHeight.clamp(1.0, double.infinity);
      final hasFloatingLabel = actualHeight < 24.0;

      // Calculate occupied range
      // Floating label is approx 28px above start
      final occupiedTop = hasFloatingLabel ? startY - 28.0 : startY;
      final occupiedBottom = startY + actualHeight;

      // Find first available lane
      int assignedLane = -1;
      for (int l = 0; l < laneFreeY.length; l++) {
        // Check if lane is free above occupiedTop
        // Use a small buffer (2px) to prevent touching
        if (laneFreeY[l] + 2.0 <= occupiedTop) {
          assignedLane = l;
          break;
        }
      }

      if (assignedLane == -1) {
        laneFreeY.add(occupiedBottom);
        assignedLane = laneFreeY.length - 1;
      } else {
        laneFreeY[assignedLane] = occupiedBottom;
      }

      // If this is our target event, return offset
      if (i == index) {
        if (hasFloatingLabel) {
          // Shift right by 80px per lane (enough for "Eat fruits" label)
          return assignedLane * 80.0;
        }
        return 0.0;
      }
    }
    return 0.0;
  }

  /// Build event tile
  Widget _buildEventTile(CalendarEventData event, bool isCompleted) {
    if (event.startTime == null || event.endTime == null) {
      return const SizedBox.shrink();
    }

    // Calculate label offset
    final eventList =
        isCompleted ? _sortedCompletedEvents : _sortedPlannedEvents;
    final labelOffset = _calculateLabelOffset(event, eventList, isCompleted);

    final duration = event.endTime!.difference(event.startTime!);
    final isNonProductive = event.title.startsWith('NP:');
    final rawEvent = event.event;
    final isDueMarker = rawEvent is Map && (rawEvent['isDueMarker'] == true);
    final isThinLine = duration.inSeconds < 60 && (isCompleted || isDueMarker);

    final durationMinutes = duration.inSeconds / 60.0;
    final timeBoxHeight = durationMinutes * _calculateHeightPerMinute();
    final cappedHeight = math.max(1.0, timeBoxHeight);
    final actualTimeBoxHeight = isThinLine
        ? 3.0.clamp(1.0, cappedHeight)
        : timeBoxHeight.clamp(1.0, double.infinity);

    final labelFitsInside = actualTimeBoxHeight >= 24.0;

    // Extract metadata from event once for reuse
    final metadata = CalendarEventMetadata.fromMap(event.event);
    final eventId = _stableEventId(event);
    final isConflict = !isCompleted &&
        eventId != null &&
        _plannedOverlappedEventIds.contains(eventId);

    final timeBox = _buildTimeBox(
      event,
      actualTimeBoxHeight,
      isCompleted,
      isNonProductive,
      isConflict: isConflict,
    );

    final label = labelFitsInside
        ? _buildInlineLabel(event, isCompleted, isNonProductive)
        : _buildFloatingLabel(event, isCompleted, isNonProductive);

    // Handler for long-press on time box only
    void handleLongPress() {
      // Only completed items should allow editing logged sessions
      if (isCompleted && metadata != null && metadata.sessionIndex >= 0) {
        _showEditEntryDialog(metadata: metadata);
      }
    }

    // Wrap only the time box with GestureDetector, not the label
    final timeBoxWithGesture = GestureDetector(
      onLongPress: handleLongPress,
      child: timeBox,
    );

    if (isThinLine) {
      return OverflowBox(
        minHeight: 0,
        maxHeight: double.infinity,
        alignment: Alignment.centerLeft,
        child: Container(
          height: actualTimeBoxHeight,
          constraints: BoxConstraints(
            minHeight: actualTimeBoxHeight,
            minWidth: 0,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: timeBoxWithGesture),
              Positioned(
                left: labelOffset,
                top: -24.0,
                child: label,
              ),
            ],
          ),
        ),
      );
    }

    return OverflowBox(
      minHeight: 0,
      maxHeight: double.infinity,
      alignment: Alignment.topLeft,
      child: Container(
        height: actualTimeBoxHeight,
        constraints: BoxConstraints(
          minHeight: actualTimeBoxHeight,
          minWidth: 0,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: timeBoxWithGesture),
            Positioned(
              left: labelFitsInside ? 4.0 : labelOffset,
              top: labelFitsInside ? 4.0 : -28.0,
              child: label,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeBox(CalendarEventData event, double height, bool isCompleted,
      bool isNonProductive,
      {required bool isConflict}) {
    // Detect non-productive tasks: check parameter OR grey color
    final isNonProd = isNonProductive || event.color == Colors.grey;

    // For non-productive tasks, use minimalist diagonal stripe pattern
    if (isNonProd) {
      // Light base color for non-productive tasks
      final baseColor = Colors.grey.shade100;
      final stripeColor = Colors.grey.shade300; // Slightly lighter for subtlety
      final borderColor = Colors.grey.shade400; // Softer border

      return Container(
        constraints: const BoxConstraints(
          minHeight: 1.0,
          minWidth: 0,
        ),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(4.0),
          border: Border.all(
            color: borderColor,
            width: 1.0, // Thinner border for minimalism
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4.0),
          child: SizedBox.expand(
            child: CustomPaint(
              painter: _DiagonalStripePainter(
                stripeColor: stripeColor,
                stripeWidth: 3.5, // Thicker lines (was 2.0)
                spacing:
                    16.0, // Much more spacing (was 6.0) for minimalist look
              ),
            ),
          ),
        ),
      );
    }

    // For regular tasks and habits, use solid color
    // For completed items, make them solid and distinct (0.6 opacity)
    // For planned items, keep them lighter (0.3 opacity)
    Color boxColor;
    if (isCompleted) {
      boxColor = event.color.withOpacity(0.6); // Solid color for completed
    } else {
      // Planned items: increased opacity for better visibility and contrast with text
      boxColor = event.color.withOpacity(0.3);
    }

    final conflictBorderColor = Colors.red.shade700;
    final baseBorderColor = event.color;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          constraints: const BoxConstraints(
            minHeight: 1.0,
            minWidth: 0,
          ),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(4.0),
            border: Border.all(
              color: isConflict ? conflictBorderColor : baseBorderColor,
              width: isConflict ? 2.0 : 1.0,
            ),
            boxShadow: isConflict
                ? [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        ),
        if (isConflict)
          ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: CustomPaint(
              painter: _DiagonalStripePainter(
                stripeColor: Colors.red.withOpacity(0.18),
                stripeWidth: 3.0,
                spacing: 7.0,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInlineLabel(
    CalendarEventData event,
    bool isCompleted,
    bool isNonProductive,
  ) {
    // Determine text color based on background luminance
    // Completed events are muted (opacity 0.4), but planned are solid/transparent blocks
    // We base it on the "perceived" background color or the event color itself

    Color textColor;
    if (isNonProductive || event.color == Colors.grey) {
      textColor = Colors.black87;
    } else if (event.color == const Color(0xFF1A1A1A)) {
      // Task color
      textColor = Colors.white;
    } else {
      // Habits - check luminance
      // If color is dark, use white text. If light, use black text.
      textColor =
          event.color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 12.0,
        minWidth: 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.title.isNotEmpty ? event.title : ' ',
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          if (event.description != null && event.description!.isNotEmpty)
            Text(
              event.description!,
              style: TextStyle(
                color: textColor.withOpacity(0.8),
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
        ],
      ),
    );
  }

  Widget _buildFloatingLabel(
    CalendarEventData event,
    bool isCompleted,
    bool isNonProductive,
  ) {
    final labelColor = event.color.withOpacity(0.9);
    Color textColor;
    if (isNonProductive || event.color == Colors.grey) {
      textColor = Colors.black87;
    } else if (event.color == const Color(0xFF1A1A1A)) {
      // Task color
      textColor = Colors.white;
    } else {
      // Habits - check luminance
      textColor =
          event.color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 24.0,
        minWidth: 40.0,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: labelColor,
          borderRadius: BorderRadius.circular(4.0),
          border: isCompleted
              ? Border.all(
                  color: event.color, // Solid border
                  width: 1.5,
                )
              : null,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4.0,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          event.title.isNotEmpty ? event.title : ' ',
          style: TextStyle(
            color: textColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: isCompleted
                ? null
                : [
                    Shadow(
                      offset: const Offset(0, 0),
                      blurRadius: 2.0,
                      color: Colors.black.withOpacity(0.5),
                    ),
                  ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  double _calculateHeightPerMinute() {
    return _baseHeightPerMinute * _verticalZoom;
  }

  void _zoomIn() {
    final oldHeight = _calculateHeightPerMinute();
    final newScale =
        (_verticalZoom + _zoomStep).clamp(_minVerticalZoom, _maxVerticalZoom);

    if ((newScale - _verticalZoom).abs() < 0.001) return;

    // Calculate new offset to preserve top position
    final newHeight = _baseHeightPerMinute * newScale;
    final ratio = newHeight / oldHeight;
    _initialScrollOffset = _currentScrollOffset * ratio;

    setState(() {
      _verticalZoom = newScale;
    });
  }

  void _zoomOut() {
    final oldHeight = _calculateHeightPerMinute();
    final newScale =
        (_verticalZoom - _zoomStep).clamp(_minVerticalZoom, _maxVerticalZoom);

    if ((newScale - _verticalZoom).abs() < 0.001) return;

    // Calculate new offset to preserve top position
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

  // Handle zoom gesture start - capture initial values
  void _onScaleStart(ScaleStartDetails details) {
    _initialZoomOnGestureStart = _verticalZoom;
    _initialScaleOnGestureStart = 1.0; // Scale starts at 1.0
  }

  // Handle vertical pinch gestures - use relative scale change
  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_initialZoomOnGestureStart == null ||
        _initialScaleOnGestureStart == null) {
      return; // Gesture not properly initialized
    }

    // Calculate relative scale change from gesture start
    final scaleChange = details.scale / _initialScaleOnGestureStart!;

    // Apply scale change to initial zoom (not current zoom)
    final oldHeight = _calculateHeightPerMinute();
    final newZoom = _initialZoomOnGestureStart! * scaleChange;
    final clampedZoom = newZoom.clamp(_minVerticalZoom, _maxVerticalZoom);

    if ((clampedZoom - _verticalZoom).abs() < 0.001) return;

    // Calculate new offset
    final newHeight = _baseHeightPerMinute * clampedZoom;
    final ratio = newHeight / oldHeight;
    _initialScrollOffset = _currentScrollOffset * ratio;

    setState(() {
      _verticalZoom = clampedZoom;
    });
  }

  // Handle zoom gesture end - reset tracking
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
            icon: const Icon(Icons.refresh),
            onPressed: _resetZoom,
            tooltip: 'Reset Zoom',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showManualEntryDialog,
        heroTag: 'add_entry',
        child: const Icon(Icons.add),
        tooltip: 'Log Time Entry',
      ),
      body: Stack(
        children: [
          Container(
            color: Colors.white,
            child: Column(
              children: [
                // Header: Date Navigation and Toggle
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Date Navigation Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => _changeDate(-1),
                          ),
                          GestureDetector(
                            onTap: _resetDate,
                            child: Text(
                              DateFormat('EEEE, MMM d, y')
                                  .format(_selectedDate),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => _changeDate(1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // View Toggle (Planned vs Completed)
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (!_showPlanned) {
                                    setState(() {
                                      _showPlanned = true;
                                    });
                                    _saveTabState(true);
                                  }
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _showPlanned
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: _showPlanned
                                        ? [
                                            BoxShadow(
                                              color:
                                                  Colors.black.withOpacity(0.1),
                                              blurRadius: 2,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Planned',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: _showPlanned
                                            ? Colors.blue.shade700
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (_showPlanned) {
                                    setState(() {
                                      _showPlanned = false;
                                    });
                                    _saveTabState(false);
                                  }
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: !_showPlanned
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: !_showPlanned
                                        ? [
                                            BoxShadow(
                                              color:
                                                  Colors.black.withOpacity(0.1),
                                              blurRadius: 2,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Completed',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: !_showPlanned
                                            ? Colors.green.shade700
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Prominent planned-schedule conflict banner
                if (_showPlanned && _plannedOverlapPairCount > 0)
                  _buildOverlapBanner(),

                // Calendar Body
                Expanded(
                  child: GestureDetector(
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollUpdateNotification &&
                            notification.metrics.axis == Axis.vertical) {
                          _currentScrollOffset = notification.metrics.pixels;
                        }
                        return false;
                      },
                      child: GestureDetector(
                        // Block horizontal drag gestures to prevent date navigation via swipe
                        onHorizontalDragStart: (details) {
                          // Absorb the gesture - do nothing
                        },
                        onHorizontalDragUpdate: (details) {
                          // Absorb the gesture - do nothing
                        },
                        onHorizontalDragEnd: (details) {
                          // Absorb the gesture - do nothing
                        },
                        child: Listener(
                          onPointerDown: (event) {
                            // Capture the local position of the tap within the viewport
                            _lastTapDownPosition = event.localPosition;
                          },
                          child: Stack(
                            children: [
                              // DayView is wrapped in a keyed widget to force rebuild when date changes
                              // The GlobalKey is recreated in _changeDate() to ensure proper date updates
                              DayView(
                                // Use unique key to force rebuild when switching views or dates OR zooming
                                // Key is recreated in _changeDate() to ensure DayView reflects selected date
                                key: _dayViewKey,
                                scrollOffset: _initialScrollOffset,
                                controller: _showPlanned
                                    ? _plannedEventController
                                    : _completedEventController,
                                // initialDay sets the date - this should update when _selectedDate changes
                                initialDay: _selectedDate,
                                heightPerMinute: _calculateHeightPerMinute(),
                                backgroundColor: Colors.white,
                                timeLineWidth: 50,
                                hourIndicatorSettings: HourIndicatorSettings(
                                  color: Colors.grey.shade300,
                                ),
                                eventTileBuilder: (date, events, a, b, c) {
                                  return _buildEventTile(
                                      events.first, !_showPlanned);
                                },
                                dayTitleBuilder: (date) {
                                  return const SizedBox
                                      .shrink(); // Hide default header
                                },
                                onDateLongPress: (date) {
                              // Calculate precise time from touch position details
                              // The 'date' argument from onDateLongPress is imprecise (snaps to hour).
                              // use _lastTapDownPosition + scrollOffset to get pixels from top.
                              if (_lastTapDownPosition != null) {
                                // tapY is relative to the Listener widget, which wraps the DayView
                                // The Listener is at the top of the Expanded widget (below the header)
                                // So tapY is already relative to the DayView's content area
                                final double tapY = _lastTapDownPosition!.dy;

                                // Get the actual scroll position from DayView if possible
                                // Otherwise use the tracked _currentScrollOffset
                                double scrollOffset = _currentScrollOffset;

                                // Try to get scroll position directly from DayView state
                                try {
                                  final dayViewState = _dayViewKey.currentState;
                                  if (dayViewState != null) {
                                    // Access scrollController if available
                                    final dynamic state = dayViewState;
                                    if (state.scrollController != null) {
                                      scrollOffset = state
                                          .scrollController.position.pixels;
                                    }
                                  }
                                } catch (e) {
                                  // Fallback to tracked offset
                                }

                                // Calculate total pixels from top of timeline (midnight)
                                // tapY is the position in the visible viewport
                                // scrollOffset is how far we've scrolled from the top
                                final double totalPixels = tapY + scrollOffset;
                                final double totalMinutes =
                                    totalPixels / _calculateHeightPerMinute();

                                // Convert total minutes to HH:MM on the selected date
                                final int totalMinutesInt =
                                    totalMinutes.toInt();
                                final int hours = totalMinutesInt ~/ 60;
                                final int minutes = totalMinutesInt % 60;

                                // Round minutes to nearest 5
                                final int remainder = minutes % 5;
                                final int roundedMinute = remainder >= 2.5
                                    ? minutes + (5 - remainder)
                                    : minutes - remainder;

                                final startTime = DateTime(
                                  _selectedDate.year,
                                  _selectedDate.month,
                                  _selectedDate.day,
                                  hours,
                                  0, // Start from 0 minutes and add rounded minutes
                                ).add(Duration(minutes: roundedMinute));

                                final endTime = startTime.add(
                                    Duration(minutes: _defaultDurationMinutes));

                                _showManualEntryDialog(
                                  startTime: startTime,
                                  endTime: endTime,
                                );
                              } else {
                                // Fallback to old logic if no tap position (unlikely)
                                final minute = date.minute;
                                final remainder = minute % 5;
                                final roundedMinute = remainder >= 2.5
                                    ? minute + (5 - remainder)
                                    : minute - remainder;

                                final startTime = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  date.hour,
                                  roundedMinute,
                                );
                                final endTime = startTime.add(
                                    Duration(minutes: _defaultDurationMinutes));

                                _showManualEntryDialog(
                                  startTime: startTime,
                                  endTime: endTime,
                                );
                              }
                            },
                          ),
                              // Loading overlay
                              if (_isLoadingEvents)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.white.withOpacity(0.7),
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Time breakdown FAB positioned at bottom left
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: _showTimeBreakdownChart,
              heroTag: 'pie_chart',
              child: const Icon(Icons.pie_chart),
              tooltip: 'Time Breakdown',
              backgroundColor: FlutterFlowTheme.of(context).primary,
            ),
          ),
        ],
      ),
    );
  }
}
