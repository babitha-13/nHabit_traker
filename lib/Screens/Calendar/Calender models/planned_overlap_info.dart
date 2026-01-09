import 'package:habit_tracker/Screens/Calendar/Calender%20models/planned_overlap_group.dart';

class PlannedOverlapInfo {
  final int pairCount;
  final Set<String> overlappedIds;
  final List<PlannedOverlapGroup> groups;

  const PlannedOverlapInfo({
    required this.pairCount,
    required this.overlappedIds,
    required this.groups,
  });
}