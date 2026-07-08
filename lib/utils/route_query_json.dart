import 'dart:convert';

class RouteQueryJson {
  const RouteQueryJson._();

  static Map<String, dynamic>? tryDecodeMap(String raw) {
    final source = raw.trim();
    if (source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      return decoded.cast<String, dynamic>();
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static List<String>? tryDecodeStringList(String raw) {
    final source = raw.trim();
    if (source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return null;
      return decoded.map((value) => '$value').toList(growable: false);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
