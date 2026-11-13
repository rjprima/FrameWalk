import 'package:flutter/material.dart';

import '../../backend/services/walk_photo_service.dart';
import '../../models/walk_photo.dart';
import '../utils/photo_picker.dart';
import '../widgets/walk_photo_thumbnail.dart';
import 'walk_photo_editor_page.dart';

// Photos for one completed walk, grouped by the prompt they answer, plus a
// "No prompt" group. A minimal screen for testing the photo backend; all
// data access goes through WalkPhotoService.
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
    // Some changes may have saved even if the editor was closed after an
    // error, so always refresh.
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WalkPhotoGallery>(
      future: _gallery,
      builder: (context, snapshot) {
        final gallery = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(gallery?.walk.routeTitle ?? 'Walk photos'),
          ),
          floatingActionButton: gallery == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _openEditor(gallery),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    gallery.photos.isEmpty ? 'Add photos' : 'Add / edit photos',
                  ),
                ),
          body: _body(snapshot),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: sections.length,
        itemBuilder: (context, index) =>
            _PromptSection(section: sections[index], service: _service),
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
    final textTheme = Theme.of(context).textTheme;
    final subtitle = section.subtitle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${section.title} (${section.photos.length})',
            style: textTheme.titleMedium,
          ),
          if (subtitle != null && subtitle.isNotEmpty)
            Text(subtitle, style: textTheme.bodyMedium),
          const SizedBox(height: 8),
          if (section.photos.isEmpty)
            Text('No photos yet', style: textTheme.bodySmall)
          else
            SizedBox(
              height: 96,
              // Horizontal builder, so only visible thumbnails download.
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: section.photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => WalkPhotoThumbnail(
                  key: ValueKey(section.photos[index].photoId),
                  photo: section.photos[index],
                  service: service,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
