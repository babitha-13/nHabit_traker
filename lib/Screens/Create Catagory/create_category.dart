import 'package:flutter/material.dart';
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
          onPressed: () async {
            if (nameController.text.isEmpty) return;

            try {
              if (isEdit) {
                // ✅ Update existing
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
          child: Text(isEdit ? 'Update' : 'Create'),
        ),
      ],
    );
  }
}
