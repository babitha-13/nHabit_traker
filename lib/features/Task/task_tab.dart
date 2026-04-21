import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Task/task_tabs_UI.dart';
import 'package:habit_tracker/features/Task/task_page.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';

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
  StreamSubscription? _authSubscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabNames.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCategories();

    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) _loadCategories();
    });

    // Listen for auth changes to retry loading if initial load failed due to missing auth
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && (_categories.isEmpty || _hasEnsuredInbox == false)) {
        _loadCategories();
      }
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    // Force reload categories on hot reload
    _loadCategories();
  }

  void _onTabChanged() {
    setState(() {
      // Trigger rebuild to update tab styling
    });
  }

  Future<void> _loadCategories() async {
    if (!mounted) return;

    // Check if auth is ready - if not, wait for listener
    final uid = await waitForCurrentUserUid();
    if (uid.isEmpty) {
      // If auth isn't ready, we can't load yet. Listener will retry.
      return;
    }

    // Only set loading if categories are empty (initial load)
    if (_categories.isEmpty && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final fetched = await queryTaskCategoriesOnce(
        userId: uid,
        callerTag: 'TaskTab._loadCategories.initial',
      );
      if (!mounted) return;

      await _ensureInboxCategory(fetched);
      if (!mounted) return;

      final updatedFetched = await queryTaskCategoriesOnce(
        userId: uid,
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
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _ensureInboxCategory(List<CategoryRecord> categories) async {
    if (_hasEnsuredInbox) return;
    final userId = await waitForCurrentUserUid();
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
    }
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this, 'categoryUpdated');
    _authSubscription?.cancel();
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
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: _tabNames.isEmpty
                      ? const SizedBox()
                      : TabBar(
                          indicator: const BoxDecoration(),
                          indicatorColor: Colors.transparent,
                          dividerColor: Colors.transparent,
                          controller: _tabController,
                          isScrollable: true,
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          padding: EdgeInsets.zero,
                          tabAlignment: TabAlignment.start,
                          tabs: _tabNames.asMap().entries.map((entry) {
                            final index = entry.key;
                            final name = entry.value;
                            return Tab(
                              height: 36,
                              child: CustomTabDecorator(
                                isActive: _tabController.index == index,
                                child: Text(name),
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _showCategoryMenu(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.grid_view_rounded,
                        size: 20, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _categories.isEmpty
                      ? const Center(child: Text("No categories found"))
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

  void _showCategoryMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 32 + MediaQuery.of(ctx).padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Categories',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _showAddCategoryDialog(context);
                          await _loadCategories();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tabNames.asMap().entries.map((entry) {
                      final index = entry.key;
                      final name = entry.value;
                      final isSelected = _tabController.index == index;
                      return GestureDetector(
                        onTap: () {
                          _tabController.animateTo(index);
                          Navigator.pop(ctx);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? FlutterFlowTheme.of(context).primary
                                : const Color(0xFFF0F0F0),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            name,
                            style: TextStyle(
                              color:
                                  isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
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
