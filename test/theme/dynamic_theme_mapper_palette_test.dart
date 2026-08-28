import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/theme/dynamic_theme_mapper.dart';
import 'package:fly_player/theme/dynamic_theme_seed_extractor.dart';

double _hueDistance(Color actual, Color expected) {
  final actualHue = HSVColor.fromColor(actual).hue;
  final expectedHue = HSVColor.fromColor(expected).hue;
  final raw = (actualHue - expectedHue).abs();
  return raw > 180 ? 360 - raw : raw;
}

double _rgbDistance(Color a, Color b) {
  final red = a.r - b.r;
  final green = a.g - b.g;
  final blue = a.b - b.b;
  return red * red + green * green + blue * blue;
}

void main() {
  test('动态映射分别保留强调、选择和链接三种取色色相', () {
    const warmRed = Color(0xFFD85867);
    const coldBlue = Color(0xFF4B7FD8);
    const amber = Color(0xFFD49A32);
    const seed = DynamicThemeSeed(
      backgroundSeed: Color(0xFF47643F),
      accentSeed: warmRed,
      selectionSeed: coldBlue,
      linkSeed: amber,
      preferLightSurface: false,
    );

    final base = AppThemePalette.colorsFor(AppThemePreset.midnight);
    final mapped = DynamicThemeMapper.map(
      baseColors: base,
      seed: seed,
      intensity: AppDynamicThemeIntensity.medium,
    );

    expect(_hueDistance(mapped.accent, warmRed), lessThan(24));
    expect(_hueDistance(mapped.selection, coldBlue), lessThan(24));
    expect(_hueDistance(mapped.link, amber), lessThan(24));
    expect(_hueDistance(mapped.accent, mapped.selection), greaterThan(70));
    expect(_hueDistance(mapped.selection, mapped.link), greaterThan(70));
    expect(
      _rgbDistance(mapped.backgroundBase, base.backgroundBase),
      lessThan(_rgbDistance(mapped.backgroundBase, seed.backgroundSeed)),
    );
    expect(mapped.backgroundBase.computeLuminance(), lessThan(.06));
  });

  test('亮暗动态取色都不覆盖承担可读性的徽章前景色', () {
    const seed = DynamicThemeSeed(
      backgroundSeed: Color(0xFF74613A),
      accentSeed: Color(0xFF91C95C),
      selectionSeed: Color(0xFF6E552A),
      linkSeed: Color(0xFFB88724),
      preferLightSurface: false,
    );

    for (final preset in <AppThemePreset>[
      AppThemePreset.midnight,
      AppThemePreset.latte,
    ]) {
      final base = AppThemePalette.colorsFor(preset);
      final mapped = DynamicThemeMapper.map(
        baseColors: base,
        seed: seed,
        intensity: AppDynamicThemeIntensity.medium,
      );

      expect(mapped.chipText, base.chipText, reason: preset.storageValue);
    }
  });
}
