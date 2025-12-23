import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:habit_tracker/Helper/Response/login_response.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/constants.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/backend/goal_service.dart';
import 'package:habit_tracker/Screens/Goals/goal_onboarding_dialog.dart';
import 'package:habit_tracker/Screens/Manage%20categories/manage_categories.dart';
import 'package:habit_tracker/Screens/NonProductive/non_productive_templates_page.dart';
import 'package:habit_tracker/Screens/Routine/routine.dart';
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
import 'package:habit_tracker/Screens/Settings/settings_page.dart';
import 'package:habit_tracker/Helper/backend/notification_preferences_service.dart';
import 'package:habit_tracker/Helper/utils/daily_notification_scheduler.dart';
import 'package:habit_tracker/Helper/utils/engagement_reminder_scheduler.dart';
import 'package:habit_tracker/Helper/backend/reminder_scheduler.dart';
import 'package:habit_tracker/Helper/backend/routine_reminder_scheduler.dart';
import 'package:habit_tracker/main.dart';
import '../Queue/queue_page.dart';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/global_floating_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // List of all pages - initialized once and cached
  late final List<Widget> _pages;
  // Map page names to indices for easy lookup
  final Map<String, int> _pageIndexMap = {
    "Tasks": 0,
    "Habits": 1,
    "Queue": 2,
    "Routines": 3,
    "Timer": 4,
    "Calendar": 5,
  };
  // Prevent race conditions in morning catch-up check
  static bool _isCheckingCatchUp = false;
  @override
  void initState() {
    super.initState();
    // Initialize all pages once - they will be cached in IndexedStack
    _pages = [
      const TaskTab(), // index 0
      const HabitsPage(showCompleted: true), // index 1
      const QueuePage(), // index 2
      const Routines(), // index 3
      const TimerPage(), // index 4
      const CalendarPage(), // index 5
    ];
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
    // Parallelize independent operations for faster initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Run independent operations in parallel
      Future.wait([
        _checkMorningCatchUp(),
        _checkGoalOnboarding(),
        _checkDailyGoal(),
        _initializeNotifications(),
      ]).then((_) {
        // Check notification onboarding after goal onboarding completes
        // (it depends on goal onboarding being completed)
        // Only proceed if widget is still mounted to prevent disposed widget errors
        if (mounted) {
          _checkNotificationOnboarding();
        }
      });
    });
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
              // Catch-up button - always visible
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton(
                  icon: const Icon(Icons.history, color: Colors.white),
                  onPressed: showCatchUpDialogManually,
                  tooltip: 'Morning Catch-Up',
                ),
              ),
              // Goals button - always visible
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const GoalDialog(),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      'Goal',
                      style: FlutterFlowTheme.of(context).bodyLarge.override(
                            fontFamily: 'Outfit',
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ),
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
                        leading: const Icon(Icons.sort_by_alpha),
                        title: const Text('Default sort'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'importance',
                      child: ListTile(
                        leading: const Icon(Icons.star),
                        title: const Text('Sort by importance'),
                      ),
                    ),
                  ],
                ),
              ),
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
                                currentUserEmail.isNotEmpty
                                    ? currentUserEmail
                                    : "email",
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
                                  loadPage("Queue");
                                  Navigator.pop(context);
                                },
                              ),
                              _DrawerItem(
                                icon: Icons.category,
                                label: 'Manage Categories',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const ManageCategories(),
                                    ),
                                  );
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
                              _DrawerItem(
                                icon: Icons.trending_up,
                                label: 'Progress History',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const ProgressPage(),
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
                                icon: Icons.settings,
                                label: 'Settings',
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const SettingsPage(),
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
                Container(
                  color: Colors.white,
                  child: IndexedStack(
                    index: currentIndex,
                    children: _pages,
                  ),
                ),
                // Global floating timer - appears on all pages when timers are active
                const GlobalFloatingTimer(),
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
                // Map index to page name and load it
                final pageNames = [
                  "Tasks",
                  "Habits",
                  "Queue",
                  "Routines",
                  "Timer",
                  "Calendar"
                ];
                if (i >= 0 && i < pageNames.length) {
                  loadPage(pageNames[i]);
                }
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: FlutterFlowTheme.of(context).secondaryBackground,
              selectedItemColor: FlutterFlowTheme.of(context).primary,
              unselectedItemColor: FlutterFlowTheme.of(context).secondaryText,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.assignment),
                  label: 'Tasks',
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.flag),
                  label: 'Habits',
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.queue),
                  label: 'Queue',
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.playlist_play),
                  label: 'Routines',
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
          content: const Text('Press Back button again to Exit'),
          duration: Duration(seconds: 2),
        );
        ScaffoldMessenger.of(context).showSnackBar(snack);
        return false;
      } else {
        return true;
      }
    } else {
      if (mounted) {
        setState(() {
          currentIndex = 2; // Queue page index
          title = "Queue";
        });
      }
      return false;
    }
  }

  void loadPage(s) {
    if (mounted) {
      setState(() {
        // Check if this is a main navigation page (in bottom nav)
        if (_pageIndexMap.containsKey(s)) {
          currentIndex = _pageIndexMap[s]!;
          title = s;
        } else {
          // Handle pages not in bottom navigation (Progress, Manage Categories)
          // These will be shown as overlays or separate routes
          title = s;
          if (s == "Progress") {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ProgressPage(),
              ),
            );
            return;
          }
          if (s == "Manage Categories") {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ManageCategories(),
              ),
            );
            return;
          }
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
    } catch (e) {
      // Silently ignore errors in goal onboarding check - non-critical UI operation
      print('Error checking goal onboarding: $e');
    }
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
    } catch (e) {
      // Silently ignore errors in daily goal check - non-critical UI operation
      print('Error checking daily goal: $e');
    }
  }

  Future<void> _checkMorningCatchUp() async {
    if (_isCheckingCatchUp) return; // Prevent concurrent checks

    try {
      _isCheckingCatchUp = true;
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }
      
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // Check if we need to process end-of-day activities
      // This should run after midnight (12 AM) when a new day starts
      final prefs = await SharedPreferences.getInstance();
      final lastProcessedDateString = prefs.getString('last_end_of_day_processed');
      DateTime? lastProcessedDate;
      if (lastProcessedDateString != null) {
        lastProcessedDate = DateTime.parse(lastProcessedDateString);
        final lastProcessedDateOnly = DateTime(
          lastProcessedDate.year,
          lastProcessedDate.month,
          lastProcessedDate.day,
        );
        
        // If we've already processed today, skip
        if (lastProcessedDateOnly.isAtSameMomentAs(today)) {
          // Already processed today - just check if dialog should show
          final shouldShow = await MorningCatchUpService.shouldShowDialog(userId);
          if (shouldShow && mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const MorningCatchUpDialog(),
            );
          }
          return;
        }
      }
      
      // It's a new day (or first time) - process end-of-day activities
      // This runs even if there are no pending items
      await MorningCatchUpService.processEndOfDayActivities(userId);
      
      // Mark as processed for today
      await prefs.setString('last_end_of_day_processed', today.toIso8601String());
      
      // Now check if dialog should show (for pending items)
      final shouldShow = await MorningCatchUpService.shouldShowDialog(userId);
      if (shouldShow && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const MorningCatchUpDialog(),
        );
      }
    } catch (e) {
      // Error checking morning catch-up
    } finally {
      _isCheckingCatchUp = false;
    }
  }

  /// Manually trigger the catch-up dialog (for testing/debugging)
  /// Call this method from Flutter DevTools console or add a button that calls it
  Future<void> showCatchUpDialogManually() async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        // No user ID available
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
      // Error showing catch-up dialog manually
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
      // Error checking notification onboarding
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
      // Schedule all active routine reminders
      await RoutineReminderScheduler.scheduleAllActiveRoutineReminders();
      // Check for expired snoozes and reschedule
      await ReminderScheduler.checkExpiredSnoozes();
    } catch (e) {
      // Error initializing notifications
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
