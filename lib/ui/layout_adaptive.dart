import 'package:flutter/widgets.dart';

class MediaLayoutProfile {
  final double screenWidth;
  final bool isTablet;

  final double pageHorizontalPadding;
  final double sectionGap;
  final double itemGap;

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

  // 共享首页区块消费 continue/mini 两个稳定逻辑宽度，再乘设备 DPR 生成 cacheWidth；
  // 它们刻意不依赖当前响应式卡宽，旋转和分屏只改变视觉宽度，不改变图片缓存键。
  int get continueDecodeWidth => _continueDecodeWidth;
  int get miniPosterDecodeWidth => _miniPosterDecodeWidth;

  // 传统海报行仍直接消费固定物理解码宽度。
  int get homePosterDecodeWidth => _homePosterDecodeWidth;

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
    final posterW = tablet
        ? (width / (columns + 0.8)).clamp(122.0, 176.0)
        : 115.0;
    final posterImgH = posterW * 1.48;

    return MediaLayoutProfile(
      screenWidth: width,
      isTablet: tablet,
      pageHorizontalPadding: hp,
      sectionGap: tablet ? 14 : 12,
      itemGap: gap,
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
