import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Testing/simple_testing_page.dart';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Screens/Progress/Pages/habit_statistics_tab.dart';
import 'package:habit_tracker/Screens/Progress/Pages/category_statistics_tab.dart';
import '../Logic/progress_page_logic.dart';
import '../UI/progress_charts_builder.dart';
import '../UI/progress_stats_widgets.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({Key? key}) : super(key: key);
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> with ProgressPageLogic {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    checkDayTransition();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        key: scaffoldKey,
        backgroundColor: theme.primaryBackground,
        drawer: ProgressStatsWidgets.buildDrawer(context: context, theme: theme),
        appBar: AppBar(
          backgroundColor: theme.primary,
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Progress History',
            style: theme.headlineMedium.override(
                  fontFamily: 'Readex Pro',
                  color: Colors.white,
                  fontSize: 22.0,
                ),
          ),
          centerTitle: false,
          elevation: 0.0,
          actions: [
            PopupMenuButton<int>(
              icon: const Icon(Icons.calendar_today, color: Colors.white),
              tooltip: 'History Range',
              onSelected: (days) {
                if (days != historyDays) {
                  setState(() {
                    historyDays = days;
                  });
                  loadProgressHistory();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 7,
                  child: Text('Last 7 days'),
                ),
                const PopupMenuItem(
                  value: 30,
                  child: Text('Last 30 days'),
                ),
                const PopupMenuItem(
                  value: 90,
                  child: Text('Last 90 days'),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: loadProgressHistory,
              tooltip: 'Refresh',
            ),
            if (kDebugMode)
              IconButton(
                icon: const Icon(Icons.science, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SimpleTestingPage(),
                    ),
                  );
                },
                tooltip: 'Testing Tools',
              ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
              Tab(icon: Icon(Icons.list_alt), text: 'Habits'),
              Tab(icon: Icon(Icons.category), text: 'Categories'),
            ],
          ),
        ),
        body: SafeArea(
          top: true,
          child: TabBarView(
            children: [
              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildProgressContent(),
              const HabitStatisticsTab(),
              const CategoryStatisticsTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProgressStatsWidgets.buildCumulativeScoreCard(
            context: context,
            logic: this,
            onShowBreakdown: (displayGain) => showScoreBreakdownDialog(displayGain),
          ),
          const SizedBox(height: 16),
          ProgressStatsWidgets.buildSummaryCards(context: context, logic: this),
          const SizedBox(height: 16),
          ProgressChartsBuilder.buildTrendChart(context: context, logic: this),
          const SizedBox(height: 16),
          ProgressStatsWidgets.buildAggregateStatsSection(context: context, logic: this),
        ],
      ),
    );
  }
}
