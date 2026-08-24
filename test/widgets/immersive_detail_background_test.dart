import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/theme/app_theme.dart';
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
}
