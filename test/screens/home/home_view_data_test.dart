import 'dart:async';

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

  test('首页可选区块合并时失败保留旧值与图片，成功空值清空', () {
    final current = populated().copyWith(
      itemImageRequests: const <String, MediaImageRequest>{
        'resume': image,
        'next': image,
        'latest': image,
      },
      backdropImageRequests: const <String, MediaImageRequest>{
        'resume': image,
        'next': image,
        'latest': image,
      },
    );
    const refreshedBase = HomeViewData(summary: <String, dynamic>{'movie': 2});

    final merged = mergeHomeOptionalSections(
      current: current,
      refreshedBase: refreshedBase,
      continueWatching:
          const HomeSectionLoadResult<HomeMediaSectionData>.failure(),
      nextUp: const HomeSectionLoadResult<HomeMediaSectionData>.failure(),
      latest: const HomeSectionLoadResult<HomeMediaSectionData>.success(
        HomeMediaSectionData(),
      ),
    );

    expect(merged.continueWatching, <MediaLibraryItem>[resume]);
    expect(merged.nextUp, <MediaLibraryItem>[nextUp]);
    expect(merged.latest, isEmpty);
    expect(
      merged.itemImageRequests.keys,
      containsAll(<String>['resume', 'next']),
    );
    expect(merged.itemImageRequests, isNot(contains('latest')));
    expect(
      merged.backdropImageRequests.keys,
      containsAll(<String>['resume', 'next']),
    );
    expect(merged.backdropImageRequests, isNot(contains('latest')));
  });

  test('首页可选区块成功时替换旧条目及对应图片', () {
    final current = populated();
    const replacementImage = MediaImageRequest(
      urls: <String>['https://replacement'],
    );

    final merged = mergeHomeOptionalSections(
      current: current,
      refreshedBase: const HomeViewData.empty(),
      continueWatching: HomeSectionLoadResult<HomeMediaSectionData>.success(
        HomeMediaSectionData(
          items: <MediaLibraryItem>[preview],
          imageRequests: const <String, MediaImageRequest>{
            'preview': replacementImage,
          },
          backdropImageRequests: const <String, MediaImageRequest>{
            'preview': replacementImage,
          },
        ),
      ),
      nextUp: const HomeSectionLoadResult<HomeMediaSectionData>.failure(),
      latest: const HomeSectionLoadResult<HomeMediaSectionData>.failure(),
    );

    expect(merged.continueWatching, <MediaLibraryItem>[preview]);
    expect(merged.itemImageRequests['preview'], same(replacementImage));
    expect(merged.backdropImageRequests['preview'], same(replacementImage));
    expect(merged.itemImageRequests, isNot(contains('resume')));
  });

  test('缓存写入串行执行，旧代已运行时新代最终落盘', () async {
    final coordinator = HomeCacheWriteCoordinator();
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final writes = <String>[];

    final first = coordinator.schedule(
      generation: 1,
      write: () async {
        writes.add('gen1-start');
        firstStarted.complete();
        await releaseFirst.future;
        writes.add('gen1-end');
      },
    );
    await firstStarted.future;
    final second = coordinator.schedule(
      generation: 2,
      write: () async => writes.add('gen2'),
    );

    releaseFirst.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(writes, <String>['gen1-start', 'gen1-end', 'gen2']);
    expect(writes.last, 'gen2');
  });

  test('缓存写入真正开始前若已过期则跳过', () async {
    final coordinator = HomeCacheWriteCoordinator();
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var staleWriteRan = false;

    final first = coordinator.schedule(
      generation: 1,
      write: () async {
        firstStarted.complete();
        await releaseFirst.future;
      },
    );
    await firstStarted.future;
    final stale = coordinator.schedule(
      generation: 2,
      write: () async => staleWriteRan = true,
    );
    coordinator.advanceTo(3);

    releaseFirst.complete();
    await first;
    expect(await stale, isFalse);
    expect(staleWriteRan, isFalse);
  });
}
