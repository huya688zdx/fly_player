import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/theme/detail_tokens.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/ui/media_poster_card.dart';
import 'package:fly_player/widgets/detail/capability_badge.dart';
import 'package:fly_player/widgets/detail/detail_icon_button.dart';

Widget _themedApp(AppThemePreset preset, Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.build(preset),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  test('应用栏系统图标样式跟随亮暗主题', () {
    final light = AppThemeBuilder.build(AppThemePreset.latte);
    final dark = AppThemeBuilder.build(AppThemePreset.midnight);

    expect(
      light.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      dark.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.light,
    );
  });

  testWidgets('能力徽章 SVG 在亮暗主题下都使用语义前景色', (tester) async {
    for (final preset in <AppThemePreset>[
      AppThemePreset.latte,
      AppThemePreset.midnight,
    ]) {
      await tester.pumpWidget(
        _themedApp(preset, const CapabilityBadge(label: '1080')),
      );

      final context = tester.element(find.byType(CapabilityBadge));
      final colors = context.appColors;
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(
        svg.colorFilter,
        ColorFilter.mode(colors.chipText, BlendMode.srcIn),
        reason: preset.storageValue,
      );
    }
  });

  testWidgets('文本能力徽章在亮暗主题下都使用语义前景色', (tester) async {
    for (final preset in <AppThemePreset>[
      AppThemePreset.latte,
      AppThemePreset.midnight,
    ]) {
      await tester.pumpWidget(
        _themedApp(preset, const CapabilityBadge(label: '自定义规格')),
      );

      final context = tester.element(find.byType(CapabilityBadge));
      final colors = context.appColors;
      final text = tester.widget<Text>(find.text('自定义规格'));
      expect(text.style?.color, colors.chipText, reason: preset.storageValue);
    }
  });

  testWidgets('图片上的能力徽章保持独立高对比前景', (tester) async {
    await tester.pumpWidget(
      _themedApp(
        AppThemePreset.latte,
        const CapabilityBadge(label: '1080', onImage: true),
      ),
    );

    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      svg.colorFilter,
      const ColorFilter.mode(Color(0xFFF2F5F8), BlendMode.srcIn),
    );
  });

  testWidgets('海报所有叠加层都受同一圆角裁剪约束', (tester) async {
    await tester.pumpWidget(
      _themedApp(
        AppThemePreset.latte,
        const SizedBox(
          width: 120,
          height: 230,
          child: MediaPosterCard(
            images: MediaImageRequest.empty,
            title: '圆角海报',
            subtitle: '2026',
            imageHeight: 180,
            rating: 9.1,
            resolutions: <String>['1080'],
          ),
        ),
      ),
    );

    final clip = tester.widget<ClipRRect>(
      find.byKey(const ValueKey<String>('media-poster-visual-clip')),
    );
    expect(clip.borderRadius, BorderRadius.circular(10));
    expect(clip.clipBehavior, Clip.antiAlias);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情顶部圆形按钮在亮暗主题下都有渐变层次和柔和投影', (tester) async {
    for (final preset in <AppThemePreset>[
      AppThemePreset.latte,
      AppThemePreset.midnight,
    ]) {
      await tester.pumpWidget(
        _themedApp(
          preset,
          const DetailIconButton(
            iconAsset: 'assets/icons/back.svg',
            style: DetailIconButtonStyle.top,
          ),
        ),
      );

      final surface = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey<String>('detail-top-control-surface')),
      );
      final decoration = surface.decoration as BoxDecoration;
      expect(decoration.gradient, isA<LinearGradient>());
      expect(decoration.border, isNotNull);
      expect(decoration.boxShadow, isNotEmpty);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(DetailTokens.topButtonRadius),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
