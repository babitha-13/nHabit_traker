import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/Task%20Instance%20Service/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/Helpers/sound_helper.dart';
import 'package:habit_tracker/Screens/Shared/Manual_Time_Log/manual_time_log_helper.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/TimeManager.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/timer_stop_flow.dart';
import '../timer_page.dart';

mixin TimerPageLogic on State<TimerPage>, WidgetsBindingObserver {
  bool isStopwatch = true;
  bool isRunning = false;
  Timer? timer;
  Duration countdownDuration = const Duration(minutes: 10);
  Duration remainingTime = Duration.zero;
  DocumentReference? taskInstanceRef;
  DateTime? timerStartTime;
  String? templateTrackingType;
  Duration stopwatchElapsed = Duration.zero;
  DateTime? stopwatchRunStart;
  DateTime? countdownEndTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    remainingTime = countdownDuration;
    if (widget.initialTimerLogRef != null) {
      taskInstanceRef = widget.initialTimerLogRef;
      if (widget.fromNotification) {
        _resumeRunningTimer();
      } else if (widget.fromSwipe) {
        loadInstanceData();
        startTimer(fromTask: true);
      }
    }
  }

  /// Sync UI with an already-running instance (e.g. opened from notification). Does not call startTimeLogging.
  Future<void> _resumeRunningTimer() async {
    if (taskInstanceRef == null) return;
    try {
      final instance =
          await ActivityInstanceRecord.getDocumentOnce(taskInstanceRef!);
      if (!mounted) return;
      setState(() {
        templateTrackingType = instance.templateTrackingType;
        isStopwatch = true;
        isRunning = true;
        if (instance.templateTrackingType == 'binary' &&
            (instance.isTimeLogging ||
                instance.currentSessionStartTime != null)) {
          stopwatchElapsed = Duration(milliseconds: instance.totalTimeLogged);
          stopwatchRunStart =
              instance.currentSessionStartTime ?? instance.timerStartTime;
        } else {
          stopwatchElapsed = Duration(milliseconds: instance.accumulatedTime);
          stopwatchRunStart = instance.timerStartTime;
        }
      });
      startTicker();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resuming timer: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cancelTicker();
    super.dispose();
  }

  Future<void> loadInstanceData() async {
    if (taskInstanceRef == null) return;
    try {
      final instance =
          await ActivityInstanceRecord.getDocumentOnce(taskInstanceRef!);
      if (mounted) {
        setState(() {
          templateTrackingType = instance.templateTrackingType;
        });
      }
    } catch (e) {
      print('Error loading instance data: $e');
    }
  }

  Duration currentStopwatchElapsed() {
    if (!isStopwatch) return Duration.zero;
    final base = stopwatchElapsed;
    if (isRunning && stopwatchRunStart != null) {
      return base + DateTime.now().difference(stopwatchRunStart!);
    }
    return base;
  }

  Duration currentCountdownRemaining() {
    if (countdownEndTime == null) return remainingTime;
    final remaining = countdownEndTime!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void startTicker() {
    cancelTicker();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isStopwatch) {
        final remaining = currentCountdownRemaining();
        if (remaining <= Duration.zero) {
          remainingTime = Duration.zero;
          stopTimer();
        } else if (mounted) {
          setState(() {
            remainingTime = remaining;
          });
        }
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  void cancelTicker() {
    if (timer == null) return;
    timer!.cancel();
    timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isRunning) return;
    if (state == AppLifecycleState.resumed) {
      if (isStopwatch && mounted) {
        setState(() {});
      } else if (!isStopwatch && countdownEndTime != null) {
        final remaining = currentCountdownRemaining();
        if (remaining <= Duration.zero) {
          remainingTime = Duration.zero;
          stopTimer();
        } else if (mounted) {
          setState(() {
            remainingTime = remaining;
          });
        }
      }
    }
  }

  String formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  void startTimer({bool fromTask = false}) async {
    SoundHelper().playPlayButtonSound();
    cancelTicker();
    if (!fromTask) {
      try {
        taskInstanceRef = await TaskInstanceService.createTimerTaskInstance();
        timerStartTime = DateTime.now();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Could not start timer. $e')),
        );
        return;
      }
    } else if (taskInstanceRef != null) {
      try {
        await TaskInstanceService.startTimeLogging(
          activityInstanceRef: taskInstanceRef!,
        );
        timerStartTime = DateTime.now();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Could not resume timer. $e')),
        );
        return;
      }
    }
    setState(() {
      isRunning = true;
    });
    if (isStopwatch) {
      stopwatchElapsed = Duration.zero;
      stopwatchRunStart = DateTime.now();
    } else {
      remainingTime =
          remainingTime > Duration.zero ? remainingTime : countdownDuration;
      countdownEndTime = DateTime.now().add(remainingTime);
    }
    startTicker();
  }

  void stopTimer() async {
    await stopTimerInternal(markComplete: false);
  }

  void stopAndCompleteTimer() async {
    await stopTimerInternal(markComplete: true);
  }

  Future<void> stopTimerInternal({required bool markComplete}) async {
    SoundHelper().playStopButtonSound();
    final currentStopwatch = currentStopwatchElapsed();
    final currentRemaining = currentCountdownRemaining();
    Duration duration;
    if (isStopwatch) {
      duration = currentStopwatch;
    } else {
      final elapsed = countdownDuration - currentRemaining;
      duration = elapsed.isNegative ? Duration.zero : elapsed;
    }
    setState(() {
      isRunning = false;
      if (isStopwatch) {
        stopwatchElapsed = currentStopwatch;
        stopwatchRunStart = null;
      } else {
        remainingTime = currentRemaining;
        countdownEndTime = null;
      }
    });
    cancelTicker();

    final shouldSaveDirectly =
        widget.fromSwipe || widget.isessential || widget.fromNotification;

    if (shouldSaveDirectly) {
      if (taskInstanceRef == null) {
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
        if (widget.isessential) {
          await TaskInstanceService.updateTimerTaskOnStop(
            taskInstanceRef: taskInstanceRef!,
            duration: duration,
            taskName: widget.taskTitle ?? 'essential Activity',
            categoryId: null,
            categoryName: null,
            activityType: 'essential',
          );
        } else {
          await TaskInstanceService.stopTimeLogging(
            activityInstanceRef: taskInstanceRef!,
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
      if (taskInstanceRef != null) {
        try {
          final instance =
              await ActivityInstanceRecord.getDocumentOnce(taskInstanceRef!);

          final success = await TimerStopFlow.handleTimerStop(
            context: context,
            instance: instance,
            markComplete: markComplete,
            timerStartTime: timerStartTime,
            localDuration: duration,
            onSaveComplete: () {
              resetTimer();
            },
          );

          if (!success && mounted) {
            resetTimer();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }
      } else {
        DateTime startTime;
        DateTime endTime = DateTime.now();

        if (timerStartTime != null) {
          startTime = timerStartTime!;
        } else {
          startTime = endTime.subtract(duration);
        }

        showTimeLogModal(
          startTime: startTime,
          endTime: endTime,
          markCompleteOnSave: markComplete,
        );
      }
    }
  }

  void toggleTimerMode(bool value) {
    setState(() {
      isStopwatch = value;
      isRunning = false;
      stopwatchElapsed = Duration.zero;
      stopwatchRunStart = null;
      remainingTime = Duration.zero;
      countdownEndTime = null;
      taskInstanceRef = null;
      timerStartTime = null;
      cancelTicker();
    });

    if (!value && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showCountdownPicker();
        }
      });
    }
  }

  void showTimeLogModal({
    required DateTime startTime,
    required DateTime endTime,
    required bool markCompleteOnSave,
  }) {
    final selectedDate = DateTime(
      startTime.year,
      startTime.month,
      startTime.day,
    );

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
          fromTimer: true,
          onSave: () {
            saveState[0] = true;
            if (taskInstanceRef != null) {
              TaskInstanceService.discardTimeLogging(
                activityInstanceRef: taskInstanceRef!,
              ).catchError((e) {});
            }
            resetTimer();
          },
        );
      },
    ).then((_) {
      if (!saveState[0] && taskInstanceRef != null && mounted) {
        cleanupTimerInstance();
      }
    }).catchError((_) {
      if (!saveState[0] && taskInstanceRef != null && mounted) {
        cleanupTimerInstance();
      }
    });
  }

  Future<void> cleanupTimerInstance() async {
    if (taskInstanceRef == null) return;

    try {
      try {
        await TaskInstanceService.discardTimeLogging(
          activityInstanceRef: taskInstanceRef!,
        );
      } catch (e) {}

      final instance =
          await ActivityInstanceRecord.getDocumentOnce(taskInstanceRef!);
      if (!widget.fromSwipe && !widget.fromNotification) {
        if (instance.hasTemplateId()) {
          final userId = await waitForCurrentUserUid();
          if (userId.isNotEmpty) {
            final templateRef = ActivityRecord.collectionForUser(userId)
                .doc(instance.templateId);
            await templateRef.delete();
          }
        }
        await taskInstanceRef!.delete();
      }
    } catch (e) {
    } finally {
      if (mounted) {
        setState(() {
          taskInstanceRef = null;
          timerStartTime = null;
        });
      }
    }
  }

  void showCountdownPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext builder) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 64),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoTimerPicker(
                  mode: CupertinoTimerPickerMode.hms,
                  initialTimerDuration: countdownDuration,
                  onTimerDurationChanged: (Duration newDuration) {
                    setState(() {
                      countdownDuration = newDuration;
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
                        remainingTime = countdownDuration;
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

  Future<void> discardTimer() async {
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
      if (isRunning) {
        final stopwatchValue = currentStopwatchElapsed();
        final countdownRemainingValue = currentCountdownRemaining();
        setState(() {
          isRunning = false;
          if (isStopwatch) {
            stopwatchElapsed = stopwatchValue;
            stopwatchRunStart = null;
          } else {
            remainingTime = countdownRemainingValue;
            countdownEndTime = null;
          }
        });
        cancelTicker();
      }

      if (taskInstanceRef != null) {
        try {
          if (widget.fromSwipe || widget.fromNotification) {
            await TaskInstanceService.discardTimeLogging(
              activityInstanceRef: taskInstanceRef!,
            );
          } else {
            final instance =
                await ActivityInstanceRecord.getDocumentOnce(taskInstanceRef!);
            if (instance.hasTemplateId()) {
              final userId = await waitForCurrentUserUid();
              if (userId.isNotEmpty) {
                final templateRef = ActivityRecord.collectionForUser(userId)
                    .doc(instance.templateId);
                await templateRef.delete();
              }
            }
            await taskInstanceRef!.delete();
          }
        } catch (e) {}
      }

      if (mounted) {
        if (widget.fromSwipe || widget.fromNotification) {
          Navigator.of(context).pop();
        } else {
          resetTimer();
        }
      }
    }
  }

  void resetTimer() {
    if (mounted) {
      setState(() {
        isRunning = false;
        stopwatchElapsed = Duration.zero;
        stopwatchRunStart = null;
        remainingTime = Duration.zero;
        countdownEndTime = null;
        taskInstanceRef = null;
        timerStartTime = null;
      });
    }
    cancelTicker();
  }

  Future<bool> onWillPop() async {
    if (isRunning && taskInstanceRef != null) {
      try {
        await taskInstanceRef!.update({
          'templateShowInFloatingTimer': true,
        });

        final instance =
            await ActivityInstanceRecord.getDocumentOnce(taskInstanceRef!);
        TimerManager().startInstance(instance);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Timer is still running in the floating timer'),
              duration: Duration(seconds: 2),
            ),
          );
        }

        setState(() {
          isRunning = false;
          if (isStopwatch) {
            stopwatchElapsed = currentStopwatchElapsed();
            stopwatchRunStart = null;
          } else {
            remainingTime = currentCountdownRemaining();
            countdownEndTime = null;
          }
        });
        cancelTicker();

        return true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error handing off timer: $e')),
          );
        }
        return true;
      }
    }

    return true;
  }
}
