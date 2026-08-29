import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_theme_provider.dart';
import '../ui/app_transitions.dart';
// 路由映射已提取为公共构建器（与桌面分屏详情宿主共用）：detail_route_builder.dart。
import '../ui/detail_route_builder.dart';
import 'settings_destination_routes.dart';

class DetailHostScreen extends StatefulWidget {
  final String initialRouteName;
  final String? rootRouteName;
  final ValueListenable<String>? routeListenable;
  final ValueChanged<List<String>>? onRouteStackChanged;
  final bool enablePlatformChannel;

  const DetailHostScreen({
    super.key,
    required this.initialRouteName,
    this.rootRouteName,
    this.routeListenable,
    this.onRouteStackChanged,
    this.enablePlatformChannel = true,
  });

  @override
  State<DetailHostScreen> createState() => DetailHostScreenState();
}

class DetailHostScreenState extends State<DetailHostScreen> {
  static const MethodChannel _channel = MethodChannel('fly_player/detail_host');
  static const Duration _platformRouteApplyMinInterval = Duration(
    milliseconds: 320,
  );

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final List<String> _routeStack = _buildInitialStack();
  Timer? _pendingPlatformRouteTimer;
  String _pendingPlatformRouteName = '';
  DateTime _lastPlatformRouteAppliedAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    widget.routeListenable?.addListener(_handleRouteListenable);
    if (widget.enablePlatformChannel) {
      _channel.setMethodCallHandler(_handleMethodCall);
    }
  }

  @override
  void dispose() {
    _pendingPlatformRouteTimer?.cancel();
    widget.routeListenable?.removeListener(_handleRouteListenable);
    if (widget.enablePlatformChannel) {
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DetailHostScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeListenable != widget.routeListenable) {
      oldWidget.routeListenable?.removeListener(_handleRouteListenable);
      widget.routeListenable?.addListener(_handleRouteListenable);
      _handleRouteListenable();
    }
    if (oldWidget.enablePlatformChannel != widget.enablePlatformChannel) {
      if (oldWidget.enablePlatformChannel) {
        _channel.setMethodCallHandler(null);
      }
      if (widget.enablePlatformChannel) {
        _channel.setMethodCallHandler(_handleMethodCall);
      }
    }
  }

  List<String> _buildInitialStack() {
    final initialRoute = _normalizeRoute(widget.initialRouteName);
    final settingsStack = _settingsRouteStack(initialRoute);
    if (settingsStack != null && settingsStack.isNotEmpty) {
      return settingsStack;
    }
    final rootRoute = widget.rootRouteName?.trim().isNotEmpty == true
        ? _normalizeRoute(widget.rootRouteName!)
        : null;
    if (rootRoute == null || rootRoute == initialRoute) {
      return <String>[initialRoute];
    }
    return <String>[rootRoute, initialRoute];
  }

  String _normalizeRoute(String routeName) {
    final trimmed = routeName.trim();
    return trimmed.isEmpty ? '/parallel/placeholder' : trimmed;
  }

  bool get hasVisibleRoute =>
      _routeStack.isNotEmpty && _routeStack.last != '/parallel/placeholder';

  String get currentRoute =>
      _routeStack.isEmpty ? '/parallel/placeholder' : _routeStack.last;

  List<String> get routeStackSnapshot => List<String>.unmodifiable(_routeStack);

  Future<bool> maybePopRoute() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return false;
    return navigator.maybePop();
  }

  String _routePath(String routeName) {
    final uri = Uri.tryParse(routeName);
    final path = uri?.path.trim() ?? '';
    return path.isEmpty ? '/parallel/placeholder' : path;
  }

  String _routeTargetKey(String routeName) => routeTargetKeyFor(routeName);

  bool _sameRouteTarget(String a, String b) {
    if (a.trim().isEmpty || b.trim().isEmpty) return false;
    return _routeTargetKey(a) == _routeTargetKey(b);
  }

  bool _shouldReplaceTopRoute({
    required String currentRoute,
    required String nextRoute,
  }) {
    if (_routeStack.isEmpty) return false;
    if (_routeStack.length == 1 &&
        _routeStack.first == '/parallel/placeholder') {
      return true;
    }
    return _routePath(currentRoute) == _routePath(nextRoute);
  }

  Future<bool> popInPane() async {
    final rootRoute = widget.rootRouteName?.trim().isNotEmpty == true
        ? _normalizeRoute(widget.rootRouteName!)
        : null;
    if (_routeStack.length <= 1) {
      final current = currentRoute;
      if (rootRoute != null && current != rootRoute) {
        setState(() {
          _routeStack
            ..clear()
            ..add(rootRoute);
        });
        return true;
      }
      return false;
    }
    setState(() {
      _routeStack.removeLast();
    });
    return true;
  }

  void syncRouteStack(List<String> routeNames) {
    final normalizedStack = routeNames
        .map(_normalizeRoute)
        .where((route) => route.isNotEmpty)
        .toList(growable: false);
    if (normalizedStack.isEmpty) return;
    if (listEquals(_routeStack, normalizedStack)) return;
    setState(() {
      _routeStack
        ..clear()
        ..addAll(normalizedStack);
    });
  }

  void openRouteInPlace(String routeName) {
    _pushRoute(routeName);
  }

  void _pushRoute(String routeName) {
    final normalized = _normalizeRoute(routeName);
    final settingsStack = _settingsRouteStack(normalized);
    if (settingsStack != null && settingsStack.isNotEmpty) {
      if (listEquals(_routeStack, settingsStack)) {
        _syncRouteListenableValue(settingsStack.last);
        return;
      }
      setState(() {
        _routeStack
          ..clear()
          ..addAll(settingsStack);
      });
      _syncRouteListenableValue(settingsStack.last);
      return;
    }
    final current = _routeStack.isEmpty
        ? '/parallel/placeholder'
        : _routeStack.last;
    if (normalized == current || _sameRouteTarget(normalized, current)) return;
    setState(() {
      if (_shouldReplaceTopRoute(
        currentRoute: current,
        nextRoute: normalized,
      )) {
        if (_routeStack.isEmpty) {
          _routeStack.add(normalized);
        } else {
          _routeStack[_routeStack.length - 1] = normalized;
        }
      } else {
        _routeStack.add(normalized);
      }
    });
    _syncRouteListenableValue(normalized);
  }

  List<String>? _settingsRouteStack(String routeName) {
    final settingsStack = SettingsDestinationRoutes.buildNavigationStack(
      routeName,
    );
    if (settingsStack == null || settingsStack.isEmpty) {
      return null;
    }
    final rootRoute = widget.rootRouteName?.trim().isNotEmpty == true
        ? _normalizeRoute(widget.rootRouteName!)
        : null;
    if (rootRoute == null ||
        settingsStack.first == rootRoute ||
        routeName == rootRoute) {
      return settingsStack;
    }
    return <String>[rootRoute, ...settingsStack];
  }

  void _syncRouteListenableValue(String routeName) {
    final routeListenable = widget.routeListenable;
    if (routeListenable is ValueNotifier<String> &&
        routeListenable.value != routeName) {
      routeListenable.value = routeName;
    }
  }

  void _handleRouteListenable() {
    final nextRoute = widget.routeListenable?.value ?? '';
    if (!mounted) return;
    _pushRoute(nextRoute);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    // 原生壳分屏：播放器侧返回键委派到副栏，让副栏先在自己导航栈里回退。
    if (call.method == 'popInPane') {
      return handleBack();
    }
    // 原生壳分屏复用引擎时：显式重建整条路由栈（如 [首页, 详情]），保证返回逐层回退。
    if (call.method == 'setRouteStack') {
      final raw = (call.arguments as Map?)?['routeNames'];
      if (raw is List && raw.isNotEmpty) {
        syncRouteStack(raw.map((e) => e.toString()).toList());
      }
      return null;
    }
    if (call.method != 'replaceRoute') return null;
    final arguments = call.arguments as Map?;
    final routeName = arguments?['routeName']?.toString().trim() ?? '';
    final resetStack = arguments?['resetStack'] == true;
    if (!mounted || routeName.isEmpty) return null;
    _schedulePlatformRoute(routeName, resetStack: resetStack);
    return null;
  }

  /// 统一的返回处理：先弹内层导航页，弹不动再回退到 root（如副栏回首页）。
  /// 返回 true=已在 pane 内处理（不应收掉分屏/结束 host）；false=已在根，交由外层处理。
  Future<bool> handleBack() async {
    final navigator = _navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return true;
    }
    return popInPane();
  }

  void _schedulePlatformRoute(String routeName, {required bool resetStack}) {
    final normalizedRoute = _normalizeRoute(routeName);
    if (resetStack) {
      _pendingPlatformRouteTimer?.cancel();
      _pendingPlatformRouteTimer = null;
      _pendingPlatformRouteName = '';
      _lastPlatformRouteAppliedAt = DateTime.now();
      _replaceRouteStack(normalizedRoute);
      return;
    }
    final current = currentRoute;
    final pending = _pendingPlatformRouteName;
    if (_sameRouteTarget(normalizedRoute, current) ||
        _sameRouteTarget(normalizedRoute, pending)) {
      return;
    }
    _pendingPlatformRouteName = normalizedRoute;
    final elapsed = DateTime.now().difference(_lastPlatformRouteAppliedAt);
    final delay = elapsed >= _platformRouteApplyMinInterval
        ? Duration.zero
        : _platformRouteApplyMinInterval - elapsed;
    _pendingPlatformRouteTimer?.cancel();
    if (delay == Duration.zero) {
      _flushPendingPlatformRoute();
      return;
    }
    _pendingPlatformRouteTimer = Timer(delay, _flushPendingPlatformRoute);
  }

  void _flushPendingPlatformRoute() {
    _pendingPlatformRouteTimer = null;
    final routeName = _pendingPlatformRouteName;
    _pendingPlatformRouteName = '';
    if (!mounted || routeName.isEmpty) return;
    _lastPlatformRouteAppliedAt = DateTime.now();
    _pushRoute(routeName);
  }

  void _replaceRouteStack(String routeName) {
    final normalizedRoute = _normalizeRoute(routeName);
    final settingsStack = _settingsRouteStack(normalizedRoute);
    final nextStack = settingsStack ?? <String>[normalizedRoute];
    if (listEquals(_routeStack, nextStack)) {
      _syncRouteListenableValue(nextStack.last);
      return;
    }
    final themeProvider = context.read<AppThemeProvider>();
    // 整体替换路由栈时，先临时锁住主界面的动态清屏过渡，
    // 避免旧页面的环境色在新栈首帧渲染前闪一下。
    themeProvider.acquireRuntimeMainClearHold();
    setState(() {
      _routeStack
        ..clear()
        ..addAll(nextStack);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      themeProvider.releaseRuntimeMainClearHold();
    });
    _syncRouteListenableValue(nextStack.last);
  }

  void _handleDidRemovePage(Page<Object?> page) {
    if (_routeStack.length <= 1) return;
    // Navigator 已经完成实际移除，这里只同步我们维护的路由栈镜像。
    setState(() {
      _routeStack.removeLast();
    });
    final current = currentRoute;
    _syncRouteListenableValue(current);
    widget.onRouteStackChanged?.call(routeStackSnapshot);
  }

  @override
  Widget build(BuildContext context) {
    final pages = _routeStack
        .asMap()
        .map(
          (index, routeName) => MapEntry(
            index,
            AppTransitions.paneCardPage<void>(
              key: ValueKey<String>('detail-host-$routeName'),
              name: routeName,
              child: buildDetailRouteChild(
                routeName,
                isActiveRoute: index == _routeStack.length - 1,
              ),
            ),
          ),
        )
        .values
        .toList(growable: false);
    final rootRoute = widget.rootRouteName?.trim().isNotEmpty == true
        ? _normalizeRoute(widget.rootRouteName!)
        : null;
    // 设了 root 且当前不在 root → 返回键应先回退到 root（如副栏回首页），而不是结束本 host。
    final canPopToRoot = rootRoute != null && currentRoute != rootRoute;
    return PopScope<Object?>(
      canPop: _routeStack.length <= 1 && !canPopToRoot,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // 先弹内层页，弹不动则回退到 root（副栏回首页）；都不行才放行外层（收分屏）。
        await handleBack();
      },
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Navigator(
          key: _navigatorKey,
          pages: pages,
          onDidRemovePage: _handleDidRemovePage,
        ),
      ),
    );
  }
}
