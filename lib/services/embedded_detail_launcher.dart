import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/play_detail_data_loader.dart';
import '../models/media_item.dart';
import '../models/media_library_item.dart';
import '../models/play_info.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../services/play_stats/play_stats.dart';
import '../ui/player_pane_host_scope.dart';
import 'main_host_bridge.dart';
import 'parallel_browse_snapshot.dart';

class EmbeddedPlayerLaunchResult {
  final bool handled;
  final PlayDetailPlayerReturnData? data;

  const EmbeddedPlayerLaunchResult({required this.handled, this.data});
}

class EmbeddedDetailLauncher {
  static const MethodChannel _channel = MethodChannel('fly_player/embedding');

  const EmbeddedDetailLauncher._();

  static Future<bool> canOpenEmbeddedDetail() async {
    try {
      return await _channel.invokeMethod<bool>('canOpenEmbeddedDetail') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isParallelWindowSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isParallelWindowSupported') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> openItemDetail(
    String itemGuid, {
    BuildContext? context,
    String seriesGuid = '',
    Map<String, dynamic>? initialItemDetail,
  }) async {
    final normalizedGuid = itemGuid.trim();
    final normalizedSeriesGuid = seriesGuid.trim();
    if (normalizedGuid.isEmpty) return false;
    final routeName = Uri(
      path: '/detail/item',
      queryParameters: <String, String>{
        'itemGuid': normalizedGuid,
        if (normalizedSeriesGuid.isNotEmpty) 'seriesGuid': normalizedSeriesGuid,
        if (initialItemDetail != null)
          'initialItemDetail': jsonEncode(initialItemDetail),
      },
    ).toString();
    final paneHost = context == null
        ? null
        : PlayerPaneHostScope.maybeOf(context);
    if (paneHost != null) {
      return paneHost.openRoute(routeName);
    }
    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<bool>(
              'openSecondaryRoute',
              <String, String>{'routeName': routeName},
            ) ??
            false;
      } on PlatformException {
        return false;
      }
    }
    return false;
  }

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
    final paneHost = context == null
        ? null
        : PlayerPaneHostScope.maybeOf(context);
    if (paneHost != null) {
      return paneHost.openRoute(
        Uri(
          path: '/detail/season',
          queryParameters: <String, String>{
            'parentGuid': normalizedParentGuid,
            'seriesTitle': seriesTitle.trim(),
            'backdropPath': backdropPath.trim(),
            'seasonItem': jsonEncode(seasonItem.toJson()),
          },
        ).toString(),
      );
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
  }

  static Future<bool> openSearch({BuildContext? context}) async {
    return _openRoute('/screen/search', context: context);
  }

  static Future<bool> openFavorites({BuildContext? context}) async {
    return _openRoute('/screen/favorites', context: context);
  }

  static Future<bool> openSettings({
    BuildContext? context,
    String? destinationRoute,
  }) async {
    final normalizedDestination = destinationRoute?.trim() ?? '';
    final handled = await MainHostBridge.openPrimarySettings(
      destinationRoute: normalizedDestination.isEmpty
          ? null
          : normalizedDestination,
    );
    if (handled) return true;
    if (context == null || !context.mounted) return false;
    final fallbackRoute = normalizedDestination.isEmpty
        ? '/screen/settings'
        : normalizedDestination;
    try {
      await Navigator.of(context, rootNavigator: true).pushNamed(fallbackRoute);
      return true;
    } catch (_) {
      return false;
    }
  }

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

  static Future<EmbeddedPlayerLaunchResult> openFullscreenPlayer({
    BuildContext? context,
    required String title,
    required MpvMediaSource source,
    PlayInfoData? initialPlayInfo,
    PlayStartSource startSource = PlayStartSource.manual,
  }) async {
    if (context != null) {
      final paneHost = PlayerPaneHostScope.maybeOf(context);
      if (paneHost != null) {
        final handled = await paneHost.replacePlayerSource(
          title: title,
          source: source,
          initialPlayInfo: initialPlayInfo,
          startSource: startSource,
        );
        return EmbeddedPlayerLaunchResult(handled: handled);
      }
    }
    if (!Platform.isAndroid) {
      return const EmbeddedPlayerLaunchResult(handled: false);
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return const EmbeddedPlayerLaunchResult(handled: false);
    }
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'openFullscreenPlayer',
        <String, Object?>{
          'title': normalizedTitle,
          'source': source.toMap(),
          'initialPlayInfo': initialPlayInfo?.toJson(),
          'startSource': PlayStatsSqlMapper.startSourceToText(startSource),
        },
      );
      if (result == null) {
        return const EmbeddedPlayerLaunchResult(handled: true);
      }
      return EmbeddedPlayerLaunchResult(
        handled: true,
        data: PlayDetailPlayerReturnData.fromMap(_normalizeMap(result)),
      );
    } on PlatformException {
      return const EmbeddedPlayerLaunchResult(handled: false);
    }
  }

  static Future<bool> closeRightPane() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('closeRightPane') ?? false;
    } on PlatformException {
      return false;
    }
  }

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
