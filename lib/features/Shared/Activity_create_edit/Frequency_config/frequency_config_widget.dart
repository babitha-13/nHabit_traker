import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'frequency_config_dialog.dart'; // Import FrequencyConfig, FrequencyType, PeriodType

class FrequencyConfigWidget extends StatefulWidget {
  final FrequencyConfig initialConfig;
  final Function(FrequencyConfig) onChanged;
  final Set<FrequencyType>? allowedTypes;

  /// If false, hides the date-range section (useful for routines, which don't store start/end).
  final bool showDateRange;
  const FrequencyConfigWidget({
    super.key,
    required this.initialConfig,
    required this.onChanged,
    this.allowedTypes,
    this.showDateRange = true,
  });
  @override
  State<FrequencyConfigWidget> createState() => _FrequencyConfigWidgetState();
}

class _FrequencyConfigWidgetState extends State<FrequencyConfigWidget> {
  late FrequencyConfig _config;
  late final List<FrequencyType> _allowedTypes;

  @override
  void initState() {
    super.initState();
    _allowedTypes = _resolveAllowedTypes();
    _config = _ensureAllowedConfig(widget.initialConfig);
  }

  List<FrequencyType> _resolveAllowedTypes() {
    final defaults = const [
      FrequencyType.everyXPeriod,
      FrequencyType.timesPerPeriod,
      FrequencyType.specificDays,
    ];
    final provided = widget.allowedTypes;
    final list = (provided != null && provided.isNotEmpty)
        ? provided.toList()
        : defaults;
    if (list.isEmpty) {
      return defaults;
    }
    return list;
  }

  FrequencyConfig _ensureAllowedConfig(FrequencyConfig config) {
    if (_allowedTypes.contains(config.type)) {
      return config;
    }
    return config.copyWith(type: _allowedTypes.first);
  }

  bool _isAllowed(FrequencyType type) => _allowedTypes.contains(type);

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
        if (widget.showDateRange) ...[
          const SizedBox(height: 12),
          _buildSectionHeader('Date Range', theme),
          const SizedBox(height: 6),
          _buildDatePickers(theme),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, FlutterFlowTheme theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        title,
        style: theme.titleMedium.override(
          fontFamily: 'Readex Pro',
          fontWeight: FontWeight.w600,
          color: theme.primaryText,
        ),
      ),
    );
  }

  Widget _buildDatePickers(FlutterFlowTheme theme) {
    return Column(
      children: [
        _buildDateInput(
          label: 'Start Date',
          value: _formatDate(_config.startDate),
          icon: Icons.calendar_today,
          onTap: () => _selectStartDate(context),
          theme: theme,
        ),
        const SizedBox(height: 8),
        _buildDateInput(
          label: 'End Date (Optional)',
          value: _config.endDate != null
              ? _formatDate(_config.endDate!)
              : 'No end date',
          icon: Icons.calendar_today,
          onTap: () => _selectEndDate(context),
          onClear: _config.endDate != null
              ? () {
                  _updateConfig(
                      _config.copyWith(endDate: null, endDateSet: true));
                }
              : null,
          theme: theme,
        ),
      ],
    );
  }

  Widget _buildDateInput({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onClear,
    required FlutterFlowTheme theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.surfaceBorderColor.withOpacity(0.8),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.primary.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.secondaryText,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value.isNotEmpty &&
                    value != 'No end date' &&
                    value != 'Not set')
                  Text(
                    value,
                    style: theme.bodyMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w500,
                    ),
                  )
                else
                  Text(
                    value,
                    style: TextStyle(
                      color: theme.secondaryText,
                      fontSize: 14,
                    ),
                  ),
                const SizedBox(width: 8),
                if (onClear != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: onClear,
                      child: Icon(
                        Icons.clear,
                        color: theme.secondaryText,
                        size: 20,
                      ),
                    ),
                  ),
                Icon(
                  icon,
                  color: theme.secondaryText,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final theme = FlutterFlowTheme.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: _config.startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: theme.primary, // Header background color
              onPrimary: theme.info, // Header text color
              surface: theme.secondaryBackground, // Background color
              onSurface: theme.primaryText, // Text color
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: theme.primary, // Button text color
              ),
            ),
          ),
          child: child!,
        );
      },
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
    final theme = FlutterFlowTheme.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _config.endDate ?? _config.startDate.add(const Duration(days: 30)),
      firstDate: _config.startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: theme.primary, // Header background color
              onPrimary: theme.info, // Header text color
              surface: theme.secondaryBackground, // Background color
              onSurface: theme.primaryText, // Text color
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: theme.primary, // Button text color
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      _updateConfig(_config.copyWith(endDate: picked));
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildFrequencyTypeSelection(FlutterFlowTheme theme) {
    final children = <Widget>[];
    if (_isAllowed(FrequencyType.everyXPeriod)) {
      children.add(
        _buildRadioOption(
          theme,
          FrequencyType.everyXPeriod,
          'Every X period',
          null,
        ),
      );
    }
    if (_isAllowed(FrequencyType.timesPerPeriod)) {
      children.add(
        _buildRadioOption(
          theme,
          FrequencyType.timesPerPeriod,
          'Times per period',
          null,
        ),
      );
    }
    if (_isAllowed(FrequencyType.specificDays)) {
      children.add(
        _buildRadioOption(
          theme,
          FrequencyType.specificDays,
          'Specific days of the week',
          null,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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
              const SizedBox(width: 6),
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
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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
              const SizedBox(width: 6),
              Expanded(child: _buildTimesPerPeriodInput(theme)),
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => _updateConfig(_config.copyWith(type: type)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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
                const SizedBox(width: 6),
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
              const SizedBox(height: 8),
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
        SizedBox(
          width: 60,
          child: _buildNumberInput(
            initialValue: _config.timesPerPeriod.toString(),
            onChanged: (value) {
              final times = int.tryParse(value) ?? 1;
              _updateConfig(_config.copyWith(timesPerPeriod: times));
            },
            theme: theme,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'times per',
          style: TextStyle(
            fontSize: 14,
            color: theme.primaryText,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildDropdownTrigger(
            label: _config.periodType == PeriodType.weeks
                ? 'week'
                : _config.periodType == PeriodType.months
                    ? 'month'
                    : 'year',
            onTap: (buttonContext) => _showPeriodTypeMenu(buttonContext, false),
            theme: theme,
          ),
        ),
      ],
    );
  }

  Widget _buildEveryXPeriodInput(FlutterFlowTheme theme) {
    return Row(
      children: [
        Text(
          'every',
          style: TextStyle(
            fontSize: 14,
            color: theme.primaryText,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 60,
          child: _buildNumberInput(
            initialValue: _config.everyXValue.toString(),
            onChanged: (value) {
              final number = int.tryParse(value) ?? 1;
              _updateConfig(_config.copyWith(everyXValue: number));
            },
            theme: theme,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildDropdownTrigger(
            label: _config.everyXPeriodType == PeriodType.days
                ? 'days'
                : _config.everyXPeriodType == PeriodType.weeks
                    ? 'weeks'
                    : 'months',
            onTap: (buttonContext) => _showPeriodTypeMenu(buttonContext, true),
            theme: theme,
          ),
        ),
      ],
    );
  }

  Widget _buildNumberInput({
    required String initialValue,
    required Function(String) onChanged,
    required FlutterFlowTheme theme,
  }) {
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
        initialValue: initialValue,
        textAlign: TextAlign.center,
        style: theme.bodyMedium,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
        ),
        keyboardType: TextInputType.number,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDropdownTrigger({
    required String label,
    required Function(BuildContext) onTap,
    required FlutterFlowTheme theme,
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
              Text(
                label,
                style: theme.bodyMedium,
              ),
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

  Future<void> _showPeriodTypeMenu(
      BuildContext context, bool isEveryXType) async {
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
    final items = isEveryXType
        ? [
            PopupMenuItem(
                value: PeriodType.days,
                child: Text('days', style: theme.bodyMedium)),
            PopupMenuItem(
                value: PeriodType.weeks,
                child: Text('weeks', style: theme.bodyMedium)),
            PopupMenuItem(
                value: PeriodType.months,
                child: Text('months', style: theme.bodyMedium)),
          ]
        : [
            PopupMenuItem(
                value: PeriodType.weeks,
                child: Text('week', style: theme.bodyMedium)),
            PopupMenuItem(
                value: PeriodType.months,
                child: Text('month', style: theme.bodyMedium)),
            PopupMenuItem(
                value: PeriodType.year,
                child: Text('year', style: theme.bodyMedium)),
          ];

    final PeriodType? selected = await showMenu<PeriodType>(
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
      if (isEveryXType) {
        _updateConfig(_config.copyWith(everyXPeriodType: selected));
      } else {
        _updateConfig(_config.copyWith(periodType: selected));
      }
    }
  }
}
