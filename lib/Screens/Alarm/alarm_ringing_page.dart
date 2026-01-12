import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Screens/Queue/queue_page.dart';
import 'package:habit_tracker/Screens/Components/Dialogs/snooze_dialog.dart';
import 'package:habit_tracker/Helper/utils/constants.dart';
import 'package:habit_tracker/main.dart';

class AlarmRingingPage extends StatefulWidget {
  final String title;
  final String? body;
  final String? payload;

  const AlarmRingingPage({
    super.key,
    required this.title,
    this.body,
    this.payload,
  });

  @override
  State<AlarmRingingPage> createState() => _AlarmRingingPageState();
}

class _AlarmRingingPageState extends State<AlarmRingingPage>
    with WidgetsBindingObserver {
  late AudioPlayer _audioPlayer;
  ActivityInstanceRecord? _instance;
  bool _isLoadingInstance = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAlarm();
    _loadInstance();
  }

  Future<void> _loadInstance() async {
    try {
      if (widget.payload == null) {
        setState(() => _isLoadingInstance = false);
        return;
      }

      // Parse payload - could be instanceId directly or ALARM_RINGING:title|body|instanceId
      String? instanceId;
      if (widget.payload!.startsWith('ALARM_RINGING:')) {
        final parts =
            widget.payload!.substring('ALARM_RINGING:'.length).split('|');
        if (parts.length >= 3) {
          instanceId = parts[2];
        }
      } else {
        instanceId = widget.payload;
      }

      if (instanceId == null || instanceId.isEmpty) {
        setState(() => _isLoadingInstance = false);
        return;
      }

      // Get instance
      final userId = currentUserUid;
      if (userId.isEmpty) {
        setState(() => _isLoadingInstance = false);
        return;
      }

      final instances = await queryAllInstances(userId: userId);
      final instance = instances.firstWhere(
        (i) => i.reference.id == instanceId,
        orElse: () => instances.firstWhere(
          (i) => i.templateId == instanceId,
          orElse: () => instances.first,
        ),
      );

      setState(() {
        _instance = instance;
        _isLoadingInstance = false;
      });
    } catch (e) {
      print('AlarmRingingPage: Error loading instance: $e');
      setState(() => _isLoadingInstance = false);
    }
  }

  Future<void> _initializeAlarm() async {
    _audioPlayer = AudioPlayer();

    // Configure audio session for playback
    try {
      // Loop the alarm sound
      await _audioPlayer.setLoopMode(LoopMode.one);

      // Load a default alarm sound (ensure you have one in assets or use a system sound if possible)
      // For now we'll use a placeholder or asset. Ideally, bundle a 'alarm.mp3' in assets.
      // If no asset, just vibration will work for testing.
      // await _audioPlayer.setAsset('assets/audios/alarm.mp3');

      // Start vibration
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 0);
      }

      // Start playing
      // await _audioPlayer.play();

      setState(() {
        // Alarm is initialized
      });
    } catch (e) {
      print('Error playing alarm: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAlarm();
    super.dispose();
  }

  Future<void> _stopAlarm() async {
    try {
      _audioPlayer.stop();
      _audioPlayer.dispose();
      Vibration.cancel();
    } catch (e) {
      print('Error stopping alarm: $e');
    }
  }

  void _dismissAlarm() {
    _stopAlarm();
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      // Navigate to home if we can't pop
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  Future<void> _handleComplete() async {
    if (_instance == null) return;
    try {
      await ActivityInstanceService.completeInstance(
          instanceId: _instance!.reference.id);
      _dismissAlarm();
      // Navigate to Queue page
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
      Future.delayed(const Duration(milliseconds: 500), () {
        final homeContext = navigatorKey.currentContext;
        if (homeContext != null) {
          Navigator.of(homeContext).push(
            MaterialPageRoute(
              builder: (context) => QueuePage(
                focusInstanceId: _instance?.reference.id,
              ),
            ),
          );
        }
      });
    } catch (e) {
      print('AlarmRingingPage: Error completing instance: $e');
    }
  }

  Future<void> _handleAdd() async {
    if (_instance == null) return;
    try {
      final instance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: _instance!.reference.id,
      );
      final currentValue = instance.currentValue ?? 0;
      final newValue = (currentValue is num) ? (currentValue + 1) : 1;

      await ActivityInstanceService.updateInstanceProgress(
        instanceId: _instance!.reference.id,
        currentValue: newValue,
      );
      _dismissAlarm();
      // Navigate to Queue page
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
      Future.delayed(const Duration(milliseconds: 500), () {
        final homeContext = navigatorKey.currentContext;
        if (homeContext != null) {
          Navigator.of(homeContext).push(
            MaterialPageRoute(
              builder: (context) => QueuePage(
                focusInstanceId: _instance?.reference.id,
              ),
            ),
          );
        }
      });
    } catch (e) {
      print('AlarmRingingPage: Error adding to instance: $e');
    }
  }

  Future<void> _handleTimer() async {
    if (_instance == null) return;
    try {
      // Start the timer by updating the instance
      await ActivityInstanceService.toggleInstanceTimer(
        instanceId: _instance!.reference.id,
      );

      _dismissAlarm();
      // Navigate to Queue page
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
      Future.delayed(const Duration(milliseconds: 500), () {
        final homeContext = navigatorKey.currentContext;
        if (homeContext != null) {
          Navigator.of(homeContext).push(
            MaterialPageRoute(
              builder: (context) => QueuePage(
                expandCompleted: true,
                focusInstanceId: _instance?.reference.id,
              ),
            ),
          );
        }
      });
    } catch (e) {
      print('AlarmRingingPage: Error starting timer: $e');
    }
  }

  Future<void> _handleSnooze() async {
    if (_instance == null) return;

    // Find reminder ID from payload or construct it
    String reminderId;
    // Check if payload contains the original reminder ID
    if (widget.payload != null &&
        widget.payload!.startsWith('ALARM_RINGING:')) {
      // payload format: ALARM_RINGING:title|body|instanceId|reminderId
      final parts =
          widget.payload!.substring('ALARM_RINGING:'.length).split('|');
      if (parts.length >= 4) {
        reminderId = parts[3];
      } else {
        reminderId = '${_instance!.reference.id}_reminder';
      }
    } else {
      reminderId = '${_instance!.reference.id}_reminder';
    }

    await SnoozeDialog.show(context: context, reminderId: reminderId);
    _dismissAlarm();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.alarm,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 32),
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (widget.body != null) ...[
              const SizedBox(height: 16),
              Text(
                widget.body!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 64),
            // Action buttons based on instance type
            if (!_isLoadingInstance && _instance != null) ...[
              _buildActionButtons(),
              const SizedBox(height: 16),
            ],
            // Dismiss button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _dismissAlarm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text(
                    'DISMISS',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_instance == null) return const SizedBox.shrink();

    final trackingType = _instance!.templateTrackingType;
    final buttons = <Widget>[];

    // Add action button based on tracking type
    switch (trackingType) {
      case 'binary':
        buttons.add(
          _buildActionButton(
            'Mark as complete',
            Colors.green,
            _handleComplete,
          ),
        );
        break;
      case 'quantitative':
        buttons.add(
          _buildActionButton(
            'Add 1',
            Colors.blue,
            _handleAdd,
          ),
        );
        break;
      case 'time':
        buttons.add(
          _buildActionButton(
            'Start timer',
            Colors.orange,
            _handleTimer,
          ),
        );
        break;
    }

    // Always add snooze button
    buttons.add(
      _buildActionButton(
        'Snooze',
        Colors.grey,
        _handleSnooze,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: buttons,
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: 140,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
