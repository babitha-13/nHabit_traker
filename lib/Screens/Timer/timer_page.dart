import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/non_productive_service.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

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
    } catch (e) {}
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

    // Handle auto-complete for swipe or non-productive timers
    if (widget.fromSwipe || widget.isNonProductive) {
      if (_taskInstanceRef != null) {
        try {
          if (widget.isNonProductive) {
            // For non-productive: update with pre-filled name and activity type
            await TaskInstanceService.updateTimerTaskOnPause(
              taskInstanceRef: _taskInstanceRef!,
              duration: duration,
              taskName: widget.taskTitle ?? 'Non-Productive Activity',
              categoryId: null,
              categoryName: null,
              activityType: 'non_productive',
            );
          } else {
            // For swipe: pause time logging
            // Instance already has all template info, just need to pause logging
            await TaskInstanceService.pauseTimeLogging(
              activityInstanceRef: _taskInstanceRef!,
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
      // Stop time logging session if we have an existing task
      if (_taskInstanceRef != null) {
        try {
          await TaskInstanceService.pauseTimeLogging(
            activityInstanceRef: _taskInstanceRef!,
          );
        } catch (e) {}
      }
      // Show dialog to get task name and category
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
      // Stop time logging session and mark complete if we have an existing task
      if (_taskInstanceRef != null) {
        try {
          await TaskInstanceService.stopTimeLogging(
            activityInstanceRef: _taskInstanceRef!,
            markComplete: true,
          );
        } catch (e) {}
      }
      // Show dialog to get task name and category
      _showTaskNameDialog(isStop: true, duration: duration);
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
      try {
        if (_timer.isActive) {
          _timer.cancel();
        }
      } catch (e) {
        // Timer not initialized yet, ignore
      }
    });
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

  void _showTaskNameDialog({required bool isStop, required Duration duration}) {
    final taskNameController =
        TextEditingController(text: widget.taskTitle ?? '');
    String? selectedCategoryId;
    String? selectedCategoryName;
    final bool isNonProductiveMode =
        widget.isNonProductive; // Lock if started from non-productive
    bool isProductive =
        !isNonProductiveMode; // Pre-select based on widget parameter

    // Pre-populate with Inbox category if available
    if (_categories.isNotEmpty) {
      final inboxCategory = _categories.firstWhere(
        (c) => c.name == 'Inbox',
        orElse: () => _categories.first,
      );
      selectedCategoryId = inboxCategory.reference.id;
      selectedCategoryName = inboxCategory.name;
    }

    // Load non-productive templates for autocomplete
    Future<List<String>> loadNonProductiveTemplates() async {
      try {
        final templates = await NonProductiveService.getNonProductiveTemplates(
          userId: currentUserUid,
        );
        return templates.map((t) => t.name).toList();
      } catch (e) {
        return [];
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return FutureBuilder<List<String>>(
              future: loadNonProductiveTemplates(),
              builder: (context, snapshot) {
                final suggestions = snapshot.data ?? [];

                return AlertDialog(
                  title: Text(isStop ? 'Stop Timer' : 'Pause Timer'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Activity Type Toggle - Only show if not locked to non-productive
                        if (!isNonProductiveMode) ...[
                          Text(
                            'Activity Type',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Column(
                            children: [
                              RadioListTile<bool>(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Productive Task'),
                                value: true,
                                groupValue: isProductive,
                                onChanged: (value) {
                                  setDialogState(() {
                                    isProductive = value!;
                                  });
                                },
                              ),
                              RadioListTile<bool>(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Non-Productive'),
                                value: false,
                                groupValue: isProductive,
                                onChanged: (value) {
                                  setDialogState(() {
                                    isProductive = value!;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Task/Activity Name Field with Autocomplete for non-productive
                        if (!isProductive && suggestions.isNotEmpty)
                          Autocomplete<String>(
                            initialValue:
                                TextEditingValue(text: widget.taskTitle ?? ''),
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                              if (textEditingValue.text.isEmpty) {
                                return suggestions;
                              }
                              return suggestions.where((String option) {
                                return option.toLowerCase().contains(
                                    textEditingValue.text.toLowerCase());
                              });
                            },
                            onSelected: (String selection) {
                              taskNameController.text = selection;
                            },
                            fieldViewBuilder: (
                              BuildContext context,
                              TextEditingController fieldTextEditingController,
                              FocusNode fieldFocusNode,
                              VoidCallback onFieldSubmitted,
                            ) {
                              // Initialize with task name if available
                              if (widget.taskTitle != null &&
                                  fieldTextEditingController.text.isEmpty) {
                                fieldTextEditingController.text =
                                    widget.taskTitle!;
                                taskNameController.text = widget.taskTitle!;
                              }
                              // Sync changes from autocomplete field to our controller
                              fieldTextEditingController.addListener(() {
                                taskNameController.text =
                                    fieldTextEditingController.text;
                              });

                              return TextField(
                                controller: fieldTextEditingController,
                                focusNode: fieldFocusNode,
                                decoration: const InputDecoration(
                                  labelText: 'Activity Name',
                                  hintText: 'Enter activity name',
                                ),
                                autofocus: true,
                                onSubmitted: (String value) {
                                  onFieldSubmitted();
                                },
                              );
                            },
                            optionsViewBuilder: (
                              BuildContext context,
                              AutocompleteOnSelected<String> onSelected,
                              Iterable<String> options,
                            ) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4.0,
                                  borderRadius: BorderRadius.circular(4),
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxHeight: 200),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder:
                                          (BuildContext context, int index) {
                                        final String option =
                                            options.elementAt(index);
                                        return InkWell(
                                          onTap: () {
                                            onSelected(option);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Text(option),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        else
                          TextField(
                            controller: taskNameController,
                            decoration: InputDecoration(
                              labelText:
                                  isProductive ? 'Task Name' : 'Activity Name',
                              hintText: isProductive
                                  ? 'Enter task name'
                                  : 'Enter activity name',
                            ),
                            autofocus: true,
                          ),
                        const SizedBox(height: 16),
                        // Category Dropdown (only for productive tasks)
                        if (isProductive)
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
                              setDialogState(() {
                                selectedCategoryId = value;
                                selectedCategoryName = _categories
                                    .firstWhere((c) => c.reference.id == value)
                                    .name;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        // Clean up template and instance if they exist
                        if (_taskInstanceRef != null) {
                          try {
                            final instance =
                                await ActivityInstanceRecord.getDocumentOnce(
                                    _taskInstanceRef!);
                            // Delete the template
                            final templateRef =
                                ActivityRecord.collectionForUser(currentUserUid)
                                    .doc(instance.templateId);
                            await templateRef.delete();
                            // Delete the instance
                            await _taskInstanceRef!.delete();
                          } catch (e) {
                            // Handle error silently - cleanup is best effort
                          }
                        }
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
                            SnackBar(
                              content: Text(isProductive
                                  ? 'Please enter a task name'
                                  : 'Please enter an activity name'),
                            ),
                          );
                          return;
                        }
                        try {
                          if (_taskInstanceRef != null) {
                            final activityType =
                                isProductive ? 'task' : 'non_productive';
                            if (isStop) {
                              await TaskInstanceService.updateTimerTaskOnStop(
                                taskInstanceRef: _taskInstanceRef!,
                                duration: duration,
                                taskName: taskName,
                                categoryId:
                                    isProductive ? selectedCategoryId : null,
                                categoryName:
                                    isProductive ? selectedCategoryName : null,
                                activityType: activityType,
                              );
                            } else {
                              await TaskInstanceService.updateTimerTaskOnPause(
                                taskInstanceRef: _taskInstanceRef!,
                                duration: duration,
                                taskName: taskName,
                                categoryId:
                                    isProductive ? selectedCategoryId : null,
                                categoryName:
                                    isProductive ? selectedCategoryName : null,
                                activityType: activityType,
                              );
                            }
                          }
                          Navigator.of(context).pop();
                          _resetTimer();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isStop
                                  ? (isProductive
                                      ? 'Timer stopped and task created!'
                                      : 'Timer stopped and activity logged!')
                                  : (isProductive
                                      ? 'Timer paused and task created!'
                                      : 'Timer paused and activity logged!')),
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
          final instance =
              await ActivityInstanceRecord.getDocumentOnce(_taskInstanceRef!);
          // Delete the template
          final templateRef = ActivityRecord.collectionForUser(currentUserUid)
              .doc(instance.templateId);
          await templateRef.delete();
          // Delete the instance
          await _taskInstanceRef!.delete();
        } catch (e) {
          // Handle error silently - cleanup is best effort
        }
      }

      // Reset timer state and go back (only if still mounted)
      if (mounted) {
        _resetTimer();
        Navigator.of(context).pop();
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
            const SizedBox(height: 16),
            // Discard button - only show if timer has been started
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
