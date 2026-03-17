class MediaItem {
  final String id;
  final String name;
  final String? type;
  final String? path;
  final List<String> posters;
  final Map<String, dynamic>? meta;

  MediaItem({
    required this.id,
    required this.name,
    this.type,
    this.path,
    this.posters = const [],
    this.meta,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final rawPosters = json['posters'];
    final posters = rawPosters is List
        ? rawPosters.map((e) => e.toString()).toList()
        : <String>[];

    return MediaItem(
      id: (json['guid'] ?? json['id'] ?? '').toString(),
      name: (json['title'] ?? json['name'] ?? 'Unknown').toString(),
      type: (json['category'] ?? json['type'])?.toString(),
      path: (json['poster'] ?? json['path'])?.toString(),
      posters: posters,
      meta: json['meta'],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'guid': id,
      'name': name,
      'type': type,
      'path': path,
      'posters': posters,
      'meta': meta,
    };
  }
}
