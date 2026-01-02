import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('FAQ'),
        backgroundColor: theme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Quick guide to how nHabit Tracker works',
            style: theme.titleMedium.override(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Tasks vs Habits',
            children: [
              Text(
                'A quick side-by-side comparison:',
                style: theme.bodySmall,
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 680;
                  final children = <Widget>[
                    _CompareCard(
                      title: 'Tasks',
                      icon: Icons.checklist,
                      bullets: const [
                        'Things that need to be done (responsibilities).',
                        'Can be one-off (Fix the AC) or recurring (Pay rent every month).',
                        'Have a due date. If missed, they become overdue and stay until completed, skipped, or deleted.',
                        'Cannot be snoozed.',
                        'Historical progress isn’t tracked (focus is on getting them done).',
                      ],
                    ),
                    _CompareCard(
                      title: 'Habits',
                      icon: Icons.repeat,
                      bullets: const [
                        'Things you want to build or aspire to do.',
                        'Always recurring (Daily/weekly patterns).',
                        'Have a completion window (e.g., “jog once within 7 days”).',
                        'If not done within the window, it auto-skips and the next window/target appears.',
                        'Can be snoozed within the window if you know you can’t do it for a few days.',
                        'Historical progress is tracked (last 7/30 days, streak-style insights).',
                      ],
                    ),
                  ];

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: children[0]),
                        const SizedBox(width: 12),
                        Expanded(child: children[1]),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      children[0],
                      const SizedBox(height: 12),
                      children[1],
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                'Both tasks and habits can be tracked as Binary, Quantity, or Time depending on what “progress” means for that activity.',
                style: theme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Tracking types (Binary / Quantity / Time)',
            children: [
              _Bullet(
                'Binary: Done / Not Done. You mark it complete by ticking it. Partial progress is not tracked.',
              ),
              _Bullet(
                'Quantity: Track a numeric target (e.g., drink 8 glasses, read 10 pages). You can add progress as you go; it completes when the target is reached. Partial progress is tracked.',
              ),
              _Bullet(
                'Time: Track a time target (e.g., workout for 1 hour). Use the timer controls to log time; it completes when the target time is reached. Partial progress is tracked.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Scoring (the basics)',
            children: [
              _Bullet(
                'Your points are primarily driven by Priority. As a simple mental model: 1-star ≈ 1 point, 3-star ≈ 3 points for the same amount of progress.',
              ),
              _Bullet(
                'Quantity is scored by quantity progress. Time is scored by time progress. Binary is scored by completion (and optionally time spent if Effort Mode is ON).',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Two scoring systems: Goal mode vs Effort mode',
            children: [
              _Bullet(
                'Goal mode (Effort Mode OFF): points reflect completion/progress against your targets.',
              ),
              _Bullet(
                'Effort mode (Effort Mode ON): binary + time-based activities also reward time spent (in 30-minute blocks). Quantity remains quantity-only.',
              ),
              const SizedBox(height: 8),
              _Callout(
                title:
                    'When Effort Mode is ON (examples for a 1-star activity)',
                body: 'Binary:\n'
                    '- Completed in under 30m → 1 pt\n'
                    '- 1h logged → 2 pts\n'
                    '- 2h logged → 4 pts\n'
                    '\n'
                    'Time:\n'
                    '- Under 30m logged → 1 pt\n'
                    '- 1h logged → 2 pts\n'
                    '- 2h logged → 4 pts\n'
                    '\n'
                    'Quantity:\n'
                    '- Time doesn’t matter; points depend on quantity vs target.',
              ),
              const SizedBox(height: 12),
              _Callout(
                title:
                    'When Effort Mode is OFF (examples for a 1-star activity)',
                body: 'Binary:\n'
                    '- Completed → 1 pt\n'
                    '- Not completed → 0 pts\n'
                    '- Time is still logged to the calendar, but doesn’t affect binary scoring.\n'
                    '\n'
                    'Time:\n'
                    '- Scored by actual time vs your time target.\n'
                    '  Example: target 2h, logged 2h → 1 pt.\n'
                    '  Example: target 1h, logged 2h → 2 pts.\n'
                    '\n'
                    'Quantity:\n'
                    '- Scored by actual quantity vs target quantity.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Partial completion',
            children: [
              _Bullet(
                  'You don’t have to give up on an activity if you can’t finish it fully—partial effort can still earn points (except Binary).'),
              _Bullet(
                  'Binary: no partial points (it’s either completed or not).'),
              _Bullet(
                  'Quantity: points scale with completion ratio. Example: 4 out of 8 → 0.5 points (for a 1-star item).'),
              _Bullet(
                  'Time: points scale with completion ratio in Goal mode. Example: 15m out of 1h target → 0.25 points (for a 1-star item).'),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Over-completion',
            children: [
              _Bullet(
                  'You can earn more points by exceeding your targets—extra effort is rewarded.'),
              _Bullet(
                  'Binary: over-completion is not a concept in Goal mode. In Effort mode, spending more time increases points. In Goal mode, extra time doesn’t add points.'),
              _Bullet(
                  'Quantity: over-completion earns more points in both modes. Example: 10 vs 8 target → 1.25 points (for a 1-star item).'),
              _Bullet(
                'Time: you can earn more points by spending more time in both modes, but the calculation differs.\n'
                '- Effort mode ON: points are based on 30-minute blocks (e.g., 2h → 4 pts for 1-star)\n'
                '- Effort mode OFF: points are based on time vs your target (e.g., 2h on a 1h target → 2 pts for 1-star)',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'What does “Priority” mean?',
            children: [
              _Bullet(
                'Priority is the main weight for points. Higher priority items award more points for the same progress/time.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'What else is worth explaining?',
            children: [
              _Bullet(
                'Essential Activities track time but do not earn points.',
              ),
              _Bullet(
                'Windowed habits (multi-day windows) can award points based on today’s contribution within the window.',
              ),
              _Bullet(
                'Logged time can come from timers or manual time logs (depending on the activity).',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.titleSmall.override(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.title,
    required this.icon,
    required this.bullets,
  });

  final String title;
  final IconData icon;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.alternate),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.titleSmall.override(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final b in bullets) _Bullet(b),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: theme.primaryText,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.alternate),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.bodyMedium.override(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.bodySmall,
          ),
        ],
      ),
    );
  }
}
