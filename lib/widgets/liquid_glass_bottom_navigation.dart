import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/main_navigation_metrics.dart';

/// 主底部悬浮胶囊导航的条目定义。
class LiquidGlassNavDestination {
  final IconData icon;
  final String label;

  const LiquidGlassNavDestination({required this.icon, required this.label});
}

/// 悬浮胶囊底栏：内容延伸到导航条后方，单层渐隐托底（透明渐入背景色），
/// 选中块只靠填充色阶区分。供主 Shell 与分屏副栏首页复用。
class LiquidGlassBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<LiquidGlassNavDestination> destinations;

  const LiquidGlassBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLightSurface = colors.backgroundBase.computeLuminance() >= 0.58;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final safeIndex = currentIndex.clamp(0, destinations.length - 1);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final barWidth = MainNavigationMetrics.barWidthFor(viewportWidth);
    final bottomPadding = MainNavigationMetrics.outerBottomPadding(bottomInset);
    final inactive = colors.textSecondary;
    final active = Color.lerp(colors.textPrimary, colors.selection, .28)!;
    final outerSurface = Color.alphaBlend(
      colors.selection.withValues(alpha: isLightSurface ? .08 : .12),
      colors.navBarBackground,
    );
    final selectedSurface = Color.alphaBlend(
      colors.selection.withValues(alpha: isLightSurface ? .08 : .10),
      outerSurface,
    );

    // 单层渐变托底：从页面背景完全透明渐入 backgroundBase，
    // 消除旧的实色横带接缝；仅一层渐变绘制，无模糊合成开销。
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const <double>[0, .35, 1],
            colors: <Color>[
              colors.backgroundBase.withValues(alpha: 0),
              colors.backgroundBase.withValues(alpha: .72),
              colors.backgroundBase,
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: 6, bottom: bottomPadding),
          child: Center(
            heightFactor: 1,
            child: SizedBox(
              width: barWidth,
              height: MainNavigationMetrics.barHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: outerSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Color.alphaBlend(
                      colors.selection.withValues(alpha: .24),
                      outerSurface,
                    ),
                    width: .8,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: destinations.length <= 1
                          ? Alignment.center
                          : Alignment(
                              -1.0 +
                                  safeIndex * (2.0 / (destinations.length - 1)),
                              0,
                            ),
                      child: FractionallySizedBox(
                        widthFactor: 1 / destinations.length,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          // 选中块只靠填充色阶区分，去掉旧的双层描边。
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: selectedSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      // 撑满底栏高度，让图标上下的空白也能点击。
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(destinations.length, (index) {
                        final selected = index == safeIndex;
                        return Expanded(
                          child: _LiquidGlassNavItem(
                            destination: destinations[index],
                            selected: selected,
                            activeColor: active,
                            inactiveColor: inactive,
                            onTap: () => onTap(index),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidGlassNavItem extends StatelessWidget {
  final LiquidGlassNavDestination destination;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _LiquidGlassNavItem({
    required this.destination,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkResponse(
        onTap: onTap,
        radius: 44,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            height: 1.0,
          ),
          child: IconTheme(
            data: IconThemeData(color: color, size: 21),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(destination.icon),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: const TextScaler.linear(1.0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
