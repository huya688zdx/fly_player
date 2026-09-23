import 'package:fly_player/theme/visual_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('自动档默认均衡，Android 低内存设备使用流畅档', () {
    expect(
      AppVisualPerformanceMode.automatic.resolve(isLowRamDevice: false),
      AppVisualPerformanceTier.balanced,
    );
    expect(
      AppVisualPerformanceMode.automatic.resolve(isLowRamDevice: true),
      AppVisualPerformanceTier.smooth,
    );
    expect(
      AppVisualPerformanceModeX.fromStorageValue('unknown'),
      AppVisualPerformanceMode.automatic,
    );
  });

  test('三档分配装饰纹理、动效、缩略图和首页预取成本', () {
    expect(AppVisualPerformanceTier.smooth.atmosphereTextureMaxDimension, 768);
    expect(
      AppVisualPerformanceTier.balanced.atmosphereTextureMaxDimension,
      1280,
    );
    expect(AppVisualPerformanceTier.full.atmosphereTextureMaxDimension, 1920);

    expect(AppVisualPerformanceTier.smooth.allowsGlobalRuntimeThemeSync, false);
    expect(
      AppVisualPerformanceTier.balanced.allowsGlobalRuntimeThemeSync,
      false,
    );
    expect(AppVisualPerformanceTier.full.allowsGlobalRuntimeThemeSync, true);

    expect(AppVisualPerformanceTier.smooth.homeThumbnailDecodeWidth(520), 384);
    expect(AppVisualPerformanceTier.smooth.homeThumbnailDecodeWidth(440), 320);
    expect(AppVisualPerformanceTier.smooth.homeThumbnailDecodeWidth(352), 256);
    expect(
      AppVisualPerformanceTier.balanced.homeThumbnailDecodeWidth(520),
      520,
    );
    expect(AppVisualPerformanceTier.full.homeThumbnailDecodeWidth(520), 520);
    expect(AppVisualPerformanceTier.smooth.posterBrowseHomePrewarmLimit(8), 0);
    expect(
      AppVisualPerformanceTier.balanced.posterBrowseHomePrewarmLimit(8),
      2,
    );
    expect(AppVisualPerformanceTier.full.posterBrowseHomePrewarmLimit(8), 8);

    expect(
      AppVisualPerformanceTier.smooth.posterBrowseContinueWarmupLimit(20),
      1,
    );
    expect(
      AppVisualPerformanceTier.balanced.posterBrowseContinueWarmupLimit(20),
      3,
    );
    expect(
      AppVisualPerformanceTier.full.posterBrowseContinueWarmupLimit(20),
      20,
    );
    expect(
      AppVisualPerformanceTier.smooth.posterBrowseNeighborPrefetchRadius(2),
      0,
    );
    expect(
      AppVisualPerformanceTier.balanced.posterBrowseNeighborPrefetchRadius(2),
      1,
    );
    expect(
      AppVisualPerformanceTier.full.posterBrowseNeighborPrefetchRadius(2),
      2,
    );

    expect(AppVisualPerformanceTier.smooth.detailParallaxFactor(.4), 1);
    expect(AppVisualPerformanceTier.balanced.detailParallaxFactor(.4), .72);
    expect(AppVisualPerformanceTier.full.detailParallaxFactor(.4), .4);
    expect(AppVisualPerformanceTier.smooth.allowsPullDownZoom, false);
    expect(AppVisualPerformanceTier.balanced.allowsPullDownZoom, false);
    expect(AppVisualPerformanceTier.full.allowsPullDownZoom, true);

    expect(AppVisualPerformanceTier.smooth.desktopBlurSigma(22), 0);
    expect(AppVisualPerformanceTier.balanced.desktopBlurSigma(22), 8);
    expect(
      AppVisualPerformanceTier.balanced.desktopBlurSigma(22, overVideo: true),
      0,
    );
    expect(AppVisualPerformanceTier.full.desktopBlurSigma(22), 22);
  });
}
