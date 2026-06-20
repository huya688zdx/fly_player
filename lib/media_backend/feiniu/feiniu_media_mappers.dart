import '../../api/item_list_request.dart';
import '../../models/media_item.dart';
import '../../models/media_library_item.dart';
import '../filter/media_catalog_filter.dart';
import '../media_catalog.dart';
import '../media_image_ref.dart';
import '../media_item_card.dart';

/// 把飞牛媒体库入口 [MediaItem] 映射为公共 [MediaCatalog]。
MediaCatalog mapFeiniuCatalog(MediaItem item) {
  return MediaCatalog(
    id: item.id,
    title: item.name,
    type: item.type ?? '',
    primaryImage: MediaImageRef(url: item.path ?? ''),
    posters: item.posters
        .map((path) => MediaImageRef(url: path))
        .toList(growable: false),
  );
}

/// 把飞牛条目 [MediaLibraryItem] 映射为统一富卡片模型 [MediaItemCard]。
///
/// 无损搬运首页 / 搜索 / 分类卡片实际消费的全部展示字段：原始 `title` + `tvTitle`
/// （映射为 secondaryTitle，由 displayTitle getter 复刻飞牛回退语义）、多候选封面、
/// 年份区间所需的首播 / 完结日期、本地季集计数、person 作品数、清晰度角标等。
/// 滤镜 / 句柄等飞牛私有概念不进入公共模型。
MediaItemCard mapFeiniuItemCard(MediaLibraryItem item) {
  return MediaItemCard(
    id: item.guid,
    title: item.title,
    secondaryTitle: item.tvTitle,
    type: item.type,
    primaryImage: MediaImageRef(url: item.poster),
    posters: item.posterList
        .map((path) => MediaImageRef(url: path))
        .toList(growable: false),
    durationSeconds: item.duration,
    watched: item.watched != 0,
    rating: item.voteAverage,
    releaseDate: item.releaseDate,
    firstAirDate: item.firstAirDate,
    lastAirDate: item.lastAirDate,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    numberOfSeasons: item.numberOfSeasons,
    numberOfEpisodes: item.numberOfEpisodes,
    localNumberOfSeasons: item.localNumberOfSeasons,
    localNumberOfEpisodes: item.localNumberOfEpisodes,
    numberOfItem: item.numberOfItem,
    posterWidth: item.posterWidth,
    posterHeight: item.posterHeight,
    resolutions: item.resolutions,
  );
}

/// 飞牛分类页支持的排序字段（顺序与原生分类页一致）。
const List<MediaSortOption> _feiniuSortOptions = <MediaSortOption>[
  MediaSortOption(field: 'create_time'),
  MediaSortOption(field: 'release_date'),
  MediaSortOption(field: 'title'),
  MediaSortOption(field: 'vote_average'),
];

List<MediaFilterOption> _filterOptions(List<dynamic>? raw) {
  if (raw == null || raw.isEmpty) return const <MediaFilterOption>[];
  return raw
      .map((value) => MediaFilterOption(value: '$value'))
      .toList(growable: false);
}

/// 把飞牛标签接口数据合成公共筛选 schema。
///
/// 维度顺序、提交键名（注意年代/清晰度的 options 源键是复数 `decades` /
/// `resolutions`，提交键是单数 `decade` / `resolution`）与原生分类页保持一致。
/// [genresMap] / [regionNames] 作为数据字典下发，由 UI localizer 把 genre id /
/// 地区 code 还原为显示名；维度内 [MediaFilterOption.label] 一律留空。
MediaCatalogFilterSchema mapFeiniuFilterSchema({
  required Map<String, List<dynamic>> tagOptions,
  required Map<int, String> genresMap,
  required Map<String, String> regionNames,
}) {
  final dimensions = <MediaFilterDimension>[
    const MediaFilterDimension(
      key: 'type',
      kind: MediaFilterDimensionKind.mediaType,
      options: <MediaFilterOption>[
        MediaFilterOption(value: 'Movie'),
        MediaFilterOption(value: 'TV'),
      ],
    ),
    MediaFilterDimension(
      key: 'genres',
      kind: MediaFilterDimensionKind.genre,
      options: _filterOptions(tagOptions['genres']),
    ),
    MediaFilterDimension(
      key: 'locate',
      kind: MediaFilterDimensionKind.region,
      options: _filterOptions(tagOptions['locate']),
    ),
    MediaFilterDimension(
      key: 'decade',
      kind: MediaFilterDimensionKind.decade,
      options: _filterOptions(tagOptions['decades']),
    ),
    MediaFilterDimension(
      key: 'resolution',
      kind: MediaFilterDimensionKind.resolution,
      options: _filterOptions(tagOptions['resolutions']),
    ),
    MediaFilterDimension(
      key: 'color_range',
      kind: MediaFilterDimensionKind.colorRange,
      options: _filterOptions(tagOptions['color_range']),
    ),
    MediaFilterDimension(
      key: 'audio_type',
      kind: MediaFilterDimensionKind.audioType,
      options: _filterOptions(tagOptions['audio_type']),
    ),
    MediaFilterDimension(
      key: 'recognition_status',
      kind: MediaFilterDimensionKind.recognitionStatus,
      options: _filterOptions(tagOptions['recognition_status']),
    ),
    const MediaFilterDimension(
      key: 'watched',
      kind: MediaFilterDimensionKind.watched,
      options: <MediaFilterOption>[
        MediaFilterOption(value: '1'),
        MediaFilterOption(value: '0'),
      ],
    ),
  ];

  return MediaCatalogFilterSchema(
    dimensions: dimensions,
    sortOptions: _feiniuSortOptions,
    genreNames: genresMap.map((id, name) => MapEntry('$id', name)),
    regionNames: regionNames,
  );
}

/// 把公共筛选查询回填为飞牛 [ItemListRequest]。
///
/// 类型回填规则与原生分类页 `_buildRequest` 一致：`type` 进 [ItemListRequest.typeTags]
/// （空选择时回退到全类型）；`genres` / `decade` 还原为数值（飞牛 `getTagList` 下发的
/// genre id 与年代均为 int，原生分类页直接发 int 而非字符串，转字符串会改变 `/item/list`
/// 线格式，故此处对可解析为整数的值还原为 int，`Recent` 等非数值年代保持字符串）；
/// 其余维度按字符串原样提交（`recognition_status` / `watched` 原生分类页本就显式字符串化）。
ItemListRequest mapMediaQueryToItemListRequest(MediaCatalogQuery query) {
  final selection = query.selection;

  final typeSelection = selection['type'] ?? const <String>[];
  final typeTags = typeSelection.isNotEmpty
      ? List<String>.from(typeSelection)
      : const <String>['Movie', 'TV', 'Directory', 'Video'];

  final tags = <String, dynamic>{};
  // genres / decade：飞牛后端按 int 下发与回填，数值原样转 int 保持线格式无损。
  const numericKeys = <String>['genres', 'decade'];
  for (final key in numericKeys) {
    final values = selection[key];
    if (values != null && values.isNotEmpty) {
      final first = values.first;
      tags[key] = int.tryParse(first) ?? first;
    }
  }
  const passthroughKeys = <String>[
    'locate',
    'resolution',
    'color_range',
    'audio_type',
    'recognition_status',
    'watched',
  ];
  for (final key in passthroughKeys) {
    final values = selection[key];
    if (values != null && values.isNotEmpty) {
      tags[key] = values.first;
    }
  }

  return ItemListRequest(
    ancestorGuid: query.catalogId,
    page: query.page,
    pageSize: query.pageSize,
    sortColumn: query.sortField,
    sortType: query.sortType,
    typeTags: typeTags,
    tags: tags.isEmpty ? null : tags,
  );
}
