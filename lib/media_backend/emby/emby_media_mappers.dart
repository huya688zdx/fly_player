import '../detail/media_detail.dart';
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

/// Emby `BaseItemDto`（详情接口）→ 公共 [MediaDetail]（详情页展示）。
///
/// 只承载展示信息，不含播放接线（轨道 / 直链留播放入口）。题材 / 地区在 Emby 已是显示名，
/// 直接用，无需后端字典翻译。图片走 `?api_key=` 自鉴权直链（与卡片同款）。
MediaDetail mapEmbyItemDetail(
  Map<String, Object?> item, {
  required String serverUrl,
  required String token,
}) {
  final id = (item['Id'] ?? '').toString();
  final userData = item['UserData'];
  return MediaDetail(
    id: id,
    type: (item['Type'] ?? '').toString(),
    title: (item['Name'] ?? '').toString(),
    overview: (item['Overview'] ?? '').toString(),
    primaryImage: _primaryImage(
      item,
      serverUrl: serverUrl,
      token: token,
      id: id,
    ),
    backdropImage: _backdropImage(
      item,
      serverUrl: serverUrl,
      token: token,
      id: id,
    ),
    logoImage: _logoImage(item, serverUrl: serverUrl, token: token, id: id),
    rating: _ratingText(item['CommunityRating']),
    releaseDate: _releaseDate(item),
    runtimeMinutes: _ticksToSeconds(item['RunTimeTicks']) ~/ 60,
    durationSeconds: _ticksToSeconds(item['RunTimeTicks']),
    genreLabels: _stringList(item['Genres']),
    regionLabels: _stringList(item['ProductionLocations']),
    watched: _played(item),
    favorite: userData is Map && userData['IsFavorite'] == true,
    resumePositionSeconds: userData is Map
        ? _ticksToSeconds(userData['PlaybackPositionTicks'])
        : 0,
    externalIds: _externalIds(item['ProviderIds']),
    people: _people(item['People'], serverUrl: serverUrl, token: token),
  );
}

MediaImageRef _logoImage(
  Map<String, Object?> item, {
  required String serverUrl,
  required String token,
  required String id,
}) {
  final tags = item['ImageTags'];
  final tag = (tags is Map ? tags['Logo'] : null)?.toString() ?? '';
  if (id.isEmpty || tag.isEmpty) return MediaImageRef.empty;
  return MediaImageRef(
    url: '$serverUrl/Items/$id/Images/Logo?tag=$tag&api_key=$token',
  );
}

/// 发行日期：优先 `PremiereDate`，否则回退 `ProductionYear`（年份字符串）。
String _releaseDate(Map<String, Object?> item) {
  final premiere = (item['PremiereDate'] ?? '').toString().trim();
  if (premiere.isNotEmpty) return premiere;
  final year = item['ProductionYear'];
  if (year == null) return '';
  final yearText = year.toString().trim();
  return yearText == '0' ? '' : yearText;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((e) => (e ?? '').toString().trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

MediaExternalIds _externalIds(Object? providerIds) {
  if (providerIds is! Map) return const MediaExternalIds();
  String pick(List<String> keys) {
    for (final entry in providerIds.entries) {
      final key = entry.key?.toString().toLowerCase() ?? '';
      if (keys.contains(key)) {
        final value = (entry.value ?? '').toString().trim();
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  return MediaExternalIds(
    tmdbId: pick(<String>['tmdb']),
    imdbId: pick(<String>['imdb']),
  );
}

List<MediaDetailPerson> _people(
  Object? people, {
  required String serverUrl,
  required String token,
}) {
  if (people is! List) return const <MediaDetailPerson>[];
  final result = <MediaDetailPerson>[];
  for (final raw in people) {
    if (raw is! Map) continue;
    final person = Map<String, Object?>.from(raw);
    final id = (person['Id'] ?? '').toString();
    final name = (person['Name'] ?? '').toString().trim();
    if (name.isEmpty) continue;
    final tag = (person['PrimaryImageTag'] ?? '').toString().trim();
    final avatar = (id.isNotEmpty && tag.isNotEmpty)
        ? MediaImageRef(
            url: '$serverUrl/Items/$id/Images/Primary?tag=$tag&api_key=$token',
          )
        : MediaImageRef.empty;
    result.add(
      MediaDetailPerson(
        id: id,
        name: name,
        role: (person['Role'] ?? '').toString().trim(),
        department: (person['Type'] ?? '').toString().trim(),
        avatar: avatar,
      ),
    );
  }
  return result;
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
