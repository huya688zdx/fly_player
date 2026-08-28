import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/ui/media_poster_card.dart';

void main() {
  testWidgets('海报占位和评分徽标跟随亮暗主题且不显示外框', (tester) async {
    for (final preset in <AppThemePreset>[
      AppThemePreset.latte,
      AppThemePreset.midnight,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeBuilder.build(preset),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 230,
                child: MediaPosterCard(
                  images: MediaImageRequest.empty,
                  title: '主题海报',
                  subtitle: '2026',
                  imageHeight: 180,
                  rating: 9.1,
                ),
              ),
            ),
          ),
        ),
      );

      final context = tester.element(find.byType(MediaPosterCard));
      final colors = context.appColors;
      final surface = tester.widget<Container>(
        find.byKey(const ValueKey<String>('media-poster-surface')),
      );
      final surfaceDecoration = surface.decoration as BoxDecoration;
      expect(surfaceDecoration.color, colors.surfaceStrong);
      expect(surface.foregroundDecoration, isNull);
      expect(surfaceDecoration.border, isNull);

      final placeholder = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('media-poster-placeholder'),
              ),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((placeholder.decoration as BoxDecoration).gradient, isNotNull);

      final rating = tester.widget<Container>(
        find.byKey(const ValueKey<String>('media-poster-rating')),
      );
      final ratingDecoration = rating.decoration! as BoxDecoration;
      expect(ratingDecoration.color, isNot(const Color(0xFFC5A425)));
      expect(ratingDecoration.border, isNotNull);
      expect(tester.takeException(), isNull, reason: preset.storageValue);
    }
  });
}
