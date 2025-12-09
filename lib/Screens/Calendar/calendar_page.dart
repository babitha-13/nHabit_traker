import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/calendar_queue_service.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:from_css_color/from_css_color.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  // Separate event controllers for completed (left) and planned (right) columns
  final EventController _completedEventController = EventController();
  final EventController _plannedEventController = EventController();
  // Keep original controller for backward compatibility with existing events
  final EventController _eventController = EventController();
  // GlobalKeys to access DayView internal scrollable widgets
  final GlobalKey _completedDayViewKey = GlobalKey();
  final GlobalKey _plannedDayViewKey = GlobalKey();
  // Track which column initiated scroll to prevent infinite loops
  bool _isSyncingScroll = false;
  // Vertical zoom constraints
  static const double _minVerticalZoom = 0.5;
  static const double _maxVerticalZoom = 3.0;
  static const double _zoomStep = 0.2;
  double _verticalZoom = 1.0;
  // Base height per minute (increased for better visibility)
  static const double _baseHeightPerMinute = 2.0;
  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  /// Sync scroll position from source to target using GlobalKey
  void _syncScrollPosition(GlobalKey sourceKey, GlobalKey targetKey) {
    if (_isSyncingScroll) return;
    
    final sourceContext = sourceKey.currentContext;
    final targetContext = targetKey.currentContext;
    
    if (sourceContext == null || targetContext == null) return;
    
    // Find Scrollable widget and its position in source
    ScrollPosition? sourcePosition;
    sourceContext.visitAncestorElements((element) {
      if (element.widget is Scrollable) {
        final scrollable = element.widget as Scrollable;
        final controller = scrollable.controller;
        if (controller != null && controller.hasClients) {
          sourcePosition = controller.position;
        }
        return false;
      }
      return true;
    });
    
    if (sourcePosition == null) return;
    final sourcePixels = sourcePosition!.pixels;
    
    // Sync to target
    targetContext.visitAncestorElements((element) {
      if (element.widget is Scrollable) {
        final scrollable = element.widget as Scrollable;
        final controller = scrollable.controller;
        if (controller != null && controller.hasClients) {
          final targetPosition = controller.position;
          if ((targetPosition.pixels - sourcePixels).abs() > 1.0) {
            _isSyncingScroll = true;
            targetPosition.jumpTo(sourcePixels);
            Future.microtask(() => _isSyncingScroll = false);
          }
        }
        return false;
      }
      return true;
    });
  }

  Future<void> _loadEvents() async {
    // Get categories for color lookup
    final userId = currentUserUid;
    final habitCategories = await queryHabitCategoriesOnce(userId: userId);
    final taskCategories = await queryTaskCategoriesOnce(userId: userId);
    final allCategories = [...habitCategories, ...taskCategories];

    // Get queue items (planned and completed)
    final queueItems = await CalendarQueueService.getTodayQueueItems();
    final plannedItems = queueItems['planned'] ?? [];
    final completedItems = queueItems['completed'] ?? [];

    // Separate event lists for completed (left) and planned (right)
    final completedEvents = <CalendarEventData>[];
    final plannedEvents = <CalendarEventData>[];

    // Process completed items (left column)
    for (final item in completedItems) {
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

      final categoryColor = category != null
          ? _parseColor(category.color)
          : Colors.grey;

      // Check if item has no time duration (no dueTime or not time-based tracking)
      final hasNoTimeDuration = (item.dueTime == null || item.dueTime!.isEmpty) &&
          (item.templateTrackingType != 'time' || item.templateTarget == null);

      // All completed items get 5-minute duration for visibility in calendar
      // (this is just for rendering, doesn't affect actual data)
      DateTime startTime;
      DateTime endTime;

      if (hasNoTimeDuration) {
        // Auto-assign 5-minute duration block ending at completion time
        // Example: completed at 5:15 → show block from 5:10 to 5:15
        endTime = item.completedAt!;
        startTime = endTime.subtract(const Duration(minutes: 5));
      } else {
        // For time-based items, also use 5 minutes centered on completion time
        // This ensures labels are visible
        final centerTime = item.completedAt!;
        startTime = centerTime.subtract(const Duration(minutes: 2));
        endTime = centerTime.add(const Duration(minutes: 3));
      }

      completedEvents.add(CalendarEventData(
        date: startTime,
        startTime: startTime,
        endTime: endTime,
        title: '✓ ${item.templateName}',
        color: _muteColor(categoryColor), // Muted color for completed
        description: 'Completed',
      ));
    }

    // Process planned items (right column)
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

      final categoryColor = category != null
          ? _parseColor(category.color)
          : Colors.blue;

      // Parse due time
      DateTime? startTime;
      if (item.dueTime != null && item.dueTime!.isNotEmpty) {
        startTime = _parseDueTime(item.dueTime!);
      } else {
        // If no due time, use current time or a default
        startTime = DateTime.now();
      }

      // Check if item has duration (time-based with templateTarget)
      final hasDuration = item.templateTrackingType == 'time' &&
          item.templateTarget != null;

      if (hasDuration) {
        // Time-based item with duration - create block
        final targetMinutes = _getTargetMinutes(item.templateTarget);
        final endTime = startTime.add(Duration(minutes: targetMinutes));

        plannedEvents.add(CalendarEventData(
          date: startTime,
          startTime: startTime,
          endTime: endTime,
          title: item.templateName,
          color: categoryColor.withOpacity(0.3), // Transparent block
          description: targetMinutes > 15
              ? '${_formatDuration(Duration(minutes: targetMinutes))}'
              : null,
        ));
      } else {
        // No duration - create thin line marker
        plannedEvents.add(CalendarEventData(
          date: startTime,
          startTime: startTime,
          endTime: startTime.add(const Duration(minutes: 1)),
          title: item.templateName,
          color: categoryColor,
          description: null,
        ));
      }
    }

    // Load existing timer/time-logged events (keep for backward compatibility)
    final timerTasks = await TaskInstanceService.getTimerTaskInstances();
    final timeLoggedTasks = await TaskInstanceService.getTimeLoggedTasks();
    final nonProductiveInstances =
        await TaskInstanceService.getNonProductiveInstances();
    final legacyEvents = <CalendarEventData>[];

    // Add timer task events
    for (final task in timerTasks) {
      if (task.timeLogSessions.isNotEmpty) {
        for (final session in task.timeLogSessions) {
          final startTime = session['startTime'] as DateTime;
          final endTime = session['endTime'] as DateTime?;
          if (endTime != null) {
            legacyEvents.add(CalendarEventData(
              date: startTime,
              startTime: startTime,
              endTime: endTime,
              title: task.templateName,
              color: _getCategoryColor(task.templateCategoryId, allCategories),
              description:
                  'Session: ${_formatDuration(endTime.difference(startTime))}',
            ));
          }
        }
      } else if (task.timerStartTime != null && task.accumulatedTime > 0) {
        legacyEvents.add(CalendarEventData(
          date: task.timerStartTime!,
          startTime: task.timerStartTime!,
          endTime: task.timerStartTime!
              .add(Duration(milliseconds: task.accumulatedTime)),
          title: task.templateName,
          color: Colors.blue,
        ));
      }
    }

    // Add time-logged task sessions
    for (final task in timeLoggedTasks) {
      for (final session in task.timeLogSessions) {
        final startTime = session['startTime'] as DateTime;
        final endTime = session['endTime'] as DateTime?;
        if (endTime != null) {
          legacyEvents.add(CalendarEventData(
            date: startTime,
            startTime: startTime,
            endTime: endTime,
            title: task.templateName,
            color: _getCategoryColor(task.templateCategoryId, allCategories),
            description:
                'Session: ${_formatDuration(endTime.difference(startTime))}',
          ));
        }
      }
    }

    // Add non-productive item sessions
    for (final instance in nonProductiveInstances) {
      for (final session in instance.timeLogSessions) {
        final startTime = session['startTime'] as DateTime;
        final endTime = session['endTime'] as DateTime?;
        if (endTime != null) {
          legacyEvents.add(CalendarEventData(
            date: startTime,
            startTime: startTime,
            endTime: endTime,
            title: 'NP: ${instance.templateName}',
            color: Colors.grey.shade400,
            description: instance.notes.isNotEmpty
                ? '${_formatDuration(endTime.difference(startTime))} - ${instance.notes}'
                : 'Session: ${_formatDuration(endTime.difference(startTime))}',
          ));
        }
      }
    }

    // Add events to respective controllers
    _completedEventController.addAll(completedEvents);
    _plannedEventController.addAll(plannedEvents);
    _eventController.addAll(legacyEvents);
  }

  /// Parse dueTime string (HH:mm) to DateTime for today
  DateTime _parseDueTime(String dueTime) {
    final timeOfDay = TimeUtils.stringToTimeOfDay(dueTime);
    if (timeOfDay == null) {
      return DateTime.now(); // Fallback to current time
    }
    final today = DateService.currentDate;
    return DateTime(
      today.year,
      today.month,
      today.day,
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

  /// Mute a color for completed items (reduce saturation and opacity)
  Color _muteColor(Color color) {
    // Reduce opacity and create a more muted version
    return color.withOpacity(0.4);
  }

  /// Build event tile with handling for small durations
  Widget _buildEventTile(CalendarEventData event, bool isCompleted) {
    if (event.startTime == null || event.endTime == null) {
      return const SizedBox.shrink();
    }
    final duration = event.endTime!.difference(event.startTime!);
    final isSmallDuration = duration.inMinutes < 15;
    final isNonProductive = event.title.startsWith('NP:');
    final isThinLine = duration.inMinutes <= 5 && isCompleted; // Completed items render as thin lines

    // For small durations or thin lines, use compact label style
    if (isSmallDuration || isThinLine) {
      // For thin lines, show a thin vertical line with a horizontal label block
      if (isThinLine) {
        return SizedBox(
          height: double.infinity,
          child: OverflowBox(
            minWidth: 0,
            maxWidth: double.infinity, // Allow label to extend beyond event bounds
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Thin vertical line marker on the left edge
                Container(
                  width: 3.0, // Thin line width
                  decoration: BoxDecoration(
                    color: isCompleted ? _muteColor(event.color) : event.color,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                // Horizontal label block that extends to the right, only as wide as text needs
                Padding(
                  padding: const EdgeInsets.only(left: 6.0),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? Colors.grey.shade300 // Light grey background for completed items
                            : event.color,
                        borderRadius: BorderRadius.circular(4.0),
                        border: isCompleted
                            ? Border.all(
                                color: _muteColor(event.color),
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: Text(
                        event.title,
                        style: TextStyle(
                          color: isCompleted
                              ? Colors.black87 // Dark text on light background
                              : Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700, // Bolder for visibility
                          shadows: isCompleted
                              ? null // No shadow needed with dark text on light bg
                              : [
                                  Shadow(
                                    offset: const Offset(0, 0),
                                    blurRadius: 2.0,
                                    color: Colors.black.withOpacity(0.5),
                                  ),
                                ],
                        ),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      
      // For small durations (but not thin lines), use compact label style
      return Container(
        constraints: const BoxConstraints(
          minHeight: 20.0,
          minWidth: 60.0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: isCompleted
              ? _muteColor(event.color).withOpacity(0.4)
              : event.color.withOpacity(0.3),
          borderRadius: BorderRadius.circular(3.0),
          border: Border.all(
            color: isCompleted ? _muteColor(event.color) : event.color,
            width: 1.0,
          ),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            event.title,
            style: TextStyle(
              color: isCompleted
                  ? Colors.grey.shade900
                  : event.color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              shadows: isCompleted
                  ? [
                      Shadow(
                        offset: const Offset(0, 0),
                        blurRadius: 1.0,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ]
                  : null,
            ),
            overflow: TextOverflow.fade,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.left,
          ),
        ),
      );
    }

    // For larger durations, show full block with description
    return Container(
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: isCompleted
            ? _muteColor(event.color).withOpacity(0.3) // Increased from 0.2
            : (isNonProductive
                ? event.color.withOpacity(0.3)
                : event.color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(
          color: isCompleted ? _muteColor(event.color) : event.color,
          width: isNonProductive ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.title,
            style: TextStyle(
              color: isCompleted
                  ? Colors.grey.shade900 // Changed from shade700 for better contrast
                  : (isNonProductive ? Colors.white : Colors.black87),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          if (event.description != null)
            Text(
              event.description!,
              style: TextStyle(
                color: isCompleted
                    ? Colors.grey.shade800 // Changed from shade600 for better contrast
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

  Color _getCategoryColor(String categoryId, List<CategoryRecord> categories) {
    try {
      final category = categories.firstWhere(
        (c) => c.reference.id == categoryId,
      );
      return _parseColor(category.color);
    } catch (e) {
      return Colors.blue; // Default color
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  // Calculate height per minute based on vertical zoom
  double _calculateHeightPerMinute() {
    return _baseHeightPerMinute * _verticalZoom;
  }

  void _zoomIn() {
    final newScale =
        (_verticalZoom + _zoomStep).clamp(_minVerticalZoom, _maxVerticalZoom);
    setState(() {
      _verticalZoom = newScale;
    });
  }

  void _zoomOut() {
    final newScale =
        (_verticalZoom - _zoomStep).clamp(_minVerticalZoom, _maxVerticalZoom);
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
  void _onScaleStart(ScaleStartDetails details) {
    // Store initial zoom level for gesture
  }
  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Only respond to vertical scaling
    if (details.scale != 1.0) {
      final newZoom = _verticalZoom * details.scale;
      setState(() {
        _verticalZoom = newZoom.clamp(_minVerticalZoom, _maxVerticalZoom);
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // Gesture ended
  }
  @override
  void dispose() {
    _eventController.dispose();
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
          // Zoom controls in app bar
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
        child: Stack(
          children: [
            // Split layout: Left (Completed) and Right (Planned)
            GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: Container(
                color: Colors.white,
                child: Row(
                  children: [
                    // Left column: Completed items
                    Expanded(
                      child: Column(
                        children: [
                          // Column header
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8.0, horizontal: 12.0),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              border: Border(
                                bottom: BorderSide(
                                    color: Colors.grey.shade300, width: 1),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle,
                                    size: 16, color: Colors.grey),
                                SizedBox(width: 4),
                                Text(
                                  'Completed',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Completed calendar view
                          Expanded(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                // Sync on any scroll update or end
                                if ((notification is ScrollUpdateNotification ||
                                        notification is ScrollEndNotification) &&
                                    !_isSyncingScroll) {
                                  // Use a small delay to ensure scroll position is updated
                                  Future.microtask(() {
                                    _syncScrollPosition(
                                        _completedDayViewKey, _plannedDayViewKey);
                                  });
                                }
                                return false;
                              },
                              child: DayView(
                                key: _completedDayViewKey,
                                controller: _completedEventController,
                                heightPerMinute: _calculateHeightPerMinute(),
                                backgroundColor: Colors.white,
                                timeLineWidth: 30, // Narrower for split view
                                hourIndicatorSettings: HourIndicatorSettings(
                                  color: Colors.grey.shade300,
                                ),
                                eventTileBuilder: (date, events, a, b, c) {
                                  return _buildEventTile(events.first, true);
                                },
                                dayTitleBuilder: (date) {
                                  return const SizedBox
                                      .shrink(); // Hide title in split view
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Vertical divider
                    Container(
                      width: 1,
                      color: Colors.grey.shade300,
                    ),
                    // Right column: Planned items
                    Expanded(
                      child: Column(
                        children: [
                          // Column header
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8.0, horizontal: 12.0),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              border: Border(
                                bottom: BorderSide(
                                    color: Colors.grey.shade300, width: 1),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.schedule,
                                    size: 16, color: Colors.blue),
                                SizedBox(width: 4),
                                Text(
                                  'Planned',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Planned calendar view
                          Expanded(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                // Sync on any scroll update or end
                                if ((notification is ScrollUpdateNotification ||
                                        notification is ScrollEndNotification) &&
                                    !_isSyncingScroll) {
                                  // Use a small delay to ensure scroll position is updated
                                  Future.microtask(() {
                                    _syncScrollPosition(
                                        _plannedDayViewKey, _completedDayViewKey);
                                  });
                                }
                                return false;
                              },
                              child: DayView(
                                key: _plannedDayViewKey,
                                controller: _plannedEventController,
                                heightPerMinute: _calculateHeightPerMinute(),
                                backgroundColor: Colors.white,
                                timeLineWidth: 30, // Narrower for split view
                                hourIndicatorSettings: HourIndicatorSettings(
                                  color: Colors.grey.shade300,
                                ),
                                eventTileBuilder: (date, events, a, b, c) {
                                  return _buildEventTile(events.first, false);
                                },
                                dayTitleBuilder: (date) {
                                  return const SizedBox
                                      .shrink(); // Hide title in split view
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Zoom level indicator
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(_verticalZoom * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
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
