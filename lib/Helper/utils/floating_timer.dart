import 'dart:async';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/habit_tracking_util.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

class FloatingTimer extends StatefulWidget {
  final List<HabitRecord> activeHabits;
  final Future<void> Function()? onRefresh;
  final void Function(HabitRecord updatedHabit)? onHabitUpdated;

  const FloatingTimer({
    Key? key,
    required this.activeHabits,
    this.onRefresh,
    this.onHabitUpdated,
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
    if (widget.activeHabits != oldWidget.activeHabits) {
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

  List<HabitRecord> get _activeTimers {
    return widget.activeHabits.where((habit) {
      if (habit.trackingType != 'time') return false;
      final isVisible = habit.showInFloatingTimer ?? true;
      final target = HabitTrackingUtil.getTargetDuration(habit);
      final tracked = HabitTrackingUtil.getTrackedTime(habit);
      final notCompleted = target == Duration.zero || tracked < target;
      return habit.isTimerActive && isVisible && notCompleted && !_hiddenAfterStop.contains(habit.reference.id);
    }).toList();
  }

  Future<void> _resetTimer(HabitRecord habit) async {
    try {
      await habit.reference.update({
        'accumulatedTime': 0,
        'timerStartTime': null,
        'isTimerActive': false,
        'showInFloatingTimer': true,
      });
      final updatedHabit = HabitRecord.getDocumentFromData(
        {...habit.snapshotData,
          'accumulatedTime': 0,
          'timerStartTime': null,
          'isTimerActive': false,
          'showInFloatingTimer': true},
        habit.reference,
      );
      widget.onHabitUpdated?.call(updatedHabit);
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
        children: _activeTimers.map((habit) => _buildTimerCard(habit)).toList(),
      ),
    );
  }

  Widget _buildTimerCard(HabitRecord habit) {
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
                          habit.name,
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
                    HabitTrackingUtil.getTimerDisplayTextWithSeconds(habit),
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
                              if (habit.isTimerActive) {
                                // Currently active - stop the timer (pause)

                                // Update local state immediately for instant UI feedback
                                final updatedHabitData = createHabitRecordData(
                                  isTimerActive: false,
                                  showInFloatingTimer: true,
                                );
                                final updatedHabit =
                                    HabitRecord.getDocumentFromData(
                                  {
                                    ...habit.snapshotData,
                                    ...updatedHabitData,
                                  },
                                  habit.reference,
                                );
                                widget.onHabitUpdated?.call(updatedHabit);

                                await HabitTrackingUtil.pauseTimer(habit);
                              } else {
                                // Not active - start/resume the timer

                                // Update local state immediately for instant UI feedback
                                final updatedHabitData = createHabitRecordData(
                                  isTimerActive: true,
                                  showInFloatingTimer: true,
                                  timerStartTime: DateTime.now(),
                                );
                                final updatedHabit =
                                    HabitRecord.getDocumentFromData(
                                  {
                                    ...habit.snapshotData,
                                    ...updatedHabitData,
                                  },
                                  habit.reference,
                                );
                                widget.onHabitUpdated?.call(updatedHabit);

                                await HabitTrackingUtil.startTimer(habit);
                              }
                              if (mounted) setState(() {});
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Error controlling timer: $e')),
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
                                await HabitTrackingUtil.forceStopTimer(habit);
                                // Hide this timer after force stop
                                _hiddenAfterStop.add(habit.reference.id);
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
                                        content:
                                            Text('Error force stopping timer: $e')),
                                  );
                                }
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: FlutterFlowTheme.of(context).primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(
                            habit.isTimerActive ? 'Stop' : 'Play',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Reset button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _resetTimer(habit),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: const Text('Reset', style: TextStyle(fontSize: 12)),
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
                    _hiddenAfterStop.add(habit.reference.id);
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
}
