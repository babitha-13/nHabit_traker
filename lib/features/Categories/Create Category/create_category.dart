import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/category_color_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Shared/polished_dialog.dart';
import 'package:habit_tracker/Screens/Categories/Create Category/Logic/create_category_logic.dart';

class CreateCategory extends StatefulWidget {
  final CategoryRecord? category;
  final String? categoryType; // 'habit' or 'task'
  const CreateCategory({super.key, this.category, this.categoryType});
  @override
  State<CreateCategory> createState() => _CreateCategoryState();
}

class _CreateCategoryState extends State<CreateCategory>
    with CreateCategoryLogic {
  late TextEditingController nameController;
  late TextEditingController descriptionController;
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
    loadExistingCategories();
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
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
        absorbing: isValidating,
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
            if (isValidating)
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
              isValidating ? null : () => Navigator.of(context).pop(false),
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
          onPressed: isValidating
              ? null
              : () async {
                  final result = await saveCategory(
                    nameController: nameController,
                    descriptionController: descriptionController,
                    category: widget.category,
                    categoryType: widget.categoryType,
                    isEdit: isEdit,
                  );
                  if (mounted && result != null) {
                    Navigator.of(context).pop(result);
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
