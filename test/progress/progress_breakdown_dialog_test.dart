import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/features/Progress/Pages/progress_breakdown_dialog.dart';

void main() {
  testWidgets(
    'renders mixed-type historical breakdown data without crashing',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressBreakdownDialog(
              date: DateTime(2026, 2, 12),
              totalEarned: 12.0,
              totalTarget: 16.0,
              percentage: 75.0,
              habitBreakdown: const [
                {
                  'name': 'Read book',
                  'status': 'completed',
                  'earned': 3,
                  'target': 4,
                  'progress': 75,
                },
              ],
              taskBreakdown: const [
                {
                  'name': 'Plan day',
                  'earned': 2,
                  'target': 2,
                },
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Read book'), findsOneWidget);
      expect(find.text('Plan day'), findsOneWidget);
      expect(find.text('75.0%'), findsWidgets);
      expect(find.text('unknown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
