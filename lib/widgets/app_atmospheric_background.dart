import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_theme_provider.dart';

import '../theme/app_theme.dart';

@immutable
class AppAtmospherePalette {
  const AppAtmospherePalette({
    required this.base,
    required this.accentGlow,
    required this.selectionGlow,
    required this.linkGlow,
    required this.hasDynamicTheme,
  });

  final Color base;
  final Color accentGlow;
  final Color selectionGlow;
  final Color linkGlow;
  final bool hasDynamicTheme;

  factory AppAtmospherePalette.resolve({
    required AppThemeColors baseColors,
    required AppThemeColors effectiveColors,
    required bool hasDynamicTheme,
  }) {
    final isLight = baseColors.backgroundBase.computeLuminance() >= .58;
    if (!hasDynamicTheme) {
      return AppAtmospherePalette(
        base: baseColors.backgroundBase,
        accentGlow: baseColors.accent.withValues(alpha: isLight ? .08 : .15),
        selectionGlow: baseColors.selection.withValues(
          alpha: isLight ? .06 : .11,
        ),
        linkGlow: baseColors.link.withValues(alpha: isLight ? .05 : .08),
        hasDynamicTheme: false,
      );
    }

    return AppAtmospherePalette(
      base: Color.alphaBlend(
        effectiveColors.backgroundBase.withValues(alpha: isLight ? .06 : .10),
        baseColors.backgroundBase,
      ),
      accentGlow: effectiveColors.accent.withValues(alpha: isLight ? .16 : .30),
      selectionGlow: effectiveColors.selection.withValues(
        alpha: isLight ? .13 : .24,
      ),
      linkGlow: effectiveColors.link.withValues(alpha: isLight ? .10 : .18),
      hasDynamicTheme: true,
    );
  }
}

/// 以中性底承载主题和动态取色的多层氛围背景。
class AppAtmosphericBackground extends StatelessWidget {
  const AppAtmosphericBackground({
    super.key,
    required this.palette,
    required this.child,
  });

  final AppAtmospherePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isLight = palette.base.computeLuminance() >= .58;
    final iconBrightness = isLight ? Brightness.dark : Brightness.light;
    final style = context.select<AppThemeProvider?, AppBackgroundStyle>(
      (provider) => provider?.backgroundStyle ?? AppBackgroundStyle.softMist,
    );
    final background = AppAtmosphereSurface(palette: palette, style: style);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey<String>('app-atmosphere-system-ui'),
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: palette.base,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: iconBrightness,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: RepaintBoundary(
              key: const ValueKey<String>('app-atmosphere-static-layer'),
              child:
                  !kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.android &&
                      style == AppBackgroundStyle.softMist
                  ? _AppAtmosphereSnapshot(
                      // 颜色变化时重建快照；尺寸与像素比由 SnapshotWidget 更新。
                      key: ValueKey((
                        palette.base,
                        palette.accentGlow,
                        palette.selectionGlow,
                        palette.linkGlow,
                      )),
                      child: background,
                    )
                  : background,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// 仅缓存静态背景，避免 Android Vulkan 每帧重复绘制全屏渐变。
class _AppAtmosphereSnapshot extends StatefulWidget {
  const _AppAtmosphereSnapshot({super.key, required this.child});

  final Widget child;

  @override
  State<_AppAtmosphereSnapshot> createState() => _AppAtmosphereSnapshotState();
}

class _AppAtmosphereSnapshotState extends State<_AppAtmosphereSnapshot> {
  final _controller = SnapshotController(allowSnapshotting: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: _controller,
    autoresize: true,
    child: widget.child,
  );
}

/// 页面与设置缩略图共用的静态背景，不修改系统栏或读取全局样式。
class AppAtmosphereSurface extends StatelessWidget {
  const AppAtmosphereSurface({
    super.key,
    required this.palette,
    required this.style,
  });

  final AppAtmospherePalette palette;
  final AppBackgroundStyle style;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey<String>('app-atmosphere-base'),
    color: palette.base,
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (style == AppBackgroundStyle.softMist)
          _AtmosphereGlow(
            glowKey: const ValueKey<String>('app-atmosphere-accent'),
            color: palette.accentGlow,
            // 半径略大于视口：顶部主晕染铺得更开，接入侧栏后
            // 左上整块读作同一条缓变渐变，而不是角落一团亮斑。
            center: const Alignment(-1.02, -.92),
            radius: 1.05,
          ),
        if (style == AppBackgroundStyle.softMist)
          _AtmosphereGlow(
            glowKey: const ValueKey<String>('app-atmosphere-selection'),
            color: palette.selectionGlow,
            center: const Alignment(1.04, -.16),
            radius: .96,
          ),
        if (style == AppBackgroundStyle.softMist)
          _AtmosphereGlow(
            glowKey: const ValueKey<String>('app-atmosphere-link'),
            color: palette.linkGlow,
            center: const Alignment(-.72, .74),
            radius: 1.02,
          ),
        if (style == AppBackgroundStyle.edgeGlow) ...<Widget>[
          _AtmosphereGlow(
            glowKey: const ValueKey<String>('app-atmosphere-edge-left'),
            color: palette.accentGlow,
            center: const Alignment(-1.35, -.6),
            radius: .72,
          ),
          _AtmosphereGlow(
            glowKey: const ValueKey<String>('app-atmosphere-edge-right'),
            color: palette.selectionGlow,
            center: const Alignment(1.35, .35),
            radius: .72,
          ),
        ],
        if (style == AppBackgroundStyle.auroraRibbon)
          Positioned.fill(
            child: CustomPaint(painter: _AuroraRibbonPainter(palette)),
          ),
        if (style == AppBackgroundStyle.cinemaLight)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    palette.accentGlow,
                    palette.selectionGlow.withValues(
                      alpha: palette.selectionGlow.a * .45,
                    ),
                    Colors.transparent,
                  ],
                  stops: const <double>[0, .24, .75],
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey<String>('app-atmosphere-vignette'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.transparent,
                    palette.base.withValues(alpha: .06),
                    palette.base.withValues(alpha: .32),
                  ],
                  stops: const <double>[0, .64, 1],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AuroraRibbonPainter extends CustomPainter {
  const _AuroraRibbonPainter(this.palette);

  final AppAtmospherePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * .15
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height * .065);
    final upper = Path()
      ..moveTo(-size.width * .15, size.height * .48)
      ..cubicTo(
        size.width * .25,
        -size.height * .12,
        size.width * .55,
        size.height * .62,
        size.width * 1.15,
        size.height * .12,
      );
    canvas.drawPath(upper, paint..color = palette.accentGlow);
    final lower = Path()
      ..moveTo(-size.width * .15, size.height * .7)
      ..cubicTo(
        size.width * .35,
        size.height * .1,
        size.width * .7,
        size.height * .88,
        size.width * 1.15,
        size.height * .38,
      );
    canvas.drawPath(lower, paint..color = palette.selectionGlow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AuroraRibbonPainter oldDelegate) =>
      oldDelegate.palette.accentGlow != palette.accentGlow ||
      oldDelegate.palette.selectionGlow != palette.selectionGlow;
}

/// 图标按钮使用的协调色组，避免把高饱和取色直接铺到边框和图标。
@immutable
class AppTonalControlPalette {
  const AppTonalControlPalette({
    required this.fill,
    required this.border,
    required this.foreground,
  });

  final Color fill;
  final Color border;
  final Color foreground;

  factory AppTonalControlPalette.resolve({
    required AppThemeColors colors,
    required bool active,
  }) {
    if (!active) {
      return AppTonalControlPalette(
        fill: colors.surfaceSubtle,
        border: colors.borderSubtle,
        foreground: colors.textSecondary,
      );
    }
    return AppTonalControlPalette(
      fill: Color.alphaBlend(
        colors.selection.withValues(alpha: .14),
        colors.surface,
      ),
      border: Color.alphaBlend(
        colors.selection.withValues(alpha: .30),
        colors.borderStrong,
      ),
      foreground: Color.lerp(colors.textPrimary, colors.selection, .34)!,
    );
  }
}

class _AtmosphereGlow extends StatelessWidget {
  const _AtmosphereGlow({
    required this.glowKey,
    required this.color,
    required this.center,
    required this.radius,
  });

  final Key glowKey;
  final Color color;
  final Alignment center;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          key: glowKey,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: center,
              radius: radius,
              colors: <Color>[color, Colors.transparent],
              stops: const <double>[0, 1],
            ),
          ),
        ),
      ),
    );
  }
}
