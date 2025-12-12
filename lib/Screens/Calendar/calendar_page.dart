import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:habit_tracker/Helper/backend/calendar_queue_service.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:from_css_color/from_css_color.dart';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadEvents();
  }

  void _resetDate() {
    setState(() {
      _selectedDate = DateTime.now();
    });
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    // Clear existing events
    _completedEventController.removeWhere((e) => true);
    _plannedEventController.removeWhere((e) => true);

    // Get categories for color lookup
    final userId = currentUserUid;
    final habitCategories = await queryHabitCategoriesOnce(userId: userId);
    final taskCategories = await queryTaskCategoriesOnce(userId: userId);
    final allCategories = [...habitCategories, ...taskCategories];

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

    // 1. Fetch completed items
    final completedItems = await CalendarQueueService.getCompletedItems(
      userId: userId,
      date: _selectedDate,
    );

    // 2. Fetch time logged items (filtered by date)
    final timeLoggedTasks = await TaskInstanceService.getTimeLoggedTasks(
      userId: userId,
      startDate: selectedDateStart,
      endDate: selectedDateEnd,
    );
    final nonProductiveInstances =
        await TaskInstanceService.getNonProductiveInstances(
      userId: userId,
      startDate: selectedDateStart,
      endDate: selectedDateEnd,
    );

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

    // Separate event lists
    final completedEvents = <CalendarEventData>[];
    final plannedEvents = <CalendarEventData>[];

    // Process all items to generate calendar events
    for (final item in allItemsMap.values) {
      if (item.completedAt == null) continue;

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

      final categoryColor =
          category != null ? _parseColor(category.color) : Colors.grey;

      // A. Time Tracked Events (Priority) - has timeLogSessions
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

        // If we have sessions for this date, show them
        if (sessionsOnDate.isNotEmpty) {
          // Create a calendar event for each session
          for (final session in sessionsOnDate) {
            final sessionStart = session['startTime'] as DateTime;
            final sessionEnd = session['endTime'] as DateTime?;
            if (sessionEnd == null) continue;

            completedEvents.add(CalendarEventData(
              date: _selectedDate,
              startTime: sessionStart,
              endTime: sessionEnd,
              title: '✓ ${item.templateName}',
              color: _muteColor(categoryColor),
              description:
                  'Session: ${_formatDuration(sessionEnd.difference(sessionStart))}',
            ));
          }
          continue; // Skip to next item - processed as time logged event
        }
        // If no sessions on this date, fall through to check legacy/default completion logic
        // This handles cases where task was completed today but time logs were on other days
      }

      // B. Legacy/Simple Timer Events - has accumulatedTime and timerStartTime
      if (item.accumulatedTime > 0 && item.timerStartTime != null) {
        final duration = Duration(milliseconds: item.accumulatedTime);
        final endTime = item.completedAt!;
        final startTime = endTime.subtract(duration);

        completedEvents.add(CalendarEventData(
          date: _selectedDate,
          startTime: startTime,
          endTime: endTime,
          title: '✓ ${item.templateName}',
          color: _muteColor(categoryColor),
          description: 'Timer: ${_formatDuration(duration)}',
        ));
        continue; // Skip to next item - already processed
      }

      // C. Non-Tracked Events (Binary / Quantity) - default duration
      // Calculate default duration: 10 minutes total, adjusted by quantity
      Duration defaultDuration;
      if (item.templateTrackingType == 'qty' && item.templateTarget != null) {
        // Quantity-based: (10 minutes / target) * current
        final targetQty = _getTargetMinutes(item.templateTarget);
        final currentQty = _getCurrentValue(item.currentValue);
        if (targetQty > 0 && currentQty > 0) {
          final minutesPerUnit = 10.0 / targetQty;
          final totalMinutes = (minutesPerUnit * currentQty).round();
          defaultDuration = Duration(minutes: totalMinutes.clamp(1, 60));
        } else {
          defaultDuration = const Duration(minutes: 10);
        }
      } else {
        // Binary (todo) - default 10 minutes
        defaultDuration = const Duration(minutes: 10);
      }

      final endTime = item.completedAt!;
      final startTime = endTime.subtract(defaultDuration);

      completedEvents.add(CalendarEventData(
        date: _selectedDate,
        startTime: startTime,
        endTime: endTime,
        title: '✓ ${item.templateName}',
        color: _muteColor(categoryColor),
        description: 'Completed',
      ));
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

      cascadedEvents.add(CalendarEventData(
        date: event.date,
        startTime: startTime,
        endTime: endTime,
        title: event.title,
        color: event.color,
        description: event.description,
      ));
    }

    // Assign sorted completed events
    _sortedCompletedEvents = cascadedEvents;
    // Note: cascadedEvents are processed in reverse order (end time desc). 
    // For label collision, we want them sorted by START time ascending.
    _sortedCompletedEvents.sort((a, b) => a.startTime!.compareTo(b.startTime!));

    // Get planned items for selected date
    final queueItems = await CalendarQueueService.getQueueItems(
      userId: userId,
      date: _selectedDate,
    );
    final plannedItems = queueItems['planned'] ?? [];

    // Process planned items
    for (final item in plannedItems) {
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

      final categoryColor =
          category != null ? _parseColor(category.color) : Colors.blue;

      // Parse due time
      DateTime startTime;
      if (item.dueTime != null && item.dueTime!.isNotEmpty) {
        startTime = _parseDueTime(item.dueTime!, _selectedDate);
      } else {
        // If no due time, use 9:00 AM on selected date or current time if today
        final today = DateService.todayStart;
        if (today.year == _selectedDate.year &&
            today.month == _selectedDate.month &&
            today.day == _selectedDate.day) {
          startTime = DateTime.now();
        } else {
          startTime = DateTime(
              _selectedDate.year, _selectedDate.month, _selectedDate.day, 9, 0);
        }
      }

      final hasDuration =
          item.templateTrackingType == 'time' && item.templateTarget != null;

      if (hasDuration) {
        final targetMinutes = _getTargetMinutes(item.templateTarget);
        final endTime = startTime.add(Duration(minutes: targetMinutes));

        plannedEvents.add(CalendarEventData(
          date: _selectedDate,
          startTime: startTime,
          endTime: endTime,
          title: item.templateName,
          color: categoryColor.withOpacity(0.3), // Transparent block
          description: targetMinutes > 15
              ? '${_formatDuration(Duration(minutes: targetMinutes))}'
              : null,
        ));
      } else {
        plannedEvents.add(CalendarEventData(
          date: _selectedDate,
          startTime: startTime,
          endTime: startTime.add(const Duration(minutes: 1)),
          title: item.templateName,
          color: categoryColor,
          description: null,
        ));
      }
    }

    // Sort planned events by start time and assign
    plannedEvents.sort((a, b) {
      if (a.startTime == null || b.startTime == null) return 0;
      return a.startTime!.compareTo(b.startTime!);
    });
    _sortedPlannedEvents = plannedEvents;

    // Add legacy/timer events if any (optional, maybe filter by date?)
    // For now, skipping legacy complex timer logic for past dates to keep it simple,
    // or we can add them if they match date.
    // The original code loaded them all. We should filter.
    // Simplifying for now to focus on the requested feature.

    // Add events to respective controllers
    _completedEventController.addAll(cascadedEvents);
    _plannedEventController.addAll(plannedEvents);

    // Force rebuild to show new events
    if (mounted) setState(() {});
  }

  /// Get current value as integer (for quantity calculations)
  int _getCurrentValue(dynamic currentValue) {
    if (currentValue == null) return 0;
    if (currentValue is int) return currentValue;
    if (currentValue is double) return currentValue.toInt();
    if (currentValue is String) {
      return int.tryParse(currentValue) ?? 0;
    }
    return 0;
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

  /// Get target minutes from templateTarget
  int _getTargetMinutes(dynamic templateTarget) {
    if (templateTarget == null) return 0;
    if (templateTarget is int) return templateTarget;
    if (templateTarget is double) return templateTarget.toInt();
    if (templateTarget is String) {
      return int.tryParse(templateTarget) ?? 0;
    }
    return 0;
  }

  /// Parse color string (hex) to Color
  Color _parseColor(String colorString) {
    try {
      return fromCssColor(colorString);
    } catch (e) {
      return Colors.blue; // Default color
    }
  }

  /// Mute a color for completed items
  Color _muteColor(Color color) {
    return color.withOpacity(0.4);
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
      final durationMinutes = duration.inMinutes;

      // Replicate layout logic from _buildEventTile
      final isThin = durationMinutes <= 5 && isCompletedList;
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
    final eventList = isCompleted ? _sortedCompletedEvents : _sortedPlannedEvents;
    final labelOffset = _calculateLabelOffset(event, eventList, isCompleted);

    final duration = event.endTime!.difference(event.startTime!);
    final isNonProductive = event.title.startsWith('NP:');
    final isThinLine = duration.inMinutes <= 5 && isCompleted;

    final timeBoxHeight = duration.inMinutes * _calculateHeightPerMinute();
    final cappedHeight = math.max(1.0, timeBoxHeight);
    final actualTimeBoxHeight = isThinLine
        ? 3.0.clamp(1.0, cappedHeight)
        : timeBoxHeight.clamp(1.0, double.infinity);

    final labelFitsInside = actualTimeBoxHeight >= 24.0;

    final timeBox = _buildTimeBox(
      event,
      actualTimeBoxHeight,
      isCompleted,
      isNonProductive,
    );

    final label = labelFitsInside
        ? _buildInlineLabel(event, isCompleted, isNonProductive)
        : _buildFloatingLabel(event, isCompleted, isNonProductive);

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
              Positioned.fill(child: timeBox),
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
            Positioned.fill(child: timeBox),
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

  Widget _buildTimeBox(
    CalendarEventData event,
    double height,
    bool isCompleted,
    bool isNonProductive,
  ) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 1.0,
        minWidth: 0,
      ),
      decoration: BoxDecoration(
        color: isCompleted
            ? _muteColor(event.color).withOpacity(0.3)
            : (isNonProductive
                ? event.color.withOpacity(0.3)
                : event.color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(
          color: isCompleted ? _muteColor(event.color) : event.color,
          width: isNonProductive ? 1.5 : 1.0,
        ),
      ),
    );
  }

  Widget _buildInlineLabel(
    CalendarEventData event,
    bool isCompleted,
    bool isNonProductive,
  ) {
    final textColor = isCompleted
        ? Colors.grey.shade900
        : (isNonProductive ? Colors.white : Colors.black87);

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
                color: isCompleted
                    ? Colors.grey.shade800
                    : (isNonProductive ? Colors.white70 : Colors.black54),
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
    final labelColor = isCompleted
        ? Colors.grey.shade300
        : (isNonProductive
            ? event.color.withOpacity(0.9)
            : event.color.withOpacity(0.9));
    final textColor = isCompleted
        ? Colors.black87
        : (isNonProductive ? Colors.white : Colors.white);

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
                  color: _muteColor(event.color),
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

  // Handle vertical pinch gestures
  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.scale != 1.0) {
      final oldHeight = _calculateHeightPerMinute();
      final newZoom = _verticalZoom * details.scale;
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
  }

  @override
  void dispose() {
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
      body: Container(
        color: Colors.white,
        child: Column(
          children: [
            // Header: Date Navigation and Toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          DateFormat('EEEE, MMM d, y').format(_selectedDate),
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
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _showPlanned
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: _showPlanned
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
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
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: !_showPlanned
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: !_showPlanned
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
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

            // Calendar Body
            Expanded(
              child: GestureDetector(
                onScaleUpdate: _onScaleUpdate,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification &&
                        notification.metrics.axis == Axis.vertical) {
                      _currentScrollOffset = notification.metrics.pixels;
                    }
                    return false;
                  },
                  child: DayView(
                    // Use unique key to force rebuild when switching views or dates OR zooming
                    key: ValueKey('$_selectedDate-$_showPlanned-$_verticalZoom'),
                    scrollOffset: _initialScrollOffset,
                    controller: _showPlanned
                        ? _plannedEventController
                        : _completedEventController,
                    // Assuming initialDay sets the date
                    initialDay: _selectedDate,
                  heightPerMinute: _calculateHeightPerMinute(),
                  backgroundColor: Colors.white,
                  timeLineWidth: 50,
                  hourIndicatorSettings: HourIndicatorSettings(
                    color: Colors.grey.shade300,
                  ),
                  eventTileBuilder: (date, events, a, b, c) {
                    return _buildEventTile(events.first, !_showPlanned);
                  },
                  dayTitleBuilder: (date) {
                    return const SizedBox.shrink(); // Hide default header
                  },
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}
