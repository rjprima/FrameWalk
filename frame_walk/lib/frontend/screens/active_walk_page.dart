import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../backend/services/location_source.dart';
import '../../backend/services/route_manager.dart';
import '../../backend/services/route_progress_tracker.dart';
import '../../backend/services/walk_repository.dart';
import '../../backend/services/walk_tracking_service.dart';
import '../../models/location_point.dart';
import '../../models/route_stop.dart';

// iOS apps can't open the device-wide Location Services switch directly; the
// settings button opens FrameWalk's own Settings page instead, so iOS users
// are told where the switch is.
bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;
const _iosLocationServicesPath =
    'Settings > Privacy & Security > Location Services';

// Records the user's walk along [route] while this page is on screen.
class ActiveWalkPage extends StatefulWidget {
  const ActiveWalkPage({
    super.key,
    required this.route,
    required this.stops,
    required this.routePoints,
    this.trackingService,
    this.userId,
    this.showMap = true,
  });

  final WalkingRoute route;
  final List<RouteStop> stops;
  final List<LatLng> routePoints;

  // Injected by tests. Defaults to GPS and Firestore.
  final WalkTrackingService? trackingService;

  // Defaults to the signed-in user.
  final String? userId;

  // Google Maps can't render in widget tests.
  final bool showMap;

  @override
  State<ActiveWalkPage> createState() => _ActiveWalkPageState();
}

class _ActiveWalkPageState extends State<ActiveWalkPage>
    with WidgetsBindingObserver {
  late final WalkTrackingService _service;
  late final bool _ownsService;
  StreamSubscription<StopEvent>? _stopEventsSub;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.trackingService == null;
    _service = widget.trackingService ??
        WalkTrackingService(
          locationSource: const GeolocatorLocationSource(),
          repository: WalkRepository(),
        );
    _service.addListener(_onServiceChanged);
    _stopEventsSub = _service.stopEvents.listen(_onStopEvent);
    WidgetsBinding.instance.addObserver(this);
    // Refreshes the elapsed time. Coarse on purpose to avoid needless redraws.
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _stopEventsSub?.cancel();
    _service.removeListener(_onServiceChanged);
    // Disposing stops the location stream, whatever state the walk is in.
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _service.handleAppLifecycleState(state);
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final userId = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    await _service.startWalk(
      userId: userId,
      routeId: widget.route.id,
      routeTitle: widget.route.name,
      stops: widget.stops,
      routePath: widget.routePoints
          .map((p) => GeoCoordinate(p.latitude, p.longitude))
          .toList(),
    );
  }

  void _onStopEvent(StopEvent event) {
    if (!mounted) return;
    final message = event.type == StopEventType.reached
        ? 'You reached ${event.stop.stopName}! ${event.stop.prompt}'
        : 'Approaching ${event.stop.stopName}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _finish() async {
    await _service.completeWalk();
  }

  Future<void> _confirmCancel() async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this walk?'),
        content: const Text(
          'Your progress and location history for this walk will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep walking'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel walk'),
          ),
        ],
      ),
    );
    if (cancel != true || !mounted) return;
    await _service.cancelWalk();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final phase = _service.phase;
    return PopScope(
      // Leaving mid-walk must go through cancel, so tracking always stops
      // deliberately.
      canPop: phase != WalkPhase.active && phase != WalkPhase.finishing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && phase == WalkPhase.active) _confirmCancel();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.route.name)),
        body: SafeArea(child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final userId = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const _Message(text: 'Please log in to record a walk.');
    }
    switch (_service.phase) {
      case WalkPhase.idle:
      case WalkPhase.starting:
        return const Center(child: CircularProgressIndicator());
      case WalkPhase.blocked:
        return _buildBlocked(context);
      case WalkPhase.active:
      case WalkPhase.finishing:
        return _buildActive(context);
      case WalkPhase.completed:
        return _buildCompleted(context);
      case WalkPhase.cancelled:
        return const _Message(text: 'Walk cancelled.');
      case WalkPhase.failed:
        return _Message(
          text: _service.errorMessage ?? 'Something went wrong.',
          action: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        );
    }
  }

  Widget _buildBlocked(BuildContext context) {
    final String text;
    Widget? action;
    switch (_service.readiness) {
      case LocationReadiness.serviceDisabled:
        text = _isIOS
            ? 'Location Services are turned off. Turn them on in '
                '$_iosLocationServicesPath to track your walk.'
            : 'Location services are turned off. Turn them on to track '
                'your walk.';
        action = ElevatedButton(
          onPressed: _service.openLocationSettings,
          child: Text(_isIOS ? 'Open Settings' : 'Open location settings'),
        );
      case LocationReadiness.denied:
        text = 'FrameWalk needs your location to follow you along the route '
            'and tell you when you reach each stop.';
        action = ElevatedButton(
          onPressed: _start,
          child: const Text('Allow location'),
        );
      case LocationReadiness.deniedForever:
        text = 'Location access is turned off for FrameWalk. You can allow '
            'it in Settings.';
        action = ElevatedButton(
          onPressed: _service.openAppSettings,
          child: const Text('Open settings'),
        );
      case LocationReadiness.approximateOnly:
        text = 'FrameWalk needs your precise location to tell when you reach '
            'a stop. Turn on "Precise location" for FrameWalk in Settings.';
        action = ElevatedButton(
          onPressed: _service.openAppSettings,
          child: const Text('Open settings'),
        );
      case LocationReadiness.unavailable:
      case LocationReadiness.ready:
      case null:
        text = "Location isn't available on this device right now.";
    }
    return _Message(
      text: text,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?action,
          TextButton(onPressed: _start, child: const Text('Try again')),
        ],
      ),
    );
  }

  Widget _buildActive(BuildContext context) {
    final progress = _service.progress!;
    final walk = _service.walk!;
    final next = progress.nextStop;
    final toNext = progress.distanceToNextStopMeters;
    final elapsed = DateTime.now().difference(walk.startedAt);
    final finishing = _service.phase == WalkPhase.finishing;

    return Column(
      children: [
        _SignalBanner(service: _service),
        if (widget.showMap) Expanded(child: _buildMap(context)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${progress.reachedCount} of ${progress.totalStops} stops '
                'reached',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress.fractionComplete),
              const SizedBox(height: 12),
              Text(
                next == null
                    ? 'All stops reached!'
                    : 'Next: ${next.stopName}'
                        '${toNext == null ? '' : ' · ${_meters(toNext)} away'}',
              ),
              const SizedBox(height: 4),
              Text(
                '${_meters(walk.distanceMeters)} walked · '
                '${elapsed.inMinutes} min',
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: finishing ? null : _finish,
                child: Text(finishing ? 'Saving...' : 'Finish walk'),
              ),
              TextButton(
                onPressed: finishing ? null : _confirmCancel,
                child: const Text('Cancel walk'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMap(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final progress = _service.progress!;
    final walked = _service.recordedPoints
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: widget.routePoints.isNotEmpty
            ? widget.routePoints.first
            : const LatLng(47.6553, -122.3035),
        zoom: 16,
      ),
      // Safe: the walk only starts once location permission is granted.
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      markers: {
        for (final stop in progress.stops)
          Marker(
            markerId: MarkerId(stop.stopId),
            position: LatLng(stop.latitude, stop.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              progress.proximityOf(stop.stopId) == StopProximity.reached
                  ? BitmapDescriptor.hueGreen
                  : BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(title: stop.stopName, snippet: stop.prompt),
          ),
      },
      polylines: {
        if (widget.routePoints.isNotEmpty)
          Polyline(
            polylineId: const PolylineId('route'),
            points: widget.routePoints,
            color: color.withValues(alpha: 0.4),
            width: 5,
          ),
        if (walked.length > 1)
          Polyline(
            polylineId: const PolylineId('walked'),
            points: walked,
            color: color,
            width: 4,
          ),
      },
    );
  }

  Widget _buildCompleted(BuildContext context) {
    final walk = _service.walk!;
    final reached = walk.reachedStopIds.length;
    return _Message(
      text: 'Walk complete!\n\n'
          '$reached of ${walk.stops.length} stops reached\n'
          '${_meters(walk.distanceMeters)} walked in '
          '${walk.duration?.inMinutes ?? 0} min',
      action: ElevatedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    );
  }

  static String _meters(double meters) => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(2)} km'
      : '${meters.round()} m';
}

class _SignalBanner extends StatelessWidget {
  const _SignalBanner({required this.service});

  final WalkTrackingService service;

  @override
  Widget build(BuildContext context) {
    final String? text;
    VoidCallback? onFix;
    String fixLabel = 'Try again';
    switch (service.signal) {
      case SignalStatus.good:
        text = null;
      case SignalStatus.acquiring:
        text = 'Finding your location...';
      case SignalStatus.lowAccuracy:
        text = 'GPS signal is weak. Try moving away from tall buildings.';
      case SignalStatus.noRecentFix:
        text = 'No recent GPS update. Your location will update as you walk.';
        onFix = () => service.resumeTracking();
      case SignalStatus.gpsDisabled:
        text = _isIOS
            ? 'Location Services are off. Turn them on in '
                '$_iosLocationServicesPath to keep tracking.'
            : 'Location services are off. Turn them on to keep tracking.';
        onFix = service.openLocationSettings;
        fixLabel = 'Settings';
      case SignalStatus.permissionRevoked:
        text = 'Location permission was turned off.';
        onFix = () => service.resumeTracking(requestPermission: true);
        fixLabel = 'Allow';
      case SignalStatus.pausedInBackground:
        text = 'Tracking is paused while FrameWalk is in the background.';
    }
    if (text == null) return const SizedBox.shrink();
    return MaterialBanner(
      content: Text(text),
      actions: [
        if (onFix != null)
          TextButton(onPressed: onFix, child: Text(fixLabel))
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
