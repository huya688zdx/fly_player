class MediaLocaleText {
  MediaLocaleText._();

  static String text(
    Map<String, dynamic> localeMap,
    String path, {
    required String fallback,
    Map<String, Object?> params = const {},
  }) {
    final dynamic value = _value(localeMap, path);
    final raw = value is String && value.trim().isNotEmpty ? value : fallback;
    if (params.isEmpty) return raw;

    var resolved = _normalizeSimpleIcu(raw);
    params.forEach((key, val) {
      resolved = resolved.replaceAll('{$key}', '${val ?? ''}');
    });
    return resolved;
  }

  static String _normalizeSimpleIcu(String raw) {
    final trimmed = raw.trim();
    final match = RegExp(
      r'^\{(\w+),\s*plural,\s*other\s*\{(.+)\}\}$',
      dotAll: true,
    ).firstMatch(trimmed);
    if (match == null) return raw;
    return match.group(2)?.trim() ?? raw;
  }

  static dynamic _value(Map<String, dynamic> localeMap, String path) {
    dynamic current = localeMap;
    for (final segment in path.split('.')) {
      if (current is Map<String, dynamic>) {
        if (!current.containsKey(segment)) return null;
        current = current[segment];
        continue;
      }
      if (current is Map) {
        if (!current.containsKey(segment)) return null;
        current = current[segment];
        continue;
      }
      return null;
    }
    return current;
  }
}
