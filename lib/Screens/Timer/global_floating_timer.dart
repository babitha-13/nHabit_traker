import 'dart:async';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/TimeManager.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Helper/Helpers/sound_helper.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/timer_stop_flow.dart';

/// Global floating timer widget that appears on all pages when timers are active
class GlobalFloatingTimer extends StatefulWidget {
  const GlobalFloatingTimer({Key? key}) : super(key: key);

  @override
  State<GlobalFloatingTimer> createState() => _GlobalFloatingTimerState();
}

class _GlobalFloatingTimerState extends State<GlobalFloatingTimer>
    with SingleTickerProviderStateMixin {
  final TimerManager _timerManager = TimerManager();
  bool _isExpanded = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Drag state
  double _bottomOffset = 16.0;
  double _rightOffset = 16.0;
  double _initialBottomOffset = 16.0;
  double _initialRightOffset = 16.0;
  Offset? _initialDragPosition;

  @override
  void initState() {
    super.initState();
    _timerManager.addListener(_onTimerStateChanged);

    // Load existing active timers from Firestore
    _timerManager.loadActiveTimers();

    // Listen to instance update events for real-time sync
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceUpdated,
      _onInstanceUpdated,
    );

    // Pulse animation for active timer
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timerManager.removeListener(_onTimerStateChanged);
    NotificationCenter.removeObserver(this, InstanceEvents.instanceUpdated);
    _pulseController.dispose();
    super.dispose();
  }

  void _onTimerStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Handle instance update events from NotificationCenter
  void _onInstanceUpdated(Object? data) {
    if (data is ActivityInstanceRecord) {
      // Check if it's a timer instance (time type or binary with time logging) and sync with TimerManager
      final isTimeType = data.templateTrackingType == 'time';
      final isBinaryTimerSession = data.templateTrackingType == 'binary' &&
          (data.isTimeLogging || data.currentSessionStartTime != null);
      if (isTimeType || isBinaryTimerSession) {
        _timerManager.updateInstance(data);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTimers = _timerManager.activeTimers;

    if (activeTimers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: _bottomOffset,
      right: _rightOffset,
      child: GestureDetector(
        onTap: _isExpanded
            ? null
            : () {
                setState(() => _isExpanded = true);
              },
        onPanStart: (details) {
          _initialDragPosition = details.globalPosition;
          _initialBottomOffset = _bottomOffset;
          _initialRightOffset = _rightOffset;
        },
        onPanUpdate: (details) {
          if (_initialDragPosition == null) return;

          final delta = details.globalPosition - _initialDragPosition!;

          // Only start dragging if movement is significant (prevents accidental drags on taps)
          if (delta.distance < 5) return;

          // Get screen size to constrain dragging
          final screenHeight = MediaQuery.of(context).size.height;
          final screenWidth = MediaQuery.of(context).size.width;

          // Calculate new position (invert Y axis since bottom is from bottom)
          double newBottom = _initialBottomOffset - delta.dy;
          double newRight = _initialRightOffset - delta.dx;

          // Constrain to screen bounds
          final widgetHeight = _isExpanded ? 400.0 : 64.0;
          final widgetWidth = _isExpanded ? 320.0 : 64.0;

          newBottom = newBottom.clamp(0.0, screenHeight - widgetHeight - 16);
          newRight = newRight.clamp(0.0, screenWidth - widgetWidth - 16);

          setState(() {
            _bottomOffset = newBottom;
            _rightOffset = newRight;
          });
        },
        onPanEnd: (details) {
          _initialDragPosition = null;
        },
        behavior: HitTestBehavior.opaque,
        child: _isExpanded
            ? _buildExpandedCard(activeTimers)
            : _buildCompactBubble(activeTimers),
      ),
    );
  }

  /// Build compact bubble (collapsed state)
  Widget _buildCompactBubble(List<ActivityInstanceRecord> activeTimers) {
    final theme = FlutterFlowTheme.of(context);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
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
                Icon(
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
  Widget _buildExpandedCard(List<ActivityInstanceRecord> activeTimers) {
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
          // Header (draggable area - drag handle icon indicates draggability)
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
                  onPressed: () {
                    setState(() => _isExpanded = false);
                  },
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
                return _buildTimerItem(activeTimers[index], theme);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build individual timer item
  Widget _buildTimerItem(
      ActivityInstanceRecord instance, FlutterFlowTheme theme) {
    final currentTime = _getCurrentTime(instance);

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
              _formatDuration(currentTime),
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
                onPressed: () => _stopTimer(instance, markComplete: false),
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
                onPressed: () => _stopTimer(instance, markComplete: true),
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
                onPressed: () => _cancelTimer(instance),
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
                onPressed: () => _stopTimer(instance, markComplete: false),
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
                onPressed: () => _cancelTimer(instance),
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

  /// Get current elapsed time for an instance
  int _getCurrentTime(ActivityInstanceRecord instance) {
    int totalMilliseconds = instance.accumulatedTime;

    // For binary timer sessions, use currentSessionStartTime
    if (instance.templateTrackingType == 'binary' &&
        instance.currentSessionStartTime != null) {
      final elapsed = DateTime.now()
          .difference(instance.currentSessionStartTime!)
          .inMilliseconds;
      totalMilliseconds += elapsed;
    } else if (instance.isTimerActive && instance.timerStartTime != null) {
      // For time-tracking instances, use timerStartTime
      final elapsed =
          DateTime.now().difference(instance.timerStartTime!).inMilliseconds;
      totalMilliseconds += elapsed;
    }

    return totalMilliseconds;
  }

  /// Format duration in HH:MM:SS or MM:SS format
  String _formatDuration(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Cancel timer - directly discard without showing modal
  Future<void> _cancelTimer(ActivityInstanceRecord instance) async {
    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard Timer?'),
          content: const Text(
            'Are you sure you want to discard this timer session? All progress will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Discard'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return; // User cancelled
      }

      // For binary timer sessions (from timer page), discard and delete if temporary
      if (instance.templateTrackingType == 'binary' &&
          (instance.isTimeLogging ||
              instance.currentSessionStartTime != null)) {
        // Check if this is a temporary timer task (not from swipe)
        // Timer tasks have templateCategoryType 'task' and are binary
        if (instance.templateCategoryType == 'task') {
          // Discard time logging first
          try {
            await TaskInstanceService.discardTimeLogging(
              activityInstanceRef: instance.reference,
            );
          } catch (e) {
            // Ignore errors - might already be discarded
          }

          // Delete the template if it exists
          try {
            if (instance.hasTemplateId()) {
              final templateRef =
                  ActivityRecord.collectionForUser(currentUserUid)
                      .doc(instance.templateId);
              await templateRef.delete();
            }
            // Delete the instance
            await instance.reference.delete();
          } catch (e) {
            // Handle error silently - cleanup is best effort
          }
        } else {
          // For swipe-started instances, just discard time logging
          await TaskInstanceService.discardTimeLogging(
            activityInstanceRef: instance.reference,
          );
        }
      } else {
        // For time-tracking instances, just discard time logging
        await TaskInstanceService.discardTimeLogging(
          activityInstanceRef: instance.reference,
        );
      }

      // Remove from TimerManager
      _timerManager.stopInstance(instance);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timer discarded'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error discarding timer: $e')),
        );
      }
    }
  }

  /// Check if instance is from a swipe (has real task details, not temporary timer task)
  bool _isFromSwipe(ActivityInstanceRecord instance) {
    // Timer-created instances have template name "Timer Task"
    // Swipe-started instances have the actual task name
    return instance.templateName != 'Timer Task' &&
        instance.templateName.isNotEmpty;
  }

  /// Stop timer with optional completion
  Future<void> _stopTimer(ActivityInstanceRecord instance,
      {required bool markComplete}) async {
    try {
      // Play stop button sound
      SoundHelper().playStopButtonSound();

      // Check if this is from a swipe (has task details already)
      final isFromSwipe = _isFromSwipe(instance);

      // For binary timer sessions
      if (instance.templateTrackingType == 'binary' &&
          (instance.isTimeLogging ||
              instance.currentSessionStartTime != null)) {
        // If from swipe, save directly without showing modal (task details already available)
        if (isFromSwipe) {
          try {
            // For swipe-started instances: stop time logging (with or without completion)
            await TaskInstanceService.stopTimeLogging(
              activityInstanceRef: instance.reference,
              markComplete: markComplete,
            );

            // Remove from TimerManager after save
            _timerManager.stopInstance(instance);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(markComplete
                      ? 'Timer completed and saved'
                      : 'Timer stopped and saved'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error saving timer: $e')),
              );
            }
          }
        } else {
          // For timer-created instances, show modal to get task details
          final success = await TimerStopFlow.handleTimerStop(
            context: context,
            instance: instance,
            markComplete: markComplete,
            timerStartTime: instance.currentSessionStartTime,
            onSaveComplete: () {
              // Remove from TimerManager after save
              _timerManager.stopInstance(instance);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(markComplete
                        ? 'Timer completed and saved'
                        : 'Timer stopped and saved'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          );

          if (!success) {
            // Modal was cancelled, refresh instance state
            final updatedInstance =
                await ActivityInstanceService.getUpdatedInstance(
              instanceId: instance.reference.id,
            );
            _timerManager.updateInstance(updatedInstance);
          }
        }
      } else {
        // For time-tracking instances, use existing toggle logic
        final wasActive = instance.isTimerActive;
        if (wasActive) {
          await ActivityInstanceService.toggleInstanceTimer(
            instanceId: instance.reference.id,
          );
        }
        final updatedInstance =
            await ActivityInstanceService.getUpdatedInstance(
          instanceId: instance.reference.id,
        );
        // If timer was stopped, remove it from TimerManager
        if (wasActive && !updatedInstance.isTimerActive) {
          _timerManager.stopInstance(updatedInstance);
        } else {
          _timerManager.updateInstance(updatedInstance);
        }
        InstanceEvents.broadcastInstanceUpdated(updatedInstance);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping timer: $e')),
        );
      }
    }
  }
}
