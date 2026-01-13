import 'package:flutter/widgets.dart';

/// Shared route observer for widgets that need to react to navigation events.
final RouteObserver<ModalRoute<void>> globalRouteObserver =
    RouteObserver<ModalRoute<void>>();

