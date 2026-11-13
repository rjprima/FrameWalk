import 'package:flutter_test/flutter_test.dart';
import '../services/route_manager.dart';
import '../../models/mock_route_data.dart';
import '../providers/route_provider.dart';

WalkingRoute makeRoute(
  String id, {
  String? name,
  int minutes = 10,
  double miles = 0.5,
  List<String> tags = const [],
  bool bookmarked = false,
}) {
  return WalkingRoute(
    id: id,
    name: name ?? 'Route $id',
    stopIds: const [],
    estimatedMinutes: minutes,
    distanceMiles: miles,
    sceneryTags: tags,
    isBookmarked: bookmarked,
  );
}

/// Provider with no seed data, filled with the given routes.
RouteProvider makeProvider(List<WalkingRoute> routes) {
  final provider = RouteProvider(seedMockData: false);
  for (final route in routes) {
    provider.addRoute(route);
  }
  return provider;
}

List<String> ids(List<WalkingRoute> routes) =>
    routes.map((r) => r.id).toList();

void main() {

  // This group tests that RouteProviders are constructed as expected
  group('construction', () {
    test('starts empty when seedMockData is false', () {
      final provider = RouteProvider(seedMockData: false);
      expect(provider.routes, isEmpty);
      expect(provider.bookmarkedRoutes, isEmpty);
    });

    test('seeds MockRouteData.routes by default', () {
      final provider = RouteProvider();
      expect(ids(provider.routes), ids(MockRouteData.routes));
    });

    test('uses an injected manager', () {
      final manager = RouteManager()..addRoute(makeRoute('x'));
      final provider = RouteProvider(manager: manager, seedMockData: false);
      expect(ids(provider.routes), ['x']);
    });
  });

  // This group tests that seeded data is consistent (has expected info)
  group('seed data consistency', () {
    // Guards against a route that can't render on RouteInfoPage.
    final provider = RouteProvider();

    test('every seeded route has stops', () {
      for (final route in provider.routes) {
        expect(
          MockRouteData.getStops(route.id),
          isNotEmpty,
          reason: '${route.id} has no stops',
        );
      }
    });

    test('every seeded route has map points', () {
      for (final route in provider.routes) {
        expect(
          MockRouteData.getRoutePoints(route.id),
          isNotEmpty,
          reason: '${route.id} has no route points',
        );
      }
    });

    test('stopIds match the stops returned by getStops', () {
      for (final route in provider.routes) {
        final stopIds =
            MockRouteData.getStops(route.id).map((s) => s.id).toList();
        expect(route.stopIds, stopIds, reason: route.id);
      }
    });
  });

// Tests if provider looks up routes correctly
  group('lookup', () {
    late RouteProvider provider;

    setUp(() {
      provider = makeProvider([
        makeRoute('a'),
        makeRoute('b', bookmarked: true),
      ]);
    });

    test('byId returns the route', () {
      expect(provider.byId('a')?.id, 'a');
    });

    test('byId returns null for an unknown id', () {
      expect(provider.byId('nope'), isNull);
    });

    test('byId returns null for null, empty, or blank ids', () {
      expect(provider.byId(null), isNull);
      expect(provider.byId(''), isNull);
      expect(provider.byId('   '), isNull);
    });

    test('isBookmarked reflects the stored route', () {
      expect(provider.isBookmarked('a'), isFalse);
      expect(provider.isBookmarked('b'), isTrue);
    });

    test('isBookmarked is false for an unknown id', () {
      expect(provider.isBookmarked('nope'), isFalse);
    });
  });

  // Tests if provider bookmarks routes correctly
  group('bookmarks', () {
    late RouteProvider provider;
    late int notifications;

    setUp(() {
      provider = makeProvider([makeRoute('a'), makeRoute('b')]);
      notifications = 0;
      provider.addListener(() => notifications++);
    });

    test('toggleBookmark bookmarks and un-bookmarks a route', () {
      provider.toggleBookmark('a');
      expect(provider.isBookmarked('a'), isTrue);

      provider.toggleBookmark('a');
      expect(provider.isBookmarked('a'), isFalse);
    });

    test('toggleBookmark notifies listeners once per change', () {
      provider.toggleBookmark('a');
      expect(notifications, 1);

      provider.toggleBookmark('a');
      expect(notifications, 2);
    });

    test('toggleBookmark on an unknown id does nothing and does not notify',
        () {
      provider.toggleBookmark('nope');
      expect(notifications, 0);
      expect(provider.bookmarkedRoutes, isEmpty);
    });

    test('bookmarkedRoutes contains only bookmarked routes', () {
      provider.toggleBookmark('b');
      expect(ids(provider.bookmarkedRoutes), ['b']);
    });

    test('bookmarking does not change other routes or route order', () {
      provider.toggleBookmark('a');
      expect(ids(provider.routes), ['a', 'b']);
      expect(provider.isBookmarked('b'), isFalse);
    });
  });


  // idk if we need to test or have add, remove or update b/c idk what situation would they
  // be used, so these are commented out for now
  // group('add / remove / update', () {
  //   late RouteProvider provider;
  //   late int notifications;

  //   setUp(() {
  //     provider = makeProvider([makeRoute('a')]);
  //     notifications = 0;
  //     provider.addListener(() => notifications++);
  //   });

  //   test('addRoute adds the route and notifies', () {
  //     provider.addRoute(makeRoute('b'));
  //     expect(ids(provider.routes), ['a', 'b']);
  //     expect(notifications, 1);
  //   });

  //   test('addRoute with a duplicate id throws and does not notify', () {
  //     expect(() => provider.addRoute(makeRoute('a')), throwsArgumentError);
  //     expect(notifications, 0);
  //     expect(provider.routes.length, 1);
  //   });

  //   test('removeRoute removes the route and notifies', () {
  //     provider.removeRoute('a');
  //     expect(provider.routes, isEmpty);
  //     expect(notifications, 1);
  //   });

  //   test('removeRoute on an unknown id does not notify', () {
  //     provider.removeRoute('nope');
  //     expect(notifications, 0);
  //     expect(provider.routes.length, 1);
  //   });

  //   test('updateRoute replaces the route and notifies', () {
  //     provider.updateRoute(makeRoute('a', name: 'Renamed'));
  //     expect(provider.byId('a')?.name, 'Renamed');
  //     expect(notifications, 1);
  //   });

  //   test('updateRoute on an unknown id does not notify', () {
  //     provider.updateRoute(makeRoute('nope'));
  //     expect(notifications, 0);
  //     expect(provider.byId('nope'), isNull);
  //   });
  // });

  // Tests if provider searches correctly
  group('search', () {
    late RouteProvider provider;

    setUp(() {
      provider = makeProvider([
        makeRoute('a',
            name: 'Red Square Walk',
            minutes: 10,
            miles: 0.5,
            tags: ['Architecture', 'Urban']),
        makeRoute('b',
            name: 'UW Nature Walk',
            minutes: 20,
            miles: 1.2,
            tags: ['Nature', 'Urban']),
        makeRoute('c',
            name: 'Waterfront Views',
            minutes: 30,
            miles: 1.8,
            tags: ['Water', 'Nature']),
        makeRoute('d',
            name: 'Long Hike', minutes: 45, miles: 2.5, tags: ['Nature']),
      ]);
    });

    test('no arguments returns every route in insertion order', () {
      expect(ids(provider.search()), ['a', 'b', 'c', 'd']);
    });

    group('query', () {
      test('matches part of the name', () {
        expect(ids(provider.search(query: 'walk')), ['a', 'b']);
      });

      test('is case-insensitive', () {
        expect(ids(provider.search(query: 'WATERFRONT')), ['c']);
      });

      test('ignores leading and trailing spaces', () {
        expect(ids(provider.search(query: '  red  ')), ['a']);
      });

      test('returns nothing when no name matches', () {
        expect(provider.search(query: 'zzz'), isEmpty);
      });
    });

    // Tests if provider filters by duration correctly
    group('duration', () {
      test('0-15 min', () {
        expect(ids(provider.search(duration: '0-15 min')), ['a']);
      });

      test('15-30 min', () {
        expect(ids(provider.search(duration: '15-30 min')), ['b', 'c']);
      });

      test('30+ min', () {
        expect(ids(provider.search(duration: '30+ min')), ['d']);
      });

      test('Any duration returns everything', () {
        expect(
          ids(provider.search(duration: RouteProvider.anyDuration)),
          ['a', 'b', 'c', 'd'],
        );
      });

      test('an unrecognized value does not filter', () {
        expect(provider.search(duration: 'bogus').length, 4);
      });
    });

    // Tests if provider filters by distance correctly
    group('distance', () {
      test('Under 1 mi', () {
        expect(ids(provider.search(distance: 'Under 1 mi')), ['a']);
      });

      test('1-2 mi', () {
        expect(ids(provider.search(distance: '1-2 mi')), ['b', 'c']);
      });

      test('2+ mi', () {
        expect(ids(provider.search(distance: '2+ mi')), ['d']);
      });

      test('Any distance returns everything', () {
        expect(
          ids(provider.search(distance: RouteProvider.anyDistance)),
          ['a', 'b', 'c', 'd'],
        );
      });

      test('an unrecognized value does not filter', () {
        expect(provider.search(distance: 'bogus').length, 4);
      });
    });

    // Tests if provider filters by scenery correctly
    group('scenery', () {
      test('matches routes that have the tag', () {
        expect(ids(provider.search(scenery: 'Nature')), ['b', 'c', 'd']);
      });

      test('is case-insensitive', () {
        expect(ids(provider.search(scenery: 'nature')), ['b', 'c', 'd']);
      });

      test('Any scenery returns everything', () {
        expect(
          ids(provider.search(scenery: RouteProvider.anyScenery)),
          ['a', 'b', 'c', 'd'],
        );
      });

      test('returns nothing for a tag no route has', () {
        expect(provider.search(scenery: 'Desert'), isEmpty);
      });
    });

    // Tests if provider filters correctly when doing combinations of searching and filters
    group('combined filters', () {
      test('all filters must match', () {
        expect(
          ids(provider.search(
            query: 'water',
            duration: '15-30 min',
            distance: '1-2 mi',
            scenery: 'Nature',
          )),
          ['c'],
        );
      });

      test('a failing filter excludes an otherwise matching route', () {
        // "UW Nature Walk" matches the query but is 20 minutes, not 30+.
        expect(
          provider.search(query: 'nature walk', duration: '30+ min'),
          isEmpty,
        );
      });
    });

    test('reflects bookmark changes in results', () {
      provider.toggleBookmark('a');
      expect(provider.search(query: 'red').single.isBookmarked, isTrue);
    });
  });

  // tests edge cases of filters 
  group('search boundaries', () {
    late RouteProvider provider;

    setUp(() {
      provider = makeProvider([
        makeRoute('e', minutes: 15, miles: 1.0),
        makeRoute('f', minutes: 16, miles: 2.0),
        makeRoute('g', minutes: 30, miles: 0.99),
        makeRoute('h', minutes: 31, miles: 2.01),
      ]);
    });

    test('duration buckets: 15 is short, 30 is medium, 31 is long', () {
      expect(ids(provider.search(duration: '0-15 min')), ['e']);
      expect(ids(provider.search(duration: '15-30 min')), ['f', 'g']);
      expect(ids(provider.search(duration: '30+ min')), ['h']);
    });

    test('distance buckets: 1.0 and 2.0 are in 1-2 mi', () {
      expect(ids(provider.search(distance: 'Under 1 mi')), ['g']);
      expect(ids(provider.search(distance: '1-2 mi')), ['e', 'f']);
      expect(ids(provider.search(distance: '2+ mi')), ['h']);
    });
  });
}