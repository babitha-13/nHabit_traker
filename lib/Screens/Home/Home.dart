import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:habit_tracker/Helper/Response/login_response.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/constants.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Helper/backend/goal_service.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Screens/Goals/goal_onboarding_dialog.dart';
import 'package:habit_tracker/Screens/Manage%20categories/manage_categories.dart';
import 'package:habit_tracker/Screens/NonProductive/non_productive_templates_page.dart';
import 'package:habit_tracker/Screens/Sequence/sequence.dart';
import 'package:habit_tracker/Screens/Task/task_tab.dart';
import 'package:habit_tracker/Screens/Habits/habits_page.dart';
import 'package:habit_tracker/Screens/Timer/timer_page.dart';
import 'package:habit_tracker/Screens/Calendar/calendar_page.dart';
import 'package:habit_tracker/Screens/Progress/progress_page.dart';
import 'package:habit_tracker/Screens/Testing/simple_testing_page.dart';
import 'package:habit_tracker/Screens/Goals/goal_dialog.dart';
import 'package:habit_tracker/Screens/CatchUp/morning_catchup_dialog.dart';
import 'package:habit_tracker/Helper/backend/morning_catchup_service.dart';
import 'package:habit_tracker/Screens/Onboarding/notification_onboarding_dialog.dart';
import 'package:habit_tracker/Screens/Settings/notification_settings_page.dart';
import 'package:habit_tracker/Helper/backend/notification_preferences_service.dart';
import 'package:habit_tracker/Helper/utils/daily_notification_scheduler.dart';
import 'package:habit_tracker/Helper/utils/engagement_reminder_scheduler.dart';
import 'package:habit_tracker/Helper/backend/reminder_scheduler.dart';
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
  int currentIndex = 2;
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
    // Check for goal onboarding and morning catch-up after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkMorningCatchUp();
      _checkGoalOnboarding();
      _checkDailyGoal();
      _checkNotificationOnboarding();
      _initializeNotifications();
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
                icon: const Icon(Icons.gps_fixed, color: Colors.white),
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
              ),
              Visibility(
                visible: title == "Habits",
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) => _handleHabitsMenuAction(value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'clear_test_data',
                      child: ListTile(
                        leading: Icon(Icons.refresh, color: Colors.orange),
                        title: Text('Clear Test Data'),
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
                                    currentIndex = 2;
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
                                icon: Icons.access_time,
                                label: 'Non-Productive Items',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const NonProductiveTemplatesPage(),
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
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const NotificationSettingsPage(),
                                    ),
                                  );
                                },
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
              ],
            ),
          ),
          // DEBUG: FAB for testing catch-up dialog (remove after testing)
          floatingActionButton: FloatingActionButton(
            onPressed: showCatchUpDialogManually,
            backgroundColor: FlutterFlowTheme.of(context).primary,
            child: const Icon(Icons.history, color: Colors.white),
            tooltip: 'Test Catch-Up Dialog',
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
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
                    loadPage("Habits");
                  } else if (i == 2) {
                    loadPage("Queue");
                  } else if (i == 3) {
                    loadPage("Sequences");
                  } else if (i == 4) {
                    loadPage("Timer");
                  } else if (i == 5) {
                    loadPage("Calendar");
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
                  icon: Icon(Icons.playlist_play),
                  label: 'Sequences',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.timer),
                  label: 'Timer',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.calendar_today),
                  label: 'Calendar',
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
        if (s == "Timer") {
          title = s;
          cWidget = const TimerPage();
        }
        if (s == "Calendar") {
          title = s;
          cWidget = const CalendarPage();
        }
      });
    }
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
    } catch (e) {}
  }

  Future<void> _checkDailyGoal() async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }
      final shouldShow = await GoalService.shouldShowGoal(userId);
      if (shouldShow && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const GoalDialog(),
        );
      }
    } catch (e) {}
  }

  Future<void> _checkMorningCatchUp() async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }
      // Check if morning catch-up dialog should be shown
      // Now uses optimized batch writes to handle expired instances efficiently
      final shouldShow = await MorningCatchUpService.shouldShowDialog(userId);
      if (shouldShow && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const MorningCatchUpDialog(),
        );
      }
    } catch (e) {
      print('Error checking morning catch-up: $e');
    }
  }

  /// Manually trigger the catch-up dialog (for testing/debugging)
  /// Call this method from Flutter DevTools console or add a button that calls it
  Future<void> showCatchUpDialogManually() async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        print('No user ID available');
        return;
      }
      // First, auto-skip all expired items to bring everything up to date
      await MorningCatchUpService.autoSkipExpiredItemsBeforeYesterday(userId);
      // Reset dialog state to allow showing
      await MorningCatchUpService.resetDialogState();
      // Force show the dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const MorningCatchUpDialog(),
        );
      }
    } catch (e) {
      print('Error showing catch-up dialog manually: $e');
    }
  }

  Future<void> _checkNotificationOnboarding() async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }
      // Only show if goal onboarding is completed
      final goalOnboardingCompleted =
          await GoalService.isGoalOnboardingCompleted(userId);
      if (!goalOnboardingCompleted) {
        return; // Wait for goal onboarding first
      }
      final isCompleted = await NotificationPreferencesService
          .isNotificationOnboardingCompleted(userId);
      if (!isCompleted && mounted) {
        // Add a small delay to avoid showing multiple dialogs at once
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const NotificationOnboardingDialog(),
          );
        }
      }
    } catch (e) {
      print('Error checking notification onboarding: $e');
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }
      // Initialize daily notifications
      await DailyNotificationScheduler.initializeDailyNotifications();
      // Initialize engagement reminders
      await EngagementReminderScheduler.initializeEngagementReminders();
      // Schedule all pending task/habit reminders (after user is authenticated)
      await ReminderScheduler.scheduleAllPendingReminders();
      // Check for expired snoozes and reschedule
      await ReminderScheduler.checkExpiredSnoozes();
    } catch (e) {
      print('Error initializing notifications: $e');
    }
  }

  Future<void> _handleHabitsMenuAction(String value) async {
    if (value == 'clear_test_data') {
      final shouldClear = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear Test Data'),
          content: const Text(
            'This will delete ALL existing instances (completed, pending, skipped) and create fresh instances starting tomorrow. Your habit and task templates will be preserved.\n\nThis action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange,
              ),
              child: const Text('Clear All Data'),
            ),
          ],
        ),
      );

      if (shouldClear == true) {
        try {
          // Show loading indicator
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Text('Clearing test data...'),
                ],
              ),
            ),
          );

          // Call the reset service
          final result =
              await ActivityInstanceService.resetAllInstancesForFreshStart();

          // Close loading dialog
          Navigator.of(context).pop();

          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Test data cleared! ${result['createdInstances']} fresh instances created for ${(result['habitTemplates'] ?? 0) + (result['taskTemplates'] ?? 0)} templates.',
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );

            // Refresh the habits page
            NotificationCenter.post("loadHabits", "");
          }
        } catch (e) {
          // Close loading dialog if it's still open
          Navigator.of(context).pop();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error clearing test data: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
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
