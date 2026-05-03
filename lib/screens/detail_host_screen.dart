import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../models/media_library_item.dart';
import '../providers/app_theme_provider.dart';
import '../services/detail_route_payload_store.dart';
import '../ui/app_transitions.dart';
import '../ui/detail_presentation.dart';
import 'detail_route_bodies.dart';
import 'app_settings_screen.dart';
import 'category_items_screen.dart';
import 'download_list_screen.dart';
import 'favorite_items_screen.dart';
import 'media_list_screen.dart';
import 'parallel_placeholder_screen.dart';
import 'person_detail_screen.dart';
import 'search_screen.dart';
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

  String _routeTargetKey(String routeName) {
    final normalized = _normalizeRoute(routeName);
    final uri = Uri.tryParse(normalized);
    if (uri == null) return normalized;
    final path = uri.path.trim();
    switch (path) {
      case '/detail/item':
        return [
          path,
          uri.queryParameters['itemGuid']?.trim() ?? '',
          uri.queryParameters['seriesGuid']?.trim() ?? '',
        ].join('|');
      case '/detail/person':
        return [
          path,
          uri.queryParameters['personGuid']?.trim() ?? '',
        ].join('|');
      case '/detail/season':
        return [
          path,
          uri.queryParameters['parentGuid']?.trim() ?? '',
          uri.queryParameters['seasonGuid']?.trim() ?? '',
        ].join('|');
      default:
        return normalized;
    }
  }

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

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'replaceRoute') return;
    final arguments = call.arguments as Map?;
    final routeName = arguments?['routeName']?.toString().trim() ?? '';
    final resetStack = arguments?['resetStack'] == true;
    if (!mounted || routeName.isEmpty) return;
    _schedulePlatformRoute(routeName, resetStack: resetStack);
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

Widget _buildRouteChild(String routeName, {required bool isActiveRoute}) {
  final normalizedRoute = routeName.trim().isEmpty
      ? '/parallel/placeholder'
      : routeName.trim();
  final uri = Uri.tryParse(normalizedRoute);
  if (uri == null) {
    return const _DetailHostRouteError(message: 'Invalid route format');
  }

  if (uri.path == '/detail/item') {
    final itemGuid = uri.queryParameters['itemGuid'] ?? '';
    final payloadToken = DetailRoutePayloadStore.payloadTokenFromUri(uri);
    final rawInitialItemDetail = payloadToken == null
        ? (uri.queryParameters['initialItemDetail'] ?? '')
        : '';
    final decodedInitialItemDetail = rawInitialItemDetail.isEmpty
        ? null
        : (jsonDecode(rawInitialItemDetail) as Map).cast<String, dynamic>();
    if (itemGuid.trim().isEmpty) {
      return const _DetailHostRouteError(message: 'Missing detail parameters');
    }
    return DetailItemRouteBody(
      key: ValueKey<String>(routeName),
      itemGuid: itemGuid,
      seriesGuid: uri.queryParameters['seriesGuid'] ?? '',
      initialItemDetail: decodedInitialItemDetail,
      payloadToken: payloadToken,
      presentation: DetailPresentation.pane,
    );
  }

  if (uri.path == '/detail/season') {
    final payloadToken = DetailRoutePayloadStore.payloadTokenFromUri(uri);
    final rawSeasonItem = payloadToken == null
        ? (uri.queryParameters['seasonItem'] ?? '')
        : '';
    final decodedSeasonItem = rawSeasonItem.isEmpty
        ? const <String, dynamic>{}
        : (jsonDecode(rawSeasonItem) as Map).cast<String, dynamic>();
    final parentGuid = uri.queryParameters['parentGuid'] ?? '';
    final seasonItem = decodedSeasonItem.isEmpty
        ? null
        : MediaLibraryItem.fromJson(decodedSeasonItem);
    final seasonGuid = uri.queryParameters['seasonGuid'] ?? '';
    if (parentGuid.trim().isEmpty ||
        (((seasonItem?.guid ?? '').trim().isEmpty) &&
            seasonGuid.trim().isEmpty)) {
      return const _DetailHostRouteError(
        message: 'Missing season detail parameters',
      );
    }
    return DetailSeasonRouteBody(
      key: ValueKey<String>(routeName),
      parentGuid: parentGuid,
      seriesTitle: uri.queryParameters['seriesTitle'] ?? '',
      backdropPath: uri.queryParameters['backdropPath'] ?? '',
      seasonItem: seasonItem,
      seasonGuid: seasonGuid,
      payloadToken: payloadToken,
      presentation: DetailPresentation.pane,
    );
  }

  if (uri.path == '/detail/person') {
    final personGuid = uri.queryParameters['personGuid'] ?? '';
    if (personGuid.trim().isEmpty) {
      return const _DetailHostRouteError(
        message: 'Missing person detail parameters',
      );
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
      return const _DetailHostRouteError(
        message: 'Missing download detail parameters',
      );
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

  return const _DetailHostRouteError(message: 'Page not found');
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
