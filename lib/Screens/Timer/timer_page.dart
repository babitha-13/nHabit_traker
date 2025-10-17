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

  const TimerPage({
    super.key,
    this.initialTimerLogRef,
    this.taskTitle,
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
      // Legacy support - this will be removed in future
      _startTimer(fromTask: true);
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

  void _pauseTimer() {
    final duration =
        _isStopwatch ? _stopwatch.elapsed : _countdownDuration - _remainingTime;

    setState(() {
      _isRunning = false;
    });
    if (_isStopwatch) {
      _stopwatch.stop();
    }
    _timer.cancel();

    // Show dialog to get task name and category
    _showTaskNameDialog(isStop: false, duration: duration);
  }

  void _stopTimer() {
    final duration =
        _isStopwatch ? _stopwatch.elapsed : _countdownDuration - _remainingTime;

    setState(() {
      _isRunning = false;
    });
    if (_isStopwatch) {
      _stopwatch.stop();
    }
    _timer.cancel();

    // Show dialog to get task name and category
    _showTaskNameDialog(isStop: true, duration: duration);
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
                  child: const Text('Stop'),
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
