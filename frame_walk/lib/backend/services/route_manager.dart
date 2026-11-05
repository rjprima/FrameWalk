// FrameWalk - Route Manager
// Stores route definitions and provides basic route operations.
// A Provider can wrap RouteManager to notify the UI about bookmark changes.

class WalkingRoute {
  final String id;
  final String name;
  final String description;
  final int estimatedMinutes;
  final double distanceMiles;
  final List<String> stopIds;
  final List<String> sceneryTags;
  final bool isBookmarked;

  WalkingRoute({
    required this.id,
    required this.name,
    required List<String> stopIds,
    this.description = '',
    this.estimatedMinutes = 0,
    this.distanceMiles = 0.0,
    List<String> sceneryTags = const [],
    this.isBookmarked = false,
  })  : stopIds = List.unmodifiable(stopIds),
        sceneryTags = List.unmodifiable(sceneryTags) {
    if (estimatedMinutes < 0) {
      throw ArgumentError('Estimated minutes cannot be negative');
    }
    if (!distanceMiles.isFinite || distanceMiles < 0) {
      throw ArgumentError('Distance must be a finite nonnegative number');
    }
  }

  WalkingRoute copyWith({
    String? name,
    String? description,
    int? estimatedMinutes,
    double? distanceMiles,
    List<String>? stopIds,
    List<String>? sceneryTags,
    bool? isBookmarked,
  }) {
    return WalkingRoute(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      distanceMiles: distanceMiles ?? this.distanceMiles,
      stopIds: stopIds ?? this.stopIds,
      sceneryTags: sceneryTags ?? this.sceneryTags,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }
}

class RouteManager {
  final Map<String, WalkingRoute> _routes = {};

  void addRoute(WalkingRoute route) {
    _validateRoute(route);
    if (_routes.containsKey(route.id)) {
      throw ArgumentError('Route already exists');
    }
    _routes[route.id] = route;
  }

  WalkingRoute? getRoute(String routeId) {
    _validateId(routeId);
    return _routes[routeId];
  }

  List<WalkingRoute> getAllRoutes() => List.unmodifiable(_routes.values);

  List<String> getStopsForRoute(String routeId) {
    return getRoute(routeId)?.stopIds ?? const [];
  }

  bool removeRoute(String routeId) {
    _validateId(routeId);
    return _routes.remove(routeId) != null;
  }

  // Replaces a route with updated information. Returns false if not found.
  bool updateRoute(WalkingRoute route) {
    _validateRoute(route);
    if (!_routes.containsKey(route.id)) return false;
    _routes[route.id] = route;
    return true;
  }

  // Bookmark changes are stored in the route model. A UI Provider should
  // call this and notifyListeners() so all screens refresh together.
  bool setBookmarked(String routeId, bool bookmarked) {
    final route = getRoute(routeId);
    if (route == null) return false;
    _routes[routeId] = route.copyWith(isBookmarked: bookmarked);
    return true;
  }

  bool toggleBookmark(String routeId) {
    final route = getRoute(routeId);
    if (route == null) return false;
    return setBookmarked(routeId, !route.isBookmarked);
  }

  List<WalkingRoute> getBookmarkedRoutes() => List.unmodifiable(
        _routes.values.where((route) => route.isBookmarked),
      );

  // Matches routes containing every requested scenery tag (case-insensitive).
  List<WalkingRoute> filterBySceneryTags(List<String> tags) {
    final requested = tags.map((tag) => tag.trim().toLowerCase())
        .where((tag) => tag.isNotEmpty).toSet();
    return List.unmodifiable(_routes.values.where((route) {
      final available = route.sceneryTags
          .map((tag) => tag.trim().toLowerCase()).toSet();
      return available.containsAll(requested);
    }));
  }

  void _validateId(String id) {
    if (id.trim().isEmpty) {
      throw ArgumentError('Route ID cannot be empty');
    }
  }

  void _validateRoute(WalkingRoute route) {
    _validateId(route.id);
    if (route.name.trim().isEmpty) {
      throw ArgumentError('Route name cannot be empty');
    }
  }
}
