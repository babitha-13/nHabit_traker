import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:intl/intl.dart';

class CalendarDayViewBody extends StatelessWidget {
  final bool showPlanned;
  final DateTime selectedDate;
  final GlobalKey<DayViewState> dayViewKey;
  final int plannedOverlapPairCount;
  final double currentScrollOffset;
  final double initialScrollOffset;
  final double calendarViewportHeight;
  final Offset? lastTapDownPosition;
  final bool isLoadingEvents;
  final EventController plannedEventController;
  final EventController completedEventController;
  final int defaultDurationMinutes;
  final Function(int) onChangeDate;
  final VoidCallback onResetDate;
  final Function(bool) onSaveTabState;
  final Function(bool) onTogglePlanned;
  final VoidCallback onShowTimeBreakdownChart;
  final Function(DateTime, DateTime) onShowManualEntryDialog;
  final Function(ScaleStartDetails) onScaleStart;
  final Function(ScaleUpdateDetails) onScaleUpdate;
  final Function(ScaleEndDetails) onScaleEnd;
  final Function(double) onCalendarViewportHeightChanged;
  final Function(double) onCurrentScrollOffsetChanged;
  final Function(Offset) onPointerDown;
  final double Function() calculateHeightPerMinute;
  final Widget Function(CalendarEventData, bool) buildEventTile;
  final Widget Function() buildOverlapBanner;

  const CalendarDayViewBody({
    super.key,
    required this.showPlanned,
    required this.selectedDate,
    required this.dayViewKey,
    required this.plannedOverlapPairCount,
    required this.currentScrollOffset,
    required this.initialScrollOffset,
    required this.calendarViewportHeight,
    required this.lastTapDownPosition,
    required this.isLoadingEvents,
    required this.plannedEventController,
    required this.completedEventController,
    required this.defaultDurationMinutes,
    required this.onChangeDate,
    required this.onResetDate,
    required this.onSaveTabState,
    required this.onTogglePlanned,
    required this.onShowTimeBreakdownChart,
    required this.onShowManualEntryDialog,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
    required this.onCalendarViewportHeightChanged,
    required this.onCurrentScrollOffsetChanged,
    required this.onPointerDown,
    required this.calculateHeightPerMinute,
    required this.buildEventTile,
    required this.buildOverlapBanner,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: Colors.white,
          child: Column(
            children: [
              // Header: Date Navigation and Toggle
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Date Navigation Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => onChangeDate(-1),
                        ),
                        GestureDetector(
                          onTap: onResetDate,
                          child: Text(
                            DateFormat('EEEE, MMM d, y').format(selectedDate),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => onChangeDate(1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // View Toggle (Planned vs Completed)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (!showPlanned) {
                                  onTogglePlanned(true);
                                  onSaveTabState(true);
                                }
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: showPlanned
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: showPlanned
                                      ? [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            blurRadius: 2,
                                            offset: const Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    'Planned',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: showPlanned
                                          ? Colors.blue.shade700
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                if (showPlanned) {
                                  onTogglePlanned(false);
                                  onSaveTabState(false);
                                }
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: !showPlanned
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: !showPlanned
                                      ? [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            blurRadius: 2,
                                            offset: const Offset(0, 1),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    'Completed',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: !showPlanned
                                          ? Colors.green.shade700
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Prominent planned-schedule conflict banner
              if (showPlanned && plannedOverlapPairCount > 0)
                buildOverlapBanner(),

              // Calendar Body
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Defer setState call to avoid calling it during build
                    SchedulerBinding.instance.addPostFrameCallback((_) {
                      onCalendarViewportHeightChanged(constraints.maxHeight);
                    });
                    return GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onScaleStart: onScaleStart,
                      onScaleUpdate: onScaleUpdate,
                      onScaleEnd: onScaleEnd,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          // Block horizontal scroll notifications to prevent swipe navigation
                          if (notification is ScrollUpdateNotification) {
                            if (notification.metrics.axis == Axis.horizontal) {
                              // Absorb horizontal scroll notifications - prevent swipe navigation
                              return true;
                            } else if (notification.metrics.axis ==
                                Axis.vertical) {
                              onCurrentScrollOffsetChanged(
                                  notification.metrics.pixels);
                            }
                          }
                          return false;
                        },
                        child: GestureDetector(
                          // Block horizontal drag gestures to prevent date navigation via swipe
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (details) {
                            // Absorb the gesture - prevent swipe navigation
                          },
                          onHorizontalDragUpdate: (details) {
                            // Absorb the gesture - prevent swipe navigation
                          },
                          onHorizontalDragEnd: (details) {
                            // Absorb the gesture - prevent swipe navigation
                          },
                          child: ScrollConfiguration(
                            // Disable horizontal scrolling to prevent swipe navigation
                            behavior: ScrollConfiguration.of(context).copyWith(
                              scrollbars: false,
                            ),
                            child: Listener(
                              onPointerDown: (event) {
                                // Capture the local position of the tap within the viewport
                                onPointerDown(event.localPosition);
                              },
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onHorizontalDragStart: (_) {},
                                    onHorizontalDragUpdate: (_) {},
                                    onHorizontalDragEnd: (_) {},
                                    child: DayView(
                                      key: dayViewKey,
                                      scrollOffset: initialScrollOffset,
                                      controller: showPlanned
                                          ? plannedEventController
                                          : completedEventController,
                                      // initialDay sets the date - this should update when _selectedDate changes
                                      initialDay: selectedDate,
                                      heightPerMinute:
                                          calculateHeightPerMinute(),
                                      backgroundColor: Colors.white,
                                      showVerticalLine:
                                          true, // Ensure vertical line is visible
                                      timeLineWidth:
                                          65.0, // Increased for better visibility
                                      // Ensure standard hourly steps for timeline
                                      hourIndicatorSettings:
                                          HourIndicatorSettings(
                                        color: Colors.grey.shade300,
                                      ),
                                      timeLineBuilder: (date) {
                                        final hour = date.hour;
                                        final minute = date.minute;

                                        // Show labels for each hour (at minute 0)
                                        if (minute != 0) {
                                          return const SizedBox.shrink();
                                        }

                                        // Show hour labels (e.g., "12 AM", "1 AM", etc.)
                                        final hour12 = hour == 0 || hour == 12
                                            ? 12
                                            : hour % 12;
                                        final period = hour < 12 ? 'AM' : 'PM';
                                        return Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.only(
                                              right: 8.0, top: 0.0),
                                          alignment: Alignment.topRight,
                                          child: Text(
                                            '$hour12 $period',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.right,
                                          ),
                                        );
                                      },
                                      liveTimeIndicatorSettings:
                                          const LiveTimeIndicatorSettings(
                                        color: Colors.red,
                                        height: 2.0,
                                        offset: 5,
                                      ),
                                      eventTileBuilder:
                                          (date, events, a, b, c) {
                                        return buildEventTile(
                                            events.first, !showPlanned);
                                      },
                                      dayTitleBuilder: (date) {
                                        return const SizedBox
                                            .shrink(); // Hide default header
                                      },
                                      onDateLongPress: (date) {
                                        if (lastTapDownPosition != null) {
                                          final double tapY =
                                              lastTapDownPosition!.dy;

                                          double scrollOffset =
                                              currentScrollOffset;

                                          // Try to get scroll position directly from DayView state
                                          try {
                                            final dayViewState =
                                                dayViewKey.currentState;
                                            if (dayViewState != null) {
                                              // Access scrollController if available
                                              final dynamic state =
                                                  dayViewState;
                                              if (state.scrollController !=
                                                  null) {
                                                scrollOffset = state
                                                    .scrollController
                                                    .position
                                                    .pixels;
                                              }
                                            }
                                          } catch (e) {
                                            // Fallback to tracked offset
                                          }
                                          // scrollOffset is how far we've scrolled from the top
                                          final double totalPixels =
                                              tapY + scrollOffset;
                                          final double totalMinutes =
                                              totalPixels /
                                                  calculateHeightPerMinute();

                                          // Convert total minutes to HH:MM on the selected date
                                          final int totalMinutesInt =
                                              totalMinutes.toInt();
                                          final int hours =
                                              totalMinutesInt ~/ 60;
                                          final int minutes =
                                              totalMinutesInt % 60;

                                          // Round minutes to nearest 5
                                          final int remainder = minutes % 5;
                                          final int roundedMinute =
                                              remainder >= 2.5
                                                  ? minutes + (5 - remainder)
                                                  : minutes - remainder;

                                          final startTime = DateTime(
                                            selectedDate.year,
                                            selectedDate.month,
                                            selectedDate.day,
                                            hours,
                                            0, // Start from 0 minutes and add rounded minutes
                                          ).add(
                                              Duration(minutes: roundedMinute));

                                          final endTime = startTime.add(
                                              Duration(
                                                  minutes:
                                                      defaultDurationMinutes));

                                          onShowManualEntryDialog(
                                            startTime,
                                            endTime,
                                          );
                                        } else {
                                          // Fallback to old logic if no tap position (unlikely)
                                          final minute = date.minute;
                                          final remainder = minute % 5;
                                          final roundedMinute = remainder >= 2.5
                                              ? minute + (5 - remainder)
                                              : minute - remainder;

                                          final startTime = DateTime(
                                            date.year,
                                            date.month,
                                            date.day,
                                            date.hour,
                                            roundedMinute,
                                          );
                                          final endTime = startTime.add(
                                              Duration(
                                                  minutes:
                                                      defaultDurationMinutes));

                                          onShowManualEntryDialog(
                                            startTime,
                                            endTime,
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                  // Loading overlay
                                  if (isLoadingEvents)
                                    Positioned.fill(
                                      child: Container(
                                        color: Colors.white.withOpacity(0.7),
                                        child: const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Time breakdown FAB positioned at bottom left
        Positioned(
          left: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: onShowTimeBreakdownChart,
            heroTag: 'pie_chart',
            tooltip: 'Time Breakdown',
            backgroundColor: FlutterFlowTheme.of(context).primary,
            child: const Icon(Icons.pie_chart),
          ),
        ),
      ],
    );
  }
}
