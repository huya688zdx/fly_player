import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'external_playback_host.dart';
import 'external_playback_mini_player.dart';
import 'external_player_adapter.dart';

/// 极简模式复用主窗口和播放会话；离开时恢复窗口，不重建导航器。
class ExternalPlaybackMiniController {
  static final available = ValueNotifier(false);
  static final active = ValueNotifier(false);
  static _ExternalPlaybackMiniHostState? _host;

  static Future<void> enter() async => _host?._enter();
  static Future<void> exit() async => _host?._exit();
}

class ExternalPlaybackMiniHost extends StatefulWidget {
  const ExternalPlaybackMiniHost({super.key, required this.child});

  final Widget child;

  @override
  State<ExternalPlaybackMiniHost> createState() =>
      _ExternalPlaybackMiniHostState();
}

class _ExternalPlaybackMiniHostState extends State<ExternalPlaybackMiniHost> {
  static const _collapsedSize = Size(360, 64);
  static const _expandedSize = Size(360, 196);
  static const _settingsSize = Size(360, 492);
  bool _active = false;
  bool _expanded = false;
  bool _settingsExpanded = false;
  bool _changing = false;
  Size? _pageSize;
  Rect? _bounds;
  bool _maximized = false;
  bool _fullscreen = false;
  bool _alwaysOnTop = false;
  bool _pinned = true;
  bool _resizable = true;
  ExternalPlayerAdapter? _miniPlayer;

  @override
  void initState() {
    super.initState();
    ExternalPlaybackMiniController._host = this;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ExternalPlaybackMiniController.available.value = true;
    });
  }

  Future<void> _enter() async {
    final player = ExternalPlaybackHost.status.value?.player;
    if (_active || _changing || player == null || !player.supportsMiniPlayer) {
      return;
    }
    _changing = true;
    try {
      _miniPlayer = player;
      _fullscreen = await windowManager.isFullScreen();
      _maximized = await windowManager.isMaximized();
      _alwaysOnTop = await windowManager.isAlwaysOnTop();
      _resizable = await windowManager.isResizable();
      if (!mounted) return;
      _pageSize = MediaQuery.sizeOf(context);
      // 先保留完整页面布局，再收起窗口，避免详情页被压成悬浮条宽度。
      setState(() {
        _active = true;
        _expanded = false;
        _settingsExpanded = false;
      });
      ExternalPlaybackMiniController.active.value = true;
      await WidgetsBinding.instance.endOfFrame;
      if (_fullscreen) await windowManager.setFullScreen(false);
      if (await windowManager.isMaximized()) await windowManager.unmaximize();
      _bounds = await windowManager.getBounds();
      await windowManager.setResizable(false);
      await windowManager.setSize(_collapsedSize);
      await windowManager.setAlignment(Alignment.topCenter);
      final position = await windowManager.getPosition();
      await windowManager.setPosition(position + const Offset(0, 12));
      if (!mounted) return;
      await _setPinned(true);
      if (mounted) setState(() => _pinned = true);
    } catch (_) {
      if (_active) await _restore();
      _miniPlayer = null;
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
    await _setPinned(false);
    await windowManager.setResizable(_resizable);
    if (_bounds != null) await windowManager.setBounds(_bounds!);
    if (_maximized) await windowManager.maximize();
    if (_fullscreen) await windowManager.setFullScreen(true);
    await windowManager.setAlwaysOnTop(_alwaysOnTop);
    // 等待新尺寸进入 Flutter 后，再显示保留的页面。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() {
      _active = false;
      _expanded = false;
      _settingsExpanded = false;
      _pageSize = null;
      _bounds = null;
      _miniPlayer = null;
    });
    ExternalPlaybackMiniController.active.value = false;
  }

  Future<void> _toggleExpanded() async {
    if (!_active || _changing) return;
    _changing = true;
    try {
      final size = _expanded ? _collapsedSize : _expandedSize;
      await _resize(size);
      if (mounted) {
        setState(() {
          _expanded = !_expanded;
          _settingsExpanded = false;
        });
      }
    } finally {
      _changing = false;
    }
  }

  Future<void> _togglePinned() async {
    if (!_active || _changing) return;
    _changing = true;
    try {
      final pinned = !_pinned;
      await _setPinned(pinned);
      if (mounted) setState(() => _pinned = pinned);
    } finally {
      _changing = false;
    }
  }

  Future<void> _setPinned(bool pinned) async {
    final player = _miniPlayer;
    if (player != null) await player.setMiniPinned(pinned);
  }

  Future<void> _toggleSettings() async {
    if (!_active || !_expanded || _changing) return;
    _changing = true;
    try {
      await _resize(_settingsExpanded ? _expandedSize : _settingsSize);
      if (mounted) setState(() => _settingsExpanded = !_settingsExpanded);
    } finally {
      _changing = false;
    }
  }

  Future<void> _resize(Size size) async {
    final bounds = await windowManager.getBounds();
    var position = bounds.topLeft;
    if (size.height > bounds.height) {
      // 在底边附近展开时向上让位，防止常用操作落到屏幕外。
      final bottom = await calcWindowPosition(size, Alignment.bottomLeft);
      if (position.dy > bottom.dy) position = Offset(position.dx, bottom.dy);
    }
    await windowManager.setBounds(position & size);
  }

  @override
  void dispose() {
    if (_active) {
      unawaited(
        _setPinned(false).catchError((Object error) {
          debugPrint('关闭极简模式置顶失败：$error');
        }),
      );
    }
    _miniPlayer = null;
    if (identical(ExternalPlaybackMiniController._host, this)) {
      ExternalPlaybackMiniController._host = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ExternalPlaybackMiniController._host == null) {
          ExternalPlaybackMiniController.available.value = false;
          ExternalPlaybackMiniController.active.value = false;
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
              child: ExternalPlaybackMiniPlayer(
                expanded: _expanded,
                settingsExpanded: _settingsExpanded,
                pinned: _pinned,
                onTogglePinned: _togglePinned,
                onToggleExpanded: _toggleExpanded,
                onToggleSettings: _toggleSettings,
                onRestore: _exit,
              ),
            ),
          ),
      ],
    );
  }
}
