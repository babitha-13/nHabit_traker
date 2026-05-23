import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';

class AppBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(String) loadPage;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.loadPage,
  });

  // Visual layout (left → right):
  //   [Tasks] [Habits]   (Queue)   (Calendar)   [Templates] [Routines]
  //    small   small      LARGE     LARGE        small       small
  //
  // Page indices below match the _pageIndexMap in home_screen.dart and
  // are intentionally non-sequential here because the visual order differs
  // from the IndexedStack order.
  static const List<_TabSpec> _tabs = [
    _TabSpec(
      pageIndex: 0,
      label: 'Tasks',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment,
      isPrimary: false,
    ),
    _TabSpec(
      pageIndex: 1,
      label: 'Habits',
      icon: Icons.flag_outlined,
      activeIcon: Icons.flag,
      isPrimary: false,
    ),
    _TabSpec(
      pageIndex: 2,
      label: 'Queue',
      icon: Icons.queue_outlined,
      activeIcon: Icons.queue,
      isPrimary: true,
    ),
    _TabSpec(
      pageIndex: 5,
      label: 'Calendar',
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today,
      isPrimary: true,
    ),
    _TabSpec(
      pageIndex: 3,
      label: 'Templates',
      icon: Icons.dashboard_customize_outlined,
      activeIcon: Icons.dashboard_customize,
      isPrimary: false,
    ),
    _TabSpec(
      pageIndex: 4,
      label: 'Routines',
      icon: Icons.playlist_play_outlined,
      activeIcon: Icons.playlist_play,
      isPrimary: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        border: Border(
          top: BorderSide(color: theme.alternate, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _tabs.map((tab) {
              final selected = currentIndex == tab.pageIndex;
              return Expanded(
                flex: tab.isPrimary ? 3 : 2,
                child: _TabButton(
                  spec: tab,
                  selected: selected,
                  theme: theme,
                  onTap: () => loadPage(tab.label),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _TabSpec {
  final int pageIndex;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool isPrimary;

  const _TabSpec({
    required this.pageIndex,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.isPrimary,
  });
}

class _TabButton extends StatelessWidget {
  final _TabSpec spec;
  final bool selected;
  final FlutterFlowTheme theme;
  final VoidCallback onTap;

  const _TabButton({
    required this.spec,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = spec.isPrimary ? 28.0 : 22.0;
    final fontSize = spec.isPrimary ? 12.5 : 10.5;
    final fontWeight = spec.isPrimary ? FontWeight.w600 : FontWeight.w500;

    final activeColor = theme.primary;
    final inactiveColor = theme.secondaryText;
    final color = selected ? activeColor : inactiveColor;

    // Primary tabs get a soft pill behind the icon when selected so they
    // read as the dominant destinations even at a glance.
    final showPill = spec.isPrimary && selected;

    return InkResponse(
      onTap: onTap,
      highlightShape: BoxShape.rectangle,
      containedInkWell: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: showPill
                  ? const EdgeInsets.symmetric(horizontal: 14, vertical: 2)
                  : EdgeInsets.zero,
              decoration: showPill
                  ? BoxDecoration(
                      color: activeColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    )
                  : null,
              child: Icon(
                selected ? spec.activeIcon : spec.icon,
                size: iconSize,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              spec.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
