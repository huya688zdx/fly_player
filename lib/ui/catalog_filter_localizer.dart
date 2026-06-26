import '../l10n/generated/app_localizations.dart';
import '../media_backend/filter/media_catalog_filter.dart';

/// 分类页筛选 / 排序文案的 UI 本地化器。
///
/// 双轨 label 机制的 UI 侧：backend 只下发结构（[MediaFilterDimensionKind]）和数据字典
/// （[MediaCatalogFilterSchema.genreNames] / [MediaCatalogFilterSchema.regionNames]），
/// 本类按维度 kind + 选项 [MediaFilterOption.value] 合成显示文案，逐项复刻
/// `category_items_screen` 既有 labeler 语义，保证飞牛分类页迁移到 schema 驱动后
/// 显示文案不变。新后端（Emby 等）若直接在适配层填好 [MediaFilterOption.label]，
/// 用 `plain` 维度即可，无需在此扩展 kind 分支。
class CatalogFilterLocalizer {
  final AppLocalizations l10n;
  final MediaCatalogFilterSchema schema;

  const CatalogFilterLocalizer({required this.l10n, required this.schema});

  /// 单个筛选选项的显示文案。
  String optionLabel(MediaFilterDimension dimension, MediaFilterOption option) {
    final value = option.value;
    switch (dimension.kind) {
      case MediaFilterDimensionKind.plain:
        return option.label.isNotEmpty ? option.label : value;
      case MediaFilterDimensionKind.genre:
        return schema.genreNames[value] ?? value;
      case MediaFilterDimensionKind.region:
        // 分类页按大写 ISO code 查表，回退保留原始 value。
        return schema.regionNames[value] ??
            schema.regionNames[value.toUpperCase()] ??
            value;
      case MediaFilterDimensionKind.decade:
        return value == 'Recent' ? l10n.listFilterDecadeRecent : value;
      case MediaFilterDimensionKind.resolution:
        return _resolutionLabel(value);
      case MediaFilterDimensionKind.audioType:
        return _audioLabel(value);
      case MediaFilterDimensionKind.colorRange:
        return value;
      case MediaFilterDimensionKind.recognitionStatus:
        return _recognitionStatusLabel(value);
      case MediaFilterDimensionKind.watched:
        return _watchedLabel(value);
      case MediaFilterDimensionKind.mediaType:
        return _typeLabel(value);
      case MediaFilterDimensionKind.favorite:
        return l10n.listFilterFavoriteOnly;
      case MediaFilterDimensionKind.seriesStatus:
        return _seriesStatusLabel(value);
    }
  }

  /// 筛选面板里维度分组的标题。
  String dimensionTitle(MediaFilterDimension dimension) {
    switch (dimension.kind) {
      case MediaFilterDimensionKind.mediaType:
        return l10n.listFilterType;
      case MediaFilterDimensionKind.genre:
        return l10n.listFilterGenres;
      case MediaFilterDimensionKind.region:
        return l10n.listFilterLocate;
      case MediaFilterDimensionKind.decade:
        return l10n.listFilterDecade;
      case MediaFilterDimensionKind.resolution:
        return l10n.listFilterResolution;
      case MediaFilterDimensionKind.colorRange:
        return l10n.listFilterColorRange;
      case MediaFilterDimensionKind.audioType:
        return l10n.listFilterAudioType;
      case MediaFilterDimensionKind.recognitionStatus:
        return l10n.listFilterRecognitionStatus;
      case MediaFilterDimensionKind.watched:
        return l10n.listFilterWatched;
      case MediaFilterDimensionKind.favorite:
        return l10n.listFilterFavorite;
      case MediaFilterDimensionKind.seriesStatus:
        return l10n.listFilterSeriesStatus;
      case MediaFilterDimensionKind.plain:
        return dimension.key;
    }
  }

  /// 排序字段的显示文案；未知字段回退“按添加时间”（与分类页一致）。
  String sortLabel(String field) {
    switch (field) {
      case 'release_date':
        return l10n.listSortReleaseDate;
      case 'title':
        return l10n.listSortTitleField;
      case 'vote_average':
        return l10n.listSortVoteAverage;
      case 'create_time':
      default:
        return l10n.listSortCreateTime;
    }
  }

  String _resolutionLabel(String value) {
    final text = value.trim();
    final match = RegExp(
      r'^(\d{3,4})p$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) return match.group(1) ?? text;
    if (text == 'Others') return l10n.commonOther;
    return text;
  }

  String _audioLabel(String value) {
    switch (value) {
      case 'DolbySurround':
        return l10n.audioSpecDolbySurround;
      case 'DolbyAtmos':
        return l10n.audioSpecDolbyAtmos;
      case 'DTS':
        return l10n.audioSpecDts;
      case 'Stereo':
        return l10n.audioSpecStereo;
      case 'Others':
        return l10n.commonOther;
      default:
        return value;
    }
  }

  String _recognitionStatusLabel(String value) {
    switch (int.tryParse(value) ?? 0) {
      case 1:
        return l10n.listRecognitionUnmatched;
      case 2:
        return l10n.listRecognitionMatched;
      case 3:
        return l10n.listRecognitionNfo;
      default:
        return value;
    }
  }

  String _watchedLabel(String value) {
    switch (int.tryParse(value) ?? -1) {
      case 1:
        return l10n.listWatched;
      case 0:
        return l10n.listUnwatched;
      default:
        return value;
    }
  }

  String _seriesStatusLabel(String value) {
    switch (value) {
      case 'Continuing':
        return l10n.seriesStatusContinuing;
      case 'Ended':
        return l10n.seriesStatusEnded;
      default:
        return value;
    }
  }

  String _typeLabel(String value) {
    switch (value) {
      case 'Movie':
        return l10n.listTypeMovie;
      case 'TV':
        return l10n.listTypeTv;
      case 'Directory':
        return l10n.resourceTypeDirectory;
      case 'Video':
        return l10n.resourceTypeVideo;
      default:
        return value;
    }
  }
}
