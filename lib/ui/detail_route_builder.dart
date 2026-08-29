import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/media_item.dart';
import '../models/media_library_item.dart';
import '../services/detail_route_payload_store.dart';
import '../utils/route_query_json.dart';
import 'detail_presentation.dart';
import '../screens/app_settings_screen.dart';
import '../screens/category_items_screen.dart';
import '../screens/detail_route_bodies.dart';
import '../screens/download_list_screen.dart';
import '../screens/favorite_items_screen.dart';
import '../screens/media_list_screen.dart';
import '../screens/parallel_placeholder_screen.dart';
import '../screens/person_detail_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_destination_routes.dart';

/// 嵌入式详情/副栏路由的统一构建入口。
///
/// 从 `detail_host_screen.dart` 提取的公共路由映射，供两处复用：
/// - Android 原生壳分屏副栏（`DetailHostScreen` 的内嵌 Navigator）；
/// - 桌面「浏览 | 详情」分屏详情宿主（`desktop_detail_pane_host.dart`）。
///
/// 详情类路由（/detail/item、/detail/season、/detail/person）一律以
/// `DetailPresentation.pane` 构建——pane 模式无 AppBar、按 pane 宽度自适应；
/// 取图走 `DetailArtworkResolver` / `MediaImageRef` 既有管线（飞牛相对路径
/// backdrop 与 Emby/Jellyfin 自鉴权直链均由页面自身逻辑处理，本文件只负责
/// 把路由参数送进去）。

/// 把路由名称解析为「同目标判定」键：详情类路由仅取身份参数（guid），
/// 其余路由取完整名称。用于防抖/去重（重复打开同一条目不重复压栈）。
String routeTargetKeyFor(String routeName) {
  final normalized = normalizePaneRouteName(routeName);
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
      return [path, uri.queryParameters['personGuid']?.trim() ?? ''].join('|');
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

/// 归一化路由名称：去首尾空白，空值回落到占位路由。
String normalizePaneRouteName(String routeName) {
  final trimmed = routeName.trim();
  return trimmed.isEmpty ? '/parallel/placeholder' : trimmed;
}

/// 路由名称的路径部分（忽略 query），空值回落占位路由。
String paneRoutePath(String routeName) {
  final uri = Uri.tryParse(routeName.trim());
  final path = uri?.path.trim() ?? '';
  return path.isEmpty ? '/parallel/placeholder' : path;
}

/// 按嵌入式副栏/桌面 pane 的统一映射，把命名路由构建为页面 Widget。
///
/// 与 main.dart 的顶层 URI 路由表保持同一套路径与参数约定，但详情类页面
/// 固定使用 [DetailPresentation.pane]。
Widget buildDetailRouteChild(String routeName, {required bool isActiveRoute}) {
  final normalizedRoute = normalizePaneRouteName(routeName);
  final uri = Uri.tryParse(normalizedRoute);
  if (uri == null) {
    return const _DetailHostRouteError(
      kind: _DetailHostRouteErrorKind.invalidFormat,
    );
  }

  if (uri.path == '/detail/item') {
    final itemGuid = uri.queryParameters['itemGuid'] ?? '';
    final payloadToken = DetailRoutePayloadStore.payloadTokenFromUri(uri);
    final rawInitialItemDetail = payloadToken == null
        ? (uri.queryParameters['initialItemDetail'] ?? '')
        : '';
    final decodedInitialItemDetail = RouteQueryJson.tryDecodeMap(
      rawInitialItemDetail,
    );
    if (itemGuid.trim().isEmpty) {
      return const _DetailHostRouteError(
        kind: _DetailHostRouteErrorKind.missingDetail,
      );
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
    final decodedSeasonItem =
        RouteQueryJson.tryDecodeMap(rawSeasonItem) ?? const <String, dynamic>{};
    final parentGuid = uri.queryParameters['parentGuid'] ?? '';
    final seasonItem = decodedSeasonItem.isEmpty
        ? null
        : MediaLibraryItem.fromJson(decodedSeasonItem);
    final seasonGuid = uri.queryParameters['seasonGuid'] ?? '';
    if (parentGuid.trim().isEmpty ||
        (((seasonItem?.guid ?? '').trim().isEmpty) &&
            seasonGuid.trim().isEmpty)) {
      return const _DetailHostRouteError(
        kind: _DetailHostRouteErrorKind.missingSeason,
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
        kind: _DetailHostRouteErrorKind.missingPerson,
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
    final decodedCategory =
        RouteQueryJson.tryDecodeMap(rawCategory) ?? const <String, dynamic>{};
    final decodedTypes = RouteQueryJson.tryDecodeStringList(rawTypes);
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
        kind: _DetailHostRouteErrorKind.missingDownload,
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

  return const _DetailHostRouteError(
    kind: _DetailHostRouteErrorKind.pageNotFound,
  );
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

enum _DetailHostRouteErrorKind {
  invalidFormat,
  missingDetail,
  missingSeason,
  missingPerson,
  missingDownload,
  pageNotFound,
}

class _DetailHostRouteError extends StatelessWidget {
  final _DetailHostRouteErrorKind kind;

  const _DetailHostRouteError({required this.kind});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final message = switch (kind) {
      _DetailHostRouteErrorKind.invalidFormat => l10n.routeErrorInvalidFormat,
      _DetailHostRouteErrorKind.missingDetail => l10n.routeErrorMissingDetail,
      _DetailHostRouteErrorKind.missingSeason => l10n.routeErrorMissingSeason,
      _DetailHostRouteErrorKind.missingPerson => l10n.routeErrorMissingPerson,
      _DetailHostRouteErrorKind.missingDownload =>
        l10n.routeErrorMissingDownload,
      _DetailHostRouteErrorKind.pageNotFound => l10n.routeErrorPageNotFound,
    };
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
