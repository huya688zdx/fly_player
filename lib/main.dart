import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'danmaku/settings/danmaku_saved_source_store.dart';
import 'desktop/desktop_breakpoints.dart';
import 'desktop/desktop_environment.dart';
import 'desktop/desktop_shell.dart';
import 'l10n/generated/app_localizations.dart';
import 'models/media_item.dart';
import 'models/media_library_item.dart';
import 'providers/app_locale_provider.dart';
import 'providers/app_theme_provider.dart';
import 'media_backend/media_backend_kind.dart';
import 'providers/backend_session_provider.dart';
import 'providers/media_backend_provider.dart';
import 'providers/nas_provider.dart';
import 'providers/parallel_window_settings_provider.dart';
import 'providers/startup_preferences_provider.dart';
import 'screens/app_settings_screen.dart';
import 'screens/category_items_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/detail_host_screen.dart';
import 'screens/detail_route_bodies.dart';
import 'screens/download_list_screen.dart';
import 'screens/favorite_items_screen.dart';
import 'screens/media_list_screen.dart';
import 'screens/parallel_placeholder_screen.dart';
import 'screens/person_detail_screen.dart';
import 'screens/poster_browse/poster_browse_screen.dart';
import 'screens/search_screen.dart';
import 'screens/screenshot_preview_screen.dart';
import 'services/app_log_service.dart';
import 'services/detail_route_payload_store.dart';
import 'services/gpu_profile_bridge.dart';
import 'services/main_host_bridge.dart';
import 'screens/settings_destination_routes.dart';
import 'theme/app_theme.dart';
import 'theme/dynamic_theme_runtime_controller.dart';
import 'theme/dynamic_theme_seed_extractor.dart';
import 'ui/adaptive_text.dart';
import 'ui/app_transitions.dart';
import 'ui/media_poster_card.dart';
import 'ui/main_navigation_metrics.dart';
import 'ui/route_transition_gate.dart';
import 'utils/private_network_http_overrides.dart';
import 'utils/route_query_json.dart';
import 'utils/app_exception.dart';
import 'widgets/common/app_error_state.dart';
import 'widgets/startup_destination_gate.dart';
import 'package:fly_player/widgets/common/bird_loader.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Phase 4.3：默认 ImageCache 上限 100MB 偏小——详情页 hero 背景最高 1440px
      // (单张解码后 ~4-5MB) 叠加首页海报墙，进出详情/滚动时 hero 反复被驱逐再 decode。
      // 提到 256MB 给足缓存余量，减少重复解码尖峰。注意真机需核内存占用。
      PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20; // 256MB
      await AppLogService.instance.initialize();
      _FrameTimingLogger.install();
      // 启动即把遗留在 SharedPreferences 的大 blob 迁出，使 prefs map 从一开始就干净
      // （否则弹幕源 70KB 要等首次进播放器才懒迁移，期间主题轮询 reload 仍解码它）。
      unawaited(const DanmakuSavedSourceStore().ensureMigratedFromPrefs());
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('[APP][FLUTTER_ERROR] ${details.exceptionAsString()}');
        AppLogService.instance.recordFlutterErrorSync(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('[APP][PLATFORM_ERROR] $error');
        AppLogService.instance.recordErrorSync(
          error: error,
          stackTrace: stack,
          source: 'platform',
        );
        return true;
      };
      HttpOverrides.global = PrivateNetworkHttpOverrides();
      await DynamicThemeSeedExtractor.warmUpPersistentCache();
      await DynamicThemeRuntimeController.instance.warmUpPersistentCache();
      // 预热海报卡 SVG 角标/徽章，削平首屏滚动时的解析尖峰（不阻塞启动）。
      unawaited(MediaPosterCard.precacheBadgeIcons());
      ErrorWidget.builder = (_) {
        return Material(
          color: AppThemePalette.fallback.backgroundBase,
          child: const _GlobalErrorFallback(),
        );
      };
      runApp(const FlyPlayerApp());
    },
    (error, stack) {
      debugPrint('[APP][ZONE_ERROR] $error');
      AppLogService.instance.recordErrorSync(
        error: error,
        stackTrace: stack,
        source: 'zone',
      );
    },
  );
}

class _FrameTimingLogger {
  _FrameTimingLogger._();

  static const int _summaryFrameCount = 120;
  static const int _windowFrameCount = 90;
  static const int _slowFrameMicros = 16667;
  static const int _jankyFrameMicros = 33333;
  static bool _installed = false;
  static int _frames = 0;
  static int _slowFrames = 0;
  static int _jankyFrames = 0;
  static int _buildMicros = 0;
  static int _rasterMicros = 0;
  static int _totalMicros = 0;
  static int _maxTotalMicros = 0;
  static int _maxBuildMicros = 0;
  static int _maxRasterMicros = 0;
  // 窗口标记：markWindow(label) 之后单独汇总接下来 _windowFrameCount 帧，
  // 用于把某次路由 push/pop 的转场窗口从滚动统计里切出来对比（Phase 0 基线工具）。
  static String? _windowLabel;
  static int _windowFrames = 0;
  static int _windowSlowFrames = 0;
  static int _windowJankyFrames = 0;
  static int _windowBuildMicros = 0;
  static int _windowRasterMicros = 0;
  static int _windowTotalMicros = 0;
  static int _windowMaxTotalMicros = 0;
  static int _windowMaxBuildMicros = 0;
  static int _windowMaxRasterMicros = 0;
  static final String _source = _resolveSource();

  static void install() {
    if (_installed || kReleaseMode) {
      return;
    }
    _installed = true;
    WidgetsBinding.instance.addTimingsCallback(_handleTimings);
    debugPrint('[PERF][FRAME][$_source] timings enabled');
  }

  /// 标记一个测量窗口：此后 [_windowFrameCount] 帧单独汇总，输出
  /// `[PERF][FRAME][WINDOW][label]`。若上一个窗口尚未填满即被新标记覆盖，
  /// 先把已采集的部分 flush 掉再开新窗口。
  static void markWindow(String label) {
    if (!_installed || kReleaseMode) {
      return;
    }
    if (_windowLabel != null && _windowFrames > 0) {
      _flushWindowSummary();
    }
    _windowLabel = label;
    _windowFrames = 0;
    _windowSlowFrames = 0;
    _windowJankyFrames = 0;
    _windowBuildMicros = 0;
    _windowRasterMicros = 0;
    _windowTotalMicros = 0;
    _windowMaxTotalMicros = 0;
    _windowMaxBuildMicros = 0;
    _windowMaxRasterMicros = 0;
  }

  static void _handleTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final buildMicros = timing.buildDuration.inMicroseconds;
      final rasterMicros = timing.rasterDuration.inMicroseconds;
      final totalMicros = timing.totalSpan.inMicroseconds;
      _frames++;
      _buildMicros += buildMicros;
      _rasterMicros += rasterMicros;
      _totalMicros += totalMicros;
      if (totalMicros > _maxTotalMicros) {
        _maxTotalMicros = totalMicros;
      }
      if (buildMicros > _maxBuildMicros) {
        _maxBuildMicros = buildMicros;
      }
      if (rasterMicros > _maxRasterMicros) {
        _maxRasterMicros = rasterMicros;
      }
      if (totalMicros > _slowFrameMicros) {
        _slowFrames++;
      }
      if (totalMicros > _jankyFrameMicros) {
        _jankyFrames++;
        debugPrint(
          '[PERF][FRAME][$_source] jank total=${_ms(totalMicros)} build=${_ms(buildMicros)} raster=${_ms(rasterMicros)}',
        );
      }
      if (_windowLabel != null) {
        _windowFrames++;
        _windowBuildMicros += buildMicros;
        _windowRasterMicros += rasterMicros;
        _windowTotalMicros += totalMicros;
        if (totalMicros > _windowMaxTotalMicros) {
          _windowMaxTotalMicros = totalMicros;
        }
        if (buildMicros > _windowMaxBuildMicros) {
          _windowMaxBuildMicros = buildMicros;
        }
        if (rasterMicros > _windowMaxRasterMicros) {
          _windowMaxRasterMicros = rasterMicros;
        }
        if (totalMicros > _slowFrameMicros) {
          _windowSlowFrames++;
        }
        if (totalMicros > _jankyFrameMicros) {
          _windowJankyFrames++;
        }
        if (_windowFrames >= _windowFrameCount) {
          _flushWindowSummary();
        }
      }
      if (_frames >= _summaryFrameCount) {
        _flushSummary();
      }
    }
  }

  static void _flushWindowSummary() {
    final label = _windowLabel;
    if (label == null || _windowFrames == 0) {
      _windowLabel = null;
      return;
    }
    final avgBuild = _windowBuildMicros / _windowFrames;
    final avgRaster = _windowRasterMicros / _windowFrames;
    final avgTotal = _windowTotalMicros / _windowFrames;
    debugPrint(
      '[PERF][FRAME][WINDOW][$label] frames=$_windowFrames '
      'slow60=$_windowSlowFrames jank30=$_windowJankyFrames '
      'avgBuild=${_ms(avgBuild)} maxBuild=${_ms(_windowMaxBuildMicros)} '
      'avgRaster=${_ms(avgRaster)} maxRaster=${_ms(_windowMaxRasterMicros)} '
      'avgTotal=${_ms(avgTotal)} maxTotal=${_ms(_windowMaxTotalMicros)}',
    );
    _windowLabel = null;
  }

  static void _flushSummary() {
    if (_frames == 0) {
      return;
    }
    final avgBuild = _buildMicros / _frames;
    final avgRaster = _rasterMicros / _frames;
    final avgTotal = _totalMicros / _frames;
    final estimatedFps = avgTotal <= 0 ? 0 : 1000000 / avgTotal;
    debugPrint(
      '[PERF][FRAME][$_source] summary frames=$_frames slow60=$_slowFrames jank30=$_jankyFrames '
      'avgBuild=${_ms(avgBuild)} avgRaster=${_ms(avgRaster)} avgTotal=${_ms(avgTotal)} '
      'estFps=${estimatedFps.toStringAsFixed(1)} maxTotal=${_ms(_maxTotalMicros)} '
      'maxBuild=${_ms(_maxBuildMicros)} maxRaster=${_ms(_maxRasterMicros)}',
    );
    _frames = 0;
    _slowFrames = 0;
    _jankyFrames = 0;
    _buildMicros = 0;
    _rasterMicros = 0;
    _totalMicros = 0;
    _maxTotalMicros = 0;
    _maxBuildMicros = 0;
    _maxRasterMicros = 0;
  }

  static String _ms(num micros) => '${(micros / 1000).toStringAsFixed(1)}ms';

  static String _resolveSource() {
    final route = PlatformDispatcher.instance.defaultRouteName.trim();
    final normalizedRoute = route.isEmpty ? '/' : route;
    final uri = Uri.tryParse(normalizedRoute);
    final path = uri?.path ?? normalizedRoute;
    if (path == '/player') {
      return 'player route=$normalizedRoute';
    }
    if (path == '/parallel/placeholder') {
      return 'placeholder route=$normalizedRoute';
    }
    if (path == '/detail/host') {
      final childRoute = uri?.queryParameters['route']?.trim() ?? '';
      final childPath = Uri.tryParse(childRoute)?.path ?? childRoute;
      if (childPath == '/parallel/placeholder') {
        return 'placeholder route=$childRoute';
      }
      return 'detail route=${childRoute.isEmpty ? normalizedRoute : childRoute}';
    }
    if (path.startsWith('/detail/')) {
      return 'detail route=$normalizedRoute';
    }
    return 'main route=$normalizedRoute';
  }
}

/// 在路由 push/pop 时给 [_FrameTimingLogger] 打窗口标记，把转场期间的帧
/// 从滚动统计里单独切出来（Phase 0 基线工具，仅 debug 生效）。
class _PerfNavigatorObserver extends NavigatorObserver {
  _PerfNavigatorObserver();

  static String _label(Route<dynamic>? route) {
    final name = route?.settings.name?.trim();
    if (name == null || name.isEmpty) {
      return 'unknown';
    }
    final path = Uri.tryParse(name)?.path;
    return path == null || path.isEmpty ? name : path;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PageRoute) {
      _FrameTimingLogger.markWindow('push ${_label(route)}');
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute) {
      _FrameTimingLogger.markWindow(
        'pop ${_label(route)}->${_label(previousRoute)}',
      );
    }
  }
}

class _GlobalErrorFallback extends StatelessWidget {
  const _GlobalErrorFallback();

  @override
  Widget build(BuildContext context) {
    const colors = AppThemePalette.fallback;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, color: colors.danger, size: 52),
            const SizedBox(height: 16),
            Text(
              _maybeAppLocalizations(context)?.globalLoadFailed ??
                  lookupAppLocalizations(
                    const Locale('zh', 'CN'),
                  ).globalLoadFailed,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FlyPlayerApp extends StatelessWidget {
  const FlyPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NasProvider()),
        ChangeNotifierProvider(create: (_) => BackendSessionProvider()),
        ChangeNotifierProxyProvider2<
          NasProvider,
          BackendSessionProvider,
          MediaBackendProvider
        >(
          create: (context) => MediaBackendProvider(
            context.read<NasProvider>(),
            context.read<BackendSessionProvider>(),
          ),
          update: (context, nas, session, previous) =>
              previous ?? MediaBackendProvider(nas, session),
        ),
        ChangeNotifierProvider(create: (_) => ParallelWindowSettingsProvider()),
        ChangeNotifierProvider(create: (_) => StartupPreferencesProvider()),
        ChangeNotifierProvider(create: (_) => AppThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppLocaleProvider()),
      ],
      child: Selector<AppThemeProvider, String>(
        selector: (_, themeProvider) => themeProvider.materialThemeSignature,
        builder: (context, _, __) {
          final themeProvider = context.read<AppThemeProvider>();
          final materialThemeColors = themeProvider.selectedThemeBaseColors;
          return Consumer<AppLocaleProvider>(
            builder: (context, localeProvider, _) {
              return MaterialApp(
                title: '飞翔播放器',
                onGenerateTitle: (context) =>
                    AppLocalizations.of(context).appTitle,
                locale: localeProvider.locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppThemeBuilder.buildFromColors(materialThemeColors),
                navigatorObservers: _appNavigatorObservers,
                builder: (context, child) {
                  if (child == null) return const SizedBox.shrink();
                  final media = MediaQuery.of(context);
                  final scale = AdaptiveText.globalScale(media);
                  return AppRuntimeColorScopeBuilder(
                    controller: AppRuntimeColorController.instance,
                    child: MediaQuery(
                      data: media.copyWith(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: child,
                    ),
                  );
                },
                initialRoute: _initialRouteName(),
                onGenerateInitialRoutes: _buildInitialRoutes,
                onGenerateRoute: _buildRoute,
              );
            },
          );
        },
      ),
    );
  }
}

final List<NavigatorObserver> _appNavigatorObservers = <NavigatorObserver>[
  // 转场闸门：始终安装（含 release），它驱动 RouteTransitionGate 的全局转场标志。
  RouteTransitionGate.observer,
  // 帧率窗口标记：仅 debug。
  if (!kReleaseMode) _PerfNavigatorObserver(),
];

String _initialRouteName() {
  final route = PlatformDispatcher.instance.defaultRouteName.trim();
  return route.isEmpty ? '/' : route;
}

Route<dynamic> _buildRoute(RouteSettings settings) {
  final routeName = settings.name?.trim().isNotEmpty == true
      ? settings.name!.trim()
      : '/';
  final uri = Uri.tryParse(routeName);

  if (uri != null && uri.path == '/detail/item') {
    final payloadToken = DetailRoutePayloadStore.payloadTokenFromUri(uri);
    final rawInitialItemDetail = payloadToken == null
        ? (uri.queryParameters['initialItemDetail'] ?? '')
        : '';
    final decodedInitialItemDetail = RouteQueryJson.tryDecodeMap(
      rawInitialItemDetail,
    );
    return AppTransitions.leftToRightPageTurnRoute<void>(
      DetailItemRoute(
        itemGuid: uri.queryParameters['itemGuid'] ?? '',
        seriesGuid: uri.queryParameters['seriesGuid'] ?? '',
        initialItemDetail: decodedInitialItemDetail,
        payloadToken: payloadToken,
      ),
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/detail/host') {
    return AppTransitions.splitPaneHostRoute<void>(
      DetailHostRoute(
        initialRouteName: uri.queryParameters['route'] ?? '/',
        // root：副栏可回退到的根路由（如原生壳分屏副栏 root=/screen/home，
        // 使返回键先回首页浏览，而不是直接收掉分屏）。
        rootRouteName: uri.queryParameters['root']?.trim().isNotEmpty == true
            ? uri.queryParameters['root']!.trim()
            : null,
      ),
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/detail/season') {
    final payloadToken = DetailRoutePayloadStore.payloadTokenFromUri(uri);
    final rawSeasonItem = payloadToken == null
        ? (uri.queryParameters['seasonItem'] ?? '')
        : '';
    final decodedSeasonItem =
        RouteQueryJson.tryDecodeMap(rawSeasonItem) ?? const <String, dynamic>{};
    return AppTransitions.leftToRightPageTurnRoute<void>(
      DetailSeasonRoute(
        parentGuid: uri.queryParameters['parentGuid'] ?? '',
        seriesTitle: uri.queryParameters['seriesTitle'] ?? '',
        backdropPath: uri.queryParameters['backdropPath'] ?? '',
        seasonItem: decodedSeasonItem.isEmpty
            ? null
            : MediaLibraryItem.fromJson(decodedSeasonItem),
        seasonGuid: uri.queryParameters['seasonGuid'] ?? '',
        payloadToken: payloadToken,
      ),
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/detail/person') {
    return AppTransitions.leftToRightPageTurnRoute<void>(
      DetailPersonRoute(
        personGuid: uri.queryParameters['personGuid'] ?? '',
        initialName: uri.queryParameters['initialName'] ?? '',
      ),
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/screen/search') {
    return AppTransitions.leftToRightPageTurnRoute<void>(
      const SearchRoute(),
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/screen/poster-browse') {
    return AppTransitions.leftToRightPageTurnRoute<void>(
      const PosterBrowseRoute(),
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/screen/favorites') {
    return AppTransitions.leftToRightPageTurnRoute<void>(
      const FavoriteRoute(),
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/screen/downloads') {
    return AppTransitions.leftToRightPageTurnRoute<void>(
      DownloadListRoute(
        initialTab: DownloadListTabX.fromRouteValue(
          uri.queryParameters['tab'] ?? '',
        ),
      ),
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/screen/downloads/detail') {
    return AppTransitions.leftToRightPageTurnRoute<void>(
      DownloadGroupDetailRoute(
        groupId: uri.queryParameters['groupId'] ?? '',
        initialTab: DownloadListTabX.fromRouteValue(
          uri.queryParameters['tab'] ?? '',
        ),
      ),
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/screen/category') {
    final rawCategory = uri.queryParameters['category'] ?? '';
    final rawTypes = uri.queryParameters['types'] ?? '';
    final decodedCategory =
        RouteQueryJson.tryDecodeMap(rawCategory) ?? const <String, dynamic>{};
    final decodedTypes = RouteQueryJson.tryDecodeStringList(rawTypes);
    return AppTransitions.leftToRightPageTurnRoute<void>(
      CategoryRoute(
        category: MediaItem.fromJson(decodedCategory),
        initialTypeTags: decodedTypes,
      ),
      settings: settings,
    );
  }
  if (uri != null && uri.path == ScreenshotLightboxRouteScreen.routePath) {
    final payloadToken = ScreenshotLightboxRouteScreen.payloadTokenFromUri(uri);
    if (payloadToken != null) {
      return ScreenshotLightboxRouteScreen.buildRoute(
        payloadToken: payloadToken,
        settings: settings,
      );
    }
    final item = ScreenshotLightboxRouteScreen.itemFromUri(uri);
    if (item != null) {
      return ScreenshotLightboxRouteScreen.buildRoute(
        item: item,
        settings: settings,
      );
    }
  }
  final settingsDestination = SettingsDestinationRoutes.buildRoute(routeName);
  if (settingsDestination != null) {
    return AppTransitions.leftToRightPageTurnRoute<void>(
      settingsDestination,
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/screen/settings') {
    return AppTransitions.leftToRightPageTurnRoute<void>(
      const SettingsRoute(),
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/parallel/placeholder') {
    return AppTransitions.leftToRightPageTurnRoute<void>(
      const ParallelPlaceholderRoute(),
      settings: settings,
    );
  }
  return AppTransitions.leftToRightPageTurnRoute<void>(
    const AppEntry(),
    settings: settings,
  );
}

List<Route<dynamic>> _buildInitialRoutes(String initialRoute) {
  final normalized = initialRoute.trim().isEmpty ? '/' : initialRoute.trim();
  return <Route<dynamic>>[_buildRoute(RouteSettings(name: normalized))];
}

class _ProviderGate extends StatelessWidget {
  final Widget child;
  final bool requireConfigured;

  const _ProviderGate({required this.child, this.requireConfigured = true});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NasProvider>();
    final session = context.watch<BackendSessionProvider>();
    final colors = context.appColors;
    final hasUnreadyLoadFailure =
        (!provider.isReady && provider.hasLoadFailure) ||
        (!session.isReady && session.hasLoadFailure);
    if (hasUnreadyLoadFailure) {
      return Scaffold(
        backgroundColor: colors.backgroundBase,
        body: AppErrorState(
          error: AppException(
            kind: AppExceptionKind.transient,
            action: 'initialize session providers',
            message: AppLocalizations.of(context).globalLoadFailed,
          ),
          onRetry: () {
            unawaited(
              Future.wait<void>(<Future<void>>[
                if (!provider.isReady) provider.retryLoad(),
                if (!session.isReady) session.retryLoad(),
              ]),
            );
          },
        ),
      );
    }
    if (!provider.isReady || !session.isReady) {
      return Scaffold(
        backgroundColor: colors.backgroundBase,
        body: const Center(child: BirdLoader(size: 140)),
      );
    }
    // 飞牛已配置，或当前后端会话为服务器族且已认证，均可进入主导航；否则回登录页。
    final serverFamilyReady =
        session.currentKind.isServerFamily && session.isConfigured;
    if (requireConfigured && !provider.isConfigured && !serverFamilyReady) {
      return const ConnectionScreen();
    }
    return child;
  }
}

class AppEntry extends StatelessWidget {
  final MainPrimaryTab initialTab;

  const AppEntry({super.key, this.initialTab = MainPrimaryTab.home});

  @override
  Widget build(BuildContext context) {
    final nas = context.watch<NasProvider>();
    final session = context.watch<BackendSessionProvider>();
    final serverFamilyReady =
        session.currentKind.isServerFamily && session.isConfigured;
    return StartupDestinationGate(
      decisionReady: nas.isReady && session.isReady,
      canOpenDestination: nas.isConfigured || serverFamilyReady,
      child: _ProviderGate(child: MainNavigation(initialTab: initialTab)),
    );
  }
}

enum MainPrimaryTab {
  home('home', 0),
  settings('settings', 1);

  const MainPrimaryTab(this.tabId, this.tabIndex);

  final String tabId;
  final int tabIndex;

  static MainPrimaryTab fromIndex(int index) {
    for (final tab in values) {
      if (tab.tabIndex == index) return tab;
    }
    return home;
  }

  static MainPrimaryTab fromTabId(String tabId) {
    final normalizedTabId = tabId.trim();
    for (final tab in values) {
      if (tab.tabId == normalizedTabId) return tab;
    }
    return home;
  }
}

class DetailItemRoute extends StatelessWidget {
  final String itemGuid;
  final String seriesGuid;
  final Map<String, dynamic>? initialItemDetail;
  final String? payloadToken;

  const DetailItemRoute({
    super.key,
    required this.itemGuid,
    this.seriesGuid = '',
    this.initialItemDetail,
    this.payloadToken,
  });

  @override
  Widget build(BuildContext context) {
    if (itemGuid.trim().isEmpty) {
      return const _RouteErrorScreen(kind: _RouteErrorKind.missingDetail);
    }
    return _ProviderGate(
      child: DetailItemRouteBody(
        itemGuid: itemGuid,
        seriesGuid: seriesGuid,
        initialItemDetail: initialItemDetail,
        payloadToken: payloadToken,
      ),
    );
  }
}

class DetailHostRoute extends StatelessWidget {
  final String initialRouteName;
  final String? rootRouteName;

  const DetailHostRoute({
    super.key,
    required this.initialRouteName,
    this.rootRouteName,
  });

  @override
  Widget build(BuildContext context) {
    return _ProviderGate(
      child: DetailHostScreen(
        initialRouteName: initialRouteName,
        rootRouteName: rootRouteName,
      ),
    );
  }
}

class DetailSeasonRoute extends StatelessWidget {
  final String parentGuid;
  final String seriesTitle;
  final String backdropPath;
  final MediaLibraryItem? seasonItem;
  final String? seasonGuid;
  final String? payloadToken;

  const DetailSeasonRoute({
    super.key,
    required this.parentGuid,
    required this.seriesTitle,
    required this.backdropPath,
    this.seasonItem,
    this.seasonGuid,
    this.payloadToken,
  });

  @override
  Widget build(BuildContext context) {
    if (parentGuid.trim().isEmpty ||
        (((seasonItem?.guid ?? '').trim().isEmpty) &&
            (seasonGuid?.trim().isNotEmpty != true))) {
      return const _RouteErrorScreen(kind: _RouteErrorKind.missingSeason);
    }
    return _ProviderGate(
      child: DetailSeasonRouteBody(
        parentGuid: parentGuid,
        seriesTitle: seriesTitle,
        backdropPath: backdropPath,
        seasonItem: seasonItem,
        seasonGuid: seasonGuid,
        payloadToken: payloadToken,
      ),
    );
  }
}

class DetailPersonRoute extends StatelessWidget {
  final String personGuid;
  final String initialName;

  const DetailPersonRoute({
    super.key,
    required this.personGuid,
    required this.initialName,
  });

  @override
  Widget build(BuildContext context) {
    if (personGuid.trim().isEmpty) {
      return const _RouteErrorScreen(kind: _RouteErrorKind.missingPerson);
    }
    return _ProviderGate(
      child: PersonDetailScreen(
        personGuid: personGuid,
        initialName: initialName,
      ),
    );
  }
}

class SearchRoute extends StatelessWidget {
  const SearchRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ProviderGate(child: SearchScreen(secondaryHost: true));
  }
}

class PosterBrowseRoute extends StatelessWidget {
  const PosterBrowseRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ProviderGate(child: PosterBrowseScreen());
  }
}

class FavoriteRoute extends StatelessWidget {
  const FavoriteRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ProviderGate(child: FavoriteItemsScreen.secondaryHost());
  }
}

class DownloadListRoute extends StatelessWidget {
  final DownloadListTab initialTab;

  const DownloadListRoute({
    super.key,
    this.initialTab = DownloadListTab.downloaded,
  });

  @override
  Widget build(BuildContext context) {
    return _ProviderGate(
      requireConfigured: false,
      child: DownloadListScreen(initialTab: initialTab),
    );
  }
}

class DownloadGroupDetailRoute extends StatelessWidget {
  final String groupId;
  final DownloadListTab initialTab;

  const DownloadGroupDetailRoute({
    super.key,
    required this.groupId,
    this.initialTab = DownloadListTab.downloaded,
  });

  @override
  Widget build(BuildContext context) {
    if (groupId.trim().isEmpty) {
      return const _RouteErrorScreen(kind: _RouteErrorKind.missingDownload);
    }
    return _ProviderGate(
      requireConfigured: false,
      child: DownloadGroupDetailScreen(
        groupId: groupId,
        initialTab: initialTab,
      ),
    );
  }
}

class CategoryRoute extends StatelessWidget {
  final MediaItem category;
  final List<String>? initialTypeTags;

  const CategoryRoute({
    super.key,
    required this.category,
    this.initialTypeTags,
  });

  @override
  Widget build(BuildContext context) {
    return _ProviderGate(
      child: CategoryItemsScreen(
        category: category,
        initialTypeTags: initialTypeTags,
        secondaryHost: true,
      ),
    );
  }
}

class SettingsRoute extends StatelessWidget {
  const SettingsRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ProviderGate(
      child: MainNavigation(initialTab: MainPrimaryTab.settings),
    );
  }
}

class ParallelPlaceholderRoute extends StatelessWidget {
  const ParallelPlaceholderRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ProviderGate(
      requireConfigured: false,
      child: ParallelPlaceholderScreen(),
    );
  }
}

enum _RouteErrorKind {
  missingDetail,
  missingSeason,
  missingPerson,
  missingDownload,
}

AppLocalizations? _maybeAppLocalizations(BuildContext context) {
  return Localizations.of<AppLocalizations>(context, AppLocalizations);
}

class _RouteErrorScreen extends StatelessWidget {
  final _RouteErrorKind kind;

  const _RouteErrorScreen({required this.kind});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final message = _message(context);
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

  String _message(BuildContext context) {
    final l10n = _maybeAppLocalizations(context);
    final fallback = lookupAppLocalizations(const Locale('zh', 'CN'));
    return switch (kind) {
      _RouteErrorKind.missingDetail =>
        l10n?.routeErrorMissingDetail ?? fallback.routeErrorMissingDetail,
      _RouteErrorKind.missingSeason =>
        l10n?.routeErrorMissingSeason ?? fallback.routeErrorMissingSeason,
      _RouteErrorKind.missingPerson =>
        l10n?.routeErrorMissingPerson ?? fallback.routeErrorMissingPerson,
      _RouteErrorKind.missingDownload =>
        l10n?.routeErrorMissingDownload ?? fallback.routeErrorMissingDownload,
    };
  }
}

class MainNavigation extends StatefulWidget {
  final MainPrimaryTab initialTab;

  const MainNavigation({super.key, this.initialTab = MainPrimaryTab.home});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late MainPrimaryTab _selectedTab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    unawaited(MainHostBridge.setMethodCallHandler(_handleMainHostMethodCall));
    // 预取 GPU 画像并缓存：供播放器在创建视频平台视图前决定 texture/surface 后端
    // （Mali 走 SurfaceView）。此处 engine 已就绪、system channel 已注册。
    unawaited(GpuProfileBridge.ensureLoaded());
  }

  @override
  void didUpdateWidget(covariant MainNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _selectedTab = widget.initialTab;
    }
  }

  @override
  void dispose() {
    unawaited(MainHostBridge.setMethodCallHandler(null));
    super.dispose();
  }

  Future<dynamic> _handleMainHostMethodCall(MethodCall call) async {
    final arguments = (call.arguments as Map?)?.map(
      (key, value) => MapEntry('${key ?? ''}', value),
    );
    switch (call.method) {
      case 'switchPrimaryTab':
      case 'openPrimarySettings':
        final tabId =
            arguments?['tabId']?.toString() ??
            (call.method == 'openPrimarySettings'
                ? MainPrimaryTab.settings.tabId
                : MainPrimaryTab.home.tabId);
        if (!mounted) return null;
        setState(() {
          _selectedTab = MainPrimaryTab.fromTabId(tabId);
        });
        return true;
      default:
        return null;
    }
  }

  Future<void> _handleNavigationTap(int index) async {
    if (!mounted) return;
    setState(() {
      _selectedTab = MainPrimaryTab.fromIndex(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 桌面端宽窗口改走侧栏 Shell（feat/desktop-nav）；Android / 窄窗口保持
    // 底部胶囊导航路径与既有行为完全一致。
    final viewportWidth = MediaQuery.sizeOf(context).width;
    if (DesktopEnvironment.isDesktopPlatform &&
        viewportWidth >= DesktopBreakpoints.sidebarMinWidth) {
      return DesktopShell(initialTab: _selectedTab.tabIndex);
    }
    const pages = <Widget>[MediaListScreen(), AppSettingsScreen()];
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      // 内容延伸到导航条后方：底栏只保留悬浮胶囊 + 单层渐隐托底，
      // 由各页面的列表自行预留 MainNavigationMetrics.contentBottomInset。
      extendBody: true,
      body: IndexedStack(index: _selectedTab.tabIndex, children: pages),
      bottomNavigationBar: _LiquidGlassBottomNavigation(
        currentIndex: _selectedTab.tabIndex,
        onTap: (index) => unawaited(_handleNavigationTap(index)),
        destinations: <_LiquidGlassNavDestination>[
          _LiquidGlassNavDestination(
            icon: Icons.video_library_outlined,
            label: l10n.navMovies,
          ),
          _LiquidGlassNavDestination(
            icon: Icons.tune_rounded,
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}

class _LiquidGlassNavDestination {
  final IconData icon;
  final String label;

  const _LiquidGlassNavDestination({required this.icon, required this.label});
}

class _LiquidGlassBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<_LiquidGlassNavDestination> destinations;

  const _LiquidGlassBottomNavigation({
    required this.currentIndex,
    required this.onTap,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isLightSurface = colors.backgroundBase.computeLuminance() >= 0.58;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final safeIndex = currentIndex.clamp(0, destinations.length - 1);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final barWidth = MainNavigationMetrics.barWidthFor(viewportWidth);
    final bottomPadding = MainNavigationMetrics.outerBottomPadding(bottomInset);
    final inactive = colors.textSecondary;
    final active = Color.lerp(colors.textPrimary, colors.selection, .28)!;
    final outerSurface = Color.alphaBlend(
      colors.selection.withValues(alpha: isLightSurface ? .08 : .12),
      colors.navBarBackground,
    );
    final selectedSurface = Color.alphaBlend(
      colors.selection.withValues(alpha: isLightSurface ? .16 : .20),
      outerSurface,
    );

    // 单层渐变托底：从页面背景完全透明渐入 backgroundBase，
    // 消除旧的实色横带接缝；仅一层渐变绘制，无模糊合成开销。
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const <double>[0, .35, 1],
            colors: <Color>[
              colors.backgroundBase.withValues(alpha: 0),
              colors.backgroundBase.withValues(alpha: .72),
              colors.backgroundBase,
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: 6, bottom: bottomPadding),
          child: Center(
            heightFactor: 1,
            child: SizedBox(
              width: barWidth,
              height: MainNavigationMetrics.barHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: outerSurface,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: Color.alphaBlend(
                      colors.selection.withValues(alpha: .24),
                      outerSurface,
                    ),
                    width: .8,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: destinations.length <= 1
                          ? Alignment.center
                          : Alignment(
                              -1.0 +
                                  safeIndex * (2.0 / (destinations.length - 1)),
                              0,
                            ),
                      child: FractionallySizedBox(
                        widthFactor: 1 / destinations.length,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          // 选中块只靠填充色阶区分，去掉旧的双层描边。
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(19),
                              color: selectedSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(destinations.length, (index) {
                        final selected = index == safeIndex;
                        return Expanded(
                          child: _LiquidGlassNavItem(
                            destination: destinations[index],
                            selected: selected,
                            activeColor: active,
                            inactiveColor: inactive,
                            onTap: () => onTap(index),
                          ),
                        );
                      }),
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

class _LiquidGlassNavItem extends StatelessWidget {
  final _LiquidGlassNavDestination destination;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _LiquidGlassNavItem({
    required this.destination,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkResponse(
        onTap: onTap,
        radius: 44,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: color,
            fontSize: selected ? 13 : 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            height: 1.0,
          ),
          child: IconTheme(
            data: IconThemeData(color: color, size: selected ? 21 : 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(destination.icon),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: const TextScaler.linear(1.0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
