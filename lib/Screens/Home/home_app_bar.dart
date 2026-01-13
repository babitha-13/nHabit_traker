import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Goals/goal_dialog.dart';
import 'package:habit_tracker/Screens/Home/catchup_dialog.dart';
import 'package:habit_tracker/Screens/Timer/timer_page.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final GlobalKey<ScaffoldState> scaffoldKey;

  const HomeAppBar({
    super.key,
    required this.title,
    required this.scaffoldKey,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: FlutterFlowTheme.of(context).primary,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: FlutterFlowTheme.of(context).headerSheenGradient,
        ),
      ),
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.white),
        onPressed: () => scaffoldKey.currentState?.openDrawer(),
      ),
      title: Text(
        title,
        style: FlutterFlowTheme.of(context).headlineMedium.override(
              fontFamily: 'Outfit',
              color: Colors.white,
              fontSize: 22,
            ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.history, color: Colors.white),
          onPressed: () {
            showCatchUpDialogManually(context);
          },
        ),
        _goalButton(context),
        IconButton(
          icon: const Icon(Icons.timer, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TimerPage()),
            );
          },
        ),
        Visibility(
          visible: title == 'Tasks',
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: Colors.white),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'default',
                child: ListTile(
                  leading: Icon(Icons.sort_by_alpha),
                  title: Text('Default sort'),
                ),
              ),
              PopupMenuItem(
                value: 'importance',
                child: ListTile(
                  leading: Icon(Icons.star),
                  title: Text('Sort by importance'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _goalButton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => const GoalDialog(),
          );
        },
        child: Text(
          'Goal',
          style: FlutterFlowTheme.of(context).bodyLarge.override(
                fontFamily: 'Outfit',
                color: Colors.white,
                fontSize: 16,
              ),
        ),
      ),
    );
  }
}
