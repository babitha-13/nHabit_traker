import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/custom_tab_decorator.dart';
import 'package:habit_tracker/Screens/Task/task_page.dart';

class TaskTab extends StatefulWidget {
  const TaskTab({super.key});
  @override
  State<TaskTab> createState() => _TaskTabState();
}

class _TaskTabState extends State<TaskTab> with TickerProviderStateMixin {
  late TabController _tabController;
  List<CategoryRecord> _categories = [];
  List<String> _tabNames = ["All"];
  static bool _hasEnsuredInbox = false;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabNames.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCategories();
  }

  void _onTabChanged() {
    setState(() {
      // Trigger rebuild to update tab styling
    });
  }

  Future<void> _loadCategories() async {
    if (!mounted) return;
    final fetched = await queryTaskCategoriesOnce(
      userId: currentUserUid,
      callerTag: 'TaskTab._loadCategories.initial',
    );
    if (!mounted) return;

    await _ensureInboxCategory(fetched);
    if (!mounted) return;

    final updatedFetched = await queryTaskCategoriesOnce(
      userId: currentUserUid,
      callerTag: 'TaskTab._loadCategories.updated',
    );
    if (!mounted) return;

    final List<String> newTabNames = ['All'];
    if (updatedFetched.isNotEmpty) {
      CategoryRecord? inboxCategory;
      for (final category in updatedFetched) {
        if (category.name.toLowerCase() == 'inbox') {
          inboxCategory = category;
          break;
        }
      }
      final inboxName = inboxCategory?.name ?? 'Inbox';
      final otherCategories = updatedFetched
          .where((c) => c.name.toLowerCase() != 'inbox')
          .toList();
      newTabNames
        ..add(inboxName)
        ..addAll(otherCategories.map((c) => c.name));
    }
    if (mounted) {
      setState(() {
        _categories = updatedFetched;
        _tabNames = newTabNames;
        _tabController.removeListener(_onTabChanged);
        _tabController.dispose();
        _tabController = TabController(length: _tabNames.length, vsync: this);
        _tabController.addListener(_onTabChanged);
      });
    }
  }

  Future<void> _ensureInboxCategory(List<CategoryRecord> categories) async {
    if (_hasEnsuredInbox) return;
    final userId = currentUserUid;
    if (userId.isEmpty) return;
    final inboxExists = categories.any(
      (c) => c.name.toLowerCase() == 'inbox' && c.isSystemCategory,
    );
    if (inboxExists) {
      _hasEnsuredInbox = true;
      return;
    }
    try {
      await createCategory(
        name: 'Inbox',
        description: 'Inbox task category',
        weight: 1.0,
        color: '#2F4F4F', // Dark Slate Gray (charcoal) for tasks
        categoryType: 'task',
        userId: userId,
        isSystemCategory: true,
      );
      _hasEnsuredInbox = true;
    } catch (e) {
      // Ignore duplicate creation errors; another instance likely created it.
      debugPrint('TaskTab: Unable to ensure Inbox category: $e');
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            // Add breathing room so the first tab isn't glued to the edge
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: _tabNames.isEmpty
                      ? const SizedBox()
                      : TabBar(
                          indicator: const BoxDecoration(),
                          indicatorColor: Colors.transparent,
                          controller: _tabController,
                          isScrollable: true,
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          padding: EdgeInsets.zero,
                          tabAlignment: TabAlignment.start,
                          tabs: _tabNames.asMap().entries.map((entry) {
                            final index = entry.key;
                            final name = entry.value;
                            return Tab(
                              child: CustomTabDecorator(
                                isActive: _tabController.index == index,
                                child: Text(name),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.black),
                  onPressed: () async {
                    await _showAddCategoryDialog(context);
                    await _loadCategories();
                  },
                ),
              ],
            ),
          ),
          Expanded(
              child: _categories.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: _tabNames.map((name) {
                        final categoryName = name == 'All' ? null : name;
                        return TaskPage(categoryName: categoryName);
                      }).toList(),
                    ))
        ],
      ),
    );
  }

  Future<void> _showAddCategoryDialog(BuildContext context) async {
    final TextEditingController tabController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Center(
                      child: Text(
                        "Add Category",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tabController,
                decoration: const InputDecoration(
                  hintText: "Enter category name",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final newName = tabController.text.trim();
                    if (newName.isEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Category name cannot be empty"),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                    }
                    final exists = _categories.any(
                      (c) => c.name.toLowerCase() == newName.toLowerCase(),
                    );
                    if (exists || newName.toLowerCase() == "inbox") {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Category already exists"),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                    }
                    await createCategory(
                      name: newName,
                      description: null,
                      weight: 1,
                      color: '#2F4F4F', // Dark Slate Gray (charcoal) for tasks
                      categoryType: 'task',
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FlutterFlowTheme.of(context).primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    "Add",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              )
            ],
          ),
        );
      },
    );
  }
}
