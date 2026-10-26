
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _query = '';
  String _duration = 'Any duration';
  String _distance = 'Any distance';
  String _scenery = 'Any scenery';

  // final List<PhotoRoute> _routes = [
  //   const PhotoRoute(
  //     id: '1',
  //     title: 'Red Square Walk',
  //     durationMinutes: 10,
  //     distanceMiles: 0.5,
  //     sceneryTags: ['Architecture', 'Easy'],
  //   ),
  //   const PhotoRoute(
  //     id: '2',
  //     title: 'UW Nature Walk',
  //     durationMinutes: 20,
  //     distanceMiles: 1.2,
  //     sceneryTags: ['Nature', 'Easy'],
  //   ),
  //   const PhotoRoute(
  //     id: '3',
  //     title: 'Waterfront Views',
  //     durationMinutes: 30,
  //     distanceMiles: 1.8,
  //     sceneryTags: ['Water', 'Nature'],
  //   ),
  // ];

  // List<PhotoRoute> get _filteredRoutes {
  //   return _routes.where((route) {
  //     final matchesQuery = route.title
  //         .toLowerCase()
  //         .contains(_query.toLowerCase());

  //     final matchesDuration =
  //         _duration == 'Any duration' ||
  //         (_duration == '0-15 min' &&
  //             route.durationMinutes <= 15) ||
  //         (_duration == '15-30 min' &&
  //             route.durationMinutes > 15 &&
  //             route.durationMinutes <= 30) ||
  //         (_duration == '30+ min' &&
  //             route.durationMinutes > 30);

  //     final matchesDistance =
  //         _distance == 'Any distance' ||
  //         (_distance == 'Under 1 mi' &&
  //             route.distanceMiles < 1) ||
  //         (_distance == '1-2 mi' &&
  //             route.distanceMiles >= 1 &&
  //             route.distanceMiles <= 2) ||
  //         (_distance == '2+ mi' &&
  //             route.distanceMiles > 2);

  //     final matchesScenery =
  //         _scenery == 'Any scenery' ||
  //         route.sceneryTags.any(
  //           (tag) => tag.toLowerCase() == _scenery.toLowerCase(),
  //         );

  //     return matchesQuery &&
  //         matchesDuration &&
  //         matchesDistance &&
  //         matchesScenery;
  //   }).toList();
  // }

  // void _toggleBookmark(PhotoRoute route) {
  //   setState(() {
  //     final index = _routes.indexWhere((r) => r.id == route.id);
  //     if (index != -1) {
  //       _routes[index] = _routes[index].copyWith(
  //         isBookmarked: !_routes[index].isBookmarked,
  //       );
  //     }
  //   });
  // }

  // void _openRoute(PhotoRoute route) {
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(content: Text('Selected ${route.title}')),
  //   );

  //   // Replace this with navigation to your route detail page.
  // }

   @override
   Widget build(BuildContext context) {
    return Placeholder();
   }
  //   return Scaffold(
  //     body: SafeArea(
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Padding(
  //             padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
  //             child: Text(
  //               'FrameWalk',
  //               style: Theme.of(context).textTheme.titleLarge,
  //             ),
  //           ),
  //           Padding(
  //             padding: const EdgeInsets.symmetric(horizontal: 16),
  //             child: RouteSearchBar(
  //               onChanged: (value) {
  //                 setState(() => _query = value);
  //               },
  //             ),
  //           ),
  //           Padding(
  //             padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
  //             child: RouteFilterChips(
  //               duration: _duration,
  //               distance: _distance,
  //               scenery: _scenery,
  //               onDurationChanged: (value) {
  //                 setState(() => _duration = value);
  //               },
  //               onDistanceChanged: (value) {
  //                 setState(() => _distance = value);
  //               },
  //               onSceneryChanged: (value) {
  //                 setState(() => _scenery = value);
  //               },
  //             ),
  //           ),
  //           const Padding(
  //             padding: EdgeInsets.symmetric(horizontal: 16),
  //             child: Text(
  //               'Suggested Routes',
  //               style: TextStyle(fontWeight: FontWeight.bold),
  //             ),
  //           ),
  //           const SizedBox(height: 8),
  //           Expanded(
  //             child: _filteredRoutes.isEmpty
  //                 ? const Center(
  //                     child: Text('No matching routes found.'),
  //                   )
  //                 : ListView.builder(
  //                     padding: const EdgeInsets.symmetric(
  //                       horizontal: 12,
  //                     ),
  //                     itemCount: _filteredRoutes.length,
  //                     itemBuilder: (context, index) {
  //                       final route = _filteredRoutes[index];

  //                       return Padding(
  //                         padding: const EdgeInsets.only(bottom: 8),
  //                         child: RouteCard(
  //                           route: route,
  //                           onTap: () => _openRoute(route),
  //                           onBookmarkTap: () =>
  //                               _toggleBookmark(route),
  //                         ),
  //                       );
  //                     },
  //                   ),
  //           ),
  //         ],
  //       ),
  //     ),
  //     bottomNavigationBar: const AppBottomNav(),
  //   );
  // }
}
