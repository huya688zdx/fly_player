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
  final userData = item['UserData'];
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
    resumePositionSeconds: userData is Map
        ? _ticksToSeconds(userData['PlaybackPositionTicks'])
        : 0,
    rating: _ratingText(item['CommunityRating']),
    releaseDate: (item['PremiereDate'] ?? '').toString(),
    seasonNumber: _asInt(item['ParentIndexNumber']),
    episodeNumber: _asInt(item['IndexNumber']),
    resolutions: _cardResolutions(item),
  );
}

/// 卡片清晰度角标：取首条视频流高 → `1080p`/`4K` 等。需查询带上 `MediaStreams` 字段，
/// 缺失时返回空（不显示角标）。
List<String> _cardResolutions(Map<String, Object?> item) {
  final sources = item['MediaSources'];
  List? streams;
  if (sources is List && sources.isNotEmpty && sources.first is Map) {
    streams = (sources.first as Map)['MediaStreams'] as List?;
  }
  streams ??= item['MediaStreams'] as List?;
  if (streams == null) return const <String>[];
  for (final raw in streams) {
    if (raw is! Map) continue;
    if ((raw['Type'] ?? '').toString().toLowerCase() != 'video') continue;
    final label = _resolutionTier(_asInt(raw['Width']), _asInt(raw['Height']));
    return label.isEmpty ? const <String>[] : <String>[label];
  }
  return const <String>[];
}

/// 分辨率归档到 app 徽章体系支持的档位：4K / 2K / 1080 / 720 / 480。
///
/// 优先按**宽度**判定：宽银幕 scope 内容高度偏低（如 4K 蓝光 3840×1604，宽 3840 仍是 4K，
/// 按高度会误判成 2K），按宽度才稳。宽度缺失时用高度兜底。无法判定返回空（不显角标 / 用源名）。
String _resolutionTier(int width, int height) {
  if (width >= 3000 || height >= 2000) return '4K';
  if (width >= 2000 || height >= 1400) return '2K';
  if (width >= 1800 || height >= 1000) return '1080';
  if (width >= 1100 || height >= 700) return '720';
  if (width >= 600 || height >= 400) return '480';
  return '';
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
    // 剧集面包屑（剧名 · 季 · 集）所需：Emby 单集 BaseItemDto 携带 SeriesName/
    // ParentIndexNumber(季)/IndexNumber(集)。非剧集时缺省 → 空/0，详情头部不显示面包屑。
    parentTitle: (item['SeriesName'] ?? '').toString(),
    seasonNumber: _asInt(item['ParentIndexNumber']),
    episodeNumber: _asInt(item['IndexNumber']),
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
    // 地区保持原样（Emby 给英文国名 / ISO code）；本地化在有 l10n context 的渲染层做
    // （mapper 无 AppLocalizations，且中文文案须走 l10n 不可写死）。见 RegionNameLocalizer。
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
    resolutions: _cardResolutions(episode),
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
              videoResolution = _resolutionTier(
                _asInt(stream['Width']),
                _asInt(stream['Height']),
              );
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
        : (name.isNotEmpty
              ? name
              : '$mediaSourceFallbackLabelPrefix${versions.length + 1}');
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
      ? (external ? mediaExternalSubtitleSummaryToken : '')
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
  final width = _asInt(stream['Width']);
  final height = _asInt(stream['Height']);
  final res = _resolutionTier(width, height);
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
  final range = (stream['VideoRange'] ?? '').toString().trim();
  final interlaced = stream['IsInterlaced'] == true;
  return MediaSourceStream(
    type: MediaStreamType.video,
    label: label,
    summary: summary,
    fields: <MediaInfoField>[
      MediaInfoField(MediaInfoFieldKey.encoder, codec),
      MediaInfoField(
        MediaInfoFieldKey.profile,
        (stream['Profile'] ?? '').toString().trim(),
      ),
      MediaInfoField(MediaInfoFieldKey.level, _levelText(stream['Level'])),
      MediaInfoField(
        MediaInfoFieldKey.resolution,
        (width > 0 && height > 0) ? '$width * $height' : '',
      ),
      MediaInfoField(
        MediaInfoFieldKey.aspectRatio,
        (stream['AspectRatio'] ?? '').toString().trim(),
      ),
      const MediaInfoField.divider(),
      MediaInfoField(MediaInfoFieldKey.interlaced, _yesNoRaw(!interlaced)),
      MediaInfoField(
        MediaInfoFieldKey.frameRate,
        _frameRateText(stream['RealFrameRate'] ?? stream['AverageFrameRate']),
      ),
      MediaInfoField(MediaInfoFieldKey.bitrate, _bitrate(stream['BitRate'])),
      MediaInfoField(MediaInfoFieldKey.range, range),
      MediaInfoField(
        MediaInfoFieldKey.colorPrimaries,
        (stream['ColorPrimaries'] ?? '').toString().trim(),
      ),
      const MediaInfoField.divider(),
      MediaInfoField(
        MediaInfoFieldKey.colorSpace,
        (stream['ColorSpace'] ?? '').toString().trim(),
      ),
      MediaInfoField(
        MediaInfoFieldKey.colorTransfer,
        (stream['ColorTransfer'] ?? '').toString().trim(),
      ),
      MediaInfoField(MediaInfoFieldKey.bitDepth, bit > 0 ? '$bit bit' : ''),
      MediaInfoField(
        MediaInfoFieldKey.pixelFormat,
        (stream['PixelFormat'] ?? '').toString().trim(),
      ),
      MediaInfoField(
        MediaInfoFieldKey.refs,
        _asInt(stream['RefFrames']) > 0 ? '${_asInt(stream['RefFrames'])}' : '',
      ),
    ],
  );
}

MediaSourceStream _audioStream(Map<String, Object?> stream) {
  final display = (stream['DisplayTitle'] ?? '').toString().trim();
  final codec = (stream['Codec'] ?? '').toString().trim().toUpperCase();
  final layout = (stream['ChannelLayout'] ?? '').toString().trim();
  final rate = _asInt(stream['SampleRate']);
  final channels = _asInt(stream['Channels']);
  final language = (stream['Language'] ?? '').toString().trim();
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
    fields: <MediaInfoField>[
      MediaInfoField(MediaInfoFieldKey.language, language),
      MediaInfoField(MediaInfoFieldKey.encoder, codec),
      MediaInfoField(
        MediaInfoFieldKey.profile,
        (stream['Profile'] ?? '').toString().trim(),
      ),
      const MediaInfoField.divider(),
      MediaInfoField(
        MediaInfoFieldKey.channels,
        channels > 0 ? '$channels ch' : '',
      ),
      MediaInfoField(MediaInfoFieldKey.sampleRate, rate > 0 ? '$rate Hz' : ''),
      MediaInfoField(MediaInfoFieldKey.bitrate, _bitrate(stream['BitRate'])),
      const MediaInfoField.divider(),
      MediaInfoField(MediaInfoFieldKey.layout, layout),
      MediaInfoField(
        MediaInfoFieldKey.isDefault,
        _yesNoRaw(stream['IsDefault'] == true),
      ),
    ],
  );
}

MediaSourceStream _subtitleStream(Map<String, Object?> stream) {
  final display = (stream['DisplayTitle'] ?? '').toString().trim();
  final codec = (stream['Codec'] ?? '').toString().trim().toUpperCase();
  final external = stream['IsExternal'] == true;
  final language = (stream['Language'] ?? '').toString().trim();
  final label = display.isNotEmpty ? display : codec;
  final summary = external ? mediaExternalSubtitleSummaryToken : '';
  return MediaSourceStream(
    type: MediaStreamType.subtitle,
    label: label,
    summary: summary,
    fields: <MediaInfoField>[
      MediaInfoField(MediaInfoFieldKey.language, language),
      MediaInfoField(MediaInfoFieldKey.encoder, codec.toLowerCase()),
      const MediaInfoField.divider(),
      MediaInfoField(
        MediaInfoFieldKey.isDefault,
        _yesNoRaw(stream['IsDefault'] == true),
      ),
      MediaInfoField(
        MediaInfoFieldKey.forced,
        _yesNoRaw(stream['IsForced'] == true),
      ),
      const MediaInfoField.divider(),
      MediaInfoField(MediaInfoFieldKey.external, _yesNoRaw(external)),
    ],
  );
}

/// 是/否的中立标记值（`1`/`0`）；UI 层据此渲染本地化的「是/否」。空值场景用空串。
String _yesNoRaw(bool value) => value ? '1' : '0';

String _levelText(Object? level) {
  final value = _asInt(level);
  if (value <= 0) return '';
  // Emby 的 Level 是放大整数（如 51 表示 5.1）；保持与 ffprobe 习惯一致地原样展示。
  return '$value';
}

String _frameRateText(Object? rate) {
  final value = rate is num
      ? rate.toDouble()
      : double.tryParse('${rate ?? ''}');
  if (value == null || value <= 0) return '';
  return '${value.toStringAsFixed(3)} fps';
}

/// 码率（bps）→ `x.xx mbps`（≥1Mbps）或 `x kbps`，与详情明细页观感一致。
String _bitrate(Object? bitRate) {
  final value = _asInt(bitRate);
  if (value <= 0) return '';
  if (value >= 1000000) return '${(value / 1000000.0).toStringAsFixed(2)} mbps';
  return '${(value / 1000.0).toStringAsFixed(0)} kbps';
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
    url: _imageUrl(
      serverUrl: serverUrl,
      id: id,
      kind: 'Logo',
      tag: tag,
      token: token,
      // 详情页 logo 显示高度 ≤124，横条图限宽 800 足够高分屏。
      maxWidth: 800,
    ),
    headers: _imageHeaders(token),
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
            url: _imageUrl(
              serverUrl: serverUrl,
              id: id,
              kind: 'Primary',
              tag: tag,
              token: token,
              // 演职员头像卡片显示宽度 ≤180 逻辑像素。
              maxWidth: 360,
            ),
            headers: _imageHeaders(token),
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
  if (id.isEmpty) return MediaImageRef.empty;
  if (tag.isNotEmpty) {
    return MediaImageRef(
      url: _imageUrl(
        serverUrl: serverUrl,
        id: id,
        kind: 'Primary',
        tag: tag,
        token: token,
        // 海报卡片/详情竖图，对齐飞牛管线的 w≤400 量级。
        maxWidth: 400,
      ),
      headers: _imageHeaders(token),
    );
  }
  // BoxSet 常无自有 Primary 图（合集封面多为成员海报合成 / folder.jpg，服务端不一定下发
  // Primary tag）：回退 Thumb → 首张 Backdrop，避免合集卡整排占位图。其它类型维持无图即空
  // （不猜 URL，防成片 404）。
  if ((item['Type'] ?? '').toString() != 'BoxSet') return MediaImageRef.empty;
  final thumbTag = (tags is Map ? tags['Thumb'] : null)?.toString() ?? '';
  if (thumbTag.isNotEmpty) {
    return MediaImageRef(
      url: _imageUrl(
        serverUrl: serverUrl,
        id: id,
        kind: 'Thumb',
        tag: thumbTag,
        token: token,
        maxWidth: 400,
      ),
      headers: _imageHeaders(token),
    );
  }
  final backdrops = item['BackdropImageTags'];
  final backdropTag = (backdrops is List && backdrops.isNotEmpty)
      ? (backdrops.first?.toString() ?? '')
      : '';
  if (backdropTag.isEmpty) return MediaImageRef.empty;
  return MediaImageRef(
    url: _imageUrl(
      serverUrl: serverUrl,
      id: id,
      kind: 'Backdrop',
      tag: backdropTag,
      token: token,
      maxWidth: 400,
    ),
    headers: _imageHeaders(token),
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
    url: _imageUrl(
      serverUrl: serverUrl,
      id: id,
      kind: 'Backdrop',
      tag: tag,
      token: token,
      // 详情背景 hero 大图，对齐飞牛管线的 w=1200 上限。
      maxWidth: 1280,
    ),
    headers: _imageHeaders(token),
  );
}

String _imageUrl({
  required String serverUrl,
  required String id,
  required String kind,
  required String tag,
  required String token,
  required int maxWidth,
}) {
  final base = serverUrl.replaceAll(RegExp(r'/$'), '');
  final query = StringBuffer('tag=${Uri.encodeQueryComponent(tag)}');
  // 必须限制服务端出图尺寸：不带 maxWidth 时 Emby 返回原图（backdrop 常见
  // 1920~3840 宽、数 MB JPEG），下载/解码/纹理上传恰落在进场转场窗口内。
  // 注意该 URL 同时是 Flutter ImageCache 的缓存键，预取与展示必须同参。
  query.write('&maxWidth=$maxWidth&quality=90');
  // token 必须进查询串（`api_key=`），不能只放 [MediaImageRef.headers]：历史 UI 管线
  // （首页/收藏/搜索卡片等 [MediaLibraryItem] 链路）只透传 URL 字符串会丢 headers，
  // 且海报组件在 NAS token 为空时仅凭 `api_key=` 识别自鉴权 URL 放行加载。
  final key = token.trim();
  if (key.isNotEmpty) {
    query.write('&api_key=${Uri.encodeQueryComponent(key)}');
  }
  return '$base/Items/$id/Images/$kind?$query';
}

Map<String, String> _imageHeaders(String token) {
  final normalized = token.trim();
  if (normalized.isEmpty) return const <String, String>{};
  return <String, String>{'X-Emby-Token': normalized};
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
