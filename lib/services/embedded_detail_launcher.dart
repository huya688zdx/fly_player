import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/play_detail_data_loader.dart';
import '../models/media_item.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../models/media_library_item.dart';
import 'parallel_browse_snapshot.dart';

class EmbeddedPlayerLaunchResult {
  final bool handled;
  final PlayDetailPlayerReturnData? data;

  const EmbeddedPlayerLaunchResult({
    required this.handled,
    this.data,
  });
}

class EmbeddedDetailLauncher {
  static const MethodChannel _channel = MethodChannel('fly_player/embedding');

  const EmbeddedDetailLauncher._();

  static Future<bool> canOpenEmbeddedDetail() async {
    try {
      return await _channel.invokeMethod<bool>('canOpenEmbeddedDetail') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> openItemDetail(String itemGuid) async {
    final normalizedGuid = itemGuid.trim();
    if (normalizedGuid.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('openItemDetail', <String, String>{
            'itemGuid': normalizedGuid,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> openSeasonDetail({
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
    try {
      return await _channel.invokeMethod<bool>('openSeasonDetail', <String, Object?>{
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

  static Future<bool> openSearch() async {
    return _openRoute('/screen/search');
  }

  static Future<bool> openFavorites() async {
    return _openRoute('/screen/favorites');
  }

  static Future<bool> openSettings() async {
    return _openRoute('/screen/settings');
  }

  static Future<bool> openCategory({
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
    );
  }

  static Future<bool> openPersonDetail({
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
    );
  }

  static Future<EmbeddedPlayerLaunchResult> openFullscreenPlayer({
    required String title,
    required MpvMediaSource source,
  }) async {
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
    if (await navigator.maybePop()) {
      return;
    }
    await closeRightPane();
  }

  static Future<void> reportBrowseSnapshot(
    ParallelBrowseSnapshot snapshot,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('reportBrowseSnapshot', snapshot.toMap());
    } on PlatformException {
      // Ignore snapshot reporting failures; navigation should continue.
    }
  }

  static Future<bool> _openRoute(String routeName) async {
    if (!Platform.isAndroid) return false;
    final normalizedRoute = routeName.trim();
    if (normalizedRoute.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openSecondaryRoute',
            <String, Object?>{'routeName': normalizedRoute},
          ) ??
          false;
    } on PlatformException {
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
