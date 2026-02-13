import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:habit_tracker/features/Home/CatchUp/logic/morning_catchup_service.dart';
import 'package:habit_tracker/features/Home/CatchUp/presentation/morning_catchup_dialog.dart';
import 'package:habit_tracker/core/utils/Date_time/date_formatter.dart';
import 'package:habit_tracker/core/utils/Date_time/ist_day_boundary_service.dart';
import 'package:habit_tracker/main.dart';

Future<void> showCatchUpDialogManually(BuildContext context) async {
  try {
    final userId = users.uid;
    if (userId == null || userId.isEmpty) {
      return;
    }

    // Best-effort backend sync for test runs; do not block dialog on failures.
    try {
      await MorningCatchUpService.runInstanceMaintenanceForDayTransition(userId);
    } catch (e) {
      debugPrint('Manual catch-up maintenance failed: $e');
    }
    try {
      await MorningCatchUpService.persistScoresForDate(
        userId: userId,
        targetDate: IstDayBoundaryService.yesterdayStartIst(),
        suppressToasts: true,
      );
    } catch (e) {
      debugPrint('Manual catch-up score finalize failed: $e');
    }

    // Reset dialog state
    await MorningCatchUpService.resetDialogState();

    if (!context.mounted) return;

    // Show dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const MorningCatchUpDialog(
        isDayTransition: false,
        baselineProcessedAtOpen: false,
      ),
    );
  } catch (e) {
    // optionally log error
  }
}

Future<void> forceRecalculateYesterdayDev(BuildContext context) async {
  try {
    final userId = users.uid;
    if (userId == null || userId.isEmpty) return;
    final targetDate = IstDayBoundaryService.yesterdayStartIst();
    final targetDateLabel = formatDateKeyIST(targetDate);

    await MorningCatchUpService.recalculateDailyProgressRecordForDate(
      userId: userId,
      targetDate: targetDate,
      suppressToasts: true,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Forced recalculation completed for $targetDateLabel',
        ),
      ),
    );
  } catch (e) {
    String message;
    if (e is FirebaseFunctionsException) {
      final targetDateLabel =
          formatDateKeyIST(IstDayBoundaryService.yesterdayStartIst());
      message =
          'Force recalculation failed for $targetDateLabel: ${e.code} - ${e.message ?? e.details ?? 'unknown'}';
    } else {
      final targetDateLabel =
          formatDateKeyIST(IstDayBoundaryService.yesterdayStartIst());
      message = 'Force recalculation failed for $targetDateLabel: $e';
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
