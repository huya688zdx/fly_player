import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// Windows 窗口外壳：标题栏跟随应用配色，全屏时让出完整画面。
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
    final colors = context.appColors;
    final brightness = ThemeData.estimateBrightnessForColor(
      colors.backgroundBase,
    );
    // 顶部缩放区域与标题栏共用实际状态，避免插件内部缓存也因漏事件而失效。
    return DragToResizeArea(
      enableResizeEdges: (_fullscreen || _maximized)
          ? const []
          : const [ResizeEdge.topLeft, ResizeEdge.top, ResizeEdge.topRight],
      child: Column(
        children: [
          if (!_fullscreen)
            SizedBox(
              height: 36,
              child: WindowCaption(
                backgroundColor: colors.backgroundBase,
                brightness: brightness,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('lib/img/app_logo.png', width: 22, height: 22),
                    const SizedBox(width: 9),
                    Text(
                      AppLocalizations.of(context).appTitle,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 保持导航器所在的结构稳定，切换全屏不会重建页面和播放器。
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(size: constraints.biggest),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
