// FrameWalk - Route Manager
//
// Manages walking routes and their photography stops.
// Supports adding, retrieving, and removing routes.

// Represents a walking route with photography stops.
class WalkingRoute {
  final String id;
  final String name;
  final List<String> stopIds;

  WalkingRoute({
    required this.id,
    required this.name,
    required List<String> stopIds,
  }) : stopIds = List.unmodifiable(stopIds);
}

// Manages walking routes for the FrameWalk application.
class RouteManager {
  // Stores routes using their unique IDs.
  final Map<String, WalkingRoute> _routes = {};

  // Adds a new walking route.
  void addRoute(WalkingRoute route) {
    // Validate route ID.
    if (route.id.trim().isEmpty) {
      throw ArgumentError('Route ID cannot be empty');
    }

    // Validate route name.
    if (route.name.trim().isEmpty) {
      throw ArgumentError('Route name cannot be empty');
    }

    // Prevent duplicate route IDs.
    if (_routes.containsKey(route.id)) {
      throw ArgumentError('Route already exists');
    }

    // Store the route.
    _routes[route.id] = route;
  }

  // Retrieves a route using its unique ID.
  // Returns null if the route does not exist.
  WalkingRoute? getRoute(String routeId) {
    if (routeId.trim().isEmpty) {
      throw ArgumentError('Route ID cannot be empty');
    }

    return _routes[routeId];
  }

  // Returns all available walking routes.
  List<WalkingRoute> getAllRoutes() {
    return List.unmodifiable(_routes.values);
  }

  // Retrieves photography stop IDs for a selected route.
  // Returns an empty list if the route does not exist.
  List<String> getStopsForRoute(String routeId) {
    final route = getRoute(routeId);

    if (route == null) {
      return [];
    }

    return route.stopIds;
  }

  // Removes an existing route.
  // Returns true if the route was removed.
  // Returns false if the route does not exist.
  bool removeRoute(String routeId) {
    if (routeId.trim().isEmpty) {
      throw ArgumentError('Route ID cannot be empty');
    }

    return _routes.remove(routeId) != null;
  }
}
