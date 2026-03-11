import 'package:flutter/widgets.dart';

class MediaLayoutProfile {
  final double screenWidth;
  final bool isTablet;

  final double pageHorizontalPadding;
  final double sectionGap;
  final double itemGap;

  final double categoryStripHeight;
  final double categoryCardWidth;
  final double categoryMiniPosterWidth;
  final double categoryMiniPosterHeight;

  final double continueCardWidth;
  final double continueImageHeight;
  final double continueRowHeight;

  final double homePosterCardWidth;
  final double homePosterImageHeight;
  final double homePosterRowHeight;
  final double homePosterTitleFontSize;
  final double homePosterSubtitleFontSize;

  final int categoryGridColumns;
  final double categoryGridAspectRatio;
  final double categoryGridTitleFontSize;
  final double categoryGridSubtitleFontSize;
  final double categoryFilterSummaryMaxWidth;

  const MediaLayoutProfile({
    required this.screenWidth,
    required this.isTablet,
    required this.pageHorizontalPadding,
    required this.sectionGap,
    required this.itemGap,
    required this.categoryStripHeight,
    required this.categoryCardWidth,
    required this.categoryMiniPosterWidth,
    required this.categoryMiniPosterHeight,
    required this.continueCardWidth,
    required this.continueImageHeight,
    required this.continueRowHeight,
    required this.homePosterCardWidth,
    required this.homePosterImageHeight,
    required this.homePosterRowHeight,
    required this.homePosterTitleFontSize,
    required this.homePosterSubtitleFontSize,
    required this.categoryGridColumns,
    required this.categoryGridAspectRatio,
    required this.categoryGridTitleFontSize,
    required this.categoryGridSubtitleFontSize,
    required this.categoryFilterSummaryMaxWidth,
  });

  int get homeContinueRequestWidth =>
      (continueCardWidth * 2).round().clamp(320, 900);

  int get homePosterRequestWidth =>
      (homePosterCardWidth * 2.5).round().clamp(260, 860);

  int get categoryGridRequestWidth =>
      (categoryGridCardWidth * 2.5).round().clamp(240, 960);

  double get categoryGridCardWidth {
    final availableWidth =
        screenWidth -
        pageHorizontalPadding * 2 -
        itemGap * (categoryGridColumns - 1);
    return (availableWidth / categoryGridColumns).clamp(110.0, 240.0);
  }

  double get categoryGridImageHeight => categoryGridCardWidth * 1.48;

  double get categoryGridRowHeight =>
      categoryGridImageHeight + (isTablet ? 62 : 60);

  static MediaLayoutProfile of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final shortest = size.shortestSide;
    final tablet = shortest >= 600;

    int columns;
    if (width >= 1400) {
      columns = 7;
    } else if (width >= 1200) {
      columns = 6;
    } else if (width >= 900) {
      columns = 5;
    } else if (width >= 700) {
      columns = 4;
    } else {
      columns = 3;
    }

    final hp = tablet ? 12.0 : 8.0;
    final gap = tablet ? 10.0 : 8.0;
    final continueW = tablet ? (width * 0.19).clamp(180.0, 260.0) : 188.0;
    final continueImgH = continueW * 0.56;

    final posterW = tablet
        ? (width / (columns + 0.8)).clamp(122.0, 176.0)
        : 115.0;
    final posterImgH = posterW * 1.48;

    final categoryW = tablet ? (width * 0.135).clamp(138.0, 198.0) : 138.0;
    final miniPosterW = (categoryW * 0.29).clamp(36.0, 52.0);
    final miniPosterH = miniPosterW * 1.48;

    return MediaLayoutProfile(
      screenWidth: width,
      isTablet: tablet,
      pageHorizontalPadding: hp,
      sectionGap: tablet ? 14 : 12,
      itemGap: gap,
      categoryStripHeight: tablet ? 108 : 98,
      categoryCardWidth: categoryW,
      categoryMiniPosterWidth: miniPosterW,
      categoryMiniPosterHeight: miniPosterH,
      continueCardWidth: continueW,
      continueImageHeight: continueImgH,
      continueRowHeight: continueImgH + (tablet ? 66 : 60),
      homePosterCardWidth: posterW,
      homePosterImageHeight: posterImgH,
      homePosterRowHeight: posterImgH + (tablet ? 62 : 60),
      homePosterTitleFontSize: tablet ? 13 : 12,
      homePosterSubtitleFontSize: tablet ? 12 : 11,
      categoryGridColumns: columns,
      categoryGridAspectRatio: tablet ? 0.635 : 0.60,
      categoryGridTitleFontSize: tablet ? 14 : 13,
      categoryGridSubtitleFontSize: tablet ? 12 : 11,
      categoryFilterSummaryMaxWidth: (width * 0.44).clamp(220.0, 420.0),
    );
  }
}
