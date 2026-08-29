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
import 'desktop_breakpoints.dart';
import 'desktop_split_controller.dart';
import 'desktop_tokens.dart';

/// 桌面「浏览 | 详情」分屏的详情宿主。
///
/// 提供 Flutter 侧 [PlayerPaneHostScope] + [PlayerPaneHostController] 实现，
/// 让 `EmbeddedDetailLauncher` 在 pane 存在时完全走 Flutter 侧 pane 通道
/// （openRoute/backInPane/closePane），不再触碰 Android 平台通道。
///
/// ## 主干 Shell 接线（合并时执行，一行）
/// ```dart
/// controller.paneHostBuilder =
///     (context) => DesktopDetailPaneHost(splitController: controller);
/// ```
/// Shell 侧最小改动：在 `DesktopBreakpoints.splitMinWidth` 且
/// `controller.enabled` 时读取 `controller.paneHostBuilder` 渲染右栏
/// （未接线时保持现有占位逻辑）；宿主随 `enabled` 挂载/卸载即可，
/// 无需其他生命周期管理。
///
/// ## 语义约定
/// - **openRoute**：向内嵌 Navigator push 命名路由；映射与
///   `detail_host_screen` / `main.dart` 一致（提取自
///   `lib/ui/detail_route_builder.dart`），详情类路由固定以
///   `DetailPresentation.pane` 构建。栈顶同目标（详情按 guid 判定）直接
///   视为成功不重复压栈；同路径不同目标替换栈顶（与 Android 副栏一致，
///   如 `/detail/item?itemGuid=A` → `/detail/item?itemGuid=B`）；其余压栈。
///   `AsyncActionGuard` 以目标键防抖（320ms settle），连点同一海报只开一次。
/// - **backInPane**：内嵌 Navigator maybePop；已在栈底（base 占位）返回
///   false，由外层决定收起分屏。
/// - **closePane**：清空 pane 路由栈并置 `splitController.enabled = false`
///   （收起分屏右栏）。开关由 `DesktopSplitController.enabled` 单一表达，
///   Shell 监听后卸载本宿主；再次打开时宿主以空栈重建。
/// - **replacePlayerSource**：桌面播放内核未选型（见
///   design/desktop/IMPLEMENTATION_PLAN.md），恒返回 false，不承载播放。
class DesktopDetailPaneHost extends StatefulWidget {
  const DesktopDetailPaneHost({
    super.key,
    this.splitController,
    this.onGenerateRoute,
  });

  /// 共享的分屏控制器（正式接线时由桌面 Shell 传入）。
  /// 传 null 时内部自建，便于独立使用与测试。
  final DesktopSplitController? splitController;

  /// 自定义路由工厂（测试注入极简映射用）；缺省使用
  /// `buildDetailRouteChild` 的统一映射。
  final RouteFactory? onGenerateRoute;

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
    // 关闭语义：收起分屏右栏（单一开关 DesktopSplitController.enabled）。
    // Shell 监听该开关卸载本宿主；重新打开时以空栈重建。
    _splitController.enabled = false;
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlayerPaneHostScope(
      controller: this,
      child: ListenableBuilder(
        listenable: _splitController,
        builder: (context, _) {
          final colors = context.appColors;
          return LayoutBuilder(
            builder: (context, constraints) {
              final tooNarrow =
                  constraints.maxWidth < DesktopBreakpoints.paneMinWidth;
              return Column(
                children: [
                  _buildToolbar(colors),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Navigator 常驻（过窄时仅被提示层遮盖），
                        // 保证镜像栈与导航栈状态始终一致。
                        ColoredBox(
                          color: colors.surface,
                          child: Navigator(
                            key: _navigatorKey,
                            initialRoute: baseRouteName,
                            // initialRoute 以 '/' 开头会被 Navigator 按
                            // deep-link 拆段展开，这里显式只压栈底一条。
                            onGenerateInitialRoutes: _buildInitialRoutes,
                            onGenerateRoute: _generateRoute,
                            onUnknownRoute: _generateRoute,
                            observers: <NavigatorObserver>[_routeObserver],
                          ),
                        ),
                        if (tooNarrow) _PaneTooNarrowHint(colors: colors),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildToolbar(AppThemeColors colors) {
    final current = currentRouteName;
    final canGoBack = current != null;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: canGoBack ? '返回' : '关闭',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              canGoBack ? Icons.arrow_back_rounded : Icons.close_rounded,
              size: 20,
              color: colors.textSecondary,
            ),
            onPressed: () async {
              if (await backInPane()) return;
              // 栈底时返回按钮变为关闭语义。
              await closePane();
            },
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              current == null ? '详情' : _routeTitle(current),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildFractionChips(colors),
          IconButton(
            tooltip: '关闭',
            key: const ValueKey<String>('desktop_pane_close'),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: colors.textSecondary,
            ),
            onPressed: () => closePane(),
          ),
        ],
      ),
    );
  }

  /// 比例预设 chip 组：选中项 accent 描边，点击写回
  /// [DesktopSplitController.setPaneFraction]。
  Widget _buildFractionChips(AppThemeColors colors) {
    final currentFraction = _splitController.paneFraction;
    final children = <Widget>[];
    for (final preset in DesktopSplitController.paneFractionPresets) {
      final selected = (currentFraction - preset).abs() < 0.001;
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: 6));
      }
      children.add(
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _splitController.setPaneFraction(preset),
            child: AnimatedContainer(
              duration: DesktopTokens.hoverDuration,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: selected ? colors.accentSoft : Colors.transparent,
                border: Border.all(
                  color: selected ? colors.accent : colors.borderSubtle,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Text(
                '${(preset * 100).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  color: selected ? colors.accentStrong : colors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  /// 标题显示当前栈顶路由的尾段（拿不到页面标题时按路由名兜底）。
  String _routeTitle(String routeName) {
    final uri = Uri.tryParse(routeName.trim());
    final path = uri?.path ?? routeName;
    final segments = path
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return path.trim().isEmpty ? routeName : path;
    }
    return segments.last;
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

/// 宽度低于 [DesktopBreakpoints.paneMinWidth] 时的过窄提示层。
class _PaneTooNarrowHint extends StatelessWidget {
  const _PaneTooNarrowHint({required this.colors});

  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.width_normal_rounded,
                size: 40,
                color: colors.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                '窗口过窄，无法展示详情栏',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '请加宽窗口，详情栏至少需要 '
                '${DesktopBreakpoints.paneMinWidth.round()} 逻辑像素宽度',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
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
    final old = oldRoute;
    if (old != null) onRouteRemoved(old);
  }
}
