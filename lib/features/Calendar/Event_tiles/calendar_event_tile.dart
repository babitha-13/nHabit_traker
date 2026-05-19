import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/features/Calendar/Conflicting_events_overlap/diagonal_stripe_painter.dart';
import 'package:habit_tracker/features/Calendar/Event_tiles/dashed_border_painter.dart';
import 'package:habit_tracker/features/Item_component/presentation/item_component_ui.dart';
import 'package:habit_tracker/features/Item_component/presentation/item_dotted_line_painter.dart';
import 'dart:math' as math;

import 'package:habit_tracker/features/Calendar/Helpers/calendar_models.dart';
import 'package:habit_tracker/features/Calendar/Conflicting_events_overlap/calendar_overlap_calculator.dart';

/// Helper class for building calendar event tiles
class CalendarEventTileBuilder {
  final double Function() calculateHeightPerMinute;
  final Set<String> plannedOverlappedEventIds;
  final Function(CalendarEventMetadata) onEditEntry;
  final void Function(CalendarEventMetadata, DateTime? startTime,
      DateTime? endTime)? onAddTimeLog;

  // Cache for label offsets to avoid recalculating on every build
  Map<String, double> _labelOffsetCache = {};
  String? _lastCompletedEventsHash;
  String? _lastPlannedEventsHash;
  static const double _floatingLabelMinVisibleTop = 4.0;

  CalendarEventTileBuilder({
    required this.calculateHeightPerMinute,
    required this.plannedOverlappedEventIds,
    required this.onEditEntry,
    this.onAddTimeLog,
  });

  /// Generate hash of event list to detect changes
  String _generateEventsHash(List<CalendarEventData> events) {
    if (events.isEmpty) return '';
    // Create hash from event IDs and order
    return events.map((e) {
      final eventId = CalendarOverlapCalculator.stableEventId(e);
      return eventId ??
          '${e.startTime?.millisecondsSinceEpoch}_${e.endTime?.millisecondsSinceEpoch}';
    }).join('|');
  }

  /// Invalidate label offset cache if event list has changed
  void _invalidateCacheIfNeeded(
    List<CalendarEventData> completedEvents,
    List<CalendarEventData> plannedEvents,
  ) {
    final completedHash = _generateEventsHash(completedEvents);
    final plannedHash = _generateEventsHash(plannedEvents);

    // Only clear cache if event order changed
    if (completedHash != _lastCompletedEventsHash ||
        plannedHash != _lastPlannedEventsHash) {
      _labelOffsetCache.clear();
      _lastCompletedEventsHash = completedHash;
      _lastPlannedEventsHash = plannedHash;
    }
  }

  /// Calculate label offset for event positioning
  /// Uses cache to avoid recalculating on every build
  double calculateLabelOffset(
    CalendarEventData event,
    List<CalendarEventData> sortedEvents,
    bool isCompletedList,
  ) {
    if (event.startTime == null || event.endTime == null) return 0.0;

    // Generate cache key for this event
    final eventId = CalendarOverlapCalculator.stableEventId(event) ??
        '${event.startTime!.millisecondsSinceEpoch}_${event.endTime!.millisecondsSinceEpoch}';
    final cacheKey = '${isCompletedList ? 'completed' : 'planned'}_$eventId';

    // Check cache first
    if (_labelOffsetCache.containsKey(cacheKey)) {
      return _labelOffsetCache[cacheKey]!;
    }

    final eventIdForMatch = CalendarOverlapCalculator.stableEventId(event);
    final index = sortedEvents.indexWhere((e) {
      if (eventIdForMatch != null) {
        return CalendarOverlapCalculator.stableEventId(e) == eventIdForMatch;
      }
      return e.startTime == event.startTime &&
          e.endTime == event.endTime &&
          e.title == event.title;
    });

    if (index <= 0) {
      _labelOffsetCache[cacheKey] = 0.0;
      return 0.0;
    }

    final laneFreeY = <double>[];
    final heightPerMinute = calculateHeightPerMinute();

    double getPixelY(DateTime time) {
      final minutes = time.hour * 60 + time.minute + time.second / 60.0;
      return minutes * heightPerMinute;
    }

    for (int i = 0; i <= index; i++) {
      final e = sortedEvents[i];
      if (e.startTime == null || e.endTime == null) continue;

      final startY = getPixelY(e.startTime!);
      final duration = e.endTime!.difference(e.startTime!);
      final durationMinutes = duration.inSeconds / 60.0;
      final isThin = duration.inSeconds < 60 && isCompletedList;
      final timeBoxHeight = durationMinutes * heightPerMinute;
      final cappedHeight = math.max(1.0, timeBoxHeight);
      final actualHeight = isThin
          ? 3.0.clamp(1.0, cappedHeight)
          : timeBoxHeight.clamp(1.0, double.infinity);
      final hasFloatingLabel = actualHeight < 24.0;
      final occupiedTop = hasFloatingLabel ? startY - 28.0 : startY;
      final occupiedBottom = startY + actualHeight;
      int assignedLane = -1;
      for (int l = 0; l < laneFreeY.length; l++) {
        if (laneFreeY[l] + 2.0 <= occupiedTop) {
          assignedLane = l;
          break;
        }
      }

      if (assignedLane == -1) {
        laneFreeY.add(occupiedBottom);
        assignedLane = laneFreeY.length - 1;
      } else {
        laneFreeY[assignedLane] = occupiedBottom;
      }
      if (i == index) {
        final offset = hasFloatingLabel ? assignedLane * 80.0 : 0.0;
        // Cache the result
        _labelOffsetCache[cacheKey] = offset;
        return offset;
      }
    }
    _labelOffsetCache[cacheKey] = 0.0;
    return 0.0;
  }

  /// Build event tile widget
  Widget buildEventTile(
    CalendarEventData event,
    bool isCompleted,
    List<CalendarEventData> sortedCompletedEvents,
    List<CalendarEventData> sortedPlannedEvents,
  ) {
    if (event.startTime == null || event.endTime == null) {
      return const SizedBox.shrink();
    }

    // Invalidate cache if event lists have changed
    _invalidateCacheIfNeeded(sortedCompletedEvents, sortedPlannedEvents);

    final eventList = isCompleted ? sortedCompletedEvents : sortedPlannedEvents;
    final labelOffset = calculateLabelOffset(event, eventList, isCompleted);
    final duration = event.endTime!.difference(event.startTime!);
    final isessential = event.title.startsWith('NP:');
    final rawEvent = event.event;
    final isDueMarker = rawEvent is Map && (rawEvent['isDueMarker'] == true);
    final isThinLine = duration.inSeconds < 60 && (isCompleted || isDueMarker);

    final durationMinutes = duration.inSeconds / 60.0;
    final timeBoxHeight = durationMinutes * calculateHeightPerMinute();
    final cappedHeight = math.max(1.0, timeBoxHeight);
    final actualTimeBoxHeight = isThinLine
        ? 3.0.clamp(1.0, cappedHeight)
        : timeBoxHeight.clamp(1.0, double.infinity);

    final labelFitsInside = actualTimeBoxHeight >= 24.0;
    final eventStartMinutes = event.startTime!.hour * 60 +
        event.startTime!.minute +
        (event.startTime!.second / 60.0);
    final eventStartY = eventStartMinutes * calculateHeightPerMinute();

    double clampFloatingLabelTop(double preferredTop) {
      final minLocalTop = _floatingLabelMinVisibleTop - eventStartY;
      return math.max(preferredTop, minLocalTop);
    }

    final metadata = CalendarEventMetadata.fromMap(event.event);
    final eventId = CalendarOverlapCalculator.stableEventId(event);
    final isConflict = !isCompleted &&
        eventId != null &&
        plannedOverlappedEventIds.contains(eventId);

    final timeBox = buildTimeBox(
      event,
      actualTimeBoxHeight,
      isCompleted,
      isessential,
      isConflict: isConflict,
    );

    final label = labelFitsInside
        ? buildInlineLabel(event, isCompleted, isessential)
        : buildFloatingLabel(event, isCompleted, isessential);

    void handleLongPress() {
      if (isCompleted && metadata != null && metadata.sessionIndex >= 0) {
        onEditEntry(metadata);
      } else if (onAddTimeLog != null && metadata != null) {
        // Allow adding a time log via long press for today or any past day.
        final eventDate = event.startTime;
        if (eventDate != null) {
          final today = DateTime.now();
          final todayDate = DateTime(today.year, today.month, today.day);
          final eventDateOnly =
              DateTime(eventDate.year, eventDate.month, eventDate.day);
          if (!eventDateOnly.isAfter(todayDate)) {
            onAddTimeLog!(metadata, event.startTime, event.endTime);
          }
        }
      }
    }

    final timeBoxWithGesture = GestureDetector(
      onLongPress: handleLongPress,
      child: timeBox,
    );

    // Generate stable key for widget to prevent unnecessary rebuilds
    String? widgetKey;
    if (eventId != null) {
      // Use stable event ID, append sessionIndex for completed events to ensure uniqueness
      if (isCompleted && metadata != null && metadata.sessionIndex >= 0) {
        widgetKey = '${eventId}_session_${metadata.sessionIndex}';
      } else {
        widgetKey = eventId;
      }
    } else if (event.startTime != null && event.endTime != null) {
      // Fallback key based on time if no event ID
      widgetKey =
          'event_${event.startTime!.millisecondsSinceEpoch}_${event.endTime!.millisecondsSinceEpoch}';
    }

    final keyedWidget = widgetKey != null ? Key(widgetKey) : null;

    if (isThinLine) {
      return OverflowBox(
        key: keyedWidget,
        minHeight: 0,
        maxHeight: double.infinity,
        alignment: Alignment.centerLeft,
        child: Container(
          height: actualTimeBoxHeight,
          constraints: BoxConstraints(
            minHeight: actualTimeBoxHeight,
            minWidth: 0,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: timeBoxWithGesture),
              Positioned(
                left: labelOffset,
                top: clampFloatingLabelTop(-24.0),
                child: label,
              ),
            ],
          ),
        ),
      );
    }

    return OverflowBox(
      key: keyedWidget,
      minHeight: 0,
      maxHeight: double.infinity,
      alignment: Alignment.topLeft,
      child: Container(
        height: actualTimeBoxHeight,
        constraints: BoxConstraints(
          minHeight: actualTimeBoxHeight,
          minWidth: 0,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: timeBoxWithGesture),
            Positioned(
              left: labelFitsInside ? 4.0 : labelOffset,
              top: labelFitsInside ? 4.0 : clampFloatingLabelTop(-28.0),
              child: label,
            ),
          ],
        ),
      ),
    );
  }

  /// Build time box widget
  Widget buildTimeBox(CalendarEventData event, double height, bool isCompleted,
      bool isessential,
      {required bool isConflict}) {
    final metadata = CalendarEventMetadata.fromMap(event.event);
    final activityType = (metadata?.activityType ?? 'task').toLowerCase();

    Color boxColor;
    Color borderColor;
    double leftEdgeWidth;
    Widget leftEdgeContent;

    if (activityType == 'essential') {
      boxColor = event.color.withValues(alpha: isCompleted ? 0.07 : 0.03);
      borderColor = event.color.withValues(alpha: 0.2);
      leftEdgeWidth = 6.0;
      leftEdgeContent = CustomPaint(
        painter: DoubleLinePainter(
          color: event.color.withValues(alpha: isCompleted ? 0.6 : 0.4),
        ),
      );
    } else if (activityType == 'habit') {
      boxColor = event.color.withValues(alpha: isCompleted ? 0.12 : 0.06);
      borderColor = event.color.withValues(alpha: 0.25);
      leftEdgeWidth = 4.0;
      leftEdgeContent = CustomPaint(
        painter: DottedLinePainter(
          color: event.color.withValues(alpha: isCompleted ? 0.9 : 0.75),
        ),
      );
    } else {
      boxColor = event.color.withValues(alpha: isCompleted ? 0.18 : 0.10);
      borderColor = event.color.withValues(alpha: 0.3);
      leftEdgeWidth = 3.5;
      leftEdgeContent = Container(
        color: event.color.withValues(alpha: isCompleted ? 0.85 : 0.7),
      );
    }

    final conflictBorderColor = Colors.red.shade700;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          constraints: const BoxConstraints(
            minHeight: 1.0,
            minWidth: 0,
          ),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(4.0),
            border: Border.all(
              color: isConflict ? conflictBorderColor : borderColor,
              width: isConflict ? 2.0 : 0.8,
            ),
            boxShadow: isConflict
                ? [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: leftEdgeWidth,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4.0),
              bottomLeft: Radius.circular(4.0),
            ),
            child: leftEdgeContent,
          ),
        ),
        if (isConflict)
          ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: CustomPaint(
              painter: DiagonalStripePainter(
                stripeColor: Colors.red.withValues(alpha: 0.18),
                stripeWidth: 3.0,
                spacing: 7.0,
              ),
            ),
          ),
      ],
    );
  }

  /// Build inline label widget
  Widget buildInlineLabel(
    CalendarEventData event,
    bool isCompleted,
    bool isessential,
  ) {
    final metadata = CalendarEventMetadata.fromMap(event.event);
    final activityType = (metadata?.activityType ?? 'task').toLowerCase();
    final isEssentialActivity = activityType == 'essential';

    // Fills are now near-transparent — text sits on a light background, so always use dark text.
    Color textColor;
    if (isEssentialActivity) {
      textColor = Colors.black54;
    } else {
      // Use the category color for text when it's dark enough to read on a light bg,
      // otherwise fall back to black87.
      textColor = event.color.computeLuminance() < 0.5
          ? event.color.withValues(alpha: 0.9)
          : Colors.black87;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 12.0,
        minWidth: 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isCompleted)
                Padding(
                  padding: const EdgeInsets.only(right: 2.0),
                  child: Icon(
                    Icons.check,
                    size: 12,
                    color: textColor,
                  ),
                ),
              Flexible(
                child: Text(
                  event.title.isNotEmpty ? event.title : ' ',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          if (event.description != null && event.description!.isNotEmpty)
            Text(
              event.description!,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.75),
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
        ],
      ),
    );
  }

  /// Build floating label widget
  Widget buildFloatingLabel(
    CalendarEventData event,
    bool isCompleted,
    bool isessential,
  ) {
    final metadata = CalendarEventMetadata.fromMap(event.event);
    final activityType = (metadata?.activityType ?? 'task').toLowerCase();
    final isEssentialActivity = activityType == 'essential';
    final isHabit = activityType == 'habit';

    // Per-type chip style:
    // Task   → solid fill, no special border
    // Habit  → solid fill + dashed white border overlay
    // Essential → transparent fill + solid colored border (less prominent)
    Color fillColor;
    Color textColor;
    Border? solidBorder;
    bool useDashedBorder = false;
    Color dashedBorderColor = Colors.transparent;
    List<BoxShadow>? shadows;

    if (isEssentialActivity) {
      fillColor = event.color.withValues(alpha: isCompleted ? 0.08 : 0.0);
      textColor = Colors.black87;
      solidBorder = Border.all(
        color: event.color.withValues(alpha: isCompleted ? 0.65 : 0.45),
        width: 1.5,
      );
      shadows = null;
    } else if (isHabit) {
      fillColor = event.color.withValues(alpha: isCompleted ? 0.92 : 0.82);
      textColor = event.color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
      useDashedBorder = true;
      dashedBorderColor = Colors.black.withValues(alpha: isCompleted ? 0.35 : 0.25);
      shadows = const [BoxShadow(color: Colors.black26, blurRadius: 4.0, offset: Offset(0, 2))];
    } else {
      // task
      fillColor = event.color.withValues(alpha: isCompleted ? 0.92 : 0.82);
      textColor = event.color == const Color(0xFF1A1A1A)
          ? Colors.white
          : event.color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
      shadows = const [BoxShadow(color: Colors.black26, blurRadius: 4.0, offset: Offset(0, 2))];
    }

    final rowContent = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (isCompleted)
          Padding(
            padding: const EdgeInsets.only(right: 2.0),
            child: Icon(Icons.check, size: 11, color: textColor),
          ),
        Flexible(
          child: Text(
            event.title.isNotEmpty ? event.title : ' ',
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ],
    );

    final container = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(4.0),
        border: solidBorder,
        boxShadow: shadows,
      ),
      child: rowContent,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 24.0, minWidth: 40.0),
      child: useDashedBorder
          ? Stack(
              children: [
                container,
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: DashedBorderPainter(
                        color: dashedBorderColor,
                        borderRadius: 4.0,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : container,
    );
  }
}
