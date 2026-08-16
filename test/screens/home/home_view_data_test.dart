import 'package:fly_player/media_backend/media_image_request.dart';
import 'package:fly_player/models/media_item.dart';
import 'package:fly_player/models/media_library_item.dart';
import 'package:fly_player/screens/home/home_view_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalog = MediaItem(id: 'catalog', name: '媒体库');
  final preview = MediaLibraryItem.fromJson(const <String, dynamic>{
    'guid': 'preview',
    'title': '预览',
  });
  final resume = MediaLibraryItem.fromJson(const <String, dynamic>{
    'guid': 'resume',
    'title': '续看',
  });
  final nextUp = MediaLibraryItem.fromJson(const <String, dynamic>{
    'guid': 'next',
    'title': '下一集',
  });
  final latest = MediaLibraryItem.fromJson(const <String, dynamic>{
    'guid': 'latest',
    'title': '最近添加',
  });
  const image = MediaImageRequest(urls: <String>['https://image']);

  HomeViewData populated() => HomeViewData(
    catalogs: <MediaItem>[catalog],
    catalogPreviewItems: <String, List<MediaLibraryItem>>{
      catalog.id: <MediaLibraryItem>[preview],
    },
    continueWatching: <MediaLibraryItem>[resume],
    nextUp: <MediaLibraryItem>[nextUp],
    latest: <MediaLibraryItem>[latest],
    summary: const <String, dynamic>{'movie': 1},
    catalogImageRequests: const <String, List<MediaImageRequest>>{
      'catalog': <MediaImageRequest>[image],
    },
    itemImageRequests: const <String, MediaImageRequest>{'resume': image},
    backdropImageRequests: const <String, MediaImageRequest>{'resume': image},
  );

  test('const empty 提供全部空区块', () {
    const empty = HomeViewData.empty();

    expect(empty.catalogs, isEmpty);
    expect(empty.catalogPreviewItems, isEmpty);
    expect(empty.continueWatching, isEmpty);
    expect(empty.nextUp, isEmpty);
    expect(empty.latest, isEmpty);
    expect(empty.summary, isEmpty);
    expect(empty.catalogImageRequests, isEmpty);
    expect(empty.itemImageRequests, isEmpty);
    expect(empty.backdropImageRequests, isEmpty);
  });

  test('copyWith 只替换概要并保留所有非空区块', () {
    final original = populated();

    final updated = original.copyWith(
      summary: const <String, dynamic>{'movie': 12},
    );

    expect(updated.summary, const <String, dynamic>{'movie': 12});
    expect(updated.catalogs, <MediaItem>[catalog]);
    expect(updated.catalogPreviewItems[catalog.id], <MediaLibraryItem>[
      preview,
    ]);
    expect(updated.continueWatching, <MediaLibraryItem>[resume]);
    expect(updated.nextUp, <MediaLibraryItem>[nextUp]);
    expect(updated.latest, <MediaLibraryItem>[latest]);
    expect(updated.catalogImageRequests['catalog'], <MediaImageRequest>[image]);
    expect(updated.itemImageRequests, const <String, MediaImageRequest>{
      'resume': image,
    });
    expect(updated.backdropImageRequests, const <String, MediaImageRequest>{
      'resume': image,
    });
  });

  test('copyWith 后修改新快照集合不会篡改旧快照', () {
    final original = populated();
    final updated = original.copyWith(
      summary: const <String, dynamic>{'movie': 2},
    );

    updated.itemImageRequests['new'] = image;
    updated.catalogPreviewItems[catalog.id]!.add(resume);

    expect(original.itemImageRequests, isNot(contains('new')));
    expect(original.catalogPreviewItems[catalog.id], <MediaLibraryItem>[
      preview,
    ]);
  });

  test('可选区块失败保留旧值，成功空值会清空', () {
    final oldItems = <MediaLibraryItem>[resume];

    const failed = HomeSectionLoadResult<List<MediaLibraryItem>>.failure();
    const succeededEmpty =
        HomeSectionLoadResult<List<MediaLibraryItem>>.success(
          <MediaLibraryItem>[],
        );

    expect(failed.valueOr(oldItems), same(oldItems));
    expect(succeededEmpty.valueOr(oldItems), isEmpty);
  });

  test('首页加载代次只允许最后启动的请求落地', () {
    final generation = HomeLoadGeneration();

    final first = generation.begin();
    final second = generation.begin();

    expect(generation.isCurrent(first), isFalse);
    expect(generation.isCurrent(second), isTrue);
    generation.invalidate();
    expect(generation.isCurrent(second), isFalse);
  });
}
