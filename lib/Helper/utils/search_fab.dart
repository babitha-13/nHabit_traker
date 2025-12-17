import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

/// Reusable Search FAB component that displays at bottom-left
/// Opens a bottom sheet modal for search input
class SearchFAB extends StatelessWidget {
  final String? heroTag;
  const SearchFAB({super.key, this.heroTag});

  void _showSearchBottomSheet(BuildContext context) {
    final searchManager = SearchStateManager();
    final controller = TextEditingController(text: searchManager.currentQuery);
    
    // Use persistent bottom sheet (non-modal) to allow background interaction
    Scaffold.of(context).showBottomSheet(
      backgroundColor: Colors.transparent,
      enableDrag: true,
      (context) => _SearchBottomSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    // Use hashCode to ensure unique heroTag per instance to avoid conflicts during navigation
    final uniqueHeroTag = heroTag ?? 'search_fab_${hashCode}';
    return Positioned(
      left: 16,
      bottom: 16,
      child: FloatingActionButton(
        heroTag: uniqueHeroTag,
        onPressed: () => _showSearchBottomSheet(context),
        backgroundColor: theme.primary,
        child: const Icon(Icons.search, color: Colors.white),
        tooltip: 'Search',
      ),
    );
  }
}

/// Bottom sheet modal for search input
class _SearchBottomSheet extends StatefulWidget {
  final TextEditingController controller;

  const _SearchBottomSheet({required this.controller});

  @override
  State<_SearchBottomSheet> createState() => _SearchBottomSheetState();
}

class _SearchBottomSheetState extends State<_SearchBottomSheet> {
  final _searchManager = SearchStateManager();
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    // Listen to text changes to update clear button visibility
    widget.controller.addListener(_onTextControllerChanged);
    // Auto-focus after the bottom sheet is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextControllerChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextControllerChanged() {
    setState(() {
      // Trigger rebuild to update clear button visibility
    });
  }

  void _onTextChanged(String value) {
    _searchManager.updateQuery(value);
  }

  void _clearSearch() {
    widget.controller.clear();
    _searchManager.clearQuery();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: theme.secondaryText.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Search input field
          TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: widget.controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clearSearch,
                      tooltip: 'Clear',
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: theme.secondaryBackground,
            ),
            onChanged: _onTextChanged,
            textInputAction: TextInputAction.search,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

