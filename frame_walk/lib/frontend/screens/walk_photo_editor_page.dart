import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/services/walk_photo_service.dart';
import '../../models/walk_photo.dart';
import '../utils/photo_picker.dart';
import '../widgets/walk_photo_thumbnail.dart';

// Add photos to a walk, change which prompt each belongs to, and remove them.
// Edits are staged in a PhotoChangeSet and nothing is uploaded until Save.
// If a save partly fails, the unsaved changes stay on screen and Save
// becomes Retry. A minimal screen for testing the photo backend.
class WalkPhotoEditorPage extends StatefulWidget {
  const WalkPhotoEditorPage({
    super.key,
    required this.gallery,
    required this.service,
    this.pickPhotos = pickPhotosFromLibrary,
  });

  final WalkPhotoGallery gallery;
  final WalkPhotoService service;
  final PickPhotos pickPhotos;

  @override
  State<WalkPhotoEditorPage> createState() => _WalkPhotoEditorPageState();
}

// Dropdown value for "No prompt" (a null stopId). Stop IDs are never empty.
const String _noPrompt = '';

class _WalkPhotoEditorPageState extends State<WalkPhotoEditorPage> {
  late List<WalkPhoto> _saved = widget.gallery.photos;
  PhotoChangeSet _changes = PhotoChangeSet();
  bool _saving = false;
  SaveProgress? _progress;
  List<PhotoSaveError> _errors = const [];

  String get _walkId => widget.gallery.walk.id;

  // ---------------------------------------------------------------- actions

  Future<void> _addPhotos() async {
    final List<PickedPhoto> picked;
    try {
      picked = await widget.pickPhotos();
    } on PlatformException catch (error) {
      _showMessage(
        'Could not open your photos: ${error.message ?? error.code}',
      );
      return;
    }
    final rejected = <String>[];
    setState(() {
      for (final photo in picked) {
        try {
          _changes.add(
            widget.service.preparePhoto(photo.bytes, fileName: photo.name),
          );
        } on PhotoFailure catch (failure) {
          rejected.add('${photo.name}: ${failure.message}');
        }
      }
    });
    if (rejected.isNotEmpty) {
      _showMessage('Not added:\n${rejected.join('\n')}');
    }
  }

  void _setStop(String photoId, String? stopId) {
    setState(() => _changes.setStop(photoId, stopId));
  }

  void _remove(String photoId) {
    setState(() => _changes.remove(photoId));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _progress = null;
      _errors = const [];
    });
    try {
      final result = await widget.service.saveChanges(
        _walkId,
        _changes,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = result.photos;
        // Whatever didn't save stays staged, so Save retries just that.
        _changes = result.remaining;
        _errors = result.errors;
      });
      if (result.isComplete) {
        _showMessage('Photos saved');
        Navigator.pop(context);
      } else {
        _showMessage('Some changes were not saved. Tap Retry to try again.');
      }
    } on PhotoFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors = [
          PhotoSaveError(
            failure.code,
            failure.message,
            photoId: failure.photoId,
          ),
        ];
      });
      _showMessage(failure.message);
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------- view

  String? _currentStop(WalkPhoto photo) =>
      _changes.stopChanges.containsKey(photo.photoId)
      ? _changes.stopChanges[photo.photoId]
      : photo.stopId;

  String? _errorFor(String photoId) {
    for (final error in _errors) {
      if (error.photoId == photoId) return error.message;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final visibleSaved = _saved
        .where((photo) => !_changes.deletions.contains(photo.photoId))
        .toList();
    final additions = _changes.additions;
    final rows = <Widget>[
      for (final photo in additions)
        _PhotoRow(
          key: ValueKey(photo.photoId),
          thumbnail: PhotoBytesThumbnail(bytes: photo.bytes, size: 72),
          label: 'New${photo.fileName == null ? '' : ' · ${photo.fileName}'}',
          stopId: photo.stopId,
          prompts: widget.gallery.prompts,
          error: _errorFor(photo.photoId),
          enabled: !_saving,
          onStopChanged: (stopId) => _setStop(photo.photoId, stopId),
          onRemove: () => _remove(photo.photoId),
        ),
      for (final photo in visibleSaved)
        _PhotoRow(
          key: ValueKey(photo.photoId),
          thumbnail: WalkPhotoThumbnail(
            photo: photo,
            service: widget.service,
            size: 72,
          ),
          label: _changes.stopChanges.containsKey(photo.photoId)
              ? 'Saved · prompt changed'
              : 'Saved',
          stopId: _currentStop(photo),
          prompts: widget.gallery.prompts,
          error: _errorFor(photo.photoId),
          enabled: !_saving,
          onStopChanged: (stopId) => _setStop(photo.photoId, stopId),
          onRemove: () => _remove(photo.photoId),
        ),
    ];
    final generalErrors = _errors.where((e) => e.photoId == null).toList();
    final pendingDeletes = _changes.deletions.length;

    return PopScope(
      canPop: _changes.isEmpty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit photos'),
          actions: [
            IconButton(
              tooltip: 'Add photos',
              onPressed: _saving ? null : _addPhotos,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_saving) _ProgressBanner(progress: _progress),
            for (final error in generalErrors)
              _ErrorBanner(message: error.message),
            if (pendingDeletes > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  '$pendingDeletes photo${pendingDeletes == 1 ? '' : 's'} '
                  'will be removed from FrameWalk when you save. '
                  'Your device photos are not affected.',
                ),
              ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: TextButton.icon(
                        onPressed: _saving ? null : _addPhotos,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add photos'),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 24),
                      itemBuilder: (_, index) => rows[index],
                    ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _saving || _changes.isEmpty ? null : _save,
              child: Text(
                _saving
                    ? 'Saving...'
                    : _errors.isNotEmpty && !_changes.isEmpty
                    ? 'Retry failed changes (${_changes.changeCount})'
                    : 'Save',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    super.key,
    required this.thumbnail,
    required this.label,
    required this.stopId,
    required this.prompts,
    required this.enabled,
    required this.onStopChanged,
    required this.onRemove,
    this.error,
  });

  final Widget thumbnail;
  final String label;
  final String? stopId;
  final List<WalkPrompt> prompts;
  final bool enabled;
  final ValueChanged<String?> onStopChanged;
  final VoidCallback onRemove;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        thumbnail,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              DropdownButton<String>(
                isExpanded: true,
                value: stopId ?? _noPrompt,
                onChanged: enabled
                    ? (value) => onStopChanged(
                        value == null || value == _noPrompt ? null : value,
                      )
                    : null,
                items: [
                  const DropdownMenuItem(
                    value: _noPrompt,
                    child: Text('No prompt'),
                  ),
                  for (final prompt in prompts)
                    DropdownMenuItem(
                      value: prompt.stopId,
                      child: Text(
                        prompt.prompt.isEmpty
                            ? prompt.stopName
                            : '${prompt.stopName}: ${prompt.prompt}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              if (error != null)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove photo',
          onPressed: enabled ? onRemove : null,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  const _ProgressBanner({required this.progress});

  final SaveProgress? progress;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress?.fraction),
          const SizedBox(height: 4),
          Text(
            progress == null || progress.photosTotal == 0
                ? 'Saving...'
                : 'Uploaded ${progress.photosUploaded} of '
                      '${progress.photosTotal} photos',
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
    );
  }
}
