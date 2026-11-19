import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/providers/profile_provider.dart';
import '../../backend/services/walk_photo_service.dart';
import '../../models/walk_photo.dart';
import '../utils/photo_picker.dart';
import '../widgets/walk_photo_thumbnail.dart';
import 'walk_photo_editor_page.dart';

// Displays photos for one particular completed walk, grouped by prompt.
class WalkGalleryPage extends StatefulWidget {
  const WalkGalleryPage({
    super.key,
    required this.walkedRouteId,
    this.service,
    this.pickPhotos = pickPhotosFromLibrary,
  });

  final String walkedRouteId;
  final WalkPhotoService? service;
  final PickPhotos pickPhotos;

  static Future<void> open(BuildContext context, String walkedRouteId) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => WalkGalleryPage(walkedRouteId: walkedRouteId),
      ),
    );
  }

  @override
  State<WalkGalleryPage> createState() => _WalkGalleryPageState();
}

class _WalkGalleryPageState extends State<WalkGalleryPage> {
  late final WalkPhotoService _service = widget.service ?? WalkPhotoService();

  late Future<WalkPhotoGallery> _gallery;

  @override
  void initState() {
    super.initState();
    _gallery = _service.fetchGallery(widget.walkedRouteId);
  }

  void _reload() {
    final next = _service.fetchGallery(widget.walkedRouteId);

    setState(() {
      _gallery = next;
    });
  }

  Future<void> _openEditor(WalkPhotoGallery gallery) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => WalkPhotoEditorPage(
          gallery: gallery,
          service: _service,
          pickPhotos: widget.pickPhotos,
        ),
      ),
    );

    // Refresh after returning from the editor.
    if (!mounted) return;

    _reload();
    context.read<ProfileProvider?>()?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<WalkPhotoGallery>(
      future: _gallery,
      builder: (context, snapshot) {
        final gallery = snapshot.data;

        final date = gallery?.walk.completedAt == null
            ? 'Walk photos'
            : MaterialLocalizations.of(context)
                  .formatMediumDate(gallery!.walk.completedAt!.toLocal());

        return Scaffold(
          appBar: AppBar(
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            backgroundColor: Theme.of(context).colorScheme.surface,
          ),
          floatingActionButton: gallery == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _openEditor(gallery),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    gallery.photos.isEmpty ? 'Add photos' : 'Add / edit photos',
                  ),
                ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date heading below the back button.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(date, style: theme.textTheme.headlineMedium),
              ),

              Expanded(child: _body(snapshot)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<WalkPhotoGallery> snapshot) {
    if (snapshot.hasError) {
      final error = snapshot.error;

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is PhotoFailure ? error.message : 'Could not load photos',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _reload,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final gallery = snapshot.data;

    if (gallery == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final sections = [
      for (final prompt in gallery.prompts)
        _Section(
          title: prompt.stopName,
          subtitle: prompt.prompt,
          photos: gallery.photosForStop(prompt.stopId),
        ),
      _Section(title: 'No prompt', photos: gallery.unassigned),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _gallery;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: sections.length,
        itemBuilder: (context, index) {
          return _PromptSection(section: sections[index], service: _service);
        },
      ),
    );
  }
}

class _Section {
  final String title;
  final String? subtitle;
  final List<WalkPhoto> photos;

  const _Section({required this.title, required this.photos, this.subtitle});
}

class _PromptSection extends StatelessWidget {
  const _PromptSection({required this.section, required this.service});

  final _Section section;
  final WalkPhotoService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = section.subtitle;

    return Card(
      color: Colors.white,
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(section.title, style: theme.textTheme.titleLarge),

            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],

            const SizedBox(height: 12),

            if (section.photos.isEmpty)
              _EmptyPhotoPlaceholder()
            else
              // Horizontally scrolling photos for this prompt.
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: section.photos.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final photo = section.photos[index];

                    return SizedBox(
                      width: 110,
                      height: 110,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: WalkPhotoThumbnail(
                          key: ValueKey(photo.photoId),
                          photo: photo,
                          service: service,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}


// Placeholder with the same dimensions and shape as a photo thumbnail.
class _EmptyPhotoPlaceholder extends StatelessWidget {
  const _EmptyPhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 26,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Flexible(
            child: Text(
              'No photos yet',
              textAlign: TextAlign.center,
              softWrap: true,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
