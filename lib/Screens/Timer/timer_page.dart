import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Screens/Components/manual_time_log_modal.dart';
import 'package:flutter/foundation.dart';

class TimerPage extends StatefulWidget {
  final DocumentReference? initialTimerLogRef;
  final String? taskTitle;
  final bool fromSwipe;
  final bool isNonProductive; // Indicates if this is a non-productive activity
  const TimerPage({
    super.key,
    this.initialTimerLogRef,
    this.taskTitle,
    this.fromSwipe = false,
    this.isNonProductive = false,
  });
  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  bool _isStopwatch = true;
  bool _isRunning = false;
  final Stopwatch _stopwatch = Stopwatch();
  late Timer _timer;
  Duration _countdownDuration = const Duration(minutes: 10);
  Duration _remainingTime = Duration.zero;
  DocumentReference? _taskInstanceRef;
  DateTime? _timerStartTime; // Track when timer started
  @override
  void initState() {
    super.initState();
    if (widget.initialTimerLogRef != null) {
      // Set the task instance reference from swipe action
      _taskInstanceRef = widget.initialTimerLogRef;
      // Auto-start timer when coming from swipe
      if (widget.fromSwipe) {
        _startTimer(fromTask: true);
      }
    }
  }

  String _formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  void _startTimer({bool fromTask = false}) async {
    if (!fromTask) {
      try {
        _taskInstanceRef = await TaskInstanceService.createTimerTaskInstance();
        // Track start time when creating new timer instance
        _timerStartTime = DateTime.now();
      } catch (e) {
        // Handle error: user not logged in or other issues
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Could not start timer. $e')),
        );
        return;
      }
    } else if (_taskInstanceRef != null) {
      // Resume existing task - start new session
      try {
        await TaskInstanceService.startTimeLogging(
          activityInstanceRef: _taskInstanceRef!,
        );
        // Track start time for resumed session
        _timerStartTime = DateTime.now();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Could not resume timer. $e')),
        );
        return;
      }
    }
    setState(() {
      _isRunning = true;
    });
    if (_isStopwatch) {
      _stopwatch.start();
    } else {
      _remainingTime =
          _remainingTime > Duration.zero ? _remainingTime : _countdownDuration;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isStopwatch && _remainingTime.inSeconds <= 0) {
        _stopTimer();
      } else {
        if (mounted) {
          setState(() {
            if (!_isStopwatch) {
              _remainingTime -= const Duration(seconds: 1);
            }
          });
        }
      }
    });
  }

  void _stopTimer() async {
    final duration =
        _isStopwatch ? _stopwatch.elapsed : _countdownDuration - _remainingTime;
    setState(() {
      _isRunning = false;
    });
    if (_isStopwatch) {
      _stopwatch.stop();
    }
    _timer.cancel();

    // Handle auto-complete for swipe or non-productive timers
    if (widget.fromSwipe || widget.isNonProductive) {
      if (_taskInstanceRef != null) {
        try {
          if (widget.isNonProductive) {
            // For non-productive: update with pre-filled name and activity type
            await TaskInstanceService.updateTimerTaskOnStop(
              taskInstanceRef: _taskInstanceRef!,
              duration: duration,
              taskName: widget.taskTitle ?? 'Non-Productive Activity',
              categoryId: null,
              categoryName: null,
              activityType: 'non_productive',
            );
          } else {
            // For swipe: stop time logging and mark complete
            // Instance already has all template info, just need to stop logging and mark complete
            await TaskInstanceService.stopTimeLogging(
              activityInstanceRef: _taskInstanceRef!,
              markComplete: true,
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error saving timer: $e')),
            );
          }
        }
      }
      // Auto-return to previous page
      if (mounted) {
        Navigator.of(context).pop();
      }
    } else {
      // Calculate start and end times for the modal
      DateTime startTime;
      DateTime endTime = DateTime.now();

      // Get start time from tracked value or from instance
      // Keep the session active until modal resolves (save or cancel)
      if (_timerStartTime != null) {
        startTime = _timerStartTime!;
      } else if (_taskInstanceRef != null) {
        try {
          final instance =
              await ActivityInstanceRecord.getDocumentOnce(_taskInstanceRef!);
          // Use currentSessionStartTime if available, otherwise calculate from duration
          startTime =
              instance.currentSessionStartTime ?? endTime.subtract(duration);
        } catch (e) {
          // Fallback: calculate from duration
          startTime = endTime.subtract(duration);
        }
      } else {
        // Fallback: calculate from duration
        startTime = endTime.subtract(duration);
      }

      // Don't clear session start time yet - we need it for the modal
      // It will be cleared when modal saves (via logManualTimeEntry) or cancels (via cleanup)

      // Show modal to get activity details
      _showTimeLogModal(startTime: startTime, endTime: endTime);
    }
  }

  void _toggleTimerMode(bool value) {
    setState(() {
      _isStopwatch = value;
      // Reset timer when switching modes
      _isRunning = false;
      _stopwatch.reset();
      _remainingTime = Duration.zero;
      _taskInstanceRef = null;
      _timerStartTime = null;
      try {
        if (_timer.isActive) {
          _timer.cancel();
        }
      } catch (e) {
        // Timer not initialized yet, ignore
      }
    });
  }

  void _showTimeLogModal(
      {required DateTime startTime, required DateTime endTime}) {
    // Get the date from start time for the modal
    final selectedDate = DateTime(
      startTime.year,
      startTime.month,
      startTime.day,
    );

    // Use a mutable list to track save state (workaround for closure capture)
    final saveState = <bool>[false];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return ManualTimeLogModal(
          selectedDate: selectedDate,
          initialStartTime: startTime,
          initialEndTime: endTime,
          fromTimer:
              true, // Indicate this is from timer for auto-completion logic
          onSave: () {
            saveState[0] = true; // Mark as saved before resetting
            // Clear the timer instance's session since time was logged to selected template
            if (_taskInstanceRef != null) {
              TaskInstanceService.discardTimeLogging(
                activityInstanceRef: _taskInstanceRef!,
              ).catchError((e) {
                // Ignore errors - instance might already be cleaned up
                // Error clearing timer session after save
              });
            }
            // Reset timer after saving
            _resetTimer();
          },
        );
      },
    ).then((_) {
      // Modal was closed - check if it was saved
      // If not saved, clean up the timer instance
      if (!saveState[0] && _taskInstanceRef != null && mounted) {
        _cleanupTimerInstance();
      }
    }).catchError((_) {
      // Handle any errors, but still cleanup if needed
      if (!saveState[0] && _taskInstanceRef != null && mounted) {
        _cleanupTimerInstance();
      }
    });
  }

  Future<void> _cleanupTimerInstance() async {
    if (_taskInstanceRef == null) return;

    try {
      // First, discard the active session (clears currentSessionStartTime)
      // This prevents partial sessions from being left behind
      try {
        await TaskInstanceService.discardTimeLogging(
          activityInstanceRef: _taskInstanceRef!,
        );
      } catch (e) {
        // If discard fails (e.g., no active session), continue with cleanup
        // Error discarding timer session
      }

      // Check if instance still exists
      final instance =
          await ActivityInstanceRecord.getDocumentOnce(_taskInstanceRef!);
      // If it's a temporary timer instance (not from swipe), delete it
      if (!widget.fromSwipe) {
        // Delete the template if templateId exists
        if (instance.hasTemplateId()) {
          final templateRef = ActivityRecord.collectionForUser(currentUserUid)
              .doc(instance.templateId);
          await templateRef.delete();
        }
        // Delete the instance
        await _taskInstanceRef!.delete();
      }
      // If from swipe, discardTimeLogging was already called above
    } catch (e) {
      // Handle error silently - cleanup is best effort
      // Error cleaning up timer instance
    } finally {
      if (mounted) {
        setState(() {
          _taskInstanceRef = null;
          _timerStartTime = null;
        });
      }
    }
  }

  void _showCountdownPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext builder) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(
                16, 8, 16, 64), // 16 + 48 = 64px bottom padding
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.hms,
                  initialTimerDuration: _countdownDuration,
                  onTimerDurationChanged: (Duration newDuration) {
                    setState(() {
                      _countdownDuration = newDuration;
                    });
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _remainingTime = _countdownDuration;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _discardTimer() async {
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
            child: const Text('Cancel'),
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

    if (confirmed == true) {
      // Stop timer if running
      if (_isRunning) {
        if (_isStopwatch) {
          _stopwatch.stop();
        }
        try {
          if (_timer.isActive) {
            _timer.cancel();
          }
        } catch (e) {
          // Timer not initialized yet, ignore
        }
      }

      // Clean up template and instance if they exist
      if (_taskInstanceRef != null) {
        try {
          if (widget.fromSwipe) {
            // If from swipe, just discard timer status without deleting instance
            await TaskInstanceService.discardTimeLogging(
              activityInstanceRef: _taskInstanceRef!,
            );
          } else {
            // For temporary timer (not from swipe), delete instance and template
            final instance =
                await ActivityInstanceRecord.getDocumentOnce(_taskInstanceRef!);
            // Delete the template if templateId exists
            if (instance.hasTemplateId()) {
              final templateRef =
                  ActivityRecord.collectionForUser(currentUserUid)
                      .doc(instance.templateId);
              await templateRef.delete();
            }
            // Delete the instance
            await _taskInstanceRef!.delete();
          }
        } catch (e) {
          // Handle error silently - cleanup is best effort
        }
      }

      // Go back or reset timer
      if (mounted) {
        if (widget.fromSwipe) {
          Navigator.of(context).pop();
        } else {
          _resetTimer();
        }
      }
    }
  }

  void _resetTimer() {
    if (mounted) {
      setState(() {
        _isRunning = false;
        _stopwatch.reset();
        _remainingTime = Duration.zero;
        _taskInstanceRef = null;
      });
    }
  }

  @override
  void dispose() {
    try {
      if (_timer.isActive) {
        _timer.cancel();
      }
    } catch (e) {
      // Timer not initialized yet, ignore
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayTime = _isStopwatch ? _stopwatch.elapsed : _remainingTime;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.taskTitle ?? 'Timer'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Prominent task name display
            if (widget.taskTitle != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                  widget.taskTitle!,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).primaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            Text(
              _formatTime(displayTime),
              style: const TextStyle(fontSize: 72),
            ),
            const SizedBox(height: 30),
            if (!_isStopwatch)
              TextButton(
                onPressed: _showCountdownPicker,
                child: const Text('Set Countdown Duration'),
              ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _isRunning ? null : () => _startTimer(),
                  child: const Text('Start'),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: !_isRunning ? null : _stopTimer,
                  child: const Text('Stop and Complete'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Discard button - show if timer instance exists (started but not saved)
            // This allows user to discard even after stopping and canceling modal
            if (_taskInstanceRef != null)
              TextButton.icon(
                onPressed: _discardTimer,
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
                  value: _isStopwatch,
                  onChanged: _toggleTimerMode,
                ),
                const Text('Stopwatch'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
