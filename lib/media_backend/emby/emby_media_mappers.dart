import '../media_catalog.dart';
import '../media_image_ref.dart';
import '../media_item_card.dart';

/// Emby `BaseItemDto`（媒体库 View）→ 公共 [MediaCatalog]。
///
/// 飞牛私有结构不进公共层；Emby 字段只在本适配层映射。图片用 `?api_key=` 自鉴权 URL
/// （首页首光阶段；若被首页图片加载器破坏再退 headers 方案，见设计 §5）。
MediaCatalog mapEmbyView(
  Map<String, Object?> view, {
  required String serverUrl,
  required String token,
}) {
  final id = (view['Id'] ?? '').toString();
  final image = _primaryImage(view, serverUrl: serverUrl, token: token, id: id);
  return MediaCatalog(
    id: id,
    title: (view['Name'] ?? '').toString(),
    type: (view['CollectionType'] ?? view['Type'] ?? '').toString(),
    primaryImage: image,
    posters: image.isNotEmpty
        ? <MediaImageRef>[image]
        : const <MediaImageRef>[],
  );
}

/// Emby `BaseItemDto` → 公共 [MediaItemCard]（首页卡片 / 继续观看）。
MediaItemCard mapEmbyItemCard(
  Map<String, Object?> item, {
  required String serverUrl,
  required String token,
}) {
  final id = (item['Id'] ?? '').toString();
  final primary = _primaryImage(
    item,
    serverUrl: serverUrl,
    token: token,
    id: id,
  );
  return MediaItemCard(
    id: id,
    title: (item['Name'] ?? '').toString(),
    secondaryTitle: (item['SeriesName'] ?? '').toString(),
    type: (item['Type'] ?? '').toString(),
    primaryImage: primary,
    posters: primary.isNotEmpty
        ? <MediaImageRef>[primary]
        : const <MediaImageRef>[],
    backdropImage: _backdropImage(
      item,
      serverUrl: serverUrl,
      token: token,
      id: id,
    ),
    durationSeconds: _ticksToSeconds(item['RunTimeTicks']),
    watched: _played(item),
    rating: _ratingText(item['CommunityRating']),
    releaseDate: (item['PremiereDate'] ?? '').toString(),
    seasonNumber: _asInt(item['ParentIndexNumber']),
    episodeNumber: _asInt(item['IndexNumber']),
  );
}

MediaImageRef _primaryImage(
  Map<String, Object?> item, {
  required String serverUrl,
  required String token,
  required String id,
}) {
  final tags = item['ImageTags'];
  final tag = (tags is Map ? tags['Primary'] : null)?.toString() ?? '';
  if (id.isEmpty || tag.isEmpty) return MediaImageRef.empty;
  return MediaImageRef(
    url: '$serverUrl/Items/$id/Images/Primary?tag=$tag&api_key=$token',
  );
}

MediaImageRef _backdropImage(
  Map<String, Object?> item, {
  required String serverUrl,
  required String token,
  required String id,
}) {
  final tags = item['BackdropImageTags'];
  if (id.isEmpty || tags is! List || tags.isEmpty) return MediaImageRef.empty;
  final tag = tags.first?.toString() ?? '';
  if (tag.isEmpty) return MediaImageRef.empty;
  return MediaImageRef(
    url: '$serverUrl/Items/$id/Images/Backdrop?tag=$tag&api_key=$token',
  );
}

/// Emby `RunTimeTicks`（100ns 单位）→ 秒。
int _ticksToSeconds(Object? ticks) {
  final value = ticks is num ? ticks : num.tryParse('${ticks ?? ''}');
  if (value == null || value <= 0) return 0;
  return (value ~/ 10000000).toInt();
}

bool _played(Map<String, Object?> item) {
  final userData = item['UserData'];
  return userData is Map && userData['Played'] == true;
}

String _ratingText(Object? rating) {
  if (rating == null) return '';
  return rating.toString().trim();
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}
