import 'package:google_maps_flutter/google_maps_flutter.dart';

//can change this
class RouteStop {
  final String id;
  final String name;
  final String prompt;

  // Coordinates for displaying this stop on the map.
  final double latitude;
  final double longitude;

  const RouteStop({
    required this.id,
    required this.name,
    required this.prompt,
    required this.latitude,
    required this.longitude,
  });
}

//separates routes from points for more accurate routes
class Route {
  final List<RouteStop> route_stops;
  final List<LatLng> path;

  const Route({
    required this.route_stops,
    required this.path,
  });
}