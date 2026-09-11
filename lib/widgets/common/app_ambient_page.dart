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

  /// 设置卡片在各平台透出氛围底色，与背景是否由导航器共用无关。
  static Color cardColorOf(BuildContext context, Color color) =>
      color.withValues(alpha: 0.16);

  /// 设置控件与状态统一沿用选择色，不修改全局主题配方。
  static AppThemeColors controlColorsOf(BuildContext context) {
    final colors = context.appColors;
    return colors.copyWith(
      accent: colors.selection,
      accentSoft: colors.selectionSoft,
      accentStrong: colors.selectionStrong,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (sharesBackgroundOf(context)) return child;
    final theme = Theme.of(context);
    final themedChild = Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? context.appColors.textMuted
                  : context.appColors.selectionStrong,
            ),
          ),
        ),
      ),
      child: child,
    );
    final content = shareBackground
        ? _SharedAmbientBackground(child: themedChild)
        : themedChild;
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
