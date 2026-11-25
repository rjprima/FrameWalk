import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../backend/services/route_manager.dart';
import 'route_stop.dart';

// mock route data to show when opening a route info page
// and to seed RouteProvider until real data exists.
class MockRouteData {
  // Default map center (UW campus).
  static const LatLng uwCampus = LatLng(47.6553, -122.3035);

  // RED SQUARE WALK
  static const List<RouteStop> redSquareStops = [
    RouteStop(
      id: 'red_stop_1',
      name: 'Red Square',
      prompt: 'Capture an interesting pattern in the surrounding architecture.',
      latitude: 47.6559,
      longitude: -122.3078,
    ),
    RouteStop(
      id: 'red_stop_2',
      name: 'Suzzallo Library',
      prompt: 'Find an interesting contrast between light and shadow.',
      latitude: 47.6553,
      longitude: -122.3099,
    ),
    RouteStop(
      id: 'red_stop_3',
      name: 'Drumheller Fountain',
      prompt: 'Photograph a reflection or interesting interaction with water.',
      latitude: 47.6545,
      longitude: -122.3070,
    ),
    RouteStop(
      id: 'red_stop_4',
      name: 'Kane Hall',
      prompt: 'Find an everyday object that tells a story about campus life.',
      latitude: 47.6560,
      longitude: -122.3090,
    ),
  ];

  // UW NATURE WALK
  static const List<RouteStop> uwNatureStops = [
    RouteStop(
      id: 'nature_stop_1',
      name: 'Rainier Vista',
      prompt: 'Capture the relationship between nature and architecture.',
      latitude: 47.6534,
      longitude: -122.3075,
    ),
    RouteStop(
      id: 'nature_stop_2',
      name: 'Gould Hall Garden',
      prompt: 'Find an interesting leaf shape or natural pattern.',
      latitude: 47.6568,
      longitude: -122.3110,
    ),
    RouteStop(
      id: 'nature_stop_3',
      name: 'Quad',
      prompt: 'Photograph something that shows the changing seasons.',
      latitude: 47.6568,
      longitude: -122.3100,
    ),
    RouteStop(
      id: 'nature_stop_4',
      name: 'Sylvan Grove',
      prompt: 'Look for an interesting texture in the trees or landscape.',
      latitude: 47.6578,
      longitude: -122.3120,
    ),
  ];

  // WATERFRONT VIEWS
  static const List<RouteStop> waterfrontStops = [
    RouteStop(
      id: 'water_stop_1',
      name: 'Waterfront Activities Center',
      prompt: 'Capture the colors and movement of the water.',
      latitude: 47.6502,
      longitude: -122.3015,
    ),
    RouteStop(
      id: 'water_stop_2',
      name: 'Union Bay',
      prompt: 'Photograph a reflection on the water.',
      latitude: 47.6495,
      longitude: -122.3000,
    ),
    RouteStop(
      id: 'water_stop_3',
      name: 'Waterfront Path',
      prompt: 'Find an interesting natural shape or silhouette.',
      latitude: 47.6488,
      longitude: -122.3020,
    ),
    RouteStop(
      id: 'water_stop_4',
      name: 'Waterfront Overlook',
      prompt: 'Capture a wide-angle view that shows depth and perspective.',
      latitude: 47.6498,
      longitude: -122.3040,
    ),
  ];

  // ROUTE COORDINATES
  // These coordinates determine the line drawn on Google Maps (Map page and
  // Route Info page both read them via getRoutePoints). Each route is a closed
  // loop that passes through its stops in order, with extra bend points
  // between stops. Same shape as the map-only loops below. The first and last
  // point match, and the points between them draw the path and dots.
  // UI fixtures: illustrative, not verified walking directions.

  static const List<LatLng> redSquareRoutePoints = [
    LatLng(47.6559, -122.3078), // Red Square
    LatLng(47.6558, -122.3089),
    LatLng(47.6553, -122.3099), // Suzzallo Library
    LatLng(47.6547, -122.3086),
    LatLng(47.6545, -122.3070), // Drumheller Fountain
    LatLng(47.6552, -122.3083),
    LatLng(47.6560, -122.3090), // Kane Hall
    LatLng(47.6563, -122.3084),
    LatLng(47.6559, -122.3078), // back to start
  ];

  static const List<LatLng> uwNatureRoutePoints = [
    LatLng(47.6534, -122.3075), // Rainier Vista
    LatLng(47.6548, -122.3095),
    LatLng(47.6568, -122.3110), // Gould Hall Garden
    LatLng(47.6569, -122.3105),
    LatLng(47.6568, -122.3100), // Quad
    LatLng(47.6574, -122.3112),
    LatLng(47.6578, -122.3120), // Sylvan Grove
    LatLng(47.6558, -122.3092),
    LatLng(47.6546, -122.3084),
    LatLng(47.6534, -122.3075), // back to start
  ];

  static const List<LatLng> waterfrontRoutePoints = [
    LatLng(47.6502, -122.3015), // Waterfront Activities Center
    LatLng(47.6499, -122.3006),
    LatLng(47.6495, -122.3000), // Union Bay
    LatLng(47.6490, -122.3009),
    LatLng(47.6488, -122.3020), // Waterfront Path
    LatLng(47.6492, -122.3032),
    LatLng(47.6498, -122.3040), // Waterfront Overlook
    LatLng(47.6501, -122.3029),
    LatLng(47.6502, -122.3015), // back to start
  ];

  // MAP-ONLY CAMPUS LOOPS
  // UI fixtures: replace with the team's curated route coordinates.
  // These paths are illustrative, not verified walking directions.

  static const List<LatLng> burkeLoopPoints = [
    LatLng(47.6605, -122.3115),
    LatLng(47.6604, -122.3095),
    LatLng(47.6597, -122.3088),
    LatLng(47.6586, -122.3090),
    LatLng(47.6583, -122.3108),
    LatLng(47.6592, -122.3117),
    LatLng(47.6605, -122.3115),
  ];

  static const List<LatLng> quadLoopPoints = [
    LatLng(47.6584, -122.3078),
    LatLng(47.6588, -122.3063),
    LatLng(47.6582, -122.3053),
    LatLng(47.6569, -122.3055),
    LatLng(47.6566, -122.3067),
    LatLng(47.6572, -122.3080),
    LatLng(47.6584, -122.3078),
  ];

  static const List<LatLng> drumhellerLoopPoints = [
    LatLng(47.6540, -122.3070),
    LatLng(47.6541, -122.3055),
    LatLng(47.6536, -122.3043),
    LatLng(47.6524, -122.3042),
    LatLng(47.6518, -122.3056),
    LatLng(47.6523, -122.3071),
    LatLng(47.6540, -122.3070),
  ];

  // MAP-ONLY CAMPUS LOOP STOPS
  // UI fixtures: each stop sits on a vertex of its loop's route points.

  static const List<RouteStop> burkeLoopStops = [
    RouteStop(
      id: 'burke_stop_1',
      name: 'Burke Museum',
      prompt: 'Capture the lines and materials of the building facade.',
      latitude: 47.6605,
      longitude: -122.3115,
    ),
    RouteStop(
      id: 'burke_stop_2',
      name: 'Museum Lawn',
      prompt: 'Find an interesting contrast between light and shadow.',
      latitude: 47.6597,
      longitude: -122.3088,
    ),
    RouteStop(
      id: 'burke_stop_3',
      name: 'Stone Pathway',
      prompt: 'Look for a texture or pattern in the ground or walls.',
      latitude: 47.6583,
      longitude: -122.3108,
    ),
    RouteStop(
      id: 'burke_stop_4',
      name: 'Corner Overlook',
      prompt: 'Frame the buildings with something natural in the foreground.',
      latitude: 47.6592,
      longitude: -122.3117,
    ),
  ];

  static const List<RouteStop> quadLoopStops = [
    RouteStop(
      id: 'quad_stop_1',
      name: 'Quad Entrance',
      prompt: 'Capture the relationship between nature and architecture.',
      latitude: 47.6584,
      longitude: -122.3078,
    ),
    RouteStop(
      id: 'quad_stop_2',
      name: 'Cherry Trees',
      prompt: 'Find an interesting branch shape or natural pattern.',
      latitude: 47.6582,
      longitude: -122.3053,
    ),
    RouteStop(
      id: 'quad_stop_3',
      name: 'Quad Lawn',
      prompt: 'Photograph something that shows the changing seasons.',
      latitude: 47.6566,
      longitude: -122.3067,
    ),
    RouteStop(
      id: 'quad_stop_4',
      name: 'Quad Corner',
      prompt: 'Find an everyday object that tells a story about campus life.',
      latitude: 47.6572,
      longitude: -122.3080,
    ),
  ];

  static const List<RouteStop> drumhellerLoopStops = [
    RouteStop(
      id: 'drum_stop_1',
      name: 'Fountain Overlook',
      prompt: 'Photograph a reflection or interesting interaction with water.',
      latitude: 47.6540,
      longitude: -122.3070,
    ),
    RouteStop(
      id: 'drum_stop_2',
      name: 'Garden Path',
      prompt: 'Look for an interesting texture in the plants or landscape.',
      latitude: 47.6536,
      longitude: -122.3043,
    ),
    RouteStop(
      id: 'drum_stop_3',
      name: 'Lower Lawn',
      prompt: 'Capture a wide-angle view that shows depth and perspective.',
      latitude: 47.6524,
      longitude: -122.3042,
    ),
    RouteStop(
      id: 'drum_stop_4',
      name: 'Reflecting Spot',
      prompt: 'Find an interesting natural shape or silhouette.',
      latitude: 47.6518,
      longitude: -122.3056,
    ),
  ];

  // ROUTE DEFINITIONS
  // Used to seed RouteProvider. `final` (not const) because WalkingRoute
  // validates its fields in its constructor. stopIds come from the stop
  // lists above so the two can't drift apart.
  static final List<WalkingRoute> routes = [
    WalkingRoute(
      id: '1',
      name: 'Red Square Walk',
      stopIds: redSquareStops.map((s) => s.id).toList(),
      estimatedMinutes: 10,
      distanceMiles: 0.5,
      sceneryTags: const ['Architecture', 'Urban'],
    ),
    WalkingRoute(
      id: '2',
      name: 'UW Nature Walk',
      stopIds: uwNatureStops.map((s) => s.id).toList(),
      estimatedMinutes: 20,
      distanceMiles: 1.2,
      sceneryTags: const ['Nature', 'Urban'],
    ),
    WalkingRoute(
      id: '3',
      name: 'Waterfront Views',
      stopIds: waterfrontStops.map((s) => s.id).toList(),
      estimatedMinutes: 30,
      distanceMiles: 1.8,
      sceneryTags: const ['Water', 'Nature'],
    ),
    WalkingRoute(
      id: 'map-burke',
      name: 'Burke Museum Loop',
      stopIds: burkeLoopStops.map((s) => s.id).toList(),
      estimatedMinutes: 12,
      distanceMiles: 0.5,
      sceneryTags: const ['Architecture', 'Urban'],
    ),
    WalkingRoute(
      id: 'map-quad',
      name: 'UW Quad Walk',
      stopIds: quadLoopStops.map((s) => s.id).toList(),
      estimatedMinutes: 15,
      distanceMiles: 0.6,
      sceneryTags: const ['Nature', 'Architecture'],
    ),
    WalkingRoute(
      id: 'map-drumheller',
      name: 'Drumheller Fountain Loop',
      stopIds: drumhellerLoopStops.map((s) => s.id).toList(),
      estimatedMinutes: 25,
      distanceMiles: 1.0,
      sceneryTags: const ['Water', 'Nature'],
    ),
  ];

  // GET STOPS FOR A ROUTE
  static List<RouteStop> getStops(String routeId) {
    switch (routeId) {
      case '1':
        return redSquareStops;
      case '2':
        return uwNatureStops;
      case '3':
        return waterfrontStops;
      case 'map-burke':
        return burkeLoopStops;
      case 'map-quad':
        return quadLoopStops;
      case 'map-drumheller':
        return drumhellerLoopStops;
      default:
        return [];
    }
  }

  // GET MAP COORDINATES FOR A ROUTE
  static List<LatLng> getRoutePoints(String routeId) {
    switch (routeId) {
      case '1':
        return redSquareRoutePoints;
      case '2':
        return uwNatureRoutePoints;
      case '3':
        return waterfrontRoutePoints;
      case 'map-burke':
        return burkeLoopPoints;
      case 'map-quad':
        return quadLoopPoints;
      case 'map-drumheller':
        return drumhellerLoopPoints;
      default:
        return [];
    }
  }
}
