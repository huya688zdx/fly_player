import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// 播放器内浮层面板的呈现样式。
enum PlayerOverlayPanelStyle {
  /// 右侧全高抽屉（轨道/画质等短列表）。
  sideDrawer,

  /// 顶栏下方右侧悬浮卡（选集）。
  floatCard,

  /// 居中独立弹窗（播放设置）。
  centeredDialog,
}

/// 播放器浮层面板入口。
///
/// `sideDrawer` 为右侧全高抽屉，`floatCard` 为顶栏下方右侧悬浮卡（底边悬于
/// 控制条上方），`centeredDialog` 为居中独立弹窗——不依附窗口边缘。
Future<void> showPlayerOverlayPanel(
  BuildContext context, {
  required WidgetBuilder builder,
  required PlayerOverlayPanelStyle style,
  required String barrierLabel,
  String? closeTooltip,
  VoidCallback? onAfterClose,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: style == PlayerOverlayPanelStyle.floatCard
        ? const Color(0x28000000)
        : const Color(0x70000000),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      switch (style) {
        case PlayerOverlayPanelStyle.centeredDialog:
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              child: child,
            ),
          );
        case PlayerOverlayPanelStyle.sideDrawer:
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        case PlayerOverlayPanelStyle.floatCard:
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
      }
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      switch (style) {
        case PlayerOverlayPanelStyle.floatCard:
          return _FloatCardPanel(builder: builder);
        case PlayerOverlayPanelStyle.centeredDialog:
          return _CenteredDialogPanel(
            builder: builder,
            closeTooltip: closeTooltip,
          );
        case PlayerOverlayPanelStyle.sideDrawer:
          return _SideDrawerPanel(builder: builder, closeTooltip: closeTooltip);
      }
    },
  ).whenComplete(() => onAfterClose?.call());
}

/// 弹窗内容统一关闭贴边滚动条：与悬浮玻璃卡一致，滚动靠滚轮/拖拽。
class _DialogScrollless extends StatelessWidget {
  const _DialogScrollless({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: child,
    );
  }
}

/// 选集悬浮卡：top 对齐顶栏下方、right 24、bottom 悬于控制条上方，
/// 列表/网格双视图由 DesktopEpisodePanel 自带。
class _FloatCardPanel extends StatelessWidget {
  const _FloatCardPanel({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.30).clamp(340.0, 430.0).toDouble();
    final bottomGap = (size.height * 0.16).clamp(112.0, 160.0).toDouble();
    return Padding(
      padding: EdgeInsets.only(top: 72, right: 24, bottom: bottomGap),
      child: Align(
        alignment: Alignment.topRight,
        child: Material(
          color: const Color(0x990B111C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          elevation: 24,
          shadowColor: Colors.black,
          clipBehavior: Clip.antiAlias,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: SizedBox(
                width: width,
                height: double.infinity,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: _DialogScrollless(child: builder(context)),
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

/// 居中独立弹窗（播放设置）：脱离窗口边缘，带遮罩与关闭钮。
class _CenteredDialogPanel extends StatelessWidget {
  const _CenteredDialogPanel({required this.builder, this.closeTooltip});

  final WidgetBuilder builder;
  final String? closeTooltip;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.42).clamp(420.0, 560.0).toDouble();
    final height = (size.height * 0.84).clamp(480.0, 780.0).toDouble();
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Material(
          color: const Color(0x990B111C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          elevation: 28,
          shadowColor: Colors.black,
          clipBehavior: Clip.antiAlias,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: _DialogScrollless(child: builder(context)),
                    ),
                    if (closeTooltip != null)
                      Positioned(
                        top: 14,
                        right: 16,
                        child: IconButton(
                          tooltip: closeTooltip,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white,
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0x1FFFFFFF),
                            hoverColor: const Color(0x38FFFFFF),
                            fixedSize: const Size.square(36),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0x20FFFFFF)),
                            ),
                          ),
                        ),
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

/// 原型设置抽屉固定在约 400px，避免宽屏下膨胀成占据半屏的移动端大面板。
class _SideDrawerPanel extends StatelessWidget {
  const _SideDrawerPanel({required this.builder, this.closeTooltip});

  final WidgetBuilder builder;
  final String? closeTooltip;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.30).clamp(340.0, 400.0).toDouble();
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: const Color(0x990B111C),
        elevation: 28,
        shadowColor: Colors.black,
        shape: const Border(left: BorderSide(color: Color(0x1AFFFFFF))),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: SizedBox(
              width: width,
              height: double.infinity,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: _DialogScrollless(child: builder(context)),
                  ),
                  if (closeTooltip != null)
                    Positioned(
                      top: 14,
                      right: 16,
                      child: IconButton(
                        tooltip: closeTooltip,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0x1FFFFFFF),
                          hoverColor: const Color(0x38FFFFFF),
                          fixedSize: const Size.square(36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0x20FFFFFF)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
