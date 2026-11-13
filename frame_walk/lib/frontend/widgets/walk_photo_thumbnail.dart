import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../backend/services/walk_photo_service.dart';
import '../../models/walk_photo.dart';

// A square thumbnail of a saved photo. The image is only downloaded when this
// widget is built, so inside a ListView.builder photos load as they scroll
// into view, and are freed when they scroll away.
class WalkPhotoThumbnail extends StatefulWidget {
  const WalkPhotoThumbnail({
    super.key,
    required this.photo,
    required this.service,
    this.size = 96,
  });

  final WalkPhoto photo;
  final WalkPhotoService service;
  final double size;

  @override
  State<WalkPhotoThumbnail> createState() => _WalkPhotoThumbnailState();
}

class _WalkPhotoThumbnailState extends State<WalkPhotoThumbnail> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.service.loadPhotoBytes(widget.photo);
  }

  @override
  void didUpdateWidget(WalkPhotoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.photoId != widget.photo.photoId) {
      _bytes = widget.service.loadPhotoBytes(widget.photo);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return PhotoBytesThumbnail(bytes: snapshot.data!, size: widget.size);
        }
        return _Placeholder(
          size: widget.size,
          child: snapshot.hasError
              ? const Icon(Icons.broken_image_outlined)
              : const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
        );
      },
    );
  }
}

// A thumbnail from bytes already in memory, such as a photo picked but not
// saved yet.
class PhotoBytesThumbnail extends StatelessWidget {
  const PhotoBytesThumbnail({super.key, required this.bytes, this.size = 96});

  final Uint8List bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Decode at thumbnail size, not full resolution, to save memory.
        cacheWidth: pixels,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _Placeholder(
          size: size,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
