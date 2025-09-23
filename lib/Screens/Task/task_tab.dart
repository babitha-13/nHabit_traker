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

class _TaskTabState extends State<TaskTab>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<CategoryRecord> _categories = [];
  List<String> _tabNames = ["Default"];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabNames.length, vsync: this);
    _loadCategories();
  }


  Future<void> _loadCategories() async {
    final fetched = await queryCategoriesRecordOnce(userId: currentUserUid);
    setState(() {
      _categories = fetched;
      _tabNames = ["Default", ..._categories.map((c) => c.name)];
      _tabController.dispose();
      _tabController = TabController(length: _tabNames.length, vsync: this);
    });
  }

  @override
  void dispose() {
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
                    tabs: _tabNames
                        .map((name) => Tab(text: name))
                        .toList(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons. add, color: Colors.black),
                  onPressed: () async {
                    await _showAddCategoryDialog(context);
                    _loadCategories();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabNames.map((name) {
                if (name == "Default") {
                  return const TaskPage();
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
                    if (tabController.text.isEmpty) return;
                    await createCategory(
                      name: tabController.text,
                      description: null,
                      weight: 1,
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
              ),
            ],
          ),
        );
      },
    );
  }
}