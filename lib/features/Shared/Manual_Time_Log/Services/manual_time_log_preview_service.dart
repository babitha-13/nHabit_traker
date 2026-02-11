import 'package:flutter/material.dart';
import 'package:habit_tracker/features/Shared/Manual_Time_Log/manual_time_log_helper.dart';
import 'package:habit_tracker/features/Shared/Manual_Time_Log/Services/manual_time_log_search_service.dart';
import 'package:habit_tracker/features/Shared/Manual_Time_Log/Services/manual_time_log_helper_service.dart';

/// Service for preview updates and type selection
class ManualTimeLogPreviewService {
  /// Update preview callback
  static void updatePreview(ManualTimeLogModalState state) {
    if (state.widget.onPreviewChange == null) return;

    Color? previewColor;
    if (state.selectedType == 'habit') {
      previewColor = Colors.orange;
    } else if (state.selectedType == 'essential') {
      previewColor = Colors.grey;
    } else {
      previewColor =
          null; // Use default or let cal decide (neutral grey initially)
    }

    state.widget.onPreviewChange!(
      state.startTime,
      state.endTime,
      state.selectedType,
      previewColor,
    );
  }

  /// Select activity type
  static void selectType(ManualTimeLogModalState state, String type) {
    state.setState(() {
      state.selectedType = type;
      state.selectedTemplate = null;
      state.activityController.clear();
      ManualTimeLogHelperService.updateDefaultCategory(state);
      ManualTimeLogSearchService.removeOverlay(state);
      ManualTimeLogSearchService.onSearchChanged(state);
      updatePreview(state);
    });
  }
}
