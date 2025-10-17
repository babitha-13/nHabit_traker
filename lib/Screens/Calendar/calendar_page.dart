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
    final taskInstances = await TaskInstanceService.getTimerTaskInstances();
    final events = taskInstances
        .map((instance) {
          if (instance.timerStartTime == null ||
              instance.accumulatedTime <= 0) {
            return null;
          }

          Color eventColor = Colors.blue; // Default color
          if (instance.templateCategoryId.isNotEmpty) {
            try {
              // Try to get color from category - for now use default
              // In future, we can query category details for color
              eventColor = Colors.blue;
            } catch (e) {
              // Keep default color if parsing fails
            }
          }

          final startTime = instance.timerStartTime!;
          final endTime =
              startTime.add(Duration(milliseconds: instance.accumulatedTime));

          return CalendarEventData(
            date: startTime,
            startTime: startTime,
            endTime: endTime,
            title: instance.templateName,
            color: eventColor,
          );
        })
        .whereType<CalendarEventData>()
        .toList();

    _eventController.addAll(events);
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
