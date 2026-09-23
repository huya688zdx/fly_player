import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/theme/visual_performance.dart';
import 'package:fly_player/widgets/app_atmospheric_background.dart';
import 'package:fly_player/widgets/detail/detail_hero_overlay.dart';
import 'package:fly_player/widgets/detail/immersive_detail_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('详情正文使用所选样式绘制海报取色晕染', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = AppThemeProvider();
    final baseColors = AppThemeBuilder.build(
      AppThemePreset.midnight,
    ).extension<AppThemeColors>()!;
    const ambientTint = Color(0xFF65A85D);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => provider,
        child: MaterialApp(
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
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => provider.setBackgroundStyle(AppBackgroundStyle.cinemaLight),
    );
    await tester.pumpAndSettle();
    final wash = tester.widget<AppAtmosphereSurface>(
      find.byKey(const ValueKey<String>('detail-background-ambient-wash')),
    );
    expect(wash.style, AppBackgroundStyle.cinemaLight);
    expect(wash.palette.hasDynamicTheme, isTrue);
    expect(wash.palette.base, baseColors.backgroundBase);
    expect(wash.palette.accentGlow.withValues(alpha: 1), ambientTint);
    expect(wash.palette.accentGlow.a, greaterThan(.10));
    expect(find.byType(AppAtmosphereStaticLayer), findsOneWidget);
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

  testWidgets('接续带从承接色起笔并把色差缓释进正文底面', (tester) async {
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
    final seam = tester.widget<Positioned>(
      find.byKey(const ValueKey<String>('detail-hero-seam-fade')),
    );

    // 接续带向上重叠一个物理像素，防止桌面缩放时共边栅格化露缝。
    final overlap = 1 / tester.view.devicePixelRatio;
    expect(seam.top, closeTo(bridge.top! + bridge.height! - overlap, 0.01));
    expect(seam.height, greaterThanOrEqualTo(96));
    expect(seam.height, lessThanOrEqualTo(160 + overlap));

    // 起笔色必须与交接层终点色完全一致（连续性契约），终点全透明。
    final transitionColor =
        (tester
                    .widget<DecoratedBox>(
                      find.byKey(
                        const ValueKey<String>(
                          'detail-hero-transition-gradient',
                        ),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .gradient!
            .colors
            .last;
    final seamDecoration =
        (tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: find.byKey(
                          const ValueKey<String>('detail-hero-seam-fade'),
                        ),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .gradient!;
    expect(seamDecoration.colors.first, transitionColor);
    expect(seamDecoration.colors.last.a, 0);

    // 不拦截正文触摸。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('detail-hero-seam-fade')),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
  });

  testWidgets('竖向详情页的取色渐变在图片区保留足够行程', (tester) async {
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
    final mainDecoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(
                    const ValueKey<String>('detail-hero-transition-gradient'),
                  ),
                )
                .decoration
            as BoxDecoration;
    final veilDecoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(
                    const ValueKey<String>('detail-hero-transition-veil'),
                  ),
                )
                .decoration
            as BoxDecoration;
    final mainGradient = mainDecoration.gradient!;
    final veilGradient = veilDecoration.gradient!;

    expect(bridge.height, greaterThanOrEqualTo(400 * 0.56));
    expect(mainGradient.stops![1], lessThanOrEqualTo(0.30));
    expect(veilGradient.stops![1], lessThanOrEqualTo(0.46));
  });

  testWidgets('海报交接终点使用正文的动态取色承接色', (tester) async {
    final baseColors = AppThemeBuilder.build(
      AppThemePreset.midnight,
    ).extension<AppThemeColors>()!;
    const ambientTint = Color(0xFF69A95C);
    const transitionBody = Color(0xFF10251D);

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
              ambientTintOverride: ambientTint,
              transitionTintColor: Color(0xFF07110D),
              transitionBodyColor: transitionBody,
            ),
          ),
        ),
      ),
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
    final expectedSeamColor = Color.alphaBlend(
      ambientTint.withValues(alpha: 0.17),
      transitionBody,
    );

    expect(gradient.colors.last, expectedSeamColor);
    expect(gradient.stops![3], greaterThanOrEqualTo(0.88));
    expect(gradient.colors[3].a, lessThanOrEqualTo(0.45));
  });

  testWidgets('浅色详情标题与 Logo 回退跟随页面文字色，不叠加阴影或分界渐变', (tester) async {
    final colors = AppThemeBuilder.build(
      AppThemePreset.latte,
    ).extension<AppThemeColors>()!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppThemePreset.midnight),
        home: AppRuntimeColorScope(
          colors: colors,
          hasRuntimeColors: true,
          child: const Scaffold(
            body: Column(
              children: [
                DetailHeroOverlay(height: 300, title: '标题', subtitle: '剧集信息'),
                DetailHeroLogoTitle(
                  images: MediaImageRequest.empty,
                  fallbackTitle: 'Logo 回退',
                  maxHeight: 100,
                  maxWidth: 400,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('标题'));
    final fallback = tester.widget<Text>(find.text('Logo 回退'));
    expect(title.style?.color, colors.textPrimary);
    expect(fallback.style?.color, colors.textPrimary);
    expect(
      tester.widget<Text>(find.text('剧集信息')).style?.color,
      colors.textSecondary,
    );
    expect(title.style?.shadows, isEmpty);
    expect(fallback.style?.shadows, isEmpty);
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

  testWidgets('正常上滑时整块海报裁切层移动且图片仍保持视差', (tester) async {
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
              scrollOffset: 96,
              posterHeight: 400,
              ambientTintOverride: Color(0xFF65A85D),
            ),
          ),
        ),
      ),
    );

    final regionFollowFinder = find.byKey(
      const ValueKey<String>('detail-hero-region-scroll-follow'),
    );
    expect(regionFollowFinder, findsOneWidget);
    final regionTransform = tester.widget<Transform>(regionFollowFinder);
    final regionShiftY = regionTransform.transform.storage[13];
    final imageTransform = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('detail-hero-image-parallax')),
    );
    final imageCompensationY = imageTransform.transform.storage[13];
    final bridge = tester.widget<Positioned>(
      find.byKey(const ValueKey<String>('detail-hero-transition')),
    );

    expect(regionShiftY, closeTo(-96, 0.01));
    expect(bridge.top! + bridge.height! + regionShiftY, closeTo(304, 0.01));
    expect(regionShiftY + imageCompensationY, closeTo(-38.4, 0.01));
    expect(
      find.byKey(
        const ValueKey<String>('detail-hero-transition-scroll-follow'),
      ),
      findsNothing,
    );
  });

  testWidgets('流畅档让详情大图正常随正文滚动并取消额外视差', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = AppThemeProvider();
    await provider.setVisualPerformanceMode(AppVisualPerformanceMode.smooth);
    final baseColors = AppThemeBuilder.build(
      AppThemePreset.midnight,
    ).extension<AppThemeColors>()!;

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => provider,
        child: MaterialApp(
          theme: AppThemeBuilder.build(AppThemePreset.midnight),
          home: AppRuntimeColorScope(
            colors: baseColors,
            hasRuntimeColors: true,
            child: const Scaffold(
              body: ImmersiveDetailBackground(
                images: MediaImageRequest.empty,
                scrollOffset: 96,
                posterHeight: 400,
                ambientTintOverride: Color(0xFF65A85D),
              ),
            ),
          ),
        ),
      ),
    );

    final regionTransform = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('detail-hero-region-scroll-follow')),
    );
    final imageTransform = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('detail-hero-image-parallax')),
    );
    final regionShiftY = regionTransform.transform.storage[13];
    final imageCompensationY = imageTransform.transform.storage[13];

    expect(regionShiftY, closeTo(-96, 0.01));
    expect(imageCompensationY, closeTo(0, 0.01));
    expect(regionShiftY + imageCompensationY, closeTo(-96, 0.01));
  });

  testWidgets('小数滚动偏移时海报裁切边界对齐物理像素', (tester) async {
    tester.view.devicePixelRatio = 3;
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
              scrollOffset: 0.5,
              posterHeight: 400,
              ambientTintOverride: Color(0xFF65A85D),
            ),
          ),
        ),
      ),
    );

    final regionTransform = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('detail-hero-region-scroll-follow')),
    );
    final imageTransform = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('detail-hero-image-parallax')),
    );
    final regionShiftY = regionTransform.transform.storage[13];
    final imageCompensationY = imageTransform.transform.storage[13];
    final physicalShiftY = regionShiftY * 3;

    expect(physicalShiftY, closeTo(physicalShiftY.roundToDouble(), 0.0001));
    expect(regionShiftY + imageCompensationY, closeTo(-0.2, 0.0001));
  });
}
