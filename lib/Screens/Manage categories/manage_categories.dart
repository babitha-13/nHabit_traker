import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/polished_dialog.dart';
import 'package:habit_tracker/Screens/Create%20Catagory/create_category.dart';

class ManageCategories extends StatefulWidget {
  const ManageCategories({super.key});
  @override
  _ManageCategoriesState createState() => _ManageCategoriesState();
}

class _ManageCategoriesState extends State<ManageCategories> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  List<CategoryRecord> _categories = [];
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        // Load only user-created categories (exclude system categories like Inbox)
        final categories = await queryUserCategoriesOnce(userId: userId);
        setState(() {
          _categories = categories;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteCategory(CategoryRecord category) async {
    try {
      // Safety check: prevent deletion of system categories
      if (category.isSystemCategory) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('System categories cannot be deleted'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      await deleteCategory(category.reference.id, userId: currentUserUid);
      await _loadCategories(); // Reload the list
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Category "${category.name}" deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting category: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEditCategoryDialog(CategoryRecord category) {
    showDialog(
      context: context,
      builder: (context) => CreateCategory(category: category),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      body: SafeArea(
        top: true,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Categories list
                  Expanded(
                    child: _categories.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.category,
                                  size: 64,
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryText,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No categories yet',
                                  style:
                                      FlutterFlowTheme.of(context).titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Create categories to organize your habits and tasks!',
                                  style:
                                      FlutterFlowTheme.of(context).bodyMedium,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _showAddCategoryDialog,
                                  child: const Text('Add Category'),
                                ),
                              ],
                            ),
                          )
                        : _buildCategorizedList(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildCategorizedList() {
    // Separate categories by type
    final habitCategories =
        _categories.where((cat) => cat.categoryType == 'habit').toList();
    final taskCategories =
        _categories.where((cat) => cat.categoryType == 'task').toList();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Habit Categories Section
          if (habitCategories.isNotEmpty) ...[
            _buildSectionHeader(
                'Habit Categories', Icons.repeat, habitCategories.length),
            ...habitCategories
                .map((category) => _buildCategoryItem(category, 'habit')),
            const SizedBox(height: 16),
          ],
          // Task Categories Section
          if (taskCategories.isNotEmpty) ...[
            _buildSectionHeader(
                'Task Categories', Icons.task_alt, taskCategories.length),
            ...taskCategories
                .map((category) => _buildCategoryItem(category, 'task')),
            const SizedBox(height: 16),
          ],
          // Show message if only one type exists
          if (habitCategories.isEmpty && taskCategories.isNotEmpty)
            _buildEmptyTypeMessage('habit'),
          if (taskCategories.isEmpty && habitCategories.isNotEmpty)
            _buildEmptyTypeMessage('task'),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlutterFlowTheme.of(context).primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: FlutterFlowTheme.of(context).primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: FlutterFlowTheme.of(context).titleMedium.override(
                  fontWeight: FontWeight.w600,
                  color: FlutterFlowTheme.of(context).primary,
                ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(CategoryRecord category, String type) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _parseColor(category.color),
            shape: BoxShape.circle,
          ),
          child: Icon(
            type == 'habit' ? Icons.repeat : Icons.task_alt,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                category.name,
                style: FlutterFlowTheme.of(context).titleMedium,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: type == 'habit'
                    ? Colors.green.withOpacity(0.2)
                    : Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                type.toUpperCase(),
                style: TextStyle(
                  color: type == 'habit' ? Colors.green[700] : Colors.blue[700],
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (category.description.isNotEmpty)
              Text(
                category.description,
                style: FlutterFlowTheme.of(context).bodyMedium,
              ),
            const SizedBox(height: 4),
            Row(
              children: [],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditCategoryDialog(category),
              color: FlutterFlowTheme.of(context).secondaryText,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _showDeleteConfirmation(category),
              color: Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTypeMessage(String missingType) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            FlutterFlowTheme.of(context).secondaryBackground.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            missingType == 'habit' ? Icons.repeat : Icons.task_alt,
            color: FlutterFlowTheme.of(context).secondaryText,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No ${missingType} categories yet. Create one to organize your ${missingType}s!',
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    color: FlutterFlowTheme.of(context).secondaryText,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String colorString) {
    try {
      return Color(int.parse(colorString.replaceAll('#', '0xFF')));
    } catch (e) {
      return Colors.blue;
    }
  }

  void _showDeleteConfirmation(CategoryRecord category) {
    showPolishedAlertDialog(
      context: context,
      title: 'Delete Category',
      content:
          'Are you sure you want to delete "${category.name}"? This action cannot be undone.',
      cancelText: 'Cancel',
      confirmText: 'Delete',
      isDestructive: true,
      onConfirm: () {
        Navigator.of(context).pop();
        _deleteCategory(category);
      },
    );
  }

  void _showAddCategoryDialog() {
    showPolishedDialog(
      context: context,
      content: const CreateCategory(),
    );
  }
}
