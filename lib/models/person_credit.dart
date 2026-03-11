class PersonCredit {
  final String itemGuid;
  final String personGuid;
  final String role;
  final String job;
  final int order;
  final String name;
  final String originalName;
  final String profilePath;

  const PersonCredit({
    required this.itemGuid,
    required this.personGuid,
    required this.role,
    required this.job,
    required this.order,
    required this.name,
    required this.originalName,
    required this.profilePath,
  });

  factory PersonCredit.fromJson(Map<String, dynamic> json) {
    return PersonCredit(
      itemGuid: (json['item_guid'] ?? '').toString(),
      personGuid: (json['person_guid'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      job: (json['job'] ?? '').toString(),
      order: _asInt(json['order']),
      name: (json['name'] ?? '').toString(),
      originalName: (json['original_name'] ?? '').toString(),
      profilePath: (json['profile_path'] ?? '').toString(),
    );
  }

  String get displayName {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    final o = originalName.trim();
    if (o.isNotEmpty) return o;
    return '\u672A\u77E5';
  }

  String get displaySubTitle {
    final r = role.trim();
    if (r.isNotEmpty && r != '(voice)') return '\u9970 $r';
    final j = job.trim();
    if (j.isEmpty) return '';
    switch (j.toLowerCase()) {
      case 'director':
        return '\u5BFC\u6F14';
      case 'actor':
        return '\u6F14\u5458';
      case 'screenplay':
        return '\u7F16\u5267';
      default:
        return j;
    }
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}
