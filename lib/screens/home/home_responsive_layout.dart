/// 首页横向卡片分页的响应式布局结果。
class HomeResponsiveLayout {
  const HomeResponsiveLayout._({
    required this.columns,
    required this.cardWidth,
    required this.gap,
    required this.pageCount,
  });

  /// 每页展示的卡片列数。
  final int columns;

  /// 单张卡片宽度。
  final double cardWidth;

  /// 相邻卡片之间的间距。
  final double gap;

  /// 全部条目所占的页数。
  final int pageCount;

  /// 根据可用宽度和条目数量计算响应式布局。
  static HomeResponsiveLayout resolve({
    required double availableWidth,
    required int itemCount,
    double idealCardWidth = 190,
    double gap = 10,
    double textScale = 1,
    int maxColumns = 5,
  }) {
    if (availableWidth <= 0 || itemCount <= 0) {
      return HomeResponsiveLayout._(
        columns: 0,
        cardWidth: 0,
        gap: gap,
        pageCount: 0,
      );
    }

    final adjustedIdeal =
        idealCardWidth * textScale.clamp(1.0, 1.25).toDouble();
    final candidate = ((availableWidth + gap) / (adjustedIdeal + gap)).round();
    final safeMaxColumns = maxColumns < 1 ? 1 : maxColumns;
    final widthLimitedColumns = candidate.clamp(1, safeMaxColumns).toInt();
    final columns = widthLimitedColumns > itemCount
        ? itemCount
        : widthLimitedColumns;
    final cardWidth = (availableWidth - gap * (columns - 1)) / columns;
    final pageCount = (itemCount + columns - 1) ~/ columns;

    return HomeResponsiveLayout._(
      columns: columns,
      cardWidth: cardWidth,
      gap: gap,
      pageCount: pageCount,
    );
  }

  /// 返回指定首条目所在的有效页码。
  int pageForFirstItem(int itemIndex) {
    if (columns == 0 || pageCount == 0) {
      return 0;
    }

    return (itemIndex ~/ columns).clamp(0, pageCount - 1).toInt();
  }
}
