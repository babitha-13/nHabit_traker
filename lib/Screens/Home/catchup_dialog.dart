import 'package:flutter/material.dart';
import 'package:habit_tracker/Screens/CatchUp/morning_catchup_service.dart';
import 'package:habit_tracker/Screens/CatchUp/morning_catchup_dialog_UI.dart';
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
