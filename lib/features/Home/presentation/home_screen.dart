import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:habit_tracker/services/login_response.dart';
import 'package:habit_tracker/core/constants.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/features/Goals/goal_data_service.dart';
import 'package:habit_tracker/features/Goals/goal_onboarding_dialog.dart';
import 'package:habit_tracker/features/Home/presentation/widgets/home_app_bar.dart';
import 'package:habit_tracker/features/Home/presentation/widgets/home_bottom_navigation_bar.dart';
import 'package:habit_tracker/features/Home/presentation/widgets/app_drawer.dart';
import 'package:habit_tracker/features/Categories/Manage%20Category/manage_categories.dart';
import 'package:habit_tracker/features/Essential/essential_templates_page_main.dart';
import 'package:habit_tracker/features/Routine/Routine%20Main%20page/routines_page_main.dart';
import 'package:habit_tracker/features/Task/task_tab.dart';
import 'package:habit_tracker/features/Habits/presentation/habits_page.dart';
import 'package:habit_tracker/features/Calendar/calendar_page_main.dart';
import 'package:habit_tracker/features/Progress/Pages/progress_page.dart';
import 'package:habit_tracker/features/Goals/goal_dialog.dart';
import 'package:habit_tracker/features/Home/CatchUp/presentation/morning_catchup_dialog.dart';
import 'package:habit_tracker/features/Home/CatchUp/logic/morning_catchup_service.dart';
import 'package:habit_tracker/core/utils/Date_time/ist_day_boundary_service.dart';
import 'package:habit_tracker/features/Settings/notification_onboarding_dialog.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/notification_preferences_service.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/notification_service.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/Engagement%20Notifications/daily_notification_scheduler.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/Engagement%20Notifications/engagement_reminder_scheduler.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/reminder_scheduler.dart';
import 'package:habit_tracker/features/Routine/routine_reminder_scheduler.dart';
import 'package:habit_tracker/main.dart';
import '../../Queue/queue_page.dart';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/auth/logout_cleanup.dart';
import 'package:habit_tracker/features/Timer/global_floating_timer.dart';
import 'package:habit_tracker/features/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';
import 'package:habit_tracker/services/resource_tracker.dart';

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
  final Set<int> _initializedPageIndexes = {2};
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
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
      _catchUpPendingSnackbar;
  @override
  void initState() {
    // CRITICAL: Reset observers on hot reload BEFORE widgets start adding new ones
    // Home creates all page widgets, so this is the best place to detect hot reload
    final observerCountBefore = NotificationCenter.observerCount();
    if (observerCountBefore > 6) {
      // More than just FirestoreCacheService observers - likely a hot reload
      // Reset all observers to prevent accumulation from previous hot reloads
      NotificationCenter.reset();
      FirestoreCacheService.resetListenersSetup();
      ResourceTracker.reset();
    }
    NotificationCenter.addObserver(
        this, 'navigateBottomTab', _onNavigateBottomTab);
    super.initState();
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
      NotificationService.processPendingNotificationResponses();
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
  void reassemble() {
    super.reassemble();
    // Clean up observers on hot reload to prevent accumulation
    NotificationCenter.removeObserver(this);
    NotificationCenter.addObserver(
        this, 'navigateBottomTab', _onNavigateBottomTab);
  }

  @override
  void dispose() {
    _dayTransitionTimer?.cancel();
    _clearCatchUpPendingSnackbar();
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
            onLogout: () async {
              await performLogout(
                sharedPref: sharedPref,
                onLoggedOut: () async {
                  users = LoginResponse();
                  if (!context.mounted) return;
                  Navigator.pushReplacementNamed(context, login);
                },
              );
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
                    children: _buildIndexedStackChildren(),
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
          _initializedPageIndexes.add(currentIndex);
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

  List<Widget> _buildIndexedStackChildren() {
    return List<Widget>.generate(_pageIndexMap.length, (index) {
      if (!_initializedPageIndexes.contains(index)) {
        return const SizedBox.shrink();
      }
      return _buildPageForIndex(index);
    });
  }

  Widget _buildPageForIndex(int index) {
    switch (index) {
      case 0:
        return const TaskTab();
      case 1:
        return const HabitsPage(showCompleted: true);
      case 2:
        return const QueuePage();
      case 3:
        return const essentialTemplatesPage();
      case 4:
        return const Routines();
      case 5:
        return const CalendarPage();
      default:
        return const SizedBox.shrink();
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
    final nextCheck = IstDayBoundaryService.nextIst005();
    final delayMs = nextCheck.millisecondsSinceEpoch -
        DateTime.now().millisecondsSinceEpoch;
    final delay = Duration(milliseconds: delayMs > 0 ? delayMs : 0);
    _dayTransitionTimer = Timer(delay, _handleDayTransitionWhileOpen);
  }

  Future<void> _handleDayTransitionWhileOpen() async {
    await _runDayEndFlow(showDayTransitionInfo: true);
    _scheduleDayTransitionTimer();
  }

  Future<void> _checkMorningCatchUp() async {
    // Cloud-first day transition starts only after 00:05 IST.
    if (!IstDayBoundaryService.hasReachedIst005()) {
      return;
    }

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

      final targetDateIst = IstDayBoundaryService.yesterdayStartIst();
      var alreadyProcessedInCloud =
          await MorningCatchUpService.isDayTransitionProcessedInCloud(
        userId: userId,
        targetDateIst: targetDateIst,
      );
      bool ranFallback = false;

      if (!alreadyProcessedInCloud) {
        try {
          await MorningCatchUpService.runDayTransitionForUser(
            userId: userId,
            targetDate: targetDateIst,
          );
          ranFallback = true;
          alreadyProcessedInCloud =
              await MorningCatchUpService.isDayTransitionProcessedInCloud(
            userId: userId,
            targetDateIst: targetDateIst,
          );
        } catch (e) {
          if (kDebugMode) {
            print('Cloud fallback day transition failed: $e');
          }
        }
      }

      final launchState =
          await MorningCatchUpService.getCatchUpLaunchState(userId);

      if (launchState.shouldAutoResolveAfterCap) {
        try {
          await MorningCatchUpService.autoResolveAfterReminderCap(
            userId: userId,
            targetDate: targetDateIst,
            baselineProcessedAtOpen: alreadyProcessedInCloud,
          );
          final hadPendingToasts = MorningCatchUpService.hasPendingToasts();
          MorningCatchUpService.showPendingToasts();
          if (hadPendingToasts) {
            await MorningCatchUpService.markFinalizationToastsShownForDate(
              targetDateIst,
              userId: userId,
            );
          }
          _clearCatchUpPendingSnackbar();
          NotificationCenter.post('loadHabits', null);
          NotificationCenter.post('loadData', null);
          return;
        } catch (e) {
          if (kDebugMode) {
            print('Catch-up auto resolve after reminder cap failed: $e');
          }
        }
      }

      if (launchState.shouldShow && mounted) {
        final result = await showDialog<MorningCatchUpDialogResult>(
          context: context,
          barrierDismissible: false,
          builder: (context) => MorningCatchUpDialog(
            isDayTransition: showDayTransitionInfo,
            initialItems: launchState.items,
            baselineProcessedAtOpen: alreadyProcessedInCloud,
          ),
        );

        if (!mounted) return;
        if (result == MorningCatchUpDialogResult.snoozed) {
          _showCatchUpPendingSnackbar();
        } else {
          _clearCatchUpPendingSnackbar();
        }
      } else {
        if (alreadyProcessedInCloud || ranFallback) {
          await MorningCatchUpService.showFinalizationToastsIfNeeded(
            userId: userId,
            targetDate: targetDateIst,
          );
        }
        if (ranFallback) {
          // Refresh Queue/Progress views for the new day
          NotificationCenter.post('loadHabits', null);
          NotificationCenter.post('loadData', null);
        }
      }
    } catch (e) {
      // Error running day-end flow
    } finally {
      _isCheckingCatchUp = false;
    }
  }

  void _showCatchUpPendingSnackbar() {
    if (!mounted) return;
    _clearCatchUpPendingSnackbar();
    _catchUpPendingSnackbar = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        content: const Text(
          'Catch-up is pending. Some instances/status may be outdated. Complete catch-up for accurate scores and latest instance visibility.',
        ),
        action: SnackBarAction(
          label: 'Open catch-up',
          onPressed: () {
            _clearCatchUpPendingSnackbar();
            unawaited(_runDayEndFlow(showDayTransitionInfo: false));
          },
        ),
      ),
    );
  }

  void _clearCatchUpPendingSnackbar() {
    _catchUpPendingSnackbar?.close();
    _catchUpPendingSnackbar = null;
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
      // Reset stale schedules so all reminders are rebuilt with current timezone rules.
      await NotificationService.cancelAllNotifications();
      // Initialize daily notifications
      await DailyNotificationScheduler.initializeDailyNotifications();
      // Initialize engagement reminders
      await EngagementReminderScheduler.initializeEngagementReminders();
      // Schedule all pending task/habit reminders (after user is authenticated)
      await ReminderScheduler.scheduleAllPendingReminders();
      // Schedule all active routine reminders
      await RoutineReminderScheduler.scheduleAllActiveRoutineReminders();
    } catch (e) {
      // Error initializing notifications
    }
  }
}
