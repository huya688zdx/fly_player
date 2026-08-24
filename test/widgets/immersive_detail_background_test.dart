import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/detail/detail_hero_overlay.dart';
import 'package:fly_player/widgets/detail/immersive_detail_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('详情正文背景持续绘制可感知的海报取色晕染', (tester) async {
    final baseColors = AppThemeBuilder.build(
      AppThemePreset.midnight,
    ).extension<AppThemeColors>()!;
    const ambientTint = Color(0xFF65A85D);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        home: AppRuntimeColorScope(
          colors: baseColors,
          hasRuntimeColors: true,
          child: const Scaffold(
            body: ImmersiveDetailBackground(
              images: MediaImageRequest.empty,
              scrollOffset: 0,
              posterHeight: 420,
              ambientTintOverride: ambientTint,
            ),
          ),
        ),
      ),
    );

    final wash = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('detail-background-ambient-wash')),
    );
    final decoration = wash.decoration as BoxDecoration;
    final gradient = decoration.gradient;

    expect(gradient, isNotNull);
    expect(gradient!.colors.first, isNot(baseColors.backgroundBase));
    expect(gradient.colors.first.a, greaterThan(0.10));
    expect(gradient.colors.last.a, greaterThan(0.02));
    expect(gradient.colors.last.a, lessThan(gradient.colors.first.a));
  });

  testWidgets('海报与正文交接层完全属于海报且不侵入正文', (tester) async {
    final baseColors = AppThemeBuilder.build(
      AppThemePreset.midnight,
    ).extension<AppThemeColors>()!;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        home: AppRuntimeColorScope(
          colors: baseColors,
          hasRuntimeColors: true,
          child: const Scaffold(
            body: ImmersiveDetailBackground(
              images: MediaImageRequest.empty,
              scrollOffset: 0,
              posterHeight: 400,
              ambientTintOverride: Color(0xFF65A85D),
            ),
          ),
        ),
      ),
    );

    final bridge = tester.widget<Positioned>(
      find.byKey(const ValueKey<String>('detail-hero-transition')),
    );
    final top = bridge.top!;
    final height = bridge.height!;
    expect(top, lessThan(400));
    expect(top + height, closeTo(400, 0.01));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('detail-hero-image-region')),
        matching: find.byKey(const ValueKey<String>('detail-hero-transition')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('detail-hero-transition-veil')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('detail-hero-transition')),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(
                    const ValueKey<String>('detail-hero-transition-gradient'),
                  ),
                )
                .decoration
            as BoxDecoration;
    final gradient = decoration.gradient!;
    expect(gradient.colors.last.a, 1);
  });

  testWidgets('标题覆盖层只承载标题而不再绘制第二套分界渐变', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        home: const Scaffold(body: DetailHeroOverlay(height: 400, title: '标题')),
      ),
    );

    expect(find.byType(DecoratedBox), findsNothing);
  });

  testWidgets('短横屏下交接层的不透明节点仍与真实海报底边对齐', (tester) async {
    tester.view.physicalSize = const Size(853, 384);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final baseColors = AppThemeBuilder.build(
      AppThemePreset.midnight,
    ).extension<AppThemeColors>()!;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        home: AppRuntimeColorScope(
          colors: baseColors,
          hasRuntimeColors: true,
          child: const Scaffold(
            body: ImmersiveDetailBackground(
              images: MediaImageRequest.empty,
              scrollOffset: 0,
              posterHeight: 150,
              ambientTintOverride: Color(0xFF65A85D),
            ),
          ),
        ),
      ),
    );

    final bridge = tester.widget<Positioned>(
      find.byKey(const ValueKey<String>('detail-hero-transition')),
    );
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(
                    const ValueKey<String>('detail-hero-transition-gradient'),
                  ),
                )
                .decoration
            as BoxDecoration;
    final gradient = decoration.gradient!;
    final opaqueStop = gradient.stops![4];
    final opaqueY = bridge.top! + bridge.height! * opaqueStop;

    expect(opaqueY, closeTo(150, 0.01));
  });
}
