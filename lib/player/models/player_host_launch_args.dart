import '../controllers/mpv_player_controller.dart';

class PlayerHostLaunchArgs {
  final String title;
  final MpvMediaSource source;
  final bool fromParallelHost;
  final String layoutMode;
  final String initialRightPaneRoute;

  const PlayerHostLaunchArgs({
    required this.title,
    required this.source,
    required this.fromParallelHost,
    required this.layoutMode,
    required this.initialRightPaneRoute,
  });

  static PlayerHostLaunchArgs? fromPlatformMap(Map<Object?, Object?> raw) {
    return fromNormalizedMap(_normalizeMap(raw));
  }

  static PlayerHostLaunchArgs? fromNormalizedMap(Map<String, dynamic> raw) {
    final title = (raw['title'] ?? '').toString().trim();
    final sourceMap = _mapValue(raw['source']);
    if (title.isEmpty || sourceMap == null) return null;
    final layoutMode = (raw['layoutMode'] ?? 'fullscreen').toString().trim();
    return PlayerHostLaunchArgs(
      title: title,
      source: MpvMediaSource.fromMap(sourceMap),
      fromParallelHost: raw['fromParallelHost'] == true,
      layoutMode: layoutMode.isEmpty ? 'fullscreen' : layoutMode,
      initialRightPaneRoute: (raw['initialRightPaneRoute'] ?? '')
          .toString()
          .trim(),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'title': title,
      'source': source.toMap(),
      'fromParallelHost': fromParallelHost,
      'layoutMode': layoutMode,
      'initialRightPaneRoute': initialRightPaneRoute,
    };
  }

  static Map<String, dynamic> _normalizeMap(Map<Object?, Object?> raw) {
    final normalized = <String, dynamic>{};
    raw.forEach((key, value) {
      normalized[key?.toString() ?? ''] = _normalizeValue(value);
    });
    return normalized;
  }

  static dynamic _normalizeValue(Object? value) {
    if (value is Map<Object?, Object?>) {
      return _normalizeMap(value);
    }
    if (value is List) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    return value;
  }

  static Map<String, dynamic>? _mapValue(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map<Object?, Object?>) {
      return _normalizeMap(value);
    }
    return null;
  }
}
