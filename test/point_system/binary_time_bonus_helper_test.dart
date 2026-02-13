import 'package:flutter_test/flutter_test.dart';
import 'package:habit_tracker/features/Progress/Point_system_helper/binary_time_bonus_helper.dart';

void main() {
  group('BinaryTimeBonusHelper.scoreForLoggedMinutes (ON mode)', () {
    test('20m target, 10m logged -> 0.5', () {
      final score = BinaryTimeBonusHelper.scoreForLoggedMinutes(
        loggedMinutes: 10,
        targetMinutes: 20,
        priority: 1,
        timeBonusEnabled: true,
      );
      expect(score, closeTo(0.5, 1e-9));
    });

    test('20m target, 15m logged -> 0.75', () {
      final score = BinaryTimeBonusHelper.scoreForLoggedMinutes(
        loggedMinutes: 15,
        targetMinutes: 20,
        priority: 1,
        timeBonusEnabled: true,
      );
      expect(score, closeTo(0.75, 1e-9));
    });

    test('30m target, 15m logged -> 0.5', () {
      final score = BinaryTimeBonusHelper.scoreForLoggedMinutes(
        loggedMinutes: 15,
        targetMinutes: 30,
        priority: 1,
        timeBonusEnabled: true,
      );
      expect(score, closeTo(0.5, 1e-9));
    });

    test('60m target, 30m logged -> 1.0', () {
      final score = BinaryTimeBonusHelper.scoreForLoggedMinutes(
        loggedMinutes: 30,
        targetMinutes: 60,
        priority: 1,
        timeBonusEnabled: true,
      );
      expect(score, closeTo(1.0, 1e-9));
    });

    test('60m target, 120m logged -> 2.533...', () {
      final score = BinaryTimeBonusHelper.scoreForLoggedMinutes(
        loggedMinutes: 120,
        targetMinutes: 60,
        priority: 1,
        timeBonusEnabled: true,
      );
      expect(score, closeTo(2.533, 1e-3));
    });
  });

  group('BinaryTimeBonusHelper.scoreForLoggedMinutes (OFF mode)', () {
    test('20m target: 20->1.0, 40->1.7, 60->2.19', () {
      final score20 = BinaryTimeBonusHelper.scoreForLoggedMinutes(
        loggedMinutes: 20,
        targetMinutes: 20,
        priority: 1,
        timeBonusEnabled: false,
      );
      final score40 = BinaryTimeBonusHelper.scoreForLoggedMinutes(
        loggedMinutes: 40,
        targetMinutes: 20,
        priority: 1,
        timeBonusEnabled: false,
      );
      final score60 = BinaryTimeBonusHelper.scoreForLoggedMinutes(
        loggedMinutes: 60,
        targetMinutes: 20,
        priority: 1,
        timeBonusEnabled: false,
      );

      expect(score20, closeTo(1.0, 1e-9));
      expect(score40, closeTo(1.7, 1e-9));
      expect(score60, closeTo(2.19, 1e-9));
    });

    test('60m target: 60->1.0, 120->1.7', () {
      final score60 = BinaryTimeBonusHelper.scoreForLoggedMinutes(
        loggedMinutes: 60,
        targetMinutes: 60,
        priority: 1,
        timeBonusEnabled: false,
      );
      final score120 = BinaryTimeBonusHelper.scoreForLoggedMinutes(
        loggedMinutes: 120,
        targetMinutes: 60,
        priority: 1,
        timeBonusEnabled: false,
      );

      expect(score60, closeTo(1.0, 1e-9));
      expect(score120, closeTo(1.7, 1e-9));
    });
  });

  group('BinaryTimeBonusHelper.scoreForTargetMinutes', () {
    test('ON mode target score: 20->1.0, 60->1.7', () {
      final score20 = BinaryTimeBonusHelper.scoreForTargetMinutes(
        targetMinutes: 20,
        priority: 1,
        timeBonusEnabled: true,
      );
      final score60 = BinaryTimeBonusHelper.scoreForTargetMinutes(
        targetMinutes: 60,
        priority: 1,
        timeBonusEnabled: true,
      );

      expect(score20, closeTo(1.0, 1e-9));
      expect(score60, closeTo(1.7, 1e-9));
    });
  });
}
