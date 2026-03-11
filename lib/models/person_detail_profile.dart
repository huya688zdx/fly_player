class PersonDetailProfile {
  final String guid;
  final String name;
  final String originalName;
  final String profilePath;
  final String imdbId;
  final String trimId;
  final String biography;
  final bool isFavorite;

  const PersonDetailProfile({
    required this.guid,
    required this.name,
    required this.originalName,
    required this.profilePath,
    required this.imdbId,
    required this.trimId,
    required this.biography,
    required this.isFavorite,
  });

  factory PersonDetailProfile.fromJson(Map<String, dynamic> json) {
    return PersonDetailProfile(
      guid: (json['guid'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      originalName: (json['original_name'] ?? '').toString(),
      profilePath: (json['profile'] ?? json['profile_path'] ?? '').toString(),
      imdbId: (json['imdb_id'] ?? json['imdbId'] ?? '').toString(),
      trimId: (json['trim_id'] ?? json['trimId'] ?? '').toString(),
      biography: (json['biography'] ?? '').toString(),
      isFavorite: _toInt(json['is_favorite']) == 1,
    );
  }

  String get displayName {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    final o = originalName.trim();
    if (o.isNotEmpty) return o;
    return '\u672a\u77e5';
  }
}

int _toInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}
