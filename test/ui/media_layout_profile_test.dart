import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/ui/layout_adaptive.dart';
import 'package:fly_player/ui/media_poster_card.dart';

void main() {
  MediaLayoutProfile profile({
    required double screenWidth,
    required bool isTablet,
    required double homePosterCardWidth,
  }) {
    return MediaLayoutProfile(
      screenWidth: screenWidth,
      isTablet: isTablet,
      pageHorizontalPadding: 0,
      sectionGap: 0,
      itemGap: 0,
      homePosterCardWidth: homePosterCardWidth,
      homePosterImageHeight: 0,
      homePosterRowHeight: 0,
      homePosterTitleFontSize: 0,
      homePosterSubtitleFontSize: 0,
      categoryGridColumns: 1,
      categoryGridAspectRatio: 1,
      categoryGridTitleFontSize: 0,
      categoryGridSubtitleFontSize: 0,
      categoryFilterSummaryMaxWidth: 0,
    );
  }

  test('首页海报请求和解码宽度不随分屏 profile 改变', () {
    final fullWidth = profile(
      screenWidth: 1400,
      isTablet: true,
      homePosterCardWidth: 176,
    );
    final splitPane = profile(
      screenWidth: 520,
      isTablet: false,
      homePosterCardWidth: 115,
    );

    expect(
      splitPane.homeContinueRequestWidth,
      fullWidth.homeContinueRequestWidth,
    );
    expect(splitPane.homePosterRequestWidth, fullWidth.homePosterRequestWidth);
    expect(
      splitPane.homeCatalogRequestWidth,
      fullWidth.homeCatalogRequestWidth,
    );
    expect(splitPane.continueDecodeWidth, fullWidth.continueDecodeWidth);
    expect(splitPane.homePosterDecodeWidth, fullWidth.homePosterDecodeWidth);
    expect(splitPane.homeCatalogDecodeWidth, fullWidth.homeCatalogDecodeWidth);
    expect(splitPane.continueDecodeWidth, 520);
    expect(splitPane.homeCatalogDecodeWidth, 440);
    expect(splitPane.homeCatalogRequestWidth, 440);
    expect(splitPane.homeCatalogRequestWidth, isNonNegative);
  });

  testWidgets('首页海报行按真实文字缩放为两行文字留足高度', (tester) async {
    for (final scale in <double>[2, 3]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeBuilder.build(AppThemePreset.midnight),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  final layout = MediaLayoutProfile.of(context);
                  return SizedBox(
                    width: layout.homePosterCardWidth,
                    height: layout.homePosterRowHeightFor(
                      MediaQuery.textScalerOf(context),
                    ),
                    child: MediaPosterCard(
                      images: MediaImageRequest.empty,
                      title: '一个足够长的首页媒体标题',
                      subtitle: '2026 · 第 12 集',
                      imageHeight: layout.homePosterImageHeight,
                      titleFontSize: layout.homePosterTitleFontSize,
                      subtitleFontSize: layout.homePosterSubtitleFontSize,
                      titleFontWeight: FontWeight.w500,
                      subtitleFontWeight: FontWeight.w400,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: '文字缩放 $scale 不应溢出');
    }
  });
}
