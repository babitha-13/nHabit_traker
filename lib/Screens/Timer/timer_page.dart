import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/sound_helper.dart';
import 'package:habit_tracker/Helper/utils/TimeManager.dart';
import 'package:habit_tracker/Screens/Components/manual_time_log_modal.dart';
import 'package:habit_tracker/Screens/Timer/timer_stop_flow.dart';

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
  String? _templateTrackingType; // Store tracking type for button logic
  @override
  void initState() {
    super.initState();
    if (widget.initialTimerLogRef != null) {
      // Set the task instance reference from swipe action
      _taskInstanceRef = widget.initialTimerLogRef;
      // Load instance data to get tracking type if from swipe
      if (widget.fromSwipe) {
        _loadInstanceData();
        // Auto-start timer when coming from swipe
        _startTimer(fromTask: true);
      }
    }
  }

  /// Load instance data to determine tracking type for button logic
  Future<void> _loadInstanceData() async {
    if (_taskInstanceRef == null) return;
    try {
      final instance =
          await ActivityInstanceRecord.getDocumentOnce(_taskInstanceRef!);
      if (mounted) {
        setState(() {
          _templateTrackingType = instance.templateTrackingType;
        });
      }
    } catch (e) {
      // If loading fails, continue without tracking type (will use fallback)
      print('Error loading instance data: $e');
    }
  }

  String _formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  void _startTimer({bool fromTask = false}) async {
    // Play play button sound
    SoundHelper().playPlayButtonSound();
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

  /// Stop timer and log time (without marking complete)
  void _stopTimer() async {
    await _stopTimerInternal(markComplete: false);
  }

  /// Stop timer, log time, AND mark task as complete
  void _stopAndCompleteTimer() async {
    await _stopTimerInternal(markComplete: true);
  }

  /// Internal method to handle timer stopping with optional completion
  Future<void> _stopTimerInternal({required bool markComplete}) async {
    // Play stop button sound
    SoundHelper().playStopButtonSound();
    final duration =
        _isStopwatch ? _stopwatch.elapsed : _countdownDuration - _remainingTime;
    setState(() {
      _isRunning = false;
    });
    if (_isStopwatch) {
      _stopwatch.stop();
    }
    _timer.cancel();

    final shouldSaveDirectly = widget.fromSwipe || widget.isNonProductive;

    // Handle swipe-started timers or explicitly non-productive sessions inline.
    if (shouldSaveDirectly) {
      if (_taskInstanceRef == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to save timer session. Please try again.'),
            ),
          );
        }
        return;
      }
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
          // For swipe-started instances: stop time logging (with or without completion based on button pressed)
          // For binary tasks: markComplete is true for "Stop and Complete", false for "Stop"
          // For qty/time tasks: always false (completion is automatic based on progress)
          await TaskInstanceService.stopTimeLogging(
            activityInstanceRef: _taskInstanceRef!,
            markComplete: markComplete,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving timer: $e')),
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } else {
      // Use shared timer stop flow
      if (_taskInstanceRef != null) {
        try {
          final instance =
              await ActivityInstanceRecord.getDocumentOnce(_taskInstanceRef!);
          
          final success = await TimerStopFlow.handleTimerStop(
            context: context,
            instance: instance,
            markComplete: markComplete,
            timerStartTime: _timerStartTime,
            localDuration: duration,
            onSaveComplete: () {
              // Reset timer after saving
              _resetTimer();
            },
          );
          
          if (!success && mounted) {
            // Modal was cancelled, cleanup already handled by TimerStopFlow
            _resetTimer();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }
      } else {
        // Fallback: calculate times manually if no instance
        DateTime startTime;
        DateTime endTime = DateTime.now();
        
        if (_timerStartTime != null) {
          startTime = _timerStartTime!;
        } else {
          startTime = endTime.subtract(duration);
        }
        
        _showTimeLogModal(
          startTime: startTime,
          endTime: endTime,
          markCompleteOnSave: markComplete,
        );
      }
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
    
    // Auto-open countdown picker when switching to countdown mode
    if (!value && mounted) {
      // Use addPostFrameCallback to ensure state update completes first
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showCountdownPicker();
        }
      });
    }
  }

  void _showTimeLogModal({
    required DateTime startTime,
    required DateTime endTime,
    required bool markCompleteOnSave,
  }) {
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
          markCompleteOnSave: markCompleteOnSave,
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

  /// Build stop buttons based on tracking type
  Widget _buildStopButtons() {
    // For qty/time tasks from swipe: show only "Stop" (completion is automatic)
    if (widget.fromSwipe &&
        (_templateTrackingType == 'quantitative' ||
            _templateTrackingType == 'time')) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: _isRunning ? null : () => _startTimer(),
            child: const Text('Start'),
          ),
          const SizedBox(width: 20),
          ElevatedButton(
            onPressed: !_isRunning ? null : _stopTimer,
            child: const Text('Stop'),
          ),
        ],
      );
    }
    
    // For binary tasks from swipe OR timer-created instances (non-swipe): show both buttons
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: _isRunning ? null : () => _startTimer(),
          child: const Text('Start'),
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          onPressed: !_isRunning ? null : _stopTimer,
          child: const Text('Stop'),
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          onPressed: !_isRunning ? null : _stopAndCompleteTimer,
          child: const Text('Stop and Complete'),
        ),
      ],
    );
  }

  /// Handle back button - preserve timer session to floating timer
  Future<bool> _onWillPop() async {
    // If timer is running and has an instance, hand it off to floating timer
    if (_isRunning && _taskInstanceRef != null) {
      try {
        // Ensure the instance is set to show in floating timer
        await _taskInstanceRef!.update({
          'templateShowInFloatingTimer': true,
        });
        
        // Load the updated instance and register with TimerManager
        final instance = await ActivityInstanceRecord.getDocumentOnce(_taskInstanceRef!);
        TimerManager().startInstance(instance);
        
        // Show feedback message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Timer is still running in the floating timer'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        
        // Reset local state but keep Firestore timer active
        setState(() {
          _isRunning = false;
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
        });
        
        // Allow navigation
        return true;
      } catch (e) {
        // If handoff fails, show error but still allow navigation
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error handing off timer: $e')),
          );
        }
        return true;
      }
    }
    
    // If no active timer, allow normal back navigation
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final displayTime = _isStopwatch ? _stopwatch.elapsed : _remainingTime;
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
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
            // Make displayed time clickable in countdown mode
            GestureDetector(
              onTap: !_isStopwatch ? _showCountdownPicker : null,
              child: Text(
                _formatTime(displayTime),
                style: TextStyle(
                  fontSize: 72,
                  color: !_isStopwatch
                      ? Theme.of(context).primaryColor
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 30),
            // Show different buttons based on tracking type and context
            _buildStopButtons(),
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
      ),
    );
  }
}
