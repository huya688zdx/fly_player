import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/pages/feiniu_tv_detail_display_policy.dart';

void main() {
  group('FeiniuTvDetailDisplayPolicy', () {
    test('初始阶段缺少 backdrop 或季列表仍加载时保留标题和简介', () {
      final state = FeiniuTvDetailDisplayPolicy.resolve(
        detailIsFull: false,
        detailBackdrop: '',
        initialBackdrop: '',
        detailStill: '',
        detailPoster: '',
        detailOverview: '这是一段系列简介。',
        seasonListResolved: false,
      );

      expect(state.showTitleFallback, isTrue);
      expect(state.showOverview, isTrue);
      expect(state.heroPath, isEmpty);
    });

    test('刷新数据无 backdrop 时不把空背景误认为已就绪', () {
      final state = FeiniuTvDetailDisplayPolicy.resolve(
        detailIsFull: true,
        detailBackdrop: '',
        initialBackdrop: '',
        detailStill: '',
        detailPoster: '',
        detailOverview: '刷新后的系列简介。',
        seasonListResolved: false,
      );

      expect(state.showTitleFallback, isTrue);
      expect(state.showOverview, isTrue);
      expect(state.heroPath, isEmpty);
    });

    test('飞牛详情返回 backdrop 后使用它淡入，且不依赖季列表状态', () {
      final loading = FeiniuTvDetailDisplayPolicy.resolve(
        detailIsFull: true,
        detailBackdrop: '/series-backdrop.jpg',
        initialBackdrop: '',
        detailStill: '/episode-still.jpg',
        detailPoster: '/series-poster.jpg',
        detailOverview: '完整系列简介。',
        seasonListResolved: false,
      );
      final resolved = FeiniuTvDetailDisplayPolicy.resolve(
        detailIsFull: true,
        detailBackdrop: '/series-backdrop.jpg',
        initialBackdrop: '',
        detailStill: '/episode-still.jpg',
        detailPoster: '/series-poster.jpg',
        detailOverview: '完整系列简介。',
        seasonListResolved: true,
      );

      expect(loading.heroPath, '/series-backdrop.jpg');
      expect(resolved.heroPath, loading.heroPath);
      expect(resolved.showTitleFallback, isTrue);
      expect(resolved.showOverview, isTrue);
    });

    test('完整详情无 backdrop 时按安全顺序回退 still 再海报', () {
      final state = FeiniuTvDetailDisplayPolicy.resolve(
        detailIsFull: true,
        detailBackdrop: '',
        initialBackdrop: '',
        detailStill: '/still.jpg',
        detailPoster: '/poster.jpg',
        detailOverview: '',
        seasonListResolved: false,
      );

      expect(state.heroPath, '/still.jpg');
      expect(state.showOverview, isFalse);
    });
  });
}
