import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final EventController _eventController = EventController();

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

    // Add timer task events (existing)
    for (final task in timerTasks) {
      if (task.timerStartTime != null && task.accumulatedTime > 0) {
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

  @override
  void dispose() {
    _eventController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar View'),
      ),
      body: DayView(
        controller: _eventController,
        eventTileBuilder: (date, events, a, b, c) {
          // The calendar_view package's builder is a bit unusual. We only need the events.
          return Container(
            padding: const EdgeInsets.all(4.0),
            decoration: BoxDecoration(
              color: events.first.color.withOpacity(0.8),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Text(
              events.first.title,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          );
        },
        dayTitleBuilder: (date) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            decoration: const BoxDecoration(
              color: Colors.grey,
              border:
                  Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
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
    );
  }
}
