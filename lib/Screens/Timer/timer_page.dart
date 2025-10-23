import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

class TimerPage extends StatefulWidget {
  final DocumentReference? initialTimerLogRef;
  final String? taskTitle;
  final bool fromSwipe;

  const TimerPage({
    super.key,
    this.initialTimerLogRef,
    this.taskTitle,
    this.fromSwipe = false,
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
  List<CategoryRecord> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    if (widget.initialTimerLogRef != null) {
      // Set the task instance reference from swipe action
      _taskInstanceRef = widget.initialTimerLogRef;
      // Auto-start timer when coming from swipe
      if (widget.fromSwipe) {
        _startTimer(fromTask: true);
      }
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await queryTaskCategoriesOnce(userId: currentUserUid);
      setState(() {
        _categories = categories;
      });
    } catch (e) {
      print('Error loading categories: $e');
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
        _pauseTimer();
      } else {
        setState(() {
          if (!_isStopwatch) {
            _remainingTime -= const Duration(seconds: 1);
          }
        });
      }
    });
  }

  void _pauseTimer() async {
    final duration =
        _isStopwatch ? _stopwatch.elapsed : _countdownDuration - _remainingTime;

    setState(() {
      _isRunning = false;
    });
    if (_isStopwatch) {
      _stopwatch.stop();
    }
    _timer.cancel();

    // Stop time logging session if we have an existing task
    if (_taskInstanceRef != null) {
      try {
        await TaskInstanceService.pauseTimeLogging(
          activityInstanceRef: _taskInstanceRef!,
        );
      } catch (e) {
        print('Error pausing time logging: $e');
      }
    }

    // Show dialog to get task name and category (skip if from swipe)
    if (!widget.fromSwipe) {
      _showTaskNameDialog(isStop: false, duration: duration);
    }
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

    // Stop time logging session and mark complete if we have an existing task
    if (_taskInstanceRef != null) {
      try {
        await TaskInstanceService.stopTimeLogging(
          activityInstanceRef: _taskInstanceRef!,
          markComplete: true,
        );
      } catch (e) {
        print('Error stopping time logging: $e');
      }
    }

    // Show dialog to get task name and category (skip if from swipe)
    if (!widget.fromSwipe) {
      _showTaskNameDialog(isStop: true, duration: duration);
    } else {
      // Auto-return to previous page when coming from swipe
      Navigator.of(context).pop();
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
      if (_timer.isActive) {
        _timer.cancel();
      }
    });
  }

  void _showCountdownPicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext builder) {
        return SizedBox(
          height: 250,
          child: CupertinoTimerPicker(
            mode: CupertinoTimerPickerMode.hms,
            initialTimerDuration: _countdownDuration,
            onTimerDurationChanged: (Duration newDuration) {
              setState(() {
                _countdownDuration = newDuration;
              });
            },
          ),
        );
      },
    );
  }

  void _showTaskNameDialog({required bool isStop, required Duration duration}) {
    final taskNameController = TextEditingController();
    String? selectedCategoryId;
    String? selectedCategoryName;

    // Pre-populate with Inbox category if available
    if (_categories.isNotEmpty) {
      final inboxCategory = _categories.firstWhere(
        (c) => c.name == 'Inbox',
        orElse: () => _categories.first,
      );
      selectedCategoryId = inboxCategory.reference.id;
      selectedCategoryName = inboxCategory.name;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(isStop ? 'Stop Timer' : 'Pause Timer'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: taskNameController,
                    decoration: const InputDecoration(
                      labelText: 'Task Name',
                      hintText: 'Enter task name',
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Category (optional)',
                    ),
                    items: _categories.map((category) {
                      return DropdownMenuItem<String>(
                        value: category.reference.id,
                        child: Text(category.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedCategoryId = value;
                        selectedCategoryName = _categories
                            .firstWhere((c) => c.reference.id == value)
                            .name;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Reset timer state
                    _resetTimer();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final taskName = taskNameController.text.trim();
                    if (taskName.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Please enter a task name')),
                      );
                      return;
                    }

                    try {
                      if (_taskInstanceRef != null) {
                        if (isStop) {
                          await TaskInstanceService.updateTimerTaskOnStop(
                            taskInstanceRef: _taskInstanceRef!,
                            duration: duration,
                            taskName: taskName,
                            categoryId: selectedCategoryId,
                            categoryName: selectedCategoryName,
                          );
                        } else {
                          await TaskInstanceService.updateTimerTaskOnPause(
                            taskInstanceRef: _taskInstanceRef!,
                            duration: duration,
                            taskName: taskName,
                            categoryId: selectedCategoryId,
                            categoryName: selectedCategoryName,
                          );
                        }
                      }

                      Navigator.of(context).pop();
                      _resetTimer();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isStop
                              ? 'Timer stopped and task created!'
                              : 'Timer paused and task created!'),
                        ),
                      );
                    } catch (e) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  },
                  child: Text(isStop ? 'Stop' : 'Pause'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _resetTimer() {
    setState(() {
      _isRunning = false;
      _stopwatch.reset();
      _remainingTime = Duration.zero;
      _taskInstanceRef = null;
    });
  }

  @override
  void dispose() {
    if (_timer.isActive) {
      _timer.cancel();
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
                  onPressed: !_isRunning ? null : _pauseTimer,
                  child: const Text('Pause'),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: !_isRunning ? null : _stopTimer,
                  child: const Text('Stop and Complete'),
                ),
              ],
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
