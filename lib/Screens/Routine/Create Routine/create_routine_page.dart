import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Item_component/item_dotted_line_painter.dart';
import 'package:habit_tracker/Screens/Routine/Create Routine/Logic/create_routine_page_logic.dart';

class CreateRoutinePage extends StatefulWidget {
  final RoutineRecord? existingRoutine;
  const CreateRoutinePage({
    Key? key,
    this.existingRoutine,
  }) : super(key: key);
  @override
  _CreateRoutinePageState createState() => _CreateRoutinePageState();
}

class _CreateRoutinePageState extends State<CreateRoutinePage>
    with CreateRoutinePageLogic {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existingRoutine != null) {
      fetchLatestRoutineAndLoadActivities(widget.existingRoutine).then((routineName) {
        if (mounted && routineName != null) {
          _nameController.text = routineName;
        } else if (mounted) {
          _nameController.text = widget.existingRoutine!.name;
        }
      });
    } else {
      loadActivities();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildSimplifiedItemCard(ActivityRecord activity, bool isSelected) {
    final theme = FlutterFlowTheme.of(context);
    final stripeColor = getStripeColor(activity);
    final isessential = activity.categoryType == 'essential';

    return GestureDetector(
      onLongPress: isessential ? () => showDeleteConfirmation(activity) : null,
      onTap: () {
        if (isSelected) {
          removeItem(activity);
        } else {
          addItem(activity);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          gradient: theme.neumorphicGradientSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.cardBorderColor,
            width: 1,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              isessential
                  ? SizedBox(
                      width: 3,
                      child: CustomPaint(
                        size: const Size(3, double.infinity),
                        painter: DottedLinePainter(color: stripeColor),
                      ),
                    )
                  : Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: stripeColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
              const SizedBox(width: 5),
              SizedBox(
                width: 36,
                child: Center(
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: stripeColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      activity.categoryType == 'habit'
                          ? Icons.flag
                          : activity.categoryType == 'task'
                              ? Icons.assignment
                              : Icons.monitor_heart,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      activity.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyMedium.override(
                        fontFamily: 'Readex Pro',
                        fontWeight: FontWeight.w600,
                        color: theme.primaryText,
                      ),
                    ),
                    if (activity.categoryName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        activity.categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall.override(
                          fontFamily: 'Readex Pro',
                          color: theme.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (isSelected) {
                        removeItem(activity);
                      } else {
                        addItem(activity);
                      }
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color:
                              isSelected ? theme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: isSelected
                              ? null
                              : Border.all(
                                  color: stripeColor,
                                  width: 2,
                                ),
                        ),
                        child: Icon(
                          isSelected ? Icons.check : Icons.add,
                          size: 18,
                          color: isSelected ? Colors.white : stripeColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final bottomSafePadding = MediaQuery.of(context).viewPadding.bottom;
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && isKeyboardVisible != wasKeyboardVisible) {
        setState(() {
          isSelectedItemsExpanded = !isKeyboardVisible;
          wasKeyboardVisible = isKeyboardVisible;
        });
      }
    });
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primaryBackground,
        elevation: 0,
        title: Text(
          widget.existingRoutine != null ? 'Edit Routine' : 'Create Routine',
          style: theme.titleMedium.override(
            fontFamily: 'Readex Pro',
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              decoration: BoxDecoration(
                gradient: theme.primaryButtonGradient,
                borderRadius: BorderRadius.circular(theme.buttonRadius),
              ),
              child: TextButton(
                onPressed: isSaving ? null : () => saveRoutine(_nameController),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Save',
                        style: theme.bodyMedium.override(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: BoxDecoration(
                gradient: theme.neumorphicGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border.all(
                  color: theme.surfaceBorderColor,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, -2),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomSafePadding),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Routine Name *',
                              style: theme.bodySmall.override(
                                color: theme.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: theme.tertiary.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: theme.surfaceBorderColor,
                                  width: 1,
                                ),
                              ),
                              child: TextFormField(
                                controller: _nameController,
                                style: theme.bodyMedium,
                                decoration: InputDecoration(
                                  hintText: 'Enter routine name',
                                  hintStyle: TextStyle(
                                    color: theme.secondaryText,
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter a routine name';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add Items',
                              style: theme.titleMedium.override(
                                fontFamily: 'Readex Pro',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.tertiary.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: theme.surfaceBorderColor,
                                        width: 1,
                                      ),
                                    ),
                                    child: TextField(
                                      controller: _searchController,
                                      style: theme.bodyMedium,
                                      decoration: InputDecoration(
                                        hintText:
                                            'Search habits, tasks, or non-produc...',
                                        hintStyle: TextStyle(
                                          color: theme.secondaryText,
                                          fontSize: 14,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                vertical: 8),
                                        prefixIcon: Icon(
                                          Icons.search,
                                          color: theme.secondaryText,
                                          size: 20,
                                        ),
                                        prefixIconConstraints:
                                            const BoxConstraints(
                                          minWidth: 40,
                                          minHeight: 20,
                                        ),
                                      ),
                                      onChanged: filterActivities,
                                    ),
                                  ),
                                ),
                                if (widget.existingRoutine == null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: theme.primaryButtonGradient,
                                      borderRadius: BorderRadius.circular(
                                          theme.buttonRadius),
                                    ),
                                    child: ElevatedButton.icon(
                                      onPressed: () => createNewEssentialItem((_) {}),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                      ),
                                      icon: const Icon(Icons.add,
                                          color: Colors.white),
                                      label: Text(
                                        'New Item',
                                        style: theme.bodyMedium.override(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: filteredActivities.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 64,
                                      color: theme.secondaryText,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No items found',
                                      style: theme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Try a different search term or create a new item',
                                      style: theme.bodyMedium,
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: filteredActivities.length,
                                itemBuilder: (context, index) {
                                  final activity = filteredActivities[index];
                                  final isSelected = selectedItems.any(
                                    (item) =>
                                        item.reference.id ==
                                        activity.reference.id,
                                  );
                                  return _buildSimplifiedItemCard(
                                      activity, isSelected);
                                },
                              ),
                      ),
                      if (selectedItems.isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          decoration: BoxDecoration(
                            gradient: theme.neumorphicGradientSubtle,
                            border: Border(
                              top: BorderSide(
                                color: theme.surfaceBorderColor,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  FocusScope.of(context).unfocus();
                                  setState(() {
                                    isSelectedItemsExpanded =
                                        !isSelectedItemsExpanded;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Selected Items (${selectedItems.length})',
                                          style: theme.titleMedium.override(
                                            fontFamily: 'Readex Pro',
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        isSelectedItemsExpanded
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        color: theme.secondaryText,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedCrossFade(
                                duration: const Duration(milliseconds: 300),
                                crossFadeState: isSelectedItemsExpanded
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                firstChild: const SizedBox.shrink(),
                                secondChild: Container(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Drag to reorder items in the routine',
                                        style: theme.bodySmall.override(
                                          color: theme.secondaryText,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height:
                                            260, // Max height for selected items
                                        child: ReorderableListView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          itemCount: selectedItems.length,
                                          onReorder: reorderItems,
                                          itemBuilder: (context, index) {
                                            final activity =
                                                selectedItems[index];
                                            final stripeColor =
                                                getStripeColor(activity);
                                            final isessential =
                                                activity.categoryType ==
                                                    'essential';
                                            return Container(
                                              key: ValueKey(
                                                  activity.reference.id),
                                              margin: const EdgeInsets.only(
                                                  bottom: 4),
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      6, 6, 6, 6),
                                              decoration: BoxDecoration(
                                                gradient: theme
                                                    .neumorphicGradientSubtle,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: theme.cardBorderColor,
                                                  width: 1,
                                                ),
                                              ),
                                              child: IntrinsicHeight(
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    isessential
                                                        ? SizedBox(
                                                            width: 3,
                                                            child: CustomPaint(
                                                              size: const Size(
                                                                  3,
                                                                  double
                                                                      .infinity),
                                                              painter:
                                                                  DottedLinePainter(
                                                                      color:
                                                                          stripeColor),
                                                            ),
                                                          )
                                                        : Container(
                                                            width: 3,
                                                            decoration:
                                                                BoxDecoration(
                                                              color:
                                                                  stripeColor,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          2),
                                                            ),
                                                          ),
                                                    const SizedBox(width: 5),
                                                    SizedBox(
                                                      width: 32,
                                                      child: Center(
                                                        child: Container(
                                                          width: 24,
                                                          height: 24,
                                                          decoration:
                                                              BoxDecoration(
                                                            color: stripeColor,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                          ),
                                                          child: Icon(
                                                            activity.categoryType ==
                                                                    'habit'
                                                                ? Icons.flag
                                                                : activity.categoryType ==
                                                                        'task'
                                                                    ? Icons
                                                                        .assignment
                                                                    : Icons
                                                                        .playlist_add,
                                                            color: Colors.white,
                                                            size: 16,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Text(
                                                            activity.name,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: theme
                                                                .bodyMedium
                                                                .override(
                                                              fontFamily:
                                                                  'Readex Pro',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: theme
                                                                  .primaryText,
                                                            ),
                                                          ),
                                                          if (activity
                                                              .categoryName
                                                              .isNotEmpty) ...[
                                                            const SizedBox(
                                                                height: 2),
                                                            Text(
                                                              activity
                                                                  .categoryName,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: theme
                                                                  .bodySmall
                                                                  .override(
                                                                fontFamily:
                                                                    'Readex Pro',
                                                                color: theme
                                                                    .secondaryText,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                    Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Icon(
                                                          Icons.drag_handle,
                                                          color: theme
                                                              .secondaryText,
                                                          size: 20,
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
