
import 'package:flutter/material.dart';
import '../../models/photo_route.dart';

class RouteCard extends StatelessWidget {
  final PhotoRoute route;
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
                      route.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: route.isBookmarked
                        ? 'Remove bookmark'
                        : 'Bookmark route',
                    onPressed: onBookmarkTap,
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
                  Text('${route.durationMinutes} min'),
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
