import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/utils/neumorphic_container.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Progress/weekly_habit_item.dart';

class WeeklyCategoryGroup extends StatefulWidget {
  final CategoryRecord category;
  final List<HabitRecord> habits;
  final Future<void> Function() onRefresh;

  const WeeklyCategoryGroup({
    super.key,
    required this.category,
    required this.habits,
    required this.onRefresh,
  });

  @override
  State<WeeklyCategoryGroup> createState() => _WeeklyCategoryGroupState();
}

class _WeeklyCategoryGroupState extends State<WeeklyCategoryGroup> {
  bool _isExpanded = true;
  int? _weightOverride;

  @override
  Widget build(BuildContext context) {
    return NeumorphicContainer(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      radius: 16,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.category.name,
                            overflow: TextOverflow.ellipsis,
                            style: FlutterFlowTheme.of(context)
                                .titleMedium
                                .override(
                                  fontFamily: 'Readex Pro',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Color(int.parse(widget.category.color
                                .replaceFirst('#', '0xFF'))),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '(${widget.habits.length})',
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                          fontFamily: 'Readex Pro',
                          color: FlutterFlowTheme.of(context).secondaryText,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 2.5,),
                      _buildCategoryWeightStars(),
                      const SizedBox(width: 2.5,),
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: FlutterFlowTheme.of(context).secondaryText,
                        size: 20,
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            ...widget.habits.map((habit) => WeeklyHabitItem(
                  key: Key('w_${habit.reference.id}'),
                  habit: habit,
                  categoryColorHex: widget.category.color,
                  onRefresh: widget.onRefresh,
                  onHabitDeleted: (deleted) {
                    setState(() {
                      widget.habits.removeWhere(
                          (h) => h.reference.id == deleted.reference.id);
                    });
                  },
                )),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryWeightStars() {
    final int current =
        (_weightOverride ?? widget.category.weight.round()).clamp(1, 3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final level = i + 1;
        final filled = current >= level;
        return GestureDetector(
          onTap: () async{
                try {
                  final next = current % 3 + 1;
                  await updateCategory(
                    categoryId: widget.category.reference.id,
                    weight: next.toDouble(),
                  );
                  if (mounted) setState(() => _weightOverride = next);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating category weight: $e')),
                  );
                }
          },
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: 24,
              color: filled
                  ? Colors.amber
                  : FlutterFlowTheme.of(context).secondaryText.withOpacity(0.35),
          ),
        );
      }),
    );
  }
}
