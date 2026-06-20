import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/filter/media_catalog_filter.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';

void main() {
  test('MediaFilterOption 默认 label 为空（需 UI 本地化的维度）', () {
    const raw = MediaFilterOption(value: '12');
    expect(raw.value, '12');
    expect(raw.label, '');

    const filled = MediaFilterOption(value: 'HDR', label: 'HDR');
    expect(filled.label, 'HDR');
  });

  test('MediaFilterDimension 默认单选、空选项', () {
    const dim = MediaFilterDimension(
      key: 'genres',
      kind: MediaFilterDimensionKind.genre,
    );
    expect(dim.key, 'genres');
    expect(dim.kind, MediaFilterDimensionKind.genre);
    expect(dim.options, isEmpty);
    expect(dim.multiSelect, isFalse);
  });

  test('MediaCatalogFilterSchema 携带 genre/region 字典', () {
    const schema = MediaCatalogFilterSchema(
      dimensions: [
        MediaFilterDimension(
          key: 'genres',
          kind: MediaFilterDimensionKind.genre,
          options: [MediaFilterOption(value: '28')],
        ),
      ],
      sortOptions: [MediaSortOption(field: 'release_date')],
      genreNames: {'28': '动作'},
      regionNames: {'US': '美国'},
    );

    expect(schema.dimensions.single.key, 'genres');
    expect(schema.sortOptions.single.field, 'release_date');
    expect(schema.genreNames['28'], '动作');
    expect(schema.regionNames['US'], '美国');
  });

  test('MediaCatalogQuery 默认值与 copyWith', () {
    const query = MediaCatalogQuery(catalogId: 'cat-1');
    expect(query.sortField, 'create_time');
    expect(query.sortType, 'DESC');
    expect(query.page, 1);
    expect(query.pageSize, 50);
    expect(query.selection, isEmpty);

    final next = query.copyWith(
      selection: {
        'genres': ['28'],
      },
      sortField: 'release_date',
      page: 2,
    );
    expect(next.catalogId, 'cat-1');
    expect(next.selection['genres'], ['28']);
    expect(next.sortField, 'release_date');
    expect(next.sortType, 'DESC');
    expect(next.page, 2);
  });

  test('MediaItemCardPage 复用 MediaItemCard 承载分页结果', () {
    const page = MediaItemCardPage(
      items: [
        MediaItemCard(
          id: 'a',
          title: 't',
          type: 'Movie',
          primaryImage: MediaImageRef.empty,
        ),
      ],
      total: 100,
    );
    expect(page.items.single.id, 'a');
    expect(page.total, 100);
  });
}
