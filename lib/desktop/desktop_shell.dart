import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../media_backend/media_catalog.dart';
import '../models/media_item.dart';
import '../models/play_info.dart';
import '../playback/playback_source.dart';
import '../providers/media_backend_provider.dart';
import '../providers/parallel_window_settings_provider.dart';
import '../screens/app_settings_screen.dart';
import '../screens/media_list_screen.dart';
import '../services/play_stats/play_stats_models.dart';
import '../theme/app_theme.dart';
import '../ui/player_pane_host_scope.dart';
import 'desktop_detail_pane_host.dart';
import 'desktop_hover_region.dart';
import 'desktop_side_bar.dart';
import 'desktop_split_controller.dart';

/// 桌面侧栏 Shell：左侧 [DesktopSideBar] + 右侧主导航两页（与
/// MainNavigation 的底部胶囊路径复用同一组页面），宽窗口下替代底部导航。
///
/// 分屏「浏览 | 详情」状态经 [ChangeNotifierProvider] 注入
/// [DesktopSplitController]；开启分屏后右栏由 [DesktopDetailPaneHost]
/// 承载（经 [DesktopSplitController.paneHostBuilder] 接线）。
class DesktopShell extends StatefulWidget {
  const DesktopShell({
    super.key,
    this.initialTab = 0,
    this.pages,
    this.paneRouteFactory,
    required this.contentRouteFactory,
  });

  /// 初始主导航页签序号（0=影视、1=设置，与 MainPrimaryTab.tabIndex 对齐）。
  final int initialTab;

  /// 主导航两页内容；生产环境固定复用 [MediaListScreen] / [AppSettingsScreen]
  /// （与 MainNavigation 的 IndexedStack 相同）。IndexedStack 会同时构建两页，
  /// 测试可注入轻量替身避免拉起完整 provider 栈。
  final List<Widget>? pages;

  /// 分屏右栏路由工厂（测试注入轻量替身用）；缺省用宿主统一映射。
  final RouteFactory? paneRouteFactory;

  /// 影视页签内容区内嵌导航的路由工厂：侧栏 / 首页的二级页
  /// （媒体库、分类、搜索、收藏、下载）在此导航器打开，左侧栏常驻。
  /// 生产环境传 App 根路由表（main.buildAppRoute 同源的 `_buildRoute`）。
  final RouteFactory contentRouteFactory;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  // 接线分屏详情宿主（feat/desktop-detail-pane）：开启分屏后右栏由
  // DesktopDetailPaneHost 承载。开关在「设置 → 分屏窗口」（与安卓一致），
  // 壳层监听 ParallelWindowSettingsProvider 同步 enabled。
  late final DesktopSplitController _splitController = DesktopSplitController()
    ..paneHostBuilder = _buildPaneHost;

  /// 全局 pane host 代理：宿主就绪后注入，让首页等
  /// pane 槽位之外的入口也能把详情打开到右栏；分屏未开启时回退内容区。
  /// late 初始化以便引用实例方法 [_openPaneRouteFallback]。
  late final _DesktopPaneHostProxy _paneHostProxy = _DesktopPaneHostProxy(
    openFallback: _openPaneRouteFallback,
  );

  /// 影视页签内容区内嵌导航：侧栏二级页在此打开，侧栏永远可见。
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();

  ParallelWindowSettingsProvider? _parallelSettings;

  late final FocusNode _shellFocusNode = FocusNode(
    debugLabel: 'desktop-shell-shortcuts',
  );

  /// 侧栏「媒体库 / 分类」分组数据（经 MediaBackend 公共接口拉取，失败静默降级）。
  List<MediaCatalog> _sidebarCatalogs = const <MediaCatalog>[];
  int _sidebarTotal = 0;
  int _sidebarMovie = 0;
  int _sidebarTv = 0;
  int _sidebarFavorite = 0;
  int _sidebarOther = 0;
  bool _sidebarDataLoaded = false;

  late int _selectedTab = widget.initialTab;

  Widget _buildPaneHost(BuildContext context) => DesktopDetailPaneHost(
    splitController: _splitController,
    onGenerateRoute: widget.paneRouteFactory,
    onHostReady: (controller) => _paneHostProxy.attach(controller),
  );

  @override
  void initState() {
    super.initState();
    try {
      _parallelSettings = context.read<ParallelWindowSettingsProvider>();
    } catch (_) {
      // 测试环境可能未注入：分屏保持默认关闭。
    }
    // 初始同步 + 监听设置变化（双向：设置页开关 ↔ 分屏控制器，
    // 右栏关闭按钮经控制器回写设置）。
    final parallel = _parallelSettings;
    if (parallel != null) {
      _splitController.enabled = parallel.enabled;
      parallel.addListener(_onParallelSettingsChanged);
    }
    _splitController.addListener(_onSplitControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSidebarCatalogData();
    });
  }

  @override
  void dispose() {
    _shellFocusNode.dispose();
    _parallelSettings?.removeListener(_onParallelSettingsChanged);
    _splitController.removeListener(_onSplitControllerChanged);
    _splitController.dispose();
    super.dispose();
  }

  void _onParallelSettingsChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final parallel = _parallelSettings;
      if (parallel != null && _splitController.enabled != parallel.enabled) {
        _splitController.enabled = parallel.enabled;
      }
    });
  }

  void _onSplitControllerChanged() {
    final parallel = _parallelSettings;
    if (parallel != null && parallel.enabled != _splitController.enabled) {
      unawaited(parallel.setEnabled(_splitController.enabled));
    }
  }

  Future<void> _loadSidebarCatalogData() async {
    if (_sidebarDataLoaded) return;
    try {
      final backend = context.read<MediaBackendProvider>().backend;
      final results = await Future.wait(<Future<Object?>>[
        backend.getCatalogs(),
        backend.getHomeSummary(),
      ]);
      if (!mounted) return;
      final summary = results[1] as Map<String, dynamic>;
      setState(() {
        _sidebarCatalogs = results[0] as List<MediaCatalog>;
        _sidebarTotal = _summaryIntOf(summary, 'total');
        _sidebarMovie = _summaryIntOf(summary, 'movie');
        _sidebarTv = _summaryIntOf(summary, 'tv');
        _sidebarFavorite = _summaryIntOf(summary, 'favorite');
        _sidebarOther = _summaryIntOf(summary, 'other');
        _sidebarDataLoaded = true;
      });
    } catch (_) {
      // 测试环境 / 未连接 / 后端不支持：侧栏分组静默降级为无计数。
    }
  }

  static int _summaryIntOf(Map<String, dynamic> summary, String key) {
    final value = summary[key];
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  // ---------------------------------------------------------------------------
  // 侧栏二级页：全部推入影视页签内容区内嵌导航（侧栏常驻，与分屏无关）。
  // ---------------------------------------------------------------------------

  void _openContentRoute(String routeName) {
    final navigator = _contentNavKey.currentState;
    if (navigator == null) return;
    _selectTab(0);
    unawaited(
      navigator
          .pushNamedAndRemoveUntil(routeName, (route) => route.isFirst)
          .catchError((Object _) => null),
    );
  }

  void _openContentHome() {
    _contentNavKey.currentState?.popUntil((route) => route.isFirst);
    _selectTab(0);
  }

  /// 分屏关闭（或右栏拒收）时 EmbeddedDetailLauncher / AdaptiveDetailNavigator
  /// 的统一回退：详情与二级页推进影视页签内容区内嵌导航器，侧栏常驻、
  /// 不整窗覆盖。设置类路由例外——切到设置页签（内容区里不再嵌整套
  /// MainNavigation），与安卓经 MainHostBridge 切主 tab 的行为对齐。
  Future<bool> _openPaneRouteFallback(String routeName) async {
    final navigator = _contentNavKey.currentState;
    if (navigator == null) return false;
    final path = Uri.tryParse(routeName)?.path ?? '';
    if (path == '/screen/settings' || path.startsWith('/screen/settings/')) {
      _selectTab(1);
      return true;
    }
    unawaited(navigator.pushNamed(routeName).catchError((Object _) => null));
    return true;
  }

  void _openSidebarCategory(
    BuildContext context, {
    required String name,
    List<String>? typeTags,
  }) {
    _openContentRoute(
      Uri(
        path: '/screen/category',
        queryParameters: <String, String>{
          'category': jsonEncode(MediaItem(id: '', name: name).toJson()),
          if (typeTags != null && typeTags.isNotEmpty)
            'types': jsonEncode(typeTags),
        },
      ).toString(),
    );
  }

  void _openSidebarCatalog(BuildContext context, MediaCatalog catalog) {
    _openContentRoute(
      Uri(
        path: '/screen/category',
        queryParameters: <String, String>{
          'category': jsonEncode(
            MediaItem(
              id: catalog.id,
              name: catalog.title,
              type: catalog.type,
              path: catalog.primaryImage.url,
              posters: catalog.posters
                  .map((image) => image.url)
                  .toList(growable: false),
            ).toJson(),
          ),
        },
      ).toString(),
    );
  }

  @override
  void didUpdateWidget(covariant DesktopShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（如 MainHostBridge）切换 tab 时同步到 Shell 内部状态。
    final nextTab = widget.initialTab;
    if (nextTab != oldWidget.initialTab &&
        nextTab >= 0 &&
        nextTab <= 1 &&
        nextTab != _selectedTab) {
      _selectedTab = nextTab;
    }
  }

  void _selectTab(int index) {
    if (index < 0 || index > 1 || index == _selectedTab) return;
    setState(() => _selectedTab = index);
    // IndexedStack 切页后焦点可能落在被隐藏的内容导航子树中失效，
    // 主动把焦点拉回 Shell 快捷键域，保证数字键 / Esc 连续可用。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shellFocusNode.requestFocus();
    });
  }

  void _openSearch() {
    _openContentRoute('/screen/search');
  }

  Future<void> _escape() async {
    // 优先退出内容区二级页（侧栏常驻），栈底再回退 root（如全屏大屏浏览）。
    final content = _contentNavKey.currentState;
    if (content != null && content.canPop()) {
      content.pop();
      return;
    }
    await Navigator.of(context, rootNavigator: true).maybePop();
  }

  /// 主焦点位于文本输入（EditableText / TextField）内时，数字与 Esc 快捷键让路，
  /// 不劫持输入；Ctrl+K 组合键不受影响。
  bool get _isEditingTextActive {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dividerColor = colors.borderSubtle;

    return ChangeNotifierProvider<DesktopSplitController>.value(
      value: _splitController,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _DesktopOpenSearchIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _DesktopEscapeIntent(),
          SingleActivator(LogicalKeyboardKey.digit1): _DesktopTabIntent(0),
          SingleActivator(LogicalKeyboardKey.numpad1): _DesktopTabIntent(0),
          SingleActivator(LogicalKeyboardKey.digit2): _DesktopTabIntent(1),
          SingleActivator(LogicalKeyboardKey.numpad2): _DesktopTabIntent(1),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _DesktopOpenSearchIntent:
                _DesktopShortcutAction<_DesktopOpenSearchIntent>(
                  onInvoke: (_) => _openSearch(),
                ),
            _DesktopEscapeIntent: _DesktopShortcutAction<_DesktopEscapeIntent>(
              enabledWhen: (_) => !_isEditingTextActive,
              onInvoke: (_) => unawaited(_escape()),
            ),
            _DesktopTabIntent: _DesktopShortcutAction<_DesktopTabIntent>(
              enabledWhen: (_) => !_isEditingTextActive,
              onInvoke: (intent) => _selectTab(intent.tabIndex),
            ),
          },
          // autofocus 兜底：Shell 内无可聚焦控件时也保证按键事件进入本快捷键域。
          child: Focus(
            focusNode: _shellFocusNode,
            autofocus: true,
            skipTraversal: true,
            // 全局 pane host 作用域：覆盖侧栏与浏览区，
            // 详情页可在右栏打开（分屏由设置页控制）。
            child: PlayerPaneHostScope(
              controller: _paneHostProxy,
              // 壳层自绘主题底色：侧栏与各页签间隙不再透出窗口黑底，
              // 亮色主题下侧栏随之变白（此前深色主题恰好看不出差异）。
              child: ColoredBox(
                color: colors.backgroundBase,
                // 指针位置采集：DesktopHoverRegion 悬停自愈校验依赖真实指针位置
                // （指针静止而内容移动时 MouseRegion exit 不派发）。
                child: DesktopPointerPositionTracker(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      DesktopSideBar(
                        selectedTabIndex: _selectedTab,
                        onTabSelected: (index) {
                          if (index == 0) {
                            _openContentHome();
                          } else {
                            _selectTab(index);
                          }
                        },
                        catalogs: _sidebarCatalogs,
                        favoriteCount: _sidebarFavorite,
                        totalItems: _sidebarTotal,
                        movieCount: _sidebarMovie,
                        tvCount: _sidebarTv,
                        otherCount: _sidebarOther,
                        onOpenSearch: (context) =>
                            _openContentRoute('/screen/search'),
                        onOpenFavorites: (context) =>
                            _openContentRoute('/screen/favorites'),
                        onOpenDownloads: (context) =>
                            _openContentRoute('/screen/downloads'),
                        onOpenCatalog: (context, catalog) =>
                            _openSidebarCatalog(context, catalog),
                        onOpenAllItems: (context) => _openSidebarCategory(
                          context,
                          name: AppLocalizations.of(context).mediaAllItemsTitle,
                        ),
                        onOpenByType: (context, name, typeTags) =>
                            _openSidebarCategory(
                              context,
                              name: name,
                              typeTags: typeTags,
                            ),
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: dividerColor,
                      ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: _splitController,
                          builder: (context, _) {
                            if (!_splitController.enabled) {
                              return _buildTabStack();
                            }
                            // paneFraction 为详情栏（右栏）宽度占比，按 flex 换算。
                            final paneFlex =
                                (_splitController.paneFraction * 100).round();
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Expanded(
                                  flex: 100 - paneFlex,
                                  child: _buildTabStack(),
                                ),
                                VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: dividerColor,
                                ),
                                Expanded(
                                  flex: paneFlex,
                                  child: _buildDetailPane(context),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 主导航两页（影视内容区 + 设置）的保活切换容器。
  /// 影视页签包一层内嵌导航：侧栏二级页在此打开，侧栏永远可见。
  Widget _buildTabStack() {
    final pages =
        widget.pages ?? const <Widget>[MediaListScreen(), AppSettingsScreen()];
    return LayoutBuilder(
      builder: (context, constraints) {
        // 内容区实际宽度 ≠ 整窗宽度（左侧栏与分屏右栏都在挤占）：在这里按
        // 真实可用尺寸覆写 MediaQuery，页内 MediaLayoutProfile / 桌面断点
        // 才会按渲染宽度取密度；否则海报卡按整窗宽算列数与图高，
        // 在窄区里被压窄拉高、比例失真。
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
          child: IndexedStack(
            index: _selectedTab,
            children: <Widget>[
              Navigator(
                key: _contentNavKey,
                onGenerateInitialRoutes: (navigator, initialRoute) =>
                    <Route<dynamic>>[
                      PageRouteBuilder<void>(
                        settings: const RouteSettings(name: '/content-home'),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                        pageBuilder: (_, __, ___) => pages.first,
                      ),
                    ],
                onGenerateRoute: widget.contentRouteFactory,
                onUnknownRoute: widget.contentRouteFactory,
              ),
              if (pages.length > 1) pages[1] else const SizedBox.shrink(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailPane(BuildContext context) {
    final hostBuilder = _splitController.paneHostBuilder;
    if (hostBuilder != null) return hostBuilder(context);
    return _DesktopPanePlaceholder(controller: _splitController);
  }
}

/// [PlayerPaneHostController] 的空安全代理：宿主就绪（分屏开启）时转发右栏；
/// 未挂载或右栏拒收时经 [openFallback] 回退到影视页签内容区内嵌导航器，
/// 让首页入口 / 媒体库条目在无分屏时也能打开（侧栏常驻，不整窗覆盖）。
/// backInPane / closePane / replacePlayerSource 不回退——它们是右栏专属操作。
class _DesktopPaneHostProxy implements PlayerPaneHostController {
  _DesktopPaneHostProxy({required this.openFallback});

  /// 分屏右栏不可用时的路由回退（由 Shell 注入，指向内容区导航器）。
  final Future<bool> Function(String routeName) openFallback;

  PlayerPaneHostController? _inner;

  void attach(PlayerPaneHostController? controller) {
    _inner = controller;
  }

  @override
  Future<bool> openRoute(String routeName) async {
    final inner = _inner;
    if (inner != null && await inner.openRoute(routeName)) {
      return true;
    }
    return openFallback(routeName);
  }

  @override
  Future<bool> backInPane() async => _inner?.backInPane() ?? false;

  @override
  Future<bool> closePane() async => _inner?.closePane() ?? false;

  @override
  Future<bool> replacePlayerSource({
    required String title,
    required MpvMediaSource source,
    PlayInfoData? initialPlayInfo,
    PlayStartSource startSource = PlayStartSource.manual,
  }) async =>
      _inner?.replacePlayerSource(
        title: title,
        source: source,
        initialPlayInfo: initialPlayInfo,
        startSource: startSource,
      ) ??
      false;
}

class _DesktopOpenSearchIntent extends Intent {
  const _DesktopOpenSearchIntent();
}

class _DesktopEscapeIntent extends Intent {
  const _DesktopEscapeIntent();
}

class _DesktopTabIntent extends Intent {
  const _DesktopTabIntent(this.tabIndex);

  final int tabIndex;
}

/// 带动态启用条件的快捷键 Action：disabled 时 Shortcuts 返回 ignored，
/// 按键继续冒泡（文本框内数字/Esc 不被吞掉）。
class _DesktopShortcutAction<T extends Intent> extends Action<T> {
  _DesktopShortcutAction({required this.onInvoke, this.enabledWhen});

  final void Function(T intent) onInvoke;
  final bool Function(T intent)? enabledWhen;

  @override
  bool isEnabled(T intent) => enabledWhen?.call(intent) ?? true;

  @override
  Object? invoke(T intent) {
    onInvoke(intent);
    return null;
  }
}

/// 分屏详情宿主未接线（desktop-detail-pane 未合入）时的右栏占位：
/// 居中提示 + 比例预设 chip + 关闭分屏按钮。
class _DesktopPanePlaceholder extends StatelessWidget {
  const _DesktopPanePlaceholder({required this.controller});

  final DesktopSplitController controller;

  // 分屏详情宿主尚未接入的占位文案，无对应 l10n key（接入后随宿主一并移除）。
  static const String _placeholderMessage = '分屏详情宿主待接入（desktop-detail-pane）';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return ColoredBox(
          color: colors.surface,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.view_sidebar_outlined,
                  size: 40,
                  color: colors.textMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  _placeholderMessage,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                Material(
                  type: MaterialType.transparency,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final fraction
                          in DesktopSplitController
                              .paneFractionPresets) ...<Widget>[
                        _PaneFractionChip(
                          fraction: fraction,
                          selected:
                              (controller.paneFraction - fraction).abs() <
                              0.001,
                          onTap: () => controller.setPaneFraction(fraction),
                        ),
                        if (fraction !=
                            DesktopSplitController.paneFractionPresets.last)
                          const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                IconButton(
                  key: const ValueKey<String>('desktop_pane_close'),
                  tooltip: l10n.commonClose,
                  onPressed: () => controller.enabled = false,
                  icon: const Icon(Icons.close),
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PaneFractionChip extends StatelessWidget {
  const _PaneFractionChip({
    required this.fraction,
    required this.selected,
    required this.onTap,
  });

  final double fraction;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.selectionSoft : colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? colors.selection : colors.chipBorder,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          '${(fraction * 100).round()}%',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: selected ? colors.textPrimary : colors.textSecondary,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
