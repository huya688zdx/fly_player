import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppThemePreset { midnight, ocean, forest, graphite, sunset, aurora, latte }

extension AppThemePresetX on AppThemePreset {
  String get storageValue => switch (this) {
    AppThemePreset.midnight => 'midnight',
    AppThemePreset.ocean => 'ocean',
    AppThemePreset.forest => 'forest',
    AppThemePreset.graphite => 'graphite',
    AppThemePreset.sunset => 'sunset',
    AppThemePreset.aurora => 'aurora',
    AppThemePreset.latte => 'latte',
  };

  String get title => switch (this) {
    AppThemePreset.midnight => 'Midnight',
    AppThemePreset.ocean => 'Ocean',
    AppThemePreset.forest => 'Forest',
    AppThemePreset.graphite => 'Graphite',
    AppThemePreset.sunset => 'Sunset',
    AppThemePreset.aurora => 'Aurora',
    AppThemePreset.latte => 'Latte',
  };

  String get subtitle => switch (this) {
    AppThemePreset.midnight => 'Cinema-inspired dark palette',
    AppThemePreset.ocean => 'Cool ocean palette',
    AppThemePreset.forest => 'Soft natural green palette',
    AppThemePreset.graphite => 'Neutral graphite palette',
    AppThemePreset.sunset => 'Warm sunset palette',
    AppThemePreset.aurora => 'Bright aurora palette',
    AppThemePreset.latte => 'Light latte palette',
  };

  bool get isLight => this == AppThemePreset.latte;

  static AppThemePreset fromStorageValue(String? value) {
    return AppThemePreset.values.firstWhere(
      (preset) => preset.storageValue == value,
      orElse: () => AppThemePreset.midnight,
    );
  }
}

enum AppAccentTone { blue, cyan, green, amber, rose, coral, indigo, mint }

extension AppAccentToneX on AppAccentTone {
  String get storageValue => switch (this) {
    AppAccentTone.blue => 'blue',
    AppAccentTone.cyan => 'cyan',
    AppAccentTone.green => 'green',
    AppAccentTone.amber => 'amber',
    AppAccentTone.rose => 'rose',
    AppAccentTone.coral => 'coral',
    AppAccentTone.indigo => 'indigo',
    AppAccentTone.mint => 'mint',
  };

  String get title => switch (this) {
    AppAccentTone.blue => 'Blue',
    AppAccentTone.cyan => 'Cyan',
    AppAccentTone.green => 'Green',
    AppAccentTone.amber => 'Amber',
    AppAccentTone.rose => 'Rose',
    AppAccentTone.coral => 'Coral',
    AppAccentTone.indigo => 'Indigo',
    AppAccentTone.mint => 'Mint',
  };

  Color get color => switch (this) {
    AppAccentTone.blue => const Color(0xFF3A82F7),
    AppAccentTone.cyan => const Color(0xFF27B5E9),
    AppAccentTone.green => const Color(0xFF37B36B),
    AppAccentTone.amber => const Color(0xFFD39A28),
    AppAccentTone.rose => const Color(0xFFD95B77),
    AppAccentTone.coral => const Color(0xFFE67358),
    AppAccentTone.indigo => const Color(0xFF6B6FE8),
    AppAccentTone.mint => const Color(0xFF39C7A7),
  };

  Color get strongColor => switch (this) {
    AppAccentTone.blue => const Color(0xFF63A0FF),
    AppAccentTone.cyan => const Color(0xFF7AD8FF),
    AppAccentTone.green => const Color(0xFF87E6AC),
    AppAccentTone.amber => const Color(0xFFFFCC67),
    AppAccentTone.rose => const Color(0xFFFF97B2),
    AppAccentTone.coral => const Color(0xFFFFA089),
    AppAccentTone.indigo => const Color(0xFF9EA4FF),
    AppAccentTone.mint => const Color(0xFF8EECD8),
  };

  Color colorFor({required bool light}) {
    return light ? AppThemePalette.mix(color, Colors.white, 0.16) : color;
  }

  Color strongColorFor({required bool light}) {
    return light ? AppThemePalette.emphasize(color) : strongColor;
  }

  static AppAccentTone fromStorageValue(String? value) {
    return AppAccentTone.values.firstWhere(
      (tone) => tone.storageValue == value,
      orElse: () => AppAccentTone.blue,
    );
  }
}

enum AppBackgroundTone { night, slate, ocean, moss, ember, pearl, linen, ivory }

extension AppBackgroundToneX on AppBackgroundTone {
  String get storageValue => switch (this) {
    AppBackgroundTone.night => 'night',
    AppBackgroundTone.slate => 'slate',
    AppBackgroundTone.ocean => 'ocean',
    AppBackgroundTone.moss => 'moss',
    AppBackgroundTone.ember => 'ember',
    AppBackgroundTone.pearl => 'pearl',
    AppBackgroundTone.linen => 'linen',
    AppBackgroundTone.ivory => 'ivory',
  };

  String get title => switch (this) {
    AppBackgroundTone.night => 'Night',
    AppBackgroundTone.slate => 'Slate',
    AppBackgroundTone.ocean => 'Ocean',
    AppBackgroundTone.moss => 'Moss',
    AppBackgroundTone.ember => 'Ember',
    AppBackgroundTone.pearl => 'Pearl',
    AppBackgroundTone.linen => 'Linen',
    AppBackgroundTone.ivory => 'Ivory',
  };

  bool get isLight => switch (this) {
    AppBackgroundTone.pearl ||
    AppBackgroundTone.linen ||
    AppBackgroundTone.ivory => true,
    _ => false,
  };

  Color get tint => switch (this) {
    AppBackgroundTone.night => const Color(0xFF0C1320),
    AppBackgroundTone.slate => const Color(0xFF202A38),
    AppBackgroundTone.ocean => const Color(0xFF0A3342),
    AppBackgroundTone.moss => const Color(0xFF1B3A2A),
    AppBackgroundTone.ember => const Color(0xFF3B241E),
    AppBackgroundTone.pearl => const Color(0xFFE8EDF4),
    AppBackgroundTone.linen => const Color(0xFFF3EBDD),
    AppBackgroundTone.ivory => const Color(0xFFF8F3E8),
  };

  static AppBackgroundTone fromStorageValue(String? value) {
    return AppBackgroundTone.values.firstWhere(
      (tone) => tone.storageValue == value,
      orElse: () => AppBackgroundTone.night,
    );
  }
}

enum AppDynamicThemeMode { off, detailsAndPeople }

extension AppDynamicThemeModeX on AppDynamicThemeMode {
  String get storageValue => switch (this) {
    AppDynamicThemeMode.off => 'off',
    AppDynamicThemeMode.detailsAndPeople => 'details_and_people',
  };

  String get title => switch (this) {
    AppDynamicThemeMode.off => 'Off',
    AppDynamicThemeMode.detailsAndPeople => 'Details and people',
  };

  static AppDynamicThemeMode fromStorageValue(String? value) {
    return AppDynamicThemeMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => AppDynamicThemeMode.off,
    );
  }
}

enum AppDynamicThemeIntensity { subtle, medium, vivid }

extension AppDynamicThemeIntensityX on AppDynamicThemeIntensity {
  String get storageValue => switch (this) {
    AppDynamicThemeIntensity.subtle => 'subtle',
    AppDynamicThemeIntensity.medium => 'medium',
    AppDynamicThemeIntensity.vivid => 'vivid',
  };

  String get title => switch (this) {
    AppDynamicThemeIntensity.subtle => 'Subtle',
    AppDynamicThemeIntensity.medium => 'Medium',
    AppDynamicThemeIntensity.vivid => 'Vivid',
  };

  String get settingsTitle => switch (this) {
    AppDynamicThemeIntensity.subtle => 'Subtle',
    AppDynamicThemeIntensity.medium => 'Medium',
    AppDynamicThemeIntensity.vivid => 'Advanced',
  };

  bool get usesAmbientOnly => this == AppDynamicThemeIntensity.subtle;

  bool allowsGlobalRuntimeThemeSync({
    required bool inPlayerPaneHost,
    required bool isPane,
  }) {
    return this == AppDynamicThemeIntensity.vivid;
  }

  String get behaviorDescription => switch (this) {
    AppDynamicThemeIntensity.subtle => 'Light current-page color extraction',
    AppDynamicThemeIntensity.medium => 'Full current-page color extraction',
    AppDynamicThemeIntensity.vivid => 'Advanced color extraction',
  };

  static AppDynamicThemeIntensity fromStorageValue(String? value) {
    return AppDynamicThemeIntensity.values.firstWhere(
      (intensity) => intensity.storageValue == value,
      orElse: () => AppDynamicThemeIntensity.medium,
    );
  }
}

enum AppThemeSourceType { preset, currentCustom, savedCustomTheme }

extension AppThemeSourceTypeX on AppThemeSourceType {
  String get storageValue => switch (this) {
    AppThemeSourceType.preset => 'preset',
    AppThemeSourceType.currentCustom => 'current_custom',
    AppThemeSourceType.savedCustomTheme => 'saved_custom_theme',
  };

  static AppThemeSourceType fromStorageValue(String? value) {
    return AppThemeSourceType.values.firstWhere(
      (source) => source.storageValue == value,
      orElse: () => AppThemeSourceType.preset,
    );
  }
}

@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color backgroundBase;
  final Color backgroundElevated;
  final Color surface;
  final Color surfaceSubtle;
  final Color surfaceStrong;
  final Color navBarBackground;
  final Color borderSubtle;
  final Color borderStrong;
  final Color accent;
  final Color accentSoft;
  final Color accentStrong;
  final Color selection;
  final Color selectionSoft;
  final Color selectionStrong;
  final Color link;
  final Color chipBackground;
  final Color chipBorder;
  final Color chipText;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;
  final Color overlayScrim;

  const AppThemeColors({
    required this.backgroundBase,
    required this.backgroundElevated,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfaceStrong,
    required this.navBarBackground,
    required this.borderSubtle,
    required this.borderStrong,
    required this.accent,
    required this.accentSoft,
    required this.accentStrong,
    required this.selection,
    required this.selectionSoft,
    required this.selectionStrong,
    required this.link,
    required this.chipBackground,
    required this.chipBorder,
    required this.chipText,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.overlayScrim,
  });

  @override
  AppThemeColors copyWith({
    Color? backgroundBase,
    Color? backgroundElevated,
    Color? surface,
    Color? surfaceSubtle,
    Color? surfaceStrong,
    Color? navBarBackground,
    Color? borderSubtle,
    Color? borderStrong,
    Color? accent,
    Color? accentSoft,
    Color? accentStrong,
    Color? selection,
    Color? selectionSoft,
    Color? selectionStrong,
    Color? link,
    Color? chipBackground,
    Color? chipBorder,
    Color? chipText,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? warning,
    Color? danger,
    Color? overlayScrim,
  }) {
    return AppThemeColors(
      backgroundBase: backgroundBase ?? this.backgroundBase,
      backgroundElevated: backgroundElevated ?? this.backgroundElevated,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      surfaceStrong: surfaceStrong ?? this.surfaceStrong,
      navBarBackground: navBarBackground ?? this.navBarBackground,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentStrong: accentStrong ?? this.accentStrong,
      selection: selection ?? this.selection,
      selectionSoft: selectionSoft ?? this.selectionSoft,
      selectionStrong: selectionStrong ?? this.selectionStrong,
      link: link ?? this.link,
      chipBackground: chipBackground ?? this.chipBackground,
      chipBorder: chipBorder ?? this.chipBorder,
      chipText: chipText ?? this.chipText,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      overlayScrim: overlayScrim ?? this.overlayScrim,
    );
  }

  /// Stable value-based signature for cache keys — avoids the per-frame
  /// churn that [identityHashCode] causes when new wrapper objects are
  /// created each build.
  int get cacheSignature => Object.hash(
    backgroundBase.toARGB32(),
    backgroundElevated.toARGB32(),
    surface.toARGB32(),
    surfaceStrong.toARGB32(),
    accent.toARGB32(),
    accentStrong.toARGB32(),
    selection.toARGB32(),
    textPrimary.toARGB32(),
    overlayScrim.toARGB32(),
  );

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      backgroundBase: Color.lerp(backgroundBase, other.backgroundBase, t)!,
      backgroundElevated: Color.lerp(
        backgroundElevated,
        other.backgroundElevated,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      surfaceStrong: Color.lerp(surfaceStrong, other.surfaceStrong, t)!,
      navBarBackground: Color.lerp(
        navBarBackground,
        other.navBarBackground,
        t,
      )!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentStrong: Color.lerp(accentStrong, other.accentStrong, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      selectionSoft: Color.lerp(selectionSoft, other.selectionSoft, t)!,
      selectionStrong: Color.lerp(selectionStrong, other.selectionStrong, t)!,
      link: Color.lerp(link, other.link, t)!,
      chipBackground: Color.lerp(chipBackground, other.chipBackground, t)!,
      chipBorder: Color.lerp(chipBorder, other.chipBorder, t)!,
      chipText: Color.lerp(chipText, other.chipText, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      overlayScrim: Color.lerp(overlayScrim, other.overlayScrim, t)!,
    );
  }

  Map<String, int> toMap() {
    return <String, int>{
      'backgroundBase': backgroundBase.toARGB32(),
      'backgroundElevated': backgroundElevated.toARGB32(),
      'surface': surface.toARGB32(),
      'surfaceSubtle': surfaceSubtle.toARGB32(),
      'surfaceStrong': surfaceStrong.toARGB32(),
      'navBarBackground': navBarBackground.toARGB32(),
      'borderSubtle': borderSubtle.toARGB32(),
      'borderStrong': borderStrong.toARGB32(),
      'accent': accent.toARGB32(),
      'accentSoft': accentSoft.toARGB32(),
      'accentStrong': accentStrong.toARGB32(),
      'selection': selection.toARGB32(),
      'selectionSoft': selectionSoft.toARGB32(),
      'selectionStrong': selectionStrong.toARGB32(),
      'link': link.toARGB32(),
      'chipBackground': chipBackground.toARGB32(),
      'chipBorder': chipBorder.toARGB32(),
      'chipText': chipText.toARGB32(),
      'textPrimary': textPrimary.toARGB32(),
      'textSecondary': textSecondary.toARGB32(),
      'textMuted': textMuted.toARGB32(),
      'success': success.toARGB32(),
      'warning': warning.toARGB32(),
      'danger': danger.toARGB32(),
      'overlayScrim': overlayScrim.toARGB32(),
    };
  }

  Iterable<int> toSignatureValues() sync* {
    yield backgroundBase.toARGB32();
    yield backgroundElevated.toARGB32();
    yield surface.toARGB32();
    yield surfaceSubtle.toARGB32();
    yield surfaceStrong.toARGB32();
    yield navBarBackground.toARGB32();
    yield borderSubtle.toARGB32();
    yield borderStrong.toARGB32();
    yield accent.toARGB32();
    yield accentSoft.toARGB32();
    yield accentStrong.toARGB32();
    yield selection.toARGB32();
    yield selectionSoft.toARGB32();
    yield selectionStrong.toARGB32();
    yield link.toARGB32();
    yield chipBackground.toARGB32();
    yield chipBorder.toARGB32();
    yield chipText.toARGB32();
    yield textPrimary.toARGB32();
    yield textSecondary.toARGB32();
    yield textMuted.toARGB32();
    yield success.toARGB32();
    yield warning.toARGB32();
    yield danger.toARGB32();
    yield overlayScrim.toARGB32();
  }

  static AppThemeColors fromMap(Map<String, dynamic> map) {
    const fallback = AppThemePalette.fallback;
    return AppThemeColors(
      backgroundBase: _readColor(
        map,
        'backgroundBase',
        fallback.backgroundBase,
      ),
      backgroundElevated: _readColor(
        map,
        'backgroundElevated',
        fallback.backgroundElevated,
      ),
      surface: _readColor(map, 'surface', fallback.surface),
      surfaceSubtle: _readColor(map, 'surfaceSubtle', fallback.surfaceSubtle),
      surfaceStrong: _readColor(map, 'surfaceStrong', fallback.surfaceStrong),
      navBarBackground: _readColor(
        map,
        'navBarBackground',
        fallback.navBarBackground,
      ),
      borderSubtle: _readColor(map, 'borderSubtle', fallback.borderSubtle),
      borderStrong: _readColor(map, 'borderStrong', fallback.borderStrong),
      accent: _readColor(map, 'accent', fallback.accent),
      accentSoft: _readColor(map, 'accentSoft', fallback.accentSoft),
      accentStrong: _readColor(map, 'accentStrong', fallback.accentStrong),
      selection: _readColor(map, 'selection', fallback.selection),
      selectionSoft: _readColor(map, 'selectionSoft', fallback.selectionSoft),
      selectionStrong: _readColor(
        map,
        'selectionStrong',
        fallback.selectionStrong,
      ),
      link: _readColor(map, 'link', fallback.link),
      chipBackground: _readColor(
        map,
        'chipBackground',
        fallback.chipBackground,
      ),
      chipBorder: _readColor(map, 'chipBorder', fallback.chipBorder),
      chipText: _readColor(map, 'chipText', fallback.chipText),
      textPrimary: _readColor(map, 'textPrimary', fallback.textPrimary),
      textSecondary: _readColor(map, 'textSecondary', fallback.textSecondary),
      textMuted: _readColor(map, 'textMuted', fallback.textMuted),
      success: _readColor(map, 'success', fallback.success),
      warning: _readColor(map, 'warning', fallback.warning),
      danger: _readColor(map, 'danger', fallback.danger),
      overlayScrim: _readColor(map, 'overlayScrim', fallback.overlayScrim),
    );
  }

  static Color _readColor(
    Map<String, dynamic> map,
    String key,
    Color fallback,
  ) {
    final value = map[key];
    return value is int ? Color(value) : fallback;
  }
}

@immutable
class SavedCustomTheme {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final AppThemeColors colorsSnapshot;

  const SavedCustomTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.colorsSnapshot,
  });

  SavedCustomTheme copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    AppThemeColors? colorsSnapshot,
  }) {
    return SavedCustomTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      colorsSnapshot: colorsSnapshot ?? this.colorsSnapshot,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'colorsSnapshot': colorsSnapshot.toMap(),
    };
  }

  static SavedCustomTheme? fromMap(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString().trim();
    final name = (map['name'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty) {
      return null;
    }
    final createdAtText = (map['createdAt'] ?? '').toString().trim();
    final rawColors = map['colorsSnapshot'];
    if (rawColors is! Map) {
      return null;
    }
    return SavedCustomTheme(
      id: id,
      name: name,
      description: (map['description'] ?? '').toString().trim(),
      createdAt: DateTime.tryParse(createdAtText)?.toLocal() ?? DateTime.now(),
      colorsSnapshot: AppThemeColors.fromMap(rawColors.cast<String, dynamic>()),
    );
  }
}

class AppThemePalette {
  AppThemePalette._();

  static const AppThemeColors fallback = AppThemeColors(
    backgroundBase: Color(0xFF09111C),
    backgroundElevated: Color(0xFF0D1624),
    surface: Color(0xFF101B2A),
    surfaceSubtle: Color(0xFF132238),
    surfaceStrong: Color(0xFF173253),
    navBarBackground: Color(0xFF0B1422),
    borderSubtle: Color(0x1AFFFFFF),
    borderStrong: Color(0x334A6A94),
    accent: Color(0xFF3A82F7),
    accentSoft: Color(0x241F7DFF),
    accentStrong: Color(0xFF63A0FF),
    selection: Color(0xFF3A82F7),
    selectionSoft: Color(0x241F7DFF),
    selectionStrong: Color(0xFF63A0FF),
    link: Color(0xFF63A0FF),
    chipBackground: Color(0xFF15243A),
    chipBorder: Color(0x335D7392),
    chipText: Color(0xC9DCEBFF),
    textPrimary: Colors.white,
    textSecondary: Color(0xFFC4D0DE),
    textMuted: Color(0xFF8EA2BA),
    success: Color(0xFF19A35B),
    warning: Color(0xFFB8860B),
    danger: Color(0xFFD64545),
    overlayScrim: Color(0xBF020812),
  );

  static const AppThemeColors _lightFallback = AppThemeColors(
    backgroundBase: Color(0xFFF8F4EC),
    backgroundElevated: Color(0xFFF1EBDD),
    surface: Color(0xFFFFFCF7),
    surfaceSubtle: Color(0xFFF4EEE2),
    surfaceStrong: Color(0xFFE4DAC6),
    navBarBackground: Color(0xFFF1E9DA),
    borderSubtle: Color(0x1A2A3240),
    borderStrong: Color(0x334D5F79),
    accent: Color(0xFF6C8FF1),
    accentSoft: Color(0x2A6C8FF1),
    accentStrong: Color(0xFF395EBE),
    selection: Color(0xFF6C8FF1),
    selectionSoft: Color(0x246C8FF1),
    selectionStrong: Color(0xFF395EBE),
    link: Color(0xFF395EBE),
    chipBackground: Color(0xFFF0E7D5),
    chipBorder: Color(0x334D5F79),
    chipText: Color(0xFF223047),
    textPrimary: Color(0xFF182132),
    textSecondary: Color(0xFF4C5768),
    textMuted: Color(0xFF768091),
    success: Color(0xFF268A54),
    warning: Color(0xFF9A6E12),
    danger: Color(0xFFC13E45),
    overlayScrim: Color(0x6621262D),
  );

  static Color mix(Color a, Color b, double t) {
    return Color.lerp(a, b, t)!.withAlpha(255);
  }

  static Color emphasize(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - 0.18).clamp(0.28, 0.52))
        .toColor();
  }

  static AppThemeColors neutralForBrightness(Brightness brightness) {
    return brightness == Brightness.light ? _lightFallback : fallback;
  }

  static AppThemeColors colorsFor(
    AppThemePreset preset, {
    AppBackgroundTone backgroundTone = AppBackgroundTone.night,
    AppAccentTone accentTone = AppAccentTone.blue,
    AppAccentTone selectionTone = AppAccentTone.blue,
    AppAccentTone linkTone = AppAccentTone.blue,
    Color? customBackgroundColor,
    Color? customAccentColor,
    Color? customSelectionColor,
    Color? customLinkColor,
  }) {
    final presetBase = switch (preset) {
      AppThemePreset.midnight => fallback,
      AppThemePreset.ocean => const AppThemeColors(
        backgroundBase: Color(0xFF07121A),
        backgroundElevated: Color(0xFF0A1721),
        surface: Color(0xFF0E1D29),
        surfaceSubtle: Color(0xFF13283A),
        surfaceStrong: Color(0xFF173B58),
        navBarBackground: Color(0xFF091722),
        borderSubtle: Color(0x225F82A8),
        borderStrong: Color(0x3378A1CC),
        accent: Color(0xFF2E9BFF),
        accentSoft: Color(0x1F2E9BFF),
        accentStrong: Color(0xFF7CC6FF),
        selection: Color(0xFF2E9BFF),
        selectionSoft: Color(0x1F2E9BFF),
        selectionStrong: Color(0xFF7CC6FF),
        link: Color(0xFF7CC6FF),
        chipBackground: Color(0xFF122434),
        chipBorder: Color(0x336386B2),
        chipText: Color(0xFFD6E9FA),
        textPrimary: Color(0xFFF4FAFF),
        textSecondary: Color(0xFFBDD2E6),
        textMuted: Color(0xFF88A3BC),
        success: Color(0xFF24AF6E),
        warning: Color(0xFFD3A031),
        danger: Color(0xFFE05D67),
        overlayScrim: Color(0xBF031019),
      ),
      AppThemePreset.forest => const AppThemeColors(
        backgroundBase: Color(0xFF08130E),
        backgroundElevated: Color(0xFF0B1913),
        surface: Color(0xFF102019),
        surfaceSubtle: Color(0xFF173026),
        surfaceStrong: Color(0xFF1C4437),
        navBarBackground: Color(0xFF0B1812),
        borderSubtle: Color(0x223E6F5A),
        borderStrong: Color(0x3364A184),
        accent: Color(0xFF3EBC7A),
        accentSoft: Color(0x1F3EBC7A),
        accentStrong: Color(0xFF8AE0B2),
        selection: Color(0xFF3EBC7A),
        selectionSoft: Color(0x1F3EBC7A),
        selectionStrong: Color(0xFF8AE0B2),
        link: Color(0xFF8AE0B2),
        chipBackground: Color(0xFF173126),
        chipBorder: Color(0x335A8C76),
        chipText: Color(0xFFD7EBDD),
        textPrimary: Color(0xFFF5FCF7),
        textSecondary: Color(0xFFC6DCCF),
        textMuted: Color(0xFF91AC9D),
        success: Color(0xFF42C978),
        warning: Color(0xFFD4A443),
        danger: Color(0xFFE26A68),
        overlayScrim: Color(0xBF030A07),
      ),
      AppThemePreset.graphite => const AppThemeColors(
        backgroundBase: Color(0xFF111419),
        backgroundElevated: Color(0xFF171C22),
        surface: Color(0xFF1B212A),
        surfaceSubtle: Color(0xFF212A35),
        surfaceStrong: Color(0xFF2D3948),
        navBarBackground: Color(0xFF151A21),
        borderSubtle: Color(0x1FFFFFFF),
        borderStrong: Color(0x334B5A70),
        accent: Color(0xFF83A3FF),
        accentSoft: Color(0x2483A3FF),
        accentStrong: Color(0xFFB5C8FF),
        selection: Color(0xFF83A3FF),
        selectionSoft: Color(0x2483A3FF),
        selectionStrong: Color(0xFFB5C8FF),
        link: Color(0xFFB5C8FF),
        chipBackground: Color(0xFF252E39),
        chipBorder: Color(0x334A5D77),
        chipText: Color(0xFFD9E1EE),
        textPrimary: Color(0xFFF7F9FC),
        textSecondary: Color(0xFFC2CBD7),
        textMuted: Color(0xFF8F98A7),
        success: Color(0xFF45C784),
        warning: Color(0xFFD0A245),
        danger: Color(0xFFE36C72),
        overlayScrim: Color(0xBF080A0D),
      ),
      AppThemePreset.sunset => const AppThemeColors(
        backgroundBase: Color(0xFF18100D),
        backgroundElevated: Color(0xFF211613),
        surface: Color(0xFF291C18),
        surfaceSubtle: Color(0xFF36221D),
        surfaceStrong: Color(0xFF4A2D24),
        navBarBackground: Color(0xFF1E1512),
        borderSubtle: Color(0x22C99570),
        borderStrong: Color(0x33D79E79),
        accent: Color(0xFFE6815B),
        accentSoft: Color(0x24E6815B),
        accentStrong: Color(0xFFFFB094),
        selection: Color(0xFFE6815B),
        selectionSoft: Color(0x24E6815B),
        selectionStrong: Color(0xFFFFB094),
        link: Color(0xFFFFB094),
        chipBackground: Color(0xFF31221D),
        chipBorder: Color(0x337E6458),
        chipText: Color(0xFFF2DDD2),
        textPrimary: Color(0xFFFFF7F4),
        textSecondary: Color(0xFFE2C7BC),
        textMuted: Color(0xFFB08D84),
        success: Color(0xFF4BC983),
        warning: Color(0xFFE2AA4A),
        danger: Color(0xFFE56A63),
        overlayScrim: Color(0xBF0E0503),
      ),
      AppThemePreset.aurora => const AppThemeColors(
        backgroundBase: Color(0xFF071619),
        backgroundElevated: Color(0xFF0B1E22),
        surface: Color(0xFF0F252A),
        surfaceSubtle: Color(0xFF153239),
        surfaceStrong: Color(0xFF1B4450),
        navBarBackground: Color(0xFF0A1A1E),
        borderSubtle: Color(0x225B9AA0),
        borderStrong: Color(0x3385BEC4),
        accent: Color(0xFF35C7B0),
        accentSoft: Color(0x2435C7B0),
        accentStrong: Color(0xFF8DECDD),
        selection: Color(0xFF2FA3F1),
        selectionSoft: Color(0x242FA3F1),
        selectionStrong: Color(0xFF88D0FF),
        link: Color(0xFF8DECDD),
        chipBackground: Color(0xFF143036),
        chipBorder: Color(0x3367969D),
        chipText: Color(0xFFD5EBED),
        textPrimary: Color(0xFFF3FDFD),
        textSecondary: Color(0xFFC2DADC),
        textMuted: Color(0xFF90AEB1),
        success: Color(0xFF3CCB8E),
        warning: Color(0xFFD4AA46),
        danger: Color(0xFFE26F75),
        overlayScrim: Color(0xBF041012),
      ),
      AppThemePreset.latte => _lightFallback,
    };

    final backgroundSeed = customBackgroundColor ?? backgroundTone.tint;
    final isLight = customBackgroundColor != null
        ? customBackgroundColor.computeLuminance() >= 0.58
        : (backgroundTone.isLight || preset.isLight);

    var colors = _applyBackgroundSeed(
      presetBase,
      seed: backgroundSeed,
      light: isLight,
      useSeedAsPrimarySource:
          customBackgroundColor != null || backgroundTone.isLight,
    );

    final accentBase = customAccentColor ?? accentTone.colorFor(light: isLight);
    final selectionBase =
        customSelectionColor ?? selectionTone.colorFor(light: isLight);
    final linkBase = customLinkColor ?? linkTone.strongColorFor(light: isLight);

    colors = colors.copyWith(
      accent: accentBase,
      accentSoft: accentBase.withValues(alpha: isLight ? 0.20 : 0.22),
      accentStrong: customAccentColor != null
          ? emphasize(accentBase)
          : accentTone.strongColorFor(light: isLight),
      selection: selectionBase,
      selectionSoft: selectionBase.withValues(alpha: isLight ? 0.18 : 0.22),
      selectionStrong: customSelectionColor != null
          ? emphasize(selectionBase)
          : selectionTone.strongColorFor(light: isLight),
      link: linkBase,
      chipBorder: mix(
        colors.chipBorder,
        selectionBase.withValues(alpha: isLight ? 0.28 : 0.20),
        0.42,
      ),
      borderStrong: mix(
        colors.borderStrong,
        selectionBase.withValues(alpha: isLight ? 0.22 : 0.16),
        0.36,
      ),
      success: isLight ? const Color(0xFF2D8E5C) : const Color(0xFF19A35B),
      warning: isLight ? const Color(0xFFA77718) : const Color(0xFFB8860B),
      danger: isLight ? const Color(0xFFC04444) : const Color(0xFFD64545),
    );

    return colors;
  }

  static AppThemeColors _applyBackgroundSeed(
    AppThemeColors base, {
    required Color seed,
    required bool light,
    required bool useSeedAsPrimarySource,
  }) {
    if (light) {
      final seedHsl = HSLColor.fromColor(seed);
      final neutralSaturation = (seedHsl.saturation * 0.28).clamp(0.02, 0.16);
      final neutral = seedHsl.withSaturation(neutralSaturation);
      final backgroundBase = neutral.withLightness(0.965).toColor();
      final backgroundElevated = neutral.withLightness(0.94).toColor();
      final surface = neutral.withLightness(0.985).toColor();
      final surfaceSubtle = neutral.withLightness(0.955).toColor();
      final surfaceStrong = neutral.withLightness(0.885).toColor();
      final navBarBackground = neutral.withLightness(0.925).toColor();
      final borderColor = mix(
        neutral.withLightness(0.68).toColor(),
        seed,
        useSeedAsPrimarySource ? 0.32 : 0.16,
      );
      return base.copyWith(
        backgroundBase: backgroundBase,
        backgroundElevated: backgroundElevated,
        surface: surface,
        surfaceSubtle: surfaceSubtle,
        surfaceStrong: surfaceStrong,
        navBarBackground: navBarBackground,
        borderSubtle: borderColor.withValues(alpha: 0.12),
        borderStrong: borderColor.withValues(alpha: 0.24),
        chipBackground: mix(surfaceSubtle, seed, 0.06),
        chipBorder: borderColor.withValues(alpha: 0.20),
        chipText: const Color(0xFF253247),
        textPrimary: const Color(0xFF182132),
        textSecondary: const Color(0xFF4C5768),
        textMuted: const Color(0xFF788395),
        overlayScrim: const Color(0x6621262D),
      );
    }

    final alpha = useSeedAsPrimarySource ? 0.24 : 0.16;
    return base.copyWith(
      backgroundBase: Color.alphaBlend(
        seed.withValues(alpha: alpha),
        base.backgroundBase,
      ),
      backgroundElevated: Color.alphaBlend(
        seed.withValues(alpha: alpha + 0.02),
        base.backgroundElevated,
      ),
      surface: Color.alphaBlend(
        seed.withValues(alpha: alpha - 0.02),
        base.surface,
      ),
      surfaceSubtle: Color.alphaBlend(
        seed.withValues(alpha: alpha + 0.02),
        base.surfaceSubtle,
      ),
      surfaceStrong: Color.alphaBlend(
        seed.withValues(alpha: alpha + 0.06),
        base.surfaceStrong,
      ),
      navBarBackground: Color.alphaBlend(
        seed.withValues(alpha: alpha + 0.04),
        base.navBarBackground,
      ),
      chipBackground: Color.alphaBlend(
        seed.withValues(alpha: alpha - 0.04),
        base.chipBackground,
      ),
    );
  }
}

class AppThemeBuilder {
  AppThemeBuilder._();

  static ThemeData build(
    AppThemePreset preset, {
    AppBackgroundTone backgroundTone = AppBackgroundTone.night,
    AppAccentTone accentTone = AppAccentTone.blue,
    AppAccentTone selectionTone = AppAccentTone.blue,
    AppAccentTone linkTone = AppAccentTone.blue,
    Color? customBackgroundColor,
    Color? customAccentColor,
    Color? customSelectionColor,
    Color? customLinkColor,
  }) {
    final colors = AppThemePalette.colorsFor(
      preset,
      backgroundTone: backgroundTone,
      accentTone: accentTone,
      selectionTone: selectionTone,
      linkTone: linkTone,
      customBackgroundColor: customBackgroundColor,
      customAccentColor: customAccentColor,
      customSelectionColor: customSelectionColor,
      customLinkColor: customLinkColor,
    );
    return buildFromColors(colors);
  }

  static ThemeData buildFromColors(
    AppThemeColors colors, {
    ThemeData? baseTheme,
  }) {
    final brightness = brightnessOf(colors);
    final primaryForeground = _foregroundOn(colors.accent);
    final secondaryForeground = _foregroundOn(colors.selection);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: primaryForeground,
      secondary: colors.selection,
      onSecondary: secondaryForeground,
      error: colors.danger,
      onError: _foregroundOn(colors.danger),
      surface: colors.surface,
      onSurface: colors.textPrimary,
    );

    final seedBase = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.backgroundBase,
      canvasColor: colors.backgroundBase,
      cardColor: colors.surface,
      dividerColor: colors.borderSubtle,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      extensions: <ThemeExtension<dynamic>>[colors],
    );
    // 先用一份完整的 M3 主题兜底，再叠加调用方传入的 baseTheme。
    // 这样外层如果已经有字体、平台适配或导航主题定制，可以保留原有骨架，
    // 但颜色体系仍然由当前动态主题统一接管。
    final base = (baseTheme ?? seedBase).copyWith(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.backgroundBase,
      canvasColor: colors.backgroundBase,
      cardColor: colors.surface,
      dividerColor: colors.borderSubtle,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      extensions: <ThemeExtension<dynamic>>[colors],
    );
    final modalBackground = Color.alphaBlend(
      colors.accent.withValues(
        alpha: brightness == Brightness.light ? 0.055 : 0.085,
      ),
      colors.surface,
    );
    final systemIconBrightness = brightness == Brightness.light
        ? Brightness.dark
        : Brightness.light;
    final systemOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: systemIconBrightness,
      statusBarBrightness: brightness,
      systemNavigationBarColor: colors.backgroundBase,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: systemIconBrightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        systemOverlayStyle: systemOverlayStyle,
        iconTheme: IconThemeData(color: colors.textPrimary),
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.navBarBackground,
        selectedItemColor: colors.selectionStrong,
        unselectedItemColor: colors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: colors.textPrimary,
        displayColor: colors.textPrimary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: modalBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: modalBackground,
        modalBackgroundColor: modalBackground,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: colors.overlayScrim,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      dividerTheme: DividerThemeData(
        color: colors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: colors.accent,
          foregroundColor: primaryForeground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: primaryForeground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colors.accentStrong;
          return colors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.accent.withValues(alpha: 0.36);
          }
          return colors.surfaceStrong;
        }),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(999),
        thickness: WidgetStateProperty.all(7),
        thumbVisibility: WidgetStateProperty.all(true),
        trackVisibility: WidgetStateProperty.all(true),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return colors.accentStrong.withValues(alpha: 0.92);
          }
          if (states.contains(WidgetState.hovered)) {
            return colors.accent.withValues(alpha: 0.82);
          }
          return colors.borderStrong.withValues(alpha: 0.8);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return colors.surfaceStrong.withValues(alpha: 0.5);
        }),
        trackBorderColor: WidgetStateProperty.resolveWith((states) {
          return colors.borderSubtle.withValues(alpha: 0.25);
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.accent),
    );
  }

  static Brightness brightnessOf(AppThemeColors colors) {
    return colors.backgroundBase.computeLuminance() >= 0.58
        ? Brightness.light
        : Brightness.dark;
  }

  static Color _foregroundOn(Color background) {
    return background.computeLuminance() >= 0.54
        ? const Color(0xFF172030)
        : Colors.white;
  }
}

class AppRuntimeColorController extends ChangeNotifier {
  AppRuntimeColorController._();

  static final AppRuntimeColorController instance =
      AppRuntimeColorController._();

  String _pageKey = '';
  AppThemeColors? _colors;
  String _signature = '';

  String get pageKey => _pageKey;
  AppThemeColors? get colors => _colors;
  bool get hasRuntimeColors => _colors != null;

  void setRuntimeColors({
    required String pageKey,
    required AppThemeColors colors,
  }) {
    final normalizedPageKey = pageKey.trim();
    if (normalizedPageKey.isEmpty) {
      return;
    }
    final signature = _runtimeSignature(normalizedPageKey, colors);
    if (_signature == signature) {
      return;
    }
    _pageKey = normalizedPageKey;
    _colors = colors;
    _signature = signature;
    notifyListeners();
  }

  void clearRuntimeColors({String? pageKey}) {
    final normalizedPageKey = pageKey?.trim() ?? '';
    if (normalizedPageKey.isNotEmpty && normalizedPageKey != _pageKey) {
      return;
    }
    if (_colors == null && _pageKey.isEmpty) {
      return;
    }
    _pageKey = '';
    _colors = null;
    _signature = '';
    notifyListeners();
  }

  static String _runtimeSignature(String pageKey, AppThemeColors colors) {
    return <Object>[pageKey, ...colors.toSignatureValues()].join('|');
  }
}

class AppRuntimeColorScope extends InheritedWidget {
  final AppThemeColors? colors;
  final bool hasRuntimeColors;

  const AppRuntimeColorScope({
    super.key,
    required this.colors,
    required this.hasRuntimeColors,
    required super.child,
  });

  static AppThemeColors? maybeColorsOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppRuntimeColorScope>()
        ?.colors;
  }

  static bool hasRuntimeColorsOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AppRuntimeColorScope>()
            ?.hasRuntimeColors ??
        false;
  }

  @override
  bool updateShouldNotify(AppRuntimeColorScope oldWidget) {
    return colors != oldWidget.colors ||
        hasRuntimeColors != oldWidget.hasRuntimeColors;
  }
}

/// Wraps [AppRuntimeColorScope] and only rebuilds it when the controller's
/// effective [AppThemeColors] actually changes — not on every
/// [ChangeNotifier.notifyListeners] call.
class AppRuntimeColorScopeBuilder extends StatefulWidget {
  final AppRuntimeColorController controller;
  final Widget child;

  const AppRuntimeColorScopeBuilder({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<AppRuntimeColorScopeBuilder> createState() =>
      _AppRuntimeColorScopeBuilderState();
}

class _AppRuntimeColorScopeBuilderState
    extends State<AppRuntimeColorScopeBuilder> {
  AppThemeColors? _lastColors;
  bool _lastHasRuntime = false;

  @override
  void initState() {
    super.initState();
    _lastColors = widget.controller.colors;
    _lastHasRuntime = widget.controller.hasRuntimeColors;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AppRuntimeColorScopeBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _lastColors = widget.controller.colors;
      _lastHasRuntime = widget.controller.hasRuntimeColors;
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final newColors = widget.controller.colors;
    final newHasRuntime = widget.controller.hasRuntimeColors;
    if (identical(newColors, _lastColors) &&
        newHasRuntime == _lastHasRuntime &&
        newColors == _lastColors) {
      return;
    }
    _lastColors = newColors;
    _lastHasRuntime = newHasRuntime;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AppRuntimeColorScope(
      colors: _lastColors,
      hasRuntimeColors: _lastHasRuntime,
      child: widget.child,
    );
  }
}

class DynamicPageThemeSnapshot extends InheritedWidget {
  final bool hasDynamicTheme;
  final AppThemeColors effectiveColors;

  const DynamicPageThemeSnapshot({
    super.key,
    required this.hasDynamicTheme,
    required this.effectiveColors,
    required super.child,
  });

  static DynamicPageThemeSnapshot? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DynamicPageThemeSnapshot>();
  }

  @override
  bool updateShouldNotify(DynamicPageThemeSnapshot oldWidget) {
    return hasDynamicTheme != oldWidget.hasDynamicTheme ||
        effectiveColors != oldWidget.effectiveColors;
  }
}

extension AppThemeBuildContextX on BuildContext {
  AppThemeColors get baseAppColors =>
      Theme.of(this).extension<AppThemeColors>() ?? AppThemePalette.fallback;

  AppThemeColors get appColors {
    final pageSnapshot = DynamicPageThemeSnapshot.maybeOf(this);
    if (pageSnapshot?.hasDynamicTheme == true) {
      return pageSnapshot!.effectiveColors;
    }
    return AppRuntimeColorScope.maybeColorsOf(this) ?? baseAppColors;
  }

  /// 未使用 [AppModalSurface] 的旧弹层也统一获得当前页面动态取色后的低饱和底色。
  Color get appModalBackgroundColor {
    final colors = appColors;
    final isLight = colors.backgroundBase.computeLuminance() >= 0.58;
    return Color.alphaBlend(
      colors.accent.withValues(alpha: isLight ? 0.055 : 0.085),
      colors.surface,
    );
  }

  bool get hasRuntimeAppColors => AppRuntimeColorScope.hasRuntimeColorsOf(this);
}
