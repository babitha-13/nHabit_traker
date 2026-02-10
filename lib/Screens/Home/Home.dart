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
import 'package:habit_tracker/Screens/Categories/Manage%20Category/manage_categories.dart';
import 'package:habit_tracker/Screens/Essential/essential_templates_page_main.dart';
import 'package:habit_tracker/Screens/Routine/Routine%20Main%20page/routines_page_main.dart';
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
import 'package:habit_tracker/Helper/auth/logout_cleanup.dart';
import 'package:habit_tracker/Screens/Timer/global_floating_timer.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';
import 'package:habit_tracker/Helper/Helpers/resource_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:habit_tracker/Helper/backend/schema/users_record.dart';
import 'package:habit_tracker/Helper/backend/schema/user_progress_stats_record.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';

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
        _storeUserTimezone(),
        _checkMorningCatchUp(),
        _checkOnboardingDialogs(), // Combined goal + notification onboarding
        _checkDailyGoal(),
        _initializeNotifications(),
        _preWarmCache(), // Pre-warm templates and categories cache for faster page loads
      ]);
    });
    _scheduleDayTransitionTimer();
  }

  /// Store user's timezone offset in their profile
  /// Called on app open to keep timezone up-to-date (handles timezone changes when traveling)
  Future<void> _storeUserTimezone() async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }

      // Get device timezone offset in hours from UTC
      final now = DateTime.now();
      final timezoneOffset = now.timeZoneOffset.inHours +
          (now.timeZoneOffset.inMinutes % 60) / 60.0;

      // Get current user document
      final userRef = UsersRecord.collection.doc(userId);
      final userDoc = await userRef.get();

      if (userDoc.exists) {
        final currentUser = UsersRecord.fromSnapshot(userDoc);
        // Only update if timezone has changed (to avoid unnecessary writes)
        if ((currentUser.timezoneOffset ?? 0) != timezoneOffset) {
          await userRef.update({
            'timezone_offset': timezoneOffset,
          });
        }
      }
    } catch (e) {
      // Silent error - timezone update is not critical
      print('Error storing user timezone: $e');
    }
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

  /// Check both goal and notification onboarding dialogs
  /// Queries user document once and handles both sequentially
  Future<void> _checkOnboardingDialogs() async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }

      // Query user document once
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        return;
      }
      final userData = UsersRecord.fromSnapshot(userDoc);

      // Check goal onboarding first
      final goalOnboardingCompleted = userData.goalOnboardingCompleted;
      final shouldShowGoalOnboarding = !userData.goalPromptSkipped &&
          !goalOnboardingCompleted &&
          userData.currentGoalId.isEmpty;

      if (shouldShowGoalOnboarding && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const GoalOnboardingDialog(),
        );
        return; // Don't show notification onboarding until goal onboarding is done
      }

      // Only check notification onboarding if goal onboarding is completed
      if (goalOnboardingCompleted && mounted) {
        final isNotificationOnboardingCompleted =
            await NotificationPreferencesService
                .isNotificationOnboardingCompleted(userId);
        if (!isNotificationOnboardingCompleted) {
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
      }
    } catch (e) {
      print('Error checking onboarding dialogs: $e');
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
        // Check if we need to wait for cloud function or run as fallback
        final shouldRunProcessing =
            await _shouldRunDayEndProcessing(userId, now);

        if (shouldRunProcessing) {
          // Run UI processing as fallback (cloud function hasn't processed yet)
          await MorningCatchUpService.runInstanceMaintenanceForDayTransition(
              userId);

          // Check if there are missed days before deciding whether to await
          final hasMissed =
              await MorningCatchUpService.hasMissedDays(userId: userId);

          if (hasMissed) {
            // Await missed days persistence to ensure graphs have complete data
            await MorningCatchUpService.persistScoresForMissedDaysIfNeeded(
                userId: userId);
          } else {
            // No missed days - run in background for performance
            unawaited(MorningCatchUpService.persistScoresForMissedDaysIfNeeded(
                userId: userId));
          }

          // Persist yesterday's score (always await to ensure it's ready)
          await MorningCatchUpService.persistScoresForDate(
            userId: userId,
            targetDate: DateService.yesterdayStart,
          );

          await prefs.setString(
              'last_end_of_day_processed', today.toIso8601String());
        } else {
          // Cloud function already processed - just update SharedPreferences
          await prefs.setString(
              'last_end_of_day_processed', today.toIso8601String());
        }
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

  /// Check if UI should run day-end processing as fallback
  /// Returns true if cloud function hasn't processed yet (after 5-minute wait)
  /// Returns false if cloud function already processed or before midnight
  Future<bool> _shouldRunDayEndProcessing(String userId, DateTime now) async {
    try {
      // Calculate midnight in user's local timezone
      final localMidnight = DateTime(now.year, now.month, now.day);
      final timeSinceMidnight = now.difference(localMidnight);

      // If before midnight, no processing needed
      if (timeSinceMidnight.isNegative) {
        return false;
      }

      // If less than 5 minutes since midnight, wait for cloud function
      if (timeSinceMidnight.inMinutes < 5) {
        // Wait until 5 minutes have passed
        final waitDuration = Duration(minutes: 5) - timeSinceMidnight;
        await Future.delayed(waitDuration);
        // After waiting, check cloud function status (don't recurse to avoid re-waiting)
        final cloudFunctionProcessed =
            await _checkCloudFunctionExecutionStatus(userId);
        return !cloudFunctionProcessed; // Return true if not processed (should run UI)
      }

      // After 5 minutes, check if cloud function already processed
      final cloudFunctionProcessed =
          await _checkCloudFunctionExecutionStatus(userId);

      if (cloudFunctionProcessed) {
        // Cloud function already processed - don't run UI processing
        return false;
      }

      // Cloud function hasn't processed - run UI processing as fallback
      return true;
    } catch (e) {
      // On error, run UI processing as fallback to ensure processing happens
      print('Error checking cloud function status: $e');
      return true;
    }
  }

  /// Check if cloud function has already processed yesterday's day-end
  /// Returns true if lastProcessedDate matches yesterday, false otherwise
  Future<bool> _checkCloudFunctionExecutionStatus(String userId) async {
    try {
      final yesterday = DateService.yesterdayStart;

      // Get user progress stats
      final statsRef =
          UserProgressStatsRecord.collectionForUser(userId).doc('main');
      final statsDoc = await statsRef.get();

      if (!statsDoc.exists) {
        // No stats document - cloud function hasn't processed
        return false;
      }

      final stats = UserProgressStatsRecord.fromSnapshot(statsDoc);

      if (!stats.hasLastProcessedDate()) {
        // No lastProcessedDate - cloud function hasn't processed
        return false;
      }

      final lastProcessedDate = stats.lastProcessedDate!;
      final lastProcessedDateOnly = DateTime(
        lastProcessedDate.year,
        lastProcessedDate.month,
        lastProcessedDate.day,
      );

      // Check if lastProcessedDate matches yesterday
      return lastProcessedDateOnly.isAtSameMomentAs(yesterday);
    } catch (e) {
      // On error, assume cloud function hasn't processed
      print('Error checking cloud function execution status: $e');
      return false;
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

  /// Pre-warm cache with templates and categories during app startup
  /// This reduces redundant queries when pages load, improving performance
  Future<void> _preWarmCache() async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }

      final cache = FirestoreCacheService();

      // Fetch templates and categories in parallel
      final results = await Future.wait([
        queryActivitiesRecordOnce(userId: userId, includeEssentialItems: true),
        queryCategoriesRecordOnce(userId: userId),
      ]);

      final templates = results[0] as List<ActivityRecord>;
      final categories = results[1] as List<CategoryRecord>;

      // Cache all templates at once
      final templatesMap = <String, ActivityRecord>{};
      for (final template in templates) {
        templatesMap[template.reference.id] = template;
      }
      cache.cacheTemplates(templatesMap);

      // Cache categories (split by type for efficient access)
      final habitCategories = categories
          .where((c) => c.categoryType == 'habit')
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      final taskCategories = categories
          .where((c) => c.categoryType == 'task')
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      cache.cacheHabitCategories(habitCategories);
      cache.cacheTaskCategories(taskCategories);
    } catch (e) {
      // Silent error - cache pre-warming is non-critical
      // Pages will fetch data on-demand if cache fails
      print('Error pre-warming cache: $e');
    }
  }
}
