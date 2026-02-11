import 'package:flutter/material.dart';
import '../Logic/timer_page_logic.dart';

class TimerWidgetsBuilder {
  static Widget buildStopButtons({
    required BuildContext context,
    required TimerPageLogic logic,
    required bool fromSwipe,
    required String? templateTrackingType,
  }) {
    if (fromSwipe &&
        (templateTrackingType == 'quantitative' ||
            templateTrackingType == 'time')) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: logic.isRunning ? null : () => logic.startTimer(),
            child: const Text('Start'),
          ),
          const SizedBox(width: 20),
          ElevatedButton(
            onPressed: !logic.isRunning ? null : logic.stopTimer,
            child: const Text('Stop'),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: logic.isRunning ? null : () => logic.startTimer(),
          child: const Text('Start'),
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          onPressed: !logic.isRunning ? null : logic.stopTimer,
          child: const Text('Stop'),
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          onPressed: !logic.isRunning ? null : logic.stopAndCompleteTimer,
          child: const Text('Stop and Complete'),
        ),
      ],
    );
  }

  static Widget buildTaskTitle({
    required BuildContext context,
    required String? taskTitle,
  }) {
    if (taskTitle == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        taskTitle,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).primaryColor,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
