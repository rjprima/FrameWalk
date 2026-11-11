
  // FrameWalk - Route Manager
  // Stores route definitions and provides route operations.
  // A Provider can wrap RouteManager to notify the UI about changes.

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
        throw ArgumentError(
          'Distance must be a finite nonnegative number',
        );
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

    // Add a new walking route.
    void addRoute(WalkingRoute route) {
      _validateRoute(route);

      if (_routes.containsKey(route.id)) {
        throw ArgumentError('Route already exists');
      }

      _routes[route.id] = route;
    }

    // Retrieve a route using its ID.
    WalkingRoute? getRoute(String routeId) {
      _validateId(routeId);
      return _routes[routeId];
    }

    // Retrieve every available route.
    List<WalkingRoute> getAllRoutes() {
      return List.unmodifiable(_routes.values);
    }

    // Retrieve photography stop IDs for a route.
    List<String> getStopsForRoute(String routeId) {
      return getRoute(routeId)?.stopIds ?? const [];
    }

    // Remove a route.
    // Returns false when the route does not exist.
    bool removeRoute(String routeId) {
      _validateId(routeId);
      return _routes.remove(routeId) != null;
    }

    // Replace an existing route with updated information.
    bool updateRoute(WalkingRoute route) {
      _validateRoute(route);

      if (!_routes.containsKey(route.id)) {
        return false;
      }

      _routes[route.id] = route;
      return true;
    }

    // Set the bookmark state for a route.
    bool setBookmarked(String routeId, bool bookmarked) {
      final route = getRoute(routeId);

      if (route == null) {
        return false;
      }

      _routes[routeId] = route.copyWith(
        isBookmarked: bookmarked,
      );

      return true;
    }

    // Switch a route between bookmarked and unbookmarked.
    bool toggleBookmark(String routeId) {
      final route = getRoute(routeId);

      if (route == null) {
        return false;
      }

      return setBookmarked(
        routeId,
        !route.isBookmarked,
      );
    }

    // Retrieve only bookmarked routes.
    List<WalkingRoute> getBookmarkedRoutes() {
      return List.unmodifiable(
        _routes.values.where(
          (route) => route.isBookmarked,
        ),
      );
    }

    // Filter routes by scenery tags.
    // A route must contain every requested tag.
    // Matching is case-insensitive.
    List<WalkingRoute> filterBySceneryTags(
      List<String> tags,
    ) {
      final requested = tags
          .map((tag) => tag.trim().toLowerCase())
          .where((tag) => tag.isNotEmpty)
          .toSet();

      return List.unmodifiable(
        _routes.values.where((route) {
          final available = route.sceneryTags
              .map((tag) => tag.trim().toLowerCase())
              .toSet();

          return available.containsAll(requested);
        }),
      );
    }

    // NEW: Search routes by name or description.
    // Matching is case-insensitive.
    // An empty search returns all routes.
    List<WalkingRoute> searchRoutes(String query) {
      final search = query.trim().toLowerCase();

      if (search.isEmpty) {
        return getAllRoutes();
      }

      return List.unmodifiable(
        _routes.values.where((route) {
          return route.name.toLowerCase().contains(search) ||
              route.description.toLowerCase().contains(search);
        }),
      );
    }

    // Validate route IDs.
    void _validateId(String id) {
      if (id.trim().isEmpty) {
        throw ArgumentError('Route ID cannot be empty');
      }
    }

    // Validate route information.
    void _validateRoute(WalkingRoute route) {
      _validateId(route.id);

      if (route.name.trim().isEmpty) {
        throw ArgumentError('Route name cannot be empty');
      }
    }
  }

