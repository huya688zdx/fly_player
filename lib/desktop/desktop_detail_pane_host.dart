import 'dart:async';

import 'package:flutter/material.dart';

import '../models/play_info.dart';
import '../playback/playback_source.dart';
import '../services/play_stats/play_stats.dart';
import '../theme/app_theme.dart';
import '../ui/app_transitions.dart';
import '../ui/detail_route_builder.dart';
import '../ui/player_pane_host_scope.dart';
import '../utils/async_action_guard.dart';
import '../widgets/common/app_ambient_page.dart';
import 'desktop_split_controller.dart';

/// 桌面「浏览 | 详情」分屏的详情宿主。
///
/// 提供 Flutter 侧 [PlayerPaneHostScope] + [PlayerPaneHostController] 实现，
/// 让 `EmbeddedDetailLauncher` 在 pane 存在时完全走 Flutter 侧 pane 通道
/// （openRoute/backInPane/closePane），不再触碰 Android 平台通道。
///
/// 设置允许分屏时，打开路由展开副屏；退到栈底或关闭只收起副屏。
/// 页面使用自身的返回按钮，宿主不再叠加工具条。
class DesktopDetailPaneHost extends StatefulWidget {
  const DesktopDetailPaneHost({
    super.key,
    this.splitController,
    this.onGenerateRoute,
    this.onHostReady,
  });

  /// 共享的分屏控制器（正式接线时由桌面 Shell 传入）。
  /// 传 null 时内部自建，便于独立使用与测试。
  final DesktopSplitController? splitController;

  /// 自定义路由工厂（测试注入极简映射用）；缺省使用
  /// `buildDetailRouteChild` 的统一映射。
  final RouteFactory? onGenerateRoute;

  /// 宿主就绪 / 卸载回调：Shell 借此把 controller 注入全局 pane 代理，
  /// 让 pane 槽位之外的入口（侧栏 / 首页）也能往右栏打开二级页。
  final ValueChanged<PlayerPaneHostController?>? onHostReady;

  @override
  State<DesktopDetailPaneHost> createState() => DesktopDetailPaneHostState();
}

class DesktopDetailPaneHostState extends State<DesktopDetailPaneHost>
    implements PlayerPaneHostController {
  /// 栈底占位路由：永远位于索引 0，表示「尚未打开任何详情」。
  static const String baseRouteName = '/desktop/pane-base';

  static const Duration _openDebounce = Duration(milliseconds: 320);

  late DesktopSplitController _splitController;
  late bool _ownsSplitController;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// 内嵌 Navigator 的路由栈镜像：[0] 恒为 base，与导航栈保持同步
  /// （push 时同步写入，pop/remove/replace 由 [_PaneRouteSyncObserver] 回推）。
  final List<String> _routeStack = <String>[baseRouteName];

  late final _PaneRouteSyncObserver _routeObserver = _PaneRouteSyncObserver(
    _handleRouteRemoved,
  );

  @override
  void initState() {
    super.initState();
    _ownsSplitController = false;
    _adoptSplitController(widget.splitController);
    widget.onHostReady?.call(this);
  }

  @override
  void didUpdateWidget(covariant DesktopDetailPaneHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.splitController, oldWidget.splitController)) {
      _adoptSplitController(widget.splitController);
    }
  }

  void _adoptSplitController(DesktopSplitController? external) {
    if (_ownsSplitController) {
      _splitController.dispose();
    }
    if (external != null) {
      _splitController = external;
      _ownsSplitController = false;
    } else {
      _splitController = DesktopSplitController(enabled: true);
      _ownsSplitController = true;
    }
  }

  @override
  void dispose() {
    widget.onHostReady?.call(null);
    if (_ownsSplitController) {
      _splitController.dispose();
    }
    super.dispose();
  }

  /// 当前栈顶路由名称；栈底（base）时返回 null。
  String? get currentRouteName =>
      _routeStack.length > 1 ? _routeStack.last : null;

  @override
  Future<bool> openRoute(String routeName) async {
    final normalized = routeName.trim();
    if (normalized.isEmpty) return false;
    _splitController.paneVisible = true;
    final targetKey = routeTargetKeyFor(normalized);
    // 同目标防抖：栈顶已是同一目标（详情按 guid 判定）→ 视为成功，不重复压栈。
    if (routeTargetKeyFor(_routeStack.last) == targetKey) return true;
    return AsyncActionGuard.run<bool>(
      'desktop_pane_open:$targetKey',
      settleDuration: _openDebounce,
      action: () async {
        if (!mounted) return false;
        final navigator = _navigatorKey.currentState;
        if (navigator == null) return false;
        if (routeTargetKeyFor(_routeStack.last) == targetKey) return true;
        final replaceTop =
            _routeStack.length > 1 &&
            paneRoutePath(_routeStack.last) == paneRoutePath(normalized);
        setState(() {
          if (replaceTop) {
            _routeStack[_routeStack.length - 1] = normalized;
          } else {
            _routeStack.add(normalized);
          }
        });
        // 同路径换目标（如详情→另一条目详情）替换栈顶，保持栈深不增长。
        final pendingPush = replaceTop
            ? navigator.pushReplacementNamed<Object?, Object?>(normalized)
            : navigator.pushNamed<Object?>(normalized);
        unawaited(pendingPush.catchError((Object _) => null));
        return true;
      },
    );
  }

  @override
  Future<bool> backInPane() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return false;
    if (!navigator.canPop() || _routeStack.length <= 1) {
      // 栈底（base 占位）：pane 内无页可退，交由外层决定收起分屏。
      return false;
    }
    return navigator.maybePop();
  }

  @override
  Future<bool> closePane() async {
    final navigator = _navigatorKey.currentState;
    if (navigator != null && _routeStack.length > 1) {
      navigator.popUntil((route) => route.isFirst);
    }
    _splitController.paneVisible = false;
    return true;
  }

  @override
  Future<bool> replacePlayerSource({
    required String title,
    required MpvMediaSource source,
    PlayInfoData? initialPlayInfo,
    PlayStartSource startSource = PlayStartSource.manual,
  }) async {
    // 桌面播放内核选型未定，桌面宿主不承载播放。
    return false;
  }

  void _handleRouteRemoved(Route<Object?> route) {
    final name = route.settings.name;
    if (name == null || !mounted) return;
    final index = _routeStack.lastIndexOf(name);
    if (index <= 0) return; // base 占位永不移除
    setState(() {
      _routeStack.removeAt(index);
    });
    if (_routeStack.length == 1) {
      // 路由观察者也接住页面自身的 Navigator.pop。
      _splitController.paneVisible = false;
    }
  }

  /// 初始路由只压栈底 base 占位一条（绕开 Navigator 对 '/' 开头
  /// initialRoute 的 deep-link 拆段行为）。
  List<Route<dynamic>> _buildInitialRoutes(
    NavigatorState navigator,
    String initialRoute,
  ) {
    return <Route<dynamic>>[
      _generateRoute(const RouteSettings(name: baseRouteName))!,
    ];
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    final name = settings.name ?? baseRouteName;
    if (name == baseRouteName) {
      return AppTransitions.paneCardRoute<void>(
        const _PaneBasePlaceholder(),
        settings: settings,
        animate: false,
      );
    }
    final custom = widget.onGenerateRoute;
    if (custom != null) {
      final route = custom(settings);
      if (route != null) return route;
    }
    return AppTransitions.paneCardRoute<void>(
      buildDetailRouteChild(name, isActiveRoute: true),
      settings: settings,
      // 第一层由 Shell 统一转场，避免页面淡出后副屏才开始收起。
      animate: _routeStack.length > 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = paneRoutePath(currentRouteName ?? baseRouteName);
    final settingsPane =
        path == '/screen/settings' || path.startsWith('/screen/settings/');
    final navigator = ColoredBox(
      color: settingsPane ? Colors.transparent : context.appColors.surface,
      child: Navigator(
        key: _navigatorKey,
        initialRoute: baseRouteName,
        onGenerateInitialRoutes: _buildInitialRoutes,
        onGenerateRoute: _generateRoute,
        onUnknownRoute: _generateRoute,
        observers: <NavigatorObserver>[_routeObserver],
      ),
    );
    return PlayerPaneHostScope(
      controller: this,
      child: LayoutBuilder(
        builder: (context, constraints) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(size: Size(constraints.maxWidth, constraints.maxHeight)),
          // 副屏与设置首页是兄弟节点，须在导航器外共享整窗背景，
          // 使后续压入的设置子页也继承卡片材质和控件配色。
          child: settingsPane
              ? AppAmbientPage(shareBackground: true, child: navigator)
              : navigator,
        ),
      ),
    );
  }
}

/// 栈底占位：尚未打开任何详情时的空态。
class _PaneBasePlaceholder extends StatelessWidget {
  const _PaneBasePlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined, size: 44, color: colors.textMuted),
          const SizedBox(height: 12),
          Text(
            '选择内容查看详情',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '在浏览区点击海报或卡片，详情将在这里打开',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 同步内嵌 Navigator 与镜像路由栈：pop / remove / replace 时移除对应条目。
/// push 侧由 openRoute 同步写入，这里只处理移除方向。
class _PaneRouteSyncObserver extends NavigatorObserver {
  _PaneRouteSyncObserver(this.onRouteRemoved);

  final void Function(Route<Object?> route) onRouteRemoved;

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {
    onRouteRemoved(route);
  }

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) {
    onRouteRemoved(route);
  }

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    // 搜索直达以同名选项页替换入口页时，副屏目标和栈深均未改变。
    if (newRoute != null && newRoute.settings.name == oldRoute?.settings.name) {
      return;
    }
    final old = oldRoute;
    if (old != null) onRouteRemoved(old);
  }
}
