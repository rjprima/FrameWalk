import 'package:flutter_test/flutter_test.dart';
import '../services/route_manager.dart';

void main() {
  late RouteManager routeManager;

  // Create a new RouteManager before every test.
  setUp(() {
    routeManager = RouteManager();
  });

  group('RouteManager Tests', () {

    // Test 1: Add a route successfully.
    test('Adds a walking route', () {
      final route = WalkingRoute(
        id: 'route1',
        name: 'UW Campus Walk',
        stopIds: ['stop1', 'stop2'],
      );

      routeManager.addRoute(route);

      expect(routeManager.getRoute('route1'), equals(route));
    });

    // Test 2: Retrieve an existing route.
    test('Retrieves a route by ID', () {
      routeManager.addRoute(
        WalkingRoute(
          id: 'route1',
          name: 'Red Square Walk',
          stopIds: ['stop1'],
        ),
      );

      final result = routeManager.getRoute('route1');

      expect(result, isNotNull);
      expect(result!.name, equals('Red Square Walk'));
    });

    // Test 3: Retrieve all routes.
    test('Returns all available routes', () {
      routeManager.addRoute(
        WalkingRoute(
          id: 'route1',
          name: 'UW Campus Walk',
          stopIds: ['stop1'],
        ),
      );

      routeManager.addRoute(
        WalkingRoute(
          id: 'route2',
          name: 'Fountain Walk',
          stopIds: ['stop2'],
        ),
      );

      expect(routeManager.getAllRoutes().length, equals(2));
    });

    // Test 4: Retrieve photography stops.
    test('Returns stops for a route', () {
      routeManager.addRoute(
        WalkingRoute(
          id: 'route1',
          name: 'UW Campus Walk',
          stopIds: ['stop1', 'stop2'],
        ),
      );

      final stops = routeManager.getStopsForRoute('route1');

      expect(stops, equals(['stop1', 'stop2']));
    });

    // Test 5: Remove a route.
    test('Removes an existing route', () {
      routeManager.addRoute(
        WalkingRoute(
          id: 'route1',
          name: 'UW Campus Walk',
          stopIds: ['stop1'],
        ),
      );

      final removed = routeManager.removeRoute('route1');

      expect(removed, isTrue);
      expect(routeManager.getRoute('route1'), isNull);
    });

    // Test 6: Reject duplicate route IDs.
    test('Rejects duplicate route IDs', () {
      final route = WalkingRoute(
        id: 'route1',
        name: 'UW Campus Walk',
        stopIds: ['stop1'],
      );

      routeManager.addRoute(route);

      expect(
        () => routeManager.addRoute(route),
        throwsArgumentError,
      );
    });

    // Test 7: Reject empty route IDs.
    test('Rejects empty route IDs', () {
      expect(
        () => routeManager.addRoute(
          WalkingRoute(
            id: '',
            name: 'Invalid Route',
            stopIds: [],
          ),
        ),
        throwsArgumentError,
      );
    });

    // Test 8: Reject empty route names.
    test('Rejects empty route names', () {
      expect(
        () => routeManager.addRoute(
          WalkingRoute(
            id: 'route1',
            name: '',
            stopIds: [],
          ),
        ),
        throwsArgumentError,
      );
    });

    // Test 9: Unknown routes return null.
    test('Returns null for unknown routes', () {
      expect(routeManager.getRoute('unknown'), isNull);
    });

    // Test 10: Unknown routes return no stops.
    test('Returns empty stops for unknown routes', () {
      expect(routeManager.getStopsForRoute('unknown'), isEmpty);
    });

    // Test 11: Reject empty IDs when retrieving.
    test('Rejects empty IDs during retrieval', () {
      expect(
        () => routeManager.getRoute(''),
        throwsArgumentError,
      );
    });

    // Test 12: Reject empty IDs when removing.
    test('Rejects empty IDs during removal', () {
      expect(
        () => routeManager.removeRoute(''),
        throwsArgumentError,
      );
    });

    // Test 13: Removing an unknown route returns false.
    test('Returns false for unknown route removal', () {
      expect(routeManager.removeRoute('unknown'), isFalse);
    });

    // Test 14: Prevent changes to returned route lists.
    test('Prevents modifying the route list', () {
      routeManager.addRoute(
        WalkingRoute(
          id: 'route1',
          name: 'UW Campus Walk',
          stopIds: ['stop1'],
        ),
      );

      expect(
        () => routeManager.getAllRoutes().clear(),
        throwsUnsupportedError,
      );
    });

    // Test 15: Prevent changes to photography stops.
    test('Prevents modifying stop IDs', () {
      final route = WalkingRoute(
        id: 'route1',
        name: 'UW Campus Walk',
        stopIds: ['stop1'],
      );

      expect(
        () => route.stopIds.add('stop2'),
        throwsUnsupportedError,
      );
    });
  });
}
