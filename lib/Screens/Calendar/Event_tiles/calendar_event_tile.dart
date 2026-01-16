import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Screens/Calendar/Conflicting_events_overlap/diagonal_stripe_painter.dart';
import 'package:habit_tracker/Screens/Calendar/Event_tiles/dotted_diagonal_painter.dart';
import 'package:habit_tracker/Screens/Calendar/Event_tiles/double_diagonal_painter.dart';
import 'dart:math' as math;

import 'package:habit_tracker/Screens/Calendar/Helpers/calendar_models.dart';
import 'package:habit_tracker/Screens/Calendar/Conflicting_events_overlap/calendar_overlap_calculator.dart';

/// Helper class for building calendar event tiles
class CalendarEventTileBuilder {
  final double Function() calculateHeightPerMinute;
  final Set<String> plannedOverlappedEventIds;
  final Function(CalendarEventMetadata) onEditEntry;

  // Cache for label offsets to avoid recalculating on every build
  Map<String, double> _labelOffsetCache = {};
  String? _lastCompletedEventsHash;
  String? _lastPlannedEventsHash;

  CalendarEventTileBuilder({
    required this.calculateHeightPerMinute,
    required this.plannedOverlappedEventIds,
    required this.onEditEntry,
  });

  /// Generate hash of event list to detect changes
  String _generateEventsHash(List<CalendarEventData> events) {
    if (events.isEmpty) return '';
    // Create hash from event IDs and order
    return events.map((e) {
      final eventId = CalendarOverlapCalculator.stableEventId(e);
      return eventId ?? '${e.startTime?.millisecondsSinceEpoch}_${e.endTime?.millisecondsSinceEpoch}';
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

    final index = sortedEvents.indexOf(event);
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
      widgetKey = 'event_${event.startTime!.millisecondsSinceEpoch}_${event.endTime!.millisecondsSinceEpoch}';
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
                top: -24.0,
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
              top: labelFitsInside ? 4.0 : -28.0,
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
    final activityType = metadata?.activityType ?? 'task';
    Color boxColor;
    Color borderColor = event.color;
    CustomPainter? patternPainter;

    if (activityType == 'essential') {
      boxColor = event.color.withOpacity(isCompleted ? 0.25 : 0.12);
      borderColor = event.color.withOpacity(0.3);
      patternPainter = DoubleDiagonalPainter(
        stripeColor: event.color.withOpacity(0.2),
        stripeWidth: 2.5,
        spacing: 28.0,
        lineGap: 5.0,
      );
    } else if (activityType == 'habit') {
      boxColor = event.color.withOpacity(isCompleted ? 0.5 : 0.25);
      borderColor = event.color;
      patternPainter = DottedDiagonalPainter(
        stripeColor: event.color.withOpacity(0.6),
        stripeWidth: 3.0,
        spacing: 12.0,
        dotLength: 4.0,
        dotGap: 4.0,
      );
    } else {
      if (isCompleted) {
        boxColor = event.color.withOpacity(0.6);
      } else {
        boxColor = event.color.withOpacity(0.3);
      }
      borderColor = event.color;
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
              width: isConflict ? 2.0 : 1.0,
            ),
            boxShadow: isConflict
                ? [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: patternPainter != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: patternPainter,
                    ),
                  ),
                )
              : null,
        ),
        if (isConflict)
          ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: CustomPaint(
              painter: DiagonalStripePainter(
                stripeColor: Colors.red.withOpacity(0.18),
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
    final activityType = metadata?.activityType ?? 'task';
    final isEssentialActivity = activityType == 'essential';

    Color textColor;
    if (isEssentialActivity || event.color == Colors.grey) {
      textColor = Colors.black;
    } else if (event.color == const Color(0xFF1A1A1A)) {
      textColor = Colors.white;
    } else {
      textColor =
          event.color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
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
          Text(
            event.title.isNotEmpty ? event.title : ' ',
            style: TextStyle(
              color: isEssentialActivity
                  ? (isCompleted ? Colors.black87 : textColor.withOpacity(0.7))
                  : textColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          if (event.description != null && event.description!.isNotEmpty)
            Text(
              event.description!,
              style: TextStyle(
                color: isEssentialActivity && isCompleted
                    ? Colors.black87
                    : textColor.withOpacity(0.8),
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
    final activityType = metadata?.activityType ?? 'task';
    final isEssentialActivity = activityType == 'essential';
    final labelColor = isEssentialActivity
        ? event.color.withOpacity(0.5)
        : event.color.withOpacity(0.9);
    Color textColor;
    if (isEssentialActivity || event.color == Colors.grey) {
      textColor = Colors.black;
    } else if (event.color == const Color(0xFF1A1A1A)) {
      textColor = Colors.white;
    } else {
      textColor =
          event.color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 24.0,
        minWidth: 40.0,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: labelColor,
          borderRadius: BorderRadius.circular(4.0),
          border: isCompleted
              ? Border.all(
                  color: event.color,
                  width: 1.5,
                )
              : null,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4.0,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          event.title.isNotEmpty ? event.title : ' ',
          style: TextStyle(
            color:
                isEssentialActivity && isCompleted ? Colors.black87 : textColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: isCompleted
                ? null
                : [
                    Shadow(
                      offset: const Offset(0, 0),
                      blurRadius: 2.0,
                      color: Colors.black.withOpacity(0.5),
                    ),
                  ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
    );
  }
}
