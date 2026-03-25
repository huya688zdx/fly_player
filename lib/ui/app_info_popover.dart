import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppInfoPopoverAnchor extends StatefulWidget {
  final Widget child;
  final String title;
  final String description;
  final String? detail;
  final double maxWidth;
  final bool preferBelow;

  const AppInfoPopoverAnchor({
    super.key,
    required this.child,
    required this.title,
    required this.description,
    this.detail,
    this.maxWidth = 320,
    this.preferBelow = false,
  });

  @override
  State<AppInfoPopoverAnchor> createState() => _AppInfoPopoverAnchorState();
}

class _AppInfoPopoverAnchorState extends State<AppInfoPopoverAnchor> {
  final GlobalKey _anchorKey = GlobalKey();

  OverlayEntry? _overlayEntry;

  bool get _isShowing => _overlayEntry != null;

  @override
  void dispose() {
    _hidePopover(notify: false);
    super.dispose();
  }

  void _togglePopover() {
    if (_isShowing) {
      _hidePopover();
      return;
    }
    _showPopover();
  }

  void _showPopover() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final anchorBox =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || anchorBox == null) {
      return;
    }

    final overlaySize = overlayBox.size;
    final safePadding = MediaQuery.paddingOf(context);
    final anchorOffset = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final anchorRect = anchorOffset & anchorBox.size;
    const horizontalMargin = 16.0;
    const verticalGap = 12.0;
    const arrowSize = 14.0;
    final width = math.min(
      widget.maxWidth,
      overlaySize.width - (horizontalMargin * 2),
    );
    final availableAbove =
        anchorRect.top - safePadding.top - verticalGap - arrowSize;
    final availableBelow =
        overlaySize.height -
        safePadding.bottom -
        anchorRect.bottom -
        verticalGap -
        arrowSize;
    final showBelow = widget.preferBelow
        ? availableBelow > 120 || availableBelow >= availableAbove
        : availableAbove <= 120 && availableBelow > availableAbove;
    final left = (anchorRect.center.dx - (width / 2)).clamp(
      horizontalMargin,
      overlaySize.width - width - horizontalMargin,
    );
    final arrowCenter = (anchorRect.center.dx - left).clamp(26.0, width - 26.0);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _hidePopover,
                  ),
                ),
                Positioned(
                  left: left,
                  width: width,
                  top: showBelow ? anchorRect.bottom + verticalGap : null,
                  bottom: showBelow
                      ? null
                      : overlaySize.height - anchorRect.top + verticalGap,
                  child: _InfoPopoverCard(
                    title: widget.title,
                    description: widget.description,
                    detail: widget.detail,
                    preferBelow: showBelow,
                    arrowCenter: arrowCenter,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
    if (mounted) {
      setState(() {});
    }
  }

  void _hidePopover({bool notify = true}) {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (notify && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _anchorKey,
      child: InkResponse(
        onTap: _togglePopover,
        radius: 20,
        highlightShape: BoxShape.circle,
        child: widget.child,
      ),
    );
  }
}

class _InfoPopoverCard extends StatelessWidget {
  final String title;
  final String description;
  final String? detail;
  final bool preferBelow;
  final double arrowCenter;

  const _InfoPopoverCard({
    required this.title,
    required this.description,
    required this.detail,
    required this.preferBelow,
    required this.arrowCenter,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final background = Color.alphaBlend(
      colors.accentSoft.withValues(alpha: 0.12),
      colors.surfaceStrong.withValues(alpha: 0.96),
    );
    final borderColor = colors.borderStrong.withValues(alpha: 0.82);
    final shadowColor = colors.overlayScrim.withValues(alpha: 0.24);
    final arrow = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: background,
        border: Border(
          top: BorderSide(color: borderColor),
          left: BorderSide(color: borderColor),
        ),
      ),
      transform: Matrix4.rotationZ(math.pi / 4),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final offsetY = (1 - value) * (preferBelow ? -10 : 10);
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, offsetY),
            child: Transform.scale(
              scale: 0.96 + (0.04 * value),
              alignment: preferBelow
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(
              top: preferBelow ? 10 : 0,
              bottom: preferBelow ? 0 : 10,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    background,
                    Color.alphaBlend(
                      colors.selectionSoft.withValues(alpha: 0.08),
                      background,
                    ),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: borderColor),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colors.accentSoft.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: colors.accent.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.8,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (detail != null && detail!.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Container(
                      height: 1,
                      color: colors.borderSubtle.withValues(alpha: 0.82),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      detail!,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 11.9,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            left: arrowCenter - 7,
            top: preferBelow ? 3 : null,
            bottom: preferBelow ? null : 3,
            child: arrow,
          ),
        ],
      ),
    );
  }
}
