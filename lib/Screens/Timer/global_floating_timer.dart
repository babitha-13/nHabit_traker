import 'package:flutter/material.dart';
import 'Logic/global_floating_timer_logic.dart';
import 'UI/global_floating_timer_widgets.dart';

/// Global floating timer widget that appears on all pages when timers are active
class GlobalFloatingTimer extends StatefulWidget {
  const GlobalFloatingTimer({Key? key}) : super(key: key);

  @override
  State<GlobalFloatingTimer> createState() => _GlobalFloatingTimerState();
}

class _GlobalFloatingTimerState extends State<GlobalFloatingTimer>
    with SingleTickerProviderStateMixin, GlobalFloatingTimerLogic {
  @override
  Widget build(BuildContext context) {
    final activeTimers = timerManager.activeTimers;

    if (activeTimers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: bottomOffset,
      right: rightOffset,
      child: GestureDetector(
        onTap: isExpanded
            ? null
            : () {
                setState(() => isExpanded = true);
              },
        onPanStart: handlePanStart,
        onPanUpdate: handlePanUpdate,
        onPanEnd: handlePanEnd,
        behavior: HitTestBehavior.opaque,
        child: isExpanded
            ? GlobalFloatingTimerWidgets.buildExpandedCard(
                context: context,
                activeTimers: activeTimers,
                logic: this,
                onClose: () {
                  setState(() => isExpanded = false);
                },
              )
            : GlobalFloatingTimerWidgets.buildCompactBubble(
                context: context,
                activeTimers: activeTimers,
                pulseAnimation: pulseAnimation,
              ),
      ),
    );
  }
}
