import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../backend/services/route_manager.dart';
import '../../models/mock_route_data.dart';
import '../../models/route_stop.dart';
import '../../backend/providers/route_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/route_card.dart' show toggleRouteBookmarkWithFeedback;
import 'active_walk_page.dart';

class RouteInfoPage extends StatefulWidget {
  const RouteInfoPage({super.key, required this.route});

  final WalkingRoute route;

  /// Opens the info page for [route]. Use this from any screen instead of
  /// building the MaterialPageRoute by hand.
  static Future<void> open(BuildContext context, WalkingRoute route) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => RouteInfoPage(route: route)),
    );
  }

  @override
  State<RouteInfoPage> createState() => _RouteInfoPageState();
}

class _RouteInfoPageState extends State<RouteInfoPage> {
  GoogleMapController? _mapController;

  // TODO: replace MockRouteData with real stop / geometry lookups.
  late final List<RouteStop> _stops;
  late final List<LatLng> _routePoints;

  @override
  void initState() {
    super.initState();
    _stops = MockRouteData.getStops(widget.route.id);
    _routePoints = MockRouteData.getRoutePoints(widget.route.id);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  // Zoom the map so the whole route is visible (same idea as the Map page).
  Future<void> _fitRoute() async {
    if (_routePoints.isEmpty) return;
    // Let the map lay out before animating to bounds.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    var south = _routePoints.first.latitude;
    var north = south;
    var west = _routePoints.first.longitude;
    var east = west;
    for (final point in _routePoints) {
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
    }
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        44,
      ),
    );
  }

  Set<Marker> _buildMarkers() {
    return _stops.map((stop) {
      return Marker(
        markerId: MarkerId(stop.id),
        position: LatLng(stop.latitude, stop.longitude),
        infoWindow: InfoWindow(title: stop.name, snippet: stop.prompt),
      );
    }).toSet();
  }

  // Same look as the selected route on the Map page.
  Set<Polyline> _buildPolylines() {
    if (_routePoints.isEmpty) return {};

    return {
      Polyline(
        polylineId: PolylineId(widget.route.id),
        points: _routePoints,
        color: AppTheme.teal,
        width: 6,
      ),
    };
  }

  // White dots at each bend, like the Map page.
  Set<Circle> _buildCircles() {
    return {
      for (var i = 1; i < _routePoints.length - 1; i++)
        Circle(
          circleId: CircleId('${widget.route.id}-$i'),
          center: _routePoints[i],
          radius: 7,
          fillColor: Colors.white,
          strokeColor: AppTheme.teal,
          strokeWidth: 2,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Map with back and bookmark buttons.
              SizedBox(
                height: 210,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _routePoints.isEmpty
                          ? const Center(child: Text('Route map unavailable'))
                          : GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: _routePoints.first,
                                zoom: 15,
                              ),
                              markers: _buildMarkers(),
                              polylines: _buildPolylines(),
                              circles: _buildCircles(),
                              zoomControlsEnabled: false,
                              mapToolbarEnabled: false,
                              myLocationButtonEnabled: false,
                              onMapCreated: (controller) {
                                _mapController = controller;
                                _fitRoute();
                              },
                            ),
                    ),

                    // Back button.
                    Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.surface,
                          foregroundColor: colorScheme.onSurface,
                        ),
                      ),
                    ),

                    // Bookmark button, shared with the rest of the app.
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Consumer<RouteProvider>(
                        builder: (context, provider, _) {
                          final isBookmarked = provider.isBookmarked(
                            widget.route.id,
                          );
                          return IconButton(
                            tooltip: isBookmarked
                                ? 'Remove bookmark'
                                : 'Bookmark route',
                            onPressed: () => toggleRouteBookmarkWithFeedback(
                              context,
                              isBookmarked: isBookmarked,
                              onToggle: () =>
                                  provider.toggleBookmark(widget.route.id),
                            ),
                            icon: Icon(
                              isBookmarked
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: colorScheme.surface,
                              foregroundColor: colorScheme.onSurface,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Route information.
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.route.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),

                    const SizedBox(height: 12),

                    // Duration, number of stops, and tags.
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          color: Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text('${widget.route.estimatedMinutes} min'),

                        const SizedBox(width: 12),

                        const Icon(
                          Icons.location_on,
                          color: Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Text('${_stops.length} stops'),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: widget.route.sceneryTags.take(2).map((
                              tag,
                            ) {
                              return Chip(
                                label: Text(tag),
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Start Walk button.
                    Center(
                      child: SizedBox(
                        width: 200,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ActiveWalkPage(
                                route: widget.route,
                                stops: _stops,
                                routePoints: _routePoints,
                              ),
                            ),
                          ),
                          child: const Text('Start Walk'),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    Text(
                      'Route Stops',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),

                    const SizedBox(height: 12),

                    // Expandable stops.
                    ..._stops.asMap().entries.map((entry) {
                      final index = entry.key;
                      final stop = entry.value;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: colorScheme.primary,
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontSize: 16,
                                ),
                              ),
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ExpansionTile(
                                  title: Text(
                                    stop.name,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  childrenPadding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(stop.prompt),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
