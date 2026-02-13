import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/features/Queue/queue_page.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/snooze_dialog.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/reminder_scheduler.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/notification_service.dart';
import 'package:habit_tracker/core/constants.dart';
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
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        setState(() => _isLoadingInstance = false);
        return;
      }

      final instances = await queryAllInstances(userId: userId);
      final instance = _resolveInstance(instances, instanceId);

      setState(() {
        _instance = instance;
        _isLoadingInstance = false;
      });
    } catch (e) {
      print('AlarmRingingPage: Error loading instance: $e');
      setState(() => _isLoadingInstance = false);
    }
  }

  ActivityInstanceRecord? _resolveInstance(
    List<ActivityInstanceRecord> instances,
    String instanceId,
  ) {
    if (instances.isEmpty) return null;

    for (final instance in instances) {
      if (instance.reference.id == instanceId) {
        return instance;
      }
    }

    ActivityInstanceRecord? templateMatch;
    for (final instance in instances) {
      if (instance.templateId != instanceId) continue;
      if (instance.status == 'pending' && instance.isActive) {
        return instance;
      }
      templateMatch ??= instance;
    }

    return templateMatch;
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
    NotificationService.clearActiveAlarm();
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      // Navigate to home if we can't pop
      Navigator.of(context).pushNamedAndRemoveUntil(
        home,
        (route) => false,
      );
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
    final reminderId = _extractReminderId();
    if (reminderId == null) return;

    await SnoozeDialog.show(context: context, reminderId: reminderId);
    _dismissAlarm();
  }

  String? _extractReminderId() {
    if (widget.payload != null &&
        widget.payload!.startsWith('ALARM_RINGING:')) {
      final parts =
          widget.payload!.substring('ALARM_RINGING:'.length).split('|');
      if (parts.length >= 4 && parts[3].trim().isNotEmpty && parts[3] != 'null') {
        return parts[3].trim();
      }
    }
    if (_instance != null) {
      return '${_instance!.reference.id}_reminder';
    }
    return null;
  }

  Future<void> _quickSnooze(int minutes) async {
    final reminderId = _extractReminderId();
    if (reminderId == null) return;
    try {
      await ReminderScheduler.snoozeReminder(
        reminderId: reminderId,
        durationMinutes: minutes,
      );
      _dismissAlarm();
    } catch (e) {
      print('AlarmRingingPage: Quick snooze failed: $e');
    }
  }

  String _primaryActionLabel() {
    final trackingType = _instance?.templateTrackingType ?? 'binary';
    switch (trackingType) {
      case 'quantitative':
        return 'Add 1';
      case 'time':
        return 'Start timer';
      case 'binary':
      default:
        return 'Mark as complete';
    }
  }

  Future<void> _handlePrimaryAction() async {
    final trackingType = _instance?.templateTrackingType ?? 'binary';
    if (trackingType == 'quantitative') {
      await _handleAdd();
      return;
    }
    if (trackingType == 'time') {
      await _handleTimer();
      return;
    }
    await _handleComplete();
  }

  String? _buildDueContext() {
    final instance = _instance;
    if (instance == null) return null;
    final dueDate = instance.dueDate;
    final dueTime = instance.dueTime;
    if (dueDate == null && (dueTime == null || dueTime.isEmpty)) {
      return null;
    }

    if (dueDate != null && dueTime != null && dueTime.isNotEmpty) {
      return 'Due ${dueDate.month}/${dueDate.day} at $dueTime';
    }
    if (dueDate != null) {
      return 'Due ${dueDate.month}/${dueDate.day}';
    }
    return 'Due at $dueTime';
  }

  @override
  Widget build(BuildContext context) {
    final title = _instance?.templateName.isNotEmpty == true
        ? _instance!.templateName
        : widget.title;
    final subtitle = widget.body;
    final dueContext = _buildDueContext();
    final canSnooze = _extractReminderId() != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.alarm, size: 28, color: Color(0xFFFF6B6B)),
                  SizedBox(width: 10),
                  Text(
                    'Alarm ringing',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2129),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2F3743)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (dueContext != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        dueContext,
                        style: const TextStyle(
                          color: Color(0xFF9AD0FF),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (_instance != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Type: ${_instance!.templateTrackingType}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_isLoadingInstance)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!_isLoadingInstance && _instance == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Task details are unavailable. You can still snooze or dismiss this alarm.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (!_isLoadingInstance && _instance != null) ...[
                SizedBox(
                  height: 64,
                  child: ElevatedButton(
                    onPressed: _handlePrimaryAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2EB67D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _primaryActionLabel(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Text(
                'Quick snooze',
                style: TextStyle(
                  color: canSnooze ? Colors.white : Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in const [5, 10, 15, 30])
                    ActionChip(
                      label: Text('${minutes}m'),
                      onPressed: canSnooze ? () => _quickSnooze(minutes) : null,
                      backgroundColor: const Color(0xFF2A2F38),
                      labelStyle: const TextStyle(color: Colors.white),
                    ),
                  ActionChip(
                    label: const Text('More'),
                    onPressed: canSnooze ? _handleSnooze : null,
                    backgroundColor: const Color(0xFF2A2F38),
                    labelStyle: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _dismissAlarm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD94B4B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Dismiss',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
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
