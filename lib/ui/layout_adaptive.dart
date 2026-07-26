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

  static const int _homeContinueRequestWidth = 520;
  static const int _homePosterRequestWidth = 440;
  static const int _categoryMiniPosterRequestWidth = 156;
  static const int _continueDecodeWidth = 520;
  static const int _homePosterDecodeWidth = 352;
  static const int _miniPosterDecodeWidth = 104;

  // 首页海报的网络请求宽度固定取卡片上界，避免飞牛 ?w= 随分屏宽度变化。
  int get homeContinueRequestWidth => _homeContinueRequestWidth;
  int get homePosterRequestWidth => _homePosterRequestWidth;
  int get categoryMiniPosterRequestWidth => _categoryMiniPosterRequestWidth;

  // 稳定解码宽度(像素)：仅取「卡片宽度上界(下方 of() 里 clamp 的 ceiling) × 2」，
  // **刻意不依赖当前窗口/分屏宽度**。进/退分屏时卡片会随 pane 缩放，但解码尺寸恒定，
  // 于是 Image 的 ResizeImage(cacheWidth) 缓存 key 不变 → 命中图片缓存、海报不重解码闪烁。
  // (dpr 在同机型上恒定，这里用固定 ×2 作代理；上界变更需同步这几个常量。)
  int get continueDecodeWidth => _continueDecodeWidth;
  int get homePosterDecodeWidth => _homePosterDecodeWidth;
  int get miniPosterDecodeWidth => _miniPosterDecodeWidth;

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
