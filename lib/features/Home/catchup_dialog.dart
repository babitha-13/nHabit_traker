import 'package:flutter/material.dart';
import 'package:habit_tracker/features/Home/CatchUp/logic/morning_catchup_service.dart';
import 'package:habit_tracker/features/Home/CatchUp/presentation/morning_catchup_dialog.dart';
import 'package:habit_tracker/main.dart';

Future<void> showCatchUpDialogManually(BuildContext context) async {
  try {
    final userId = users.uid;
    if (userId == null || userId.isEmpty) {
      return;
    }

    // Bring everything up to date
    await MorningCatchUpService.runInstanceMaintenanceForDayTransition(userId);

    // Reset dialog state
    await MorningCatchUpService.resetDialogState();

    if (!context.mounted) return;

    // Show dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const MorningCatchUpDialog(
        isDayTransition: false,
      ),
    );
  } catch (e) {
    // optionally log error
  }
}
