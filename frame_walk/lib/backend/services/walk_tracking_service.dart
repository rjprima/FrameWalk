import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../../models/location_point.dart';
import '../../models/route_stop.dart';
import '../../models/walked_route.dart';
import 'location_source.dart';
import 'route_progress_tracker.dart';
import 'walk_repository.dart';

enum WalkPhase {
  idle,

  // Checking permission and creating the walk.
  starting,

  // Location can't be used yet. See [WalkTrackingService.readiness].
  blocked,

  // Recording.
  active,

  // Saving the finished walk.
  finishing,

  completed,
  cancelled,

  // Saving failed. See [WalkTrackingService.errorMessage].
  failed,
}

// The state of the GPS signal during an active walk.
enum SignalStatus {
  // Waiting for the first reading.
  acquiring,
  good,

  // Readings are arriving but are too imprecise to record.
  lowAccuracy,

  // No reading for [TrackingConfig.signalLostAfter]. Can also mean the user
  // is standing still, since the distance filter suppresses those readings.
  noRecentFix,

  // The user turned off device location services mid-walk.
  gpsDisabled,

  // The user revoked location permission mid-walk.
  permissionRevoked,

  // FrameWalk is off screen. Tracking is foreground-only, so it's paused.
  pausedInBackground,
}

class TrackingConfig {
  final TrackingSettings settings;

  // Readings less precise than this are ignored. Stops are tens of meters
  // apart, so anything worse can't place the user reliably.
  final double maxAcceptedAccuracyMeters;

  // Distance isn't added for jumps faster than this. Walking is ~1.4 m/s;
  // anything this fast is a GPS jump, not the user.
  final double maxPlausibleSpeedMetersPerSecond;

  // Points are saved in batches to reduce radio use and Firestore writes.
  final int flushEveryPoints;
  final Duration flushInterval;

  final Duration signalLostAfter;
  final Duration housekeepingInterval;

  // How long to wait for Firestore before carrying on. Firestore keeps the
  // write in its offline cache and syncs it later.
  final Duration persistTimeout;

  const TrackingConfig({
    this.settings = const TrackingSettings(),
    this.maxAcceptedAccuracyMeters = 50,
    this.maxPlausibleSpeedMetersPerSecond = 12,
    this.flushEveryPoints = 10,
    this.flushInterval = const Duration(seconds: 30),
    this.signalLostAfter = const Duration(minutes: 2),
    this.housekeepingInterval = const Duration(seconds: 15),
    this.persistTimeout = const Duration(seconds: 8),
  });
}

// Records one walk at a time: asks for location access, follows the user
// along the route, saves their location history, and stops listening when the
// walk is completed or cancelled.
//
// Foreground only. When FrameWalk leaves the screen, call
// [handleAppLifecycleState] and tracking pauses until the app returns.
class WalkTrackingService extends ChangeNotifier {
  final LocationSource _source;
  final WalkRepository _walkRepository;
  final TrackingConfig config;
  final DateTime Function() _now;

  WalkTrackingService({
    required LocationSource locationSource,
    required WalkRepository repository,
    this.config = const TrackingConfig(),
    DateTime Function()? clock,
  })  : _source = locationSource,
        _walkRepository = repository,
        _now = clock ?? DateTime.now;

  WalkPhase _phase = WalkPhase.idle;
  SignalStatus _signal = SignalStatus.acquiring;
  LocationReadiness? _readiness;
  String? _errorMessage;

  WalkedRoute? _walk;
  RouteProgressTracker? _progress;
  final List<LocationPoint> _points = [];
  final List<LocationPoint> _pending = [];
  LocationSample? _lastAccepted;
  DateTime? _lastFixReceivedAt;
  DateTime _lastFlushAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _inBackground = false;

  StreamSubscription<LocationSample>? _positionSub;
  StreamSubscription<bool>? _serviceSub;
  Timer? _housekeeping;
  final StreamController<StopEvent> _stopEvents =
      StreamController<StopEvent>.broadcast();
  bool _disposed = false;

  WalkPhase get phase => _phase;
  SignalStatus get signal => _signal;
  LocationReadiness? get readiness => _readiness;
  String? get errorMessage => _errorMessage;
  WalkedRoute? get walk => _walk;
  RouteProgressTracker? get progress => _progress;
  List<LocationPoint> get recordedPoints => List.unmodifiable(_points);
  LocationSample? get lastLocation => _lastAccepted;
  bool get isInBackground => _inBackground;

  // True only while the location stream is open.
  bool get isListening => _positionSub != null;

  // Points recorded but not yet handed to Firestore.
  int get pendingPointCount => _pending.length;

  // Fires when the user approaches or reaches a stop.
  Stream<StopEvent> get stopEvents => _stopEvents.stream;

  // Checks permission (asking if needed) and starts recording. Returns the
  // readiness; anything but [LocationReadiness.ready] leaves the phase as
  // [WalkPhase.blocked] and records nothing.
  Future<LocationReadiness> startWalk({
    required String userId,
    required String routeId,
    required String routeTitle,
    required List<RouteStop> stops,
    List<GeoCoordinate> routePath = const [],
  }) async {
    if (_phase == WalkPhase.starting ||
        _phase == WalkPhase.active ||
        _phase == WalkPhase.finishing) {
      throw StateError('A walk is already in progress');
    }
    _errorMessage = null;
    _setPhase(WalkPhase.starting);

    final readiness = await checkLocationReadiness(_source);
    _readiness = readiness;
    if (_disposed) return readiness;
    if (readiness != LocationReadiness.ready) {
      _setPhase(WalkPhase.blocked);
      return readiness;
    }

    final walk = WalkedRoute.start(
      id: _walkRepository.newWalkId(userId),
      userId: userId,
      routeId: routeId,
      routeTitle: routeTitle,
      stops: stops,
      startedAt: _now(),
    );
    try {
      await _persist(_walkRepository.createWalk(walk));
    } catch (error) {
      _errorMessage = "Couldn't start the walk. Please try again.";
      _setPhase(WalkPhase.failed);
      return readiness;
    }
    if (_disposed) return readiness;

    _walk = walk;
    _progress = RouteProgressTracker(stops: walk.stops, routePath: routePath);
    _points.clear();
    _pending.clear();
    _lastAccepted = null;
    _lastFixReceivedAt = null;
    _lastFlushAt = _now();
    _inBackground = false;
    _signal = SignalStatus.acquiring;
    _phase = WalkPhase.active;

    _serviceSub = _source.serviceEnabledChanges().listen(
      _onServiceChanged,
      onError: (Object _) {},
    );
    _listen();
    _housekeeping = Timer.periodic(
      config.housekeepingInterval,
      (_) => runHousekeeping(),
    );
    _notify();
    return readiness;
  }

  // Stops tracking, saves the remaining points, and marks the walk
  // completed. Stops don't all have to be reached.
  Future<WalkedRoute> completeWalk() async {
    if (_phase != WalkPhase.active) {
      throw StateError('There is no active walk to complete');
    }
    _setPhase(WalkPhase.finishing);
    _stopTracking();

    final completed = _walk!.copyWith(
      status: WalkStatus.completed,
      completedAt: _now(),
    );
    _walk = completed;
    try {
      // Issued together: Firestore applies them in this order, even offline.
      await _persist(Future.wait([
        _flush(),
        _walkRepository.completeWalk(completed),
      ]));
    } catch (error) {
      _errorMessage = "Couldn't save your walk. Check your connection.";
      _setPhase(WalkPhase.failed);
      return completed;
    }
    _setPhase(WalkPhase.completed);
    return completed;
  }

  // Stops tracking and deletes the walk and its location history.
  Future<void> cancelWalk() async {
    if (_phase != WalkPhase.active) {
      throw StateError('There is no active walk to cancel');
    }
    _stopTracking();
    _pending.clear();
    final walk = _walk!;
    _setPhase(WalkPhase.cancelled);
    try {
      await _persist(_walkRepository.deleteWalk(walk));
    } catch (error) {
      _errorMessage = "The walk was cancelled but couldn't be removed.";
      _notify();
    }
  }

  // Foreground-only tracking: closes the location stream when FrameWalk
  // leaves the screen and reopens it on return.
  void handleAppLifecycleState(AppLifecycleState state) {
    if (_phase != WalkPhase.active) return;
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_inBackground) return;
        _inBackground = true;
        _cancelPositionStream();
        _flush();
        _signal = SignalStatus.pausedInBackground;
        _notify();
      case AppLifecycleState.resumed:
        if (!_inBackground) return;
        _inBackground = false;
        resumeTracking();
      case AppLifecycleState.inactive:
        // Brief interruptions such as permission dialogs. Keep listening.
        break;
    }
  }

  // Re-checks location access and reopens the stream. Used on return from
  // the background and by the UI's "Try again" action.
  Future<LocationReadiness> resumeTracking({
    bool requestPermission = false,
  }) async {
    final readiness =
        await checkLocationReadiness(_source, request: requestPermission);
    if (_phase != WalkPhase.active || _inBackground || _disposed) {
      return readiness;
    }
    _readiness = readiness;
    switch (readiness) {
      case LocationReadiness.ready:
      case LocationReadiness.approximateOnly:
        // Approximate readings will be rejected as low accuracy, which the
        // UI explains.
        _signal = SignalStatus.acquiring;
        _lastFixReceivedAt = _now();
        _listen();
      case LocationReadiness.serviceDisabled:
        _cancelPositionStream();
        _signal = SignalStatus.gpsDisabled;
      case LocationReadiness.denied:
      case LocationReadiness.deniedForever:
      case LocationReadiness.unavailable:
        _cancelPositionStream();
        _signal = SignalStatus.permissionRevoked;
    }
    _notify();
    return readiness;
  }

  Future<bool> openAppSettings() => _source.openAppSettings();
  Future<bool> openLocationSettings() => _source.openLocationSettings();

  // Saves points on a timer and notices when readings stop arriving. Runs
  // every [TrackingConfig.housekeepingInterval]; public so tests can drive
  // it with a fake clock.
  void runHousekeeping() {
    if (_phase != WalkPhase.active) return;
    final now = _now();
    if (_pending.isNotEmpty &&
        now.difference(_lastFlushAt) >= config.flushInterval) {
      _flush();
    }
    final waitingForFix = _signal == SignalStatus.acquiring ||
        _signal == SignalStatus.good ||
        _signal == SignalStatus.lowAccuracy;
    if (!_inBackground && waitingForFix) {
      final since = _lastFixReceivedAt ?? _walk!.startedAt;
      if (now.difference(since) >= config.signalLostAfter) {
        _signal = SignalStatus.noRecentFix;
        _notify();
      }
    }
  }

  void _listen() {
    _positionSub?.cancel();
    _positionSub = _source.positionStream(config.settings).listen(
          _onSample,
          onError: _onStreamError,
          onDone: () => _positionSub = null,
        );
  }

  void _onSample(LocationSample sample) {
    if (_phase != WalkPhase.active || _inBackground) return;
    _lastFixReceivedAt = _now();

    if (sample.accuracyMeters > config.maxAcceptedAccuracyMeters) {
      _signal = SignalStatus.lowAccuracy;
      _notify();
      return;
    }
    _signal = SignalStatus.good;

    var walk = _walk!;
    var distance = walk.distanceMeters;
    final previous = _lastAccepted;
    if (previous != null) {
      final step = GeoMath.distanceMeters(
        previous.coordinate,
        sample.coordinate,
      );
      final seconds =
          sample.recordedAt.difference(previous.recordedAt).inMilliseconds /
              1000;
      final plausible = seconds > 0
          ? step / seconds <= config.maxPlausibleSpeedMetersPerSecond
          : step <= config.maxAcceptedAccuracyMeters;
      if (plausible) distance += step;
    }
    _lastAccepted = sample;

    final point = LocationPoint.fromSample(_points.length, sample);
    _points.add(point);
    _pending.add(point);

    walk = walk.copyWith(
      distanceMeters: distance,
      locationPointCount: _points.length,
      lastLocationAt: sample.recordedAt,
    );
    final events = _progress!.update(sample);
    var stopReached = false;
    for (final event in events) {
      if (event.type == StopEventType.reached) {
        walk = walk.withStopReached(event.stop.stopId, event.time);
        stopReached = true;
      }
    }
    _walk = walk;
    for (final event in events) {
      _stopEvents.add(event);
    }

    // Reaching a stop is saved straight away; other points wait for a batch.
    if (stopReached || _pending.length >= config.flushEveryPoints) {
      _flush();
    }
    _notify();
  }

  void _onStreamError(Object error) {
    if (_phase != WalkPhase.active) return;
    final kind = error is LocationStreamException
        ? error.kind
        : LocationErrorKind.other;
    switch (kind) {
      case LocationErrorKind.serviceDisabled:
        _cancelPositionStream();
        _signal = SignalStatus.gpsDisabled;
      case LocationErrorKind.permissionDenied:
        _cancelPositionStream();
        _signal = SignalStatus.permissionRevoked;
      case LocationErrorKind.other:
        _signal = SignalStatus.noRecentFix;
    }
    _notify();
  }

  void _onServiceChanged(bool enabled) {
    if (_phase != WalkPhase.active) return;
    if (!enabled) {
      _cancelPositionStream();
      _signal = SignalStatus.gpsDisabled;
      _notify();
    } else if (!_inBackground && !isListening) {
      resumeTracking();
    }
  }

  // Hands pending points to Firestore. Failed points go back in the queue;
  // their IDs are fixed, so a retry can't duplicate them.
  Future<void> _flush() {
    final walk = _walk;
    if (walk == null || _pending.isEmpty) return Future.value();
    final batch = List<LocationPoint>.of(_pending);
    _pending.clear();
    _lastFlushAt = _now();
    return _walkRepository.appendLocationPoints(walk, batch).catchError(
      (Object error) {
        if (_phase == WalkPhase.active) _pending.insertAll(0, batch);
        _errorMessage = "Some of your route couldn't be saved yet.";
        _notify();
      },
    );
  }

  // Firestore only completes a write once the server confirms it. Offline,
  // the write is already safe in the local cache, so stop waiting after a
  // while instead of freezing the UI.
  Future<void> _persist(Future<Object?> write) => write
      .then<void>((_) {})
      .timeout(config.persistTimeout, onTimeout: () {});

  void _cancelPositionStream() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  void _stopTracking() {
    _cancelPositionStream();
    _serviceSub?.cancel();
    _serviceSub = null;
    _housekeeping?.cancel();
    _housekeeping = null;
  }

  void _setPhase(WalkPhase phase) {
    _phase = phase;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_phase == WalkPhase.active) _flush();
    _stopTracking();
    _disposed = true;
    _stopEvents.close();
    super.dispose();
  }
}
