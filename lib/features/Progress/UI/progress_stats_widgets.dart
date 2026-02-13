import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Progress/Statemanagement/today_progress_state.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/auth/logout_cleanup.dart';
import 'package:habit_tracker/core/services/local_storage_services.dart';
import 'package:habit_tracker/services/login_response.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/features/Testing/simple_testing_page.dart';
import 'package:habit_tracker/features/Habits/presentation/habits_page.dart';
import 'package:habit_tracker/features/Categories/Manage%20Category/manage_categories.dart';
import 'package:habit_tracker/features/Essential/essential_templates_page_main.dart';
import 'package:habit_tracker/features/Settings/notification_settings_page.dart';
import 'package:habit_tracker/core/constants.dart';
import 'package:flutter/foundation.dart';
import '../Logic/progress_page_logic.dart';
import 'progress_charts_builder.dart';

class ProgressStatsWidgets {
  static Widget buildSummaryCards({
    required BuildContext context,
    required ProgressPageLogic logic,
  }) {
    final last7Days = logic.getLastNDays(7);
    final last30Days = logic.getLastNDays(30);
    final avg7Day = logic.calculateAveragePercentage(last7Days);
    final avg30Day = logic.calculateAveragePercentage(last30Days);
    final avg7DayTarget = logic.calculateAverageTarget(last7Days);
    final avg7DayEarned = logic.calculateAverageEarned(last7Days);
    final avg30DayTarget = logic.calculateAverageTarget(last30Days);
    final avg30DayEarned = logic.calculateAverageEarned(last30Days);
    return Row(
      children: [
        Expanded(
          child: buildSummaryCard(
            context: context,
            title: '7-Day Avg',
            value: '${avg7Day.toStringAsFixed(0)}%',
            subtitle:
                '${avg7DayEarned.toStringAsFixed(0)}/${avg7DayTarget.toStringAsFixed(0)} pts',
            icon: Icons.trending_up,
            color: logic.getPerformanceColor(avg7Day),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: buildSummaryCard(
            context: context,
            title: '30-Day Avg',
            value: '${avg30Day.toStringAsFixed(0)}%',
            subtitle:
                '${avg30DayEarned.toStringAsFixed(0)}/${avg30DayTarget.toStringAsFixed(0)} pts',
            icon: Icons.calendar_month,
            color: logic.getPerformanceColor(avg30Day),
          ),
        ),
      ],
    );
  }

  static Widget buildSummaryCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: FlutterFlowTheme.of(context).titleMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static Widget buildAggregateStatsSection({
    required BuildContext context,
    required ProgressPageLogic logic,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Score Statistics',
          style: FlutterFlowTheme.of(context).titleMedium.override(
                fontFamily: 'Readex Pro',
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: buildAggregateStatCard(
                context: context,
                title: 'Avg Daily Score (7d)',
                value: logic.averageDailyScore7Day.toStringAsFixed(1),
                icon: Icons.trending_up,
                color: logic.averageDailyScore7Day >= 0
                    ? Colors.green
                    : Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: buildAggregateStatCard(
                context: context,
                title: 'Avg Daily Score (30d)',
                value: logic.averageDailyScore30Day.toStringAsFixed(1),
                icon: Icons.calendar_month,
                color: logic.averageDailyScore30Day >= 0
                    ? Colors.green
                    : Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: buildAggregateStatCard(
                context: context,
                title: 'Best Day',
                value: logic.bestDailyScoreGain.toStringAsFixed(1),
                icon: Icons.arrow_upward,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: buildAggregateStatCard(
                context: context,
                title: 'Worst Day',
                value: logic.worstDailyScoreGain.toStringAsFixed(1),
                icon: Icons.arrow_downward,
                color: Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: buildAggregateStatCard(
                context: context,
                title: 'Positive Days (7d)',
                value: '${logic.positiveDaysCount7Day}/7',
                icon: Icons.check_circle,
                color: logic.positiveDaysCount7Day >= 5
                    ? Colors.green
                    : Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: buildAggregateStatCard(
                context: context,
                title: 'Positive Days (30d)',
                value: '${logic.positiveDaysCount30Day}/30',
                icon: Icons.check_circle_outline,
                color: logic.positiveDaysCount30Day >= 20
                    ? Colors.green
                    : Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: buildAggregateStatCard(
                context: context,
                title: 'Avg Cumulative (7d)',
                value: logic.averageCumulativeScore7Day.toStringAsFixed(0),
                icon: Icons.bar_chart,
                color: FlutterFlowTheme.of(context).primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: buildAggregateStatCard(
                context: context,
                title: 'Avg Cumulative (30d)',
                value: logic.averageCumulativeScore30Day.toStringAsFixed(0),
                icon: Icons.assessment,
                color: FlutterFlowTheme.of(context).primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget buildAggregateStatCard({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: FlutterFlowTheme.of(context).bodyLarge.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  fontSize: 10,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static Widget buildCumulativeScoreCard({
    required BuildContext context,
    required ProgressPageLogic logic,
    required Function(double) onShowBreakdown,
  }) {
    final sharedData = TodayProgressState().getCumulativeScoreData();
    final displayScore = sharedData['cumulativeScore'] as double? ??
        logic.projectedCumulativeScore;

    // Use authoritative todayScore from shared state (matches Score Breakdown)
    // instead of computing from history diff which can diverge
    final displayGain =
        (sharedData['todayScore'] as double?) ?? logic.projectedDailyGain;

    final gainColor = displayGain >= 0 ? Colors.green : Colors.red;
    final gainIcon = displayGain >= 0 ? Icons.trending_up : Icons.trending_down;
    final gainText = displayGain >= 0
        ? '+${displayGain.toStringAsFixed(1)}'
        : displayGain.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            FlutterFlowTheme.of(context).primary.withOpacity(0.1),
            FlutterFlowTheme.of(context).secondaryBackground,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: FlutterFlowTheme.of(context).primary.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_events,
                color: FlutterFlowTheme.of(context).primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Cumulative Score',
                style: FlutterFlowTheme.of(context).titleLarge.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.bold,
                      color: FlutterFlowTheme.of(context).primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayScore.toStringAsFixed(0),
                      style: FlutterFlowTheme.of(context).displaySmall.override(
                            fontFamily: 'Readex Pro',
                            fontWeight: FontWeight.bold,
                            color: FlutterFlowTheme.of(context).primaryText,
                          ),
                    ),
                    Text(
                      'Total Points',
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            fontFamily: 'Readex Pro',
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Tap to see score breakdown',
                child: GestureDetector(
                  onTap: () => onShowBreakdown(displayGain),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Icon(gainIcon, color: gainColor, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            gainText,
                            style: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .override(
                                  fontFamily: 'Readex Pro',
                                  color: gainColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.info_outline,
                            color: gainColor,
                            size: 14,
                          ),
                        ],
                      ),
                      Text(
                        'Today',
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                              fontFamily: 'Readex Pro',
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          logic.buildMilestoneProgress(displayScore),
          const SizedBox(height: 12),
          ProgressChartsBuilder.buildCumulativeScoreGraph(
            context: context,
            logic: logic,
            onToggleRange: () {
              logic.show30Days = !logic.show30Days;
              logic.loadCumulativeScoreHistoryData();
            },
          ),
        ],
      ),
    );
  }

  static Widget buildBreakdownRow(
    BuildContext context,
    String label,
    double value,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                ),
          ),
          Text(
            value >= 0
                ? '+${value.toStringAsFixed(1)}'
                : value.toStringAsFixed(1),
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }

  static Widget buildDrawer({
    required BuildContext context,
    required FlutterFlowTheme theme,
  }) {
    final SharedPref sharedPref = SharedPref();

    return Drawer(
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
                        DrawerItem(
                          icon: Icons.home,
                          label: 'Home',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushReplacementNamed(context, home);
                          },
                        ),
                        DrawerItem(
                          icon: Icons.repeat,
                          label: 'Habits',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const HabitsPage(showCompleted: true),
                              ),
                            );
                          },
                        ),
                        DrawerItem(
                          icon: Icons.category,
                          label: 'Manage Categories',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ManageCategories(),
                              ),
                            );
                          },
                        ),
                        DrawerItem(
                          icon: Icons.monitor_heart,
                          label: 'Essential Activities',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const essentialTemplatesPage(),
                              ),
                            );
                          },
                        ),
                        DrawerItem(
                          icon: Icons.trending_up,
                          label: 'Progress History',
                          onTap: () {
                            Navigator.pop(context);
                          },
                        ),
                        if (kDebugMode) ...[
                          DrawerItem(
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
                        DrawerItem(
                          icon: Icons.settings,
                          label: 'Settings',
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
            DrawerItem(
              icon: Icons.logout,
              label: 'Log Out',
              onTap: () async {
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
          ],
        ),
      ),
    );
  }
}

class DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const DrawerItem({
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
