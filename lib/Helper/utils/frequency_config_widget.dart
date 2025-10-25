import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'frequency_config_dialog.dart'; // Import FrequencyConfig, FrequencyType, PeriodType
class FrequencyConfigWidget extends StatefulWidget {
  final FrequencyConfig initialConfig;
  final Function(FrequencyConfig) onChanged;
  const FrequencyConfigWidget({
    super.key,
    required this.initialConfig,
    required this.onChanged,
  });
  @override
  State<FrequencyConfigWidget> createState() => _FrequencyConfigWidgetState();
}
class _FrequencyConfigWidgetState extends State<FrequencyConfigWidget> {
  late FrequencyConfig _config;
  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }
  void _updateConfig(FrequencyConfig newConfig) {
    setState(() {
      _config = newConfig;
    });
    widget.onChanged(newConfig);
  }
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFrequencyTypeSelection(theme),
        const SizedBox(height: 16),
        _buildSectionHeader('Date Range', theme),
        const SizedBox(height: 8),
        _buildDatePickers(theme),
      ],
    );
  }
  Widget _buildSectionHeader(String title, FlutterFlowTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: theme.titleMedium),
    );
  }
  Widget _buildDatePickers(FlutterFlowTheme theme) {
    return Column(
      children: [
        ListTile(
          title: const Text('Start Date'),
          subtitle: Text(_formatDate(_config.startDate)),
          trailing: const Icon(Icons.calendar_today),
          onTap: () => _selectStartDate(context),
        ),
        ListTile(
          title: const Text('End Date (Optional)'),
          subtitle: Text(_config.endDate != null
              ? _formatDate(_config.endDate!)
              : 'No end date'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_config.endDate != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _updateConfig(
                        _config.copyWith(endDate: null, endDateSet: true));
                  },
                ),
              const Icon(Icons.calendar_today),
            ],
          ),
          onTap: () => _selectEndDate(context),
        ),
      ],
    );
  }
  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _config.startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && picked != _config.startDate) {
      var newConfig = _config.copyWith(startDate: picked);
      if (newConfig.endDate != null && newConfig.endDate!.isBefore(picked)) {
        newConfig = newConfig.copyWith(endDate: null, endDateSet: true);
      }
      _updateConfig(newConfig);
    }
  }
  Future<void> _selectEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _config.endDate ?? _config.startDate.add(const Duration(days: 30)),
      firstDate: _config.startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      _updateConfig(_config.copyWith(endDate: picked));
    }
  }
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
  Widget _buildFrequencyTypeSelection(FlutterFlowTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRadioOption(
          theme,
          FrequencyType.everyXPeriod,
          'Every X period',
          null,
        ),
        _buildRadioOption(
          theme,
          FrequencyType.timesPerPeriod,
          'Times per period',
          null,
        ),
        _buildRadioOption(
          theme,
          FrequencyType.specificDays,
          'Specific days of the week',
          null,
        ),
      ],
    );
  }
  Widget _buildRadioOption(
    FlutterFlowTheme theme,
    FrequencyType type,
    String title,
    String? subtitle,
  ) {
    final isSelected = _config.type == type;
    if (type == FrequencyType.everyXPeriod) {
      return InkWell(
        onTap: () => _updateConfig(_config.copyWith(type: type)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            children: [
              Radio<FrequencyType>(
                value: type,
                groupValue: _config.type,
                onChanged: (value) {
                  if (value != null) {
                    _updateConfig(_config.copyWith(type: value));
                  }
                },
                activeColor: theme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildEveryXPeriodInput(theme)),
            ],
          ),
        ),
      );
    }
    if (type == FrequencyType.timesPerPeriod) {
      return InkWell(
        onTap: () => _updateConfig(_config.copyWith(type: type)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            children: [
              Radio<FrequencyType>(
                value: type,
                groupValue: _config.type,
                onChanged: (value) {
                  if (value != null) {
                    _updateConfig(_config.copyWith(type: value));
                  }
                },
                activeColor: theme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildTimesPerPeriodInput(theme)),
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => _updateConfig(_config.copyWith(type: type)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                Radio<FrequencyType>(
                  value: type,
                  groupValue: _config.type,
                  onChanged: (value) =>
                      _updateConfig(_config.copyWith(type: value!)),
                  activeColor: theme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: theme.primaryText,
                    ),
                  ),
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 12),
              _buildInlineForm(theme, type),
            ],
          ],
        ),
      ),
    );
  }
  Widget _buildInlineForm(FlutterFlowTheme theme, FrequencyType type) {
    switch (type) {
      case FrequencyType.specificDays:
        return _buildDaySelection(theme);
      case FrequencyType.timesPerPeriod:
        return const SizedBox.shrink();
      case FrequencyType.everyXPeriod:
        return const SizedBox
            .shrink(); // This is now handled inline with the radio button
      default:
        return const SizedBox.shrink();
    }
  }
  Widget _buildDaySelection(FlutterFlowTheme theme) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(7, (index) {
        final dayIndex = index + 1; // 1-7
        final isSelected = _config.selectedDays.contains(dayIndex);
        return FilterChip(
          label: Text(days[index]),
          selected: isSelected,
          onSelected: (selected) {
            final newDays = List<int>.from(_config.selectedDays);
            if (selected) {
              newDays.add(dayIndex);
            } else {
              newDays.remove(dayIndex);
            }
            newDays.sort();
            _updateConfig(_config.copyWith(selectedDays: newDays));
          },
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
  Widget _buildTimesPerPeriodInput(FlutterFlowTheme theme) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: _config.timesPerPeriod.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.primary,
            ),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final times = int.tryParse(value) ?? 1;
              _updateConfig(_config.copyWith(timesPerPeriod: times));
            },
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'times per ',
          style: TextStyle(
            fontSize: 14,
            color: theme.primaryText,
          ),
        ),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<PeriodType>(
            value: _config.periodType,
            style: TextStyle(
              fontSize: 14,
              color: theme.primaryText,
            ),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: PeriodType.weeks, child: Text('week')),
              DropdownMenuItem(value: PeriodType.months, child: Text('month')),
              DropdownMenuItem(value: PeriodType.year, child: Text('year')),
            ],
            onChanged: (value) {
              if (value != null) {
                _updateConfig(_config.copyWith(periodType: value));
              }
            },
          ),
        ),
      ],
    );
  }
  Widget _buildEveryXPeriodInput(FlutterFlowTheme theme) {
    return Row(
      children: [
        Text(
          'every ',
          style: TextStyle(
            fontSize: 14,
            color: theme.primaryText,
          ),
        ),
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: _config.everyXValue.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.primary,
            ),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final number = int.tryParse(value) ?? 1;
              _updateConfig(_config.copyWith(everyXValue: number));
            },
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<PeriodType>(
            value: _config.everyXPeriodType,
            style: TextStyle(
              fontSize: 14,
              color: theme.primaryText,
            ),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.primary, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: PeriodType.days, child: Text('days')),
              DropdownMenuItem(value: PeriodType.weeks, child: Text('weeks')),
              DropdownMenuItem(value: PeriodType.months, child: Text('months')),
            ],
            onChanged: (value) {
              if (value != null) {
                _updateConfig(_config.copyWith(everyXPeriodType: value));
              }
            },
          ),
        ),
      ],
    );
  }
}
