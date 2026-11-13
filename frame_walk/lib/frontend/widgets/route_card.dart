
import 'package:flutter/material.dart';
import '../../backend/services/route_manager.dart';

// Shared by route cards and the bookmark button on the route details page.
// Bookmarks are updated by the existing callback; feedback is UI-only.
void toggleRouteBookmarkWithFeedback(
  BuildContext context, {
  required bool isBookmarked,
  required VoidCallback onToggle,
}) {
  onToggle();
  if (isBookmarked) return; // Removing a bookmark needs no save confirmation.
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Saved to Saved Walks in Activity.'),
        duration: Duration(seconds: 2),
      ),
    );
}

class RouteCard extends StatelessWidget {
  final WalkingRoute route;
  final VoidCallback onTap;
  final VoidCallback onBookmarkTap;

  const RouteCard({
    super.key,
    required this.route,
    required this.onTap,
    required this.onBookmarkTap,
  });

  @override
  Widget build(BuildContext context) {
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
                      route.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: route.isBookmarked
                        ? 'Remove bookmark'
                        : 'Bookmark route',
                    onPressed: () => toggleRouteBookmarkWithFeedback(
                      context,
                      isBookmarked: route.isBookmarked,
                      onToggle: onBookmarkTap,
                    ),
                    icon: Icon(
                      route.isBookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16),
                  const SizedBox(width: 4),
                  Text('${route.estimatedMinutes} min'),
                  const SizedBox(width: 12),
                  const Icon(Icons.place_outlined, size: 16),
                  const SizedBox(width: 4),
                  Text('${route.distanceMiles} mi'),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: route.sceneryTags.map((tag) {
                  return Chip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
