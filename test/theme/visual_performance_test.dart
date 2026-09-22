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

  test('三档只削减装饰纹理、持续动效、全局联动和实时模糊', () {
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
