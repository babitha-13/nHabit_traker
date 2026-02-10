import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'Logic/timer_page_logic.dart';
import 'UI/timer_widgets_builder.dart';

class TimerPage extends StatefulWidget {
  final DocumentReference? initialTimerLogRef;
  final String? taskTitle;
  final bool fromSwipe;
  final bool isessential; // Indicates if this is a essential activity
  /// When true, opens with an already-running timer (e.g. from notification tap) and shows elapsed time without calling startTimeLogging.
  final bool fromNotification;
  const TimerPage({
    super.key,
    this.initialTimerLogRef,
    this.taskTitle,
    this.fromSwipe = false,
    this.isessential = false,
    this.fromNotification = false,
  });
  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage>
    with WidgetsBindingObserver, TimerPageLogic {
  @override
  Widget build(BuildContext context) {
    final displayTime =
        isStopwatch ? currentStopwatchElapsed() : currentCountdownRemaining();
    return WillPopScope(
      onWillPop: onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.taskTitle ?? 'Timer'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TimerWidgetsBuilder.buildTaskTitle(
                context: context,
                taskTitle: widget.taskTitle,
              ),
              GestureDetector(
                onTap: !isStopwatch ? showCountdownPicker : null,
                child: Text(
                  formatTime(displayTime),
                  style: TextStyle(
                    fontSize: 72,
                    color: !isStopwatch ? Theme.of(context).primaryColor : null,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              TimerWidgetsBuilder.buildStopButtons(
                context: context,
                logic: this,
                fromSwipe: widget.fromSwipe,
                templateTrackingType: templateTrackingType,
              ),
              const SizedBox(height: 16),
              if (taskInstanceRef != null)
                TextButton.icon(
                  onPressed: discardTimer,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Discard Timer'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Countdown'),
                  Switch(
                    value: isStopwatch,
                    onChanged: toggleTimerMode,
                  ),
                  const Text('Stopwatch'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
