import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_theme_provider.dart';
import '../../theme/visual_performance.dart';

/// 按页面表现档位统一缩减或关闭桌面实时背景模糊。
class AppPerformanceBackdrop extends StatelessWidget {
  const AppPerformanceBackdrop({
    super.key,
    required this.sigma,
    required this.child,
    this.overVideo = false,
  });

  final double sigma;
  final bool overVideo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final effectiveSigma = context
        .select<AppThemeProvider?, AppVisualPerformanceTier>(
          (provider) =>
              provider?.visualPerformanceTier ?? AppVisualPerformanceTier.full,
        )
        .desktopBlurSigma(sigma, overVideo: overVideo);
    if (effectiveSigma <= 0) {
      return child;
    }
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: effectiveSigma, sigmaY: effectiveSigma),
      child: child,
    );
  }
}
