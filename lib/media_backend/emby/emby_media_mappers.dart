import '../detail/media_detail.dart';
import '../detail/media_episode_summary.dart';
import '../detail/media_season_summary.dart';
import '../detail/media_source_info.dart';
import '../detail/media_source_version.dart';
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
    seriesId: (item['SeriesId'] ?? '').toString(),
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

/// Emby 季 `BaseItemDto`（`/Shows/{id}/Seasons` 列表项）→ 公共 [MediaSeasonSummary]。
///
/// Emby 只入库已有内容，故 `ChildCount`（该季在库集数）同时充当总数与本地数。图源走
/// `?api_key=` 自鉴权直链（与卡片同款）。
MediaSeasonSummary mapEmbySeason(
  Map<String, Object?> season, {
  required String serverUrl,
  required String token,
}) {
  final id = (season['Id'] ?? '').toString();
  final childCount = _asInt(season['ChildCount']);
  final recursiveCount = _asInt(season['RecursiveItemCount']);
  final episodeCount = childCount > 0 ? childCount : recursiveCount;
  return MediaSeasonSummary(
    id: id,
    title: (season['Name'] ?? '').toString(),
    seasonNumber: _asInt(season['IndexNumber']),
    numberOfEpisodes: episodeCount,
    localNumberOfEpisodes: episodeCount,
    primaryImage: _primaryImage(
      season,
      serverUrl: serverUrl,
      token: token,
      id: id,
    ),
  );
}

/// Emby 集 `BaseItemDto`（`/Shows/{id}/Episodes` 列表项）→ 公共 [MediaEpisodeSummary]。
MediaEpisodeSummary mapEmbyEpisode(
  Map<String, Object?> episode, {
  required String serverUrl,
  required String token,
}) {
  final id = (episode['Id'] ?? '').toString();
  final userData = episode['UserData'];
  return MediaEpisodeSummary(
    id: id,
    title: (episode['Name'] ?? '').toString(),
    seasonNumber: _asInt(episode['ParentIndexNumber']),
    episodeNumber: _asInt(episode['IndexNumber']),
    overview: (episode['Overview'] ?? '').toString(),
    airDate: (episode['PremiereDate'] ?? '').toString(),
    durationSeconds: _ticksToSeconds(episode['RunTimeTicks']),
    watched: _played(episode),
    resumePositionSeconds: userData is Map
        ? _ticksToSeconds(userData['PlaybackPositionTicks'])
        : 0,
    primaryImage: _primaryImage(
      episode,
      serverUrl: serverUrl,
      token: token,
      id: id,
    ),
  );
}

/// Emby `BaseItemDto`（含 `MediaSources`）→ 中立 [MediaSourceInfo]（详情页文件 / 视频信息）。
///
/// 取第一个 `MediaSource` 的 Path/Container/Size + 条目 `DateCreated`，并把各 `MediaStream`
/// 拼成展示摘要行（视频：分辨率/编码/码率/位深；音频：DisplayTitle + 编码/布局/采样率/码率；
/// 字幕：DisplayTitle + 编码/外挂）。按设计取舍掉用户配置/等级/长宽比/像素格式等冗余字段。
MediaSourceInfo mapEmbySourceInfo(Map<String, Object?> item) {
  final sources = item['MediaSources'];
  Map<String, Object?>? source;
  if (sources is List && sources.isNotEmpty && sources.first is Map) {
    source = Map<String, Object?>.from(sources.first as Map);
  }
  final addedDate = (item['DateCreated'] ?? '').toString().trim();
  if (source == null) {
    return MediaSourceInfo(addedDate: addedDate);
  }
  return _sourceInfoFromSource(source, addedDate);
}

/// Emby `BaseItemDto`（含 `MediaSources`）→ 中立 [MediaSourceVersion] 列表（详情页版本 /
/// 音轨 / 字幕选择器）。把**每个** `MediaSource` 映射成一个可选版本，连同其音轨 / 字幕轨。
///
/// 与 [mapEmbySourceInfo]（只取首源的展示信息）的差别：保留所有源、并额外抽出可选轨道
/// （带稳定 id = stream `Index`）+ 版本默认音轨 / 字幕。展示信息部分复用同一映射。
List<MediaSourceVersion> mapEmbySourceVersions(Map<String, Object?> item) {
  final sources = item['MediaSources'];
  if (sources is! List) return const <MediaSourceVersion>[];
  final addedDate = (item['DateCreated'] ?? '').toString().trim();
  final versions = <MediaSourceVersion>[];
  for (final raw in sources) {
    if (raw is! Map) continue;
    final source = Map<String, Object?>.from(raw);
    final id = (source['Id'] ?? '').toString();
    final info = _sourceInfoFromSource(source, addedDate);

    final rawStreams = source['MediaStreams'];
    final audioTracks = <MediaTrackOption>[];
    final subtitleTracks = <MediaTrackOption>[];
    String videoResolution = '';
    String videoRange = '';
    if (rawStreams is List) {
      for (final rawStream in rawStreams) {
        if (rawStream is! Map) continue;
        final stream = Map<String, Object?>.from(rawStream);
        final index = _asInt(stream['Index']);
        switch ((stream['Type'] ?? '').toString().toLowerCase()) {
          case 'video':
            if (videoResolution.isEmpty) {
              final height = _asInt(stream['Height']);
              if (height > 0) videoResolution = '${height}p';
              videoRange = (stream['VideoRange'] ?? '').toString().trim();
            }
            break;
          case 'audio':
            audioTracks.add(_trackOption(stream, index, isSubtitle: false));
            break;
          case 'subtitle':
            subtitleTracks.add(_trackOption(stream, index, isSubtitle: true));
            break;
        }
      }
    }

    final name = (source['Name'] ?? '').toString().trim();
    final label = videoResolution.isNotEmpty
        ? videoResolution
        : (name.isNotEmpty ? name : '源 ${versions.length + 1}');
    final badges = <String>[
      if (videoResolution.isNotEmpty) videoResolution,
      if (videoRange.isNotEmpty && videoRange.toUpperCase() != 'SDR')
        videoRange,
    ];

    versions.add(
      MediaSourceVersion(
        id: id,
        label: label,
        badges: badges,
        info: info,
        audioTracks: audioTracks,
        subtitleTracks: subtitleTracks,
        defaultAudioId: _streamIndexId(source['DefaultAudioStreamIndex']),
        defaultSubtitleId: _streamIndexId(source['DefaultSubtitleStreamIndex']),
        durationSeconds: _ticksToSeconds(source['RunTimeTicks']),
      ),
    );
  }
  return versions;
}

/// Emby `MediaSource` → 中立 [MediaSourceInfo]（单源展示信息）。
MediaSourceInfo _sourceInfoFromSource(
  Map<String, Object?> source,
  String addedDate,
) {
  final path = (source['Path'] ?? '').toString().trim();
  final container = (source['Container'] ?? '').toString().trim();
  final size = _asInt(source['Size']);
  final rawStreams = source['MediaStreams'];
  final streams = <MediaSourceStream>[];
  if (rawStreams is List) {
    for (final raw in rawStreams) {
      if (raw is! Map) continue;
      final stream = Map<String, Object?>.from(raw);
      switch ((stream['Type'] ?? '').toString().toLowerCase()) {
        case 'video':
          streams.add(_videoStream(stream));
          break;
        case 'audio':
          streams.add(_audioStream(stream));
          break;
        case 'subtitle':
          streams.add(_subtitleStream(stream));
          break;
      }
    }
  }
  return MediaSourceInfo(
    path: path,
    container: container,
    sizeBytes: size,
    addedDate: addedDate,
    streams: streams,
  );
}

/// Emby 音轨 / 字幕 `MediaStream` → 中立可选 [MediaTrackOption]（id=stream `Index`）。
MediaTrackOption _trackOption(
  Map<String, Object?> stream,
  int index, {
  required bool isSubtitle,
}) {
  final display = (stream['DisplayTitle'] ?? '').toString().trim();
  final language = (stream['Language'] ?? '').toString().trim();
  final title = (stream['Title'] ?? '').toString().trim();
  final codec = (stream['Codec'] ?? '').toString().trim().toUpperCase();
  final label = display.isNotEmpty
      ? display
      : <String>[
          if (language.isNotEmpty) language,
          if (title.isNotEmpty) title,
          if (codec.isNotEmpty) codec,
        ].join(' ').trim();
  final external = stream['IsExternal'] == true;
  final summary = isSubtitle
      ? (external ? '外挂' : '')
      : <String>[
          if (codec.isNotEmpty) codec,
          if ((stream['ChannelLayout'] ?? '').toString().trim().isNotEmpty)
            (stream['ChannelLayout']).toString().trim(),
        ].join(' · ');
  return MediaTrackOption(
    id: '$index',
    label: label.isNotEmpty ? label : '#$index',
    summary: summary,
    isExternal: external,
  );
}

/// Emby `Default*StreamIndex` → 轨道 id 串；缺失 / 负值（无 / 关闭）返回空。
String _streamIndexId(Object? value) {
  final index = value is int ? value : int.tryParse('${value ?? ''}');
  if (index == null || index < 0) return '';
  return '$index';
}

MediaSourceStream _videoStream(Map<String, Object?> stream) {
  final display = (stream['DisplayTitle'] ?? '').toString().trim();
  final height = _asInt(stream['Height']);
  final res = height > 0 ? '${height}p' : '';
  final codec = (stream['Codec'] ?? '').toString().trim().toUpperCase();
  final label = display.isNotEmpty
      ? display
      : <String>[
          if (res.isNotEmpty) res,
          if (codec.isNotEmpty) codec,
        ].join(' ');
  final bit = _asInt(stream['BitDepth']);
  final summary = <String>[
    if (_mbps(stream['BitRate']).isNotEmpty) _mbps(stream['BitRate']),
    if (bit > 0) '$bit bit',
  ].join(' · ');
  return MediaSourceStream(
    type: MediaStreamType.video,
    label: label,
    summary: summary,
  );
}

MediaSourceStream _audioStream(Map<String, Object?> stream) {
  final display = (stream['DisplayTitle'] ?? '').toString().trim();
  final codec = (stream['Codec'] ?? '').toString().trim().toUpperCase();
  final layout = (stream['ChannelLayout'] ?? '').toString().trim();
  final rate = _asInt(stream['SampleRate']);
  // DisplayTitle 已含语言/编码/布局；label 用它，summary 只补采样率（DisplayTitle 通常没有）。
  final label = display.isNotEmpty
      ? display
      : <String>[
          if (codec.isNotEmpty) codec,
          if (layout.isNotEmpty) layout,
        ].join(' ');
  final summary = rate > 0 ? '$rate Hz' : '';
  return MediaSourceStream(
    type: MediaStreamType.audio,
    label: label,
    summary: summary,
  );
}

MediaSourceStream _subtitleStream(Map<String, Object?> stream) {
  final display = (stream['DisplayTitle'] ?? '').toString().trim();
  final codec = (stream['Codec'] ?? '').toString().trim().toUpperCase();
  final external = stream['IsExternal'] == true;
  final label = display.isNotEmpty ? display : codec;
  final summary = external ? '外挂' : '';
  return MediaSourceStream(
    type: MediaStreamType.subtitle,
    label: label,
    summary: summary,
  );
}

/// 码率（bps）→ `x.xx mbps`，无效返回空串。
String _mbps(Object? bitRate) {
  final value = _asInt(bitRate);
  if (value <= 0) return '';
  return '${(value / 1000000.0).toStringAsFixed(2)} mbps';
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
