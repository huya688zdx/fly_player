import 'dart:convert';

class DanmakuSettings {
  final bool enabled;
  final bool previewEnabled;
  final bool preferLocalSource;
  final bool scrollEnabled;
  final bool topEnabled;
  final bool bottomEnabled;
  final bool colorEnabled;
  final bool hideDuplicate;
  final bool avoidSubtitleArea;
  final bool avoidCenterArea;
  final double opacity;
  final double fontScale;
  final double speed;
  final double displayAreaRatio;

  const DanmakuSettings({
    required this.enabled,
    required this.previewEnabled,
    required this.preferLocalSource,
    required this.scrollEnabled,
    required this.topEnabled,
    required this.bottomEnabled,
    required this.colorEnabled,
    required this.hideDuplicate,
    required this.avoidSubtitleArea,
    required this.avoidCenterArea,
    required this.opacity,
    required this.fontScale,
    required this.speed,
    required this.displayAreaRatio,
  });

  static const DanmakuSettings defaults = DanmakuSettings(
    enabled: false,
    previewEnabled: false,
    preferLocalSource: true,
    scrollEnabled: true,
    topEnabled: true,
    bottomEnabled: false,
    colorEnabled: true,
    hideDuplicate: true,
    avoidSubtitleArea: true,
    avoidCenterArea: true,
    opacity: 0.85,
    fontScale: 1.0,
    speed: 1.0,
    displayAreaRatio: 0.50,
  );

  DanmakuSettings copyWith({
    bool? enabled,
    bool? previewEnabled,
    bool? preferLocalSource,
    bool? scrollEnabled,
    bool? topEnabled,
    bool? bottomEnabled,
    bool? colorEnabled,
    bool? hideDuplicate,
    bool? avoidSubtitleArea,
    bool? avoidCenterArea,
    double? opacity,
    double? fontScale,
    double? speed,
    double? displayAreaRatio,
  }) {
    return DanmakuSettings(
      enabled: enabled ?? this.enabled,
      previewEnabled: previewEnabled ?? this.previewEnabled,
      preferLocalSource: preferLocalSource ?? this.preferLocalSource,
      scrollEnabled: scrollEnabled ?? this.scrollEnabled,
      topEnabled: topEnabled ?? this.topEnabled,
      bottomEnabled: bottomEnabled ?? this.bottomEnabled,
      colorEnabled: colorEnabled ?? this.colorEnabled,
      hideDuplicate: hideDuplicate ?? this.hideDuplicate,
      avoidSubtitleArea: avoidSubtitleArea ?? this.avoidSubtitleArea,
      avoidCenterArea: avoidCenterArea ?? this.avoidCenterArea,
      opacity: opacity ?? this.opacity,
      fontScale: fontScale ?? this.fontScale,
      speed: speed ?? this.speed,
      displayAreaRatio: displayAreaRatio ?? this.displayAreaRatio,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'previewEnabled': previewEnabled,
      'preferLocalSource': preferLocalSource,
      'scrollEnabled': scrollEnabled,
      'topEnabled': topEnabled,
      'bottomEnabled': bottomEnabled,
      'colorEnabled': colorEnabled,
      'hideDuplicate': hideDuplicate,
      'avoidSubtitleArea': avoidSubtitleArea,
      'avoidCenterArea': avoidCenterArea,
      'opacity': opacity,
      'fontScale': fontScale,
      'speed': speed,
      'displayAreaRatio': displayAreaRatio,
    };
  }

  String encode() => jsonEncode(toJson());

  static DanmakuSettings decode(String raw) {
    if (raw.trim().isEmpty) return defaults;
    final json = jsonDecode(raw);
    if (json is! Map) return defaults;
    return fromJson(Map<String, dynamic>.from(json));
  }

  static DanmakuSettings fromJson(Map<String, dynamic> json) {
    return defaults.copyWith(
      enabled: json['enabled'] == true,
      previewEnabled: json['previewEnabled'] == true,
      preferLocalSource: json['preferLocalSource'] != false,
      scrollEnabled: json['scrollEnabled'] != false,
      topEnabled: json['topEnabled'] != false,
      bottomEnabled: json['bottomEnabled'] == true,
      colorEnabled: json['colorEnabled'] != false,
      hideDuplicate: json['hideDuplicate'] != false,
      avoidSubtitleArea: json['avoidSubtitleArea'] != false,
      avoidCenterArea: json['avoidCenterArea'] != false,
      opacity: _readDouble(json['opacity'], defaults.opacity),
      fontScale: _readDouble(json['fontScale'], defaults.fontScale),
      speed: _readDouble(json['speed'], defaults.speed),
      displayAreaRatio: _readDouble(
        json['displayAreaRatio'],
        defaults.displayAreaRatio,
      ),
    );
  }

  static double _readDouble(dynamic value, double fallback) {
    final parsed = switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text),
      _ => null,
    };
    return parsed ?? fallback;
  }
}
