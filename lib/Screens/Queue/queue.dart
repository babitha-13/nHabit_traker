import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/task_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_instance_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:intl/intl.dart';

// Unified model for both task and habit instances
class ActionItem {
  final String id;
  final String templateId;
  final String name;
  final String type; // 'task' or 'habit'
  final DateTime dueDate;
  final int priority;
  final String categoryName;
  final String trackingType;
  final dynamic target;
  final dynamic currentValue;
  final String status;
  final String unit;

  ActionItem.fromTaskInstance(TaskInstanceRecord instance)
      : id = instance.reference.id,
        templateId = instance.templateId,
        name = instance.templateName,
        type = 'task',
        dueDate = instance.dueDate!,
        priority = instance.templatePriority,
        categoryName = instance.templateCategoryName,
        trackingType = instance.templateTrackingType,
        target = instance.templateTarget,
        currentValue = instance.currentValue,
        status = instance.status,
        unit = instance.templateUnit;

  ActionItem.fromHabitInstance(HabitInstanceRecord instance)
      : id = instance.reference.id,
        templateId = instance.templateId,
        name = instance.templateName,
        type = 'habit',
        dueDate = instance.dueDate!,
        priority = instance.templatePriority,
        categoryName = instance.templateCategoryName,
        trackingType = instance.templateTrackingType,
        target = instance.templateTarget,
        currentValue = instance.currentValue,
        status = instance.status,
        unit = instance.templateUnit;

  bool get isOverdue => dueDate.isBefore(_todayStart);
  bool get isDueToday => _isSameDay(dueDate, DateTime.now());
  bool get isDueTomorrow =>
      _isSameDay(dueDate, DateTime.now().add(Duration(days: 1)));

  static DateTime get _todayStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class QueuePage extends StatefulWidget {
  final bool showCompleted;
  const QueuePage({super.key, required this.showCompleted});

  @override
  _QueuePageState createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  final ScrollController _scrollController = ScrollController();
  List<ActionItem> _allItems = [];
  bool _isLoading = true;
  late bool _showCompleted;
  bool _showTomorrow = true;
  bool _showThisWeek = false;

  @override
  void initState() {
    super.initState();
    _showCompleted = widget.showCompleted;
    _loadItems();

    NotificationCenter.addObserver(this, 'showCompleted', (param) {
      if (param is bool && mounted) {
        setState(() {
          _showCompleted = param;
        });
      }
    });

    NotificationCenter.addObserver(this, 'loadQueue', (param) {
      if (mounted) {
        _loadItems();
      }
    });
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final taskInstances = await queryTodaysTaskInstances(userId: userId);
        final habitInstances = await queryTodaysHabitInstances(userId: userId);
        final items = <ActionItem>[];
        items.addAll(taskInstances.map((t) => ActionItem.fromTaskInstance(t)));
        items.addAll(habitInstances.map((h) => ActionItem.fromHabitInstance(h)));
        items.sort((a, b) {
          final priorityCompare = b.priority.compareTo(a.priority);
          if (priorityCompare != 0) return priorityCompare;
          return a.dueDate.compareTo(b.dueDate);
        });

        setState(() {
          _allItems = items;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading queue items: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<ActionItem> get _todayItems {
    return _allItems.where((item) {
      if (!_showCompleted && item.status == 'completed') return false;
      return item.isDueToday || item.isOverdue;
    }).toList();
  }

  List<ActionItem> get _tomorrowItems {
    return _allItems.where((item) {
      if (!_showCompleted && item.status == 'completed') return false;
      return item.isDueTomorrow;
    }).toList();
  }

  List<ActionItem> get _thisWeekItems {
    final now = DateTime.now();
    final weekEnd = now.add(Duration(days: 7 - now.weekday));

    return _allItems.where((item) {
      if (!_showCompleted && item.status == 'completed') return false;
      return item.dueDate.isAfter(now.add(Duration(days: 1))) &&
          item.dueDate.isBefore(weekEnd);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _buildQueueView(),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        border: Border(
          bottom: BorderSide(
            color: FlutterFlowTheme.of(context).alternate,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE, MMMM d, y').format(DateTime.now()),
              style: FlutterFlowTheme.of(context).titleLarge.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your action queue for focused execution',
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    fontFamily: 'Readex Pro',
                    color: FlutterFlowTheme.of(context).secondaryText,
                  ),
            ),
            const SizedBox(height: 12),
            // Quick stats
            Row(
              children: [
                _buildStatChip('Today', _todayItems.length, Colors.orange),
                const SizedBox(width: 8),
                _buildStatChip('Tomorrow', _tomorrowItems.length, Colors.blue),
                const SizedBox(width: 8),
                _buildStatChip(
                    'This Week', _thisWeekItems.length, Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueView() {
    if (_allItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              size: 64,
              color: Colors.green,
            ),
            const SizedBox(height: 16),
            Text(
              'Queue is empty! 🎉',
              style: FlutterFlowTheme.of(context).titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'All caught up with your tasks and habits!',
              style: FlutterFlowTheme.of(context).bodyMedium,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        children: [
          // Today section (always shown)
          _buildSection(
            title: 'Today',
            items: _todayItems,
            isExpanded: true,
            canCollapse: false,
            color: Colors.orange,
          ),

          // Tomorrow section (collapsible)
          if (_tomorrowItems.isNotEmpty)
            _buildSection(
              title: 'Tomorrow',
              items: _tomorrowItems,
              isExpanded: _showTomorrow,
              canCollapse: true,
              color: Colors.blue,
              onToggle: () => setState(() => _showTomorrow = !_showTomorrow),
            ),

          // This Week section (collapsible)
          if (_thisWeekItems.isNotEmpty)
            _buildSection(
              title: 'This Week',
              items: _thisWeekItems,
              isExpanded: _showThisWeek,
              canCollapse: true,
              color: Colors.green,
              onToggle: () => setState(() => _showThisWeek = !_showThisWeek),
            ),

          const SizedBox(height: 140), // Space for floating elements
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<ActionItem> items,
    required bool isExpanded,
    required bool canCollapse,
    required Color color,
    VoidCallback? onToggle,
  }) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          ListTile(
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${items.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
                if (canCollapse) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more),
                    onPressed: onToggle,
                  ),
                ],
              ],
            ),
          ),
          if (isExpanded) ...[
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  title == 'Today'
                      ? 'All done for today! 🎉'
                      : 'Nothing scheduled',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...items.map((item) => _buildActionItemTile(item)).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildActionItemTile(ActionItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: item.isOverdue ? Colors.red.shade50 : null,
        borderRadius: BorderRadius.circular(8),
        border: item.isOverdue ? Border.all(color: Colors.red.shade200) : null,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getPriorityColor(item.priority),
          radius: 16,
          child: Icon(
            item.type == 'task' ? Icons.assignment : Icons.repeat,
            size: 16,
            color: Colors.white,
          ),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: item.isOverdue ? Colors.red.shade700 : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.categoryName} • ${item.type}'),
            if (item.isOverdue)
              Text(
                'Overdue',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              )
            else if (item.isDueToday)
              Text(
                'Due today',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (item.trackingType != 'binary')
              LinearProgressIndicator(
                value: _getProgress(item),
                backgroundColor: Colors.grey.shade300,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Focus button
            IconButton(
              icon: Icon(Icons.center_focus_strong, color: Colors.purple),
              onPressed: () => _enterFocusMode(item),
              tooltip: 'Focus on this ${item.type}',
            ),
            // Complete button
            IconButton(
              icon: Icon(Icons.check_circle, color: Colors.green),
              onPressed: () => _completeItem(item),
              tooltip: 'Complete',
            ),
            // Skip button
            IconButton(
              icon: Icon(Icons.skip_next, color: Colors.orange),
              onPressed: () => _skipItem(item),
              tooltip: 'Skip',
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  double _getProgress(ActionItem item) {
    if (item.target == null || item.currentValue == null) {
      return 0.0;
    }
    final target = item.target as num;
    final current = item.currentValue as num;
    if (target <= 0) return 0.0;
    return (current / target).clamp(0.0, 1.0);
  }

  Future<void> _completeItem(ActionItem item) async {
    try {
      if (item.type == 'task') {
        await completeTaskInstance(
          instanceId: item.id,
          finalValue: item.target,
        );
      } else {
        await completeHabitInstance(
          instanceId: item.id,
          finalValue: item.target,
        );
      }

      await _loadItems();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.name} completed! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error completing ${item.type}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _skipItem(ActionItem item) async {
    try {
      if (item.type == 'task') {
        await skipTaskInstance(instanceId: item.id);
      } else {
        await skipHabitInstance(instanceId: item.id);
      }

      await _loadItems();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.name} skipped'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error skipping ${item.type}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _enterFocusMode(ActionItem item) {
    // Navigate to focus mode with this item
    // This would be implemented based on your focus mode implementation
    print('Enter focus mode for: ${item.name}');

    // For now, show a dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Focus Mode'),
        content: Text('Focus mode for "${item.name}" would open here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
}
