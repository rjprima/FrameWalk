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

  // ~10 m north of Red Square, so within both its and stop A's radius.
  const stopNearA = WalkedStop(
    stopId: 'near-a',
    stopName: 'Red Square fountain',
    latitude: 47.6559 + 10 / 111195,
    longitude: -122.3078,
  );

  // Moves [meters] north of a stop (1 degree of latitude ~ 111,195 m),
  // [seconds] after t0.
  LocationSample northOf(
    WalkedStop stop,
    double meters, {
    double acc = 5,
    int seconds = 0,
  }) =>
      sampleAt(
        stop.latitude + meters / 111195,
        stop.longitude,
        t0.add(Duration(seconds: seconds)),
        accuracy: acc,
      );

  List<StopEventType> types(List<StopEvent> events) =>
      events.map((e) => e.type).toList();

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

    test('allows stops to be reached out of order when configured', () {
      final tracker = RouteProgressTracker(
        stops: [stopA, stopB],
        stopOrder: StopOrder.anyOrder,
      );
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

  group('arrival detection', () {
    test('only the next stop can be reached, in route order', () {
      final tracker = RouteProgressTracker(stops: [stopA, stopB]);

      expect(
        tracker.update(northOf(stopB, 0)),
        isEmpty,
        reason: 'B is not next, so it is neither approached nor reached',
      );
      expect(tracker.proximityOf('b'), StopProximity.upcoming);
      expect(tracker.nextStop!.stopId, 'a');

      expect(types(tracker.update(northOf(stopA, 0))), [StopEventType.reached]);
      expect(types(tracker.update(northOf(stopB, 0))), [StopEventType.reached]);
      expect(tracker.allStopsReached, isTrue);
    });

    test('one reading reaches at most one stop', () {
      final tracker = RouteProgressTracker(stops: [stopA, stopNearA]);
      final reading = northOf(stopA, 5);

      final first = tracker.update(reading);
      expect(types(first), [StopEventType.reached]);
      expect(first.single.stop.stopId, 'a');
      expect(tracker.proximityOf('near-a'), StopProximity.upcoming);

      // The next reading at the same place reaches the following stop.
      final second = tracker.update(northOf(stopA, 5, seconds: 10));
      expect(types(second), [StopEventType.reached]);
      expect(second.single.stop.stopId, 'near-a');
    });

    test('one reading reaches at most one stop in any order too', () {
      final tracker = RouteProgressTracker(
        stops: [stopA, stopNearA],
        stopOrder: StopOrder.anyOrder,
      );
      final events = tracker.update(northOf(stopA, 5));
      expect(
        events.where((e) => e.type == StopEventType.reached),
        hasLength(1),
      );
      expect(tracker.reachedCount, 1);
    });

    test('never reports the same arrival twice', () {
      final tracker = RouteProgressTracker(stops: [stopA, stopB]);
      final reached = <String>[];
      for (var i = 0; i < 5; i++) {
        for (final event in tracker.update(northOf(stopA, 2, seconds: i))) {
          if (event.type == StopEventType.reached) {
            reached.add(event.stop.stopId);
          }
        }
      }
      expect(reached, ['a']);
    });

    test('does not confirm arrival from an imprecise reading', () {
      final tracker = RouteProgressTracker(stops: [stopA]);

      // At the stop, but 30 m accuracy is worse than the 25 m limit.
      expect(
        types(tracker.update(northOf(stopA, 0, acc: 30))),
        [StopEventType.approaching],
        reason: 'an imprecise reading may still hint that the stop is near',
      );
      expect(tracker.proximityOf('a'), StopProximity.approaching);

      expect(
        types(tracker.update(northOf(stopA, 0, acc: 8, seconds: 5))),
        [StopEventType.reached],
      );
    });

    test('does not confirm arrival from a GPS jump', () {
      final tracker = RouteProgressTracker(
        stops: [stopA],
        maxPlausibleSpeedMetersPerSecond: 12,
      );
      tracker.update(northOf(stopA, 500));

      // 500 m in 10 s is 50 m/s: a glitch, not the user.
      expect(
        types(tracker.update(northOf(stopA, 0, seconds: 10))),
        isNot(contains(StopEventType.reached)),
      );
      expect(tracker.proximityOf('a'), isNot(StopProximity.reached));

      // A follow-up reading nearby, at walking pace, confirms it.
      expect(
        types(tracker.update(northOf(stopA, 3, seconds: 20))),
        [StopEventType.reached],
      );
    });

    test('accepts a long gap between readings as plausible', () {
      final tracker = RouteProgressTracker(
        stops: [stopA],
        maxPlausibleSpeedMetersPerSecond: 12,
      );
      tracker.update(northOf(stopA, 500));
      // 500 m in 5 minutes, e.g. after losing signal indoors.
      expect(
        types(tracker.update(northOf(stopA, 0, seconds: 300))),
        [StopEventType.reached],
      );
    });

    test('uses the configured arrival radius', () {
      final tight = RouteProgressTracker(
        stops: [stopA],
        arrivalRadiusMeters: 10,
        accuracyAllowanceMeters: 0,
      );
      expect(
        types(tight.update(northOf(stopA, 20))),
        [StopEventType.approaching],
      );
      expect(
        types(tight.update(northOf(stopA, 8, seconds: 5))),
        [StopEventType.reached],
      );
    });

    test('rejects a non-positive arrival accuracy limit', () {
      expect(
        () => RouteProgressTracker(
          stops: const [stopA],
          maxArrivalAccuracyMeters: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
