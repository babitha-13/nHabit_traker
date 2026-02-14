import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

class TodayInstanceSnapshot {
  final String userId;
  final DateTime dayStart;
  final DateTime dayEnd;
  final Map<String, ActivityInstanceRecord> instancesById;
  final DateTime hydratedAt;

  const TodayInstanceSnapshot({
    required this.userId,
    required this.dayStart,
    required this.dayEnd,
    required this.instancesById,
    required this.hydratedAt,
  });

  List<ActivityInstanceRecord> get instances =>
      instancesById.values.toList(growable: false);

  ActivityInstanceRecord? instanceById(String id) => instancesById[id];

  bool get isEmpty => instancesById.isEmpty;

  TodayInstanceSnapshot copyWith({
    String? userId,
    DateTime? dayStart,
    DateTime? dayEnd,
    Map<String, ActivityInstanceRecord>? instancesById,
    DateTime? hydratedAt,
  }) {
    return TodayInstanceSnapshot(
      userId: userId ?? this.userId,
      dayStart: dayStart ?? this.dayStart,
      dayEnd: dayEnd ?? this.dayEnd,
      instancesById: instancesById ?? this.instancesById,
      hydratedAt: hydratedAt ?? this.hydratedAt,
    );
  }
}
