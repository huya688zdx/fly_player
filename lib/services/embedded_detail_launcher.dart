import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media_item.dart';
import '../models/media_library_item.dart';
import '../services/detail_route_payload_store.dart';
import '../ui/player_pane_host_scope.dart';
import '../utils/async_action_guard.dart';
import 'main_host_bridge.dart';
import 'parallel_browse_snapshot.dart';

/// 统一封装嵌入式详情页与播放器的打开逻辑。
class EmbeddedDetailLauncher {
  static const MethodChannel _channel = MethodChannel('fly_player/embedding');
  static const Duration _parallelWindowSupportCacheTtl = Duration(
    milliseconds: 800,
  );
  static bool? _parallelWindowSupportCacheValue;
  static DateTime? _parallelWindowSupportCacheTime;
  static Future<bool>? _parallelWindowSupportRequest;

  const EmbeddedDetailLauncher._();

  /// 查询当前宿主环境是否支持嵌入式详情页。
  static Future<bool> canOpenEmbeddedDetail() async {
    try {
      return await _channel.invokeMethod<bool>('canOpenEmbeddedDetail') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// 查询当前环境是否支持并行浏览窗口。
  static Future<bool> isParallelWindowSupported() async {
    final now = DateTime.now();
    final cachedValue = _parallelWindowSupportCacheValue;
    final cachedTime = _parallelWindowSupportCacheTime;
    if (cachedValue != null &&
        cachedTime != null &&
        now.difference(cachedTime) < _parallelWindowSupportCacheTtl) {
      return cachedValue;
    }
    final pendingRequest = _parallelWindowSupportRequest;
    if (pendingRequest != null) {
      return pendingRequest;
    }
    final request = _queryParallelWindowSupported();
    _parallelWindowSupportRequest = request;
    try {
      final supported = await request;
      _parallelWindowSupportCacheValue = supported;
      _parallelWindowSupportCacheTime = DateTime.now();
      return supported;
    } finally {
      if (identical(_parallelWindowSupportRequest, request)) {
        _parallelWindowSupportRequest = null;
      }
    }
  }

  static Future<bool> _queryParallelWindowSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isParallelWindowSupported') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// 打开指定媒体条目的详情页。
  static Future<bool> openItemDetail(
    String itemGuid, {
    BuildContext? context,
    String seriesGuid = '',
    Map<String, dynamic>? initialItemDetail,
  }) async {
    final normalizedGuid = itemGuid.trim();
    final normalizedSeriesGuid = seriesGuid.trim();
    if (normalizedGuid.isEmpty) return false;
    final routeName = DetailRoutePayloadStore.routeNameForItem(
      itemGuid: normalizedGuid,
      seriesGuid: normalizedSeriesGuid,
      initialItemDetail: initialItemDetail,
    );
    return AsyncActionGuard.run<bool>(
      'embedded_item_detail:$normalizedGuid:$normalizedSeriesGuid',
      settleDuration: const Duration(milliseconds: 450),
      action: () async {
        final paneHost = context == null
            ? null
            : PlayerPaneHostScope.maybeOf(context);
        if (paneHost != null) {
          return paneHost.openRoute(routeName);
        }
        if (Platform.isAndroid) {
          try {
            return await _channel
                    .invokeMethod<bool>('openItemDetail', <String, Object?>{
                      'itemGuid': normalizedGuid,
                      'seriesGuid': normalizedSeriesGuid,
                      'initialItemDetail': initialItemDetail,
                    }) ??
                false;
          } on PlatformException {
            return false;
          }
        }
        return false;
      },
    );
  }

  /// 打开指定季详情页。
  static Future<bool> openSeasonDetail({
    BuildContext? context,
    required String parentGuid,
    required String seriesTitle,
    required String backdropPath,
    required MediaLibraryItem seasonItem,
  }) async {
    final normalizedParentGuid = parentGuid.trim();
    final normalizedSeasonGuid = seasonItem.guid.trim();
    if (normalizedParentGuid.isEmpty || normalizedSeasonGuid.isEmpty) {
      return false;
    }
    final routeName = DetailRoutePayloadStore.routeNameForSeason(
      parentGuid: normalizedParentGuid,
      seriesTitle: seriesTitle,
      backdropPath: backdropPath,
      seasonItem: seasonItem.toJson(),
    );
    return AsyncActionGuard.run<bool>(
      'embedded_season_detail:$normalizedParentGuid:$normalizedSeasonGuid',
      settleDuration: const Duration(milliseconds: 450),
      action: () async {
        final paneHost = context == null
            ? null
            : PlayerPaneHostScope.maybeOf(context);
        if (paneHost != null) {
          return paneHost.openRoute(routeName);
        }
        try {
          return await _channel
                  .invokeMethod<bool>('openSeasonDetail', <String, Object?>{
                    'parentGuid': normalizedParentGuid,
                    'seriesTitle': seriesTitle.trim(),
                    'backdropPath': backdropPath.trim(),
                    'seasonItem': seasonItem.toJson(),
                  }) ??
              false;
        } on PlatformException {
          return false;
        }
      },
    );
  }

  /// 打开搜索页。
  static Future<bool> openSearch({BuildContext? context}) async {
    return _openRoute('/screen/search', context: context);
  }

  /// 打开收藏页。
  static Future<bool> openFavorites({BuildContext? context}) async {
    return _openRoute('/screen/favorites', context: context);
  }

  /// 打开设置页，并可跳转到指定子路由。
  static Future<bool> openSettings({
    BuildContext? context,
    String? destinationRoute,
  }) async {
    final normalizedDestination = destinationRoute?.trim() ?? '';
    final fallbackRoute = normalizedDestination.isEmpty
        ? '/screen/settings'
        : normalizedDestination;
    return AsyncActionGuard.run<bool>(
      'embedded_settings:$fallbackRoute',
      settleDuration: const Duration(milliseconds: 450),
      action: () async {
        final handled = await MainHostBridge.openPrimarySettings(
          destinationRoute: normalizedDestination.isEmpty
              ? null
              : normalizedDestination,
        );
        if (handled) return true;
        if (context == null || !context.mounted) return false;
        try {
          await Navigator.of(
            context,
            rootNavigator: true,
          ).pushNamed(fallbackRoute);
          return true;
        } catch (_) {
          return false;
        }
      },
    );
  }

  /// 打开下载页，并可指定初始页签。
  static Future<bool> openDownloads({
    BuildContext? context,
    String? tab,
  }) async {
    final normalizedTab = tab?.trim() ?? '';
    return _openRoute(
      Uri(
        path: '/screen/downloads',
        queryParameters: <String, String>{
          if (normalizedTab.isNotEmpty) 'tab': normalizedTab,
        },
      ).toString(),
      context: context,
    );
  }

  /// 打开指定下载分组的详情页。
  static Future<bool> openDownloadDetail({
    BuildContext? context,
    required String groupId,
    String? tab,
  }) async {
    final normalizedGroupId = groupId.trim();
    if (normalizedGroupId.isEmpty) return false;
    final normalizedTab = tab?.trim() ?? '';
    return _openRoute(
      Uri(
        path: '/screen/downloads/detail',
        queryParameters: <String, String>{
          'groupId': normalizedGroupId,
          if (normalizedTab.isNotEmpty) 'tab': normalizedTab,
        },
      ).toString(),
      context: context,
    );
  }

  /// 打开分类浏览页。
  static Future<bool> openCategory({
    BuildContext? context,
    required MediaItem category,
    List<String>? initialTypeTags,
  }) async {
    return _openRoute(
      Uri(
        path: '/screen/category',
        queryParameters: <String, String>{
          'category': jsonEncode(category.toJson()),
          if (initialTypeTags != null) 'types': jsonEncode(initialTypeTags),
        },
      ).toString(),
      context: context,
    );
  }

  /// 打开人物详情页。
  static Future<bool> openPersonDetail({
    BuildContext? context,
    required String personGuid,
    String initialName = '',
  }) async {
    final normalizedGuid = personGuid.trim();
    if (normalizedGuid.isEmpty) return false;
    return _openRoute(
      Uri(
        path: '/detail/person',
        queryParameters: <String, String>{
          'personGuid': normalizedGuid,
          if (initialName.trim().isNotEmpty) 'initialName': initialName.trim(),
        },
      ).toString(),
      context: context,
    );
  }

  /// 请求关闭右侧嵌入面板。
  static Future<bool> closeRightPane() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('closeRightPane') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 优先回退当前路由，否则关闭嵌入宿主容器。
  static Future<void> closeHostOrPop(BuildContext context) async {
    final navigator = Navigator.of(context);
    final paneHost = PlayerPaneHostScope.maybeOf(context);
    if (await navigator.maybePop()) {
      return;
    }
    if (paneHost != null) {
      if (await paneHost.backInPane()) return;
      if (await paneHost.closePane()) return;
    }
    await closeRightPane();
  }

  /// 向宿主同步当前并行浏览快照。
  static Future<void> reportBrowseSnapshot(
    ParallelBrowseSnapshot snapshot,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(
        'reportBrowseSnapshot',
        snapshot.toMap(),
      );
    } on PlatformException {
      // Ignore snapshot reporting failures; navigation should continue.
    }
  }

  static Future<bool> _openRoute(
    String routeName, {
    BuildContext? context,
  }) async {
    final normalizedRoute = routeName.trim();
    if (normalizedRoute.isEmpty) return false;
    return AsyncActionGuard.run<bool>(
      'embedded_route:$normalizedRoute',
      settleDuration: const Duration(milliseconds: 450),
      action: () async {
        final paneHost = context == null
            ? null
            : PlayerPaneHostScope.maybeOf(context);
        if (paneHost != null) {
          final handled = await paneHost.openRoute(normalizedRoute);
          if (handled) return true;
        }
        if (Platform.isAndroid) {
          try {
            final handled =
                await _channel.invokeMethod<bool>(
                  'openSecondaryRoute',
                  <String, Object?>{'routeName': normalizedRoute},
                ) ??
                false;
            if (handled) return true;
          } on PlatformException {
            // Fall through to local navigator push when a Flutter context exists.
          }
        }
        if (context == null || !context.mounted) return false;
        try {
          await Navigator.of(
            context,
            rootNavigator: true,
          ).pushNamed(normalizedRoute);
          return true;
        } catch (_) {
          return false;
        }
      },
    );
  }

  static Map<String, dynamic> _normalizeMap(Map<Object?, Object?> raw) {
    final normalized = <String, dynamic>{};
    raw.forEach((key, value) {
      normalized[key?.toString() ?? ''] = _normalizeValue(value);
    });
    return normalized;
  }

  static dynamic _normalizeValue(Object? value) {
    if (value is Map<Object?, Object?>) {
      return _normalizeMap(value);
    }
    if (value is List) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    return value;
  }
}
