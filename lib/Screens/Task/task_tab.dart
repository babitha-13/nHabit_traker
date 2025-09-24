import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Task/task_page.dart';

class TaskTab extends StatefulWidget {
  const TaskTab({super.key});

  @override
  State<TaskTab> createState() => _TaskTabState();
}

class _TaskTabState extends State<TaskTab> with TickerProviderStateMixin {
  TabController? _tabController;
  List<CategoryRecord> _categories = [];
  List<String> _tabNames = ["Inbox"];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // _tabController = TabController(length: _tabNames.length, vsync: this);
    _loadCategories();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);

    try {
      final fetched = await queryCategoriesRecordOnce(
        userId: currentUserUid,
      );
      bool inboxExists =
      fetched.any((c) => c.name.trim().toLowerCase() == 'inbox');
      if (!inboxExists) {
        await createCategory(
          name: 'Inbox',
          description: 'Inbox task category',
          weight: 1,
          categoryType: 'task',
        );
        final updatedFetched = await queryCategoriesRecordOnce(
          userId: currentUserUid,
        );
        fetched.clear();
        fetched.addAll(updatedFetched);
      }
      List<String> tabNames = fetched.map((c) => c.name.trim()).toList();
      tabNames.removeWhere((name) => name.toLowerCase() == 'inbox');
      tabNames.insert(0, 'Inbox');
      _tabController?.dispose();
      setState(() {
        _categories = fetched;
        _tabNames = tabNames;
        _tabController = TabController(length: _tabNames.length, vsync: this);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading categories: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: _tabNames.isEmpty
                      ? const SizedBox()
                      : TabBar(
                          indicatorColor: Colors.black,
                          controller: _tabController,
                          isScrollable: true,
                          tabs:
                              _tabNames.map((name) => Tab(text: name)).toList(),
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.black),
                  onPressed: () async {
                    await _showAddCategoryDialog(context);
                    // _loadCategories();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabNames.map((name) {
                if (name == "Inbox") {
                  final defaultCategory = _categories.firstWhere(
                    (c) => c.name.toLowerCase() == 'inbox',
                    orElse: () => _categories.isNotEmpty
                        ? _categories.first
                        : throw Exception('No categories found'),
                  );
                  return TaskPage(categoryId: defaultCategory.reference.id);
                } else {
                  final category = _categories.firstWhere(
                    (c) => c.name == name,
                  );
                  return TaskPage(categoryId: category.reference.id);
                }
              }).toList(),
            ),
          ),
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
                    final name = tabController.text.trim();
                    if (name.isEmpty) return;

                    // Check for duplicate
                    final exists = _categories.any(
                            (cat) => cat.name.toLowerCase() == name.toLowerCase());
                    if (exists) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Category with this name already exists!'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                      return;
                    }

                    // Create category
                    await createCategory(
                      name: name,
                      description: null,
                      weight: 1,
                      categoryType: 'task',
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                      await _loadCategories(); // reload tabs after adding
                    }
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
              ),
            ],
          ),
        );
      },
    );
  }
}
