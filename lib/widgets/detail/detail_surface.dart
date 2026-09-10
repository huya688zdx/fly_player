import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 详情页信息块的统一表面：用低饱和主题渐变、细边和轻投影建立层次。
BoxDecoration detailSurfaceDecoration(
  BuildContext context, {
  double radius = 24,
}) {
  final colors = context.appColors;
  final isLight = colors.backgroundBase.computeLuminance() >= .55;
  final topBase = isLight ? colors.surface : colors.surfaceStrong;
  final bottomBase = colors.surfaceSubtle;
  final top = Color.alphaBlend(
    colors.accent.withValues(alpha: isLight ? .035 : .055),
    topBase,
  );
  final bottom = Color.alphaBlend(
    colors.accent.withValues(alpha: isLight ? .018 : .032),
    bottomBase,
  );
  final border = Color.alphaBlend(
    colors.accent.withValues(alpha: isLight ? .14 : .18),
    colors.borderSubtle,
  );

  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[top, bottom],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border, width: .8),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: isLight
            ? colors.accent.withValues(alpha: .075)
            : Colors.black.withValues(alpha: .18),
        blurRadius: isLight ? 20 : 16,
        offset: const Offset(0, 7),
      ),
    ],
  );
}

/// 压在海报图上的顶部圆形控件需要比正文信息块更实、更聚焦。
BoxDecoration detailFloatingControlDecoration(
  BuildContext context, {
  required double radius,
}) {
  final colors = context.appColors;
  final isLight = colors.backgroundBase.computeLuminance() >= .55;
  final topBase = isLight ? colors.surface : colors.surfaceStrong;
  final bottomBase = colors.backgroundElevated;
  final top = Color.alphaBlend(
    colors.accent.withValues(alpha: isLight ? .075 : .09),
    topBase,
  );
  final bottom = Color.alphaBlend(
    colors.accent.withValues(alpha: isLight ? .025 : .045),
    bottomBase,
  );

  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[top, bottom],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: Color.alphaBlend(
        colors.accent.withValues(alpha: isLight ? .22 : .28),
        colors.borderStrong,
      ),
      width: .8,
    ),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: isLight ? .10 : .22),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

class DetailSurface extends StatelessWidget {
  const DetailSurface({
    super.key,
    required this.child,
    this.padding,
    this.radius = 24,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    Widget content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    if (onTap != null) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            child: content,
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: detailSurfaceDecoration(context, radius: radius),
        child: content,
      ),
    );
  }
}
