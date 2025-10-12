import 'dart:async';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

class FloatingTimer extends StatefulWidget {
  final List<ActivityInstanceRecord> activeInstances;
  final Future<void> Function()? onRefresh;
  final void Function(ActivityInstanceRecord updatedInstance)?
      onInstanceUpdated;

  const FloatingTimer({
    Key? key,
    required this.activeInstances,
    this.onRefresh,
    this.onInstanceUpdated,
  }) : super(key: key);

  @override
  State<FloatingTimer> createState() => _FloatingTimerState();
}

class _FloatingTimerState extends State<FloatingTimer> {
  Timer? _updateTimer;
  final Set<String> _hiddenAfterStop = <String>{};

  @override
  void initState() {
    super.initState();
    if (_activeTimers.isNotEmpty) {
      _startUpdateTimer();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FloatingTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeInstances != oldWidget.activeInstances) {
      if (_activeTimers.isNotEmpty) {
        _startUpdateTimer();
      }
    }
  }

  void _startUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  List<ActivityInstanceRecord> get _activeTimers {
    return widget.activeInstances.where((instance) {
      if (instance.templateTrackingType != 'time') return false;
      final isVisible = instance.templateShowInFloatingTimer;
      final target = instance.templateTarget ?? 0;
      final tracked = instance.accumulatedTime;
      final notCompleted = target == 0 || tracked < target;
      return instance.isTimerActive &&
          isVisible &&
          notCompleted &&
          !_hiddenAfterStop.contains(instance.reference.id);
    }).toList();
  }

  Future<void> _resetTimer(ActivityInstanceRecord instance) async {
    try {
      await instance.reference.update({
        'accumulatedTime': 0,
        'timerStartTime': null,
        'isTimerActive': false,
      });

      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instance.reference.id,
      );
      widget.onInstanceUpdated?.call(updatedInstance);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting timer: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_activeTimers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 80, // Above bottom navigation
      right: 80, // Increased padding to avoid FAB overlap
      child: Column(
        children:
            _activeTimers.map((instance) => _buildTimerCard(instance)).toList(),
      ),
    );
  }

  Widget _buildTimerCard(ActivityInstanceRecord instance) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).secondaryBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: FlutterFlowTheme.of(context).primary,
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.timer,
                        color: FlutterFlowTheme.of(context).primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          instance.templateName,
                          style:
                              FlutterFlowTheme.of(context).bodyMedium.override(
                                    fontFamily: 'Readex Pro',
                                    fontWeight: FontWeight.w600,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getTimerDisplayWithSeconds(instance),
                    style: FlutterFlowTheme.of(context).titleMedium.override(
                          fontFamily: 'Readex Pro',
                          fontWeight: FontWeight.w600,
                          color: FlutterFlowTheme.of(context).primary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  // Play/Stop button - now full width
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              if (instance.isTimerActive) {
                                // Currently active - stop the timer (pause)
                                await ActivityInstanceService
                                    .toggleInstanceTimer(
                                  instanceId: instance.reference.id,
                                );

                                final updatedInstance =
                                    await ActivityInstanceService
                                        .getUpdatedInstance(
                                  instanceId: instance.reference.id,
                                );
                                widget.onInstanceUpdated?.call(updatedInstance);
                              } else {
                                // Not active - start/resume the timer
                                await ActivityInstanceService
                                    .toggleInstanceTimer(
                                  instanceId: instance.reference.id,
                                );

                                final updatedInstance =
                                    await ActivityInstanceService
                                        .getUpdatedInstance(
                                  instanceId: instance.reference.id,
                                );
                                widget.onInstanceUpdated?.call(updatedInstance);
                              }
                              if (mounted) setState(() {});
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Error controlling timer: $e')),
                                );
                              }
                            }
                          },
                          onLongPress: () async {
                            final shouldForceStop = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Force Stop Timer'),
                                content: const Text(
                                    'Timer seems stuck. Force stop and reset timer state?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text('Force Stop'),
                                  ),
                                ],
                              ),
                            );
                            if (shouldForceStop == true) {
                              try {
                                await instance.reference.update({
                                  'accumulatedTime': 0,
                                  'timerStartTime': null,
                                  'isTimerActive': false,
                                });
                                // Hide this timer after force stop
                                _hiddenAfterStop.add(instance.reference.id);
                                if (mounted) setState(() {});
                                if (widget.onRefresh != null)
                                  await widget.onRefresh!();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Timer force stopped successfully')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Error force stopping timer: $e')),
                                  );
                                }
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                FlutterFlowTheme.of(context).primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(
                            instance.isTimerActive ? 'Stop' : 'Play',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Reset button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _resetTimer(instance),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: const Text('Reset',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Close button positioned in top-right corner
              Positioned(
                top: -4,
                right: -4,
                child: IconButton(
                  onPressed: () {
                    _hiddenAfterStop.add(instance.reference.id);
                    setState(() {});
                  },
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: FlutterFlowTheme.of(context).secondaryText,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        FlutterFlowTheme.of(context).secondaryBackground,
                    padding: const EdgeInsets.all(4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(24, 24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTimerDisplayWithSeconds(ActivityInstanceRecord instance) {
    final accumulated = instance.accumulatedTime;
    int totalMilliseconds = accumulated;

    // Add elapsed time if timer is active
    if (instance.isTimerActive && instance.timerStartTime != null) {
      final elapsed =
          DateTime.now().difference(instance.timerStartTime!).inMilliseconds;
      totalMilliseconds += elapsed;
    }

    final totalSeconds = totalMilliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
