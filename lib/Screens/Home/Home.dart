import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:habit_tracker/Helper/Response/login_response.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/constants.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Screens/Create%20Catagory/create_category.dart';
import 'package:habit_tracker/Screens/CreateHabit/create_Habit.dart';
import 'package:habit_tracker/Screens/Manage%20categories/manage_categories.dart';
import 'package:habit_tracker/Screens/Progress/progress_page.dart';
import 'package:habit_tracker/Screens/Sequence/sequence.dart';
import 'package:habit_tracker/Screens/Task/task_page.dart';
import 'package:habit_tracker/Screens/Task/task_tab.dart';
import 'package:habit_tracker/Screens/Today/today.dart';
import 'package:habit_tracker/main.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String title = "Today";
  DateTime preBackPress = DateTime.now();
  final GlobalKey _parentKey = GlobalKey();
  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showCompleted = false;
  int currentIndex = 1;
  late Widget cWidget;
  String _sortMode = 'default';

  @override
  void initState() {
    super.initState();
    cWidget = TodayPage(showCompleted: _showCompleted);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Container(
        color: Colors.white,
        child: Scaffold(
          key: scaffoldKey,
          appBar: AppBar(
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
              Visibility(
                visible: title != "Progress" && title != "Tasks",
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Show Completed',
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                          fontFamily: 'Readex Pro',
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: _showCompleted,
                        onChanged: (value) {
                          setState(() => _showCompleted = value);
                          NotificationCenter.post("showCompleted", _showCompleted);
                          },
                        activeColor: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
              Visibility(
                  visible: title == "Tasks",
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.sort, color: Colors.white),
                    onSelected: (value) {
                      setState(() => _sortMode = value);
                    },
                    itemBuilder: (context) => const [
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
              )
            ],
            centerTitle: false,
            elevation: 0,
          ),
          drawer: Drawer(
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          color: theme.primary,
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Today',
                                style: theme.headlineSmall.override(
                                  fontFamily: 'Outfit',
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "email",
                                style: theme.bodyMedium.override(
                                  fontFamily: 'Readex Pro',
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            children: [
                              _DrawerItem(
                                icon: Icons.home,
                                label: 'Home',
                                onTap: () {
                                  setState(() {
                                    currentIndex = 1;
                                    loadPage("Today");
                                    Navigator.pop(context);
                                  });
                                },
                              ),
                              _DrawerItem(
                                icon: Icons.category,
                                label: 'Manage Categories',
                                onTap: () {
                                  loadPage("Manage Categories");
                                  Navigator.pop(context);
                                },
                              ),
                              _DrawerItem(
                                icon: Icons.playlist_play,
                                label: 'Sequences',
                                onTap: () {
                                  loadPage("Sequences");
                                  Navigator.pop(context);
                                },
                              ),
                              const Divider(),
                              _DrawerItem(
                                icon: Icons.person,
                                label: 'Profile',
                                onTap: () {},
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.logout,
                    label: 'Log Out',
                    onTap: () {
                      sharedPref
                          .remove(SharedPreference.name.sUserDetails)
                          .then((value) {
                        setState(() {
                          users = LoginResponse();
                          Navigator.pushReplacementNamed(context, login);
                        });
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          body: SafeArea(
            child: Stack(
              key: _parentKey,
              children: [
                Container(color: Colors.white, child: cWidget),
                Visibility(
                  visible: title != "Tasks",
                  child: Positioned(
                    right: 16,
                    bottom: 88, // above bottom nav
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FloatingActionButton(
                          heroTag: 'fab_add_habit',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CreateHabitPage(),
                              ),
                            ).then((value){
                              if(value){
                                NotificationCenter.post("loadToday", "");
                              }
                            });
                          },
                          tooltip: 'Add Habit',
                          backgroundColor: FlutterFlowTheme.of(context).primary,
                          child: const Icon(Icons.add, color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        FloatingActionButton(
                          heroTag: 'fab_add_category',
                          onPressed: _showAddCategoryDialog,
                          tooltip: 'Add Category',
                          backgroundColor: FlutterFlowTheme.of(context).secondary,
                          child: const Icon(Icons.create_new_folder,
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).secondaryBackground,
              border: Border(
                top: BorderSide(
                  color: FlutterFlowTheme.of(context).alternate,
                  width: 1,
                ),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: currentIndex,
              onTap: (i) {
                setState(() {
                  currentIndex = i;
                  if (i == 0) {
                    loadPage("Tasks");
                  } else if (i == 1) {
                    loadPage("Today");
                  } else if (i == 2) {
                    loadPage("Progress");
                  }
                });
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
              selectedItemColor: FlutterFlowTheme.of(context).primary,
              unselectedItemColor: FlutterFlowTheme.of(context).secondaryText,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.assignment),
                  label: 'Tasks',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.today),
                  label: 'Today',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.trending_up),
                  label: 'Progress',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (title == "Today") {
      final timeGap = DateTime.now().difference(preBackPress);
      final cantExit = timeGap >= const Duration(seconds: 2);
      preBackPress = DateTime.now();
      if (cantExit) {
        const snack = SnackBar(
          content: Text('Press Back button again to Exit'),
          duration: Duration(seconds: 2),
        );
        ScaffoldMessenger.of(context).showSnackBar(snack);
        return false;
      } else {
        return true;
      }
    } else {
      if (mounted) {
        title = "Today";
        setState(() {
          cWidget =  TodayPage( showCompleted: _showCompleted,);
        });
      }
      return false;
    }
  }

  void loadPage(s) {
    if (mounted) {
      setState(() {
        if (s == "Today") {
          title = s;
          cWidget =  TodayPage(
            showCompleted: _showCompleted,
          );
        }
        if (s == "Tasks") {
          title = s;
          cWidget = const TaskTab();
        }
        if (s == "Today") {
          title = s;
          cWidget =  TodayPage(
            showCompleted: _showCompleted,
          );
        }
        if (s == "Progress") {
          title = s;
          cWidget = const ProgressPage();
        }
        if(s == "Manage Categories"){
          title = s;
          cWidget = const ManageCategories();
        }
        if(s == "Sequences"){
          title = s;
          cWidget = const Sequences();
        }
      });
    }
  }

  void _showAddCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          StatefulBuilder(builder: (context, setLocalState) => const CreateCategory()),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.primary),
      title: Text(label, style: theme.bodyLarge),
      onTap: onTap,
    );
  }
}
