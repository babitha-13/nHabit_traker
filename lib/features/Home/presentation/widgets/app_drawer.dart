import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/features/Settings/faq_page.dart';
import 'package:habit_tracker/features/Categories/Manage%20Category/manage_categories.dart';
import 'package:habit_tracker/features/Progress/Pages/progress_page.dart';
import 'package:habit_tracker/features/Settings/settings_page.dart';
import 'package:habit_tracker/features/Testing/simple_testing_page.dart';

/// Drawer item widget for consistent menu item styling
class DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const DrawerItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label, style: theme.textTheme.bodyLarge),
      onTap: onTap,
    );
  }
}

class AppDrawer extends StatelessWidget {
  final String currentUserEmail;
  final Function(String) loadPage;
  final VoidCallback onLogout;

  const AppDrawer({
    super.key,
    required this.currentUserEmail,
    required this.loadPage,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(theme),
                  Expanded(child: _buildMenu(context)),
                ],
              ),
            ),
            DrawerItem(
              icon: Icons.logout,
              label: 'Log Out',
              onTap: onLogout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      color: theme.colorScheme.primary,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            currentUserEmail.isNotEmpty ? currentUserEmail : 'email',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    return ListView(
      children: [
        DrawerItem(
          icon: Icons.home,
          label: 'Home',
          onTap: () {
            loadPage('Queue');
            Navigator.pop(context);
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
                builder: (_) => const ManageCategories(),
              ),
            );
          },
        ),
        DrawerItem(
          icon: Icons.monitor_heart,
          label: 'Essential Activities',
          onTap: () {
            loadPage('Essential');
            Navigator.pop(context);
          },
        ),
        DrawerItem(
          icon: Icons.trending_up,
          label: 'Progress History',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProgressPage(),
              ),
            );
          },
        ),
        if (kDebugMode)
          DrawerItem(
            icon: Icons.science,
            label: 'Testing Tools',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SimpleTestingPage(),
                ),
              );
            },
          ),
        const Divider(),
        DrawerItem(
          icon: Icons.settings,
          label: 'Settings',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SettingsPage(),
              ),
            );
          },
        ),
        DrawerItem(
          icon: Icons.help_outline,
          label: 'FAQ',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const FaqPage(),
              ),
            );
          },
        ),
      ],
    );
  }
}
