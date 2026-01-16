import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:habit_tracker/Helper/Helpers/login_response.dart';
import 'package:habit_tracker/Helper/Helpers/constants.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Screens/Goals/goal_data_service.dart';
import 'package:habit_tracker/Screens/Goals/goal_onboarding_dialog.dart';
import 'package:habit_tracker/Screens/Home/home_app_bar.dart';
import 'package:habit_tracker/Screens/Home/home_bottom_navigation_bar.dart';
import 'package:habit_tracker/Screens/Home/app_drawer.dart';
import 'package:habit_tracker/Screens/Categories/manage_categories.dart';
import 'package:habit_tracker/Screens/Essential/essential_templates_page_main.dart';
import 'package:habit_tracker/Screens/Routine/routines_page_main.dart';
import 'package:habit_tracker/Screens/Task/task_tab.dart';
import 'package:habit_tracker/Screens/Habits/habits_page.dart';
import 'package:habit_tracker/Screens/Calendar/calendar_page_main.dart';
import 'package:habit_tracker/Screens/Progress/Pages/progress_page.dart';
import 'package:habit_tracker/Screens/Goals/goal_dialog.dart';
import 'package:habit_tracker/Screens/CatchUp/morning_catchup_dialog_UI.dart';
import 'package:habit_tracker/Screens/CatchUp/morning_catchup_service.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Screens/Settings/notification_onboarding_dialog.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/notification_preferences_service.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/Engagement%20Notifications/daily_notification_scheduler.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/Engagement%20Notifications/engagement_reminder_scheduler.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/reminder_scheduler.dart';
import 'package:habit_tracker/Screens/Routine/routine_reminder_scheduler.dart';
import 'package:habit_tracker/main.dart';
import '../Queue/queue_page.dart';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Screens/Timer/global_floating_timer.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_state_manager.dart';
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
  late final List<Widget> _pages;
  final Map<String, int> _pageIndexMap = {
    "Tasks": 0,
    "Habits": 1,
    "Queue": 2,
    "Essential": 3,
    "Routines": 4,
    "Calendar": 5,
  };
  static bool _isCheckingCatchUp = false;
  Timer? _dayTransitionTimer;
  @override
  void initState() {
    NotificationCenter.addObserver(
        this, 'navigateBottomTab', _onNavigateBottomTab);
    super.initState();
    _pages = [
      const TaskTab(), // index 0
      const HabitsPage(showCompleted: true), // index 1
      const QueuePage(), // index 2
      const essentialTemplatesPage(), // index 3
      const Routines(), // index 4
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.wait([
        _checkMorningCatchUp(),
        _checkGoalOnboarding(),
        _checkDailyGoal(),
        _initializeNotifications(),
      ]).then((_) {
        if (mounted) {
          _checkNotificationOnboarding();
        }
      });
    });
    _scheduleDayTransitionTimer();
  }

  void _onNavigateBottomTab(Object? param) {
    if (param is String) {
      loadPage(param);
    }
  }

  @override
  void dispose() {
    _dayTransitionTimer?.cancel();
    NotificationCenter.removeObserver(this, 'navigateBottomTab');
    NotificationCenter.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Container(
        color: Colors.white,
        child: Scaffold(
          key: scaffoldKey,
          appBar: HomeAppBar(
            title: title,
            scaffoldKey: scaffoldKey,
          ),
          drawer: AppDrawer(
            currentUserEmail: currentUserEmail,
            loadPage: loadPage,
            onLogout: () {
              sharedPref.remove(SharedPreference.name.sUserDetails).then((_) {
                users = LoginResponse();
                Navigator.pushReplacementNamed(context, login);
              });
            },
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
                const GlobalFloatingTimer(),
              ],
            ),
          ),
          bottomNavigationBar: AppBottomNavigationBar(
            currentIndex: currentIndex,
            loadPage: loadPage,
          ),
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (SearchStateManager().isSearchOpen) {
      NotificationCenter.post('closeSearch', null);
      return false;
    }
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
        if (_pageIndexMap.containsKey(s)) {
          currentIndex = _pageIndexMap[s]!;
          title = s;
        } else {
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
      print('Error checking daily goal: $e');
    }
  }

  void _scheduleDayTransitionTimer() {
    _dayTransitionTimer?.cancel();
    final now = DateTime.now();
    final nextCheck = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1, minutes: 1));
    final delay = nextCheck.difference(now);
    _dayTransitionTimer = Timer(delay, _handleDayTransitionWhileOpen);
  }

  Future<void> _handleDayTransitionWhileOpen() async {
    await _runDayEndFlow(showDayTransitionInfo: true);
    _scheduleDayTransitionTimer();
  }

  Future<void> _checkMorningCatchUp() async {
    await _runDayEndFlow(showDayTransitionInfo: false);
  }

  Future<void> _runDayEndFlow({required bool showDayTransitionInfo}) async {
    if (_isCheckingCatchUp) return;

    try {
      _isCheckingCatchUp = true;
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final prefs = await SharedPreferences.getInstance();
      final lastProcessedDateString =
          prefs.getString('last_end_of_day_processed');
      DateTime? lastProcessedDate;
      bool alreadyProcessedToday = false;
      if (lastProcessedDateString != null) {
        lastProcessedDate = DateTime.parse(lastProcessedDateString);
        final lastProcessedDateOnly = DateTime(
          lastProcessedDate.year,
          lastProcessedDate.month,
          lastProcessedDate.day,
        );
        alreadyProcessedToday = lastProcessedDateOnly.isAtSameMomentAs(today);
      }

      // Check if dialog should be shown before processing
      final shouldShow = await MorningCatchUpService.shouldShowDialog(userId);

      if (!alreadyProcessedToday) {
        await MorningCatchUpService.runInstanceMaintenanceForDayTransition(
            userId);

        // Persist scores in background (non-blocking)
        // Suppress toasts if catch-up dialog will be shown (toasts will show after dialog closes)
        unawaited(MorningCatchUpService.persistScoresForMissedDaysIfNeeded(
            userId: userId));
        unawaited(MorningCatchUpService.persistScoresForDate(
          userId: userId,
          targetDate: DateService.yesterdayStart,
          suppressToasts: shouldShow, // Suppress toasts if dialog will be shown
        ));

        await prefs.setString(
            'last_end_of_day_processed', today.toIso8601String());
      }

      if (shouldShow && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => MorningCatchUpDialog(
            isDayTransition: showDayTransitionInfo,
          ),
        );
      } else if (!alreadyProcessedToday) {
        // Refresh Queue/Progress views for the new day
        NotificationCenter.post('loadHabits', null);
        NotificationCenter.post('loadData', null);
      }
    } catch (e) {
      // Error running day-end flow
    } finally {
      _isCheckingCatchUp = false;
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
