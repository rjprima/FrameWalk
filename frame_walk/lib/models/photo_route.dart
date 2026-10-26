// Represents a photo route - can change this later
class PhotoRoute {
  final String id;
  final String title;
  final int durationMinutes;
  final double distanceMiles;
  final List<String> sceneryTags;
  final bool isBookmarked;

  const PhotoRoute({
    required this.id,
    required this.title,
    required this.durationMinutes,
    required this.distanceMiles,
    required this.sceneryTags,
    this.isBookmarked = false,
  });

  PhotoRoute copyWith({bool? isBookmarked}) {
    return PhotoRoute(
      id: id,
      title: title,
      durationMinutes: durationMinutes,
      distanceMiles: distanceMiles,
      sceneryTags: sceneryTags,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }
}
