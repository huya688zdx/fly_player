/// 飞牛系列详情页在异步数据到达期间的展示策略。
///
/// 顶部标题和简介属于详情内容，不应被季列表或 backdrop 请求的状态门控；
/// backdrop 则继续遵循“初始数据只用明确 backdrop，完整详情再安全回退”的规则，
/// 避免把单集 still/海报错误地放大成系列背景。
class FeiniuTvDetailDisplayState {
  final String heroPath;
  final String overview;
  final bool showTitleFallback;
  final bool showOverview;

  const FeiniuTvDetailDisplayState({
    required this.heroPath,
    required this.overview,
    required this.showTitleFallback,
    required this.showOverview,
  });

  /// 背景只由已解析出的真实图片路径决定，不再受季列表或入场动画计时器影响。
  bool get showArtwork => heroPath.isNotEmpty;
}

class FeiniuTvDetailDisplayPolicy {
  const FeiniuTvDetailDisplayPolicy._();

  static FeiniuTvDetailDisplayState resolve({
    required bool detailIsFull,
    required String detailBackdrop,
    required String initialBackdrop,
    required String detailStill,
    required String detailPoster,
    required String detailOverview,
    required bool seasonListResolved,
  }) {
    // 季列表是否完成只影响季卡片，不影响顶部详情内容。
    // 保留参数让调用点显式表达这个边界，避免后续重新把两条链路绑在一起。

    final heroPath = detailIsFull
        ? _firstNonEmpty(detailBackdrop, detailStill, detailPoster)
        : initialBackdrop.trim();
    final overview = detailOverview.trim();
    return FeiniuTvDetailDisplayState(
      heroPath: heroPath,
      overview: overview,
      // 没有图时仍显示系列标题文字，避免 heroTitleChild 用空 SizedBox
      // 把标题 fallback 一并遮掉。
      showTitleFallback: true,
      showOverview: overview.isNotEmpty,
    );
  }

  static String _firstNonEmpty(String first, String second, String third) {
    for (final value in <String>[first, second, third]) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }
}
