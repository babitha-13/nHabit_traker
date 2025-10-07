import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/timer_service.dart';

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
  DocumentReference? _timerLogRef;

  @override
  void initState() {
    super.initState();
    if (widget.initialTimerLogRef != null) {
      _timerLogRef = widget.initialTimerLogRef;
      _startTimer(fromTask: true);
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
      _timerLogRef = await TimerService.startTimer();
      if (_timerLogRef == null) {
        // Handle error: user not logged in
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Could not log timer start.')),
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
    if (_timerLogRef != null) {
      final duration = _isStopwatch
          ? _stopwatch.elapsed
          : _countdownDuration - _remainingTime;
      TimerService.pauseTimer(_timerLogRef!, duration);
    }

    setState(() {
      _isRunning = false;
    });
    if (_isStopwatch) {
      _stopwatch.stop();
    }
    _timer.cancel();
  }

  void _toggleTimerMode(bool value) {
    setState(() {
      _isStopwatch = value;
      // Reset timer when switching modes
      _isRunning = false;
      _stopwatch.reset();
      _remainingTime = Duration.zero;
      _timerLogRef = null;
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
