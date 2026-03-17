import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:flutter/services.dart';

@immutable
class DynamicThemeSeed {
  final Color backgroundSeed;
  final Color accentSeed;
  final Color selectionSeed;
  final Color linkSeed;
  final bool preferLightSurface;

  const DynamicThemeSeed({
    required this.backgroundSeed,
    required this.accentSeed,
    required this.selectionSeed,
    required this.linkSeed,
    required this.preferLightSurface,
  });
}

class DynamicThemeSeedExtractor {
  const DynamicThemeSeedExtractor._();

  static const MethodChannel _themeSamplerChannel = MethodChannel(
    'fly_player/theme_sampler',
  );

  static Future<DynamicThemeSeed?> extract({
    required String imageUrl,
    required String token,
  }) async {
    if (imageUrl.trim().isEmpty) return null;

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final nativeSeed = await _extractOnAndroid(
          imageUrl: imageUrl,
          token: token,
        );
        if (nativeSeed != null) return nativeSeed;
      }

      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(
          imageUrl,
          headers: token.trim().isEmpty
              ? const <String, String>{}
              : <String, String>{
                  'Authorization': token,
                  'Trim-MC-token': token,
                },
        ),
        maximumColorCount: 16,
        size: const Size(220, 140),
      );

      final backgroundCandidate = _firstAccepted(<Color?>[
        palette.darkVibrantColor?.color,
        palette.vibrantColor?.color,
        palette.dominantColor?.color,
        palette.mutedColor?.color,
      ]);
      final accentCandidate = _firstAccepted(<Color?>[
        palette.vibrantColor?.color,
        palette.darkVibrantColor?.color,
        palette.lightVibrantColor?.color,
        palette.dominantColor?.color,
        palette.mutedColor?.color,
      ]);

      final baseCandidate = backgroundCandidate ?? accentCandidate;
      final actionCandidate = accentCandidate ?? backgroundCandidate;
      if (baseCandidate == null || actionCandidate == null) {
        return null;
      }
      final preferLightSurface = _preferLightSurface(baseCandidate);

      return DynamicThemeSeed(
        backgroundSeed: _backgroundSeedFor(
          baseCandidate,
          preferLightSurface: preferLightSurface,
        ),
        accentSeed: _accentSeedFor(actionCandidate),
        selectionSeed: _selectionSeedFor(actionCandidate),
        linkSeed: _linkSeedFor(actionCandidate),
        preferLightSurface: preferLightSurface,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<DynamicThemeSeed?> _extractOnAndroid({
    required String imageUrl,
    required String token,
  }) async {
    final raw = await _themeSamplerChannel.invokeMapMethod<String, dynamic>(
      'extractDynamicThemeSeed',
      <String, dynamic>{'imageUrl': imageUrl, 'token': token},
    );
    if (raw == null) return null;
    final backgroundValue = raw['backgroundSeed'];
    final accentValue = raw['accentSeed'];
    final selectionValue = raw['selectionSeed'];
    final linkValue = raw['linkSeed'];
    if (backgroundValue is! int ||
        accentValue is! int ||
        selectionValue is! int ||
        linkValue is! int) {
      return null;
    }
    return DynamicThemeSeed(
      backgroundSeed: Color(backgroundValue & 0xFFFFFFFF),
      accentSeed: Color(accentValue & 0xFFFFFFFF),
      selectionSeed: Color(selectionValue & 0xFFFFFFFF),
      linkSeed: Color(linkValue & 0xFFFFFFFF),
      preferLightSurface: (raw['preferLightSurface'] as bool?) ?? false,
    );
  }

  static Color? _firstAccepted(List<Color?> colors) {
    for (final color in colors) {
      final normalized = _normalizeCandidate(color);
      if (normalized != null) return normalized;
    }
    return null;
  }

  static Color? _normalizeCandidate(Color? color) {
    if (color == null) return null;
    var hsl = HSLColor.fromColor(color);
    if (hsl.saturation < 0.08) return null;
    if (hsl.lightness < 0.06 || hsl.lightness > 0.90) return null;

    final hue = hsl.hue;
    final isHarshWarmHue =
        (hue <= 14 || hue >= 342 || (hue >= 34 && hue <= 72));
    if (isHarshWarmHue && hsl.saturation > 0.66) {
      hsl = hsl.withSaturation(0.66);
    }

    return hsl.toColor();
  }

  static bool _preferLightSurface(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.lightness >= 0.62;
  }

  static Color _backgroundSeedFor(
    Color color, {
    required bool preferLightSurface,
  }) {
    final hsl = HSLColor.fromColor(color);
    if (preferLightSurface) {
      return hsl
          .withSaturation((hsl.saturation * 0.42).clamp(0.08, 0.22))
          .withLightness((hsl.lightness * 0.92).clamp(0.74, 0.90))
          .toColor();
    }
    return hsl
        .withSaturation((hsl.saturation * 0.84).clamp(0.18, 0.54))
        .withLightness(((hsl.lightness * 0.58) + 0.02).clamp(0.18, 0.36))
        .toColor();
  }

  static Color _accentSeedFor(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.22, 0.58))
        .withLightness(hsl.lightness.clamp(0.34, 0.56))
        .toColor();
  }

  static Color _selectionSeedFor(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.24, 0.62))
        .withLightness((hsl.lightness - 0.02).clamp(0.30, 0.52))
        .toColor();
  }

  static Color _linkSeedFor(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.20, 0.54))
        .withLightness((hsl.lightness + 0.08).clamp(0.42, 0.64))
        .toColor();
  }
}
