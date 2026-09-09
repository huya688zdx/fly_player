import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../app_atmospheric_background.dart';

/// 设置类页面的氛围底；桌面设置导航可统一持有背景，子页只绘制内容。
class AppAmbientPage extends StatelessWidget {
  const AppAmbientPage({
    super.key,
    required this.child,
    this.shareBackground = false,
  });

  final Widget child;
  final bool shareBackground;

  static bool sharesBackgroundOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SharedAmbientBackground>() !=
      null;

  @override
  Widget build(BuildContext context) {
    if (sharesBackgroundOf(context)) return child;
    final content = shareBackground
        ? _SharedAmbientBackground(child: child)
        : child;
    // 宽窗复用壳层整窗背景；独立设置窗口在导航器外绘制一次。
    if (shareBackground &&
        context.findAncestorWidgetOfExactType<AppAtmosphericBackground>() !=
            null) {
      return content;
    }
    return AppAtmosphericBackground(
      palette: AppAtmospherePalette.resolve(
        baseColors: context.baseAppColors,
        effectiveColors: context.appColors,
        hasDynamicTheme: context.hasRuntimeAppColors,
      ),
      child: content,
    );
  }
}

class _SharedAmbientBackground extends InheritedWidget {
  const _SharedAmbientBackground({required super.child});

  @override
  bool updateShouldNotify(_SharedAmbientBackground oldWidget) => false;
}
