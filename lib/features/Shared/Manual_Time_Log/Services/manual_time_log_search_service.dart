import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Shared/Manual_Time_Log/manual_time_log_helper.dart';
import 'package:habit_tracker/features/Shared/Manual_Time_Log/Services/manual_time_log_preview_service.dart';
import 'package:collection/collection.dart';

/// Service for search and suggestions overlay management
class ManualTimeLogSearchService {
  /// Handle search text changes
  static void onSearchChanged(ManualTimeLogModalState state) {
    final query = state.activityController.text.toLowerCase();

    state.setState(() {
      // Filter based on selected type and query
      state.suggestions = state.allActivities.where((activity) {
        // 1. Filter by type
        bool typeMatch = false;
        if (state.selectedType == 'habit') {
          typeMatch = activity.categoryType == 'habit';
        } else if (state.selectedType == 'task') {
          typeMatch = activity.categoryType == 'task';
        } else if (state.selectedType == 'essential') {
          typeMatch = activity.categoryType == 'essential';
        }

        if (!typeMatch) return false;

        // 2. Filter by name (if query exists)
        if (query.isEmpty) return true;
        return activity.name.toLowerCase().contains(query);
      }).toList();

      // Update visibility based on query and focus
      state.showSuggestions = state.activityFocusNode.hasFocus;
    });

    // Update overlay based on visibility and suggestions
    if (state.showSuggestions && state.suggestions.isNotEmpty) {
      // Remove existing overlay and create new one with updated suggestions
      removeOverlay(state);
      showOverlay(state);
    } else {
      removeOverlay(state);
    }
  }

  /// Remove the overlay entry
  static void removeOverlay(ManualTimeLogModalState state) {
    state.overlayEntry?.remove();
    state.overlayEntry = null;
  }

  /// Show the suggestions overlay
  static void showOverlay(ManualTimeLogModalState state) {
    removeOverlay(state); // Remove existing overlay if any

    if (state.suggestions.isNotEmpty) {
      final theme = FlutterFlowTheme.of(state.context);
      final RenderBox? renderBox =
          state.textFieldKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) return;

      final size = renderBox.size;
      final offset = renderBox.localToGlobal(Offset.zero);

      state.overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          left: offset.dx,
          top: offset.dy +
              size.height +
              4, // Position below text field with small gap
          width: size.width,
          child: Material(
            elevation: 16,
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(1.0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: state.suggestions.length,
                itemBuilder: (context, index) {
                  final item = state.suggestions[index];
                  return ListTile(
                    title: Text(item.name, style: theme.bodyMedium),
                    subtitle: item.categoryName.isNotEmpty
                        ? Text(item.categoryName, style: theme.bodySmall)
                        : null,
                    dense: true,
                    onTap: () {
                      state.setState(() {
                        state.selectedTemplate = item;
                        state.activityController.text = item.name;
                        state.showSuggestions = false;

                        // Auto-select category from template
                        state.selectedCategory =
                            state.allCategories.firstWhereOrNull(
                          (c) =>
                              c.reference.id == item.categoryId ||
                              c.name == item.categoryName,
                        );

                        // Update duration from template estimate if not from timer
                        if (state.widget.initialEndTime == null &&
                            item.timeEstimateMinutes != null &&
                            item.timeEstimateMinutes! > 0) {
                          state.endTime = state.startTime.add(
                              Duration(minutes: item.timeEstimateMinutes!));
                        }

                        // Initialize completion controls based on tracking type
                        // If from timer and binary task, auto-mark as complete
                        if (state.widget.fromTimer &&
                            item.trackingType == 'binary') {
                          state.markAsComplete = true;
                        } else {
                          state.markAsComplete = false; // Reset checkbox
                        }
                        // Initialize quantity with current value (default to 0 if null)
                        state.quantityValue = item.currentValue is int
                            ? item.currentValue as int
                            : (item.currentValue is double
                                ? (item.currentValue as double).toInt()
                                : 0);

                        ManualTimeLogPreviewService.updatePreview(state);
                      });
                      state.activityFocusNode.unfocus();
                      removeOverlay(state);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      Overlay.of(state.context).insert(state.overlayEntry!);
    }
  }
}
