import 'package:fly_player/screens/home/home_responsive_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomeResponsiveLayout', () {
    test('根据可用宽度计算 2、3、4 列', () {
      expect(
        HomeResponsiveLayout.resolve(availableWidth: 336, itemCount: 8).columns,
        2,
      );
      expect(
        HomeResponsiveLayout.resolve(availableWidth: 570, itemCount: 8).columns,
        3,
      );
      expect(
        HomeResponsiveLayout.resolve(availableWidth: 800, itemCount: 8).columns,
        4,
      );
    });

    test('卡片均分可用宽度且分页数量正确', () {
      final layout = HomeResponsiveLayout.resolve(
        availableWidth: 570,
        itemCount: 8,
        gap: 10,
      );

      expect(layout.pageCount, 3);
      expect(layout.cardWidth * layout.columns + layout.gap * 2, 570);
    });

    test('大字体会减少同页列数', () {
      final layout = HomeResponsiveLayout.resolve(
        availableWidth: 336,
        itemCount: 8,
        textScale: 2,
      );

      expect(layout.columns, 1);
    });

    test('空数据和无可用宽度都返回安全空布局', () {
      final emptyItems = HomeResponsiveLayout.resolve(
        availableWidth: 336,
        itemCount: 0,
        gap: 12,
      );
      final emptyWidth = HomeResponsiveLayout.resolve(
        availableWidth: 0,
        itemCount: 8,
        gap: 12,
      );

      for (final layout in <HomeResponsiveLayout>[emptyItems, emptyWidth]) {
        expect(layout.columns, 0);
        expect(layout.cardWidth, 0);
        expect(layout.pageCount, 0);
        expect(layout.gap, 12);
        expect(layout.pageForFirstItem(3), 0);
      }
    });

    test('根据首个条目索引返回有效页码', () {
      final layout = HomeResponsiveLayout.resolve(
        availableWidth: 800,
        itemCount: 8,
      );

      expect(layout.pageForFirstItem(5), 1);
      expect(layout.pageForFirstItem(-1), 0);
      expect(layout.pageForFirstItem(999), layout.pageCount - 1);
    });
  });
}
