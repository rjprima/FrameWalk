import 'package:flutter/material.dart';

import '../../models/photo_route.dart';
import '../widgets/route_card.dart';
import '../widgets/route_search_bar.dart';
import '../widgets/route_filter_chips.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _query = ''; //current search query
  String _duration = 'Any duration'; //selected duration drop down option
  String _distance = 'Any distance'; //selected distance drop down option
  String _scenery = 'Any scenery'; //selected sceneryb drop down option

  //for now, hard coded in routes
  final List<PhotoRoute> _routes = [
    const PhotoRoute(
      id: '1',
      title: 'Red Square Walk',
      durationMinutes: 10,
      distanceMiles: 0.5,
      sceneryTags: ['Architecture', 'Urban'],
    ),
    const PhotoRoute(
      id: '2',
      title: 'UW Nature Walk',
      durationMinutes: 20,
      distanceMiles: 1.2,
      sceneryTags: ['Nature', 'Urban'],
    ),
    const PhotoRoute(
      id: '3',
      title: 'Waterfront Views',
      durationMinutes: 30,
      distanceMiles: 1.8,
      sceneryTags: ['Water', 'Nature'],
    ),
  ];

  // gets list of routes based on chosen filters/query
  List<PhotoRoute> get _filteredRoutes {
    return _routes.where((route) {
      final matchesQuery = route.title.toLowerCase().contains(
        _query.toLowerCase(),
      );

      final matchesDuration =
          _duration == 'Any duration' ||
          (_duration == '0-15 min' && route.durationMinutes <= 15) ||
          (_duration == '15-30 min' &&
              route.durationMinutes > 15 &&
              route.durationMinutes <= 30) ||
          (_duration == '30+ min' && route.durationMinutes > 30);

      final matchesDistance =
          _distance == 'Any distance' ||
          (_distance == 'Under 1 mi' && route.distanceMiles < 1) ||
          (_distance == '1-2 mi' &&
              route.distanceMiles >= 1 &&
              route.distanceMiles <= 2) ||
          (_distance == '2+ mi' && route.distanceMiles > 2);

      final matchesScenery =
          _scenery == 'Any scenery' ||
          route.sceneryTags.any(
            (tag) => tag.toLowerCase() == _scenery.toLowerCase(),
          );

      //returned routes need to match all query and drop down selections
      return matchesQuery &&
          matchesDuration &&
          matchesDistance &&
          matchesScenery;
    }).toList();
  }

  void _toggleBookmark(PhotoRoute route) {
    setState(() {
      final index = _routes.indexWhere(
        (r) => r.id == route.id,
      ); // gets route from _routes with matching id as route arg
      if (index != -1) {
        // flips isBookmarked for the found route - maybe we think about
        // changing this to not create a copy of the route and to instead
        // have a function to flip isBookmarked depending on how we store routes
        _routes[index] = _routes[index].copyWith(
          isBookmarked: !_routes[index].isBookmarked,
        );
      }
    });
  }

  //TODO: Replace this with navigation to route detail page.
  void _openRoute(PhotoRoute route) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Selected ${route.title}')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              'FrameWalk',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RouteSearchBar(
              onChanged: (value) {
                setState(() => _query = value);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Center(
              child: RouteFilterChips(
                duration: _duration,
                distance: _distance,
                scenery: _scenery,
                onDurationChanged: (value) {
                  setState(() => _duration = value);
                },
                onDistanceChanged: (value) {
                  setState(() => _distance = value);
                },
                onSceneryChanged: (value) {
                  setState(() => _scenery = value);
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Suggested Routes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _filteredRoutes.isEmpty
                ? const Center(child: Text('No matching routes found.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filteredRoutes.length,
                    itemBuilder: (context, index) {
                      final route = _filteredRoutes[index];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: RouteCard(
                          route: route,
                          onTap: () => _openRoute(route),
                          onBookmarkTap: () => _toggleBookmark(route),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
