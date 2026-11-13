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

// Follows a user along a route's stops. Pure logic with no I/O, so it can be
// tested with plain coordinates.
//
// Stops can be reached in any order. A stop is "approaching" once the user is
// within [approachRadiusMeters] and "reached" within [arrivalRadiusMeters]
// (widened by up to [accuracyAllowanceMeters] when the GPS is less precise).
// Each event fires only once per stop.
class RouteProgressTracker {
  final double approachRadiusMeters;
  final double arrivalRadiusMeters;
  final double accuracyAllowanceMeters;

  final List<WalkedStop> _stops;
  final List<GeoCoordinate> _path;
  final Map<String, StopProximity> _proximity;
  GeoCoordinate? _lastPosition;

  RouteProgressTracker({
    required List<WalkedStop> stops,
    List<GeoCoordinate> routePath = const [],
    this.approachRadiusMeters = 75,
    this.arrivalRadiusMeters = 25,
    this.accuracyAllowanceMeters = 15,
  })  : _stops = List.of(stops),
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
  }

  List<WalkedStop> get stops => List.unmodifiable(_stops);

  StopProximity proximityOf(String stopId) =>
      _proximity[stopId] ?? StopProximity.upcoming;

  int get reachedCount =>
      _proximity.values.where((p) => p == StopProximity.reached).length;

  int get totalStops => _stops.length;

  bool get allStopsReached => _stops.isNotEmpty && reachedCount == totalStops;

  double get fractionComplete =>
      _stops.isEmpty ? 0 : reachedCount / totalStops;

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
  // enough. Returns the events this reading caused, in route order.
  List<StopEvent> update(LocationSample sample) {
    final position = sample.coordinate;
    _lastPosition = position;

    final allowance = sample.accuracyMeters.clamp(0, accuracyAllowanceMeters);
    final reachRadius = arrivalRadiusMeters + allowance;

    final events = <StopEvent>[];
    for (var i = 0; i < _stops.length; i++) {
      final stop = _stops[i];
      final current = proximityOf(stop.stopId);
      if (current == StopProximity.reached) continue;

      final distance = GeoMath.distanceMeters(position, stop.coordinate);
      if (distance <= reachRadius) {
        _proximity[stop.stopId] = StopProximity.reached;
        _stops[i] = stop.copyWithReachedAt(sample.recordedAt);
        events.add(StopEvent(
          type: StopEventType.reached,
          stop: _stops[i],
          distanceMeters: distance,
          time: sample.recordedAt,
        ));
      } else if (distance <= approachRadiusMeters &&
          current == StopProximity.upcoming) {
        _proximity[stop.stopId] = StopProximity.approaching;
        events.add(StopEvent(
          type: StopEventType.approaching,
          stop: stop,
          distanceMeters: distance,
          time: sample.recordedAt,
        ));
      }
    }
    return events;
  }
}
