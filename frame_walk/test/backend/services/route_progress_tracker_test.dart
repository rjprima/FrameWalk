import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/route_progress_tracker.dart';
import 'package:frame_walk/models/location_point.dart';
import 'package:frame_walk/models/walked_route.dart';

import '../../fakes/fake_location_source.dart';

void main() {
  // Two stops ~220 m apart on campus.
  const stopA = WalkedStop(
    stopId: 'a',
    stopName: 'Red Square',
    latitude: 47.6559,
    longitude: -122.3078,
    prompt: 'Find a pattern.',
  );
  const stopB = WalkedStop(
    stopId: 'b',
    stopName: 'Suzzallo Library',
    latitude: 47.6553,
    longitude: -122.3099,
  );
  final t0 = DateTime(2026, 11, 9, 10);

  // Moves [meters] north of a stop (1 degree of latitude ~ 111,195 m).
  LocationSample northOf(WalkedStop stop, double meters, {double acc = 5}) =>
      sampleAt(
        stop.latitude + meters / 111195,
        stop.longitude,
        t0,
        accuracy: acc,
      );

  group('GeoMath', () {
    test('measures distance between coordinates', () {
      final d = GeoMath.distanceMeters(
        const GeoCoordinate(47.6559, -122.3078),
        const GeoCoordinate(47.6569, -122.3078),
      );
      expect(d, closeTo(111.2, 0.5));
    });

    test('measures distance to the nearest segment of a path', () {
      const path = [
        GeoCoordinate(47.6500, -122.3000),
        GeoCoordinate(47.6500, -122.2900),
      ];
      // 0.001 degrees of latitude north of the middle of the segment.
      final d = GeoMath.distanceToPathMeters(
        const GeoCoordinate(47.6510, -122.2950),
        path,
      );
      expect(d, closeTo(111.2, 1));
    });
  });

  group('RouteProgressTracker', () {
    test('starts with no stops reached and the first stop next', () {
      final tracker = RouteProgressTracker(stops: [stopA, stopB]);
      expect(tracker.reachedCount, 0);
      expect(tracker.nextStop!.stopId, 'a');
      expect(tracker.fractionComplete, 0);
      expect(tracker.distanceToNextStopMeters, isNull);
    });

    test('reports approaching once, then reached once', () {
      final tracker = RouteProgressTracker(stops: [stopA, stopB]);

      expect(tracker.update(northOf(stopA, 150)), isEmpty);

      final approaching = tracker.update(northOf(stopA, 60));
      expect(approaching.single.type, StopEventType.approaching);
      expect(tracker.proximityOf('a'), StopProximity.approaching);

      expect(
        tracker.update(northOf(stopA, 50)),
        isEmpty,
        reason: 'approaching fires only once',
      );

      final reached = tracker.update(northOf(stopA, 10));
      expect(reached.single.type, StopEventType.reached);
      expect(reached.single.stop.reachedAt, t0);
      expect(tracker.reachedCount, 1);
      expect(tracker.nextStop!.stopId, 'b');

      expect(
        tracker.update(northOf(stopA, 5)),
        isEmpty,
        reason: 'reached fires only once',
      );
    });

    test('widens the arrival radius for imprecise readings, up to a cap', () {
      final tracker = RouteProgressTracker(stops: [stopA]);
      // 35 m away: outside 25 m, but inside 25 + 15 with a 20 m accuracy.
      expect(
        tracker.update(northOf(stopA, 35, acc: 20)).last.type,
        StopEventType.reached,
      );

      final capped = RouteProgressTracker(stops: [stopA]);
      // 45 m with very poor accuracy: the allowance is capped at 15 m.
      expect(
        capped.update(northOf(stopA, 45, acc: 500)).map((e) => e.type),
        isNot(contains(StopEventType.reached)),
      );
    });

    test('allows stops to be reached out of order', () {
      final tracker = RouteProgressTracker(stops: [stopA, stopB]);
      tracker.update(northOf(stopB, 0));
      expect(tracker.proximityOf('b'), StopProximity.reached);
      expect(tracker.nextStop!.stopId, 'a');
      tracker.update(northOf(stopA, 0));
      expect(tracker.allStopsReached, isTrue);
      expect(tracker.nextStop, isNull);
      expect(tracker.fractionComplete, 1);
    });

    test('reports distance to the next stop and from the route', () {
      final tracker = RouteProgressTracker(stops: [stopA, stopB]);
      tracker.update(northOf(stopA, 100));
      expect(tracker.distanceToNextStopMeters, closeTo(100, 1));
      // The route is the line from A to B, so this point is ~100 m off it
      // (a little less, because the line runs slightly south-west).
      expect(tracker.distanceFromRouteMeters, inInclusiveRange(80, 101));
    });

    test('keeps stops already reached when resumed', () {
      final reachedA = stopA.copyWithReachedAt(t0);
      final tracker = RouteProgressTracker(stops: [reachedA, stopB]);
      expect(tracker.reachedCount, 1);
      expect(tracker.nextStop!.stopId, 'b');
    });

    test('rejects an arrival radius larger than the approach radius', () {
      expect(
        () => RouteProgressTracker(
          stops: const [stopA],
          approachRadiusMeters: 10,
          arrivalRadiusMeters: 20,
        ),
        throwsArgumentError,
      );
    });
  });
}
