import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/providers/profile_provider.dart';
import '../../models/walked_route.dart';
import '../screens/route_past_walks_page.dart';

/// Displays each unique route the user has completed - if they've done a
/// route multiple times, it shows up once. Tapping a route opens the history of
/// walks for that route.
class CompletedWalksList extends StatelessWidget {
  const CompletedWalksList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, profile, child) {

        checkValidProfileState(profile);

        // Group completed walks by route ID.
        final groupedWalks = <String, List<WalkedRoute>>{};

        for (final walk in profile.walkedRoutes) {
          groupedWalks.putIfAbsent(walk.routeId, () => []).add(walk);
        }

        // Sort individual walks within each route, newest first.
        for (final walks in groupedWalks.values) {
          walks.sort(
            (a, b) => (b.completedAt ?? DateTime(0)).compareTo(
              a.completedAt ?? DateTime(0),
            ),
          );
        }

        // Sort routes by their most recent completion date.
        final routes = groupedWalks.entries.toList()
          ..sort((a, b) {
            final aDate = a.value.first.completedAt ?? DateTime(0);
            final bDate = b.value.first.completedAt ?? DateTime(0);
            return bDate.compareTo(aDate);
          });

        return RefreshIndicator(
          onRefresh: profile.refresh,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              if (routes.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: Text('No previous walks yet.')),
                )
              else
                ...routes.map((entry) {
                  final walks = entry.value;
                  final latestWalk = walks.first;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _RouteHistoryCard(
                      routeTitle: latestWalk.routeTitle,
                      timesWalked: walks.length,
                      latestWalk: latestWalk,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RoutePastWalksPage(
                              routeId: entry.key,
                              routeTitle: latestWalk.routeTitle,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

Center checkValidProfileState(ProfileProvider profile){
  if (profile.isLoading || profile.status == ProfileStatus.initial) {
          return const Center(child: CircularProgressIndicator());
        }

        if (profile.status == ProfileStatus.signedOut) {
          return const Center(child: Text('Please log in to view your walks.'));
        }

        if (profile.status == ProfileStatus.error) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.errorMessage ?? 'Could not load your walks.'),
                TextButton(
                  onPressed: profile.refresh,
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
        }

        return Center(child: Text('Something went wrong, please reload to try again'));
}

class _RouteHistoryCard extends StatelessWidget {
  const _RouteHistoryCard({
    required this.routeTitle,
    required this.timesWalked,
    required this.latestWalk,
    required this.onTap,
  });

  final String routeTitle;
  final int timesWalked;
  final WalkedRoute latestWalk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final date = latestWalk.completedAt == null
        ? 'Date unavailable'
        : MaterialLocalizations.of(context)
              .formatMediumDate(latestWalk.completedAt!.toLocal());

    return Card(
      color: Colors.white,
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      routeTitle.isEmpty ? 'Walk' : routeTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '$timesWalked time${timesWalked == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.place_outlined, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${latestWalk.stops.length} stops',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Last walked: $date',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
