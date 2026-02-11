import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/global_route_observer.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';

/// Reusable Search FAB component that displays at bottom-left
/// Opens a bottom sheet modal for search input
class SearchFAB extends StatefulWidget {
  final String? heroTag;
  const SearchFAB({super.key, this.heroTag});

  @override
  State<SearchFAB> createState() => _SearchFABState();
}

class _SearchFABState extends State<SearchFAB> with RouteAware {
  PersistentBottomSheetController? _bottomSheetController;
  TextEditingController? _textController;
  bool _isDisposed = false;
  ModalRoute<dynamic>? _subscribedRoute;
  bool _isSearchOpen = false;
  // Store stable identifier for hero tag to ensure uniqueness per widget instance
  late final String _stableIdentifier;

  void _updateSearchOpenState(bool value) {
    _isSearchOpen = value;
    SearchStateManager().setSearchOpen(value);
  }

  void _showSearchBottomSheet(BuildContext context) {
    // Close existing bottom sheet if open
    _closeBottomSheet();

    final searchManager = SearchStateManager();
    _textController = TextEditingController(text: searchManager.currentQuery);

    // Use persistent bottom sheet (non-modal) to allow background interaction
    _bottomSheetController = Scaffold.of(context).showBottomSheet(
      backgroundColor: Colors.transparent,
      enableDrag: false,
      (context) => _SearchBottomSheet(
        controller: _textController!,
        onRequestClose: _closeBottomSheet,
      ),
    );

    if (mounted && !_isDisposed) {
      setState(() {
        _updateSearchOpenState(true);
      });
    } else {
      _updateSearchOpenState(true);
    }

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
        _updateSearchOpenState(false);
      });
    } else {
      _bottomSheetController = null;
      _updateSearchOpenState(false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeToRouteObserver();
    _checkAndCloseIfRouteInactive();
  }

  @override
  void initState() {
    super.initState();
    // Use a static counter combined with object identity for stability during hot reload
    // This ensures each widget instance gets a unique tag even during hot reload
    _stableIdentifier = '${widget.hashCode}_${Object.hash(widget.key, runtimeType)}';
    NotificationCenter.addObserver(this, 'closeSearch', (_) {
      if (_isSearchOpen && mounted) {
        _closeBottomSheet();
        _handleBottomSheetClosed();
      }
    });
  }

  void _subscribeToRouteObserver() {
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (_subscribedRoute == route) return;
    if (_subscribedRoute != null) {
      globalRouteObserver.unsubscribe(this);
    }
    _subscribedRoute = route;
    globalRouteObserver.subscribe(this, route);
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
    globalRouteObserver.unsubscribe(this);
    _isDisposed = true;
    // Close bottom sheet if still open when widget is disposed
    _closeBottomSheet();
    _textController?.dispose();
    super.dispose();
  }

  @override
  void didPushNext() {
    _closeBottomSheet();
  }

  @override
  Widget build(BuildContext context) {
    if (_isSearchOpen) {
      return const SizedBox.shrink();
    }
    // Check if route is still active on each build (only if bottom sheet is open)
    if (_bottomSheetController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _bottomSheetController != null) {
          _checkAndCloseIfRouteInactive();
        }
      });
    }

    final theme = FlutterFlowTheme.of(context);
    // Use provided heroTag directly if available (should be unique per page)
    // Otherwise use stable identifier to ensure uniqueness
    // During hot reload, the widget's hash may change, but the provided heroTag remains stable
    final uniqueHeroTag = widget.heroTag ?? 'search_fab_$_stableIdentifier';
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
  final VoidCallback onRequestClose;

  const _SearchBottomSheet({
    required this.controller,
    required this.onRequestClose,
  });

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
    return WillPopScope(
      onWillPop: () async {
        widget.onRequestClose();
        return false;
      },
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            width: double.infinity,
            child: TextField(
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
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.surfaceBorderColor.withOpacity(0.4),
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.primary,
                    width: 1.5,
                  ),
                ),
                filled: true,
                fillColor: theme.secondaryBackground,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                isDense: true,
              ),
              onChanged: _onTextChanged,
              textInputAction: TextInputAction.search,
            ),
          ),
        ),
      ),
    );
  }
}
