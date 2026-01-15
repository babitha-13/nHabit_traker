import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/Helpers/category_color_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Shared/polished_dialog.dart';

class CreateCategory extends StatefulWidget {
  final CategoryRecord? category;
  final String? categoryType; // 'habit' or 'task'
  const CreateCategory({super.key, this.category, this.categoryType});
  @override
  State<CreateCategory> createState() => _CreateCategoryState();
}

class _CreateCategoryState extends State<CreateCategory> {
  late TextEditingController nameController;
  late TextEditingController descriptionController;
  int weight = 1;
  String selectedColor = CategoryColorUtil.palette.first;
  List<CategoryRecord> existingCategories = [];
  bool _isValidating = false;
  @override
  void initState() {
    super.initState();
    // Prefill if editing
    nameController = TextEditingController(text: widget.category?.name ?? "");
    descriptionController =
        TextEditingController(text: widget.category?.description ?? "");
    weight = (widget.category?.weight ?? 1.0).round();
    selectedColor = widget.category?.color.isNotEmpty == true
        ? widget.category!.color
        : CategoryColorUtil.palette.first;
    _loadExistingCategories();
  }

  Future<void> _loadExistingCategories() async {
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

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isEdit = widget.category != null;

    final categoryTypeLabel = widget.categoryType == 'essential'
        ? 'Essential '
        : (widget.categoryType == 'task'
            ? 'Task '
            : (widget.categoryType == 'habit' ? 'Habit ' : ''));
    return PolishedDialog(
      title: isEdit
          ? 'Edit ${categoryTypeLabel}Category'
          : 'Create New ${categoryTypeLabel}Category',
      content: AbsorbPointer(
        absorbing: _isValidating,
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Name Field
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.tertiary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.surfaceBorderColor,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: nameController,
                      style: theme.bodyMedium,
                      decoration: InputDecoration(
                        labelText: 'Category Name *',
                        labelStyle: TextStyle(color: theme.secondaryText),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Description Field
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.tertiary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.surfaceBorderColor,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: descriptionController,
                      style: theme.bodyMedium,
                      decoration: InputDecoration(
                        labelText: 'Description (Optional)',
                        labelStyle: TextStyle(color: theme.secondaryText),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Color Selection
                  Text(
                    'Color',
                    style: theme.titleSmall.override(
                      color: theme.primaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.accent2.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.surfaceBorderColor,
                        width: 1,
                      ),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: CategoryColorUtil.palette.map((color) {
                        final isSelected = selectedColor == color;
                        return GestureDetector(
                          onTap: () => setState(() => selectedColor = color),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(
                                  int.parse(color.replaceFirst('#', '0xFF'))),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? theme.accent1
                                    : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: theme.accent1.withOpacity(0.3),
                                        offset: const Offset(0, 2),
                                        blurRadius: 4,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? Icon(
                                    Icons.check,
                                    size: 18,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            if (_isValidating)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.2),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(
                          isEdit
                              ? 'Updating category...'
                              : 'Saving category...',
                          style: theme.bodyMedium.override(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed:
              _isValidating ? null : () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            side: BorderSide(color: theme.surfaceBorderColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.buttonRadius),
            ),
          ),
          child: Text(
            'Cancel',
            style: TextStyle(color: theme.secondaryText),
          ),
        ),
        ElevatedButton(
          onPressed: _isValidating
              ? null
              : () async {
                  if (nameController.text.isEmpty) return;
                  if (!mounted) return;
                  setState(() {
                    _isValidating = true;
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
                          cat.reference.id == widget.category!.reference.id) {
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
                          _isValidating = false;
                        });
                      }
                      return;
                    }
                    if (isEdit) {
                      // Check if name changed for cascade update
                      final oldName = widget.category!.name;
                      final newName = nameController.text.trim();
                      final nameChanged = oldName != newName;
                      final oldColor = widget.category!.color;
                      final colorChanged = oldColor != selectedColor;
                      await updateCategory(
                        categoryId: widget.category!.reference.id,
                        name: nameController.text,
                        description: descriptionController.text.isNotEmpty
                            ? descriptionController.text
                            : null,
                        weight: 1.0,
                        color: selectedColor,
                        categoryType:
                            widget.categoryType, // Only update if provided
                      );
                      // If metadata changed, cascade the update to all templates and instances
                      if (nameChanged || colorChanged) {
                        try {
                          await updateCategoryCascade(
                            categoryId: widget.category!.reference.id,
                            userId: currentUserUid,
                            newCategoryName: nameChanged ? newName : null,
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
                      Navigator.of(context).pop(true);
                    } else {
                      // ✅ Create new
                      final newCategoryRef = await createCategory(
                        name: nameController.text,
                        description: descriptionController.text.isNotEmpty
                            ? descriptionController.text
                            : null,
                        weight: 1.0,
                        color: selectedColor,
                        categoryType: widget.categoryType ??
                            'habit', // Default to habit if not specified
                      );
                      Navigator.of(context).pop(newCategoryRef.id);
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
                  } finally {
                    if (mounted) {
                      setState(() {
                        _isValidating = false;
                      });
                    }
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.buttonRadius),
            ),
            elevation: 0,
          ),
          child: Text(
            isEdit ? 'Update' : 'Create',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
