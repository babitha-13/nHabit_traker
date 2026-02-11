/// Frequency configuration data model
class FrequencyConfig {
  final FrequencyType type;
  final List<int> selectedDays; // 1-7 for days of week
  final int timesPerPeriod; // For "X times per period"
  final int everyXValue; // For "Every X days/weeks/months"
  final PeriodType periodType; // weeks, months, year
  final PeriodType everyXPeriodType; // days, weeks, months
  final DateTime startDate;
  final DateTime? endDate;

  FrequencyConfig({
    required this.type,
    this.selectedDays = const [],
    this.timesPerPeriod = 1,
    this.everyXValue = 1,
    this.periodType = PeriodType.weeks,
    this.everyXPeriodType = PeriodType.days,
    DateTime? startDate,
    this.endDate,
  }) : startDate = startDate ?? DateTime.now();

  @override
  String toString() {
    return 'FrequencyConfig(type: $type, selectedDays: $selectedDays, timesPerPeriod: $timesPerPeriod, everyXValue: $everyXValue, periodType: $periodType, everyXPeriodType: $everyXPeriodType, startDate: $startDate, endDate: $endDate)';
  }

  FrequencyConfig copyWith({
    FrequencyType? type,
    List<int>? selectedDays,
    int? timesPerPeriod,
    int? everyXValue,
    PeriodType? periodType,
    PeriodType? everyXPeriodType,
    DateTime? startDate,
    DateTime? endDate,
    bool? endDateSet,
  }) {
    return FrequencyConfig(
      type: type ?? this.type,
      selectedDays: selectedDays ?? this.selectedDays,
      timesPerPeriod: timesPerPeriod ?? this.timesPerPeriod,
      everyXValue: everyXValue ?? this.everyXValue,
      periodType: periodType ?? this.periodType,
      everyXPeriodType: everyXPeriodType ?? this.everyXPeriodType,
      startDate: startDate ?? this.startDate,
      endDate: endDateSet == true ? endDate : (endDate ?? this.endDate),
    );
  }
}

enum FrequencyType {
  daily,
  specificDays,
  timesPerPeriod,
  everyXPeriod,
}

enum PeriodType {
  days,
  weeks,
  months,
  year,
}
