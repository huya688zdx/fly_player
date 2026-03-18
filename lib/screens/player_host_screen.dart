import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/play_detail_data_loader.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../player/models/player_host_launch_args.dart';
import '../player/mpv_player_page.dart';
import '../providers/nas_provider.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../services/player_host_bridge.dart';
import '../theme/app_theme.dart';
import '../ui/player_pane_host_scope.dart';
import 'connection_screen.dart';
import 'detail_host_screen.dart';

class PlayerHostScreen extends StatefulWidget {
  const PlayerHostScreen({super.key});

  @override
  State<PlayerHostScreen> createState() => _PlayerHostScreenState();
}

class _PlayerHostScreenState extends State<PlayerHostScreen>
    with SingleTickerProviderStateMixin
    implements PlayerPaneHostController {
  static const MethodChannel _stateChannel = MethodChannel(
    'fly_player/player_host_state',
  );
  static const String _fullscreenMode = 'fullscreen';
  static const String _splitMode = 'split';
  static const String _homeRoute = '/screen/home';
  static const Duration _paneTransitionDuration = Duration(milliseconds: 240);

  final ValueNotifier<String> _rightPaneRouteNotifier = ValueNotifier<String>(
    _homeRoute,
  );
  final GlobalKey<DetailHostScreenState> _detailHostKey =
      GlobalKey<DetailHostScreenState>();
  final List<String> _rightPaneRouteStack = <String>[_homeRoute];
  late final AnimationController _paneTransitionController;
  late final CurvedAnimation _paneTransition;
  bool _splitBackExitGuardArmed = false;
  bool _detailPaneReserved = false;

  PlayerHostLaunchArgs? _currentArgs;
  String _layoutMode = _fullscreenMode;
  bool _loadingInitialArgs = true;
  _PlayerHostActivePane _activePane = _PlayerHostActivePane.player;

  bool get _isSplitMode => _layoutMode == _splitMode;

  @override
  void initState() {
    super.initState();
    _paneTransitionController = AnimationController(
      vsync: this,
      duration: _paneTransitionDuration,
      value: 0,
    );
    _paneTransition = CurvedAnimation(
      parent: _paneTransitionController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _stateChannel.setMethodCallHandler(_handleStateMethodCall);
    unawaited(_loadInitialArgs());
  }

  @override
  void dispose() {
    _stateChannel.setMethodCallHandler(null);
    _paneTransitionController.dispose();
    _rightPaneRouteNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadInitialArgs() async {
    final args = await PlayerHostBridge.consumeInitialPlayerArgs();
    if (!mounted) return;
    setState(() {
      _loadingInitialArgs = false;
      if (args != null) {
        _applyLaunchArgs(args, replaceSourceOnly: false);
      }
    });
  }

  void _applyLaunchArgs(
    PlayerHostLaunchArgs args, {
    required bool replaceSourceOnly,
  }) {
    _currentArgs = args;
    _layoutMode = args.layoutMode == _splitMode ? _splitMode : _fullscreenMode;
    _detailPaneReserved = _layoutMode == _splitMode;
    _syncPaneTransition(animate: false);
    _activePane = _PlayerHostActivePane.player;
    final nextInitialRoute = args.initialRightPaneRoute.trim();
    if (!replaceSourceOnly) {
      _splitBackExitGuardArmed =
          nextInitialRoute.isNotEmpty &&
          _normalizeRoute(nextInitialRoute) != _homeRoute;
      _resetRightPaneStack(nextInitialRoute);
      return;
    }
    final currentRoute = _currentRightPaneRoute;
    if ((currentRoute.isEmpty || currentRoute == _homeRoute) &&
        nextInitialRoute.isNotEmpty) {
      _replaceOrPushRightPaneRoute(nextInitialRoute);
    }
  }

  String _normalizeRoute(String routeName) {
    final trimmed = routeName.trim();
    return trimmed.isEmpty ? _homeRoute : trimmed;
  }

  String _routePath(String routeName) {
    final uri = Uri.tryParse(routeName);
    final path = uri?.path.trim() ?? '';
    return path.isEmpty ? _homeRoute : path;
  }

  String get _currentRightPaneRoute =>
      _rightPaneRouteStack.isEmpty ? _homeRoute : _rightPaneRouteStack.last;

  void _syncRightPaneState() {
    final currentRoute = _currentRightPaneRoute;
    if (_rightPaneRouteNotifier.value != currentRoute) {
      _rightPaneRouteNotifier.value = currentRoute;
    }
    _detailHostKey.currentState?.syncRouteStack(_rightPaneRouteStack);
  }

  void _adoptDetailHostStack() {
    final detailHost = _detailHostKey.currentState;
    if (detailHost == null) return;
    final snapshot = detailHost.routeStackSnapshot;
    if (snapshot.isEmpty) return;
    _rightPaneRouteStack
      ..clear()
      ..addAll(snapshot);
    final currentRoute = _currentRightPaneRoute;
    if (_rightPaneRouteNotifier.value != currentRoute) {
      _rightPaneRouteNotifier.value = currentRoute;
    }
  }

  void _resetRightPaneStack(String initialRoute) {
    final normalizedRoute = _normalizeRoute(initialRoute);
    _rightPaneRouteStack
      ..clear()
      ..add(_homeRoute);
    if (normalizedRoute != _homeRoute) {
      _rightPaneRouteStack.add(normalizedRoute);
      _splitBackExitGuardArmed = true;
    } else {
      _splitBackExitGuardArmed = false;
    }
    _syncRightPaneState();
  }

  void _replaceOrPushRightPaneRoute(String routeName) {
    final normalizedRoute = _normalizeRoute(routeName);
    final currentRoute = _currentRightPaneRoute;
    if (normalizedRoute == currentRoute) {
      _syncRightPaneState();
      return;
    }
    if (_routePath(currentRoute) == _routePath(normalizedRoute)) {
      if (_rightPaneRouteStack.isEmpty) {
        _rightPaneRouteStack.add(normalizedRoute);
      } else {
        _rightPaneRouteStack[_rightPaneRouteStack.length - 1] = normalizedRoute;
      }
    } else {
      _rightPaneRouteStack.add(normalizedRoute);
    }
    _splitBackExitGuardArmed = normalizedRoute != _homeRoute;
    _syncRightPaneState();
  }

  Future<void> _syncPlatformLayoutMode(String nextMode) async {
    final args = _currentArgs;
    if (args == null) return;
    await PlayerHostBridge.switchPlayerLayoutMode(
      title: args.title,
      source: args.source.toMap(),
      targetMode: nextMode,
      result: PlayDetailPlayerReturnData(
        itemGuid: args.source.itemGuid,
        currentTsSeconds: 0,
      ),
    );
  }

  Future<void> _setLayoutMode(
    String nextMode, {
    required _PlayerHostActivePane activePane,
    required bool syncPlatform,
  }) async {
    final normalizedMode = nextMode == _splitMode ? _splitMode : _fullscreenMode;
    final layoutChanged = _layoutMode != normalizedMode;
    if (mounted) {
      setState(() {
        _layoutMode = normalizedMode;
        _activePane = activePane;
      });
    } else {
      _layoutMode = normalizedMode;
      _activePane = activePane;
    }
    if (layoutChanged) {
      unawaited(_syncPaneTransition());
    }
    if (syncPlatform) {
      await _syncPlatformLayoutMode(normalizedMode);
    }
  }

  Future<void> _syncPaneTransition({bool animate = true}) async {
    final target = _isSplitMode ? 1.0 : 0.0;
    if (!animate) {
      _detailPaneReserved = target > 0.0;
      _paneTransitionController.value = target;
      return;
    }
    if ((_paneTransitionController.value - target).abs() < 0.001) {
      return;
    }
    if (target > 0.0 && !_detailPaneReserved && mounted) {
      setState(() => _detailPaneReserved = true);
    } else if (target > 0.0) {
      _detailPaneReserved = true;
    }
    await _paneTransitionController.animateTo(target);
    if (target == 0.0) {
      if (mounted) {
        setState(() => _detailPaneReserved = false);
      } else {
        _detailPaneReserved = false;
      }
    }
  }

  Future<void> _handleStateMethodCall(MethodCall call) async {
    if (call.method == 'replaceSource') {
      final rawArgs = call.arguments;
      if (rawArgs is! Map<Object?, Object?>) return;
      final args = PlayerHostLaunchArgs.fromPlatformMap(rawArgs);
      if (args == null || !mounted) return;
      setState(() => _applyLaunchArgs(args, replaceSourceOnly: true));
      return;
    }
    if (call.method == 'replaceRightPaneRoute') {
      final routeName =
          (call.arguments as Map<Object?, Object?>?)?['routeName']
              ?.toString()
              .trim() ??
          '';
      if (routeName.isEmpty) return;
      await openRoute(routeName);
    }
  }

  @override
  Future<bool> openRoute(String routeName) async {
    final normalizedRoute = routeName.trim();
    if (normalizedRoute.isEmpty) return false;
    _replaceOrPushRightPaneRoute(normalizedRoute);
    await _setLayoutMode(
      _splitMode,
      activePane: _PlayerHostActivePane.detail,
      syncPlatform: true,
    );
    return true;
  }

  @override
  Future<bool> backInPane() async {
    final detailHost = _detailHostKey.currentState;
    if (detailHost != null && await detailHost.maybePopRoute()) {
      _adoptDetailHostStack();
      _splitBackExitGuardArmed = _currentRightPaneRoute != _homeRoute;
      return true;
    }
    final currentRoute = _currentRightPaneRoute;
    if (currentRoute != _homeRoute) {
      _resetRightPaneStack(_homeRoute);
      return true;
    }
    return false;
  }

  @override
  Future<bool> closePane() async {
    if (!_isSplitMode) return true;
    _resetRightPaneStack(_homeRoute);
    await _setLayoutMode(
      _fullscreenMode,
      activePane: _PlayerHostActivePane.player,
      syncPlatform: true,
    );
    return true;
  }

  @override
  Future<bool> replacePlayerSource({
    required String title,
    required MpvMediaSource source,
  }) async {
    final current = _currentArgs;
    final nextArgs = PlayerHostLaunchArgs(
      title: title.trim(),
      source: source,
      fromParallelHost: current?.fromParallelHost ?? true,
      layoutMode: _layoutMode,
      initialRightPaneRoute: _rightPaneRouteNotifier.value,
    );
    if (!mounted) {
      _applyLaunchArgs(nextArgs, replaceSourceOnly: true);
      return true;
    }
    setState(() => _applyLaunchArgs(nextArgs, replaceSourceOnly: true));
    return true;
  }

  Future<bool> _consumeSplitBackProtection() async {
    if (!_isSplitMode) return false;
    if (await backInPane()) return true;
    if (_splitBackExitGuardArmed) {
      _splitBackExitGuardArmed = false;
      _resetRightPaneStack(_homeRoute);
      return true;
    }
    return false;
  }

  Future<void> _handleSystemBack() async {
    await _finishPlayer(force: false);
  }

  Future<void> _finishPlayer({
    Object? result,
    bool force = false,
  }) async {
    if (!force && await _consumeSplitBackProtection()) {
      return;
    }
    final playResult = result is PlayDetailPlayerReturnData
        ? result
        : PlayDetailPlayerReturnData(
            itemGuid: _currentArgs?.source.itemGuid ?? '',
            currentTsSeconds: 0,
          );
    final closed = await PlayerHostBridge.finishPlayerActivity(playResult);
    if (!closed && mounted) {
      Navigator.of(
        context,
      ).maybePop(result is PlayDetailPlayerReturnData ? result : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NasProvider>();
    final colors = context.appColors;
    if (!provider.isReady || _loadingInitialArgs) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: colors.accent)),
      );
    }
    if (!provider.isConfigured) {
      return const ConnectionScreen();
    }
    final args = _currentArgs;
    if (args == null) {
      return const _PlayerHostError(message: '当前播放器参数错误');
    }
    final playbackPrimaryOnLeft = context
        .watch<ParallelWindowSettingsProvider>()
        .playbackPrimaryOnLeft;
    return PlayerPaneHostScope(
      controller: this,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, __) => unawaited(_handleSystemBack()),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            top: false,
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final splitWidth = totalWidth < 720
                    ? totalWidth * 0.48
                    : (totalWidth * 0.42).clamp(360.0, 640.0);
                final detailContent = Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) {
                    if (_activePane != _PlayerHostActivePane.detail && mounted) {
                      setState(() => _activePane = _PlayerHostActivePane.detail);
                    }
                  },
                  child: SizedBox(
                    width: splitWidth,
                    height: constraints.maxHeight,
                    child: Builder(
                      builder: (context) {
                        final media = MediaQuery.of(context);
                        return MediaQuery(
                          data: media.copyWith(
                            size: Size(splitWidth, constraints.maxHeight),
                          ),
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Colors.black,
                            ),
                            child: DetailHostScreen(
                              key: _detailHostKey,
                              initialRouteName: _rightPaneRouteNotifier.value,
                              rootRouteName: _homeRoute,
                              routeListenable: _rightPaneRouteNotifier,
                              enablePlatformChannel: false,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
                return AnimatedBuilder(
                  animation: _paneTransition,
                  builder: (context, _) {
                    final reveal = _paneTransition.value.clamp(0.0, 1.0);
                    final reserveDetailPaneSpace =
                        _detailPaneReserved || reveal > 0.001;
                    final playerPane = Expanded(
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (_) {
                          if (_activePane != _PlayerHostActivePane.player &&
                              mounted) {
                            setState(
                              () => _activePane = _PlayerHostActivePane.player,
                            );
                          }
                        },
                        child: DecoratedBox(
                          decoration: const BoxDecoration(color: Colors.black),
                          child: KeyedSubtree(
                            key: const ValueKey<String>('player-pane'),
                            child: MpvPlayerPage(
                              title: args.title,
                              source: args.source,
                              parallelLayoutToggleEnabled: args.fromParallelHost,
                              parallelLayoutMode: _layoutMode,
                              interceptSystemBack: false,
                              onParallelLayoutModeChanged: (nextMode) async {
                                await _setLayoutMode(
                                  nextMode,
                                  activePane: _PlayerHostActivePane.player,
                                  syncPlatform: true,
                                );
                              },
                              onCloseRequested: (result) async {
                                await _finishPlayer(result: result, force: true);
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                    final detailPane = SizedBox(
                      width: reserveDetailPaneSpace ? splitWidth : 0,
                      child: IgnorePointer(
                        ignoring: reveal < 0.98,
                        child: ClipRect(
                          child: Align(
                            alignment: playbackPrimaryOnLeft
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            widthFactor: reveal,
                            child: Opacity(
                              opacity: reveal,
                              child: RepaintBoundary(child: detailContent),
                            ),
                          ),
                        ),
                      ),
                    );
                    final children = playbackPrimaryOnLeft
                        ? <Widget>[playerPane, detailPane]
                        : <Widget>[detailPane, playerPane];
                    return Stack(
                      children: [
                        Positioned.fill(child: Row(children: children)),
                        if (reveal > 0.001)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Align(
                                alignment: playbackPrimaryOnLeft
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Opacity(
                                  opacity: reveal,
                                  child: Container(
                                    width: 1,
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

enum _PlayerHostActivePane { player, detail }

class _PlayerHostError extends StatelessWidget {
  final String message;

  const _PlayerHostError({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: Center(
        child: Text(
          message,
          style: TextStyle(color: colors.textSecondary, fontSize: 16),
        ),
      ),
    );
  }
}
