import '../media_item_card.dart';

/// 筛选维度的语义类型，决定 UI 如何把选项 [MediaFilterOption.value] 本地化成显示名。
///
/// 双轨 label 机制的桥梁：`plain` 维度的 label 由适配层直接填好；其余维度适配层只给
/// raw `value`，由 UI 层按 kind（必要时配合 [MediaCatalogFilterSchema.genreNames] /
/// [MediaCatalogFilterSchema.regionNames] 与 app 文案）本地化。新后端（Emby 等）可统一用
/// `plain` 直接给显示名，无需 UI 维护各 kind 的本地化逻辑。
enum MediaFilterDimensionKind {
  /// label 已可直接显示（适配层填好）。
  plain,
  genre,
  region,
  decade,
  resolution,
  audioType,
  colorRange,
  recognitionStatus,
  watched,
  mediaType,
  favorite,
  seriesStatus,
}

/// 一个筛选维度下的可选值。
class MediaFilterOption {
  /// 提交给后端的原始值（统一字符串；genre id、ISO code、'1080p'、枚举 token 等）。
  final String value;

  /// 显示名。`plain` 维度由适配层填好；需 UI 本地化的维度可留空，由 UI localizer 据
  /// 所属维度的 kind + value 计算。
  final String label;

  const MediaFilterOption({required this.value, this.label = ''});
}

/// 一个筛选维度（类型 / genre / 地区 / 年代 / 清晰度 / ...）。
class MediaFilterDimension {
  /// 提交查询时的标签键（例如 `genres` / `locate` / `type`）。
  final String key;

  /// 维度语义类型，决定本地化方式。
  final MediaFilterDimensionKind kind;

  final List<MediaFilterOption> options;

  /// 是否允许多选；飞牛当前各维度单选，预留多选能力。
  final bool multiSelect;

  const MediaFilterDimension({
    required this.key,
    required this.kind,
    this.options = const <MediaFilterOption>[],
    this.multiSelect = false,
  });
}

/// 一个可用排序字段。显示名走 UI 层 l10n（后端字段名各异，不下发文案）。
class MediaSortOption {
  final String field;

  const MediaSortOption({required this.field});
}

/// 某个媒体库的可筛选 / 可排序 schema。
///
/// [genreNames] / [regionNames] 是后端提供的**数据字典**（非 app l10n），供 UI localizer
/// 把 genre id / 地区 code 还原成显示名。其它后端不需要时留空。
class MediaCatalogFilterSchema {
  final List<MediaFilterDimension> dimensions;
  final List<MediaSortOption> sortOptions;
  final Map<String, String> genreNames;
  final Map<String, String> regionNames;

  const MediaCatalogFilterSchema({
    this.dimensions = const <MediaFilterDimension>[],
    this.sortOptions = const <MediaSortOption>[],
    this.genreNames = const <String, String>{},
    this.regionNames = const <String, String>{},
  });
}

/// 一次分类查询的选择条件。
class MediaCatalogQuery {
  final String catalogId;

  /// 维度 key → 选中的 value 列表（空列表表示该维度不限）。
  final Map<String, List<String>> selection;

  final String sortField;

  /// 排序方向，`ASC` 或 `DESC`。
  final String sortType;

  final int page;
  final int pageSize;

  const MediaCatalogQuery({
    required this.catalogId,
    this.selection = const <String, List<String>>{},
    this.sortField = 'create_time',
    this.sortType = 'DESC',
    this.page = 1,
    this.pageSize = 50,
  });

  MediaCatalogQuery copyWith({
    String? catalogId,
    Map<String, List<String>>? selection,
    String? sortField,
    String? sortType,
    int? page,
    int? pageSize,
  }) {
    return MediaCatalogQuery(
      catalogId: catalogId ?? this.catalogId,
      selection: selection ?? this.selection,
      sortField: sortField ?? this.sortField,
      sortType: sortType ?? this.sortType,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}

/// 分类查询的分页结果。
class MediaItemCardPage {
  final List<MediaItemCard> items;
  final int total;

  const MediaItemCardPage({
    this.items = const <MediaItemCard>[],
    this.total = 0,
  });
}
