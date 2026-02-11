import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';

class AppBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(String) loadPage;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.loadPage,
  });

  static const List<String> _pageNames = [
    "Tasks",
    "Habits",
    "Queue",
    "Essential",
    "Routines",
    "Calendar",
  ];

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        border: Border(
          top: BorderSide(
            color: theme.alternate,
            width: 1,
          ),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          if (index >= 0 && index < _pageNames.length) {
            loadPage(_pageNames[index]);
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: theme.secondaryBackground,
        selectedItemColor: theme.primary,
        unselectedItemColor: theme.secondaryText,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Tasks',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.flag),
            label: 'Habits',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.queue),
            label: 'Queue',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.monitor_heart),
            label: 'Essential',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.playlist_play),
            label: 'Routines',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendar',
          ),
        ],
      ),
    );
  }
}
