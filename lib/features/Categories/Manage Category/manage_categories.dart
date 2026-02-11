import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Categories/Manage%20Category/Logic/manage_categories_logic.dart';

class ManageCategories extends StatefulWidget {
  const ManageCategories({super.key});
  @override
  _ManageCategoriesState createState() => _ManageCategoriesState();
}

class _ManageCategoriesState extends State<ManageCategories>
    with ManageCategoriesLogic {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    loadCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        automaticallyImplyLeading: true,
        title: Text(
          'Manage Categories',
          style: FlutterFlowTheme.of(context).headlineMedium,
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: SafeArea(
        top: true,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Categories list
                  Expanded(
                    child: categories.isEmpty
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
                                  onPressed: showAddCategoryDialog,
                                  child: const Text('Add Category'),
                                ),
                              ],
                            ),
                          )
                        : categories.isEmpty
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
                                      style: FlutterFlowTheme.of(context)
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Create categories to organize your habits and tasks!',
                                      style: FlutterFlowTheme.of(context)
                                          .bodyMedium,
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: showAddCategoryDialog,
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
        categories.where((cat) => cat.categoryType == 'habit').toList();
    final taskCategories =
        categories.where((cat) => cat.categoryType == 'task').toList();
    final essentialCategories =
        categories.where((cat) => cat.categoryType == 'essential').toList();
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
          // Essential Categories Section
          if (essentialCategories.isNotEmpty) ...[
            _buildSectionHeader('Essential Categories', Icons.monitor_heart,
                essentialCategories.length),
            ...essentialCategories
                .map((category) => _buildCategoryItem(category, 'essential')),
            const SizedBox(height: 16),
          ],
          // Show message if only one or two types exist
          if (habitCategories.isEmpty &&
              taskCategories.isNotEmpty &&
              essentialCategories.isNotEmpty)
            _buildEmptyTypeMessage('habit'),
          if (taskCategories.isEmpty &&
              habitCategories.isNotEmpty &&
              essentialCategories.isNotEmpty)
            _buildEmptyTypeMessage('task'),
          if (essentialCategories.isEmpty &&
              habitCategories.isNotEmpty &&
              taskCategories.isNotEmpty)
            _buildEmptyTypeMessage('essential'),
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
            color: parseColor(category.color),
            shape: BoxShape.circle,
          ),
          child: Icon(
            type == 'habit'
                ? Icons.repeat
                : (type == 'task' ? Icons.task_alt : Icons.monitor_heart),
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
                    : (type == 'task'
                        ? Colors.blue.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                type.toUpperCase(),
                style: TextStyle(
                  color: type == 'habit'
                      ? Colors.green[700]
                      : (type == 'task' ? Colors.blue[700] : Colors.grey[700]),
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
              onPressed: () => showEditCategoryDialog(category),
              color: FlutterFlowTheme.of(context).secondaryText,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => showDeleteConfirmation(category),
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
            missingType == 'habit'
                ? Icons.repeat
                : (missingType == 'task'
                    ? Icons.task_alt
                    : Icons.monitor_heart),
            color: FlutterFlowTheme.of(context).secondaryText,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No ${missingType} categories yet. Create one to organize your ${missingType}${missingType == 'essential' ? ' activities' : 's'}!',
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
}
