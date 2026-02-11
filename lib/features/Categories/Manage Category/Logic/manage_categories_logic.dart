import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/features/Categories/Create%20Category/create_category.dart';
import 'package:habit_tracker/features/Shared/polished_dialog.dart';

/// Logic mixin for ManageCategories that contains all business logic
/// This separates business logic from UI code
mixin ManageCategoriesLogic<T extends StatefulWidget> on State<T> {
  // State variables
  List<CategoryRecord> categories = [];
  bool isLoading = true;

  Future<void> loadCategories({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        isLoading = true;
      });
    }
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) {
        if (mounted) {
          setState(() {
            if (showLoading) {
              isLoading = false;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User not authenticated'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      // Load only user-created categories (exclude system categories like Inbox)
      final categoriesResult = await queryUserCategoriesOnce(userId: userId);
      if (mounted) {
        setState(() {
          categories = categoriesResult;
          if (showLoading) {
            isLoading = false;
          }
        });
      }
    } catch (e) {
      print('Error loading categories: $e');
      if (mounted) {
        setState(() {
          if (showLoading) {
            isLoading = false;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading categories: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> deleteCategoryRecord(CategoryRecord category) async {
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
      await loadCategories(); // Reload the list
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

  Future<void> showEditCategoryDialog(CategoryRecord category) async {
    final didUpdate = await showDialog<bool>(
      context: context,
      builder: (context) => CreateCategory(category: category),
    );
    if (didUpdate == true) {
      await loadCategories(showLoading: false);
    }
  }

  void showDeleteConfirmation(CategoryRecord category) {
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
        deleteCategoryRecord(category);
      },
    );
  }

  Future<void> showAddCategoryDialog() async {
    // Show dialog to select category type
    final categoryType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Category Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.repeat, color: Colors.green),
              title: const Text('Habit Category'),
              onTap: () => Navigator.of(context).pop('habit'),
            ),
            ListTile(
              leading: const Icon(Icons.task_alt, color: Colors.blue),
              title: const Text('Task Category'),
              onTap: () => Navigator.of(context).pop('task'),
            ),
            ListTile(
              leading: const Icon(Icons.monitor_heart, color: Colors.grey),
              title: const Text('Essential Category'),
              onTap: () => Navigator.of(context).pop('essential'),
            ),
          ],
        ),
      ),
    );

    if (categoryType != null) {
      final didCreate = await showDialog<bool>(
        context: context,
        builder: (context) => CreateCategory(categoryType: categoryType),
      );
      if (didCreate == true) {
        await loadCategories(showLoading: false);
      }
    }
  }

  Color parseColor(String colorString) {
    try {
      return Color(int.parse(colorString.replaceAll('#', '0xFF')));
    } catch (e) {
      return Colors.blue;
    }
  }
}
