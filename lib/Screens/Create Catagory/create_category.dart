import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

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
  String selectedColor = '#2196F3';
  List<CategoryRecord> existingCategories = [];
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    // Prefill if editing
    nameController = TextEditingController(text: widget.category?.name ?? "");
    descriptionController =
        TextEditingController(text: widget.category?.description ?? "");
    weight = widget.category?.weight.round() ?? 1;
    selectedColor = widget.category?.color.isNotEmpty == true
        ? widget.category!.color
        : '#2196F3';
    _loadExistingCategories();
  }

  Future<void> _loadExistingCategories() async {
    try {
      final fetchedCategories =
      await queryCategoriesRecordOnce(userId: currentUserUid);
      setState(() {
        existingCategories = fetchedCategories;
      });
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
    final isEdit = widget.category != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Category' : 'Create New Category'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Category Name *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Weight: $weight')),
                Expanded(
                  child: Slider(
                    value: weight.toDouble(),
                    min: 1.0,
                    max: 3.0,
                    divisions: 2,
                    onChanged: (value) {
                      setState(() {
                        weight = value.round();
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Color'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                '#2196F3',
                '#4CAF50',
                '#FF9800',
                '#F44336',
                '#9C27B0',
                '#607D8B',
              ].map((color) {
                final isSelected = selectedColor == color;
                return GestureDetector(
                  onTap: () => setState(() => selectedColor = color),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(int.parse(color.replaceFirst('#', '0xFF'))),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? FlutterFlowTheme.of(context).accent1
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isValidating ? null : () async {
            if (nameController.text.isEmpty) return;

            setState(() {
              _isValidating = true;
            });

            try {
              // Get fresh categories from database
              final freshCategories = await queryCategoriesRecordOnce(userId: currentUserUid);

              // Check for duplicate names, but exclude the current category when editing
              final newName = nameController.text.trim().toLowerCase();
              final nameExists = freshCategories.any((cat) {
                // Skip the current category when editing
                if (isEdit && cat.reference.id == widget.category!.reference.id) {
                  return false;
                }
                final existingName = cat.name.trim().toLowerCase();
                return existingName == newName;
              });

              if (nameExists) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Category with this name already exists!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                setState(() {
                  _isValidating = false;
                });
                return;
              }
              if (isEdit) {
                await updateCategory(
                  categoryId: widget.category!.reference.id,
                  name: nameController.text,
                  description: descriptionController.text.isNotEmpty
                      ? descriptionController.text
                      : null,
                  weight: weight.toDouble(),
                  color: selectedColor,
                  categoryType: widget.categoryType, // Only update if provided
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Category "${nameController.text}" updated successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } else {
                // ✅ Create new
                await createCategory(
                  name: nameController.text,
                  description: descriptionController.text.isNotEmpty
                      ? descriptionController.text
                      : null,
                  weight: weight.toDouble(),
                  color: selectedColor,
                  categoryType: widget.categoryType ??
                      'habit', // Default to habit if not specified
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Category "${nameController.text}" created successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }

              Navigator.of(context).pop();
            } catch (e) {
              if (mounted) {
                // Check if it's a duplicate name error from backend
                final errorMessage = e.toString();
                if (errorMessage.contains('already exists')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Category with this name already exists!'),
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
          child: Text(isEdit ? 'Update' : 'Create'),
        ),
      ],
    );
  }
}
