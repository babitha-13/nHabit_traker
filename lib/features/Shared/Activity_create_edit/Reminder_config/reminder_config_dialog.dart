import 'package:flutter/material.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config.dart';

/// Dialog for managing reminder configurations
class ReminderConfigDialog extends StatefulWidget {
  final List<ReminderConfig> initialReminders;
  final TimeOfDay? dueTime; // Used to default reminder time
  final VoidCallback? onRequestDueTime;

  const ReminderConfigDialog({
    super.key,
    this.initialReminders = const [],
    this.dueTime,
    this.onRequestDueTime,
  });

  static Future<List<ReminderConfig>?> show({
    required BuildContext context,
    List<ReminderConfig>? initialReminders,
    TimeOfDay? dueTime,
    VoidCallback? onRequestDueTime,
  }) async {
    return await showDialog<List<ReminderConfig>>(
      context: context,
      builder: (context) => ReminderConfigDialog(
        initialReminders: initialReminders ?? [],
        dueTime: dueTime,
        onRequestDueTime: onRequestDueTime,
      ),
    );
  }

  @override
  State<ReminderConfigDialog> createState() => _ReminderConfigDialogState();
}

class _ReminderConfigDialogState extends State<ReminderConfigDialog> {
  late List<ReminderConfig> _reminders;

  @override
  void initState() {
    super.initState();
    _reminders = List.from(widget.initialReminders);

    // Automatically add a reminder if the list is empty when dialog opens
    if (_reminders.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addReminder();
      });
    }
  }

  void _addReminder() async {
    // For habits (no dueTime), prompt for a time immediately or default to 9 AM
    if (widget.dueTime == null) {
      // Habit Mode: Create a fixed time reminder
      final initialTime = const TimeOfDay(hour: 9, minute: 0);

      setState(() {
        final id = 'reminder_${DateTime.now().millisecondsSinceEpoch}';
        _reminders.add(ReminderConfig(
          id: id,
          type: 'notification',
          offsetMinutes: 0, // Not used for fixed time
          enabled: true,
          fixedTimeMinutes: initialTime.hour * 60 + initialTime.minute,
          specificDays: [1, 2, 3, 4, 5, 6, 7], // Default to everyday
        ));
      });
    } else {
      // Task Mode: Create offset based reminder
      setState(() {
        // Generate unique ID
        final id = 'reminder_${DateTime.now().millisecondsSinceEpoch}';
        // Default to due time for all task reminders
        final defaultOffset = 0;
        _reminders.add(ReminderConfig(
          id: id,
          type: 'notification',
          offsetMinutes: defaultOffset,
          enabled: true,
        ));
      });
    }
  }

  void _removeReminder(int index) {
    setState(() {
      _reminders.removeAt(index);
    });
  }

  void _updateReminder(int index, ReminderConfig updated) {
    setState(() {
      _reminders[index] = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Reminders',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _reminders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.notifications_off,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No reminders set',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _reminders.length,
                        itemBuilder: (context, index) {
                          return _ReminderItem(
                            reminder: _reminders[index],
                            dueTime: widget.dueTime,
                            onUpdate: (updated) =>
                                _updateReminder(index, updated),
                            onRemove: () => _removeReminder(index),
                            onRequestDueTime: widget.onRequestDueTime,
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _addReminder,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Reminder'),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, _reminders),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderItem extends StatefulWidget {
  final ReminderConfig reminder;
  final TimeOfDay? dueTime;
  final Function(ReminderConfig) onUpdate;
  final VoidCallback onRemove;
  final VoidCallback? onRequestDueTime;

  const _ReminderItem({
    required this.reminder,
    required this.dueTime,
    required this.onUpdate,
    required this.onRemove,
    this.onRequestDueTime,
  });

  @override
  State<_ReminderItem> createState() => _ReminderItemState();
}

class _ReminderItemState extends State<_ReminderItem> {
  late ReminderConfig _reminder;
  late bool _isRelativeMode;
  late TextEditingController _relativeValueController;
  String _relativeUnit = 'minutes'; // minutes, hours, days
  final GlobalKey _unitSelectorKey = GlobalKey();
  static const List<String> _relativeUnits = ['minutes', 'hours', 'days'];

  @override
  void initState() {
    super.initState();
    _reminder = widget.reminder;
    _isRelativeMode = _inferInitialMode();
    _relativeValueController = TextEditingController(
      text: _getRelativeValue().toString(),
    );
  }

  Future<void> _selectOffset() async {
    _ensureExactModeActive();
    final initialTime = _reminder.fixedTimeMinutes != null
        ? TimeOfDay(
            hour: _reminder.fixedTimeMinutes! ~/ 60,
            minute: _reminder.fixedTimeMinutes! % 60,
          )
        : widget.dueTime ?? const TimeOfDay(hour: 9, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked == null) return;

    setState(() {
      _reminder = _reminder.copyWith(
        fixedTimeMinutes: picked.hour * 60 + picked.minute,
        offsetMinutes: 0,
      );
      _isRelativeMode = false;
    });
    widget.onUpdate(_reminder);
  }

  void _toggleType() {
    setState(() {
      _reminder = _reminder.copyWith(
        type: _reminder.type == 'notification' ? 'alarm' : 'notification',
      );
    });
    widget.onUpdate(_reminder);
  }

  void _toggleEnabled() {
    setState(() {
      _reminder = _reminder.copyWith(enabled: !_reminder.enabled);
    });
    widget.onUpdate(_reminder);
  }

  void _selectMode(bool relativeSelected) {
    if (relativeSelected) {
      if (widget.dueTime == null) {
        _showMissingDueTimeWarning();
        return;
      }
      setState(() {
        _isRelativeMode = true;
        if (_reminder.fixedTimeMinutes != null) {
          // Manually recreate to ensure fixedTimeMinutes is null (copyWith ignores nulls)
          _reminder = ReminderConfig(
            id: _reminder.id,
            type: _reminder.type,
            offsetMinutes: _reminder.offsetMinutes,
            enabled: _reminder.enabled,
            fixedTimeMinutes: null,
            specificDays: _reminder.specificDays,
          );
        }
        // Keep zero offset as "at due time" by default
        _relativeValueController.text =
            _reminder.offsetMinutes.abs().toString();
        _relativeUnit = 'minutes';
      });
      widget.onUpdate(_reminder);
    } else {
      final fallbackTime =
          widget.dueTime ?? const TimeOfDay(hour: 9, minute: 0);
      final time = _reminder.fixedTimeMinutes != null
          ? TimeOfDay(
              hour: _reminder.fixedTimeMinutes! ~/ 60,
              minute: _reminder.fixedTimeMinutes! % 60,
            )
          : fallbackTime;
      setState(() {
        _isRelativeMode = false;
        _reminder = _reminder.copyWith(
          fixedTimeMinutes: time.hour * 60 + time.minute,
          offsetMinutes: 0,
        );
      });
      widget.onUpdate(_reminder);
    }
  }

  Future<void> _showMissingDueTimeWarning() async {
    final reminderContext = context;
    await showDialog<void>(
      context: context,
      builder: (alertContext) {
        return AlertDialog(
          title: const Text('Set due time first'),
          content: const Text(
            'A due time is required before you can set a relative reminder.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(alertContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final callback = widget.onRequestDueTime;
                Navigator.pop(alertContext);
                Navigator.pop(reminderContext, null);
                callback?.call();
              },
              child: const Text('Set due time'),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    setState(() => _isRelativeMode = false);
  }

  bool _inferInitialMode() {
    if (widget.dueTime == null) {
      return false;
    }
    if (_reminder.fixedTimeMinutes != null) {
      return false;
    }
    // Use relative mode for offset reminders (even zero offset)
    return _reminder.fixedTimeMinutes == null;
  }

  int _getRelativeValue() {
    int minutes = _reminder.offsetMinutes.abs();
    if (minutes % 1440 == 0 && minutes != 0) {
      _relativeUnit = 'days';
      return minutes ~/ 1440;
    }
    if (minutes % 60 == 0 && minutes != 0) {
      _relativeUnit = 'hours';
      return minutes ~/ 60;
    }
    _relativeUnit = 'minutes';
    return minutes; // Allow zero to represent "at due time"
  }

  void _onRelativeChanged() {
    final raw = int.tryParse(_relativeValueController.text) ?? 0;
    final value = raw < 0 ? 0 : raw;
    int minutes;
    switch (_relativeUnit) {
      case 'hours':
        minutes = value * 60;
        break;
      case 'days':
        minutes = value * 1440;
        break;
      default:
        minutes = value;
    }
    setState(() {
      // Manually recreate to ensure fixedTimeMinutes is null (copyWith ignores nulls)
      _reminder = ReminderConfig(
        id: _reminder.id,
        type: _reminder.type,
        offsetMinutes: -minutes,
        enabled: _reminder.enabled,
        fixedTimeMinutes: null,
        specificDays: _reminder.specificDays,
      );
    });
    widget.onUpdate(_reminder);
  }

  void _ensureExactModeActive() {
    if (!_isRelativeMode) return;
    setState(() {
      _isRelativeMode = false;
    });
  }

  Future<void> _showRelativeUnitMenu() async {
    final contextKey = _unitSelectorKey.currentContext;
    if (contextKey == null) return;
    final renderObject = contextKey.findRenderObject();
    if (renderObject is! RenderBox) return;
    final renderBox = renderObject;
    final mediaSize = MediaQuery.of(context).size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        mediaSize.width - offset.dx - size.width,
        mediaSize.height - offset.dy - size.height,
      ),
      items: _relativeUnits.map((unit) {
        final isSelected = unit == _relativeUnit;
        return PopupMenuItem<String>(
          value: unit,
          height: 36,
          child: Text(
            '${unit[0].toUpperCase()}${unit.substring(1)}',
            style: TextStyle(
              fontSize: 14,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black87,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );

    if (result != null && result != _relativeUnit) {
      setState(() {
        _relativeUnit = result;
      });
      _onRelativeChanged();
    }
  }

  TimeOfDay _effectiveExactTime() {
    if (_reminder.fixedTimeMinutes != null) {
      return TimeOfDay(
        hour: _reminder.fixedTimeMinutes! ~/ 60,
        minute: _reminder.fixedTimeMinutes! % 60,
      );
    }
    return widget.dueTime ?? const TimeOfDay(hour: 9, minute: 0);
  }

  String _timeButtonLabel(BuildContext context) {
    final time = _effectiveExactTime();
    final formatted = MaterialLocalizations.of(context).formatTimeOfDay(time);
    final hasExactTime = _reminder.fixedTimeMinutes != null;
    return hasExactTime ? formatted : 'Pick time';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _reminder.enabled ? _toggleType : null,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _reminder.enabled
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.08)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _reminder.enabled
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade300,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _reminder.type == 'alarm'
                                  ? Icons.alarm
                                  : Icons.notifications,
                              size: 20,
                              color: _reminder.enabled
                                  ? (_reminder.type == 'alarm'
                                      ? Colors.orange
                                      : Colors.blue)
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _reminder.type == 'alarm'
                                    ? 'Alarm reminder'
                                    : 'Notification reminder',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: _reminder.enabled
                                      ? Colors.black87
                                      : Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.swap_horiz,
                              size: 18,
                              color: _reminder.enabled
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _reminder.enabled,
                    onChanged: (_) => _toggleEnabled(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  onPressed: widget.onRemove,
                  tooltip: 'Delete reminder',
                  splashRadius: 20,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                InkWell(
                  onTap: _reminder.enabled && !_isRelativeMode
                      ? () => _selectMode(true)
                      : null,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _isRelativeMode
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.08)
                          : Colors.transparent,
                      border: Border.all(
                        color: _isRelativeMode
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                        width: _isRelativeMode ? 1.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 60,
                              child: TextField(
                                controller: _relativeValueController,
                                enabled: _isRelativeMode && _reminder.enabled,
                                keyboardType: TextInputType.number,
                                onChanged: _isRelativeMode
                                    ? (_) => _onRelativeChanged()
                                    : null,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: '',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 8,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: _isRelativeMode && _reminder.enabled
                                  ? _showRelativeUnitMenu
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                key: _unitSelectorKey,
                                height: 28,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: _isRelativeMode
                                      ? Colors.white
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _isRelativeMode
                                        ? Theme.of(context).dividerColor
                                        : Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${_relativeUnit[0].toUpperCase()}${_relativeUnit.substring(1)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _isRelativeMode
                                            ? Colors.black87
                                            : Colors.grey.shade500,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_drop_down,
                                      size: 18,
                                      color: _isRelativeMode
                                          ? Colors.black54
                                          : Colors.grey.shade500,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'before due time',
                              style: TextStyle(
                                fontSize: 12,
                                color: _isRelativeMode
                                    ? Colors.black87
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _reminder.enabled && _isRelativeMode
                      ? () => _selectMode(false)
                      : null,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: !_isRelativeMode
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.08)
                          : Colors.transparent,
                      border: Border.all(
                        color: !_isRelativeMode
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                        width: !_isRelativeMode ? 1.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Set time',
                          style: TextStyle(
                            fontSize: 12,
                            color: !_isRelativeMode
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: _reminder.enabled ? _selectOffset : null,
                          icon: const Icon(Icons.schedule),
                          label: Text(
                            _timeButtonLabel(context),
                            style: TextStyle(
                              color: !_isRelativeMode
                                  ? Colors.black87
                                  : Colors.grey.shade600,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
