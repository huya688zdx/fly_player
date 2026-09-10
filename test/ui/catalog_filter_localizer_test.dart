import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/l10n/generated/app_localizations_zh.dart';
import 'package:fly_player/media_backend/filter/media_catalog_filter.dart';
import 'package:fly_player/ui/catalog_filter_localizer.dart';

void main() {
  final AppLocalizations l10n = AppLocalizationsZh();
  const schema = MediaCatalogFilterSchema(
    genreNames: <String, String>{'28': '动作', '12': '冒险'},
    regionNames: <String, String>{'US': '美国', 'JP': '日本'},
  );
  final localizer = CatalogFilterLocalizer(l10n: l10n, schema: schema);

  String optionLabel(
    MediaFilterDimensionKind kind,
    String value, {
    String label = '',
  }) {
    return localizer.optionLabel(
      MediaFilterDimension(key: 'k', kind: kind, options: const []),
      MediaFilterOption(value: value, label: label),
    );
  }

  test('plain 维度有 label 用 label，否则回退 value', () {
    expect(
      optionLabel(MediaFilterDimensionKind.plain, 'HDR', label: 'HDR 色域'),
      'HDR 色域',
    );
    expect(optionLabel(MediaFilterDimensionKind.plain, 'HDR'), 'HDR');
  });

  test('genre 优先 schema.genreNames 否则回退 value', () {
    expect(optionLabel(MediaFilterDimensionKind.genre, '28'), '动作');
    expect(optionLabel(MediaFilterDimensionKind.genre, '999'), '999');
  });

  test('region 优先 schema.regionNames（大小写不敏感）否则回退 value', () {
    expect(optionLabel(MediaFilterDimensionKind.region, 'US'), '美国');
    expect(optionLabel(MediaFilterDimensionKind.region, 'jp'), '日本');
    expect(optionLabel(MediaFilterDimensionKind.region, 'XX'), 'XX');
  });

  test('decade 复刻分类页：Recent 走 l10n，其余原样', () {
    expect(
      optionLabel(MediaFilterDimensionKind.decade, 'Recent'),
      l10n.listFilterDecadeRecent,
    );
    expect(optionLabel(MediaFilterDimensionKind.decade, '2010'), '2010');
  });

  test('resolution 去掉尾部 p，Others 本地化，其余原样', () {
    expect(optionLabel(MediaFilterDimensionKind.resolution, '1080p'), '1080');
    expect(optionLabel(MediaFilterDimensionKind.resolution, '2160p'), '2160');
    expect(
      optionLabel(MediaFilterDimensionKind.resolution, 'Others'),
      l10n.commonOther,
    );
    expect(optionLabel(MediaFilterDimensionKind.resolution, '4K'), '4K');
  });

  test('audioType 本地化已知规格，其余原样', () {
    expect(
      optionLabel(MediaFilterDimensionKind.audioType, 'DolbySurround'),
      l10n.audioSpecDolbySurround,
    );
    expect(
      optionLabel(MediaFilterDimensionKind.audioType, 'DolbyAtmos'),
      l10n.audioSpecDolbyAtmos,
    );
    expect(
      optionLabel(MediaFilterDimensionKind.audioType, 'DTS'),
      l10n.audioSpecDts,
    );
    expect(
      optionLabel(MediaFilterDimensionKind.audioType, 'Stereo'),
      l10n.audioSpecStereo,
    );
    expect(
      optionLabel(MediaFilterDimensionKind.audioType, 'Others'),
      l10n.commonOther,
    );
    expect(optionLabel(MediaFilterDimensionKind.audioType, 'Foo'), 'Foo');
  });

  test('colorRange 直接展示原始 value', () {
    expect(optionLabel(MediaFilterDimensionKind.colorRange, 'HDR'), 'HDR');
    expect(optionLabel(MediaFilterDimensionKind.colorRange, 'SDR'), 'SDR');
  });

  test('recognitionStatus 复刻分类页 1/2/3 文案，其余原样', () {
    expect(
      optionLabel(MediaFilterDimensionKind.recognitionStatus, '1'),
      l10n.listRecognitionUnmatched,
    );
    expect(
      optionLabel(MediaFilterDimensionKind.recognitionStatus, '2'),
      l10n.listRecognitionMatched,
    );
    expect(
      optionLabel(MediaFilterDimensionKind.recognitionStatus, '3'),
      l10n.listRecognitionNfo,
    );
    expect(optionLabel(MediaFilterDimensionKind.recognitionStatus, '9'), '9');
  });

  test('watched 复刻分类页 1/0 文案', () {
    expect(
      optionLabel(MediaFilterDimensionKind.watched, '1'),
      l10n.listWatched,
    );
    expect(
      optionLabel(MediaFilterDimensionKind.watched, '0'),
      l10n.listUnwatched,
    );
  });

  test('mediaType 复刻分类页类型文案，其余原样', () {
    expect(
      optionLabel(MediaFilterDimensionKind.mediaType, 'Movie'),
      l10n.listTypeMovie,
    );
    expect(
      optionLabel(MediaFilterDimensionKind.mediaType, 'TV'),
      l10n.listTypeTv,
    );
    expect(
      optionLabel(MediaFilterDimensionKind.mediaType, 'Directory'),
      l10n.resourceTypeDirectory,
    );
    expect(
      optionLabel(MediaFilterDimensionKind.mediaType, 'Video'),
      l10n.resourceTypeVideo,
    );
    expect(optionLabel(MediaFilterDimensionKind.mediaType, 'Other'), 'Other');
  });

  test('sortLabel 复刻分类页排序字段文案，未知回退 createTime', () {
    expect(localizer.sortLabel('create_time'), l10n.listSortCreateTime);
    expect(localizer.sortLabel('release_date'), l10n.listSortReleaseDate);
    expect(localizer.sortLabel('title'), l10n.listSortTitleField);
    expect(localizer.sortLabel('vote_average'), l10n.listSortVoteAverage);
    expect(localizer.sortLabel('unknown'), l10n.listSortCreateTime);
  });

  test('dimensionTitle 复刻分类页维度分组标题', () {
    String title(MediaFilterDimensionKind kind) =>
        localizer.dimensionTitle(MediaFilterDimension(key: 'k', kind: kind));
    expect(title(MediaFilterDimensionKind.mediaType), l10n.listFilterType);
    expect(title(MediaFilterDimensionKind.genre), l10n.listFilterGenres);
    expect(title(MediaFilterDimensionKind.region), l10n.listFilterLocate);
    expect(title(MediaFilterDimensionKind.decade), l10n.listFilterDecade);
    expect(
      title(MediaFilterDimensionKind.resolution),
      l10n.listFilterResolution,
    );
    expect(
      title(MediaFilterDimensionKind.colorRange),
      l10n.listFilterColorRange,
    );
    expect(title(MediaFilterDimensionKind.audioType), l10n.listFilterAudioType);
    expect(
      title(MediaFilterDimensionKind.recognitionStatus),
      l10n.listFilterRecognitionStatus,
    );
    expect(title(MediaFilterDimensionKind.watched), l10n.listFilterWatched);
  });
}
