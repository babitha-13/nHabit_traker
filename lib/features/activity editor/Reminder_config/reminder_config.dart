import 'package:flutter/material.dart';

/// Model class for representing a single reminder configuration
class ReminderConfig {
  final String id;
  final String type; // 'notification' or 'alarm'
  final int
      offsetMinutes; // Offset in minutes from due time (negative = before)
  final bool enabled;
  final int? fixedTimeMinutes; // Minutes from midnight for fixed time reminders
  final List<int>? specificDays; // 1-7, null means everyday

  ReminderConfig({
    required this.id,
    required this.type,
    required this.offsetMinutes,
    this.enabled = true,
    this.fixedTimeMinutes,
    this.specificDays,
  });

  /// Create ReminderConfig from a map (Firestore data)
  factory ReminderConfig.fromMap(Map<String, dynamic> map) {
    return ReminderConfig(
      id: map['id'] as String? ?? '',
      type: map['type'] as String? ?? 'notification',
      offsetMinutes: map['offsetMinutes'] as int? ?? 0,
      enabled: map['enabled'] as bool? ?? true,
      fixedTimeMinutes: map['fixedTimeMinutes'] as int?,
      specificDays: (map['specificDays'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList(),
    );
  }

  /// Convert ReminderConfig to a map (for Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'offsetMinutes': offsetMinutes,
      'enabled': enabled,
      if (fixedTimeMinutes != null) 'fixedTimeMinutes': fixedTimeMinutes,
      if (specificDays != null) 'specificDays': specificDays,
    };
  }

  /// Create a copy with updated fields
  ReminderConfig copyWith({
    String? id,
    String? type,
    int? offsetMinutes,
    bool? enabled,
    int? fixedTimeMinutes,
    List<int>? specificDays,
  }) {
    return ReminderConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      offsetMinutes: offsetMinutes ?? this.offsetMinutes,
      enabled: enabled ?? this.enabled,
      fixedTimeMinutes: fixedTimeMinutes ?? this.fixedTimeMinutes,
      specificDays: specificDays ?? this.specificDays,
    );
  }

  /// Helper getter for TimeOfDay from fixedTimeMinutes
  TimeOfDay get time {
    if (fixedTimeMinutes != null) {
      return TimeOfDay(
          hour: fixedTimeMinutes! ~/ 60, minute: fixedTimeMinutes! % 60);
    }
    // Fallback or default
    return const TimeOfDay(hour: 9, minute: 0);
  }

  /// Helper getter for days
  List<int> get days {
    return specificDays ?? [1, 2, 3, 4, 5, 6, 7]; // Default to every day
  }

  /// Validate the reminder configuration
  bool isValid() {
    if (id.isEmpty) return false;
    if (type != 'notification' && type != 'alarm') return false;
    return true;
  }

  /// Get a human-readable description of the offset or time
  String getDescription() {
    if (fixedTimeMinutes != null) {
      final t = time;
      final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      final minute = t.minute.toString().padLeft(2, '0');
      final period = t.period == DayPeriod.am ? 'AM' : 'PM';
      return 'At $hour:$minute $period';
    }

    if (offsetMinutes == 0) return 'At due time';
    if (offsetMinutes < 0) {
      final absMinutes = offsetMinutes.abs();
      if (absMinutes < 60) {
        return '${absMinutes} minute${absMinutes == 1 ? '' : 's'} before';
      } else if (absMinutes < 1440) {
        final hours = absMinutes ~/ 60;
        return '${hours} hour${hours == 1 ? '' : 's'} before';
      } else {
        final days = absMinutes ~/ 1440;
        return '${days} day${days == 1 ? '' : 's'} before';
      }
    } else {
      final absMinutes = offsetMinutes;
      if (absMinutes < 60) {
        return '${absMinutes} minute${absMinutes == 1 ? '' : 's'} after';
      } else if (absMinutes < 1440) {
        final hours = absMinutes ~/ 60;
        return '${hours} hour${hours == 1 ? '' : 's'} after';
      } else {
        final days = absMinutes ~/ 1440;
        return '${days} day${days == 1 ? '' : 's'} after';
      }
    }
  }

  // Alias for backward compatibility if needed, or replace usage
  String getOffsetDescription() => getDescription();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          offsetMinutes == other.offsetMinutes &&
          enabled == other.enabled &&
          fixedTimeMinutes == other.fixedTimeMinutes; // Simplified check

  @override
  int get hashCode =>
      id.hashCode ^
      type.hashCode ^
      offsetMinutes.hashCode ^
      enabled.hashCode ^
      fixedTimeMinutes.hashCode;

  @override
  String toString() =>
      'ReminderConfig(id: $id, type: $type, offsetMinutes: $offsetMinutes, enabled: $enabled, fixed: $fixedTimeMinutes)';
}

/// Helper class for working with lists of reminders
class ReminderConfigList {
  /// Convert list of maps to list of ReminderConfig
  static List<ReminderConfig> fromMapList(List<dynamic>? list) {
    if (list == null) return [];
    return list
        .map((item) =>
            item is Map<String, dynamic> ? ReminderConfig.fromMap(item) : null)
        .where((item) => item != null)
        .cast<ReminderConfig>()
        .toList();
  }

  /// Convert list of ReminderConfig to list of maps
  static List<Map<String, dynamic>> toMapList(List<ReminderConfig> reminders) {
    return reminders.map((r) => r.toMap()).toList();
  }
}
