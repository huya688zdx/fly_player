import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media_item.dart';
import '../models/media_library_item.dart';
import '../pages/tv_season_detail_page.dart';
import '../ui/app_transitions.dart';
import '../ui/detail_presentation.dart';
import 'app_settings_screen.dart';
import 'category_items_screen.dart';
import 'download_list_screen.dart';
import 'favorite_items_screen.dart';
import 'media_list_screen.dart';
import 'parallel_placeholder_screen.dart';
import 'person_detail_screen.dart';
import 'play_detail_screen.dart';
import 'search_screen.dart';
import 'settings_destination_routes.dart';

class DetailHostScreen extends StatefulWidget {
  final String initialRouteName;
  final String? rootRouteName;
  final ValueListenable<String>? routeListenable;
  final bool enablePlatformChannel;

  const DetailHostScreen({
    super.key,
    required this.initialRouteName,
    this.rootRouteName,
    this.routeListenable,
    this.enablePlatformChannel = true,
  });

  @override
  State<DetailHostScreen> createState() => DetailHostScreenState();
}

class DetailHostScreenState extends State<DetailHostScreen> {
  static const MethodChannel _channel = MethodChannel('fly_player/detail_host');

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final List<String> _routeStack = _buildInitialStack();

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
    if (normalized == current) return;
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

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'replaceRoute') return;
    final arguments = call.arguments as Map?;
    final routeName = arguments?['routeName']?.toString().trim() ?? '';
    final resetStack = arguments?['resetStack'] == true;
    if (!mounted || routeName.isEmpty) return;
    if (resetStack) {
      _replaceRouteStack(routeName);
      return;
    }
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
    setState(() {
      _routeStack
        ..clear()
        ..addAll(nextStack);
    });
    _syncRouteListenableValue(nextStack.last);
  }

  bool _handlePopPage(Route<dynamic> route, Object? result) {
    if (!route.didPop(result)) return false;
    if (_routeStack.length <= 1) return false;
    setState(() {
      _routeStack.removeLast();
    });
    return true;
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
              child: _buildRouteChild(
                routeName,
                isActiveRoute: index == _routeStack.length - 1,
              ),
            ),
          ),
        )
        .values
        .toList(growable: false);
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (result) {
        _navigatorKey.currentState?.pop(result);
      },
      child: Navigator(
        key: _navigatorKey,
        pages: pages,
        onPopPage: _handlePopPage,
      ),
    );
  }
}

Widget _buildRouteChild(String routeName, {required bool isActiveRoute}) {
  final normalizedRoute = routeName.trim().isEmpty
      ? '/parallel/placeholder'
      : routeName.trim();
  final uri = Uri.tryParse(normalizedRoute);
  if (uri == null) {
    return const _DetailHostRouteError(message: '路由格式错误');
  }

  if (uri.path == '/detail/item') {
    final itemGuid = uri.queryParameters['itemGuid'] ?? '';
    final rawInitialItemDetail = uri.queryParameters['initialItemDetail'] ?? '';
    final decodedInitialItemDetail = rawInitialItemDetail.isEmpty
        ? null
        : (jsonDecode(rawInitialItemDetail) as Map).cast<String, dynamic>();
    if (itemGuid.trim().isEmpty) {
      return const _DetailHostRouteError(message: '缺少详情参数');
    }
    return PlayDetailScreen(
      key: ValueKey<String>(routeName),
      itemGuid: itemGuid,
      seriesGuid: uri.queryParameters['seriesGuid'] ?? '',
      initialItemDetail: decodedInitialItemDetail,
      presentation: DetailPresentation.pane,
    );
  }

  if (uri.path == '/detail/season') {
    final rawSeasonItem = uri.queryParameters['seasonItem'] ?? '';
    final decodedSeasonItem = rawSeasonItem.isEmpty
        ? const <String, dynamic>{}
        : (jsonDecode(rawSeasonItem) as Map).cast<String, dynamic>();
    final parentGuid = uri.queryParameters['parentGuid'] ?? '';
    final seasonItem = MediaLibraryItem.fromJson(decodedSeasonItem);
    if (parentGuid.trim().isEmpty || seasonItem.guid.trim().isEmpty) {
      return const _DetailHostRouteError(message: '缺少季详情参数');
    }
    return TvSeasonDetailPage(
      key: ValueKey<String>(routeName),
      parentGuid: parentGuid,
      seriesTitle: uri.queryParameters['seriesTitle'] ?? '',
      backdropPath: uri.queryParameters['backdropPath'] ?? '',
      seasonItem: seasonItem,
      presentation: DetailPresentation.pane,
    );
  }

  if (uri.path == '/detail/person') {
    final personGuid = uri.queryParameters['personGuid'] ?? '';
    if (personGuid.trim().isEmpty) {
      return const _DetailHostRouteError(message: '缺少人物详情参数');
    }
    return PersonDetailScreen(
      key: ValueKey<String>(routeName),
      personGuid: personGuid,
      initialName: uri.queryParameters['initialName'] ?? '',
      presentation: DetailPresentation.pane,
    );
  }

  if (uri.path == '/screen/search') {
    return const SearchScreen(
      key: ValueKey<String>('/screen/search'),
      secondaryHost: true,
    );
  }

  if (uri.path == '/screen/favorites') {
    return const FavoriteItemsScreen.secondaryHost(
      key: ValueKey<String>('/screen/favorites'),
    );
  }

  if (uri.path == '/screen/category') {
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
    return CategoryItemsScreen(
      key: ValueKey<String>(routeName),
      category: MediaItem.fromJson(decodedCategory),
      initialTypeTags: decodedTypes,
      secondaryHost: true,
    );
  }

  if (uri.path == '/screen/downloads') {
    return DownloadListScreen(
      key: ValueKey<String>(routeName),
      initialTab: DownloadListTabX.fromRouteValue(
        uri.queryParameters['tab'] ?? '',
      ),
    );
  }

  if (uri.path == '/screen/downloads/detail') {
    final groupId = uri.queryParameters['groupId'] ?? '';
    if (groupId.trim().isEmpty) {
      return const _DetailHostRouteError(message: '缺少下载详情参数');
    }
    return DownloadGroupDetailScreen(
      key: ValueKey<String>(routeName),
      groupId: groupId,
      initialTab: DownloadListTabX.fromRouteValue(
        uri.queryParameters['tab'] ?? '',
      ),
    );
  }

  final settingsDestination = SettingsDestinationRoutes.buildRoute(
    routeName,
    key: ValueKey<String>(routeName),
  );
  if (settingsDestination != null) {
    return settingsDestination;
  }

  if (uri.path == SettingsDestinationRoutes.home) {
    return const AppSettingsScreen(
      key: ValueKey<String>(SettingsDestinationRoutes.home),
      secondaryHost: true,
    );
  }

  if (uri.path == '/screen/home') {
    return _DeferredRouteChild(
      active: isActiveRoute,
      child: const MediaListScreen(
        key: ValueKey<String>('/screen/home'),
        secondaryHost: true,
      ),
    );
  }

  if (uri.path == '/parallel/placeholder') {
    return const ParallelPlaceholderScreen(
      key: ValueKey<String>('/parallel/placeholder'),
    );
  }

  return const _DetailHostRouteError(message: '未找到对应页面');
}

class _DeferredRouteChild extends StatefulWidget {
  final bool active;
  final Widget child;

  const _DeferredRouteChild({required this.active, required this.child});

  @override
  State<_DeferredRouteChild> createState() => _DeferredRouteChildState();
}

class _DeferredRouteChildState extends State<_DeferredRouteChild> {
  late bool _activated = widget.active;

  @override
  void didUpdateWidget(covariant _DeferredRouteChild oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_activated && widget.active) {
      setState(() {
        _activated = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_activated) {
      return const SizedBox.expand();
    }
    return widget.child;
  }
}

class _DetailHostRouteError extends StatelessWidget {
  final String message;

  const _DetailHostRouteError({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: Text(
          message,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 16),
        ),
      ),
    );
  }
}
