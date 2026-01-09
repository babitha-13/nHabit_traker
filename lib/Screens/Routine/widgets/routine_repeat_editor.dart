import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

/// Widget for editing routine repeat/frequency configuration
/// Only supports Every X and Specific days (matching routine backend support)
class RoutineRepeatEditor extends StatefulWidget {
  final String? frequencyType; // 'every_x' or 'specific_days'
  final int everyXValue;
  final String? everyXPeriodType; // 'day', 'week', 'month'
  final List<int> specificDays; // 1-7
  final Function(String?, int, String?, List<int>) onConfigChanged;

  const RoutineRepeatEditor({
    super.key,
    this.frequencyType,
    this.everyXValue = 1,
    this.everyXPeriodType,
    this.specificDays = const [],
    required this.onConfigChanged,
  });

  @override
  State<RoutineRepeatEditor> createState() => _RoutineRepeatEditorState();
}

class _RoutineRepeatEditorState extends State<RoutineRepeatEditor> {
  String? _frequencyType;
  int _everyXValue = 1;
  String? _everyXPeriodType = 'day';
  List<int> _specificDays = [];
  final TextEditingController _everyXController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _frequencyType = widget.frequencyType;
    _everyXValue = widget.everyXValue;
    _everyXPeriodType = widget.everyXPeriodType ?? 'day';
    _specificDays = List.from(widget.specificDays);
    _everyXController.text = _everyXValue.toString();
  }

  @override
  void dispose() {
    _everyXController.dispose();
    super.dispose();
  }

  void _setFrequencyType(String? type) {
    setState(() {
      _frequencyType = type;
      if (type == 'every_x' && _everyXPeriodType == null) {
        _everyXPeriodType = 'day';
      }
      if (type == 'specific_days' && _specificDays.isEmpty) {
        // Default to all days if none selected
        _specificDays = [1, 2, 3, 4, 5, 6, 7];
      }
    });
    _notifyChange();
  }

  void _toggleDay(int day) {
    setState(() {
      if (_specificDays.contains(day)) {
        _specificDays.remove(day);
      } else {
        _specificDays.add(day);
        _specificDays.sort();
      }
    });
    _notifyChange();
  }

  void _notifyChange() {
    widget.onConfigChanged(
      _frequencyType,
      _everyXValue,
      _everyXPeriodType,
      _specificDays,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No repeat (compact)
        _buildRadioRow(
          theme: theme,
          value: null,
          title: 'No repeat',
          subtitle: 'Reminders will not recur',
          trailing: const SizedBox.shrink(),
        ),
        // Every X (inline, like FrequencyConfigWidget)
        _buildRadioRow(
          theme: theme,
          value: 'every_x',
          title: '',
          subtitle: null,
          trailing: _buildEveryXInline(theme),
        ),
        // Specific days
        _buildRadioRow(
          theme: theme,
          value: 'specific_days',
          title: 'Specific days of the week',
          subtitle: null,
          trailing: const SizedBox.shrink(),
        ),
        if (_frequencyType == 'specific_days') ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: _buildDaySelection(theme),
          ),
        ],
      ],
    );
  }

  Widget _buildRadioRow({
    required FlutterFlowTheme theme,
    required String? value,
    required String title,
    required String? subtitle,
    required Widget trailing,
  }) {
    return InkWell(
      onTap: () => _setFrequencyType(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          children: [
            Radio<String?>(
              value: value,
              groupValue: _frequencyType,
              onChanged: (v) => _setFrequencyType(v),
              activeColor: theme.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 6),
            if (title.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.bodyMedium),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: theme.bodySmall.override(
                          color: theme.secondaryText,
                        ),
                      ),
                  ],
                ),
              )
            else
              Expanded(child: trailing),
          ],
        ),
      ),
    );
  }

  Widget _buildEveryXInline(FlutterFlowTheme theme) {
    return Row(
      children: [
        Text('every', style: theme.bodyMedium),
        const SizedBox(width: 6),
        SizedBox(
          width: 60,
          child: _buildNumberInput(theme),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildDropdownTrigger(
            theme: theme,
            label: _everyXPeriodType == 'day'
                ? 'days'
                : _everyXPeriodType == 'week'
                    ? 'weeks'
                    : 'months',
            onTap: (buttonContext) => _showPeriodTypeMenu(buttonContext),
          ),
        ),
      ],
    );
  }

  Widget _buildNumberInput(FlutterFlowTheme theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.surfaceBorderColor.withOpacity(0.8),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.primary.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextFormField(
        controller: _everyXController,
        textAlign: TextAlign.center,
        style: theme.bodyMedium,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        keyboardType: TextInputType.number,
        onChanged: (value) {
          final number = int.tryParse(value) ?? 1;
          setState(() {
            _everyXValue = number > 0 ? number : 1;
          });
          _notifyChange();
        },
      ),
    );
  }

  Widget _buildDropdownTrigger({
    required FlutterFlowTheme theme,
    required String label,
    required Function(BuildContext) onTap,
  }) {
    return Builder(
      builder: (context) => GestureDetector(
        onTap: () => onTap(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.secondaryBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.surfaceBorderColor.withOpacity(0.8),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.primary.withOpacity(0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.bodyMedium),
              Icon(
                Icons.arrow_drop_down,
                color: theme.secondaryText,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPeriodTypeMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final theme = FlutterFlowTheme.of(context);
    final items = [
      PopupMenuItem(value: 'day', child: Text('days', style: theme.bodyMedium)),
      PopupMenuItem(
          value: 'week', child: Text('weeks', style: theme.bodyMedium)),
      PopupMenuItem(
          value: 'month', child: Text('months', style: theme.bodyMedium)),
    ];

    final String? selected = await showMenu<String>(
      context: context,
      position: position,
      items: items,
      color: theme.secondaryBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.alternate),
      ),
    );

    if (selected != null) {
      setState(() {
        _everyXPeriodType = selected;
      });
      _notifyChange();
    }
  }

  Widget _buildDaySelection(FlutterFlowTheme theme) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(7, (index) {
        final dayIndex = index + 1; // 1-7
        final isSelected = _specificDays.contains(dayIndex);
        return FilterChip(
          label: Text(days[index]),
          selected: isSelected,
          onSelected: (_) => _toggleDay(dayIndex),
          selectedColor: theme.primary,
          backgroundColor: theme.secondaryBackground,
          side: BorderSide(
            color: isSelected ? theme.primary : theme.alternate,
            width: 1,
          ),
        );
      }),
    );
  }
}

