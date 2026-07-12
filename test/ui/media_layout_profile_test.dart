import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/ui/layout_adaptive.dart';

void main() {
  MediaLayoutProfile profile({
    required double screenWidth,
    required bool isTablet,
    required double continueCardWidth,
    required double homePosterCardWidth,
    required double categoryMiniPosterWidth,
  }) {
    return MediaLayoutProfile(
      screenWidth: screenWidth,
      isTablet: isTablet,
      pageHorizontalPadding: 0,
      sectionGap: 0,
      itemGap: 0,
      categoryStripHeight: 0,
      categoryCardWidth: 0,
      categoryMiniPosterWidth: categoryMiniPosterWidth,
      categoryMiniPosterHeight: 0,
      continueCardWidth: continueCardWidth,
      continueImageHeight: 0,
      continueRowHeight: 0,
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
      continueCardWidth: 260,
      homePosterCardWidth: 176,
      categoryMiniPosterWidth: 52,
    );
    final splitPane = profile(
      screenWidth: 520,
      isTablet: false,
      continueCardWidth: 188,
      homePosterCardWidth: 115,
      categoryMiniPosterWidth: 36,
    );

    expect(
      splitPane.homeContinueRequestWidth,
      fullWidth.homeContinueRequestWidth,
    );
    expect(splitPane.homePosterRequestWidth, fullWidth.homePosterRequestWidth);
    expect(
      splitPane.categoryMiniPosterRequestWidth,
      fullWidth.categoryMiniPosterRequestWidth,
    );
    expect(splitPane.continueDecodeWidth, fullWidth.continueDecodeWidth);
    expect(splitPane.homePosterDecodeWidth, fullWidth.homePosterDecodeWidth);
    expect(splitPane.miniPosterDecodeWidth, fullWidth.miniPosterDecodeWidth);
  });
}
