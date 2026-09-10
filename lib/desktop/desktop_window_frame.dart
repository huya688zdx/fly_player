import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 窗口外壳：透明控制区叠在页面背景上，全屏时让出完整画面。
class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener, WidgetsBindingObserver {
  bool _fullscreen = false;
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_readWindowState());
  }

  @override
  void didChangeMetrics() {
    // 最大化窗口退出播放全屏时，插件可能漏发退出事件，以实际状态为准。
    unawaited(_readWindowState());
  }

  Future<void> _readWindowState() async {
    final fullscreen = await windowManager.isFullScreen();
    final maximized = await windowManager.isMaximized();
    if (mounted && (fullscreen != _fullscreen || maximized != _maximized)) {
      setState(() {
        _fullscreen = fullscreen;
        _maximized = maximized;
      });
    }
  }

  @override
  void onWindowEnterFullScreen() => setState(() => _fullscreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullscreen = false);

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final captionHeight = _fullscreen ? 0.0 : 32.0;
    // 顶部缩放区域与标题栏共用实际状态，避免插件内部缓存也因漏事件而失效。
    return DragToResizeArea(
      enableResizeEdges: (_fullscreen || _maximized)
          ? const []
          : const [ResizeEdge.topLeft, ResizeEdge.top, ResizeEdge.topRight],
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 页面背景铺满窗口，内容通过系统安全区避开顶部窗口操作。
          // 导航器始终位于同一位置，全屏切换不会重建页面和播放器。
          MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(
                top: media.padding.top + captionHeight,
              ),
              viewPadding: media.viewPadding.copyWith(
                top: media.viewPadding.top + captionHeight,
              ),
            ),
            child: widget.child,
          ),
          if (!_fullscreen)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: captionHeight,
              child: Material(
                key: const ValueKey('desktop-window-caption'),
                type: MaterialType.transparency,
                child: Row(
                  children: [
                    const Expanded(
                      child: DragToMoveArea(child: SizedBox.expand()),
                    ),
                    _captionButton(
                      Icons.remove,
                      '最小化',
                      () => windowManager.minimize(),
                    ),
                    _captionButton(
                      _maximized ? Icons.filter_none : Icons.crop_square,
                      _maximized ? '还原' : '最大化',
                      () => _maximized
                          ? windowManager.unmaximize()
                          : windowManager.maximize(),
                    ),
                    _captionButton(
                      Icons.close,
                      '关闭',
                      () => windowManager.close(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _captionButton(IconData icon, String label, VoidCallback onPressed) {
    return IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(46, 32),
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(),
        hoverColor: icon == Icons.close
            ? const Color(0xffC42B1C)
            : Colors.white24,
      ),
      // 描边只跟随图标笔画，不铺底块；白色笔画与黑色细边适应明暗画面。
      icon: Icon(
        icon,
        semanticLabel: label,
        size: 16,
        color: Colors.white,
        shadows: const [
          Shadow(color: Colors.black87, offset: Offset(-0.65, 0)),
          Shadow(color: Colors.black87, offset: Offset(0.65, 0)),
          Shadow(color: Colors.black87, offset: Offset(0, -0.65)),
          Shadow(color: Colors.black87, offset: Offset(0, 0.65)),
        ],
      ),
    );
  }
}
