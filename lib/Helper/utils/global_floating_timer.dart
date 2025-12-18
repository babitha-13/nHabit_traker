import 'dart:async';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/TimeManager.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';

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
      // Check if it's a timer instance and sync with TimerManager
      if (data.templateTrackingType == 'time') {
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
      bottom: 16,
      right: 16,
      child: _isExpanded
          ? _buildExpandedCard(activeTimers)
          : _buildCompactBubble(activeTimers),
    );
  }

  /// Build compact bubble (collapsed state)
  Widget _buildCompactBubble(List<ActivityInstanceRecord> activeTimers) {
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: () {
        setState(() => _isExpanded = true);
      },
      child: AnimatedBuilder(
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
      ),
    );
  }

  /// Build expanded card (expanded state)
  Widget _buildExpandedCard(List<ActivityInstanceRecord> activeTimers) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      width: 280,
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
          // Header
          Container(
            padding: const EdgeInsets.all(12),
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
                  Icons.timer,
                  color: theme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Active Timers',
                    style: theme.titleSmall.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
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
    final target = instance.templateTarget ?? 0;
    final progress = target > 0 ? (currentTime / (target * 60 * 1000)).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.alternate.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.surfaceBorderColor.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timer name and time
          Row(
            children: [
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
              Text(
                _formatDuration(currentTime),
                style: theme.titleSmall.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                  color: theme.primary,
                ),
              ),
            ],
          ),
          // Progress bar (if target is set)
          if (target > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: theme.alternate.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(progress * 100).toStringAsFixed(0)}% of ${target} min',
              style: theme.bodySmall.override(
                fontFamily: 'Readex Pro',
                fontSize: 10,
              ),
            ),
          ],
          // Action button
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _stopTimer(instance),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Stop',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Get current elapsed time for an instance
  int _getCurrentTime(ActivityInstanceRecord instance) {
    int totalMilliseconds = instance.accumulatedTime;
    if (instance.isTimerActive && instance.timerStartTime != null) {
      final elapsed = DateTime.now()
          .difference(instance.timerStartTime!)
          .inMilliseconds;
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

  /// Stop timer
  Future<void> _stopTimer(ActivityInstanceRecord instance) async {
    try {
      final wasActive = instance.isTimerActive;
      if (wasActive) {
        await ActivityInstanceService.toggleInstanceTimer(
          instanceId: instance.reference.id,
        );
      }
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );
      // If timer was stopped, remove it from TimerManager
      if (wasActive && !updatedInstance.isTimerActive) {
        _timerManager.stopInstance(updatedInstance);
      } else {
        _timerManager.updateInstance(updatedInstance);
      }
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping timer: $e')),
        );
      }
    }
  }
}

