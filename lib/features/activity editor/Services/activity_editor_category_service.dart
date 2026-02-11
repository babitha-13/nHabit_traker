import 'package:flutter/material.dart';
import 'package:habit_tracker/features/Categories/Create%20Category/create_category.dart';
import 'package:habit_tracker/features/activity%20editor/presentation/activity_editor_dialog.dart';
import 'activity_editor_helper_service.dart';
import 'activity_editor_initialization_service.dart';

/// Service for category operations
class ActivityEditorCategoryService {
  /// Show create category dialog
  static Future<void> showCreateCategoryDialog(
      ActivityEditorDialogState state) async {
    final result = await showDialog(
      context: state.context,
      builder: (context) => CreateCategory(
        categoryType: ActivityEditorHelperService.isEssential(state)
            ? 'essential'
            : state.widget.isHabit
                ? 'habit'
                : 'task',
      ),
    );

    if (result != null && result is String) {
      // New category created, reload and select it
      await ActivityEditorInitializationService.loadCategories(state,
          selectCategoryId: result);
    } else if (result == true) {
      // Category was updated or created but no ID returned (fallback)
      await ActivityEditorInitializationService.loadCategories(state);
    }
  }
}
