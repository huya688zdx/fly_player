import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_playback_mini_player.dart';

/// 播放页暴露给迷你条的最小控制面：状态快照 + 播停/±15s/切集命令。
/// 播放页挂载时注册、卸载时注销；迷你条与播放页同 isolate，直接调用。
abstract interface class DesktopPlaybackMiniDelegate {
  /// 集名：剧名 · 集标题（缺失时回退集号/剧名/标题）。
  String get miniDisplayTitle;

  bool get miniIsPlaying;

  /// 直播不可 ±15s（播放页 `_seekTo` 对直播直接忽略）。
  bool get miniCanSeek;

  bool get miniCanPrevious;

  bool get miniCanNext;

  /// 迷你条重建信号；播放页用统一的视图修订通知驱动。
  Listenable get miniChanges;

  Future<void> miniTogglePlay();

  Future<void> miniSeekBy(Duration offset);

  Future<void> miniPrevious();

  Future<void> miniNext();
}

/// 置顶迷你窗（PC 方案候选 A）：进入 = 主窗口缩为小尺寸 + 置顶
/// （window_manager 插件 `setAlwaysOnTop`，不走 PotPlayerBridge——那是外部
/// 进程的 HWND 钩子）；播放页 Offstage 保状态，复用桌面播放会话保活，
/// 会话与页面不重建。还原 = 恢复原尺寸/最大化/全屏并解除置顶。
/// 流程与窗口态保存顺序对照 `ExternalPlaybackMiniHost` 参考实现。
class DesktopPlaybackMiniController {
  static final ValueNotifier<bool> available = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// 控制面身份修订号：注册/注销时递增，迷你条随之整体重建
  /// （快捷键绑定在外层，必须跟随 delegate 身份刷新）。
  static final ValueNotifier<int> delegateRevision = ValueNotifier<int>(0);
  static DesktopPlaybackMiniDelegate? _delegate;
  static _DesktopPlaybackMiniHostState? _host;

  static DesktopPlaybackMiniDelegate? get delegate => _delegate;

  static void registerDelegate(DesktopPlaybackMiniDelegate value) {
    _delegate = value;
    delegateRevision.value++;
  }

  /// 播放页卸载：迷你窗正挂着该页时自动还原窗口，避免悬空控制条。
  static void unregisterDelegate(DesktopPlaybackMiniDelegate value) {
    if (!identical(_delegate, value)) return;
    _delegate = null;
    delegateRevision.value++;
    if (active.value) {
      final host = _host;
      if (host != null) unawaited(host._exit());
    }
  }

  static Future<void> enter() async => _host?._enter();
  static Future<void> exit() async => _host?._exit();
}

class DesktopPlaybackMiniHost extends StatefulWidget {
  const DesktopPlaybackMiniHost({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopPlaybackMiniHost> createState() =>
      _DesktopPlaybackMiniHostState();
}

class _DesktopPlaybackMiniHostState extends State<DesktopPlaybackMiniHost> {
  // 控制密度对齐外部播放器迷你条（360x64）；本条多出上一集/下一集/±15s，
  // 放宽到 440 保证集名可读。
  static const _miniSize = Size(440, 64);
  bool _active = false;
  bool _changing = false;
  bool _pinned = true;
  Size? _pageSize;
  Rect? _bounds;
  bool _maximized = false;
  bool _fullscreen = false;
  bool _alwaysOnTop = false;
  bool _resizable = true;

  @override
  void initState() {
    super.initState();
    DesktopPlaybackMiniController._host = this;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) DesktopPlaybackMiniController.available.value = true;
    });
  }

  Future<void> _enter() async {
    if (_active ||
        _changing ||
        DesktopPlaybackMiniController._delegate == null) {
      return;
    }
    _changing = true;
    try {
      _fullscreen = await windowManager.isFullScreen();
      _maximized = await windowManager.isMaximized();
      _alwaysOnTop = await windowManager.isAlwaysOnTop();
      _resizable = await windowManager.isResizable();
      if (!mounted) return;
      _pageSize = MediaQuery.sizeOf(context);
      // 先保留完整页面布局，再收起窗口，避免播放页被压成迷你条宽度。
      setState(() {
        _active = true;
        _pinned = true;
      });
      DesktopPlaybackMiniController.active.value = true;
      await WidgetsBinding.instance.endOfFrame;
      if (_fullscreen) await windowManager.setFullScreen(false);
      if (await windowManager.isMaximized()) await windowManager.unmaximize();
      _bounds = await windowManager.getBounds();
      await windowManager.setResizable(false);
      await windowManager.setSize(_miniSize);
      await windowManager.setAlignment(Alignment.topCenter);
      final position = await windowManager.getPosition();
      await windowManager.setPosition(position + const Offset(0, 12));
      await windowManager.setAlwaysOnTop(true);
    } catch (_) {
      if (_active) await _restore();
      rethrow;
    } finally {
      _changing = false;
    }
  }

  Future<void> _exit() async {
    if (!_active || _changing) return;
    _changing = true;
    try {
      await _restore();
    } finally {
      _changing = false;
    }
  }

  Future<void> _restore() async {
    await windowManager.setResizable(_resizable);
    if (_bounds != null) await windowManager.setBounds(_bounds!);
    if (_maximized) await windowManager.maximize();
    if (_fullscreen) await windowManager.setFullScreen(true);
    await windowManager.setAlwaysOnTop(_alwaysOnTop);
    // 等待新尺寸进入 Flutter 后，再显示保留的播放页。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() {
      _active = false;
      _pageSize = null;
      _bounds = null;
    });
    DesktopPlaybackMiniController.active.value = false;
  }

  Future<void> _togglePinned() async {
    if (!_active || _changing) return;
    _changing = true;
    try {
      final pinned = !_pinned;
      await windowManager.setAlwaysOnTop(pinned);
      if (mounted) setState(() => _pinned = pinned);
    } finally {
      _changing = false;
    }
  }

  @override
  void dispose() {
    if (identical(DesktopPlaybackMiniController._host, this)) {
      DesktopPlaybackMiniController._host = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (DesktopPlaybackMiniController._host == null) {
          DesktopPlaybackMiniController.available.value = false;
          DesktopPlaybackMiniController.active.value = false;
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final pageSize = _pageSize ?? media.size;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: _active,
          child: ExcludeFocus(
            excluding: _active,
            child: TickerMode(
              enabled: !_active,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: pageSize.width,
                maxWidth: pageSize.width,
                minHeight: pageSize.height,
                maxHeight: pageSize.height,
                child: MediaQuery(
                  data: media.copyWith(size: pageSize),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
        if (_active)
          MediaQuery(
            data: media.copyWith(
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              textScaler: TextScaler.noScaling,
            ),
            child: Overlay.wrap(
              child: DesktopPlaybackMiniPlayer(
                pinned: _pinned,
                onTogglePinned: _togglePinned,
                onRestore: _exit,
              ),
            ),
          ),
      ],
    );
  }
}
