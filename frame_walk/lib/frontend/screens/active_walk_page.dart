import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../backend/providers/profile_provider.dart';
import '../../backend/services/location_source.dart';
import '../../backend/services/route_manager.dart';
import '../../backend/services/route_progress_tracker.dart';
import '../../backend/services/stop_notification_service.dart';
import '../../backend/services/walk_repository.dart';
import '../../backend/services/walk_tracking_service.dart';
import '../../models/location_point.dart';
import '../../models/mock_route_data.dart';
import '../../models/route_stop.dart';
import '../../models/walked_route.dart';
import '../theme/app_theme.dart';

// iOS apps can't open the device-wide Location Services switch directly.
bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

const _iosLocationServicesPath =
    'Settings > Privacy & Security > Location Services';

// The walk screen currently open, if any. A notification tap uses it to show
// a stop on the screen that's already there rather than opening a second one.
abstract class OpenWalkScreen {
  // Null while a new walk is still being created.
  String? get walkId;

  void showStop(String stopId);
}

// Records the user's walk along [route]. Tracking carries on while the phone
// is locked or FrameWalk is in the background (see WalkTrackingService).
class ActiveWalkPage extends StatefulWidget {
  // Starts a new walk of [route].
  const ActiveWalkPage({
    super.key,
    required WalkingRoute this.route,
    required this.stops,
    required this.routePoints,
    this.trackingService,
    this.stopNotifications,
    this.userId,
    this.showMap = true,
  }) : resumeWalkId = null,
       focusStopId = null;

  // Reopens walk [resumeWalkId], loading it from Firestore, and carries on
  // tracking it. Used when a stop notification is tapped. [focusStopId] is
  // the stop to show once the walk has loaded.
  const ActiveWalkPage.resume({
    super.key,
    required String this.resumeWalkId,
    this.focusStopId,
    this.trackingService,
    this.stopNotifications,
    this.userId,
    this.showMap = true,
  }) : route = null,
       stops = const [],
       routePoints = const [];

  // The open walk screen, or null if there isn't one.
  static OpenWalkScreen? get openScreen => _ActiveWalkPageState._open;

  // Null for a resumed walk; its details come from the saved walk instead.
  final WalkingRoute? route;
  final List<RouteStop> stops;
  final List<LatLng> routePoints;
  final String? resumeWalkId;
  final String? focusStopId;

  final WalkTrackingService? trackingService;

  // Injected by tests. Defaults to local notifications.
  final StopNotificationService? stopNotifications;

  final String? userId;
  final bool showMap;

  @override
  State<ActiveWalkPage> createState() => _ActiveWalkPageState();
}

class _ActiveWalkPageState extends State<ActiveWalkPage>
    with WidgetsBindingObserver
    implements OpenWalkScreen {
  static _ActiveWalkPageState? _open;

  late final WalkTrackingService _service;
  late final bool _ownsService;
  late final StopNotificationService _notifications;
  late final StopArrivalNotifier _arrivalNotifier;
  bool _askedForNotifications = false;

  StreamSubscription<StopEvent>? _stopEventsSub;
  Timer? _clock;
  late List<LatLng> _routePoints = widget.routePoints;

  // The stop from a tapped notification. Shown in the Current prompt box
  // until the next stop is reached.
  late String? _focusedStopId = widget.focusStopId;

  @override
  String? get walkId => _service.walk?.id ?? widget.resumeWalkId;

  @override
  void showStop(String stopId) {
    if (mounted) setState(() => _focusedStopId = stopId);
  }

  @override
  void initState() {
    super.initState();

    _ownsService = widget.trackingService == null;

    _service =
        widget.trackingService ??
        WalkTrackingService(
          locationSource: const GeolocatorLocationSource(),
          repository: WalkRepository(),
        );

    _service.addListener(_onServiceChanged);
    _stopEventsSub = _service.stopEvents.listen(_onStopEvent);

    _notifications = widget.stopNotifications ?? LocalStopNotificationService();

    // Notifies about stops reached while the phone is locked or FrameWalk
    // is in the background; on screen, _onStopEvent shows a SnackBar.
    _arrivalNotifier = StopArrivalNotifier(
      walk: _service,
      notifications: _notifications,
    );

    WidgetsBinding.instance.addObserver(this);

    // Refreshes elapsed time without unnecessary redraws.
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });

    _open = this;
    _start();
  }

  @override
  void dispose() {
    if (identical(_open, this)) _open = null;
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _stopEventsSub?.cancel();
    _arrivalNotifier.dispose();
    _service.removeListener(_onServiceChanged);

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

    final resumeWalkId = widget.resumeWalkId;
    if (resumeWalkId != null) {
      // Notification permission was settled when the walk first started.
      await _service.resumeWalk(
        userId: userId,
        walkId: resumeWalkId,
        routePathFor: _loadRoutePath,
      );
      return;
    }

    // Asked before tracking starts so Android's "recording your walk"
    // notification is visible from the beginning. Only once per walk: on
    // Android, asking again after a "no" would prompt again. A "no" doesn't
    // block the walk; stops are still shown on screen.
    if (!_askedForNotifications) {
      _askedForNotifications = true;
      await _notifications.requestPermission();
      if (!mounted) return;
    }

    await _service.startWalk(
      userId: userId,
      routeId: widget.route!.id,
      routeTitle: widget.route!.name,
      stops: widget.stops,
      routePath: _routePoints
          .map((p) => GeoCoordinate(p.latitude, p.longitude))
          .toList(),
    );
  }

  // The route line for a resumed walk, which only knows its routeId.
  // TODO: replace MockRouteData with real geometry lookups, as in
  // RouteInfoPage, which opens new walks.
  List<GeoCoordinate> _loadRoutePath(String routeId) {
    final points = MockRouteData.getRoutePoints(routeId);
    if (mounted) setState(() => _routePoints = points);
    return points.map((p) => GeoCoordinate(p.latitude, p.longitude)).toList();
  }

  // Displays a notification when the user approaches or reaches a stop.
  void _onStopEvent(StopEvent event) {
    if (!mounted) return;

    // A newly reached stop replaces a tapped notification's stop in the
    // Current prompt box.
    if (event.type == StopEventType.reached && _focusedStopId != null) {
      setState(() => _focusedStopId = null);
    }

    final message = event.type == StopEventType.reached
        ? 'You reached ${event.stop.stopName}!\n${event.stop.prompt}'
        : 'Approaching ${event.stop.stopName}';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Future<void> _finish() async {
    await _service.completeWalk();

    if (mounted && _service.phase == WalkPhase.completed) {
      context.read<ProfileProvider?>()?.refresh();
    }
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
      canPop: phase != WalkPhase.active && phase != WalkPhase.finishing, // can go back to the previous screen if the walk isn't active or finishing
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && phase == WalkPhase.active) {
          _confirmCancel();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          // displays the name of the route
          title: Text(
            widget.route?.name ?? _service.walk?.routeTitle ?? 'Your walk',
          ),
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(child: _buildBody(context)),
      ),
    );
  }

  // builds the main body of the active walk page
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
        text =
            'FrameWalk needs your location to follow you along the route '
            'and tell you when you reach each stop.';

        action = ElevatedButton(
          onPressed: _start,
          child: const Text('Allow location'),
        );

      case LocationReadiness.deniedForever:
        text =
            'Location access is turned off for FrameWalk. You can allow '
            'it in Settings.';

        action = ElevatedButton(
          onPressed: _service.openAppSettings,
          child: const Text('Open settings'),
        );

      case LocationReadiness.approximateOnly:
        text =
            'FrameWalk needs your precise location to tell when you reach '
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

  // Main active walk layout.
  Widget _buildActive(BuildContext context) {
    final progress = _service.progress!;
    final next = progress.nextStop;
    final toNext = progress.distanceToNextStopMeters;
    final finishing = _service.phase == WalkPhase.finishing;

    return Column(
      children: [
        _SignalBanner(service: _service),

        // Map takes the upper portion of the page.
        if (widget.showMap) Expanded(flex: 5, child: _buildMap(context)),

        // Progress and current prompt.
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 5),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${progress.reachedCount} of ${progress.totalStops} stops reached',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: finishing ? null : _confirmCancel,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cancel walk'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                LinearProgressIndicator(
                  value: progress.fractionComplete,
                  minHeight: 3,
                ),

                const SizedBox(height: 12),

                Text(
                  next == null
                      ? 'All stops reached!'
                      : 'Next: ${next.stopName}'
                            '${toNext == null ? '' : ' · ${_meters(toNext)} away'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),

                const SizedBox(height: 20),

                _buildCurrentPrompt(context, _currentPromptStop(progress)),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: finishing ? null : _finish,
                    child: Text(finishing ? 'Saving...' : 'Finish walk'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // The stop whose prompt the Current prompt box shows: the one a tapped
  // notification was about, otherwise the most recently reached stop.
  // Read from the walk's progress so it also works for a resumed walk.
  WalkedStop? _currentPromptStop(RouteProgressTracker progress) {
    WalkedStop? focused;
    WalkedStop? latest;
    for (final stop in progress.stops) {
      if (stop.stopId == _focusedStopId) focused = stop;
      final reachedAt = stop.reachedAt;
      if (reachedAt != null &&
          (latest == null || reachedAt.isAfter(latest.reachedAt!))) {
        latest = stop;
      }
    }
    return focused ?? latest;
  }

  // Shows the prompt for [currentStop].
  // Before the first stop is reached, displays a placeholder.
  Widget _buildCurrentPrompt(BuildContext context, WalkedStop? currentStop) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current prompt:',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            currentStop != null
                ? '${currentStop.stopName}: ${currentStop.prompt}'
                : 'Reach your first stop to see its photo prompt.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: currentStop == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // Displays the map with the Browse Stops button overlaid.
  Widget _buildMap(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final progress = _service.progress!;

    final walked = _service.recordedPoints
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _routePoints.isNotEmpty
                  ? _routePoints.first
                  : const LatLng(47.6553, -122.3035),
              zoom: 16,
            ),
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
                  infoWindow: InfoWindow(
                    title: stop.stopName,
                    snippet: stop.prompt,
                  ),
                ),
            },
            polylines: {
              if (_routePoints.isNotEmpty)
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: _routePoints,
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
          ),
        ),

        // Browse stops button.
        // Browse stops button, matching the Map page.
        Positioned(
          top: 8,
          left: 12,
          child: Material(
            color: AppTheme.cream,
            borderRadius: BorderRadius.circular(8),
            child: TextButton.icon(
              onPressed: _showStopsSheet,
              icon: const Icon(Icons.list, size: 18),
              label: Text('Browse stops (${progress.totalStops})'),
            ),
          ),
        ),
      ],
    );
  }

  // Opens the route stops in a rounded bottom sheet.
  Future<void> _showStopsSheet() {
    final theme = Theme.of(context);

    // From the walk rather than widget.stops, which a resumed walk doesn't
    // have.
    final stops = _service.progress!.stops;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          bottom: false,
          child: Container(
            height: MediaQuery.of(sheetContext).size.height * 0.62,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),

                // Sheet handle.
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Route Stops',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: stops.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final stop = stops[index];

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 19,
                            backgroundColor: theme.colorScheme.primary,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Card(
                              elevation: 2,
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ExpansionTile(
                                title: Text(
                                  stop.stopName,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          const TextSpan(
                                            text: 'PROMPT: ',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          TextSpan(text: stop.prompt),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompleted(BuildContext context) {
    final walk = _service.walk!;
    final reached = walk.reachedStopIds.length;

    return _Message(
      text:
          'Walk complete!\n\n'
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
