import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'models/media_item.dart';
import 'models/media_library_item.dart';
import 'pages/tv_season_detail_page.dart';
import 'providers/app_theme_provider.dart';
import 'providers/nas_provider.dart';
import 'providers/parallel_window_settings_provider.dart';
import 'screens/app_settings_screen.dart';
import 'screens/category_items_screen.dart';
import 'screens/connection_screen.dart';
import 'screens/detail_host_screen.dart';
import 'screens/download_list_screen.dart';
import 'screens/favorite_items_screen.dart';
import 'screens/media_list_screen.dart';
import 'screens/parallel_placeholder_screen.dart';
import 'screens/person_detail_screen.dart';
import 'screens/play_detail_screen.dart';
import 'screens/player_host_screen.dart';
import 'screens/search_screen.dart';
import 'screens/screenshot_preview_screen.dart';
import 'services/app_log_service.dart';
import 'services/main_host_bridge.dart';
import 'screens/settings_destination_routes.dart';
import 'theme/app_theme.dart';
import 'ui/adaptive_text.dart';
import 'ui/app_transitions.dart';
import 'utils/private_network_http_overrides.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await AppLogService.instance.initialize();
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
              '加载失败',
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
      ],
      child: Consumer<AppThemeProvider>(
        builder: (context, themeProvider, _) {
          final effectiveColors = themeProvider.effectiveThemeColors;
          return MaterialApp(
            title: 'Fly Player',
            theme: AppThemeBuilder.buildFromColors(effectiveColors),
            builder: (context, child) {
              if (child == null) return const SizedBox.shrink();
              final media = MediaQuery.of(context);
              final scale = AdaptiveText.globalScale(media);
              return MediaQuery(
                data: media.copyWith(textScaler: TextScaler.linear(scale)),
                child: child,
              );
            },
            initialRoute: _initialRouteName(),
            onGenerateInitialRoutes: _buildInitialRoutes,
            onGenerateRoute: _buildRoute,
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
    final rawInitialItemDetail = uri.queryParameters['initialItemDetail'] ?? '';
    final decodedInitialItemDetail = rawInitialItemDetail.isEmpty
        ? null
        : (jsonDecode(rawInitialItemDetail) as Map).cast<String, dynamic>();
    return AppTransitions.leftToRightPageTurnRoute<void>(
      DetailItemRoute(
        itemGuid: uri.queryParameters['itemGuid'] ?? '',
        seriesGuid: uri.queryParameters['seriesGuid'] ?? '',
        initialItemDetail: decodedInitialItemDetail,
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
    final rawSeasonItem = uri.queryParameters['seasonItem'] ?? '';
    final decodedSeasonItem = rawSeasonItem.isEmpty
        ? const <String, dynamic>{}
        : (jsonDecode(rawSeasonItem) as Map).cast<String, dynamic>();
    return AppTransitions.leftToRightPageTurnRoute<void>(
      DetailSeasonRoute(
        parentGuid: uri.queryParameters['parentGuid'] ?? '',
        seriesTitle: uri.queryParameters['seriesTitle'] ?? '',
        backdropPath: uri.queryParameters['backdropPath'] ?? '',
        seasonItem: MediaLibraryItem.fromJson(decodedSeasonItem),
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

  const DetailItemRoute({
    super.key,
    required this.itemGuid,
    this.seriesGuid = '',
    this.initialItemDetail,
  });

  @override
  Widget build(BuildContext context) {
    if (itemGuid.trim().isEmpty) {
      return const _RouteErrorScreen(message: '缺少详情参数');
    }
    return _ProviderGate(
      child: PlayDetailScreen(
        itemGuid: itemGuid,
        seriesGuid: seriesGuid,
        initialItemDetail: initialItemDetail,
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
  final MediaLibraryItem seasonItem;

  const DetailSeasonRoute({
    super.key,
    required this.parentGuid,
    required this.seriesTitle,
    required this.backdropPath,
    required this.seasonItem,
  });

  @override
  Widget build(BuildContext context) {
    if (parentGuid.trim().isEmpty || seasonItem.guid.trim().isEmpty) {
      return const _RouteErrorScreen(message: '缺少季详情参数');
    }
    return _ProviderGate(
      child: TvSeasonDetailPage(
        parentGuid: parentGuid,
        seriesTitle: seriesTitle,
        backdropPath: backdropPath,
        seasonItem: seasonItem,
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
      return const _RouteErrorScreen(message: '缺少人物详情参数');
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
      return const _RouteErrorScreen(message: '缺少下载详情参数');
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

class _RouteErrorScreen extends StatelessWidget {
  final String message;

  const _RouteErrorScreen({required this.message});

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

    return Scaffold(
      body: IndexedStack(index: _selectedTab.tabIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: colors.navBarBackground,
        currentIndex: _selectedTab.tabIndex,
        onTap: (index) {
          unawaited(_handleNavigationTap(index));
        },
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.movie), label: '影视'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
