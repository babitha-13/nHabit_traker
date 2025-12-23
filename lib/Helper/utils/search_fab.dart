import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

/// Reusable Search FAB component that displays at bottom-left
/// Opens a bottom sheet modal for search input
class SearchFAB extends StatefulWidget {
  final String? heroTag;
  const SearchFAB({super.key, this.heroTag});

  @override
  State<SearchFAB> createState() => _SearchFABState();
}

class _SearchFABState extends State<SearchFAB> {
  PersistentBottomSheetController? _bottomSheetController;
  TextEditingController? _textController;
  bool _isDisposed = false;

  void _showSearchBottomSheet(BuildContext context) {
    // Close existing bottom sheet if open
    _closeBottomSheet();
    
    final searchManager = SearchStateManager();
    _textController = TextEditingController(text: searchManager.currentQuery);
    
    // Use persistent bottom sheet (non-modal) to allow background interaction
    _bottomSheetController = Scaffold.of(context).showBottomSheet(
      backgroundColor: Colors.transparent,
      enableDrag: true,
      (context) => _SearchBottomSheet(controller: _textController!),
    );
    
    // Listen for when the bottom sheet closes and clear search query
    _bottomSheetController?.closed.then((_) {
      _handleBottomSheetClosed();
    });
  }

  void _closeBottomSheet() {
    if (_bottomSheetController != null) {
      try {
        _bottomSheetController!.close();
      } catch (e) {
        // Ignore errors if already closed
      }
      _bottomSheetController = null;
    }
  }

  void _handleBottomSheetClosed() {
    if (_isDisposed) return;
    
    final searchManager = SearchStateManager();
    searchManager.clearQuery();
    
    // Dispose the controller to prevent memory leaks
    // Use a post-frame callback to ensure the bottom sheet widget is fully disposed first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed && _textController != null) {
        try {
          _textController!.dispose();
        } catch (e) {
          // Ignore errors if already disposed
        }
        _textController = null;
      }
    });
    
    if (mounted && !_isDisposed) {
      setState(() {
        _bottomSheetController = null;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAndCloseIfRouteInactive();
  }

  void _checkAndCloseIfRouteInactive() {
    if (_bottomSheetController != null) {
      final route = ModalRoute.of(context);
      if (route == null || !route.isCurrent) {
        _closeBottomSheet();
        _handleBottomSheetClosed();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Close bottom sheet if still open when widget is disposed
    _closeBottomSheet();
    _textController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check if route is still active on each build (only if bottom sheet is open)
    if (_bottomSheetController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _bottomSheetController != null) {
          _checkAndCloseIfRouteInactive();
        }
      });
    }
    
    final theme = FlutterFlowTheme.of(context);
    // Use hashCode to ensure unique heroTag per instance to avoid conflicts during navigation
    final uniqueHeroTag = widget.heroTag ?? 'search_fab_${hashCode}';
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
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.3,
        ),
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 12,
          right: 12,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onChanged: _onTextChanged,
              textInputAction: TextInputAction.search,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

