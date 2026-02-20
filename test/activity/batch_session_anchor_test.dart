import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_progress_service.dart';

void main() {
  test('completion anchors are unique and ordered for batch increments', () {
    final base = DateTime(2026, 2, 20, 23, 0, 0, 500);
    const total = 4;

    final anchors = List.generate(
      total,
      (i) => ActivityInstanceProgressService
          .completionAnchorForQuantitativeIncrement(
        effectiveReferenceTime: base,
        totalIncrements: total,
        incrementIndex: i,
      ),
    );

    expect(anchors.map((t) => t.millisecondsSinceEpoch).toSet().length, total);
    expect(anchors[0].isBefore(anchors[1]), isTrue);
    expect(anchors[1].isBefore(anchors[2]), isTrue);
    expect(anchors[2].isBefore(anchors[3]), isTrue);
    expect(anchors.last, base);
  });

  test('single increment uses reference time directly', () {
    final base = DateTime(2026, 2, 20, 23, 0, 0, 500);
    final anchor =
        ActivityInstanceProgressService.completionAnchorForQuantitativeIncrement(
      effectiveReferenceTime: base,
      totalIncrements: 1,
      incrementIndex: 0,
    );

    expect(anchor, base);
  });
}
