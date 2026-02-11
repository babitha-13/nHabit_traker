import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/Helpers/category_color_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';

/// Logic mixin for CreateCategory that contains all business logic
/// This separates business logic from UI code
mixin CreateCategoryLogic<T extends StatefulWidget> on State<T> {
  // State variables
  int weight = 1;
  String selectedColor = CategoryColorUtil.palette.first;
  List<CategoryRecord> existingCategories = [];
  bool isValidating = false;

  Future<void> loadExistingCategories() async {
    try {
      final fetchedCategories = await queryCategoriesRecordOnce(
        userId: currentUserUid,
        callerTag: 'CreateCategory._loadExistingCategories',
      );
      if (mounted) {
        setState(() {
          existingCategories = fetchedCategories;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading categories: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<dynamic> saveCategory({
    required TextEditingController nameController,
    required TextEditingController descriptionController,
    required CategoryRecord? category,
    required String? categoryType,
    required bool isEdit,
  }) async {
    if (nameController.text.isEmpty) return null;
    if (!mounted) return null;
    setState(() {
      isValidating = true;
    });
    try {
      // Get fresh categories from database
      final freshCategories = await queryCategoriesRecordOnce(
        userId: currentUserUid,
        callerTag: 'CreateCategory.validateName',
      );
      // Check for duplicate names, but exclude the current category when editing
      final newName = nameController.text.trim().toLowerCase();
      final nameExists = freshCategories.any((cat) {
        // Skip the current category when editing
        if (isEdit &&
            cat.reference.id == category!.reference.id) {
          return false;
        }
        final existingName = cat.name.trim().toLowerCase();
        return existingName == newName;
      });
      if (nameExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Category with this name already exists!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        if (mounted) {
          setState(() {
            isValidating = false;
          });
        }
        return null;
      }
      if (isEdit) {
        // Check if name changed for cascade update
        final oldName = category!.name;
        final newNameValue = nameController.text.trim();
        final nameChanged = oldName != newNameValue;
        final oldColor = category.color;
        final colorChanged = oldColor != selectedColor;
        await updateCategory(
          categoryId: category.reference.id,
          name: nameController.text,
          description: descriptionController.text.isNotEmpty
              ? descriptionController.text
              : null,
          weight: 1.0,
          color: selectedColor,
          categoryType:
              categoryType, // Only update if provided
        );
        // If metadata changed, cascade the update to all templates and instances
        if (nameChanged || colorChanged) {
          try {
            await updateCategoryCascade(
              categoryId: category.reference.id,
              userId: currentUserUid,
              newCategoryName: nameChanged ? newNameValue : null,
              newCategoryColor:
                  colorChanged ? selectedColor : null,
            );
          } catch (e) {
            // Show warning but don't fail the operation
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Warning: Some items may not reflect the updated category immediately'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        }
        return true;
      } else {
        // ✅ Create new
        final newCategoryRef = await createCategory(
          name: nameController.text,
          description: descriptionController.text.isNotEmpty
              ? descriptionController.text
              : null,
          weight: 1.0,
          color: selectedColor,
          categoryType: categoryType ??
              'habit', // Default to habit if not specified
        );
        return newCategoryRef.id;
      }
    } catch (e) {
      if (mounted) {
        // Check if it's a duplicate name error from backend
        final errorMessage = e.toString();
        if (errorMessage.contains('already exists')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Category with this name already exists!'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          isValidating = false;
        });
      }
    }
  }
}
