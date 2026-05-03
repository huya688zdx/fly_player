import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'l10n/generated/app_localizations.dart';
import 'models/media_item.dart';
import 'models/media_library_item.dart';
import 'providers/app_locale_provider.dart';
import 'providers/app_theme_provider.dart';
import 'providers/nas_provider.dart';
import 'providers/parallel_window_settings_provider.dart';
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
import 'screens/player_host_screen.dart';
import 'screens/search_screen.dart';
import 'screens/screenshot_preview_screen.dart';
import 'services/app_log_service.dart';
import 'services/detail_route_payload_store.dart';
import 'services/main_host_bridge.dart';
import 'screens/settings_destination_routes.dart';
import 'theme/app_theme.dart';
import 'theme/dynamic_theme_runtime_controller.dart';
import 'theme/dynamic_theme_seed_extractor.dart';
import 'ui/adaptive_text.dart';
import 'ui/app_transitions.dart';
import 'utils/private_network_http_overrides.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await AppLogService.instance.initialize();
      _FrameTimingLogger.install();
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

  static void install() {
    if (_installed || kReleaseMode) {
      return;
    }
    _installed = true;
    WidgetsBinding.instance.addTimingsCallback(_handleTimings);
    debugPrint('[PERF][FRAME] timings enabled');
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
          '[PERF][FRAME] jank total=${_ms(totalMicros)} build=${_ms(buildMicros)} raster=${_ms(rasterMicros)}',
        );
      }
      if (_frames >= _summaryFrameCount) {
        _flushSummary();
      }
    }
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
      '[PERF][FRAME] summary frames=$_frames slow60=$_slowFrames jank30=$_jankyFrames '
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
                  'Load failed',
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
        ChangeNotifierProvider(create: (_) => ParallelWindowSettingsProvider()),
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
                title: 'Fly Player',
                onGenerateTitle: (context) =>
                    AppLocalizations.of(context).appTitle,
                locale: localeProvider.locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppThemeBuilder.buildFromColors(materialThemeColors),
                builder: (context, child) {
                  if (child == null) return const SizedBox.shrink();
                  final media = MediaQuery.of(context);
                  final scale = AdaptiveText.globalScale(media);
                  return AppRuntimeColorScope(
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
    final decodedInitialItemDetail = rawInitialItemDetail.isEmpty
        ? null
        : (jsonDecode(rawInitialItemDetail) as Map).cast<String, dynamic>();
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
      DetailHostRoute(initialRouteName: uri.queryParameters['route'] ?? '/'),
      settings: settings,
    );
  }
  if (uri != null && uri.path == '/detail/season') {
    final payloadToken = DetailRoutePayloadStore.payloadTokenFromUri(uri);
    final rawSeasonItem = payloadToken == null
        ? (uri.queryParameters['seasonItem'] ?? '')
        : '';
    final decodedSeasonItem = rawSeasonItem.isEmpty
        ? const <String, dynamic>{}
        : (jsonDecode(rawSeasonItem) as Map).cast<String, dynamic>();
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
    final decodedCategory = rawCategory.isEmpty
        ? const <String, dynamic>{}
        : (jsonDecode(rawCategory) as Map).cast<String, dynamic>();
    final decodedTypes = rawTypes.isEmpty
        ? null
        : (jsonDecode(rawTypes) as List)
              .map((value) => '$value')
              .toList(growable: false);
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
  if (uri != null && uri.path == '/player') {
    return AppTransitions.leftToRightPageTurnRoute<void>(
      const PlayerActivityRoute(),
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
    final colors = context.appColors;
    if (!provider.isReady) {
      return Scaffold(
        backgroundColor: colors.backgroundBase,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (requireConfigured && !provider.isConfigured) {
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
    return _ProviderGate(child: MainNavigation(initialTab: initialTab));
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

  const DetailHostRoute({super.key, required this.initialRouteName});

  @override
  Widget build(BuildContext context) {
    return _ProviderGate(
      child: DetailHostScreen(initialRouteName: initialRouteName),
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

class PlayerActivityRoute extends StatelessWidget {
  const PlayerActivityRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlayerHostScreen();
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
    return switch (kind) {
      _RouteErrorKind.missingDetail =>
        l10n?.routeErrorMissingDetail ?? 'Missing detail parameters',
      _RouteErrorKind.missingSeason =>
        l10n?.routeErrorMissingSeason ?? 'Missing season detail parameters',
      _RouteErrorKind.missingPerson =>
        l10n?.routeErrorMissingPerson ?? 'Missing person detail parameters',
      _RouteErrorKind.missingDownload =>
        l10n?.routeErrorMissingDownload ?? 'Missing download detail parameters',
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
    const pages = <Widget>[MediaListScreen(), AppSettingsScreen()];
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: IndexedStack(index: _selectedTab.tabIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: colors.navBarBackground,
        selectedItemColor: colors.selectionStrong,
        unselectedItemColor: colors.textMuted,
        currentIndex: _selectedTab.tabIndex,
        onTap: (index) {
          unawaited(_handleNavigationTap(index));
        },
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: const Icon(Icons.movie),
            label: l10n.navMovies,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_rounded),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}
