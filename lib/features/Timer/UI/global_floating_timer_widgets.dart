import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import '../Logic/global_floating_timer_logic.dart';

class GlobalFloatingTimerWidgets {
  /// Build compact bubble (collapsed state)
  static Widget buildCompactBubble({
    required BuildContext context,
    required List<ActivityInstanceRecord> activeTimers,
    required Animation<double> pulseAnimation,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: pulseAnimation.value,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.primary.withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.timer,
                  color: Colors.white,
                  size: 24,
                ),
                if (activeTimers.length > 1)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${activeTimers.length}',
                      style: TextStyle(
                        color: theme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build expanded card (expanded state)
  static Widget buildExpandedCard({
    required BuildContext context,
    required List<ActivityInstanceRecord> activeTimers,
    required GlobalFloatingTimerLogic logic,
    required VoidCallback onClose,
  }) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      width: 320,
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: theme.primary.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header (draggable area)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.drag_handle,
                  color: theme.primary.withOpacity(0.6),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.timer,
                  color: theme.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Active Timers',
                    style: theme.titleSmall.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // Timer list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: activeTimers.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (context, index) {
                return buildTimerItem(
                  context: context,
                  instance: activeTimers[index],
                  theme: theme,
                  logic: logic,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build individual timer item
  static Widget buildTimerItem({
    required BuildContext context,
    required ActivityInstanceRecord instance,
    required FlutterFlowTheme theme,
    required GlobalFloatingTimerLogic logic,
  }) {
    final currentTime = logic.getCurrentTime(instance);

    // Determine which buttons to show based on tracking type
    final trackingType = instance.templateTrackingType;
    final isBinary = trackingType == 'binary';
    final isQtyOrTime =
        trackingType == 'quantitative' || trackingType == 'time';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.alternate.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.surfaceBorderColor.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Timer name
          Expanded(
            child: Text(
              instance.templateName,
              style: theme.bodyMedium.override(
                fontFamily: 'Readex Pro',
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Elapsed time
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              logic.formatDuration(currentTime),
              style: theme.titleSmall.override(
                fontFamily: 'Readex Pro',
                fontWeight: FontWeight.w600,
                color: theme.primary,
                fontSize: 14,
              ),
            ),
          ),
          // Buttons based on tracking type
          if (isBinary) ...[
            // Binary tasks: Show Stop, Done, and Cancel buttons
            SizedBox(
              width: 45,
              child: ElevatedButton(
                onPressed: () => logic.stopTimer(instance, markComplete: false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Stop',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 3),
            SizedBox(
              width: 45,
              child: ElevatedButton(
                onPressed: () => logic.stopTimer(instance, markComplete: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 3),
            SizedBox(
              width: 45,
              child: ElevatedButton(
                onPressed: () => logic.cancelTimer(instance),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ] else if (isQtyOrTime) ...[
            // Qty or Time tasks: Show Stop and Cancel buttons
            SizedBox(
              width: 50,
              child: ElevatedButton(
                onPressed: () => logic.stopTimer(instance, markComplete: false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Stop',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 50,
              child: ElevatedButton(
                onPressed: () => logic.cancelTimer(instance),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
