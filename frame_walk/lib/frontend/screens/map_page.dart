import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/mock_route_data.dart';
import '../../backend/services/route_manager.dart';
import '../../backend/providers/route_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/route_card.dart';
import '../widgets/route_filter_chips.dart';
import '../widgets/route_search_bar.dart';
import 'route_info_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _routeColor = Color(0xFF7966FF);

  GoogleMapController? _mapController;
  BitmapDescriptor? _startIcon;
  BitmapDescriptor? _endIcon;
  BitmapDescriptor? _loopIcon;
  String _query = '';
  String _duration = RouteProvider.anyDuration;
  String _distance = RouteProvider.anyDistance;
  String _scenery = RouteProvider.anyScenery;
  String? _selectedId; // id of the selected route only, the route itself lives in RouteProvider

  // Returns a list of WalkingRoute's to show on the map
  List<WalkingRoute> _visibleRoutes(RouteProvider provider) => provider
      .search(
        query: _query,
        duration: _duration,
        distance: _distance,
        scenery: _scenery,
      )
      // checks that the mock route data has route points for the route r
      .where((r) => MockRouteData.getRoutePoints(r.id).isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    _createEndpointIcons();
  }

  // Reuse the app colors; render labels once without image assets.
  Future<void> _createEndpointIcons() async {
    final start = await _endpointIcon('Start', AppTheme.teal);
    final end = await _endpointIcon('End', AppTheme.black);
    final loop = await _endpointIcon('Start / End', AppTheme.teal);
    if (!mounted) return;
    setState(() {
      _startIcon = start;
      _endIcon = end;
      _loopIcon = loop;
    });
  }

  Future<BitmapDescriptor> _endpointIcon(String label, Color color) async {
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = (text.width + 36).ceil();
    const height = 76;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 2, width - 4.0, 58),
      const Radius.circular(12),
    );
    canvas.drawRRect(body, Paint()..color = color);
    canvas.drawRRect(
      body,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // The tip marks the actual coordinate, rather than the label's center.
    canvas.drawPath(
      Path()
        ..moveTo(width / 2 - 10, 58)
        ..lineTo(width / 2, 76)
        ..lineTo(width / 2 + 10, 58)
        ..close(),
      Paint()..color = color,
    );
    text.paint(
      canvas,
      Offset((width - text.width) / 2, (62 - text.height) / 2),
    );
    text.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes == null) return BitmapDescriptor.defaultMarker;
    return BitmapDescriptor.bytes(
      bytes.buffer.asUint8List(),
      width: width / 2,
      height: height / 2,
    );
  }

  Set<Marker> _routeEndpointMarkers(WalkingRoute route) {
    final points = MockRouteData.getRoutePoints(route.id);
    if (points.isEmpty) return {};
    final isLoop = points.first == points.last;
    // A loop starts and ends at the same coordinate. One combined label
    // avoids two overlapping markers and preserves the route geometry.
    return {
      Marker(
        markerId: MarkerId('${route.id}-start'),
        position: points.first,
        icon:
            (isLoop ? _loopIcon : _startIcon) ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: '${route.name} — ${isLoop ? 'Start / End' : 'Start'}',
          snippet: isLoop ? 'This loop returns here.' : 'Begin your walk here.',
        ),
        onTap: () => _selectRoute(route),
      ),
      if (!isLoop)
        Marker(
          markerId: MarkerId('${route.id}-end'),
          position: points.last,
          icon: _endIcon ?? BitmapDescriptor.defaultMarker,
          infoWindow: InfoWindow(
            title: '${route.name} — End',
            snippet: 'Your walk ends here.',
          ),
          onTap: () => _selectRoute(route),
        ),
    };
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _updateFilters({
    String? query,
    String? duration,
    String? distance,
    String? scenery,
  }) {
    // uses context.read so that this widget doesn't rebuild when changes happeb
    final provider = context.read<RouteProvider>();
    setState(() {
      if (query != null) _query = query;
      if (duration != null) _duration = duration;
      if (distance != null) _distance = distance;
      if (scenery != null) _scenery = scenery;
      // Deselects a selected route if route filters change to not include it
      if (!_visibleRoutes(provider).any((r) => r.id == _selectedId)) {
        _selectedId = null;
      }
    });
  }

  Future<void> _selectRoute(WalkingRoute route) async {
    FocusScope.of(context).unfocus();
    setState(() => _selectedId = route.id);
    // Allow the detail card to lay out before fitting the route to the map.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final points = MockRouteData.getRoutePoints(route.id);
    if (points.isEmpty) return;
    var south = points.first.latitude;
    var north = south;
    var west = points.first.longitude;
    var east = west;
    for (final point in points) {
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

  Future<void> _showRouteList() async {
    FocusScope.of(context).unfocus();
    final chosen = await showModalBottomSheet<WalkingRoute>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.65,
        // Give the sheet its own snackbar host so confirmations stay visible.
        child: ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Theme.of(sheetContext).colorScheme.surface,
            body: Consumer<RouteProvider>(
              builder: (context, provider, _) {
                final routes = _visibleRoutes(provider);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Campus routes (${routes.length})',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close routes',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: routes.isEmpty
                          ? const Center(
                              child: Text(
                                'No routes match your search or filters.',
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              itemCount: routes.length,
                              itemBuilder: (context, index) {
                                final route = routes[index];
                                return RouteCard(
                                  route: route,
                                  onTap: () =>
                                      Navigator.pop(sheetContext, route),
                                  onBookmarkTap: () =>
                                      provider.toggleBookmark(route.id),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    if (mounted && chosen != null) RouteInfoPage.open(context, chosen);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              'FrameWalk',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RouteSearchBar(
              onChanged: (value) => _updateFilters(query: value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Center(
              child: RouteFilterChips(
                duration: _duration,
                distance: _distance,
                scenery: _scenery,
                onDurationChanged: (v) => _updateFilters(duration: v),
                onDistanceChanged: (v) => _updateFilters(distance: v),
                onSceneryChanged: (v) => _updateFilters(scenery: v),
              ),
            ),
          ),
          // Map + "Browse routes" button.
          Expanded(
            child: Consumer<RouteProvider>(
              builder: (context, provider, _) {
                final routes = _visibleRoutes(provider);
                return Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: const CameraPosition(
                        target: MockRouteData.uwCampus,
                        zoom: 15,
                      ),
                      onMapCreated: (controller) => _mapController = controller,
                      onTap: (_) {
                        FocusScope.of(context).unfocus();
                        setState(() => _selectedId = null);
                      },
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      mapToolbarEnabled: false,
                      zoomControlsEnabled: true,
                      padding: const EdgeInsets.only(top: 44, bottom: 8),
                      polylines: {
                        for (final route in routes)
                          Polyline(
                            polylineId: PolylineId(route.id),
                            points: MockRouteData.getRoutePoints(route.id),
                            color: route.id == _selectedId
                                ? AppTheme.teal
                                : _routeColor,
                            width: route.id == _selectedId ? 6 : 3,
                            zIndex: route.id == _selectedId ? 2 : 1,
                            consumeTapEvents: true,
                            onTap: () => _selectRoute(route),
                          ),
                      },
                      markers: {
                        for (final route in routes)
                          ..._routeEndpointMarkers(route),
                      },
                      circles: {
                        for (final route in routes)
                          for (
                            var i = 1;
                            i <
                                MockRouteData.getRoutePoints(route.id).length -
                                    1;
                            i++
                          )
                            Circle(
                              circleId: CircleId('${route.id}-$i'),
                              center: MockRouteData.getRoutePoints(route.id)[i],
                              radius: 7,
                              fillColor: Colors.white,
                              strokeColor: route.id == _selectedId
                                  ? AppTheme.teal
                                  : _routeColor,
                              strokeWidth: 2,
                              consumeTapEvents: true,
                              onTap: () => _selectRoute(route),
                            ),
                      },
                    ),
                    Positioned(
                      top: 8,
                      left: 12,
                      child: Material(
                        color: AppTheme.cream,
                        borderRadius: BorderRadius.circular(8),
                        child: TextButton.icon(
                          onPressed: _showRouteList,
                          icon: const Icon(Icons.list, size: 18),
                          label: Text(
                            routes.isEmpty
                                ? 'No matching routes'
                                : 'Browse routes (${routes.length})',
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Selected-route detail card.
          Consumer<RouteProvider>(
            builder: (context, provider, _) {
              final selected = _visibleRoutes(provider)
                  .where((r) => r.id == _selectedId)
                  .firstOrNull;
              if (selected == null) return const SizedBox.shrink();
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Close route details',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _selectedId = null),
                        ),
                      ),
                      RouteCard(
                        route: selected,
                        onTap: () => RouteInfoPage.open(context, selected),
                        onBookmarkTap: () =>
                            provider.toggleBookmark(selected.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
