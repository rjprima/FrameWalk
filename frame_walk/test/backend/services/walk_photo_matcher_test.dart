import 'package:flutter_test/flutter_test.dart';
import 'package:frame_walk/backend/services/walk_photo_matcher.dart';
import 'package:frame_walk/models/gallery_photo.dart';

import 'fakes/fake_local_photo_service.dart';

void main() {
  const matcher = WalkPhotoMatcher();
  final walk = redSquareWalk();
  final duringWalk = walkStart.add(const Duration(minutes: 10));

  group('Timestamp matching', () {
    test('accepts a photo taken during the walk', () {
      final match = matcher.match(walk, photoAt('a', duringWalk));
      expect(match.isLikelyFromWalk, isTrue);
    });

    test('accepts photos just before the start and just after the end', () {
      final early = walkStart.subtract(const Duration(minutes: 4));
      final late = walkEnd.add(const Duration(minutes: 14));
      expect(matcher.match(walk, photoAt('a', early)).isLikelyFromWalk, isTrue);
      expect(matcher.match(walk, photoAt('b', late)).isLikelyFromWalk, isTrue);
    });

    test('rejects photos outside the time window', () {
      final dayBefore = walkStart.subtract(const Duration(days: 1));
      final hourAfter = walkEnd.add(const Duration(hours: 1));
      expect(
        matcher.match(walk, photoAt('a', dayBefore)).strength,
        MatchStrength.outsideWindow,
      );
      expect(
        matcher.match(walk, photoAt('b', hourAfter)).strength,
        MatchStrength.outsideWindow,
      );
    });

    test('rejects an out-of-window photo even if taken at a stop', () {
      final match = matcher.match(
        walk,
        photoAt('a', walkStart.subtract(const Duration(days: 3)),
            location: redSquare),
      );
      expect(match.strength, MatchStrength.outsideWindow);
      expect(match.stopId, isNull);
    });
  });

  group('GPS matching', () {
    test('photos without GPS match on time alone', () {
      final match = matcher.match(walk, photoAt('a', duringWalk));
      expect(match.strength, MatchStrength.timeOnly);
      expect(match.stopId, isNull);
    });

    test('a photo taken at a stop is matched to that stop', () {
      final match =
          matcher.match(walk, photoAt('a', duringWalk, location: suzzallo));
      expect(match.strength, MatchStrength.atStop);
      expect(match.stopId, 'red_stop_2');
      expect(match.distanceMeters, lessThan(1));
    });

    test('picks the nearest stop when a photo is a few meters off', () {
      // About 20 m north of Red Square.
      const nearby = GeoCoordinate(47.65608, -122.3078);
      final match =
          matcher.match(walk, photoAt('a', duringWalk, location: nearby));
      expect(match.stopId, 'red_stop_1');
    });

    test('a photo on the path between stops is near the route', () {
      // Halfway from Suzzallo to Drumheller Fountain, over 100 m from every
      // stop.
      const between = GeoCoordinate(47.6549, -122.30845);
      final match =
          matcher.match(walk, photoAt('a', duringWalk, location: between));
      expect(match.strength, MatchStrength.nearRoute);
      expect(match.isLikelyFromWalk, isTrue);
    });

    test('a photo far from the route is not suggested', () {
      // Downtown Seattle, about 6 km away.
      const downtown = GeoCoordinate(47.6062, -122.3321);
      final match =
          matcher.match(walk, photoAt('a', duringWalk, location: downtown));
      expect(match.strength, MatchStrength.farFromRoute);
      expect(match.isLikelyFromWalk, isFalse);
    });

    test('treats (0, 0) and invalid values as no GPS', () {
      expect(GeoCoordinate.tryCreate(0, 0), isNull);
      expect(GeoCoordinate.tryCreate(null, 10), isNull);
      expect(GeoCoordinate.tryCreate(95, 10), isNull);
      expect(GeoCoordinate.tryCreate(double.nan, 10), isNull);
      expect(GeoCoordinate.tryCreate(47.6, -122.3), isNotNull);
    });

    test('measures distance accurately', () {
      // Red Square to Suzzallo is about 175 m.
      final distance = WalkPhotoMatcher.distanceMeters(redSquare, suzzallo);
      expect(distance, closeTo(175, 10));
    });
  });
}
