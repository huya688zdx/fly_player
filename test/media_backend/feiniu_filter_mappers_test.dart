import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_media_mappers.dart';
import 'package:fly_player/media_backend/filter/media_catalog_filter.dart';

void main() {
  group('mapFeiniuFilterSchema', () {
    final schema = mapFeiniuFilterSchema(
      tagOptions: <String, List<dynamic>>{
        'genres': <dynamic>[28, 12],
        'locate': <dynamic>['US'],
        'decades': <dynamic>[2020],
        'resolutions': <dynamic>['1080p'],
        'color_range': <dynamic>['SDR'],
        'audio_type': <dynamic>['DTS'],
        'recognition_status': <dynamic>[1, 0],
      },
      genresMap: <int, String>{28: '动作', 12: '冒险'},
      regionNames: <String, String>{'US': '美国'},
    );

    test('维度顺序与提交键名固定', () {
      expect(schema.dimensions.map((d) => d.key).toList(), <String>[
        'type',
        'genres',
        'locate',
        'decade',
        'resolution',
        'color_range',
        'audio_type',
        'recognition_status',
        'watched',
      ]);
    });

    test('type / watched 维度为固定选项', () {
      final type = schema.dimensions.firstWhere((d) => d.key == 'type');
      expect(type.kind, MediaFilterDimensionKind.mediaType);
      expect(type.options.map((o) => o.value).toList(), <String>[
        'Movie',
        'TV',
      ]);

      final watched = schema.dimensions.firstWhere((d) => d.key == 'watched');
      expect(watched.kind, MediaFilterDimensionKind.watched);
      expect(watched.options.map((o) => o.value).toList(), <String>['1', '0']);
    });

    test('年代 / 清晰度 options 取自复数源键', () {
      final decade = schema.dimensions.firstWhere((d) => d.key == 'decade');
      expect(decade.kind, MediaFilterDimensionKind.decade);
      expect(decade.options.single.value, '2020');

      final resolution = schema.dimensions.firstWhere(
        (d) => d.key == 'resolution',
      );
      expect(resolution.options.single.value, '1080p');
    });

    test('genre options 字符串化且 label 留空', () {
      final genres = schema.dimensions.firstWhere((d) => d.key == 'genres');
      expect(genres.kind, MediaFilterDimensionKind.genre);
      expect(genres.options.map((o) => o.value).toList(), <String>['28', '12']);
      expect(genres.options.every((o) => o.label.isEmpty), isTrue);
    });

    test('数据字典随 schema 下发', () {
      expect(schema.genreNames['28'], '动作');
      expect(schema.genreNames['12'], '冒险');
      expect(schema.regionNames['US'], '美国');
    });

    test('排序字段与原生分类页一致', () {
      expect(schema.sortOptions.map((s) => s.field).toList(), <String>[
        'create_time',
        'release_date',
        'title',
        'vote_average',
      ]);
    });

    test('源键缺失时维度 options 为空', () {
      final empty = mapFeiniuFilterSchema(
        tagOptions: const <String, List<dynamic>>{},
        genresMap: const <int, String>{},
        regionNames: const <String, String>{},
      );
      expect(
        empty.dimensions.firstWhere((d) => d.key == 'genres').options,
        isEmpty,
      );
      // 固定维度仍存在。
      expect(
        empty.dimensions.firstWhere((d) => d.key == 'type').options.length,
        2,
      );
    });
  });

  group('mapMediaQueryToItemListRequest', () {
    test('空选择回退到全类型且不带额外标签', () {
      final request = mapMediaQueryToItemListRequest(
        const MediaCatalogQuery(catalogId: 'cat-1'),
      );
      expect(request.ancestorGuid, 'cat-1');
      expect(request.typeTags, <String>['Movie', 'TV', 'Directory', 'Video']);
      expect(request.tags, isNull);

      final payload = request.toJson();
      expect((payload['tags'] as Map)['type'], <String>[
        'Movie',
        'TV',
        'Directory',
        'Video',
      ]);
    });

    test('genres 回填为 int', () {
      final request = mapMediaQueryToItemListRequest(
        const MediaCatalogQuery(
          catalogId: 'c',
          selection: {
            'genres': ['28'],
          },
        ),
      );
      expect(request.tags!['genres'], 28);
      expect(request.tags!['genres'], isA<int>());
    });

    test('recognition_status / watched 保持字符串', () {
      final request = mapMediaQueryToItemListRequest(
        const MediaCatalogQuery(
          catalogId: 'c',
          selection: {
            'recognition_status': ['2'],
            'watched': ['1'],
          },
        ),
      );
      expect(request.tags!['recognition_status'], '2');
      expect(request.tags!['recognition_status'], isA<String>());
      expect(request.tags!['watched'], '1');
      expect(request.tags!['watched'], isA<String>());
    });

    test('type 选择进入 typeTags 而非重复标签', () {
      final request = mapMediaQueryToItemListRequest(
        const MediaCatalogQuery(
          catalogId: 'c',
          selection: {
            'type': ['Movie'],
          },
        ),
      );
      expect(request.typeTags, <String>['Movie']);
      expect(request.tags, isNull);
      expect((request.toJson()['tags'] as Map)['type'], <String>['Movie']);
    });

    test('排序与分页透传', () {
      final request = mapMediaQueryToItemListRequest(
        const MediaCatalogQuery(
          catalogId: 'c',
          sortField: 'release_date',
          sortType: 'ASC',
          page: 3,
          pageSize: 20,
        ),
      );
      expect(request.sortColumn, 'release_date');
      expect(request.sortType, 'ASC');
      expect(request.page, 3);
      expect(request.pageSize, 20);
    });
  });
}
