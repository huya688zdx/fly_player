import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../app_atmospheric_background.dart';

/// 设置类页面的氛围底：自绘与首页同源的三层光晕（不透明底）。
///
/// 页面必须整面不透明：设置子页经 AppTransitions 路由互相叠加，
/// 透明脚手架会把下层页面透出来（转场残影）。首页/收藏/分类等内容页
/// 同样自带这层氛围并整面覆盖壳层光晕，视觉与壳层连续，故设置页照此办理。
/// 动态取色切换时 palette 随 [context.appColors] 同步重建。
class AppAmbientPage extends StatelessWidget {
  const AppAmbientPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppAtmosphericBackground(
      palette: AppAtmospherePalette.resolve(
        baseColors: context.baseAppColors,
        effectiveColors: context.appColors,
        hasDynamicTheme: context.hasRuntimeAppColors,
      ),
      child: child,
    );
  }
}
