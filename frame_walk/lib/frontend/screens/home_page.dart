import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/providers/route_provider.dart';
import '../widgets/route_card.dart';
import '../widgets/route_filter_chips.dart';
import '../widgets/route_search_bar.dart';
import 'route_info_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _query = '';
  String _duration = RouteProvider.anyDuration;
  String _distance = RouteProvider.anyDistance;
  String _scenery = RouteProvider.anyScenery;

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
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Center(
              child: RouteFilterChips(
                duration: _duration,
                distance: _distance,
                scenery: _scenery,
                onDurationChanged: (v) => setState(() => _duration = v),
                onDistanceChanged: (v) => setState(() => _distance = v),
                onSceneryChanged: (v) => setState(() => _scenery = v),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Suggested Routes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          // Consumer is this low so that only the list rebuilds when routes or bookmarks change.
          Expanded(
            child: Consumer<RouteProvider>(
              builder: (context, provider, _) {
                // gets the filtered list of routes based on the current search params
                final routes = provider.search(
                  query: _query,
                  duration: _duration,
                  distance: _distance,
                  scenery: _scenery,
                );
                if (routes.isEmpty) {
                  return const Center(child: Text('No matching routes found.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: routes.length,
                  itemBuilder: (context, index) {
                    final route = routes[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RouteCard(
                        route: route,
                        onTap: () => RouteInfoPage.open(context, route),
                        onBookmarkTap: () => provider.toggleBookmark(route.id),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
