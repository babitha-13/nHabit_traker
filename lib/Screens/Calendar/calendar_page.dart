import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:intl/intl.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final EventController _eventController = EventController();
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

  Future<void> _loadEvents() async {
    // Get timer tasks (existing implementation)
    final timerTasks = await TaskInstanceService.getTimerTaskInstances();
    // Get ALL time-logged tasks (NEW)
    final timeLoggedTasks = await TaskInstanceService.getTimeLoggedTasks();
    final events = <CalendarEventData>[];
    // Add timer task events - display sessions if available, otherwise legacy format
    for (final task in timerTasks) {
      // If task has timeLogSessions, display each session separately
      if (task.timeLogSessions.isNotEmpty) {
        for (final session in task.timeLogSessions) {
          final startTime = session['startTime'] as DateTime;
          final endTime = session['endTime'] as DateTime?;
          if (endTime != null) {
            events.add(CalendarEventData(
              date: startTime,
              startTime: startTime,
              endTime: endTime,
              title: task.templateName,
              color: _getCategoryColor(task.templateCategoryId),
              description:
                  'Session: ${_formatDuration(endTime.difference(startTime))}',
            ));
          }
        }
      } else if (task.timerStartTime != null && task.accumulatedTime > 0) {
        // Legacy format for old timer tasks
        events.add(CalendarEventData(
          date: task.timerStartTime!,
          startTime: task.timerStartTime!,
          endTime: task.timerStartTime!
              .add(Duration(milliseconds: task.accumulatedTime)),
          title: task.templateName,
          color: Colors.blue,
        ));
      }
    }
    // Add time-logged task sessions (NEW) - EACH SESSION AS SEPARATE BLOCK
    for (final task in timeLoggedTasks) {
      // Create event for EACH individual session
      for (final session in task.timeLogSessions) {
        final startTime = session['startTime'] as DateTime;
        final endTime = session['endTime'] as DateTime?;
        if (endTime != null) {
          events.add(CalendarEventData(
            date: startTime,
            startTime: startTime,
            endTime: endTime,
            title: task.templateName,
            color: _getCategoryColor(task.templateCategoryId),
            description:
                'Session: ${_formatDuration(endTime.difference(startTime))}',
          ));
        }
      }
      // Add completion event as thin line (NEW)
      if (task.status == 'completed' && task.completedAt != null) {
        events.add(CalendarEventData(
          date: task.completedAt!,
          startTime: task.completedAt!,
          endTime: task.completedAt!.add(Duration(minutes: 1)), // Thin line
          title: '✓ ${task.templateName}',
          color: Colors.green,
          description: 'Completed',
        ));
      }
    }
    _eventController.addAll(events);
  }

  Color _getCategoryColor(String categoryId) {
    // Get category color from ID
    // For now, return default
    return Colors.blue;
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
            // Vertically zoomable calendar
            GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: Container(
                color: Colors.white,
                child: DayView(
                  controller: _eventController,
                  heightPerMinute: _calculateHeightPerMinute(),
                  backgroundColor: Colors.white,
                  timeLineWidth: 60,
                  hourIndicatorSettings: HourIndicatorSettings(
                    color: Colors.grey.shade300,
                  ),
                  eventTileBuilder: (date, events, a, b, c) {
                    // Enhanced event tile for better visibility when zoomed
                    return Container(
                      padding: const EdgeInsets.all(4.0),
                      decoration: BoxDecoration(
                        color: events.first.color.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4.0),
                        border: Border.all(
                          color: events.first.color,
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            events.first.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                          if (events.first.description != null)
                            Text(
                              events.first.description!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                        ],
                      ),
                    );
                  },
                  dayTitleBuilder: (date) {
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(
                              color: Colors.grey.shade400, width: 0.5),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          DateFormat.yMMMMd().format(date),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
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
