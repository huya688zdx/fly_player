import 'dart:collection';

import 'package:flutter/services.dart';

/// 管理详情页路由参数中较大载荷的本地暂存与读取。
class DetailRoutePayloadStore {
  static const String payloadTokenKey = 'payloadToken';
  static const MethodChannel _embeddingChannel = MethodChannel(
    'fly_player/embedding',
  );
  static const int _maxLocalPayloads = 48;

  static final LinkedHashMap<String, Map<String, dynamic>> _localPayloads =
      LinkedHashMap<String, Map<String, dynamic>>();
  static int _nextTokenId = 0;

  const DetailRoutePayloadStore._();

  /// 为条目详情页构造路由名称，并在必要时缓存附加载荷。
  static String routeNameForItem({
    required String itemGuid,
    String seriesGuid = '',
    Map<String, dynamic>? initialItemDetail,
  }) {
    final normalizedItemGuid = itemGuid.trim();
    final normalizedSeriesGuid = seriesGuid.trim();
    final payloadToken = initialItemDetail == null || initialItemDetail.isEmpty
        ? null
        : _storeLocalPayload(<String, dynamic>{
            'initialItemDetail': Map<String, dynamic>.from(initialItemDetail),
          });
    return Uri(
      path: '/detail/item',
      queryParameters: <String, String>{
        'itemGuid': normalizedItemGuid,
        if (normalizedSeriesGuid.isNotEmpty) 'seriesGuid': normalizedSeriesGuid,
        if (payloadToken != null) payloadTokenKey: payloadToken,
      },
    ).toString();
  }

  /// 为季详情页构造路由名称，并在必要时缓存附加载荷。
  static String routeNameForSeason({
    required String parentGuid,
    required String seriesTitle,
    required String backdropPath,
    required Map<String, dynamic> seasonItem,
  }) {
    final normalizedParentGuid = parentGuid.trim();
    final normalizedSeasonGuid = seasonItem['guid']?.toString().trim() ?? '';
    final payloadToken = seasonItem.isEmpty
        ? null
        : _storeLocalPayload(<String, dynamic>{
            'seasonItem': Map<String, dynamic>.from(seasonItem),
          });
    return Uri(
      path: '/detail/season',
      queryParameters: <String, String>{
        'parentGuid': normalizedParentGuid,
        'seriesTitle': seriesTitle.trim(),
        'backdropPath': backdropPath.trim(),
        if (normalizedSeasonGuid.isNotEmpty) 'seasonGuid': normalizedSeasonGuid,
        if (payloadToken != null) payloadTokenKey: payloadToken,
      },
    ).toString();
  }

  /// 从路由地址中提取载荷令牌。
  static String? payloadTokenFromUri(Uri uri) {
    final token = uri.queryParameters[payloadTokenKey]?.trim() ?? '';
    return token.isEmpty ? null : token;
  }

  /// 根据载荷令牌读取先前缓存的详情页附加数据。
  static Future<Map<String, dynamic>?> readPayload(String token) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      return null;
    }
    final localPayload = _readLocalPayload(normalizedToken);
    if (localPayload != null) {
      return localPayload;
    }
    try {
      final raw = await _embeddingChannel.invokeMethod<Map<Object?, Object?>>(
        'readDetailRoutePayload',
        <String, Object?>{'token': normalizedToken},
      );
      if (raw == null || raw.isEmpty) {
        return null;
      }
      return _normalizeMap(raw);
    } on PlatformException {
      return null;
    }
  }

  static Map<String, dynamic>? readCachedPayload(String token) {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      return null;
    }
    return _readLocalPayload(normalizedToken);
  }

  static String _storeLocalPayload(Map<String, dynamic> payload) {
    final token =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
        '${(_nextTokenId++).toRadixString(16)}';
    _localPayloads[token] = payload;
    while (_localPayloads.length > _maxLocalPayloads) {
      _localPayloads.remove(_localPayloads.keys.first);
    }
    return token;
  }

  static Map<String, dynamic>? _readLocalPayload(String token) {
    final payload = _localPayloads.remove(token);
    if (payload == null) {
      return null;
    }
    _localPayloads[token] = payload;
    return payload;
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
