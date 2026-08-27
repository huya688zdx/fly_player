import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'app_modal_surface.dart';

/// 单列选项弹层的统一框架，供轨道、快捷操作和排序共同使用。
class AppOptionSheetPanel extends StatelessWidget {
  const AppOptionSheetPanel({
    super.key,
    required this.title,
    required this.child,
    this.surfaceKey,
    this.maxHeight,
    this.floating = false,
  });

  final String title;
  final Widget child;
  final Key? surfaceKey;
  final double? maxHeight;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final availableHeight = math.max(
      0.0,
      media.size.height - media.viewInsets.bottom,
    );
    final resolvedMaxHeight = math.min(
      maxHeight ?? availableHeight * .7,
      availableHeight,
    );
    final bottomContentPadding = math.max(
      media.padding.bottom,
      floating ? 22.0 : 18.0,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        bottom: false,
        child: AppModalSurface(
          key: surfaceKey,
          floating: floating,
          padding: EdgeInsets.fromLTRB(
            floating ? 22 : 16,
            floating ? 20 : 16,
            floating ? 22 : 16,
            bottomContentPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: resolvedMaxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.2,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 图 2 同款的状态选项行：左侧圆点、两级文字、独立圆角选中态。
class AppOptionListTile extends StatelessWidget {
  const AppOptionListTile({
    super.key,
    required this.title,
    required this.onTap,
    this.tileKey,
    this.subtitle = '',
    this.selected = false,
    this.destructive = false,
    this.indicatorKey,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Key? tileKey;
  final bool selected;
  final bool destructive;
  final Key? indicatorKey;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = BorderRadius.circular(14);
    final selectedColor = appModalTileColor(colors, selected: true);
    final destructiveColor = Color.alphaBlend(
      colors.danger.withValues(alpha: .10),
      colors.surfaceSubtle,
    );
    final borderColor = destructive
        ? Color.alphaBlend(
            colors.danger.withValues(alpha: .34),
            colors.borderSubtle,
          )
        : selected
        ? appModalTileBorderColor(colors, selected: true)
        : Colors.transparent;

    return AnimatedContainer(
      key: tileKey,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: destructive
            ? destructiveColor
            : selected
            ? selectedColor
            : Colors.transparent,
        borderRadius: radius,
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            child: Row(
              children: [
                _OptionSelectionIndicator(
                  indicatorKey: indicatorKey,
                  selected: selected,
                  destructive: destructive,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: destructive
                              ? colors.danger
                              : colors.textPrimary,
                          fontSize: 16,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                      if (subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: destructive
                                ? colors.danger.withValues(alpha: .78)
                                : colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionSelectionIndicator extends StatelessWidget {
  const _OptionSelectionIndicator({
    this.indicatorKey,
    required this.selected,
    required this.destructive,
  });

  final Key? indicatorKey;
  final bool selected;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = destructive ? colors.danger : colors.selection;
    final inactive = destructive
        ? colors.danger.withValues(alpha: .82)
        : Color.alphaBlend(
            colors.textSecondary.withValues(alpha: .56),
            appModalTileColor(colors),
          );

    return Container(
      key: indicatorKey,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? active : inactive, width: 1.8),
        color: selected ? active : Colors.transparent,
      ),
      child: selected
          ? Icon(
              Icons.check_rounded,
              color: Theme.of(context).colorScheme.onSecondary,
              size: 14,
            )
          : destructive
          ? Icon(Icons.remove_rounded, color: active, size: 14)
          : null,
    );
  }
}
