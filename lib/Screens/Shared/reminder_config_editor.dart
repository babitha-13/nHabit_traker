import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/reminder_config.dart';

/// Screen-layer widget for editing reminder configurations
/// Reuses the UI visuals from Tasks/Habits reminder editing
class ReminderConfigEditor extends StatelessWidget {
  final List<ReminderConfig> reminders;
  final TimeOfDay? dueTime;
  final Function(List<ReminderConfig>) onRemindersChanged;

  const ReminderConfigEditor({
    super.key,
    required this.reminders,
    this.dueTime,
    required this.onRemindersChanged,
  });

  void _addReminder() {
    final updated = List<ReminderConfig>.from(reminders);
    // For routines (no dueTime), create a fixed time reminder
    if (dueTime == null) {
      final initialTime = const TimeOfDay(hour: 9, minute: 0);
      final id = 'reminder_${DateTime.now().millisecondsSinceEpoch}';
      updated.add(ReminderConfig(
        id: id,
        type: 'notification',
        offsetMinutes: 0,
        enabled: true,
        fixedTimeMinutes: initialTime.hour * 60 + initialTime.minute,
        specificDays: [1, 2, 3, 4, 5, 6, 7],
      ));
    } else {
      // Task Mode: Create offset based reminder
      final id = 'reminder_${DateTime.now().millisecondsSinceEpoch}';
      updated.add(ReminderConfig(
        id: id,
        type: 'notification',
        offsetMinutes: 0,
        enabled: true,
      ));
    }
    onRemindersChanged(updated);
  }

  void _removeReminder(int index) {
    final updated = List<ReminderConfig>.from(reminders);
    updated.removeAt(index);
    onRemindersChanged(updated);
  }

  void _updateReminder(int index, ReminderConfig updated) {
    final updatedList = List<ReminderConfig>.from(reminders);
    updatedList[index] = updated;
    onRemindersChanged(updatedList);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reminders.isNotEmpty)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: reminders
                .asMap()
                .entries
                .map((entry) => _ReminderItem(
                      reminder: entry.value,
                      dueTime: dueTime,
                      onUpdate: (updated) => _updateReminder(entry.key, updated),
                      onRemove: () => _removeReminder(entry.key),
                    ))
                .toList(),
          ),
        if (reminders.isNotEmpty) const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: _addReminder,
              icon: const Icon(Icons.add),
              label: const Text('Add Reminder'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReminderItem extends StatefulWidget {
  final ReminderConfig reminder;
  final TimeOfDay? dueTime;
  final Function(ReminderConfig) onUpdate;
  final VoidCallback onRemove;

  const _ReminderItem({
    required this.reminder,
    required this.dueTime,
    required this.onUpdate,
    required this.onRemove,
  });

  @override
  State<_ReminderItem> createState() => _ReminderItemState();
}

class _ReminderItemState extends State<_ReminderItem> {
  late ReminderConfig _reminder;
  late bool _isRelativeMode;
  late TextEditingController _relativeValueController;
  String _relativeUnit = 'minutes';
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

  @override
  void dispose() {
    _relativeValueController.dispose();
    super.dispose();
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
          _reminder = ReminderConfig(
            id: _reminder.id,
            type: _reminder.type,
            offsetMinutes: _reminder.offsetMinutes,
            enabled: _reminder.enabled,
            fixedTimeMinutes: null,
            specificDays: _reminder.specificDays,
          );
        }
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
    await showDialog<void>(
      context: context,
      builder: (alertContext) {
        return AlertDialog(
          title: const Text('Set due time first'),
          content: const Text(
            'A due time is required before you can set a relative reminder. Please set the due time in the main screen first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(alertContext),
              child: const Text('OK'),
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
    return minutes;
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

