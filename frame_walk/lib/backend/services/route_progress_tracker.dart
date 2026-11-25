import '../../models/location_point.dart';
import '../../models/walked_route.dart';

enum StopProximity { upcoming, approaching, reached }

enum StopEventType { approaching, reached }

class StopEvent {
  final StopEventType type;
  final WalkedStop stop;
  final double distanceMeters;
  final DateTime time;

  const StopEvent({
    required this.type,
    required this.stop,
    required this.distanceMeters,
    required this.time,
  });
}

// Which stops are checked on each reading.
enum StopOrder {
  // Only the next unreached stop, in route order. Later stops can't be
  // reached until it is, so a loop that passes a later stop early doesn't
  // tick it off.
  sequential,

  // Any unreached stop, so stops can be visited in any order.
  anyOrder,
}

// Follows a user along a route's stops. Pure logic with no I/O, so it can be
// tested with plain coordinates.
//
// A stop is "approaching" once the user is within [approachRadiusMeters] and
// "reached" within [arrivalRadiusMeters] (widened by up to
// [accuracyAllowanceMeters] when the GPS is less precise). Each event fires
// only once per stop, and one reading reaches at most one stop.
//
// A reading only confirms an arrival if it can be trusted:
// - its accuracy is no worse than [maxArrivalAccuracyMeters], and
// - when [maxPlausibleSpeedMetersPerSecond] is set, it isn't a jump from the
//   previous reading faster than that (a GPS glitch, not the user).
// An untrusted reading can still report "approaching", which is only a hint.
class RouteProgressTracker {
  final double approachRadiusMeters;
  final double arrivalRadiusMeters;
  final double accuracyAllowanceMeters;
  final double maxArrivalAccuracyMeters;
  final double? maxPlausibleSpeedMetersPerSecond;
  final StopOrder stopOrder;

  final List<WalkedStop> _stops;
  final List<GeoCoordinate> _path;
  final Map<String, StopProximity> _proximity;
  GeoCoordinate? _lastPosition;
  LocationSample? _lastSample;

  RouteProgressTracker({
    required List<WalkedStop> stops,
    List<GeoCoordinate> routePath = const [],
    this.approachRadiusMeters = 75,
    this.arrivalRadiusMeters = 25,
    this.accuracyAllowanceMeters = 15,
    this.maxArrivalAccuracyMeters = 25,
    this.maxPlausibleSpeedMetersPerSecond,
    this.stopOrder = StopOrder.sequential,
  }) : _stops = List.of(stops),
       _path = routePath.isNotEmpty
           ? List.unmodifiable(routePath)
           : List.unmodifiable(stops.map((stop) => stop.coordinate)),
       _proximity = {
         for (final stop in stops)
           stop.stopId: stop.reachedAt != null
               ? StopProximity.reached
               : StopProximity.upcoming,
       } {
    if (arrivalRadiusMeters <= 0 ||
        approachRadiusMeters < arrivalRadiusMeters) {
      throw ArgumentError(
        'Approach radius must be at least the (positive) arrival radius',
      );
    }
    if (maxArrivalAccuracyMeters <= 0) {
      throw ArgumentError('Arrival accuracy limit must be positive');
    }
  }

  List<WalkedStop> get stops => List.unmodifiable(_stops);

  StopProximity proximityOf(String stopId) =>
      _proximity[stopId] ?? StopProximity.upcoming;

  int get reachedCount =>
      _proximity.values.where((p) => p == StopProximity.reached).length;

  int get totalStops => _stops.length;

  bool get allStopsReached => _stops.isNotEmpty && reachedCount == totalStops;

  double get fractionComplete => _stops.isEmpty ? 0 : reachedCount / totalStops;

  // The first stop, in route order, that hasn't been reached yet.
  WalkedStop? get nextStop {
    for (final stop in _stops) {
      if (proximityOf(stop.stopId) != StopProximity.reached) return stop;
    }
    return null;
  }

  double? get distanceToNextStopMeters {
    final next = nextStop;
    final position = _lastPosition;
    if (next == null || position == null) return null;
    return GeoMath.distanceMeters(position, next.coordinate);
  }

  // How far the user is from the route line. Null before the first reading.
  double? get distanceFromRouteMeters {
    final position = _lastPosition;
    if (position == null || _path.isEmpty) return null;
    return GeoMath.distanceToPathMeters(position, _path);
  }

  // Updates progress with a reading the caller has already judged accurate
  // enough to record. Returns the events this reading caused, in route
  // order: at most one "reached".
  List<StopEvent> update(LocationSample sample) {
    final position = sample.coordinate;
    final trustedForArrival = _isTrustedForArrival(sample);
    _lastPosition = position;
    _lastSample = sample;

    final allowance = sample.accuracyMeters.clamp(0, accuracyAllowanceMeters);
    final reachRadius = arrivalRadiusMeters + allowance;

    final events = <StopEvent>[];
    var reachedOne = false;
    for (final i in _stopsToCheck()) {
      final stop = _stops[i];
      final distance = GeoMath.distanceMeters(position, stop.coordinate);
      if (!reachedOne && trustedForArrival && distance <= reachRadius) {
        reachedOne = true;
        _proximity[stop.stopId] = StopProximity.reached;
        _stops[i] = stop.copyWithReachedAt(sample.recordedAt);
        events.add(
          StopEvent(
            type: StopEventType.reached,
            stop: _stops[i],
            distanceMeters: distance,
            time: sample.recordedAt,
          ),
        );
      } else if (distance <= approachRadiusMeters &&
          proximityOf(stop.stopId) == StopProximity.upcoming) {
        _proximity[stop.stopId] = StopProximity.approaching;
        events.add(
          StopEvent(
            type: StopEventType.approaching,
            stop: stop,
            distanceMeters: distance,
            time: sample.recordedAt,
          ),
        );
      }
    }
    return events;
  }

  // Indexes of the unreached stops this reading may affect, in route order.
  Iterable<int> _stopsToCheck() sync* {
    for (var i = 0; i < _stops.length; i++) {
      if (proximityOf(_stops[i].stopId) == StopProximity.reached) continue;
      yield i;
      if (stopOrder == StopOrder.sequential) return;
    }
  }

  bool _isTrustedForArrival(LocationSample sample) {
    if (sample.accuracyMeters > maxArrivalAccuracyMeters) return false;
    final maxSpeed = maxPlausibleSpeedMetersPerSecond;
    final previous = _lastSample;
    if (maxSpeed == null || previous == null) return true;
    final seconds =
        sample.recordedAt.difference(previous.recordedAt).inMilliseconds /
            1000;
    // Readings with the same or out-of-order timestamps can't be judged.
    if (seconds <= 0) return true;
    final step = GeoMath.distanceMeters(previous.coordinate, sample.coordinate);
    return step / seconds <= maxSpeed;
  }
}
