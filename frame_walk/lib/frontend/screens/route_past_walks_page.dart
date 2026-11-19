import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/providers/profile_provider.dart';
import '../../backend/services/walk_photo_service.dart';
import '../../models/walk_photo.dart';
import '../../models/walked_route.dart';
import '../widgets/walk_photo_thumbnail.dart';
import 'walk_gallery_page.dart';

// Shows each time the user completed a particular route,
// with the photos associated with that individual walk.
class RoutePastWalksPage extends StatefulWidget {
  const RoutePastWalksPage({
    super.key,
    required this.routeId,
    required this.routeTitle,
    this.photoService,
  });

  final String routeId;
  final String routeTitle;
  final WalkPhotoService? photoService;

  @override
  State<RoutePastWalksPage> createState() => _RoutePastWalksPageState();
}

class _RoutePastWalksPageState extends State<RoutePastWalksPage> {
  late final WalkPhotoService _photoService =
      widget.photoService ?? WalkPhotoService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: Consumer<ProfileProvider>(
        builder: (context, profile, child) {
          if (profile.isLoading || profile.status == ProfileStatus.initial) {
            return const Center(child: CircularProgressIndicator());
          }

          if (profile.status == ProfileStatus.signedOut) {
            return const Center(
              child: Text('Please log in to view your walks.'),
            );
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

          // Only show completed walks belonging to this route.
          final walks =
              profile.walkedRoutes
                  .where((walk) => walk.routeId == widget.routeId)
                  .toList()
                ..sort(
                  (a, b) => (b.completedAt ?? DateTime(0)).compareTo(
                    a.completedAt ?? DateTime(0),
                  ),
                );

          // The number of stops is the same for each completed walk
          // of this route, so use the first walk to get that count.
          final stopCount = walks.isEmpty ? 0 : walks.first.stops.length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Route title and summary below the back button.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.routeTitle,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$stopCount stops  ·  Walked ${walks.length} '
                      '${walks.length == 1 ? 'time' : 'times'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              if (walks.isEmpty)
                const Expanded(
                  child: Center(child: Text('No completed walks found.')),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: walks.length,
                    itemBuilder: (context, index) {
                      return _PastWalkTile(
                        walk: walks[index],
                        photoService: _photoService,
                        onTap: () {
                          WalkGalleryPage.open(context, walks[index].id);
                        },
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// Displays one completed walk and its associated photo thumbnails.
class _PastWalkTile extends StatefulWidget {
  const _PastWalkTile({
    required this.walk,
    required this.photoService,
    required this.onTap,
  });

  final WalkedRoute walk;
  final WalkPhotoService photoService;
  final VoidCallback onTap;

  @override
  State<_PastWalkTile> createState() => _PastWalkTileState();
}

class _PastWalkTileState extends State<_PastWalkTile> {
  late Future<List<WalkPhoto>> _photos;

  @override
  void initState() {
    super.initState();
    _photos = widget.photoService.fetchPhotos(widget.walk.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final date = widget.walk.completedAt == null
        ? 'Date unavailable'
        : MaterialLocalizations.of(context)
              .formatMediumDate(widget.walk.completedAt!.toLocal());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date heading and number of stops for this individual walk.
          InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Text(date, style: theme.textTheme.titleLarge),
                  const SizedBox(width: 4),
                  const Spacer(),
                  const Icon(Icons.place_outlined, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.walk.stops.length} stops',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),

          // Load photos belonging to this specific completed walk.
          FutureBuilder<List<WalkPhoto>>(
            future: _photos,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return Card(
                  color: Colors.white,
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.photo_library_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Could not load photos for this walk.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _photos = widget.photoService.fetchPhotos(
                                widget.walk.id,
                              );
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final photos = snapshot.data ?? [];

              if (photos.isEmpty) {
                return Card(
                  color: Colors.white,
                  elevation: 1,
                  child: InkWell(
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(16),
                    child: const Padding(
                      padding: EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Icon(Icons.photo_library_outlined),
                          SizedBox(width: 12),
                          Text('No photos from this walk yet'),
                          Spacer(),
                          Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                );
              }

              // Display a small preview of this walk's photos.
              // The photos scroll horizontally instead of appearing in a grid.
              final previewPhotos = photos.take(4).toList();

              return Card(
                color: Colors.white,
                elevation: 1,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  onTap: widget.onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 110,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: previewPhotos.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final photo = previewPhotos[index];

                              return SizedBox(
                                width: 110,
                                height: 110,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: WalkPhotoThumbnail(
                                    key: ValueKey(photo.photoId),
                                    photo: photo,
                                    service: widget.photoService,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              '${photos.length} photo${photos.length == 1 ? '' : 's'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'View gallery',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
