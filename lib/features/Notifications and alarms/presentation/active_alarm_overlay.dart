import 'dart:async';

import 'package:flutter/material.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/notification_service.dart';

class ActiveAlarmOverlay extends StatelessWidget {
  const ActiveAlarmOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ActiveAlarmContext?>(
      valueListenable: NotificationService.activeAlarmListenable,
      builder: (context, alarm, _) {
        if (alarm == null) {
          return const SizedBox.shrink();
        }

        final dueLabel = _buildDueLabel(alarm);

        return IgnorePointer(
          ignoring: false,
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Material(
                  color: const Color(0xFFD94B4B),
                  elevation: 14,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.alarm, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Active Alarm',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          alarm.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (dueLabel != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            dueLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (alarm.body != null && alarm.body!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            alarm.body!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _actionButton(
                              label: alarm.primaryActionLabel,
                              emphasized: true,
                              onTap: () async {
                                final ok = await NotificationService
                                    .performPrimaryActionForActiveAlarm();
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Could not apply action. Open task and try again.'),
                                    ),
                                  );
                                }
                              },
                            ),
                            _actionButton(
                              label: 'Snooze 10m',
                              onTap: () async {
                                await NotificationService.snoozeActiveAlarm(
                                    minutes: 10);
                              },
                            ),
                            _actionButton(
                              label: 'Open task',
                              onTap: () async {
                                final ok =
                                    await NotificationService.openActiveAlarmTask();
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Could not open task.'),
                                    ),
                                  );
                                }
                              },
                            ),
                            _actionButton(
                              label: 'Dismiss',
                              onTap: () async {
                                await NotificationService.dismissActiveAlarm();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? _buildDueLabel(ActiveAlarmContext alarm) {
    final dueDate = alarm.dueDate;
    final dueTime = alarm.dueTime;

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

  Widget _actionButton({
    required String label,
    required Future<void> Function() onTap,
    bool emphasized = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        unawaited(onTap());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: emphasized ? Colors.white : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: emphasized ? const Color(0xFFD94B4B) : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
