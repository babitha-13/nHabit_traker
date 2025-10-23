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
  final TransformationController _transformationController =
      TransformationController();

  // Zoom constraints
  static const double _minZoom = 0.5;
  static const double _maxZoom = 3.0;
  static const double _zoomStep = 0.2;
  double _currentZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _loadEvents();

    // Listen to transformation changes for pinch gestures
    _transformationController.addListener(() {
      final scale = _transformationController.value.getMaxScaleOnAxis();
      if (scale != _currentZoom) {
        setState(() {
          _currentZoom = scale.clamp(_minZoom, _maxZoom);
        });
      }
    });
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

  void _zoomIn() {
    final newScale = (_currentZoom + _zoomStep).clamp(_minZoom, _maxZoom);
    _currentZoom = newScale;
    _transformationController.value = Matrix4.identity()..scale(newScale);
    setState(() {});
  }

  void _zoomOut() {
    final newScale = (_currentZoom - _zoomStep).clamp(_minZoom, _maxZoom);
    _currentZoom = newScale;
    _transformationController.value = Matrix4.identity()..scale(newScale);
    setState(() {});
  }

  void _resetZoom() {
    _currentZoom = 1.0;
    _transformationController.value = Matrix4.identity();
    setState(() {});
  }

  @override
  void dispose() {
    _eventController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: Stack(
        children: [
          // Zoomable calendar
          InteractiveViewer(
            transformationController: _transformationController,
            minScale: _minZoom,
            maxScale: _maxZoom,
            child: DayView(
              controller: _eventController,
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
                  decoration: const BoxDecoration(
                    color: Colors.grey,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey, width: 0.5),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      DateFormat.yMMMMd().format(date),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Zoom level indicator
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${(_currentZoom * 100).toInt()}%',
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
    );
  }
}
