import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:habit_tracker/Helper/Response/login_response.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/constants.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Helper/backend/goal_service.dart';
import 'package:habit_tracker/Screens/Goals/goal_onboarding_dialog.dart';
import 'package:habit_tracker/Screens/Create%20Catagory/create_category.dart';
import 'package:habit_tracker/Screens/createHabit/create_habit.dart';
import 'package:habit_tracker/Screens/Manage%20categories/manage_categories.dart';
import 'package:habit_tracker/Screens/Sequence/sequence.dart';
import 'package:habit_tracker/Screens/Task/task_tab.dart';
import 'package:habit_tracker/Screens/Habits/habits_page.dart';
import 'package:habit_tracker/Screens/Timer/timer_page.dart';
import 'package:habit_tracker/Screens/Calendar/calendar_page.dart';
import 'package:habit_tracker/Screens/Progress/progress_page.dart';
import 'package:habit_tracker/Screens/Testing/simple_testing_page.dart';
import 'package:habit_tracker/Screens/Goals/goal_dialog.dart';
import 'package:habit_tracker/main.dart';
import '../Queue/queue_page.dart';
import 'package:flutter/foundation.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String title = "Queue";
  DateTime preBackPress = DateTime.now();
  final GlobalKey _parentKey = GlobalKey();
  final scaffoldKey = GlobalKey<ScaffoldState>();
  int currentIndex = 0;
  late Widget cWidget;

  // Search functionality
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final SearchStateManager _searchManager = SearchStateManager();

  @override
  void initState() {
    super.initState();
    cWidget = const QueuePage();
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

    // Check for goal onboarding after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkGoalOnboarding();
    });
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    _searchController.dispose();
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
            title: _isSearchMode
                ? TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: const InputDecoration(
                      hintText: 'Search...',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) {
                      _searchManager.updateQuery(value);
                    },
                    autofocus: true,
                  )
                : Text(
                    title,
                    style: FlutterFlowTheme.of(context).headlineMedium.override(
                          fontFamily: 'Outfit',
                          color: Colors.white,
                          fontSize: 22,
                        ),
                  ),
            actions: [
              // Search button - toggle search mode
              IconButton(
                icon: Icon(
                  _isSearchMode ? Icons.close : Icons.search,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    if (_isSearchMode) {
                      _isSearchMode = false;
                      _searchController.clear();
                      _searchManager.clearQuery();
                    } else {
                      _isSearchMode = true;
                    }
                  });
                },
                tooltip: _isSearchMode ? 'Close search' : 'Search',
              ),
              // Goals button - always visible
              IconButton(
                icon: const Icon(Icons.flag, color: Colors.white),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const GoalDialog(),
                  );
                },
                tooltip: 'Goals',
              ),
              Visibility(
                visible: title == "Tasks",
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.sort, color: Colors.white),
                  onSelected: (value) {},
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
                                    currentIndex = 0;
                                    loadPage("Queue");
                                    Navigator.pop(context);
                                  });
                                },
                              ),
                              _DrawerItem(
                                icon: Icons.repeat,
                                label: 'Habits',
                                onTap: () {
                                  loadPage("Habits");
                                  Navigator.pop(context);
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
                              _DrawerItem(
                                icon: Icons.timer_outlined,
                                label: 'Timer',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const TimerPage(),
                                    ),
                                  );
                                },
                              ),
                              _DrawerItem(
                                icon: Icons.calendar_today,
                                label: 'Calendar',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const CalendarPage(),
                                    ),
                                  );
                                },
                              ),
                              // Development/Testing only - show in debug mode
                              if (kDebugMode) ...[
                                _DrawerItem(
                                  icon: Icons.science,
                                  label: 'Testing Tools',
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const SimpleTestingPage(),
                                      ),
                                    );
                                  },
                                ),
                              ],
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
                  visible: title != "Tasks" &&
                      title != "Manage Categories" &&
                      title != "Queue",
                  child: Positioned(
                    right: 16,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FloatingActionButton(
                          heroTag: 'fab_add_habit',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const createActivityPage(),
                              ),
                            ).then((value) {
                              if (value) {
                                NotificationCenter.post("loadHabits", "");
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
                          backgroundColor:
                              FlutterFlowTheme.of(context).secondary,
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
                    loadPage("Queue");
                  } else if (i == 1) {
                    loadPage("Tasks");
                  } else if (i == 2) {
                    loadPage("Habits");
                  } else if (i == 3) {
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
              items: [
                BottomNavigationBarItem(
                  icon: Icon(Icons.queue),
                  label: 'Queue',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.assignment),
                  label: 'Tasks',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.flag),
                  label: 'Habits',
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
    if (title == "Queue") {
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
        title = "Queue";
        setState(() {
          cWidget = const QueuePage();
        });
      }
      return false;
    }
  }

  void loadPage(s) {
    if (mounted) {
      setState(() {
        // Clear search when switching pages
        if (_isSearchMode) {
          _isSearchMode = false;
          _searchController.clear();
          _searchManager.clearQuery();
        }

        if (s == "Queue") {
          title = s;
          cWidget = const QueuePage();
        }
        if (s == "Tasks") {
          title = s;
          cWidget = const TaskTab();
        }
        if (s == "Habits") {
          title = s;
          cWidget = const HabitsPage(showCompleted: true);
        }
        if (s == "Progress") {
          title = s;
          cWidget = const ProgressPage();
        }
        if (s == "Manage Categories") {
          title = s;
          cWidget = const ManageCategories();
        }
        if (s == "Sequences") {
          title = s;
          cWidget = const Sequences();
        }
      });
    }
  }

  void _showAddCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setLocalState) =>
              const CreateCategory(categoryType: 'habit')),
    );
  }

  Future<void> _checkGoalOnboarding() async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }

      final shouldShow = await GoalService.shouldShowOnboardingGoal(userId);
      if (shouldShow && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const GoalOnboardingDialog(),
        );
      }
    } catch (e) {
      print('Home: Error checking goal onboarding: $e');
    }
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
